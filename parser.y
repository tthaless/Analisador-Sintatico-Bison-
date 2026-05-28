%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

 /* Variaveis de posicao declaradas no lexico.l */
extern int yylineno;
extern int coluna_inicial;

 /* Funcao da tabela de simbolos declarada no lexico.l */
extern void imprimir_tabela();
extern FILE *yyin;

void yyerror(const char *s);
int yylex(void);
%}

 /* Tokens */

%token INT FLOAT
%token ID NUM_INT NUM_DEC
%token IF ELSE WHILE READ PRINT RETURN
%token PLUS MINUS MULT DIV MOD
%token AND OR NOT
%token EQ NE LT LE GT GE
%token ASSIGN
%token LPAREN RPAREN LBRACE RBRACE COMMA SEMICOLON

 /* Precedencia e Associatividade */

%left OR
%left AND
%left EQ NE
%left LT LE GT GE
%left PLUS MINUS
%left MULT DIV MOD
%precedence NOT
%precedence UMINUS /* Precedencia maxima para o operador de inversao de sinal (-) */

 /* Regras de precedencia ficticias para resolver o conflito Shift/Reduce do 'Dangling Else' */
%precedence LOWER_THAN_ELSE
%precedence ELSE

%start programa

%%

 /* Regras da Gramatica (Producao) */

programa
    : lista_comandos
    ;

lista_comandos
    : comando
    | lista_comandos comando
    ;

comando
    : declaracao SEMICOLON
    | tipo ID LPAREN parametros RPAREN bloco
    | tipo ID LPAREN RPAREN bloco
    | atribuicao SEMICOLON
    | comando_if
    | comando_while
    | bloco
    | io_stmt
    | chamada_func SEMICOLON
    | RETURN expressao SEMICOLON
    | error SEMICOLON       { yyerrok; } /* Recuperacao de Erro (Panic Mode) */
    ;

bloco
    : LBRACE lista_comandos RBRACE
    | LBRACE RBRACE
    ;

comando_if
 /* Resolve a ambiguidade do Dangling Else */
    : IF LPAREN expressao RPAREN comando %prec LOWER_THAN_ELSE
    | IF LPAREN expressao RPAREN comando ELSE comando
    ;

comando_while
    : WHILE LPAREN expressao RPAREN comando
    ;

 /* Tipos suportados pela linguagem */
tipo
    : INT
    | FLOAT
    ;

 /* Declaracao de variaveis apenas */
declaracao
    : tipo lista_decl_itens
    ;

lista_decl_itens
    : decl_item
    | lista_decl_itens COMMA decl_item
    ;

decl_item
    : ID
    | ID ASSIGN expressao
    ;

 /* Atribuicao simples */
atribuicao
    : ID ASSIGN expressao
    ;

expressao
    : expressao PLUS expressao
    | expressao MINUS expressao
    | expressao MULT expressao
    | expressao DIV expressao
    | expressao MOD expressao
    | expressao AND expressao
    | expressao OR expressao
    | expressao EQ expressao
    | expressao NE expressao
    | expressao LT expressao
    | expressao LE expressao
    | expressao GT expressao
    | expressao GE expressao
    | NOT expressao
    | MINUS expressao %prec UMINUS /* Forca a precedencia do menos unario */
    | LPAREN expressao RPAREN
    | NUM_INT
    | NUM_DEC
    | ID
    | chamada_func
    ;

 /* Regras de Funcoes e I/O */

parametros
    : parametro
    | parametros COMMA parametro
    ;

parametro
    : tipo ID
    ;

chamada_func
    : ID LPAREN argumentos RPAREN
    | ID LPAREN RPAREN
    ;

argumentos
    : expressao
    | argumentos COMMA expressao
    ;

io_stmt
    : PRINT LPAREN expressao RPAREN SEMICOLON
    | READ LPAREN ID RPAREN SEMICOLON
    ;

%%

 /* Funcoes Auxiliares em C */

 /* Relato de erros sintaticos com posicao */
void yyerror(const char *s) {
    fprintf(stderr, "ERRO SINTATICO: %s na Linha %d, Coluna %d\n",
            s, yylineno, coluna_inicial);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s arquivo_entrada\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("Erro ao abrir arquivo");
        return 1;
    }

    yyin = f;
    yyparse();
    fclose(f);

    printf("\nAnalise sintatica concluida.\n");
    imprimir_tabela();

    return 0;
}
