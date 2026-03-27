#include <stdlib.h>
#include <string.h>

#include <sys/errno.h>

#include <esp_event.h>
#include <esp_log.h>
#include <esp_system.h>
#include <esp_timer.h>
#include <esp_wifi.h>
#include <freertos/FreeRTOS.h>
#include <freertos/event_groups.h>
#include <freertos/task.h>
#include <nvs_flash.h>
#include <esp_netif.h>

#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/wifi.h>

#if CONFIG_BORNEO_PROV_METHOD_NP
#include "np.h"
#elif CONFIG_BORNEO_PROV_METHOD_SC
#include "sc.h"
#endif

#define SSID_MAX_LEN 32
#define SHORT_SHUTDOWN_PERIOD 30
#define NVS_NS "borneo.wifi"
#define NVS_COUNT_KEY "shutdown-count"
#define TAG "wifi"
#define WIFI_RECONNECT_INTERVAL_MS 15000

static int bo_wifi_start();
static int _update_nvs_early(int32_t* shutdown_count);
static int _update_nvs_reset();
static void _timer_callback(void* args);
static void _wifi_reconnect_callback(void* arg);
static int _attempt_wifi_reconnect();
static void _shutdown_timer_cleanup(); // Forward declaration for shutdown timer cleanup helper

static esp_timer_handle_t _wifi_reconnect_timer = NULL;
static esp_timer_handle_t _shutdown_checking_timer = NULL;
static esp_timer_handle_t _forget_timer = NULL;
static bool _has_ssid();
static bool s_auto_reconnect = false;

static void _forget_timer_callback(void* arg);
static void wifi_events_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data);
static void system_events_handler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data);
static void bo_wifi_events_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data);
static void wifi_on_disconnected(void* event_data);

typedef enum {
    WIFI_STATE_DISCONNECTED = 0,
    WIFI_STATE_CONNECTING,
    WIFI_STATE_PROVISIONING,
    WIFI_STATE_CONNECTED,
} bo_wifi_state_t;

static bo_wifi_state_t s_wifi_state = WIFI_STATE_DISCONNECTED;
static portMUX_TYPE s_status_lock = portMUX_INITIALIZER_UNLOCKED;

ESP_EVENT_DEFINE_BASE(BO_WIFI_EVENTS);

int bo_wifi_init()
{
    ESP_LOGI(TAG, "Initializing Borneo WiFi sub-system...");
    esp_netif_t* sta_netif = esp_netif_create_default_wifi_sta();
    if (sta_netif == NULL) {
        return -1;
    }

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    BO_TRY(esp_wifi_init(&cfg));
    BO_TRY(esp_wifi_set_mode(WIFI_MODE_STA));
    BO_TRY(esp_wifi_set_ps(WIFI_PS_NONE));
    BO_TRY(esp_event_handler_register(BO_WIFI_EVENTS, ESP_EVENT_ANY_ID, &bo_wifi_events_handler,
                                      NULL)); // 添加BO_WIFI_EVENTS注册
    BO_TRY(esp_event_handler_register(BO_SYSTEM_EVENTS, ESP_EVENT_ANY_ID, &system_events_handler, NULL));

    return bo_wifi_start();
}

int bo_wifi_start()
{
    BO_TRY(esp_wifi_start());

    // Initialize auto-reconnect flag based on whether credentials are already saved
    s_auto_reconnect = _has_ssid();

    // Try to connect the AP
    if (!_has_ssid()) {
        ESP_LOGI(TAG, "There is no saved WiFi configuration.");
        s_wifi_state = WIFI_STATE_PROVISIONING;

#if CONFIG_BORNEO_PROV_METHOD_NP
        BO_TRY(bo_wifi_np_init());
        BO_TRY(bo_wifi_np_start());
#elif CONFIG_BORNEO_PROV_METHOD_SC
        BO_TRY(bo_wifi_sc_init());
        BO_TRY(bo_wifi_sc_start());
#endif
    }
    else {
        s_wifi_state = WIFI_STATE_CONNECTING;
        BO_TRY(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_events_handler, NULL));
        BO_TRY(esp_wifi_connect());

        int32_t shutdown_count = 0;
        BO_TRY(_update_nvs_early(&shutdown_count));

        if (shutdown_count > 3) {
            ESP_LOGI(TAG, "Shutdown counter: %ld", shutdown_count);
            BO_TRY(_update_nvs_reset());
            BO_TRY(bo_wifi_forget());
            vTaskDelay(pdMS_TO_TICKS(1000));
            esp_restart();
        }

        const esp_timer_create_args_t timer_args = {
            .callback = &_timer_callback,
            .name = "settings_sync_timer",
        };

        _shutdown_timer_cleanup();
        BO_TRY(esp_timer_create(&timer_args, &_shutdown_checking_timer));
        BO_TRY(esp_timer_start_once(_shutdown_checking_timer, SHORT_SHUTDOWN_PERIOD * 1000000));
    }

    ESP_LOGI(TAG, "WiFi sub-system has been initialized successfully.");
    return 0;
}

int bo_wifi_forget()
{
    ESP_LOGI(TAG, "Start to restore WiFi config...");

    // Disable auto-reconnect before disconnecting so the disconnect event is ignored
    portENTER_CRITICAL(&s_status_lock);
    s_auto_reconnect = false;
    portEXIT_CRITICAL(&s_status_lock);

    // Trigger a clean disconnect before wiping credentials
    int disconnect_err = esp_wifi_disconnect();
    if (disconnect_err != ESP_OK && disconnect_err != ESP_ERR_WIFI_NOT_CONNECT) {
        ESP_LOGW(TAG, "esp_wifi_disconnect failed: %d", disconnect_err);
    }

    int error = esp_wifi_restore();
    if (error == ESP_ERR_WIFI_NOT_INIT) {
        wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
        error = esp_wifi_init(&cfg);
        if (error != 0) {
            return error;
        }
        BO_TRY(esp_wifi_restore());
    }
    else if (error != 0) {
        return error;
    }

    ESP_LOGI(TAG, "WiFi info has been restored and provisioning started.");
    return 0;
}

static void _forget_timer_callback(void* arg)
{
    if (_forget_timer != NULL) {
        esp_timer_delete(_forget_timer);
        _forget_timer = NULL;
    }

    // Trigger a clean disconnect before wiping credentials
    int disconnect_err = esp_wifi_disconnect();
    if (disconnect_err != ESP_OK && disconnect_err != ESP_ERR_WIFI_NOT_CONNECT) {
        ESP_LOGW(TAG, "esp_wifi_disconnect failed: %d", disconnect_err);
    }

    int error = esp_wifi_restore();
    if (error == ESP_ERR_WIFI_NOT_INIT) {
        wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
        error = esp_wifi_init(&cfg);
        if (error != 0) {
            ESP_LOGE(TAG, "esp_wifi_init failed in forget callback: %d", error);
            return;
        }
        error = esp_wifi_restore();
    }
    if (error != 0) {
        ESP_LOGE(TAG, "esp_wifi_restore failed in forget callback: %d", error);
        return;
    }

    ESP_LOGI(TAG, "WiFi info has been restored and provisioning started (async).");
}

/**
 * @brief Asynchronously forget WiFi credentials after a delay.
 * Returns immediately so the caller (e.g. a CoAP handler) can send its response
 * before the network is torn down.
 * @param delay_ms Milliseconds to wait before executing the forget operation.
 */
int bo_wifi_forget_later(uint32_t delay_ms)
{
    ESP_LOGI(TAG, "Scheduling WiFi forget in %lu ms...", (unsigned long)delay_ms);

    // Immediately disable auto-reconnect so any disconnect events fired before
    // the timer fires are ignored.
    portENTER_CRITICAL(&s_status_lock);
    s_auto_reconnect = false;
    portEXIT_CRITICAL(&s_status_lock);

    // Prevent duplicate timers
    if (_forget_timer != NULL) {
        esp_timer_stop(_forget_timer);
        esp_timer_delete(_forget_timer);
        _forget_timer = NULL;
    }

    const esp_timer_create_args_t timer_args = {
        .callback = &_forget_timer_callback,
        .name = "wifi_forget_timer",
    };
    BO_TRY(esp_timer_create(&timer_args, &_forget_timer));
    BO_TRY(esp_timer_start_once(_forget_timer, (uint64_t)delay_ms * 1000));

    return 0;
}

/**
 * @brief Attempt to reconnect to WiFi. Retries indefinitely via timer until
 *        connected or credentials are cleared / auto-reconnect is disabled.
 * @return 0 if esp_wifi_connect() was called, -1 if reconnect should not proceed.
 */
static int _attempt_wifi_reconnect()
{
    portENTER_CRITICAL(&s_status_lock);
    bool auto_reconnect = s_auto_reconnect;
    portEXIT_CRITICAL(&s_status_lock);

    if (!auto_reconnect) {
        ESP_LOGI(TAG, "Auto-reconnect is disabled, skipping.");
        return -1;
    }

    if (!_has_ssid()) {
        ESP_LOGI(TAG, "No SSID configured, cannot reconnect.");
        return -1;
    }

    ESP_LOGI(TAG, "Attempting to reconnect to WiFi...");
    int rc = esp_wifi_connect();
    if (rc != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initiate WiFi connection. errno=%d. Will retry later...", rc);
        return -1;
    }

    portENTER_CRITICAL(&s_status_lock);
    s_wifi_state = WIFI_STATE_CONNECTING;
    portEXIT_CRITICAL(&s_status_lock);
    return 0;
}

static void wifi_on_disconnected(void* event_data)
{
    portENTER_CRITICAL(&s_status_lock);
    s_wifi_state = WIFI_STATE_DISCONNECTED;
    bool auto_reconnect = s_auto_reconnect;
    portEXIT_CRITICAL(&s_status_lock);
    wifi_event_sta_disconnected_t* event = (wifi_event_sta_disconnected_t*)event_data;
    uint8_t reason = event->reason;

    ESP_LOGW(TAG, "WiFi disconnected. Reason: %d", reason);

    // If auto-reconnect is disabled (e.g. after bo_wifi_forget()), skip reconnection entirely.
    // Provisioning has already been started by the caller.
    if (!auto_reconnect) {
        ESP_LOGI(TAG, "Auto-reconnect is disabled (forget in progress), skipping reconnect.");
        return;
    }

    // Stop shutdown timer once we are disconnected to avoid unnecessary reset callback
    _shutdown_timer_cleanup();

    // Attempt an immediate reconnect first
    _attempt_wifi_reconnect();

    // Schedule a persistent retry timer so we keep trying indefinitely
    if (_wifi_reconnect_timer == NULL) {
        esp_timer_create_args_t timer_args = {
            .callback = &_wifi_reconnect_callback,
            .arg = NULL,
            .name = "wifi_reconnect",
        };
        BO_MUST(esp_timer_create(&timer_args, &_wifi_reconnect_timer));
    }
    if (!esp_timer_is_active(_wifi_reconnect_timer)) {
        BO_MUST(esp_timer_start_once(_wifi_reconnect_timer, WIFI_RECONNECT_INTERVAL_MS * 1000));
    }
}

static void wifi_events_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    switch (event_id) {
    case WIFI_EVENT_SCAN_DONE: {
        ESP_LOGI(TAG, "WiFi scan done.");
    } break;

    case WIFI_EVENT_STA_START: {
        ESP_LOGI(TAG, "WiFi station mode started.");
    } break;

    case WIFI_EVENT_STA_STOP: {
        ESP_LOGI(TAG, "WiFi station mode stopped.");
    } break;

    case WIFI_EVENT_STA_DISCONNECTED: {
        wifi_on_disconnected(event_data);
    } break;

    case WIFI_EVENT_STA_CONNECTED: {
        portENTER_CRITICAL(&s_status_lock);
        s_wifi_state = WIFI_STATE_CONNECTED;
        bool was_reconnect_disabled = !s_auto_reconnect;
        s_auto_reconnect = true;
        portEXIT_CRITICAL(&s_status_lock);
        if (was_reconnect_disabled) {
            ESP_LOGI(TAG, "Auto-reconnect re-enabled after successful connection.");
        }
        if (_wifi_reconnect_timer != NULL) {
            BO_MUST(esp_timer_stop(_wifi_reconnect_timer));
            BO_MUST(esp_timer_delete(_wifi_reconnect_timer));
            _wifi_reconnect_timer = NULL;
        }
        ESP_LOGI(TAG, "WiFi connected successfully.");
    } break;

    case WIFI_EVENT_HOME_CHANNEL_CHANGE:
        break;

    default: {
        ESP_LOGI(TAG, "Unknown WiFi event. event_base=%s, event_id=%ld", event_base, event_id);
    } break;

    } // switch
}

static void bo_wifi_events_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    switch (event_id) {
    case BO_EVENT_WIFI_PROVISIONING_START: {
        ESP_LOGI(TAG, "Provisioning started.");
        esp_event_handler_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_events_handler);
        portENTER_CRITICAL(&s_status_lock);
        s_wifi_state = WIFI_STATE_PROVISIONING;
        portEXIT_CRITICAL(&s_status_lock);
        break;
    }
    case BO_EVENT_WIFI_PROVISIONING_SUCCESS: {
        ESP_LOGI(TAG, "Provisioning successful.");
        BO_MUST(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_events_handler, NULL));
        portENTER_CRITICAL(&s_status_lock);
        s_wifi_state = WIFI_STATE_CONNECTING;
        s_auto_reconnect = true;
        portEXIT_CRITICAL(&s_status_lock);
        if (_has_ssid()) {
            BO_MUST(esp_wifi_connect());
        }
        break;
    }
    case BO_EVENT_WIFI_PROVISIONING_FAIL: {
        ESP_LOGE(TAG, "Provisioning failed.");
        break;
    }
    default:
        break;
    }
}

int bo_wifi_get_rssi(int* rssi)
{
    if (rssi == NULL) {
        return -EINVAL;
    }
    BO_TRY(esp_wifi_sta_get_rssi(rssi));
    return 0;
}

static void _shutdown_timer_cleanup()
{
    if (_shutdown_checking_timer != NULL) {
        esp_timer_stop(_shutdown_checking_timer);
        esp_timer_delete(_shutdown_checking_timer);
        _shutdown_checking_timer = NULL;
    }
}

void _timer_callback(void* args) { _update_nvs_reset(); }

int _update_nvs_early(int32_t* shutdown_count)
{
    nvs_handle_t nvs_handle;
    BO_TRY(nvs_open(NVS_NS, NVS_READWRITE, &nvs_handle));

    int32_t counter = 1;
    int err = nvs_get_i32(nvs_handle, NVS_COUNT_KEY, &counter);
    if (err != ESP_OK && err != ESP_ERR_NVS_NOT_FOUND) {
        goto EXIT_AND_CLOSE;
    }

    if (err == ESP_ERR_NVS_NOT_FOUND) {
        err = nvs_set_i32(nvs_handle, NVS_COUNT_KEY, counter);
        if (err) {
            goto EXIT_AND_CLOSE;
        }
    }
    else {
        // Update booting times
        counter++;
        err = nvs_set_i32(nvs_handle, NVS_COUNT_KEY, counter);
        if (err) {
            goto EXIT_AND_CLOSE;
        }
    }
    *shutdown_count = counter;
    ESP_LOGI(TAG, "Shutdown counter=%ld", counter);

EXIT_AND_CLOSE:
    nvs_close(nvs_handle);
    return err;
}

int _update_nvs_reset()
{
    ESP_LOGI(TAG, "Reset the shutdown counter");

    nvs_handle_t nvs_handle;
    BO_TRY(nvs_open(NVS_NS, NVS_READWRITE, &nvs_handle));

    int32_t shutdown_count = 0;
    int err = nvs_set_i32(nvs_handle, NVS_COUNT_KEY, shutdown_count);
    if (err != ESP_OK) {
        goto EXIT_AND_CLOSE;
    }

EXIT_AND_CLOSE:
    nvs_close(nvs_handle);
    return err;
}

void _wifi_reconnect_callback(void* arg)
{
    ESP_LOGI(TAG, "WiFi reconnect timer fired, retrying connection...");

    portENTER_CRITICAL(&s_status_lock);
    bool auto_reconnect = s_auto_reconnect;
    bo_wifi_state_t state = s_wifi_state;
    portEXIT_CRITICAL(&s_status_lock);

    // Stop retrying if credentials were cleared or provisioning has started
    if (!auto_reconnect || !_has_ssid()) {
        ESP_LOGI(TAG, "Stopping reconnect timer (auto-reconnect disabled or no SSID).");
        if (_wifi_reconnect_timer != NULL) {
            esp_timer_delete(_wifi_reconnect_timer);
            _wifi_reconnect_timer = NULL;
        }
        return;
    }

    // Already connected — timer is no longer needed
    if (state == WIFI_STATE_CONNECTED) {
        if (_wifi_reconnect_timer != NULL) {
            esp_timer_delete(_wifi_reconnect_timer);
            _wifi_reconnect_timer = NULL;
        }
        return;
    }

    // Previous connect attempt still in progress, wait for it to complete
    if (state == WIFI_STATE_CONNECTING) {
        ESP_LOGI(TAG, "Connection already in progress, will check again later.");
        BO_MUST(esp_timer_start_once(_wifi_reconnect_timer, WIFI_RECONNECT_INTERVAL_MS * 1000));
        return;
    }

    _attempt_wifi_reconnect();

    // Reschedule unconditionally — keep retrying until connected or credentials cleared
    BO_MUST(esp_timer_start_once(_wifi_reconnect_timer, WIFI_RECONNECT_INTERVAL_MS * 1000));
}

bool _has_ssid()
{
    wifi_config_t wifi_config = { 0 };
    int rc = esp_wifi_get_config(WIFI_IF_STA, &wifi_config);
    if (rc == ESP_OK) {
        const char* saved_ssid = (const char*)wifi_config.sta.ssid;
        return (strnlen(saved_ssid, MAX_SSID_LEN) > 0);
    }
    else {
        return false;
    }
}

void system_events_handler(void* handler_args, esp_event_base_t base, int32_t event_id, void* event_data)
{
    switch (event_id) {
    case BO_EVENT_REBOOTING: {
        esp_wifi_disconnect();
    } break;

    default:
        break;
    }
}

bool bo_wifi_configurated()
{
    bo_wifi_state_t state;
    portENTER_CRITICAL(&s_status_lock);
    state = s_wifi_state;
    portEXIT_CRITICAL(&s_status_lock);
    return (state == WIFI_STATE_CONNECTED);
}