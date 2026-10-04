set(COOP_RED4EXT_REVISION ad7277714ad30d6885d7050c5ba24fa0102f6920)
set(COOP_RED4EXT_SOURCE "" CACHE PATH "Optional existing clean, pinned RED4ext.SDK checkout")
if(COOP_RED4EXT_SOURCE)
    find_package(Git REQUIRED)
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${COOP_RED4EXT_SOURCE}" rev-parse HEAD
        OUTPUT_VARIABLE sdk_revision OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    if(NOT sdk_revision STREQUAL COOP_RED4EXT_REVISION)
        message(FATAL_ERROR "RED4ext.SDK must be at ${COOP_RED4EXT_REVISION}; got ${sdk_revision}")
    endif()
    execute_process(COMMAND "${GIT_EXECUTABLE}" -C "${COOP_RED4EXT_SOURCE}" status --porcelain --untracked-files=no
        OUTPUT_VARIABLE sdk_dirty OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
    if(sdk_dirty)
        message(FATAL_ERROR "RED4ext.SDK has tracked modifications; use a clean checkout")
    endif()
    add_subdirectory("${COOP_RED4EXT_SOURCE}" "${CMAKE_CURRENT_BINARY_DIR}/RED4ext.SDK")
else()
    include(FetchContent)
    FetchContent_Declare(red4ext_sdk
        GIT_REPOSITORY https://github.com/Cyberpunk2077-Mods/RED4ext.SDK.git
        GIT_TAG ${COOP_RED4EXT_REVISION})
    FetchContent_MakeAvailable(red4ext_sdk)
endif()
