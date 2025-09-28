#ifndef LIBL_H
#define LIBL_H

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* Buffer size for reading input */
#define YY_BUF_SIZE 16384

/* Standard input handling */
extern FILE *yyin;
extern FILE *yyout;

/* Text buffer management */
extern char *yytext;
extern int yyleng;
extern int yylineno;

/* Function declarations */
int yylex(void);
int yywrap(void);
void yyrestart(FILE *input_file);
int input(void);
int unput(int c);
int output(int c);

/* Internal buffer management */
typedef struct yy_buffer_state *YY_BUFFER_STATE;
YY_BUFFER_STATE yy_create_buffer(FILE *file, int size);
void yy_switch_to_buffer(YY_BUFFER_STATE new_buffer);
void yy_delete_buffer(YY_BUFFER_STATE buffer);
void yy_flush_buffer(YY_BUFFER_STATE buffer);

#endif /* LIBL_H */
