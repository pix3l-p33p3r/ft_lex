#include <stdio.h>
#include <string.h>

void *malloc(unsigned long);
void *realloc(void *, unsigned long);
void *calloc(unsigned long, unsigned long);
void free(void *);

extern int yylex(void);
extern int yy_input_char(void);
extern int yy_unput_char(int);
extern int yy_less(int);
extern void yy_more(void);

int input(void)
{
	int c;

	c = yy_input_char();
	return c < 0 ? 0 : c;
}

int unput(int c)
{
	return yy_unput_char(c);
}

int yyless(int n)
{
	return yy_less(n);
}

int yymore(void)
{
	yy_more();
	return 0;
}

__attribute__((weak)) int yywrap(void)
{
	return 1;
}

__attribute__((weak)) int main(int argc, char **argv)
{
	(void)argc;
	(void)argv;
	yylex();
	return 0;
}
