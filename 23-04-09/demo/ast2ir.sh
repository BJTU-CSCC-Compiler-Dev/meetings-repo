set -o xtrace
clang -Xclang -disable-O0-optnone -fno-discard-value-names -emit-llvm -S main.c -o main.ll
opt -S --mem2reg main.ll -o main.ll # explain later
