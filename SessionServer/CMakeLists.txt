add_executable(CP2077SessionServer main.cpp)
target_link_libraries(CP2077SessionServer PRIVATE coop::core)
install(TARGETS CP2077SessionServer RUNTIME DESTINATION bin)
