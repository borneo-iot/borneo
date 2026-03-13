file(GLOB_RECURSE BORNEO_APP_SOURCES
    "src/*.c"
    "src/*.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../boards/${BORNEO_BOARD_ID}/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/../products/${BORNEO_PRODUCT_ID}/*.c"
)

idf_component_register(
    SRCS ${BORNEO_APP_SOURCES}
    REQUIRES drvfx coap borneo-core smf cbor coap button
    WHOLE_ARCHIVE
)
