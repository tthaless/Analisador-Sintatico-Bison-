#!/bin/bash

# --- Verifica se o arquivo-fonte foi informado ---
if [ -z "$1" ]; then
    echo "Uso: $0 <arquivo-fonte>"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "Erro: arquivo '$1' nao encontrado."
    exit 1
fi

# --- Gera o analisador sintatico (Bison) ---
echo ">> Gerando parser (Bison)..."
bison -d parser.y
if [ $? -ne 0 ]; then
    echo "Erro na geracao do parser (Bison). Abortando."
    exit 1
fi

# --- Gera o analisador lexico (Flex) ---
echo ">> Gerando lexer (Flex)..."
flex lexer.l
if [ $? -ne 0 ]; then
    echo "Erro na geracao do lexer (Flex). Abortando."
    exit 1
fi

# --- Compila o codigo C gerado ---
echo ">> Compilando (gcc)..."
gcc -o compilador parser.tab.c lex.yy.c
if [ $? -ne 0 ]; then
    echo "Erro na compilacao (gcc). Abortando."
    exit 1
fi

# --- Executa o compilador sobre o arquivo-fonte ---
echo ">> Executando sobre '$1':"
echo "------------------------------------------------"
./compilador "$1"
