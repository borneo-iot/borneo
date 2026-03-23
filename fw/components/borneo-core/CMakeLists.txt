file(GLOB_RECURSE BORNEO_CORE_SOURCES
    "src/*.c"
    "src/*.cpp"
    "drivers/*.c"
    "drivers/*.cpp"
)

set(BORNEO_INCLUDE_DIRS "./include")


idf_component_register(
    SRCS ${BORNEO_CORE_SOURCES}
    INCLUDE_DIRS ${BORNEO_INCLUDE_DIRS}
    REQUIRES nvs_flash esp_app_format esp_netif driver esp_wifi vfs esp_adc drvfx smf esp_timer spi_flash coap cbor
    WHOLE_ARCHIVE TRUE
)
