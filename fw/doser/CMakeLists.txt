# The following lines of boilerplate have to be in your project's CMakeLists
# in this exact order for cmake to work correctly
cmake_minimum_required(VERSION 3.10)

if(NOT BORNEO_BOARD)
    set(BORNEO_BOARD "doser4-old")
endif()

set(SDKCONFIG "${CMAKE_BINARY_DIR}/sdkconfig")

set(BORNEO_BOARD_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/boards/${BORNEO_BOARD}")

set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/../components")

if(CMAKE_BUILD_TYPE AND (CMAKE_BUILD_TYPE STREQUAL "Release"))
    set(SDKCONFIG_DEFAULTS "sdkconfig.common;sdkconfig.release;${CMAKE_CURRENT_SOURCE_DIR}/boards/${BORNEO_BOARD}/sdkconfig")
else()
    set(SDKCONFIG_DEFAULTS "sdkconfig.common;sdkconfig.debug;${CMAKE_CURRENT_SOURCE_DIR}/boards/${BORNEO_BOARD}/sdkconfig")
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/boards/${BORNEO_BOARD}/board.cmake")

#include(./cmake/ClangFormat.cmake REQUIRED)

FILE(GLOB_RECURSE ALL_C_SOURCES
    "./main/src/*.c"
)

FILE(GLOB_RECURSE ALL_CPP_SOURCES
    "./main/src/*.cpp"
)

FILE(GLOB_RECURSE ALL_HEADERS
    "./main/include/*.h"
    "./main/include/*.hpp"
)

#clangformat_setup(${ALL_C_SOURCES} ${ALL_CPP_SOURCES} ${ALL_HEADERS})

include($ENV{IDF_PATH}/tools/cmake/project.cmake)


project("borneo_doser_fw_${BORNEO_BOARD}")

set(BORNEO_BOARD_INCLUDE_DIR  ${BORNEO_BOARD_DIR})


message(">>>>>>> Borneo Doser Board: ${BORNEO_BOARD}")
