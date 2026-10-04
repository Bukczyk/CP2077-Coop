foreach(suite protocol session)
    add_executable(${suite}_tests ${suite}_tests.cpp)
    target_link_libraries(${suite}_tests PRIVATE coop::core)
    add_test(NAME ${suite} COMMAND ${suite}_tests)
endforeach()
add_test(NAME runtime_import COMMAND "${CMAKE_COMMAND}" -DROOT=${PROJECT_SOURCE_DIR}
    -P "${PROJECT_SOURCE_DIR}/build-support/VerifyRuntime.cmake")
