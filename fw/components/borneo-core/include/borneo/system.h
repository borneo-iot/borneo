#pragma once

#include <esp_system.h>
#include <esp_event.h>

#include <borneo/common.h>
#include <borneo/try.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BO_DEVICE_ID_LENGTH 8 ///< In bytes, EUI-64 format
#define BO_DEVICE_NAME_MAX 64
#define BO_DEVICE_VENDOR_MAX 64
#define BO_DEVICE_MODEL_MAX 32

#define BO_SEM_AUTO_RELEASE(sem_expr)                                                                                  \
    __attribute__((cleanup(bo_sem_release))) SemaphoreHandle_t sem##_##__LINE__ = sem_expr

ESP_EVENT_DECLARE_BASE(BO_SYSTEM_EVENTS);

enum {
    BO_EVENT_INITIALIZING = 0, ///< Power-on start initialization
    BO_EVENT_POWER_ON, ///< Soft power on
    BO_EVENT_REBOOTING, ///< Rebooting
    BO_EVENT_SHUTDOWN_SCHEDULED, ///< Scheduled a shutdown
    BO_EVENT_SHUTDOWN_FAULT, ///< Fault shutdown event
    BO_EVENT_TEMPERATURE_CHANGED, ///< Temperature changed event

    BO_EVENT_ENTRY_FACTORY_MODE, ///< Entry the Factory Mode

    BO_EVENT_FATAL_ERROR, ///< Fatal error occurred

    BO_EVENT_GEO_LOCATION_CHANGED, ///< Location changed
};

enum {
    BO_SHUTDOWN_REASON_SCHEDULED = 0,
    BO_SHUTDOWN_REASON_FATAL_ERROR = 0x00000001,
    BO_SHUTDOWN_REASON_OVERHEATED = 0x00000002,
    BO_SHUTDOWN_REASON_OVER_POWER = 0x00000003,

    BO_SHUTDOWN_REASON_UNKNOWN = 0xFFFFFFFF,
};

struct system_info {
    char name[BO_DEVICE_NAME_MAX];
    char model[BO_DEVICE_MODEL_MAX];
    char vendor[BO_DEVICE_VENDOR_MAX];
    uint8_t id[BO_DEVICE_ID_LENGTH];
    char hex_id[(BO_DEVICE_ID_LENGTH * 2) + 1];
};

struct system_status {
    uint32_t state_flags;
    uint32_t shutdown_reason;
    uint64_t shutdown_timestamp;
    uint8_t mode;
};

int bo_system_init();

const struct system_info* bo_system_get_info();

void bo_system_reboot_later(uint32_t delay_ms);

void bo_panic();
void bo_safe_mode(uint32_t reason);

int bo_system_factory_reset();

int bo_system_set_factory_name(const char* name);
int bo_system_set_user_name(const char* name);
int bo_system_set_model(const char* model);
int bo_system_set_vendor(const char* vendor);

uint32_t bo_system_get_shutdown_reason();
void bo_system_set_shutdown_reason(uint32_t reason);

uint64_t bo_system_get_shutdown_timestamp();

void bo_sem_release(SemaphoreHandle_t* sem);

bool bo_system_is_operable();
bool bo_system_connection_configurated();

#ifdef __cplusplus
}
#endif