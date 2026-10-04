#pragma once
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#define CHECK(expression) do { if (!(expression)) throw std::runtime_error(std::string(__FILE__) + ":" + std::to_string(__LINE__) + ": " #expression); } while (false)
template<class F> int Run(F tests) {
    try { tests(); std::cout << "All checks passed\n"; return EXIT_SUCCESS; }
    catch (const std::exception& e) { std::cerr << e.what() << '\n'; return EXIT_FAILURE; }
}
