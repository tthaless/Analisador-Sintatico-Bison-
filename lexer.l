%{
#include "parser.tab.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define MAX_SYMBOLS 4096
#define MAX_CHAR 64
#define HASH_SIZE 1024

 /* Desativa os warnings gerados pelo codigo automatico do Flex */
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wunused-label"

int coluna = 1;
int coluna_inicial = 1;

 /* Atualiza a contagem de colunas antes de cada acao */

#define YY_USER_ACTION { coluna_inicial = coluna; coluna += yyleng; }

 /* Estrutura da Tabela de Simbolos */
typedef struct Simbolo {
    char nome[MAX_CHAR];
    int primeira_linha;
    int primeira_coluna;

    /* Proximo simbolo da lista encadeada */
    struct Simbolo *prox;
} Simbolo;

 /* Tabela hash */
Simbolo *tabela_hash[HASH_SIZE] = {NULL};
int num_simbolos = 0;

unsigned int hash(const char *str) {
    unsigned int h = 0;

    while (*str) {
        h = (h * 31) + *str;
        str++;
    }

    return h % HASH_SIZE;
}

 /* Funcao para a insercao de ID na tabela */
 int inserir_simbolo(const char *nome, int linha, int col) {

    unsigned int indice = hash(nome);

    /* procura se ja existe */
    Simbolo *atual = tabela_hash[indice];

    while (atual != NULL) {
        if (strcmp(atual->nome, nome) == 0) {
            return 1; /* ja existe */
        }

        atual = atual->prox;
    }

    /* cria novo simbolo */
    Simbolo *novo = malloc(sizeof(Simbolo));

    if (!novo) {
        return -1;
    }

    strncpy(novo->nome, nome, MAX_CHAR - 1);
    novo->nome[MAX_CHAR - 1] = '\0';

    novo->primeira_linha = linha;
    novo->primeira_coluna = col;

    /* insercao no inicio da lista */
    novo->prox = tabela_hash[indice];
    tabela_hash[indice] = novo;

    num_simbolos++;

    return 0;
}

 /* Funcao para impressao da Tabela de Simbolos */
void imprimir_tabela() {
    printf("\n=== TABELA DE SIMBOLOS ===\n");
    printf("%-20s %-9s %-9s\n", "Identificador", "Linha", "Coluna");
    printf("------------------------------------------------\n");
    for (int i = 0; i < HASH_SIZE; i++) {

        Simbolo *atual = tabela_hash[i];

        while (atual != NULL) {

            printf("%-20s %-9d %-9d\n",
                atual->nome,
                atual->primeira_linha,
                atual->primeira_coluna);

            atual = atual->prox;
        }
    }
}

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
{ID}            {
                    inserir_simbolo(yytext, yylineno, coluna_inicial);
                    return ID;
                }

 /* Constantes Numericas */
{DECIMAL}       { return NUM_DEC; }
{INTEIRO}       { return NUM_INT; }

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
