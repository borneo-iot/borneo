file(GLOB_RECURSE BORNEO_APP_SOURCES
    "src/*.c"
    "src/*.cpp"
)

set(REQUIRES_PRO)

if(BORNEO_EDITION_PRO STREQUAL "1")
    list(APPEND REQUIRES_PRO borneo-factory borneo-ota)
endif()

idf_component_register(
    SRCS ${BORNEO_APP_SOURCES}
    REQUIRES drvfx coap borneo-core smf cbor coap ${REQUIRES_PRO}
    WHOLE_ARCHIVE TRUE
)
