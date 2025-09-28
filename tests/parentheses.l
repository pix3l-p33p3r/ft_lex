%{
#include <stdio.h>
%}

%%
[0-9]+      { printf("NUMBER(%s)\n", yytext); }
"+"         { printf("PLUS\n"); }
"-"         { printf("MINUS\n"); }
"*"         { printf("MULTIPLY\n"); }
"/"         { printf("DIVIDE\n"); }
"("         { printf("LPAREN\n"); }
")"         { printf("RPAREN\n"); }
[ \t\n]     { /* ignore whitespace */ }
.           { printf("ERROR: Unexpected character %s\n", yytext); }

%%

int main() {
    yylex();
    return 0;
}

int yywrap() {
    return 1;
}
