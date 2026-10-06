foreach(suite protocol session net interpolation network_e2e network_impairment game_bridge npc)
    add_executable(${suite}_tests ${suite}_tests.cpp)
    target_link_libraries(${suite}_tests PRIVATE coop::core)
    add_test(NAME ${suite} COMMAND ${suite}_tests)
endforeach()
add_test(NAME runtime_import COMMAND "${CMAKE_COMMAND}" -DROOT=${PROJECT_SOURCE_DIR}
    -P "${PROJECT_SOURCE_DIR}/build-support/VerifyRuntime.cmake")

set_tests_properties(protocol session net interpolation network_e2e runtime_import PROPERTIES TIMEOUT 40)
set_tests_properties(network_impairment PROPERTIES TIMEOUT 60)

if(COOP_BUILD_SESSION_SERVER)
    add_test(NAME server_smoke COMMAND CP2077SessionServer --config "${CMAKE_CURRENT_SOURCE_DIR}/server.ini" --run-for-ms 50)
    set_tests_properties(server_smoke PROPERTIES TIMEOUT 10 PASS_REGULAR_EXPRESSION "STOP accepted_states=0")
endif()

add_test(NAME session_bridge_contract COMMAND "${CMAKE_COMMAND}" -DROOT=${PROJECT_SOURCE_DIR}
    -P "${PROJECT_SOURCE_DIR}/build-support/VerifySessionBridge.cmake")
set_tests_properties(game_bridge npc session_bridge_contract PROPERTIES TIMEOUT 40)

include("${PROJECT_SOURCE_DIR}/build-support/LuaTests.cmake")
add_test(NAME npc_population COMMAND coop_lua_test "${CMAKE_CURRENT_SOURCE_DIR}/npc_population_tests.lua" "${PROJECT_SOURCE_DIR}")
set_tests_properties(npc_population PROPERTIES TIMEOUT 15)
