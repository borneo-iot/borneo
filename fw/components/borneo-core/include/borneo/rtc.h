#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int bo_rtc_init();

int bo_rtc_get_timestamp(uint32_t* timestamp);
int64_t bo_rtc_get_timestamp_us();
int bo_rtc_set_time(int64_t timestamp_us);
int bo_rtc_ext_update();

const char* bo_rtc_get_tz();
int bo_rtc_set_tz(const char* tz);

#ifdef __cplusplus
}
#endif