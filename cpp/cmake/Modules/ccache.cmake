# Use ccache if possible.
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
  if(NOT DEFINED CMAKE_C_COMPILER_LAUNCHER)
    message(STATUS "Using C compiler launcher: ${CCACHE_PROGRAM}")
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
  endif()
  if(NOT DEFINED CMAKE_CXX_COMPILER_LAUNCHER)
    message(STATUS "Using CXX compiler launcher: ${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
  endif()
  if(NOT DEFINED CMAKE_CUDA_COMPILER_LAUNCHER)
    message(STATUS "Using CUDA compiler launcher: ${CCACHE_PROGRAM}")
    set(CMAKE_CUDA_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
  endif()
endif()
