%{
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define MAX_SYMBOLS 4096
#define MAX_CHAR 64

int coluna = 1;
int coluna_inicial = 1;

 /* Atualiza a contagem de colunas antes de cada acao */
#define YY_USER_ACTION { coluna_inicial = coluna; coluna += yyleng; }

 /* Estrutura da Tabela de Simbolos */
typedef struct {
    char nome[MAX_CHAR];
    int primeira_linha;
    int primeira_coluna;
} Simbolo;

Simbolo tabela[MAX_SYMBOLS];
int num_simbolos = 0;

 /* Funcao para a insercao de ID na tabela */
int inserir_simbolo(const char *nome, int linha, int col) {
    for (int i = 0; i < num_simbolos; i++) {
        if (strcmp(tabela[i].nome, nome) == 0) {
            return i; /* Retorna posicao se ja existir */
        }
    }
    if (num_simbolos < MAX_SYMBOLS) {
        strncpy(tabela[num_simbolos].nome, nome, MAX_CHAR - 1);
        tabela[num_simbolos].nome[MAX_CHAR - 1] = '\0';
        tabela[num_simbolos].primeira_linha = linha;
        tabela[num_simbolos].primeira_coluna = col;
        return num_simbolos++;
    }
    return -1;
}

%}

 /* Definicoes Regulares */
WS              [ \t]+
DIGITO          [0-9]
LETRA           [a-zA-Z]
INTEIRO         -?{DIGITO}+
DECIMAL         -?{DIGITO}+\.{DIGITO}+
ID              {LETRA}({LETRA}|{DIGITO}|_)*
NEWLINE         \n
LINE_COMMENT    "//".*
OTHER           .

%option noyywrap
%option yylineno

%%

{WS}            ; /* Ignora espacos e tabs */
{LINE_COMMENT}  ; /* Comentario de linha unica */
{NEWLINE}       { coluna = 1; fprintf(yyout, "\n"); }

"/*"([^*]|\*+[^*/])*\*+"/" ;  /* Tratamento de comentario em bloco */
 /* Palavras Reservadas */
"int"           { fprintf(yyout, "<INT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"float"         { fprintf(yyout, "<FLOAT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"if"            { fprintf(yyout, "<IF, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"else"          { fprintf(yyout, "<ELSE, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"while"         { fprintf(yyout, "<WHILE, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"read"          { fprintf(yyout, "<READ, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"print"         { fprintf(yyout, "<PRINT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }

 /* Identificadores e Constantes */
{ID}            { 
                    int pos = inserir_simbolo(yytext, yylineno, coluna_inicial); 
                    fprintf(yyout, "<ID, %s, Pos:%d> [%d, %d] ", yytext, pos, yylineno, coluna_inicial); 
                }

{DECIMAL}       { fprintf(yyout, "<NUM_DEC, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
{INTEIRO}       { fprintf(yyout, "<NUM_INT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }

 /* Operadores Aritmeticos */
"="             { fprintf(yyout, "<ASSIGN, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"+"             { fprintf(yyout, "<PLUS, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"-"             { fprintf(yyout, "<MINUS, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"*"             { fprintf(yyout, "<MULT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"/"             { fprintf(yyout, "<DIV, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"%"             { fprintf(yyout, "<MOD, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }

 /* Operadores logicos */
"&&"            { fprintf(yyout, "<AND, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"||"            { fprintf(yyout, "<OR, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }

 /* Operadores relacionais */
"!"             { fprintf(yyout, "<NOT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"=="            { fprintf(yyout, "<EQ, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"!="            { fprintf(yyout, "<NE, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"<="            { fprintf(yyout, "<LE, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
">="            { fprintf(yyout, "<GE, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
"<"             { fprintf(yyout, "<LT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }
">"             { fprintf(yyout, "<GT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }

 /* Pontuacao */
"("|")"|"{"|"}"|","|";" { fprintf(yyout, "<PONT, %s> [%d, %d] ", yytext, yylineno, coluna_inicial); }

 /* Erro Lexico */
{OTHER}         { fprintf(yyout, "\nERRO LEXICO: '%s' na Linha %d, Coluna %d\n", yytext, yylineno, coluna_inicial); }

%%

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s arquivo_entrada\n", argv[0]);
        return 1;
    }

    FILE *f_in = fopen(argv[1], "r");
    if (!f_in) {
        perror("Erro ao abrir arquivo de entrada");
        return 1;
    }

    /* Redirecionamento da saida para arquivo txt */
    FILE *f_out = fopen("saida.txt", "w");
    if (!f_out) {
        perror("Erro ao criar saida.txt");
        fclose(f_in);
        return 1;
    }

    yyin = f_in;
    yyout = f_out; 
    
    yylex();

    /* Escrita da Tabela no arquivo de saida */
    fprintf(yyout, "\n\n=== TABELA DE SIMBOLOS ===\n");
    fprintf(yyout, "%-20s %-9s %-9s\n", "Identificador", "Linha", "Coluna");
    fprintf(yyout, "------------------------------------------------\n");
    for (int i = 0; i < num_simbolos; i++) {
        fprintf(yyout, "%-20s %-9d %-9d\n", tabela[i].nome, tabela[i].primeira_linha, tabela[i].primeira_coluna);
    }
    
    fclose(f_in);
    fclose(f_out);
    
    printf("Lexer finalizado. Resultados salvos em 'saida.txt'.\n");

    return 0;
}