#!/bin/bash
#
# compiler.sh - Compila o analisador (Flex + Bison) e executa sobre um arquivo-fonte.
#
# Uso: ./compiler.sh fonte.txt
#

# --- 1. Verifica se o arquivo-fonte foi informado ---
if [ -z "$1" ]; then
    echo "Uso: $0 <arquivo-fonte>"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "Erro: arquivo '$1' nao encontrado."
    exit 1
fi

# --- 2. Gera o analisador sintatico (Bison) ---
# A opcao -d gera tambem o cabecalho parser.tab.h, usado pelo lexer.
echo ">> Gerando parser (Bison)..."
bison -d parser.y
if [ $? -ne 0 ]; then
    echo "Erro na geracao do parser (Bison). Abortando."
    exit 1
fi

# --- 3. Gera o analisador lexico (Flex) ---
echo ">> Gerando lexer (Flex)..."
flex lexer.l
if [ $? -ne 0 ]; then
    echo "Erro na geracao do lexer (Flex). Abortando."
    exit 1
fi

# --- 4. Compila o codigo C gerado ---
echo ">> Compilando (gcc)..."
gcc -o compilador parser.tab.c lex.yy.c
if [ $? -ne 0 ]; then
    echo "Erro na compilacao (gcc). Abortando."
    exit 1
fi

# --- 5. Executa o compilador sobre o arquivo-fonte ---
echo ">> Executando sobre '$1':"
echo "------------------------------------------------"
./compilador "$1"
