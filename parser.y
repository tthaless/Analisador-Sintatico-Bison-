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
%token IF ELSE WHILE READ PRINT
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
%right NOT
%right UMINUS

%start programa

%%

programa
    : lista_comandos
    ;

lista_comandos
    : comando
    | lista_comandos comando
    ;

comando
    : declaracao SEMICOLON
    | atribuicao SEMICOLON
    | error SEMICOLON       { yyerrok; }
    ;

 /* Tipos suportados pela linguagem */
tipo
    : INT
    | FLOAT
    ;

 /* Declaracao de variaveis
    e inicializacao opcional: int x; int x, y; int x = 10; float f = 2.5; */
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
    : NUM_INT
    | NUM_DEC
    | ID
    ;

%%

 /* Relato de erros sintaticos com posicao
    Usa coluna_inicial pois o Flex ja avancou alem do token no momento do erro */
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
