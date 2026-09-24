# Prints what CMake reports about the host it runs on.
#
# QtAutoDetectHelpers.cmake enables the native HarmonyOS build only when
# CMAKE_HOST_SYSTEM_NAME is exactly "HarmonyOS". OpenHarmony is Linux-kernel
# based, so uname -s says Linux, and CMake reads the name in its own C++
# before CMakeDetermineSystem.cmake runs. Whether any shipped cmake reports
# "HarmonyOS" decides if that condition can ever be true.
#
# Usage: cmake -P hostprobe.cmake

message(STATUS "cmake version               = ${CMAKE_VERSION}")
message(STATUS "CMAKE_HOST_SYSTEM_NAME      = ${CMAKE_HOST_SYSTEM_NAME}")
message(STATUS "CMAKE_HOST_SYSTEM_PROCESSOR = ${CMAKE_HOST_SYSTEM_PROCESSOR}")
message(STATUS "CMAKE_HOST_SYSTEM_VERSION   = ${CMAKE_HOST_SYSTEM_VERSION}")
message(STATUS "CMAKE_SYSTEM_NAME           = ${CMAKE_SYSTEM_NAME}")
message(STATUS "CMAKE_ROOT                  = ${CMAKE_ROOT}")

# A cmake that ships no HarmonyOS platform module is unlikely to report the
# name either. qtbase supplies its own modules; these are cmake's own.
file(GLOB platform_modules
    "${CMAKE_ROOT}/Modules/Platform/*armony*"
    "${CMAKE_ROOT}/Modules/Platform/*OHOS*")
if(platform_modules)
    message(STATUS "HarmonyOS/OHOS modules in this cmake: ${platform_modules}")
else()
    message(STATUS "HarmonyOS/OHOS modules in this cmake: none")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "HarmonyOS")
    message(STATUS "RESULT: QtAutoDetectHelpers.cmake:236 CAN be true here")
else()
    message(STATUS "RESULT: QtAutoDetectHelpers.cmake:236 is FALSE here")
endif()
