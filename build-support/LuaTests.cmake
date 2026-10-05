# Interpreter is test-only, never linked into the game plugin.
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()
include(FetchContent)
enable_language(C)
FetchContent_Declare(coop_lua_source
    URL https://www.lua.org/ftp/lua-5.4.8.tar.gz
    URL_HASH SHA256=4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae)
FetchContent_MakeAvailable(coop_lua_source)
file(GLOB lua_sources "${coop_lua_source_SOURCE_DIR}/src/*.c")
list(FILTER lua_sources EXCLUDE REGEX "/luac\\.c$")
add_executable(coop_lua_test ${lua_sources})
if(UNIX)
    target_link_libraries(coop_lua_test PRIVATE m ${CMAKE_DL_LIBS})
endif()
