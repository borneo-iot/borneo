
set(SDKCONFIG "${CMAKE_BINARY_DIR}/sdkconfig")
set(EXTRA_COMPONENT_DIRS
    "${CMAKE_CURRENT_SOURCE_DIR}/../components"
    "${CMAKE_CURRENT_SOURCE_DIR}/../3rd-components"
)

message("[BORNEO] > Product ID: `${PRODUCT_ID}`")


set(BORNEO_PRODUCT_ID ${PRODUCT_ID})

include("${CMAKE_CURRENT_SOURCE_DIR}/products/${BORNEO_PRODUCT_ID}/product.cmake")

message("[BORNEO] > Board ID: `${BORNEO_BOARD_ID}`")

include("${CMAKE_CURRENT_SOURCE_DIR}/boards/${BORNEO_BOARD_ID}/board.cmake")

set(BORNEO_BOARD_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/boards/${BORNEO_BOARD_ID}")


if(CMAKE_BUILD_TYPE AND (CMAKE_BUILD_TYPE STREQUAL "Release"))
    message("[BORNEO] > Building RELEASE profile")
    set(SDKCONFIG_DEFAULTS "${CMAKE_CURRENT_SOURCE_DIR}/sdkconfig.common;${CMAKE_CURRENT_SOURCE_DIR}/sdkconfig.release;${BORNEO_BOARD_DIR}/sdkconfig.board;${CMAKE_CURRENT_SOURCE_DIR}/products/${BORNEO_PRODUCT_ID}/sdkconfig.product")
else()
    message("[BORNEO] > Building DEBUG profile")
    set(SDKCONFIG_DEFAULTS "${CMAKE_CURRENT_SOURCE_DIR}/sdkconfig.common;${CMAKE_CURRENT_SOURCE_DIR}/sdkconfig.debug;${BORNEO_BOARD_DIR}/sdkconfig.board;${CMAKE_CURRENT_SOURCE_DIR}/products/${BORNEO_PRODUCT_ID}/sdkconfig.product")
endif()


set(BORNEO_PROJECT_ID ${BORNEO_PRODUCT_ID})
string(REPLACE "/" "_" BORNEO_PROJECT_ID "${BORNEO_PRODUCT_ID}")
message("-- [BORNEO] > Project: `${BORNEO_PROJECT_ID}`")

set(BORNEO_BOARD_INCLUDE_DIR  ${BORNEO_BOARD_DIR})

if(EXISTS "${CMAKE_SOURCE_DIR}/version.txt")
    file(READ "${CMAKE_SOURCE_DIR}/version.txt" BASE_VERSION)
    string(STRIP ${BASE_VERSION} BASE_VERSION)
    message("-- Base version from version.txt: ${BASE_VERSION}")
else()
    set(BASE_VERSION "0.0.0")
    message(WARNING "version.txt not found, using default: ${BASE_VERSION}")
endif()

find_package(Git)
if(GIT_FOUND)
    execute_process(
        COMMAND ${GIT_EXECUTABLE} rev-list --count HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE BUILD_NUMBER
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
endif()

set(PROJECT_VER "${BASE_VERSION}+${BUILD_NUMBER}")

message("-- Base version: [${BASE_VERSION}], \tBuild number: [${BUILD_NUMBER}], \tFinal version: [${PROJECT_VER}]")
