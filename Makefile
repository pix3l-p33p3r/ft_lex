.PHONY: all clean test install

ZIG ?= zig
CC ?= gcc
PREFIX ?= /usr/local

all: build/ft_lex

build/ft_lex:
	$(ZIG) build -Drelease-safe

install: all
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 build/ft_lex $(DESTDIR)$(PREFIX)/bin/ft_lex
	install -d $(DESTDIR)$(PREFIX)/include
	install -m 644 libl/include/libl.h $(DESTDIR)$(PREFIX)/include/libl.h
	install -d $(DESTDIR)$(PREFIX)/lib
	install -m 644 build/libl.a $(DESTDIR)$(PREFIX)/lib/libl.a

test: all
	$(ZIG) build test
	./tests/run_tests.sh

clean:
	$(ZIG) build clean
	rm -rf build/ *.o lex.yy.c *_test *_flex *_ft_lex.out *_flex.out

.SUFFIXES: .l .c
.l.c:
	./build/ft_lex $<
