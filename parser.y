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

/* --- Protótipos auxiliares --- */
void gerar_temp(char *buffer);
void gerar_label(char *buffer);
int promover(int t1, int t2);

/* --- Variaveis Globais --- */
Simbolo *tabela[HASH_SIZE] = {NULL};
int escopo_atual = 0;
int temp_count = 1;
int label_count = 1;
int tipo_atual = TIPO_VOID;

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
    : ID ASSIGN expressao {
        Simbolo *s = buscar_simbolo($1);
        if (!s) {
            erro_semantico("Variavel nao declarada");
        } else if (s->tipo != $3.tipo) {
            if (!(s->tipo == TIPO_FLOAT && $3.tipo == TIPO_INT)) {
                erro_semantico("Tipos incompativeis na atribuicao");
            }
        }
        /* IR da atribuicao fica para o Integrante 3 */
        strcpy($$.code, $3.code);
    }
    ;

expressao
    /* ── Aritméticas ── */
    : expressao PLUS expressao {
        char temp[64];
        gerar_temp(temp);
        int tipo_res = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strcpy(cod_esq, $1.code);
        strcpy(cod_dir, $3.code);
        strcpy(place_esq, $1.place);
        strcpy(place_dir, $3.place);
        if (tipo_res == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE, "\t%s = (float)%s\n", tmp2, place_esq);
            strcpy(place_esq, tmp2);
        }
        if (tipo_res == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE, "\t%s = (float)%s\n", tmp2, place_dir);
            strcpy(place_dir, tmp2);
        }
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s + %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strcpy($$.place, temp);
        $$.tipo = tipo_res;
    }
    | expressao MINUS expressao {
        char temp[64];
        gerar_temp(temp);
        int tipo_res = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strcpy(cod_esq, $1.code);
        strcpy(cod_dir, $3.code);
        strcpy(place_esq, $1.place);
        strcpy(place_dir, $3.place);
        if (tipo_res == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE, "\t%s = (float)%s\n", tmp2, place_esq);
            strcpy(place_esq, tmp2);
        }
        if (tipo_res == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE, "\t%s = (float)%s\n", tmp2, place_dir);
            strcpy(place_dir, tmp2);
        }
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s - %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strcpy($$.place, temp);
        $$.tipo = tipo_res;
    }
    | expressao MULT expressao {
        char temp[64];
        gerar_temp(temp);
        int tipo_res = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strcpy(cod_esq, $1.code);
        strcpy(cod_dir, $3.code);
        strcpy(place_esq, $1.place);
        strcpy(place_dir, $3.place);
        if (tipo_res == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE, "\t%s = (float)%s\n", tmp2, place_esq);
            strcpy(place_esq, tmp2);
        }
        if (tipo_res == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE, "\t%s = (float)%s\n", tmp2, place_dir);
            strcpy(place_dir, tmp2);
        }
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s * %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strcpy($$.place, temp);
        $$.tipo = tipo_res;
    }
    | expressao DIV expressao {
        char temp[64];
        gerar_temp(temp);
        int tipo_res = promover($1.tipo, $3.tipo);
        char cod_esq[MAX_CODE], cod_dir[MAX_CODE];
        char place_esq[64], place_dir[64];
        strcpy(cod_esq, $1.code);
        strcpy(cod_dir, $3.code);
        strcpy(place_esq, $1.place);
        strcpy(place_dir, $3.place);
        if (tipo_res == TIPO_FLOAT && $1.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_esq + strlen(cod_esq), MAX_CODE, "\t%s = (float)%s\n", tmp2, place_esq);
            strcpy(place_esq, tmp2);
        }
        if (tipo_res == TIPO_FLOAT && $3.tipo == TIPO_INT) {
            char tmp2[64]; gerar_temp(tmp2);
            snprintf(cod_dir + strlen(cod_dir), MAX_CODE, "\t%s = (float)%s\n", tmp2, place_dir);
            strcpy(place_dir, tmp2);
        }
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s / %s\n",
                 cod_esq, cod_dir, temp, place_esq, place_dir);
        strcpy($$.place, temp);
        $$.tipo = tipo_res;
    }
    | expressao MOD expressao {
        if ($1.tipo != TIPO_INT || $3.tipo != TIPO_INT) {
            erro_semantico("Operador '%' requer operandos inteiros");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s %% %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }

    /* ── Lógicas ── */
    | expressao AND expressao {
        if ($1.tipo == TIPO_VOID || $3.tipo == TIPO_VOID) {
            erro_semantico("Operador '&&' requer operandos numericos");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s && %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }
    | expressao OR expressao {
        if ($1.tipo == TIPO_VOID || $3.tipo == TIPO_VOID) {
            erro_semantico("Operador '||' requer operandos numericos");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s || %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }

    /* ── Relacionais ── */
    | expressao EQ expressao {
        if ($1.tipo == TIPO_VOID || $3.tipo == TIPO_VOID) {
            erro_semantico("Operador '==' requer operandos numericos");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s == %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }
    | expressao NE expressao {
        if ($1.tipo == TIPO_VOID || $3.tipo == TIPO_VOID) {
            erro_semantico("Operador '!=' requer operandos numericos");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s != %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }
    | expressao LT expressao {
        if ($1.tipo == TIPO_VOID || $3.tipo == TIPO_VOID) {
            erro_semantico("Operador '<' requer operandos numericos");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s < %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }
    | expressao LE expressao {
        if ($1.tipo == TIPO_VOID || $3.tipo == TIPO_VOID) {
            erro_semantico("Operador '<=' requer operandos numericos");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s <= %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }
    | expressao GT expressao {
        if ($1.tipo == TIPO_VOID || $3.tipo == TIPO_VOID) {
            erro_semantico("Operador '>' requer operandos numericos");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s > %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }
    | expressao GE expressao {
        if ($1.tipo == TIPO_VOID || $3.tipo == TIPO_VOID) {
            erro_semantico("Operador '>=' requer operandos numericos");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s%s\t%s = %s >= %s\n",
                 $1.code, $3.code, temp, $1.place, $3.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }

    /* ── Unárias ── */
    | NOT expressao {
        if ($2.tipo == TIPO_VOID) {
            erro_semantico("Operador '!' requer operando numerico");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s\t%s = !%s\n", $2.code, temp, $2.place);
        strcpy($$.place, temp);
        $$.tipo = TIPO_INT;
    }
    | MINUS expressao %prec UMINUS {
        if ($2.tipo == TIPO_VOID) {
            erro_semantico("Operador unario '-' requer operando numerico");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s\t%s = -%s\n", $2.code, temp, $2.place);
        strcpy($$.place, temp);
        $$.tipo = $2.tipo;
    }

    /* ── Agrupamento ── */
    | LPAREN expressao RPAREN {
        strcpy($$.code,  $2.code);
        strcpy($$.place, $2.place);
        $$.tipo = $2.tipo;
    }

    /* ── Literais ── */
    | NUM_INT {
        strcpy($$.code, "");
        strcpy($$.place, $1);
        $$.tipo = TIPO_INT;
    }
    | NUM_DEC {
        strcpy($$.code, "");
        strcpy($$.place, $1);
        $$.tipo = TIPO_FLOAT;
    }

    /* ── Identificador ── */
    | ID {
        Simbolo *s = buscar_simbolo($1);
        if (!s) {
            erro_semantico("Identificador nao declarado");
            strcpy($$.place, $1);
            strcpy($$.code, "");
            $$.tipo = TIPO_INT;
        } else {
            strcpy($$.place, $1);
            strcpy($$.code, "");
            $$.tipo = s->tipo;
        }
    }

    /* ── Chamada de função ── */
    | chamada_func {
        strcpy($$.code,  $1.code);
        strcpy($$.place, $1.place);
        $$.tipo = $1.tipo;
    }
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
        if (!s) {
            erro_semantico("Funcao nao declarada");
        } else if (s->categoria != SYM_FUNC) {
            erro_semantico("Identificador nao e uma funcao");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "%s\t%s = call %s\n",
                 $3.code, temp, $1);
        strcpy($$.place, temp);
        $$.tipo = s ? s->tipo : TIPO_INT;
    }
    | ID LPAREN RPAREN {
        Simbolo *s = buscar_simbolo($1);
        if (!s) {
            erro_semantico("Funcao nao declarada");
        } else if (s->categoria != SYM_FUNC) {
            erro_semantico("Identificador nao e uma funcao");
        }
        char temp[64];
        gerar_temp(temp);
        snprintf($$.code, MAX_CODE, "\t%s = call %s\n", temp, $1);
        strcpy($$.place, temp);
        $$.tipo = s ? s->tipo : TIPO_INT;
    }
    ;

argumentos
    : expressao {
        snprintf($$.code, MAX_CODE, "%s\tparam %s\n", $1.code, $1.place);
        strcpy($$.place, $1.place);
        $$.tipo = $1.tipo;
    }
    | argumentos COMMA expressao {
        snprintf($$.code, MAX_CODE, "%s%s\tparam %s\n",
                 $1.code, $3.code, $3.place);
        strcpy($$.place, $3.place);
        $$.tipo = $3.tipo;
    }
    ;

io_stmt
    : PRINT LPAREN expressao RPAREN SEMICOLON {
        /* IR fica para o Integrante 3, mas propaga o code da expressao */
        strcpy($$.code, $3.code);
    }
    | READ LPAREN ID RPAREN SEMICOLON {
        strcpy($$.code, "");
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
