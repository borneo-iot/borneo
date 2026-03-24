# The following lines of boilerplate have to be in your project's CMakeLists
# in this exact order for cmake to work correctly
cmake_minimum_required(VERSION 3.5)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/../cmake")


if(NOT DEFINED PRODUCT_ID)
    message(WARNING "The variable `PRODUCT_ID` is not defined. Please set it using `-DPRODUCT_ID=value` when running `idf.py build`.")
    set(PRODUCT_ID "bst/blc06mk1")
endif()

include(BorneoProject REQUIRED)

# include("${CMAKE_SOURCE_DIR}/../cmake/ClangFormat.cmake" REQUIRED)


FILE(GLOB_RECURSE ALL_C_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/main/src/*.c"
)

FILE(GLOB_RECURSE ALL_CPP_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/main/src/*.cpp"
)

FILE(GLOB_RECURSE ALL_HEADERS
    "${CMAKE_CURRENT_SOURCE_DIR}/main/include/*.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/main/include/*.hpp"
)

# clangformat_setup(${ALL_C_SOURCES} ${ALL_CPP_SOURCES} ${ALL_HEADERS})

include($ENV{IDF_PATH}/tools/cmake/project.cmake)


project("${BORNEO_PROJECT_ID}")

message(STATUS "Firmware Version: ${PROJECT_VER}")