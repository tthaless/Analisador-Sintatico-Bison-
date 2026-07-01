%{
#include "parser.tab.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* Desativa os warnings gerados pelo código automático do Flex */
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-label"

int coluna = 1;
int coluna_inicial = 1;

/* Atualiza a contagem de colunas antes de cada ação */
#define YY_USER_ACTION { coluna_inicial = coluna; coluna += yyleng; }

%}

/* Definições Regulares */
WS              [ \t]+
DIGITO          [0-9]
LETRA           [a-zA-Z]
INTEIRO         {DIGITO}+
DECIMAL         {DIGITO}+\.{DIGITO}+
ID              {LETRA}({LETRA}|{DIGITO}|_)*
NEWLINE         \n
LINE_COMMENT    "//".*

%option noyywrap
%option yylineno
%option nounput
%option noinput

%%

{WS}            ; /* Ignora espaços e tabs */
{LINE_COMMENT}  ; /* Comentário de linha única */
{NEWLINE}       { coluna = 1; }

"/*"([^*]|\*+[^*/])*\*+"/" ; /* Tratamento de comentário em bloco */

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
{ID}            {
                    yylval.sval = strdup(yytext);
                    return ID;
                }

 /* Constantes Numéricas */
{DECIMAL}       { yylval.sval = strdup(yytext); return NUM_DEC; }
{INTEIRO}       { yylval.sval = strdup(yytext); return NUM_INT; }

 /* Operadores Aritméticos */
"="             { return ASSIGN; }
"+"             { return PLUS; }
"-"             { return MINUS; }
"*"             { return MULT; }
"/"             { return DIV; }
"%"             { return MOD; }

 /* Operadores Lógicos */
"&&"            { return AND; }
"||"            { return OR; }

 /* Operadores Relacionais e Unários */
"!"             { return NOT; }
"=="            { return EQ; }
"!="            { return NE; }
"<="            { return LE; }
">="            { return GE; }
"<"             { return LT; }
">"             { return GT; }

 /* Pontuação */
"("             { return LPAREN; }
")"             { return RPAREN; }
"{"             { return LBRACE; }
"}"             { return RBRACE; }
","             { return COMMA; }
";"             { return SEMICOLON; }

 /* Erro Léxico */
.               {
                    fprintf(stderr, "\nERRO LEXICO: '%s' na Linha %d, Coluna %d\n",
                            yytext, yylineno, coluna_inicial);
                }

%%
