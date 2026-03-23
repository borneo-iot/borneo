file(GLOB_RECURSE BORNEO_OTA_COAP_SOURCES
    "src/*.c"
    "src/*.cpp"
)

idf_component_register(
    SRCS ${BORNEO_OTA_COAP_SOURCES}
    REQUIRES app_update borneo-core borneo-coap
    WHOLE_ARCHIVE TRUE
)
