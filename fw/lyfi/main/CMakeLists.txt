file(GLOB_RECURSE BORNEO_APP_SOURCES
    "src/*.c"
    "src/*.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../boards/${BORNEO_BOARD_ID}/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/../products/${BORNEO_PRODUCT_ID}/*.c"
)

idf_component_register(
    SRCS ${BORNEO_APP_SOURCES}
    REQUIRES esp_driver_rmt esp_driver_ledc esp_driver_mcpwm esp_driver_dac drvfx smf button borneo-core borneo-coap borneo-ota-coap
    WHOLE_ARCHIVE TRUE
)
