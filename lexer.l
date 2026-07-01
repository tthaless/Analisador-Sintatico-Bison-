%{
#include "parser.tab.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-label"

int coluna = 1;
int coluna_inicial = 1;

#define YY_USER_ACTION { coluna_inicial = coluna; coluna += yyleng; }
%}

 /* Definicoes Regulares */
WS              [ \t]+
DIGITO          [0-9]
LETRA           [a-zA-Z]
INTEIRO         {DIGITO}+
DECIMAL         {DIGITO}+\.{DIGITO}+
ID              {LETRA}({LETRA}|{DIGITO}|_)*
NEWLINE         \n
LINE_COMMENT    "//".*
OTHER           .

%option noyywrap
%option yylineno
%option nounput
%option noinput

%%

{WS}            ; /* Ignora espacos e tabs */
{LINE_COMMENT}  ; /* Comentario de linha unica */
{NEWLINE}       { coluna = 1; }

"/*"([^*]|\*+[^*/])*\*+"/" ; /* Tratamento de comentario em bloco */

 /* Palavras Reservadas */
"int"           { return INT; }
"float"         { return FLOAT; }
"if"            { return IF; }
"else"          { return ELSE; }
"while"         { return WHILE; }
"read"          { return READ; }
"print"         { return PRINT; }
"return"        { return RETURN; }

  /* Identificadores */
{ID}      { strcpy(yylval.str, yytext); return ID; }
{DECIMAL} { strcpy(yylval.str, yytext); return NUM_DEC; }
{INTEIRO} { strcpy(yylval.str, yytext); return NUM_INT; }

 /* Operadores Aritmeticos */
"="             { return ASSIGN; }
"+"             { return PLUS; }
"-"             { return MINUS; }
"*"             { return MULT; }
"/"             { return DIV; }
"%"             { return MOD; }

 /* Operadores Logicos */
"&&"            { return AND; }
"||"            { return OR; }

 /* Operadores Relacionais */
"!"             { return NOT; }
"=="            { return EQ; }
"!="            { return NE; }
"<="            { return LE; }
">="            { return GE; }
"<"             { return LT; }
">"             { return GT; }

 /* Pontuacao */
"("             { return LPAREN; }
")"             { return RPAREN; }
"{"             { return LBRACE; }
"}"             { return RBRACE; }
","             { return COMMA; }
";"             { return SEMICOLON; }

 /* Erro Lexico */
{OTHER}         {
                    fprintf(stderr,
                        "\nERRO LEXICO: '%s' na Linha %d, Coluna %d\n",
                        yytext, yylineno, coluna_inicial);
                }

%%
