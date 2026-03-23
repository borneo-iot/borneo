
set(DRIVERS_DIR "${CMAKE_CURRENT_LIST_DIR}/drivers")

file(GLOB_RECURSE DRIVERS_FILES "${DRIVERS_DIR}/*/drivers.cmake")

foreach(module_file ${DRIVERS_FILES})
    get_filename_component(driver_name "${driver_file}" DIRECTORY)
    get_filename_component(driver_name "${driver_name}" NAME)
    message(STATUS "Loading driver module: `${module_file}`")
    include(${module_file})
endforeach()

# 4. 从全局属性中取出所有模块塞进去的源码和头文件
get_property(COMPONENT_SRCS GLOBAL PROPERTY MY_COMP_SRCS)
get_property(COMPONENT_INCS GLOBAL PROPERTY MY_COMP_INCS)


get_property(DRVFX_FINAL_DRIVERS_SRCS GLOBAL PROPERTY DRVFX_DRIVERS_SOURCES)

file(GLOB_RECURSE DRVFX_SOURCES
    "kernel/*.c"
    "kernel/*.cpp"
)

set(DRVFX_INCLUDE_DIRS "./include")

idf_component_register(
    SRCS ${DRVFX_SOURCES} ${DRVFX_FINAL_DRIVERS_SRCS}
    INCLUDE_DIRS ${DRVFX_INCLUDE_DIRS}
    REQUIRES driver esp_event esp_driver_i2c
    LDFRAGMENTS kernel-linker.lf
    WHOLE_ARCHIVE TRUE
)


include(package_manager)
cu_pkg_define_version(${CMAKE_CURRENT_LIST_DIR})