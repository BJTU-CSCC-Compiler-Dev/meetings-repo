clangOptions = -Xclang -emit-llvm -S -x c -O1 -mllvm -disable-llvm-optzns -include sysy_lib.h -target armv7a-unknown-linux-gnueabihf -march=armv7-a -mfloat-abi=hard -fno-discard-value-names 
optOptions = -S -mem2reg 
llcOptions =

sysyFiles = $(shell find . -name "*.sysy")
llFiles = $(sysyFiles:%.sysy=%.ll)
optLlFiles = $(sysyFiles:%.sysy=%.opt.ll)
sFiles = ${sysyFiles:%.sysy=%.S}

sysy_lib.so: sysy_lib.c
	arm-linux-gnueabihf-gcc -shared sysy_lib.c -o sysy_lib.so

%.ll: %.sysy
	@echo "clang : $< => $@"
	@clang ${clangOptions} $< -o $@

%.opt.ll: %.ll
	@echo "opt   : $< => $@"
	@opt ${optOptions} $< -o $@

%.S: %.opt.ll
	@echo "llc   : $< => $@"
	@llc ${llcOptions} $< -o $@

.PRECIOUS: %.ll %.opt.ll

.PHONY: all show clean
.DEFAULT_GOAL := all
all: ${sFiles}

show:
	@echo "clnag options : " ${clangOptions}
	@echo "opt options : " ${optOptions}
	@echo "llc options : " ${llcOptions}
	@echo ${sysyFiles} ${llFiles} ${optLlFiles} ${sFiles}

clean:
	rm -f ${llFiles} ${optLlFiles} ${sFiles} sysy_lib.so
