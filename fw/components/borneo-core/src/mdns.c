#include <stdlib.h>

#include <esp_mac.h>
#include <esp_system.h>
#include <esp_app_desc.h>
#include <esp_event.h>
#include <esp_log.h>
#include <mdns.h>

#include <borneo/common.h>
#include <borneo/mdns.h>
#include <borneo/system.h>

#define TAG "bo-mdns"

static int populate_hostname();
static int add_mdns_services();

#define MDNS_SERVICE_TYPE "_borneo"
#define MDNS_UDP_PORT 5683
#define HOSTNAME_MAX_LEN 70

struct mdns_context {
    char hostname[HOSTNAME_MAX_LEN];
    bool initialized;
};

static struct mdns_context s_mdns_ctx = { 0 };
static portMUX_TYPE s_mdns_lock = portMUX_INITIALIZER_UNLOCKED;

static void mdns_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data);
static int mdns_start();
static void mdns_stop();

int bo_mdns_init()
{
    ESP_LOGI(TAG, "Initializing Borneo MDNS sub-system...");

    // Register event handler for IP_EVENT_STA_GOT_IP and IP_EVENT_STA_LOST_IP
    BO_TRY_ESP(esp_event_handler_register(IP_EVENT, ESP_EVENT_ANY_ID, &mdns_event_handler, NULL));

    ESP_LOGI(TAG, "mDNS sub-system module has been initialized successfully.");

    return 0;
}

static int mdns_start()
{
    portENTER_CRITICAL(&s_mdns_lock);
    bool initialized = s_mdns_ctx.initialized;
    portEXIT_CRITICAL(&s_mdns_lock);

    if (initialized) {
        ESP_LOGW(TAG, "mDNS already started, skipping...");
        return 0;
    }

    ESP_LOGI(TAG, "Starting mDNS...");

    BO_TRY_ESP(mdns_init());
    BO_TRY(populate_hostname());

    const struct system_info* sysinfo = bo_system_get_info();

    BO_TRY_ESP(mdns_hostname_set(s_mdns_ctx.hostname));
    BO_TRY_ESP(mdns_instance_name_set(sysinfo->name));

    BO_TRY(add_mdns_services());

    portENTER_CRITICAL(&s_mdns_lock);
    s_mdns_ctx.initialized = true;
    portEXIT_CRITICAL(&s_mdns_lock);
    ESP_LOGI(TAG, "mDNS started successfully.");

    return 0;
}

static void mdns_stop()
{
    portENTER_CRITICAL(&s_mdns_lock);
    bool initialized = s_mdns_ctx.initialized;
    portEXIT_CRITICAL(&s_mdns_lock);

    if (!initialized) {
        ESP_LOGI(TAG, "mDNS not started, skipping stop...");
        return;
    }

    ESP_LOGI(TAG, "Stopping mDNS...");

    mdns_free();

    portENTER_CRITICAL(&s_mdns_lock);
    s_mdns_ctx.initialized = false;
    portEXIT_CRITICAL(&s_mdns_lock);
    ESP_LOGI(TAG, "mDNS stopped successfully.");
}

static void mdns_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    switch (event_id) {
    case IP_EVENT_STA_GOT_IP: {
        ESP_LOGI(TAG, "WiFi connected, starting mDNS...");
        BO_MUST_ESP(mdns_start());
    } break;

    case IP_EVENT_STA_LOST_IP: {
        ESP_LOGI(TAG, "WiFi disconnected, stopping mDNS...");
        mdns_stop();
    } break;

    default:
        break;
    }
}

int populate_hostname()
{
    uint8_t mac[6] = { 0 };
    BO_TRY(esp_read_mac(mac, ESP_MAC_WIFI_STA));
    portENTER_CRITICAL(&s_mdns_lock);
    snprintf(s_mdns_ctx.hostname, sizeof(s_mdns_ctx.hostname), "%s-%02X%02X", CONFIG_LWIP_LOCAL_HOSTNAME, mac[4],
             mac[5]);
    portEXIT_CRITICAL(&s_mdns_lock);
    return 0;
}

static int add_mdns_services()
{
    uint8_t mac[6] = { 0 };
    char mac_str[18];
    BO_TRY(esp_read_mac(mac, ESP_MAC_WIFI_STA));
    snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

    const struct system_info* sysinfo = bo_system_get_info();
    // Add the mDNS service
    BO_TRY_ESP(mdns_service_add(NULL, MDNS_SERVICE_TYPE, "_udp", MDNS_UDP_PORT, NULL, 0));

    // Note: You must add the service first, then you can set its properties.
    // The web server uses a custom instance name.
    BO_TRY_ESP(mdns_service_instance_name_set(MDNS_SERVICE_TYPE, "_udp", sysinfo->name));

    const esp_app_desc_t* app_desc = esp_app_get_description();

    mdns_txt_item_t serviceTxtData[] = {
        { "name", sysinfo->name },
        { "id", sysinfo->hex_id },
        { "vendor", CONFIG_BORNEO_VENDOR_NAME },
        { "model", CONFIG_BORNEO_MODEL_NAME },
        { "pid", CONFIG_BORNEO_PRODUCT_ID },
        { "hwver", CONFIG_BORNEO_HW_VER },
        { "fwver", app_desc->version },
#if CONFIG_BORNEO_EDITION_CE
        { "ce", "true" },
#else
        { "ce", "false" },
#endif
        { "serno", sysinfo->hex_id },
        { "category", CONFIG_BORNEO_DEVICE_CATEGORY },
        { "compatible", CONFIG_BORNEO_DEVICE_COMPATIBLE },
        { "path", "/borneo" },
        { "mac", mac_str },
        { "iver", "1" },
    };

    BO_TRY_ESP(mdns_service_txt_set(MDNS_SERVICE_TYPE, "_udp", serviceTxtData,
                                    sizeof(serviceTxtData) / sizeof(mdns_txt_item_t)));

    return 0;
}
