DIGIT   [0-9]
ID      [a-zA-Z_][a-zA-Z0-9_]*
%%
if|then|else|while  printf("KW %s\n", yytext);
{DIGIT}+            printf("NUM %s\n", yytext);
{ID}                printf("ID %s\n", yytext);
[[:space:]]+        ;
.                   printf("CH %s\n", yytext);
