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
#define MAX_CODE 4096

/* --- Constantes de Tipos e Categorias --- */
#define TIPO_VOID 0
#define TIPO_INT 1
#define TIPO_FLOAT 2

#define SYM_VAR 1
#define SYM_FUNC 2

/* --- Nova Estrutura da Tabela de Simbolos --- */
typedef struct Simbolo {
    char nome[64];
    int tipo;       
    int categoria;  
    int escopo;     
    struct Simbolo *prox;
} Simbolo;

/* --- Assinaturas da API --- */
void abrirEscopo();
void fecharEscopo();
Simbolo* inserir_simbolo(const char *nome, int tipo, int categoria);
Simbolo* buscar_simbolo(const char *nome);
void erro_semantico(const char *msg);

/* --- Variaveis Globais --- */
Simbolo *tabela[HASH_SIZE] = {NULL};
int escopo_atual = 0;
int temp_count = 1;
int tipo_atual = TIPO_VOID;

void gerar_temp(char *buffer) {
    sprintf(buffer, "t%d", temp_count++);
}
%}

 /* Tokens */

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
%type <expr> expressao argumentos parametros parametro
%type <cmd> comando lista_comandos bloco comando_if comando_while atribuicao io_stmt declaracao lista_decl_itens decl_item chamada_func

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
    : comando {
        strcpy($$.code, $1.code);
    }
    | lista_comandos comando {
        snprintf($$.code, MAX_CODE, "%s%s", $1.code, $2.code);
    }
    ;

comando
    : declaracao SEMICOLON
    | tipo ID LPAREN {
        if (inserir_simbolo($2, $1, SYM_FUNC) == NULL) erro_semantico("Funcao redeclarada");
        abrirEscopo(); /* Abre o escopo para capturar os parametros */
    } parametros RPAREN LBRACE lista_comandos RBRACE {
        snprintf($$.code, MAX_CODE, "%s:\n%s", $2, $8.code);
        fecharEscopo();
    }
    | tipo ID LPAREN {
        if (inserir_simbolo($2, $1, SYM_FUNC) == NULL) erro_semantico("Funcao redeclarada");
        abrirEscopo(); 
    } RPAREN LBRACE lista_comandos RBRACE {
        snprintf($$.code, MAX_CODE, "%s:\n%s", $2, $7.code);
        fecharEscopo();
    }
    | tipo ID LPAREN {
        if (inserir_simbolo($2, $1, SYM_FUNC) == NULL) erro_semantico("Funcao redeclarada");
        abrirEscopo();
    } parametros RPAREN LBRACE RBRACE {
        snprintf($$.code, MAX_CODE, "%s:\n", $2);
        fecharEscopo();
    }
    | tipo ID LPAREN {
        if (inserir_simbolo($2, $1, SYM_FUNC) == NULL) erro_semantico("Funcao redeclarada");
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
    | chamada_func SEMICOLON
    | error SEMICOLON       { yyerrok; } /* Recuperacao de Erro (Panic Mode) */
    ;

bloco
    : LBRACE { abrirEscopo(); } lista_comandos RBRACE {
        strcpy($$.code, $3.code);
        fecharEscopo();
    }
    | LBRACE { abrirEscopo(); } RBRACE {
        strcpy($$.code, "");
        fecharEscopo();
    }
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
    : INT   { $$ = TIPO_INT; }
    | FLOAT { $$ = TIPO_FLOAT; }
    ;

 /* Declaracao de variaveis apenas */
declaracao
    : tipo { tipo_atual = $1; } lista_decl_itens {
        strcpy($$.code, $3.code);
    }
    ;

lista_decl_itens
    : decl_item {
        strcpy($$.code, $1.code);
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
        strcpy($$.code, "");
    }
    | ID ASSIGN expressao {
        if (inserir_simbolo($1, tipo_atual, SYM_VAR) == NULL) {
            erro_semantico("Variavel redeclarada no mesmo escopo");
        }
        /* O Integrante 3 adicionara o IR da atribuicao aqui depois */
        strcpy($$.code, "");
    }
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
    : parametro {
        strcpy($$.code, $1.code);
        strcpy($$.place, $1.place);
        $$.tipo = $1.tipo;
    }
    | parametros COMMA parametro {
        snprintf($$.code, MAX_CODE, "%s%s", $1.code, $3.code);
        strcpy($$.place, $3.place);
        $$.tipo = $3.tipo;
    }
    ;


parametro
    : tipo ID {
        if (inserir_simbolo($2, $1, SYM_VAR) == NULL) {
            erro_semantico("Parametro redeclarado");
        }
        strcpy($$.place, $2);
        strcpy($$.code, "");
        $$.tipo = $1;
    }
    ;

chamada_func
    : ID LPAREN argumentos RPAREN {
        Simbolo *s = buscar_simbolo($1);
        if (!s) erro_semantico("Funcao nao declarada");
        else if (s->categoria != SYM_FUNC) erro_semantico("Identificador nao e uma funcao");
        $$.tipo = s ? s->tipo : TIPO_INT;
        strcpy($$.place, "");   /* Int. 2 preenche */
        strcpy($$.code, "");    /* Int. 2 preenche */
    }
    | ID LPAREN RPAREN {
        Simbolo *s = buscar_simbolo($1);
        if (!s) erro_semantico("Funcao nao declarada");
        else if (s->categoria != SYM_FUNC) erro_semantico("Identificador nao e uma funcao");
        $$.tipo = s ? s->tipo : TIPO_INT;
        strcpy($$.place, "");   /* Int. 2 preenche */
        strcpy($$.code, "");    /* Int. 2 preenche */
    }
    ;

argumentos
    : expressao {
        strcpy($$.code, $1.code);
        strcpy($$.place, $1.place);
        $$.tipo = $1.tipo;
    }
    | argumentos COMMA expressao {
        snprintf($$.code, MAX_CODE, "%s%s", $1.code, $3.code);
        strcpy($$.place, $3.place);
        $$.tipo = $3.tipo;
    }
    ;

io_stmt
    : PRINT LPAREN expressao RPAREN SEMICOLON
    | READ LPAREN ID RPAREN SEMICOLON
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
    strcpy(novo->nome, nome);
    novo->tipo = tipo;
    novo->categoria = categoria; /* SYM_VAR ou SYM_FUNC */
    novo->escopo = escopo_atual;
    
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
