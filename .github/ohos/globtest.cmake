# Checks that file(GLOB) sees every entry in a directory.
#
# On a kernel without CONFIG_ANON_VMA_NAME this fails past roughly 48 entries:
# OHOS musl names its heap VMAs with prctl(PR_SET_VMA), that prctl returns
# EINVAL and leaves errno set, and kwsys's Directory::Load checks errno after a
# readdir loop whose body allocates. The listing is complete but reported as a
# failure, so file(GLOB) yields nothing and CMake cannot even identify the
# compiler. Probing it here turns that into a named failure instead of a
# baffling one an hour into the configure.
#
# Usage: cmake -DWORKDIR=<writable dir> -P globtest.cmake

if(NOT DEFINED WORKDIR)
  message(FATAL_ERROR "pass -DWORKDIR=<writable dir>")
endif()

set(broken "")
foreach(n 8 48 49 64 256)
  set(dir "${WORKDIR}/glob_${n}")
  file(REMOVE_RECURSE "${dir}")
  file(MAKE_DIRECTORY "${dir}")
  foreach(i RANGE 1 ${n})
    file(WRITE "${dir}/f${i}.cmake" "")
  endforeach()
  file(GLOB found "${dir}/*.cmake")
  list(LENGTH found count)
  if(count EQUAL n)
    message(STATUS "file(GLOB) over ${n} entries: ${count}, ok")
  else()
    message(STATUS "file(GLOB) over ${n} entries: ${count}, EXPECTED ${n}")
    list(APPEND broken ${n})
  endif()
  file(REMOVE_RECURSE "${dir}")
endforeach()

if(broken)
  message(FATAL_ERROR
    "file(GLOB) lost entries at: ${broken}. Check that the host kernel has "
    "CONFIG_ANON_VMA_NAME; without it OHOS musl leaves errno set after every "
    "heap growth and kwsys reports good directory listings as failures.")
endif()
message(STATUS "file(GLOB) is sound at every size probed")
