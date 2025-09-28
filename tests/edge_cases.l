%{
#include <stdio.h>
%}

%%
^$          { printf("EMPTY_LINE\n"); }
[a-zA-Z]+   { printf("WORD(%s)\n", yytext); }
[0-9]+      { printf("NUMBER(%s)\n", yytext); }
[ \t]+      { printf("WHITESPACE\n"); }
\n          { printf("NEWLINE\n"); }
.           { printf("OTHER(%s)\n", yytext); }

%%

int main() {
    yylex();
    return 0;
}

int yywrap() {
    return 1;
}
