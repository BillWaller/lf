# @file Makefile
# @brief Makefile for lf file finder
# @author Bill Waller
# Copyright (c) 2026
# MIT License
# billxwaller@gmail.com
# @date 2026-06-10
#
BUILD_TYPE=Debug
BUILD_TYPE=Release
# Uncomment the following line to enable thread sanitizer
# Only use for debugging as it will slow down the build and execution
# CC_EXTRA = -fsanitize=thread
EXP0=lf2
EXP1=lf3
EXP2=lf4
EXP3=
ifndef PREFIX
	PREFIX=/usr/local
endif
ifeq ($(BUILD_TYPE), Release)
	CFLAGS=-O3 -s -fPIC -pthread $(UI)
	LINKOPT= -pthread -s
else
#	DEBUG_FLAGS= -DDEBUG_LOG
	DEBUG_FLAGS=
	CFLAGS:=-O0 -g3 -fPIC $(DEBUG_FLAGS) -pthread -fno-omit-frame-pointer \
		-rdynamic
	LINKOPT= -g3 -fno-omit-frame-pointer -rdynamic -pthread
endif

LDFLAGS:= $(LINKOPT)
CFLAGS+=$(CC_EXTRA)
CFLAGS+=-march=native -Wall -Wextra -Wshadow -Wpointer-arith -Wstrict-prototypes \
	-Wmissing-prototypes -Wmissing-declarations -Werror -Wno-unused-parameter \
	-Wno-unused-function -Wno-unused-variable -Wno-unused-result \
	-Wno-unused-but-set-variable -Wno-unused-label -Wno-unused-value  \
	-Wno-unused-const-variable -Wno-unused-macros
BUILD_DIR:=$(CURDIR)
MAJOR=0
MINOR=3
PATCH=3
VERSION:=$(MAJOR).$(MINOR).$(PATCH)
SYSDATE:=$(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
LIB_DIR:=/usr/lib64
INSTALL_BIN_DIR:=$(PREFIX)/bin
INSTALL_MAN_DIR:=$(PREFIX)/man/man1
CX:=-std=gnu2y
CC:=gcc $(CX)
BINEXES:=lf $(EXP0) $(EXP1) $(EXP2) $(EXP3)
MANPAGES:=lf.1.gz
COMMON_HDRS:=lf.h
COMMON_SRCS:=lf.c
CC+=$(CFLAGS)
COMMON_OBJS=$(COMMON_SRCS:.c=.o)

.PHONY: all config help install man install_man clean uninstall helgrind valgrind

all:	$(BINEXES) man
	@echo Make Complete

config:
	@echo ------------------------------------------------------
	@echo "     Build Date $(SYSDATE)"
	@echo "     Build Type $(BUILD_TYPE)"
	@echo "         PREFIX $(PREFIX)"
	@echo "      BUILD_DIR $(BUILD_DIR)"
	@echo "        VERSION $(VERSION)"
	@echo "             CC $(CC)"
	@echo "             CX $(CX)"
	@echo "         CFLAGS $(CFLAGS)"
	@echo "        LDFLAGS $(LDFLAGS)"
	@echo "        LINKOPT $(LINKOPT)"
	@echo "INSTALL_BIN_DIR $(INSTALL_BIN_DIR)"
	@echo "INSTALL_MAN_DIR $(INSTALL_MAN_DIR)"
	@echo "        LIB_DIR $(LIB_DIR)"
	@echo "    COMMON_HDRS $(COMMON_HDRS)"
	@echo "    COMMON_SRCS $(COMMON_SRCS)"

help:
	@echo "Available targets:"
	@echo "  config        - Display Configuration"
	@echo "  all           - Build the library and all binaries"
	@echo "  install       - Install binaries, libraries, and headers"
	@echo "  man           - Build Manual Pages"
	@echo "  install_man   - Install Manual Pages"
	@echo "  clean         - Remove build artifacts"
	@echo "  uninstall     - Remove installed binaries and libraries"
	@echo "  valgrind      - run valgrind on selected executable"
	@echo "  helgrind      - run helgrind on selected executable"

man: $(MANPAGES)

lf: lf.c lf.h
	$(CC) $(CC_EXTRA) $< -o $@ $(LDFLAGS)

$(EXP0): $(EXP0).c $(EXP0).h
	$(CC) $(CC_EXTRA) $< -o $@ $(LDFLAGS)

$(EXP1): $(EXP1).c $(EXP1).h
	$(CC) $(CC_EXTRA) $< -o $@ $(LDFLAGS)

$(EXP2): $(EXP2).c $(EXP2).h
	$(CC) $(CC_EXTRA) $< -o $@ $(LDFLAGS)

$(EXP3): $(EXP3).c $(EXP3).h
	$(CC) $(CC_EXTRA) $< -o $@ $(LDFLAGS)

%:	%.c $(LIB_SHARED)
	$(CC) $< -o $@ $(LDFLAGS)

%.o:	%.c
	$(CC) 	-c $< -fPIC -o $@

whence:	whence.c
	$(CC) 	$< -o $@

lf.1.gz:	../docs/lf.md
	pandoc -f markdown-smart -standalone --to man ../docs/lf.md -o lf.1
	gzip -f lf.1

clean:
	rm -rf $(BINEXES) $(CFLOW_OUTPUT) .user_id .group_id core scan-build* \
	perf.* x xx* *.[aeos] *.diff *.so \
	*.cflow *.gc.. *.out *.1 *.1.gz CMakeFiles cmake_install.cmake \
	   	CMakeCache.txt CMakefile CMAKE_BUILD_TYPE=Debug gdb.log

helgrind:
	valgrind --tool=helgrind --log-file=helgrind/helgrind.out -s ./lf -H

valgrind: lf
	valgrind -v \
		--tool=memcheck \
		--log-file=valgrind.out \
		--leak-check=full \
		--show-leak-kinds=definite \
		--show-reachable=no \
		--num-callers=30 \
		--leak-resolution=high \
		--track-origins=yes \
		--keep-debuginfo=yes \
		--suppressions=valgrind.supp \
		--gen-suppressions=all \
		./lf -H

install:
	install -CDp	lf    -t $(INSTALL_BIN_DIR)
	install -CDp lf.1.gz	-t $(INSTALL_MAN_DIR)

install_man:
	install -CDp lf.1.gz	-t $(INSTALL_MAN_DIR)

uninstall:
	$(INSTALL_BIN_DIR)/lf
