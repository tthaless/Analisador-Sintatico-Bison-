%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

/* Definições de tipos semânticos */
#define DT_INT   1
#define DT_FLOAT 2
#define DT_ERROR -1

/* Variáveis externas do Léxico */
extern int yylineno;
extern int coluna_inicial;
extern FILE *yyin;

int yylex(void);
void yyerror(const char *s);

/* ==========================================================================
   ESTRUTURAS DA TABELA DE SÍMBOLOS E ESCOPOS ANINHADOS
   ========================================================================== */
typedef struct Symbol {
    char *name;
    int data_type;       /* DT_INT ou DT_FLOAT */
    int scope_id;
    struct Symbol *next;
} Symbol;

typedef struct ScopeTable {
    Symbol *hash_table[211];
    int id;
    int depth;
    struct ScopeTable *parent;
} ScopeTable;

ScopeTable *current_scope = NULL;
int global_scope_counter = 0;
int current_scope_depth = 0;
int current_declaration_type = DT_INT;

/* Funções de Gerenciamento de Escopo */
unsigned int hash_func(const char *str) {
    unsigned int h = 0;
    while (*str) h = (h * 31) + *str++;
    return h % 211;
}

void enter_scope() {
    ScopeTable *new_scope = (ScopeTable *)malloc(sizeof(ScopeTable));
    memset(new_scope, 0, sizeof(ScopeTable));
    new_scope->id = global_scope_counter++;
    new_scope->depth = current_scope_depth++;
    new_scope->parent = current_scope;
    current_scope = new_scope;
}

void exit_scope() {
    if (current_scope && current_scope->parent) {
        current_scope = current_scope->parent;
        current_scope_depth--;
    }
}

void insert_symbol(const char *name, int data_type) {
    unsigned int idx = hash_func(name);
    Symbol *sym = (Symbol *)malloc(sizeof(Symbol));
    sym->name = strdup(name);
    sym->data_type = data_type;
    sym->scope_id = current_scope->id;
    sym->next = current_scope->hash_table[idx];
    current_scope->hash_table[idx] = sym;
}

Symbol* lookup_symbol(const char *name) {
    ScopeTable *sc = current_scope;
    while (sc != NULL) {
        unsigned int idx = hash_func(name);
        Symbol *sym = sc->hash_table[idx];
        while (sym != NULL) {
            if (strcmp(sym->name, name) == 0) return sym;
            sym = sym->next;
        }
        sc = sc->parent;
    }
    return NULL;
}

Symbol* lookup_current_scope(const char *name) {
    unsigned int idx = hash_func(name);
    Symbol *sym = current_scope->hash_table[idx];
    while (sym != NULL) {
        if (strcmp(sym->name, name) == 0) return sym;
        sym = sym->next;
    }
    return NULL;
}

/* ==========================================================================
   GERAÇÃO DE CÓDIGO INTERMEDIÁRIO (IR)
   ========================================================================== */
int temp_counter = 1;
int label_counter = 1;

char* newTemp() {
    char *t = (char*)malloc(20);
    sprintf(t, "t%d", temp_counter++);
    return t;
}

char* newLabel() {
    char *L = (char*)malloc(20);
    sprintf(L, "L%d", label_counter++);
    return L;
}

void emit(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    printf("\n");
    va_end(args);
}

void emitLabel(const char *label) {
    printf("%s:\n", label);
}

%}

%code requires {
    typedef struct {
        int type;   /* DT_INT, DT_FLOAT, DT_ERROR */
        char *addr; /* Endereço temporário ou literal no IR */
    } ExprInfo;
}

%union {
    int ival;
    char *sval;
    ExprInfo expr_val;
}

%token <sval> ID
%token <sval> NUM_INT
%token <sval> NUM_DEC

%token INT FLOAT
%token IF ELSE WHILE READ PRINT RETURN
%token PLUS MINUS MULT DIV MOD
%token AND OR NOT
%token EQ NE LT LE GT GE
%token ASSIGN
%token LPAREN RPAREN LBRACE RBRACE COMMA SEMICOLON

/* Definição de tipos dos não-terminais */
%type <ival> tipo
%type <expr_val> expressao chamada_func
%type <sval> while_start if_head

/* Precedência e Associatividade */
%left OR
%left AND
%left EQ NE
%left LT LE GT GE
%left PLUS MINUS
%left MULT DIV MOD
%precedence NOT
%precedence UMINUS 

%precedence LOWER_THAN_ELSE
%precedence ELSE

%start programa

%%

programa
    : { enter_scope(); } lista_comandos { exit_scope(); }
    ;

lista_comandos
    : comando
    | lista_comandos comando
    ;

comando
    : declaracao SEMICOLON
    | tipo ID {
        if (lookup_current_scope($2) != NULL) {
            char msg[256]; sprintf(msg, "Erro Semantico: Funcao '%s' ja declarada neste escopo.", $2);
            yyerror(msg);
        } else {
            insert_symbol($2, $1);
        }
        enter_scope();
    } LPAREN parametros_opt RPAREN bloco { exit_scope(); }
    | atribuicao SEMICOLON
    | comando_if
    | comando_while
    | abre_bloco lista_comandos fecha_bloco
    | io_stmt
    | chamada_func SEMICOLON
    | RETURN expressao SEMICOLON {
        emit("return %s", $2.addr);
    }
    | error SEMICOLON { yyerrok; }
    ;

abre_bloco  : LBRACE { enter_scope(); };
fecha_bloco : RBRACE { exit_scope(); };

bloco
    : LBRACE lista_comandos RBRACE
    | LBRACE RBRACE
    ;

comando_if
    : if_head comando %prec LOWER_THAN_ELSE {
        emitLabel($1);
    }
    | if_head comando ELSE {
        char *L_end = newLabel();
        emit("goto %s", L_end);
        emitLabel($1);
        $<sval>$ = L_end;
    } comando {
        emitLabel($<sval>4);
    }
    ;

if_head
    : IF LPAREN expressao RPAREN {
        char *L_false = newLabel();
        emit("ifFalse %s goto %s", $3.addr, L_false);
        $$ = L_false;
    }
    ;

while_start
    : WHILE {
        char *L_start = newLabel();
        emitLabel(L_start);
        $$ = L_start;
    }
    ;

comando_while
    : while_start LPAREN expressao RPAREN {
        char *L_end = newLabel();
        emit("ifFalse %s goto %s", $3.addr, L_end);
        $<sval>$ = L_end;
    } comando {
        emit("goto %s", $1);
        emitLabel($<sval>5);
    }
    ;

tipo
    : INT   { $$ = DT_INT; current_declaration_type = DT_INT; }
    | FLOAT { $$ = DT_FLOAT; current_declaration_type = DT_FLOAT; }
    ;

declaracao
    : tipo lista_decl_itens
    ;

lista_decl_itens
    : decl_item
    | lista_decl_itens COMMA decl_item
    ;

decl_item
    : ID {
        if (lookup_current_scope($1) != NULL) {
            char msg[256]; sprintf(msg, "Erro Semantico: Variavel '%s' ja declarada neste escopo.", $1);
            yyerror(msg);
        } else {
            insert_symbol($1, current_declaration_type);
        }
    }
    | ID ASSIGN expressao {
        if (lookup_current_scope($1) != NULL) {
            char msg[256]; sprintf(msg, "Erro Semantico: Variavel '%s' ja declarada.", $1);
            yyerror(msg);
        } else {
            insert_symbol($1, current_declaration_type);
            Symbol *s = lookup_symbol($1);
            char unique_target[256];
            sprintf(unique_target, "%s_%d", s->name, s->scope_id);

            if (current_declaration_type == DT_FLOAT && $3.type == DT_INT) {
                char *t = newTemp();
                emit("%s = (float) %s", t, $3.addr);
                emit("%s = %s", unique_target, t);
            } else if (current_declaration_type == DT_INT && $3.type == DT_FLOAT) {
                char msg[256];
                sprintf(msg, "Erro Semantico: Declaracao incompativel: nao e possivel inicializar variavel int '%s' com valor float.", $1);
                yyerror(msg);
            } else {
                emit("%s = %s", unique_target, $3.addr);
            }
        }
    }
    ;

atribuicao
    : ID ASSIGN expressao {
        Symbol *s = lookup_symbol($1);
        if (s == NULL) {
            char msg[256]; sprintf(msg, "Erro Semantico: Variavel '%s' nao declarada.", $1);
            yyerror(msg);
        } else {
            char unique_target[256];
            sprintf(unique_target, "%s_%d", s->name, s->scope_id);

            if (s->data_type == DT_FLOAT && $3.type == DT_INT) {
                char *t = newTemp();
                emit("%s = (float) %s", t, $3.addr);
                emit("%s = %s", unique_target, t);
            } else if (s->data_type == DT_INT && $3.type == DT_FLOAT) {
                char msg[256];
                sprintf(msg, "Erro Semantico: Atribuicao incompativel: nao e possivel atribuir float a variavel int '%s'.", $1);
                yyerror(msg);
            } else {
                emit("%s = %s", unique_target, $3.addr);
            }
        }
    }
    ;

expressao
    : expressao PLUS expressao  {
        $$.addr = newTemp();
        if ($1.type == DT_FLOAT || $3.type == DT_FLOAT) {
            $$.type = DT_FLOAT;
            char *a1 = $1.addr, *a2 = $3.addr;
            if ($1.type == DT_INT) { a1 = newTemp(); emit("%s = (float) %s", a1, $1.addr); }
            if ($3.type == DT_INT) { a2 = newTemp(); emit("%s = (float) %s", a2, $3.addr); }
            emit("%s = %s + %s", $$.addr, a1, a2);
        } else {
            $$.type = DT_INT;
            emit("%s = %s + %s", $$.addr, $1.addr, $3.addr);
        }
    }
    | expressao MINUS expressao {
        $$.addr = newTemp();
        if ($1.type == DT_FLOAT || $3.type == DT_FLOAT) {
            $$.type = DT_FLOAT;
            char *a1 = $1.addr, *a2 = $3.addr;
            if ($1.type == DT_INT) { a1 = newTemp(); emit("%s = (float) %s", a1, $1.addr); }
            if ($3.type == DT_INT) { a2 = newTemp(); emit("%s = (float) %s", a2, $3.addr); }
            emit("%s = %s - %s", $$.addr, a1, a2);
        } else {
            $$.type = DT_INT;
            emit("%s = %s - %s", $$.addr, $1.addr, $3.addr);
        }
    }
    | expressao MULT expressao  {
        $$.addr = newTemp();
        if ($1.type == DT_FLOAT || $3.type == DT_FLOAT) {
            $$.type = DT_FLOAT;
            char *a1 = $1.addr, *a2 = $3.addr;
            if ($1.type == DT_INT) { a1 = newTemp(); emit("%s = (float) %s", a1, $1.addr); }
            if ($3.type == DT_INT) { a2 = newTemp(); emit("%s = (float) %s", a2, $3.addr); }
            emit("%s = %s * %s", $$.addr, a1, a2);
        } else {
            $$.type = DT_INT;
            emit("%s = %s * %s", $$.addr, $1.addr, $3.addr);
        }
    }
    | expressao DIV expressao   {
        $$.addr = newTemp();
        if ($1.type == DT_FLOAT || $3.type == DT_FLOAT) {
            $$.type = DT_FLOAT;
            char *a1 = $1.addr, *a2 = $3.addr;
            if ($1.type == DT_INT) { a1 = newTemp(); emit("%s = (float) %s", a1, $1.addr); }
            if ($3.type == DT_INT) { a2 = newTemp(); emit("%s = (float) %s", a2, $3.addr); }
            emit("%s = %s / %s", $$.addr, a1, a2);
        } else {
            $$.type = DT_INT;
            emit("%s = %s / %s", $$.addr, $1.addr, $3.addr);
        }
    }
    | expressao MOD expressao   {
        if ($1.type == DT_INT && $3.type == DT_INT) {
            $$.type = DT_INT; $$.addr = newTemp();
            emit("%s = %s %% %s", $$.addr, $1.addr, $3.addr);
        } else {
            yyerror("Erro Semantico: Operador '%' aceita apenas inteiros.");
            $$.type = DT_ERROR;
            $$.addr = "0";
        }
    }
    | expressao AND expressao   {
        $$.type = DT_INT; $$.addr = newTemp();
        emit("%s = %s && %s", $$.addr, $1.addr, $3.addr);
    }
    | expressao OR expressao    {
        $$.type = DT_INT; $$.addr = newTemp();
        emit("%s = %s || %s", $$.addr, $1.addr, $3.addr);
    }
    | expressao EQ expressao    { $$.type = DT_INT; $$.addr = newTemp(); emit("%s = %s == %s", $$.addr, $1.addr, $3.addr); }
    | expressao NE expressao    { $$.type = DT_INT; $$.addr = newTemp(); emit("%s = %s != %s", $$.addr, $1.addr, $3.addr); }
    | expressao LT expressao    { $$.type = DT_INT; $$.addr = newTemp(); emit("%s = %s < %s", $$.addr, $1.addr, $3.addr); }
    | expressao LE expressao    { $$.type = DT_INT; $$.addr = newTemp(); emit("%s = %s <= %s", $$.addr, $1.addr, $3.addr); }
    | expressao GT expressao    { $$.type = DT_INT; $$.addr = newTemp(); emit("%s = %s > %s", $$.addr, $1.addr, $3.addr); }
    | expressao GE expressao    { $$.type = DT_INT; $$.addr = newTemp(); emit("%s = %s >= %s", $$.addr, $1.addr, $3.addr); }
    | NOT expressao             { $$.type = DT_INT; $$.addr = newTemp(); emit("%s = !%s", $$.addr, $2.addr); }
    | MINUS expressao %prec UMINUS {
        $$.type = $2.type; $$.addr = newTemp();
        emit("%s = -%s", $$.addr, $2.addr);
    }
    | LPAREN expressao RPAREN   { $$ = $2; }
    | NUM_INT { $$.type = DT_INT; $$.addr = strdup($1); }
    | NUM_DEC { $$.type = DT_FLOAT; $$.addr = strdup($1); }
    | ID {
        Symbol *s = lookup_symbol($1);
        if (s == NULL) {
            char msg[256]; sprintf(msg, "Erro Semantico: Variavel '%s' nao declarada.", $1);
            yyerror(msg);
            $$.type = DT_ERROR; $$.addr = "0";
        } else {
            $$.type = s->data_type;
            char unique[256]; sprintf(unique, "%s_%d", s->name, s->scope_id);
            $$.addr = strdup(unique);
        }
    }
    | chamada_func { $$ = $1; }
    ;

parametros
    : parametro
    | parametros COMMA parametro
    ;

parametros_opt
    : /* vazio */
    | parametros
    ;

parametro
    : tipo ID { insert_symbol($2, $1); }
    ;

chamada_func
    : ID LPAREN argumentos RPAREN {
        Symbol *s = lookup_symbol($1);
        $$.addr = newTemp();
        if (s != NULL) {
            $$.type = s->data_type;
        } else {
            char msg[256]; sprintf(msg, "Erro Semantico: Funcao '%s' nao declarada.", $1);
            yyerror(msg);
            $$.type = DT_ERROR;
        }
        emit("%s = call %s", $$.addr, $1);
    }
    | ID LPAREN RPAREN {
        Symbol *s = lookup_symbol($1);
        $$.addr = newTemp();
        if (s != NULL) {
            $$.type = s->data_type;
        } else {
            char msg[256]; sprintf(msg, "Erro Semantico: Funcao '%s' nao declarada.", $1);
            yyerror(msg);
            $$.type = DT_ERROR;
        }
        emit("%s = call %s", $$.addr, $1);
    }
    ;

argumentos
    : expressao             { emit("param %s", $1.addr); }
    | argumentos COMMA expressao { emit("param %s", $3.addr); }
    ;

io_stmt
    : PRINT LPAREN expressao RPAREN SEMICOLON { emit("print %s", $3.addr); }
    | READ LPAREN ID RPAREN SEMICOLON {
        Symbol *s = lookup_symbol($3);
        if (s != NULL) {
            char unique[256]; sprintf(unique, "%s_%d", s->name, s->scope_id);
            emit("read %s", unique);
        } else {
            char msg[256]; sprintf(msg, "Erro Semantico: Variavel '%s' nao declarada no 'read'.", $3);
            yyerror(msg);
        }
    }
    ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "ERRO: %s na Linha %d, Coluna %d\n", s, yylineno, coluna_inicial);
}

int main(int argc, char **argv) {
    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            fprintf(stderr, "Erro: nao foi possivel abrir o arquivo '%s'\n", argv[1]);
            return 1;
        }
    } else {
        yyin = stdin;
    }

    int result = yyparse();

    if (yyin != stdin) {
        fclose(yyin);
    }

    return result;
}