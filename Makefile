.PHONY: all libl test clean

all:
	zig build
	cp -f zig-out/bin/ft_lex ./ft_lex
	cp -f zig-out/lib/libl.a ./libl.a

libl:
	$(MAKE) -C libl
	cp -f libl/libl.a ./libl.a

test:
	zig build test

clean:
	rm -rf zig-out .zig-cache ft_lex libl.a lex.yy.c scanner
	$(MAKE) -C libl clean
