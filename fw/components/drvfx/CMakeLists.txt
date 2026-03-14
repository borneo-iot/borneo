file(GLOB_RECURSE DRVFX_SOURCES
    "kernel/*.c"
    "kernel/*.cpp"
    "drivers/*.c"
    "drivers/*.cpp"
)

set(DRVFX_INCLUDE_DIRS "./include")


idf_component_register(
    SRCS ${DRVFX_SOURCES}
    INCLUDE_DIRS ${DRVFX_INCLUDE_DIRS}
    REQUIRES driver esp_event esp_driver_i2c
    LDFRAGMENTS kernel-linker.lf
    WHOLE_ARCHIVE
)

include(package_manager)
cu_pkg_define_version(${CMAKE_CURRENT_LIST_DIR})