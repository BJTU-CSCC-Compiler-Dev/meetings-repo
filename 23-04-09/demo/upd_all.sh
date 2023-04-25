set -o xtrace
clang -Xclang -disable-O0-optnone -fno-discard-value-names -emit-llvm -S main.c -o main.ls.ll
clang -Xclang -disable-O0-optnone -fno-discard-value-names -emit-llvm -S main.c -o main.ll
opt -S --mem2reg main.ll -o main.ll # explain later
opt -S --early-cse main.ll -o main.opt.ll
llc main.opt.ll -o main.S
