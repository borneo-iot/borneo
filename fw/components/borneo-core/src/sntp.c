/*- Project:    A simple SNTP client
  - Author:     Richard James Howe
  - License:    The Unlicense
  - Email:      howe.r.j.89@gmail.com
  - Repository: https://github.com/howerj/sntp */
#include <sys/time.h>
#include <arpa/inet.h>
#include <assert.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include <time.h>

#include <esp_system.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_timer.h>
#include <esp_attr.h>
#include <esp_sntp.h>
#include <esp_event.h>
#include <esp_log.h>
#include <esp_system.h>
#include <nvs_flash.h>
#include <esp_netif.h>

#include <borneo/system.h>
#include <borneo/sntp.h>
#include <borneo/rtc.h>

#define TAG "bo-sntp"
#define MAX_RETRY_COUNT 5
#define TASK_PRIORITY 4

ESP_EVENT_DEFINE_BASE(BO_SNTP_EVENTS);

#define SNTP_SERVER_0 "pool.ntp.org"

#define DELTA (2208988800ull)

static volatile bool _is_syncing = false;
static volatile bool _can_sync = false;

static inline unsigned long unpack32(unsigned char* p)
{
    assert(p);
    unsigned long l = 0;
    l |= ((unsigned long)p[0]) << 24;
    l |= ((unsigned long)p[1]) << 16;
    l |= ((unsigned long)p[2]) << 8;
    l |= ((unsigned long)p[3]) << 0;
    return l;
}

static inline void* get_in_addr(struct sockaddr* sa)
{
    // see https://beej.us/guide/bgnet/html/#cb46-22
    assert(sa);
    if (sa->sa_family == AF_INET)
        return &(((struct sockaddr_in*)sa)->sin_addr);
    return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

static inline char* _sntp_itoa(char a[32], unsigned n)
{
    assert(a);
    int i = 0;
    do
        a[i++] = "0123456789"[n % 10];
    while (n /= 10);
    a[i] = '\0';
    for (int j = 0; j < (i / 2); j++) {
        char t = a[j];
        a[j] = a[(i - j) - 1];
        a[(i - j) - 1] = t;
    }
    return a;
}

static int establish(const char* host_or_ip, unsigned port, int type)
{
    assert(host_or_ip);
    int fd = -1;
    struct addrinfo *servinfo = NULL, *p = NULL;
    struct addrinfo hints = {
        .ai_family = AF_UNSPEC,
        .ai_socktype = type,
    };
    if (port == 0 || port > 65535 || (type != SOCK_DGRAM && type != SOCK_STREAM))
        return -1;
    if (getaddrinfo(host_or_ip, _sntp_itoa((char[32]) { 0 }, port), &hints, &servinfo) != 0)
        goto fail;

    for (p = servinfo; p != NULL; p = p->ai_next) {
        if ((fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) == -1)
            continue;
        if (connect(fd, p->ai_addr, p->ai_addrlen) == -1) {
            if (close(fd) < 0)
                goto fail;
            fd = -1;
            continue;
        }
        break;
    }
    if (p == NULL)
        goto fail;

    char ip[INET6_ADDRSTRLEN] = { 0 };
    if (NULL == inet_ntop(p->ai_family, get_in_addr((struct sockaddr*)p->ai_addr), ip, sizeof ip))
        goto fail;

    freeaddrinfo(servinfo);
    servinfo = NULL;

    struct timeval tx_tv = { .tv_sec = 30 }, rx_tv = { .tv_sec = 30 };
    if (setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tx_tv, sizeof tx_tv) < 0)
        goto fail;
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rx_tv, sizeof rx_tv) < 0)
        goto fail;

    return fd;
fail:
    (void)close(fd);
    if (servinfo) {
        freeaddrinfo(servinfo);
        servinfo = NULL;
    }
    return -1;
}

int bo_sntp(const char* server, unsigned port, unsigned long* seconds, unsigned long* fractional)
{
    assert(server);
    assert(seconds);
    assert(fractional);
    // we could populate some fields in 'h' with seconds/fractional before sending...
    *seconds = 0;
    *fractional = 0;
    unsigned char h[48] = {
        0x1b,
    };
    const int fd = establish(server, port ? port : 123, SOCK_DGRAM);
    if (fd < 0)
        return -1;
    if (write(fd, h, sizeof h) != sizeof h)
        return -2;
    if (read(fd, h, sizeof h) != sizeof h)
        return -3;
    if (close(fd) < 0)
        return -4;
    *seconds = unpack32(&h[40]) - DELTA;
    *fractional = unpack32(&h[44]);
    return 0;
}

bool bo_sntp_is_sync_needed()
{
    time_t now = time(NULL);
    return now < 612964800;
}

static int bo_try_sync_time()
{
    int rc = 0;
    _is_syncing = true;
    int retry = 1;

    ESP_LOGI(TAG, "Starting SNTP...");

    unsigned long seconds = 0, fractional = 0;
    while (bo_sntp(CONFIG_BORNEO_SNTP_SERVER, 123, &seconds, &fractional) != 0) {
        ESP_LOGI(TAG, "Waiting for system time to be set... (%d/%d)", retry, MAX_RETRY_COUNT);

        if (retry >= MAX_RETRY_COUNT) {
            ESP_LOGE(TAG, "Failed to do SNTP");
            rc = -1;
            goto _EXIT;
        }
        retry++;
        vTaskDelay(pdMS_TO_TICKS(retry * retry * 1000));
    }

    time_t ts = seconds;
    BO_TRY(bo_rtc_set_time((int64_t)ts * 1000000LL));

    rc = bo_rtc_ext_update();
    if (rc != 0) {
        // System time is already valid here, so an external RTC write failure should not discard this sync result.
        // TODO: Surface this through a fault/alarm mechanism so users can detect battery or hardware failures.
        ESP_LOGW(TAG, "SNTP updated system time, but external RTC update failed: %d", rc);
        rc = 0;
    }

    time_t now = time(NULL);
    struct tm timeinfo = { 0 };
    localtime_r(&now, &timeinfo);

    char strftime_buf[64];
    strftime(strftime_buf, sizeof(strftime_buf), "%c", &timeinfo);
    ESP_LOGI(TAG, "SNTP succeed! The current date/time(local) is: %s", strftime_buf);

    BO_TRY(esp_event_post(BO_SNTP_EVENTS, BO_SNTP_EVENT_SUCCEED, NULL, 0, portMAX_DELAY));

    rc = 0;

_EXIT:
    _is_syncing = false;
    if (rc != 0) {
        BO_TRY(esp_event_post(BO_SNTP_EVENTS, BO_SNTP_EVENT_FAILED, NULL, 0, portMAX_DELAY));
    }
    return rc;
}

static void bo_sntp_task(void* param)
{
    uint64_t last_sntp_time = 0;

    // wait for time to be set
    while (true) {

        uint64_t diff = esp_timer_get_time() - last_sntp_time;
        // every 12 hours
        if (_can_sync || diff >= (24ULL * 3600ULL * 1000ULL * 1000ULL)) {
            vTaskDelay(pdMS_TO_TICKS(5000));
            _can_sync = false;
            (void)bo_try_sync_time();
            last_sntp_time = esp_timer_get_time();
        }

        vTaskDelay(pdMS_TO_TICKS(5000));
    }

    vTaskDelete(NULL);
}

static void ip_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    if (event_base != IP_EVENT) {
        return;
    }

    switch (event_id) {

    case IP_EVENT_STA_GOT_IP:
    case IP_EVENT_ETH_GOT_IP: {
        if (!bo_sntp_is_syncing()) {
            bo_sntp_now();
        }
    } break;

    default:
        break;
    }
}

int bo_sntp_init()
{
    ESP_LOGI(TAG, "Initializing Borneo SNTP sub-system...");
    char* tz = getenv("TZ");
    if (tz != NULL) {
        ESP_LOGI(TAG, "Current time zone: %s", tz);
    }

    xTaskCreate(bo_sntp_task, "sntp_task", 2 * 1024, NULL, TASK_PRIORITY, NULL);

    BO_TRY(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &ip_event_handler, NULL));

    ESP_LOGI(TAG, "Borneo SNTP sub-system has been initialized successfully.");

    return 0;
}

int bo_sntp_now()
{
    if (_can_sync || _is_syncing) {
        return -1;
    }
    else {
        _can_sync = true;
    }
    return 0;
}

bool bo_sntp_is_syncing() { return _is_syncing; }

void bo_sntp_obtain_time_until()
{
    // wait for time to be set
    struct tm timeinfo = { 0 };
    int retry = 0;
    while (sntp_get_sync_status() == SNTP_SYNC_STATUS_RESET && ++retry < MAX_RETRY_COUNT) {
        ESP_LOGI(TAG, "Waiting for system time to be set... (%d/%d)", retry, MAX_RETRY_COUNT);
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
    time_t now = time(NULL);
    localtime_r(&now, &timeinfo);
}