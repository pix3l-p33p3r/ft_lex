%{
int lines, words, chars;
%}
%%
[^ \t\n]+   { words++; chars += yyleng; }
\n          { chars++; lines++; }
.           { chars++; }
%%
int main(void)
{
    yylex();
    printf("%d %d %d\n", lines, words, chars);
    return 0;
}
