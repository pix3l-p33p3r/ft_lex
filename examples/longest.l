%%
if      printf("IF\n");
[a-z]+  printf("ID %s\n", yytext);
[[:space:]]+ ;
.       printf("CH %s\n", yytext);
