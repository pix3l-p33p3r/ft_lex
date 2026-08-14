%x COMMENT
%%
"/*"            BEGIN COMMENT;
<COMMENT>"*/"   BEGIN INITIAL;
<COMMENT>.|\n   ;
[a-z]+          printf("WORD %s\n", yytext);
[[:space:]]+    ;
.               printf("CH %s\n", yytext);
