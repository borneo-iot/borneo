#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

#include <esp_log.h>
#include <esp_system.h>
#include <esp_timer.h>
#include <esp_rom_md5.h>
#include <esp_event.h>
#include <nvs_flash.h>

#include <borneo/common.h>
#include <borneo/system.h>
#include <borneo/power.h>

#include <borneo/nvs.h>

#define NVS_FACTORY_PART_NAME "nvs_factory"
#define TAG "bo_nvs"

esp_err_t bo_nvs_init()
{

    esp_err_t rc;
    rc = nvs_flash_init_partition(NVS_DEFAULT_PART_NAME);
    if (rc == ESP_ERR_NVS_NO_FREE_PAGES || rc == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        rc = nvs_flash_erase_partition(NVS_DEFAULT_PART_NAME);
        if (rc) {
            return rc;
        }
        rc = nvs_flash_init_partition(NVS_DEFAULT_PART_NAME);
        if (rc) {
            return rc;
        }
    }

    rc = nvs_flash_init_partition(NVS_FACTORY_PART_NAME);
    if (rc == ESP_ERR_NVS_NO_FREE_PAGES || rc == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        rc = nvs_flash_erase_partition(NVS_FACTORY_PART_NAME);
        if (rc) {
            return rc;
        }
        rc = nvs_flash_init_partition(NVS_FACTORY_PART_NAME);
    }

    ESP_LOGI(TAG, "Borneo NVS initialized successfully.");
    return rc;
}

esp_err_t bo_nvs_factory_open(const char* name, nvs_open_mode_t open_mode, nvs_handle_t* out_handle)
{
    BO_TRY_ESP(nvs_open_from_partition(NVS_FACTORY_PART_NAME, name, open_mode, out_handle));
    return 0;
}

esp_err_t bo_nvs_user_open(const char* name, nvs_open_mode_t open_mode, nvs_handle_t* out_handle)
{
    BO_TRY_ESP(nvs_open_from_partition(NVS_DEFAULT_PART_NAME, name, open_mode, out_handle));
    return 0;
}

void bo_nvs_close(nvs_handle_t handle) { nvs_close(handle); }

esp_err_t bo_nvs_get_i8_or(nvs_handle_t h, const char* key, int8_t* val)
{
    if (val == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    int8_t tmp;
    esp_err_t err = nvs_get_i8(h, key, &tmp);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err == ESP_OK) {
        *val = tmp;
    }
    return err;
}

esp_err_t bo_nvs_get_u8_or(nvs_handle_t h, const char* key, uint8_t* val)
{
    if (val == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t tmp;
    esp_err_t err = nvs_get_u8(h, key, &tmp);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err == ESP_OK) {
        *val = tmp;
    }
    return err;
}

esp_err_t bo_nvs_get_i16_or(nvs_handle_t h, const char* key, int16_t* val)
{
    if (val == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    int16_t tmp;
    esp_err_t err = nvs_get_i16(h, key, &tmp);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err == ESP_OK) {
        *val = tmp;
    }
    return err;
}

esp_err_t bo_nvs_get_u16_or(nvs_handle_t h, const char* key, uint16_t* val)
{
    if (val == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    uint16_t tmp;
    esp_err_t err = nvs_get_u16(h, key, &tmp);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err == ESP_OK) {
        *val = tmp;
    }
    return err;
}

esp_err_t bo_nvs_get_i32_or(nvs_handle_t h, const char* key, int32_t* val)
{
    if (val == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    int32_t tmp;
    esp_err_t err = nvs_get_i32(h, key, &tmp);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err == ESP_OK) {
        *val = tmp;
    }
    return err;
}

esp_err_t bo_nvs_get_u32_or(nvs_handle_t h, const char* key, uint32_t* val)
{
    if (val == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    uint32_t tmp;
    esp_err_t err = nvs_get_u32(h, key, &tmp);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err == ESP_OK) {
        *val = tmp;
    }
    return err;
}

esp_err_t bo_nvs_get_i64_or(nvs_handle_t h, const char* key, int64_t* val)
{
    if (val == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    int64_t tmp;
    esp_err_t err = nvs_get_i64(h, key, &tmp);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err == ESP_OK) {
        *val = tmp;
    }
    return err;
}

esp_err_t bo_nvs_get_u64_or(nvs_handle_t h, const char* key, uint64_t* val)
{
    if (val == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    uint64_t tmp;
    esp_err_t err = nvs_get_u64(h, key, &tmp);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    }
    if (err == ESP_OK) {
        *val = tmp;
    }
    return err;
}

/**
 * \brief Clear user partition
 *
 */
esp_err_t bo_nvs_user_reset()
{
    //
    return nvs_flash_erase_partition(NVS_DEFAULT_PART_NAME);
}

void bo_nvs_auto_close(nvs_handle_t* handle)
{
    if (*handle != 0) {
        nvs_close(*handle);
        *handle = 0;
    }
}

esp_err_t bo_nvs_get_or_set_i8(nvs_handle_t handle, const char* key, int8_t* value, int8_t default_value, bool* changed)
{
    int rc = nvs_get_i8(handle, key, value);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        *value = default_value;
        rc = nvs_set_i8(handle, key, *value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_u8(nvs_handle_t handle, const char* key, uint8_t* value, uint8_t default_value,
                               bool* changed)
{
    int rc = nvs_get_u8(handle, key, value);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        *value = default_value;
        rc = nvs_set_u8(handle, key, *value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_i16(nvs_handle_t handle, const char* key, int16_t* value, int16_t default_value,
                                bool* changed)
{
    int rc = nvs_get_i16(handle, key, value);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        *value = default_value;
        rc = nvs_set_i16(handle, key, *value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_u16(nvs_handle_t handle, const char* key, uint16_t* value, uint16_t default_value,
                                bool* changed)
{
    int rc = nvs_get_u16(handle, key, value);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        *value = default_value;
        rc = nvs_set_u16(handle, key, *value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_i32(nvs_handle_t handle, const char* key, int32_t* value, int32_t default_value,
                                bool* changed)
{
    int rc = nvs_get_i32(handle, key, value);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        *value = default_value;
        rc = nvs_set_i32(handle, key, *value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_u32(nvs_handle_t handle, const char* key, uint32_t* value, uint32_t default_value,
                                bool* changed)
{
    int rc = nvs_get_u32(handle, key, value);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        *value = default_value;
        rc = nvs_set_u32(handle, key, *value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_i64(nvs_handle_t handle, const char* key, int64_t* value, int64_t default_value,
                                bool* changed)
{
    int rc = nvs_get_i64(handle, key, value);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        *value = default_value;
        rc = nvs_set_i64(handle, key, *value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_u64(nvs_handle_t handle, const char* key, uint64_t* value, uint64_t default_value,
                                bool* changed)
{
    int rc = nvs_get_u64(handle, key, value);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        *value = default_value;
        rc = nvs_set_u64(handle, key, *value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_str(nvs_handle_t handle, const char* key, char* value, size_t* length,
                                const char* default_value, bool* changed)
{
    // TODO 增加默认值长度与 length 长度检查
    size_t default_length = strlen(default_value);
    int rc = nvs_get_str(handle, key, value, length);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        if (value != NULL && *length >= default_length + 1) {
            memcpy(value, default_value, default_length);
            value[default_length] = '\0';
            *length = default_length + 1;
        }
        else {
            return ESP_ERR_INVALID_SIZE;
        }
        rc = nvs_set_str(handle, key, value);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}

esp_err_t bo_nvs_get_or_set_blob(nvs_handle_t handle, const char* key, void* value, size_t* length,
                                 const void* default_value, size_t default_length, bool* changed)
{
    int rc = nvs_get_blob(handle, key, value, length);
    if (rc == ESP_ERR_NVS_NOT_FOUND) {
        if (value != NULL && *length >= default_length) {
            memcpy(value, default_value, default_length);
            *length = default_length;
        }
        else {
            return ESP_ERR_INVALID_SIZE;
        }
        rc = nvs_set_blob(handle, key, value, *length);
        if (rc == 0) {
            *changed = true;
        }
    }
    return rc;
}
