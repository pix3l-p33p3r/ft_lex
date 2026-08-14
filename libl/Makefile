CC = cc
AR = ar
CFLAGS = -std=c99 -Wall -Wextra

libl.a: libl.o
	$(AR) rcs $@ libl.o

libl.o: libl.c
	$(CC) $(CFLAGS) -c libl.c -o libl.o

clean:
	rm -f libl.o libl.a

.PHONY: clean
