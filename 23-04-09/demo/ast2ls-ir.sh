set -o xtrace
clang -Xclang -disable-O0-optnone -fno-discard-value-names -emit-llvm -S main.c -o main.ls.ll
