cmake_minimum_required(VERSION 3.20)

project(CP2077Coop LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory("../RED4ext.SDK" RED4ext.SDK)

add_library(${PROJECT_NAME} SHARED
    src/main.cpp
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
    RED4ext::SDK
    ws2_32
)