cmake_minimum_required(VERSION 3.20)

project(CP2077CoopServer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(CP2077CoopServer
    main.cpp
)

target_link_libraries(CP2077CoopServer
    PRIVATE
    ws2_32
)