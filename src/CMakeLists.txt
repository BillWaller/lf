cmake_minimum_required(VERSION 3.15)
project(lf
    VERSION 0.3.3
    DESCRIPTION "lf file finder"
    LANGUAGES C
)

# ------------------------------------------------------------------------------
# Build Type Setup (Defaults to Release if not specified)
# ------------------------------------------------------------------------------
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build." FORCE)
endif()

# ------------------------------------------------------------------------------
# Compiler Standard and Basic Requirements
# ------------------------------------------------------------------------------
set(CMAKE_C_STANDARD 23) # Closest standard mapping to gnu2y (-std=gnu2y)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Find Thread library dependency
find_package(Threads REQUIRED)

# ------------------------------------------------------------------------------
# Compilation and Linker Flags
# ------------------------------------------------------------------------------
add_compile_options(
    -march=native -Wall -Wextra -Wshadow -Wpointer-arith -Wstrict-prototypes
    -Wmissing-prototypes -Wmissing-declarations -Werror -Wno-unused-parameter
    -Wno-unused-function -Wno-unused-variable -Wno-unused-result
    -Wno-unused-but-set-variable -Wno-unused-label -Wno-unused-value
    -Wno-unused-const-variable -Wno-unused-macros
)

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    add_compile_options(-O3 -s -fPIC)
    add_link_options(-s)
else()
    # Debug Build Options
    add_compile_options(-O0 -g3 -fPIC -fno-omit-frame-pointer -rdynamic)
    add_link_options(-g3 -fno-omit-frame-pointer -rdynamic)
endif()

# ------------------------------------------------------------------------------
# Executable Target
# ------------------------------------------------------------------------------
add_executable(lf lf.c lf.h)
target_link_libraries(lf PRIVATE Threads::Threads)

# ------------------------------------------------------------------------------
# Man Page Generation (via pandoc and gzip)
# ------------------------------------------------------------------------------
find_program(PANDOC_EXECUTABLE pandoc)
find_program(GZIP_EXECUTABLE gzip)

if(PANDOC_EXECUTABLE AND GZIP_EXECUTABLE)
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/lf.1.gz
        COMMAND ${PANDOC_EXECUTABLE} -f markdown-smart -standalone --to man ${CMAKE_CURRENT_SOURCE_DIR}/../docs/lf.md -o ${CMAKE_CURRENT_BINARY_DIR}/lf.1
        COMMAND ${GZIP_EXECUTABLE} -f ${CMAKE_CURRENT_BINARY_DIR}/lf.1
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/../docs/lf.md
        COMMENT "Generating compressed man page from Markdown"
    )
    add_custom_target(man ALL DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/lf.1.gz)
else()
    message(WARNING "pandoc or gzip not found. Man page generation will be skipped.")
endif()

# ------------------------------------------------------------------------------
# Installation Rules
# ------------------------------------------------------------------------------
include(GNUInstallDirs) # Provides standard CMAKE_INSTALL_BINDIR (bin), CMAKE_INSTALL_MANDIR (share/man)

install(TARGETS lf DESTINATION ${CMAKE_INSTALL_BINDIR})

if(TARGET man)
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/lf.1.gz DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
endif()

# ------------------------------------------------------------------------------
# Custom Analysis Targets (Helgrind & Valgrind)
# ------------------------------------------------------------------------------
find_program(VALGRIND_EXECUTABLE valgrind)
if(VALGRIND_EXECUTABLE)
    # Helgrind target
    add_custom_target(helgrind
        COMMAND ${VALGRIND_EXECUTABLE} --tool=helgrind --log-file=helgrind.out -s $<TARGET_FILE:lf> -H $ENV{HOME} > /dev/null 2>&1
        DEPENDS lf
        COMMENT "Running Helgrind thread analysis..."
    )

    # Valgrind memcheck target
    add_custom_target(valgrind
        COMMAND ${VALGRIND_EXECUTABLE} -v
            --tool=memcheck
            --log-file=valgrind.out
            --leak-check=full
            --show-leak-kinds=definite
            --show-reachable=no
            --num-callers=30
            --leak-resolution=high
            --track-origins=yes
            --keep-debuginfo=yes
            --suppressions=${CMAKE_CURRENT_SOURCE_DIR}/valgrind.supp
            --gen-suppressions=all
            $<TARGET_FILE:lf> -H $ENV{HOME}
        DEPENDS lf
        COMMENT "Running Valgrind memory leak analysis..."
    )
endif()

