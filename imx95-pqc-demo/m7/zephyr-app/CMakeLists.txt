cmake_minimum_required(VERSION 3.20.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(imx95_m7_wolfboot_openamp)
target_sources(app PRIVATE src/main.c)

# wolfCrypt's own benchmark, not a hand-rolled one: it is the same program the
# A55 container runs, so the two cores' numbers are directly comparable and in
# the same units, and there is no bespoke timing code here to get wrong.
target_include_directories(app PRIVATE
    ${ZEPHYR_WOLFSSL_MODULE_DIR}/wolfcrypt/benchmark)

target_sources(app PRIVATE
    ${ZEPHYR_WOLFSSL_MODULE_DIR}/wolfcrypt/benchmark/benchmark.c)

# benchmark.c carries its own main() for standalone use; this app has one.
# NOTE: this also compiles out wolfcrypt_benchmark_main() and the option
# tables (benchmark.c lines 18780-19294), so the algorithm selection cannot be
# driven by arguments - see the comment in src/main.c.
zephyr_compile_definitions(NO_MAIN_DRIVER)
