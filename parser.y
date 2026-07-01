%{

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int yylineno;
extern int coluna_inicial;
extern FILE *yyin;

void yyerror(const char *s);
int yylex(void);

#define HASH_SIZE 1024
#define MAX_PARAMS 16

/* --- Constantes de Tipos e Categorias --- */
#define TIPO_VOID 0
#define TIPO_INT 1
#define TIPO_FLOAT 2

#define SYM_VAR 1
#define SYM_FUNC 2

/* --- Estrutura da Tabela de Simbolos --- */
typedef struct Simbolo {
    char nome[64];
    int tipo;       
    int categoria;  
    int escopo;     
    int num_params;
    int tipos_params[MAX_PARAMS];
    struct Simbolo *prox;
} Simbolo;

/* --- Assinaturas da API --- */
void abrirEscopo();
void fecharEscopo();
Simbolo* inserir_simbolo(const char *nome, int tipo, int categoria);
Simbolo* buscar_simbolo(const char *nome);
void erro_semantico(const char *msg);

/* --- Protótipos auxiliares --- */
void gerar_temp(char *buffer);
void gerar_label(char *buffer);
int promover(int t1, int t2);
void validar_chamada(Simbolo *s, const char *nome, int *tipos_args, int num_args);

/* --- Variaveis Globais --- */
Simbolo *tabela[HASH_SIZE] = {NULL};
int escopo_atual = 0;
int temp_count = 1;
int label_count = 1;
int tipo_atual = TIPO_VOID;

int params_buffer[MAX_PARAMS];
int params_buffer_count = 0;

Simbolo *func_em_declaracao = NULL;

int args_buffer[MAX_PARAMS];
int args_buffer_count = 0;

%}

 /* Tokens */
%code requires {
#define MAX_CODE 4096
}

%union {
    char str[64];
    int tipo;
    struct {
        char place[64];
        char code[MAX_CODE];
        int tipo;
    } expr;
    struct {
        char code[MAX_CODE];
    } cmd;
}

%token INT FLOAT
%token <str> ID NUM_INT NUM_DEC

%type <tipo> tipo
%type <expr> expressao argumentos parametros parametro chamada_func
%type <cmd> comando lista_comandos bloco comando_if comando_while atribuicao io_stmt declaracao lista_decl_itens decl_item

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
    : lista_comandos {
        printf("\n===== CODIGO INTERMEDIARIO =====\n");
        printf("%s", $1.code);
    }
    ;

lista_comandos
    : comando {
        strncpy($$.code, $1.code, MAX_CODE - 1);
        $$.code[MAX_CODE - 1] = '\0';
    }
    | lista_comandos comando {
        snprintf($$.code, MAX_CODE, "%s%s", $1.code, $2.code);
    }
    ;

comando
    : declaracao SEMICOLON
    | tipo ID LPAREN {
        func_em_declaracao = inserir_simbolo($2, $1, SYM_FUNC);
        if (func_em_declaracao == NULL) erro_semantico("Funcao redeclarada");
        params_buffer_count = 0;
        abrirEscopo(); /* Abre o escopo para capturar os parametros */
    } parametros RPAREN {
        if (func_em_declaracao != NULL) {
            func_em_declaracao->num_params = params_buffer_count;
            for (int i = 0; i < params_buffer_count; i++) {
                func_em_declaracao->tipos_params[i] = params_buffer[i];
            }
        }
    } LBRACE lista_comandos RBRACE {
        snprintf($$.code, MAX_CODE, "%s:\n%s", $2, $9.code);
        fecharEscopo();
    }
    | tipo ID LPAREN {
        func_em_declaracao = inserir_simbolo($2, $1, SYM_FUNC);
        if (func_em_declaracao == NULL) erro_semantico("Funcao redeclarada");
        if (func_em_declaracao != NULL) func_em_declaracao->num_params = 0;
        abrirEscopo(); 
    } RPAREN LBRACE lista_comandos RBRACE {
        snprintf($$.code, MAX_CODE, "%s:\n%s", $2, $7.code);
        fecharEscopo();
    }
    | tipo ID LPAREN {
        func_em_declaracao = inserir_simbolo($2, $1, SYM_FUNC);
        if (func_em_declaracao == NULL) erro_semantico("Funcao redeclarada");
        params_buffer_count = 0;
        abrirEscopo();
    } parametros RPAREN {
        if (func_em_declaracao != NULL) {
            func_em_declaracao->num_params = params_buffer_count;
            for (int i = 0; i < params_buffer_count; i++) {
                func_em_declaracao->tipos_params[i] = params_buffer[i];
            }
        }
    } LBRACE RBRACE {
        snprintf($$.code, MAX_CODE, "%s:\n", $2);
        fecharEscopo();
    }
    | tipo ID LPAREN {
        func_em_declaracao = inserir_simbolo($2, $1, SYM_FUNC);
        if (func_em_declaracao == NULL) erro_semantico("Funcao redeclarada");
        if (func_em_declaracao != NULL) func_em_declaracao->num_params = 0;
        abrirEscopo(); 
    } RPAREN LBRACE RBRACE {
        snprintf($$.code, MAX_CODE, "%s:\n", $2);
        fecharEscopo();
    }
    | RETURN expressao SEMICOLON {
        snprintf($$.code, MAX_CODE, "%s\treturn %s\n", $2.code, $2.place);
    }
    | atribuicao SEMICOLON
    | comando_if
    | comando_while
    | bloco
    | io_stmt
    | chamada_func SEMICOLON {
        strncpy($$.code, $1.code, MAX_CODE - 1);
        $$.code[MAX_CODE - 1] = '\0';
    }
    | error SEMICOLON       { $$.code[0] = '\0'; yyerrok; } /* Recuperacao de Erro (Panic Mode) */
    ;

bloco
    : LBRACE { abrirEscopo(); } lista_comandos RBRACE {
        strncpy($$.code, $3.code, MAX_CODE - 1);
        $$.code[MAX_CODE - 1] = '\0';
        fecharEscopo();
    }
    | LBRACE { abrirEscopo(); } RBRACE {
        $$.code[0] = '\0';
        fecharEscopo();
    }
    ;

comando_if
 /* Resolve a ambiguidade do Dangling Else */
    : IF LPAREN expressao RPAREN comando %prec LOWER_THAN_ELSE {
        char lbl_fim[64];
        gerar_label(lbl_fim);
        if ($3.tipo == TIPO_VOID) {
            erro_semantico("Condicao do if deve ser numerica");
        }
        
        snprintf($$.code, MAX_CODE, 
        "%s \tifFalse %s goto %s\n %s%s:\n",
        $3.code, $3.place, lbl_fim, $5.code, lbl_fim);
    }
    | IF LPAREN expressao RPAREN comando ELSE comando {
        char lbl_else[64];
        char lbl_fim[64];

        gerar_label(lbl_else);
        gerar_label(lbl_fim);
        if ($3.tipo == TIPO_VOID) {
            erro_semantico("Condicao do if/else deve ser numerica");
        }

        snprintf($$.code, MAX_CODE, 
        "%s \tifFalse %s goto %s\n %s \tgoto %s\n %s:\n %s%s:\n",
        $3.code, $3.place, lbl_else, $5.code, lbl_fim, lbl_else, $7.code, lbl_fim);
    } 
    ;

comando_while
    : WHILE LPAREN expressao RPAREN comando {
        char lbl_inicio[64];
        char lbl_fim[64];

        gerar_label(lbl_inicio);
        gerar_label(lbl_fim);

        if ($3.tipo == TIPO_VOID) {
            erro_semantico("Condicao do while deve ser numerica");
        }

        snprintf($$.code, MAX_CODE,
                "%s:\n %s \tifFalse %s goto %s\n %s \tgoto %s\n%s:\n",
                lbl_inicio, $3.code, $3.place, lbl_fim, $5.code, lbl_inicio, lbl_fim);
    }
    ;

 /* Tipos suportados pela linguagem */
tipo
    : INT {
        tipo_atual = TIPO_INT;
        $$ = TIPO_INT;
    }
    | FLOAT {
        tipo_atual = TIPO_FLOAT;
        $$ = TIPO_FLOAT;
    }
    ;

 /* Declaracao de variaveis apenas */
declaracao
    : tipo lista_decl_itens {
        strncpy($$.code, $2.code, MAX_CODE - 1);
        $$.code[MAX_CODE - 1] = '\0';
    }
    ;

lista_decl_itens
    : decl_item {
        strncpy($$.code, $1.code, MAX_CODE - 1);
        $$.code[MAX_CODE - 1] = '\0';
    }
    | lista_decl_itens COMMA decl_item {
        snprintf($$.code, MAX_CODE, "%s%s", $1.code, $3.code);
    }
    ;

decl_item
    : ID {
        if (inserir_simbolo($1, tipo_atual, SYM_VAR) == NULL) {
            erro_semantico("Variavel redeclarada no mesmo escopo");
        }
        $$.code[0] = '\0';
    }
    | ID ASSIGN expressao {
        if (inserir_simbolo($1, tipo_atual, SYM_VAR) == NULL) {
            erro_semantico("Variavel redeclarada no mesmo escopo");
        }

        char cod_expr[MAX_CODE];
        char place_expr[64];
        strncpy(cod_expr, $3.code, MAX_CODE - 1); cod_expr[MAX_CODE - 1] = '\0';
        strncpy(place_expr, $3.place, 63); place_expr[63] = '\0';

        if (tipo_atual != $3.tipo) {
            if (tipo_atual == TIPO_FLOAT && $3.tipo == TIPO_INT) {
                char tmp[64];
                gerar_temp(tmp);
                snprintf(cod_expr + strlen(cod_expr), MAX_CODE - strlen(cod_expr),
                         "\t%s = (float)%s\n", tmp, place_expr);
                strncpy(place_expr, tmp, 63); place_expr[63] = '\0';
            } else {
                erro_semantico("Tipo incompativel na inicializacao da variavel");
            }
        }

        snprintf($$.code, MAX_CODE, "%s\t%s = %s\n", cod_expr, $1, place_expr);
    }
    ;

 /* Atribuicao simples */

atribuicao
    : ID ASSIGN expressao {
        Simbolo *s = buscar_simbolo($1);
        char cod_expr[MAX_CODE];
        char place_expr[64];
        strncpy(cod_expr, $3.code, MAX_CODE - 1); cod_expr[MAX_CODE - 1] = '\0';
        strncpy(place_expr, $3.place, 63); place_expr[63] = '\0';

        if (!s) {
            erro_semantico("Variavel nao declarada");
        } else if (s->tipo != $3.tipo) {
            if (s->tipo == TIPO_FLOAT && $3.tipo == TIPO_INT) {
                char tmp[64];
                gerar_temp(tmp);
                snprintf(cod_expr + strlen(cod_expr), MAX_CODE - strlen(cod_expr),
                         "\t%s = (float)%s\n", tmp, place_expr);
                strncpy(place_expr, tmp, 63); place_expr[63] = '\0';
            } else {
                erro_semantico("Tipos incompativeis na atribuicao");
            }
        }

        snprintf($$.code, MAX_CODE, "%s\t%s = %s\n", cod_expr, $1, place_expr);
    }
    ;
expressao
    /* ── Aritméticas ── */
    : expressao PLUS expressao {
        int tipo_res = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';

        if (tipo_res == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_res == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s + %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = tipo_res;
    }
    | expressao MINUS expressao {
        int tipo_res = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';
        if (tipo_res == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_res == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s - %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = tipo_res;
    }
    | expressao MULT expressao {
        int tipo_res = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';

        if (tipo_res == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_res == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s * %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = tipo_res;
    }
    | expressao DIV expressao {
        int tipo_res = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';

        if (tipo_res == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_res == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s / %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = tipo_res;
    }
    | expressao MOD expressao {
        if ($1.tipo != TIPO_INT || $3.tipo != TIPO_INT) {
            erro_semantico("Operador modulo (%%) requer operandos inteiros");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s %% %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }

    /* ── Lógicas ── */
    | expressao AND expressao {
        char log_esq[64];
        gerar_temp(log_esq);
        char lbl_avalia_dir[64], lbl_fim[64];
        gerar_label(lbl_avalia_dir);
        gerar_label(lbl_fim);
        char temp[64];
        gerar_temp(temp);

        snprintf($$.code, MAX_CODE,
                 "%s\t%s = %s != 0\n\tif %s goto %s\n\t%s = 0\n\tgoto %s\n%s:\n%s\t%s = %s != 0\n%s:\n",
                 $1.code, log_esq, $1.place,
                 log_esq, lbl_avalia_dir,
                 temp,
                 lbl_fim,
                 lbl_avalia_dir,
                 $3.code, temp, $3.place,
                 lbl_fim);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }
    | expressao OR expressao {
        char log_esq[64];
        gerar_temp(log_esq);
        char lbl_avalia_dir[64], lbl_fim[64];
        gerar_label(lbl_avalia_dir);
        gerar_label(lbl_fim);
        char temp[64];
        gerar_temp(temp);

        char lbl_curto[64];
        gerar_label(lbl_curto);
        snprintf($$.code, MAX_CODE,
                 "%s\t%s = %s != 0\n\tif %s goto %s\n\tgoto %s\n%s:\n\t%s = 1\n\tgoto %s\n%s:\n%s\t%s = %s != 0\n%s:\n",
                 $1.code, log_esq, $1.place,
                 log_esq, lbl_curto,
                 lbl_avalia_dir,
                 lbl_curto,
                 temp,
                 lbl_fim,
                 lbl_avalia_dir,
                 $3.code, temp, $3.place,
                 lbl_fim);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }

    /* ── Relacionais ── */
    | expressao EQ expressao {
        int tipo_cmp = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';
        if (tipo_cmp == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_cmp == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s == %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }
    | expressao NE expressao {
        int tipo_cmp = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';
        if (tipo_cmp == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_cmp == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s != %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }
    | expressao LT expressao {
        int tipo_cmp = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';
        if (tipo_cmp == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_cmp == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s < %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }
    | expressao LE expressao {
        int tipo_cmp = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';
        if (tipo_cmp == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_cmp == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s <= %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }
    | expressao GT expressao {
        int tipo_cmp = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';
        if (tipo_cmp == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_cmp == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s > %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }
    | expressao GE expressao {
        int tipo_cmp = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strncpy(cod_esq, $1.code, MAX_CODE - 1); cod_esq[MAX_CODE - 1] = '\0';
        strncpy(cod_dir, $3.code, MAX_CODE - 1); cod_dir[MAX_CODE - 1] = '\0';
        strncpy(place_esq, $1.place, 63); place_esq[63] = '\0';
        strncpy(place_dir, $3.place, 63); place_dir[63] = '\0';
        if (tipo_cmp == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE - strlen(cod_esq), "\t%s = (float)%s\n", tmp2, place_esq);
            strncpy(place_esq, tmp2, 63); place_esq[63] = '\0';
        }
        if (tipo_cmp == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE - strlen(cod_dir), "\t%s = (float)%s\n", tmp2, place_dir);
            strncpy(place_dir, tmp2, 63); place_dir[63] = '\0';
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s >= %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }

    /* ── Unárias ── */
    | NOT expressao {
        char cod[MAX_CODE];
        strncpy(cod, $2.code, MAX_CODE - 1); cod[MAX_CODE - 1] = '\0';

        char log_temp[64];
        gerar_temp(log_temp);
        snprintf(cod + strlen(cod), MAX_CODE - strlen(cod), "\t%s = %s != 0\n", log_temp, $2.place);

        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s\t%s = !%s\n", cod, temp, log_temp);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }
    | MINUS expressao %prec UMINUS {
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s\t%s = -%s\n", $2.code, temp, $2.place);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = $2.tipo;
    }

    /* ── Agrupamento ── */
    | LPAREN expressao RPAREN {
        strncpy($$.code,  $2.code, MAX_CODE - 1); $$.code[MAX_CODE - 1] = '\0';
        strncpy($$.place, $2.place, 63); $$.place[63] = '\0';
        $$.tipo = $2.tipo;
    }

    /* ── Literais ── */
    | NUM_INT {
        $$.code[0] = '\0';
        strncpy($$.place, $1, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_INT;
    }
    | NUM_DEC {
        $$.code[0] = '\0';
        strncpy($$.place, $1, 63); $$.place[63] = '\0';
        $$.tipo = TIPO_FLOAT;
    }

    /* ── Identificador ── */
    | ID {
        Simbolo *s = buscar_simbolo($1);
        if (!s) {
            erro_semantico("Identificador nao declarado");
            strncpy($$.place, $1, 63); $$.place[63] = '\0';
            $$.code[0] = '\0';
            $$.tipo = TIPO_INT;
        } else {
            strncpy($$.place, $1, 63); $$.place[63] = '\0';
            $$.code[0] = '\0';
            $$.tipo = s->tipo;
        }
    }

    /* ── Chamada de função ── */
    | chamada_func {
        strncpy($$.code,  $1.code, MAX_CODE - 1); $$.code[MAX_CODE - 1] = '\0';
        strncpy($$.place, $1.place, 63); $$.place[63] = '\0';
        $$.tipo = $1.tipo;
    }
    ;

 /* Regras de Funcoes e I/O */

parametros
    : parametro {
        strncpy($$.code, $1.code, MAX_CODE - 1); $$.code[MAX_CODE - 1] = '\0';
        strncpy($$.place, $1.place, 63); $$.place[63] = '\0';
        $$.tipo = $1.tipo;
    }
    | parametros COMMA parametro {
        snprintf($$.code, MAX_CODE, "%s%s", $1.code, $3.code);
        strncpy($$.place, $3.place, 63); $$.place[63] = '\0';
        $$.tipo = $3.tipo;
    }
    ;


parametro
    : tipo ID {
        if (inserir_simbolo($2, $1, SYM_VAR) == NULL) {
            erro_semantico("Parametro redeclarado");
        }
        if (params_buffer_count < MAX_PARAMS) {
            params_buffer[params_buffer_count++] = $1;
        }
        strncpy($$.place, $2, 63); $$.place[63] = '\0';
        $$.code[0] = '\0';
        $$.tipo = $1;
    }
    ;

chamada_func
    : ID LPAREN { args_buffer_count = 0; } argumentos RPAREN {
        Simbolo *s = buscar_simbolo($1);
        if (!s) {
            erro_semantico("Funcao nao declarada");
        } else if (s->categoria != SYM_FUNC) {
            erro_semantico("Identificador nao e uma funcao");
        } else {
            validar_chamada(s, $1, args_buffer, args_buffer_count);
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s\t%s = call %s\n",
                 $4.code, temp, $1);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = s ? s->tipo : TIPO_INT;
    }
    | ID LPAREN RPAREN {
        Simbolo *s = buscar_simbolo($1);
        if (!s) {
            erro_semantico("Funcao nao declarada");
        } else if (s->categoria != SYM_FUNC) {
            erro_semantico("Identificador nao e uma funcao");
        } else {
            validar_chamada(s, $1, NULL, 0);
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "\t%s = call %s\n", temp, $1);
        strncpy($$.place, temp, 63); $$.place[63] = '\0';
        $$.tipo = s ? s->tipo : TIPO_INT;
    }
    ;

argumentos
    : expressao {
        if (args_buffer_count < MAX_PARAMS) {
            args_buffer[args_buffer_count++] = $1.tipo;
        }
        snprintf($$.code, MAX_CODE, "%s\tparam %s\n", $1.code, $1.place);
        strncpy($$.place, $1.place, 63); $$.place[63] = '\0';
        $$.tipo = $1.tipo;
    }
    | argumentos COMMA expressao {
        if (args_buffer_count < MAX_PARAMS) {
            args_buffer[args_buffer_count++] = $3.tipo;
        }
        snprintf($$.code, MAX_CODE, "%s%s\tparam %s\n",
                 $1.code, $3.code, $3.place);
        strncpy($$.place, $3.place, 63); $$.place[63] = '\0';
        $$.tipo = $3.tipo;
    }
    ;

io_stmt
    : PRINT LPAREN expressao RPAREN SEMICOLON {
        snprintf($$.code, MAX_CODE, "%s\tprint %s\n", $3.code, $3.place);
    }
    | READ LPAREN ID RPAREN SEMICOLON {
        Simbolo *s = buscar_simbolo($3);
        if (!s) {
            erro_semantico("Variavel nao declarada");
        } else if (s->categoria != SYM_VAR) {
            erro_semantico("Identificador nao e uma variavel");
        }
        snprintf($$.code, MAX_CODE, "\tread %s\n", $3);
    }
    ;
%%


/* API Tabela de Simbolos, Escopos e Funcoes */

unsigned int hash(const char *str) {
    unsigned int h = 0;
    while (*str) h = (h * 31) + *str++;
    return h % HASH_SIZE;
}

void abrirEscopo() {
    escopo_atual++;
}

void fecharEscopo() {
    for (int i = 0; i < HASH_SIZE; i++) {
        Simbolo *atual = tabela[i];
        Simbolo *ant = NULL;
        
        while (atual != NULL) {
            if (atual->escopo == escopo_atual) {
                Simbolo *remover = atual;
                if (ant == NULL) tabela[i] = atual->prox;
                else ant->prox = atual->prox;
                atual = atual->prox;
                free(remover);
            } else {
                ant = atual;
                atual = atual->prox;
            }
        }
    }
    escopo_atual--;
}

Simbolo* inserir_simbolo(const char *nome, int tipo, int categoria) {
    unsigned int idx = hash(nome);
    Simbolo *atual = tabela[idx];
    
    /* Verifica se ja existe NO MESMO ESCOPO */
    while (atual != NULL) {
        if (strcmp(atual->nome, nome) == 0 && atual->escopo == escopo_atual) {
            return NULL; /* Erro: redeclarado no mesmo escopo */
        }
        atual = atual->prox;
    }
    
    Simbolo *novo = malloc(sizeof(Simbolo));
    strncpy(novo->nome, nome, 63);
    novo->nome[63] = '\0';
    novo->tipo = tipo;
    novo->categoria = categoria; /* SYM_VAR ou SYM_FUNC */
    novo->escopo = escopo_atual;
    novo->num_params = 0;
    
    novo->prox = tabela[idx];
    tabela[idx] = novo;
    
    return novo;
}

Simbolo* buscar_simbolo(const char *nome) {
    unsigned int idx = hash(nome);
    Simbolo *atual = tabela[idx];
    Simbolo *melhor = NULL;
    
    /* Busca a declaracao mais profunda (escopo mais interno) */
    while (atual != NULL) {
        if (strcmp(atual->nome, nome) == 0) {
            if (!melhor || atual->escopo > melhor->escopo) {
                melhor = atual;
            }
        }
        atual = atual->prox;
    }
    return melhor;
}

void erro_semantico(const char *msg) {
    fprintf(stderr, "ERRO SEMANTICO: %s na Linha %d, Coluna %d\n", 
            msg, yylineno, coluna_inicial);
}

 /* Funcoes Auxiliares em C */

 /* Relato de erros sintaticos com posicao */
void yyerror(const char *s) {
    fprintf(stderr, "ERRO SINTATICO: %s na Linha %d, Coluna %d\n",
            s, yylineno, coluna_inicial);
}

/* Funcoes Auxiliares (IR) */
void gerar_temp(char *buffer) {
    sprintf(buffer, "t%d", temp_count++);
}
void gerar_label(char *buffer) {
    sprintf(buffer, "L%d", label_count++);
}
int promover(int t1, int t2) {
    if (t1 == TIPO_FLOAT || t2 == TIPO_FLOAT) return TIPO_FLOAT;
    return TIPO_INT;
}

/* Valida aridade e tipo dos argumentos contra a assinatura da funcao. */
void validar_chamada(Simbolo *s, const char *nome, int *tipos_args, int num_args) {
    if (num_args != s->num_params) {
        char msg[128];
        snprintf(msg, sizeof(msg),
                 "Funcao '%s' espera %d argumento(s), mas recebeu %d",
                 nome, s->num_params, num_args);
        erro_semantico(msg);
        return;
    }
    for (int i = 0; i < num_args; i++) {
        int esperado = s->tipos_params[i];
        int recebido = tipos_args[i];
        if (esperado != recebido &&
            !(esperado == TIPO_FLOAT && recebido == TIPO_INT)) {
            char msg[128];
            snprintf(msg, sizeof(msg),
                     "Funcao '%s': tipo incompativel no argumento %d",
                     nome, i + 1);
            erro_semantico(msg);
        }
    }
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

    return 0;
}
