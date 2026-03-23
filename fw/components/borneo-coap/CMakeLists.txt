file(GLOB_RECURSE BORNEO_COAP_SOURCES
    "src/*.c"
    "src/*.cpp"
)

set(BORNEO_COAP_INCLUDE_DIRS "./include")


idf_component_register(
    SRCS ${BORNEO_COAP_SOURCES}
    INCLUDE_DIRS ${BORNEO_COAP_INCLUDE_DIRS}
    REQUIRES nvs_flash esp_app_format esp_timer spi_flash coap cbor drvfx borneo-core
    LDFRAGMENTS ./coap.lf
    WHOLE_ARCHIVE TRUE
)
