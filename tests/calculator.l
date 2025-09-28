// Simple calculator lexer

DIGIT    [0-9]
OP       [+\-*/]
WS       [ \t\n]

%%

{DIGIT}+    { printf("NUMBER: %s\n", yytext); }
{OP}        { printf("OPERATOR: %s\n", yytext); }
"("         { printf("LPAREN\n"); }
")"         { printf("RPAREN\n"); }
{WS}        ; // Skip whitespace

%%

int main() {
    yylex();
    return 0;
}
