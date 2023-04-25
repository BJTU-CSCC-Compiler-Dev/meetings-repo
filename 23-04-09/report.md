主要详细介绍下编译器的流程和IR这个可以说是编译器最重要部分。

我们用C语言和LLVM举例子。

所有的代码会发给大家。



# 编译器的流程

## 整体流程

整个编译器的处理流如下：

```
source                   
  |                          ^
  | antlr, yacc, etc.        |
  |                          |
  v                          |
 ast (abstract syntax tree)  |=> frontend
  |                          |
  | ast visitor              |
  |                          |
  v                          v
 ir (intermediate representation) 
  |                          ^
  | optimization             |
  |                          |=> middle-end
  v                          v
 ir
  |                          ^
  | instruction selection    |
  |                          |
[lower ir]                   |
  |                          |=> backend
  | instruction scheduling   |
  | register allocation      |
  |                          |
  v                          v
 assembly code
```

我们用llvm来演示下：



## 前端

### source code -> ast

我们有一个main.c，它的内容如下：

```c
int getint();
void putint(int x);

int main(){
    int x, y;
    x = getint();
    y = getint();

    int z = x + y;
    x = z * (x + y);
    y = z + x;
    int r =  -y;

    putint(r);
	return 0;
}
```

跑show_ast.sh，可以看到它的语法树：

```shell
#	See terminal
```

在编译器的实际编码中，这就是一棵树，我们需要dfs这棵树来转化成IR。



### ast -> ir

跑ast2ir.sh，llvm就会从main.c生成main.ll，其中`main`函数对应内容大概如下：

```
define dso_local i32 @main() #0 {
entry:
  %call = call i32 (...) @getint()
  %call1 = call i32 (...) @getint()
  %add = add nsw i32 %call, %call1
  %add2 = add nsw i32 %call, %call1
  %mul = mul nsw i32 %add, %add2
  %add3 = add nsw i32 %add, %mul
  %sub = sub nsw i32 0, %add3
  call void @putint(i32 noundef %sub)
  ret i32 0
}
```

> 关于这里的`opt -S --mem2reg`，之后解释。

解释一下：

* llvm-ir几乎就是汇编，差别只有：

  * 有无限“寄存器”：上面代码中的`%call`、`%call1`之类的其实可以看成一种虚拟寄存器（VReg），在中端我们认为这种VReg有无数个，在后端再对这些VReg到底是真的放在寄存器里还是分配到内存上做选择（寄存器分配）。
  * 有特殊的指令：上面的`add`、`mul`都是llvm-ir的指令，可以用来。

  总而言之，这种IR是体系结构无关的，也就是在这个层面不考虑“参数通过哪个寄存器传”、“有哪些寄存器”、“使用哪些汇编指令”之类的底层问题（但是优化的时候在一定层面上需要考虑底层）。

* 其中`nsw`、`nonudef`之类的都是llvm用于做分析用的flag、attribute，暂时不需要了解。

* 可以注意到，源代码中的`x`是经过重复赋值的，第一次是`x=getint()`，第二次是`x=z*(x+y)`，但是IR中没有这个情况。后续会解答为什么会这样。



## 中端

中端优化是基于IR的。我们这里假设只做公共子表达式消除（cse or Common Subexpression Eliminate）这一种优化。

跑ir2optir.sh，llvm的`opt`就会从main.ll生成main.opt.ll，其中`main`函数对应的内容大概如下：

```
define dso_local i32 @main() #0 {
entry:
  %call = call i32 (...) @getint()
  %call1 = call i32 (...) @getint()
  %add = add nsw i32 %call, %call1
  %mul = mul nsw i32 %add, %add
  %add3 = add nsw i32 %add, %mul
  %sub = sub nsw i32 0, %add3
  call void @putint(i32 noundef %sub)
  ret i32 0
}
```

会发现在main.ll中的`%add2`被`%add`替换了，因为`%add2`和`%add`都是`%call`、`%call1`相加得到的，并且两次相加`%call`和`%call1`的值都没有变化。



## 后端

跑optir2asm.sh，llvm的`llc`就会从main.opt.ll生成main.S（这里是AMD64汇编）。

其中`main`函数对应的内容大概如下：

```assembly
main:                                   # @main
	.cfi_startproc
# %bb.0:                                # %entry
	pushq	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	pushq	%rbx
	pushq	%rax
	.cfi_offset %rbx, -24
	xorl	%eax, %eax
	callq	getint@PLT
	movl	%eax, %ebx
	xorl	%eax, %eax
	callq	getint@PLT
	addl	%eax, %ebx # *1
	movl	%ebx, %edi
	imull	%ebx, %edi
	addl	%ebx, %edi
	negl	%edi
	callq	putint@PLT
	xorl	%eax, %eax
	addq	$8, %rsp
	popq	%rbx
	popq	%rbp
	.cfi_def_cfa %rsp, 8
	retq
```

这里才会涉及一些底层的细节，比如（AMD64下）：函数返回值在`%eax`寄存器中，所以`*1`处直接`addl %eax, %ebx`；需要保存栈指针，所以进来先`push %rbp`，等等。



# SSA简介

这里只是介绍SSA形式IR，和一种比较避免SSA形式，但是兼容SSA的IR。关于SSA的构造和数据结构，可以在之后再说。



## 引入

前面讲到，在IR中，原本源码里重复赋值的情况没了。也就是：

```c
    x = getint();
//	...
    x = z * (x + y);
```

在IR里是：

```c
  %call = call i32 (...) @getint()
// ...
  %add2 = add nsw i32 %call, %call1
```

为什么IR层面丢掉了重复赋值这个信息呢？是因为：对于中端优化来说，变量本身没意义，有意义的是它的值，中端处理的其实是值的流动。

这就是静态单赋值（SSA, Static Single Assignment）的思想。在SSA形式的IR中，所有的变量（或者说VReg），都只被赋值一次，之后永远不被改变，我们只关心这些值是怎么被使用的。

我们之前生成的都是SSA形式的IR：

```c
define dso_local i32 @main() #0 {
entry:
  %call = call i32 (...) @getint()
  %call1 = call i32 (...) @getint()
  %add = add nsw i32 %call, %call1
  %mul = mul nsw i32 %add, %add
  %add3 = add nsw i32 %add, %mul
  %sub = sub nsw i32 0, %add3
  call void @putint(i32 noundef %sub)
  ret i32 0
}
```

可以看出：所有值都只定义了一次。



这种形式的IR下，优化会容易些。以公共子表达式消除为例：`%add = add nsw i32 %call, %call1`和`%add2 = add nsw i32 %call, %call1`得到的`%add`和`%add2`之所以一样，就是因为`%call`和`%call1`在定义之后的值就不会变化。

在接着介绍SSA形式IR之前，我们先了解一些定义：

* def-use chain：又或者说是du链，举个例子：

  ```c
    %add = add nsw i32 %call, %call1
    %mul = mul nsw i32 %add, %add
  ```

  这里的`%add`就是通过`add`定义的，而定义`%mul`的`mul`指令就使用了`%add`。

  因为是“单赋值”，所以du链是一个define（赋值）后跟多个use。

* basic block：又或者说BB，是基本块的意思。在IR层面，BB是顺序代码序列，满足：不会有指令跳往入口外的位置，除出口外没有分支指令。

  在llvm-ir里，BB的开头是一个label，比如`entry:`，结尾是跳转指令，中间没有分支指令。因此跳转只能跳转到开头的这个label，也只会在最后执行分支。

* Control flow graph：简写CFG，控制流图。BB组成的图，代表了执行的流程。

* Pass：在编译的语境下，"pass is a complete traversal of the source program"。实际上，cse优化就可以看作一个pass，没有优化的IR进去，cse完的IR出来。



## Phi指令

我们前面提到，SSA只有一次定义，那就有一个问题，比如下面的C语言语句：

```c
int a = 1;
if (...) {
  a = 2;
} else {
  a = 3;
}
return a;
```

尝试翻译成IR：

```c
entry:  
  a = 1               // 定义最初的 a
  br ..., then, else  // 执行条件判断

then:
  a_1 = 2     // 修改了 a 的值, 定义新变量 a_1
  jump end

else:
  a_2 = 3     // 修改了 a 的值, 定义新变量 a_2
  jump end

end:
  return ???  // 等等, 这里应该用哪个 a?
```

CFG如下：

```
		entry{
			a = 1
			br ... , then, else
		}
		            |
        +--------------------------+
        |                          |
        v                          v
then{							else{
	a_1 = 2							a_2 = 3
	jump end						jump end
}								}
        |                         |
        +-------------------------+
                    |
                    v
				end{
					return ???
				}
```

你会发现，遇到这种控制流合并的情况，一旦你在之前的两个控制流里对同一个变量做了不同的修改，或者只在一个控制流里改了变量而另一个没改，在控制流的交汇处再想用这个变量，你就不知道到底该用哪一个了。

而 SSA 形式用一种近乎耍赖皮的方式解决了这个问题：

```c
entry:
  a = 1
  br ..., then, else

then:
  a_1 = 2     // 修改了 a 的值, 定义新变量 a_1
  jump end

else:
  a_2 = 3     // 修改了 a 的值, 定义新变量 a_2
  jump end

end:
  // 定义一个新变量 a_3
  // 如果控制流是从 then 基本块流入的, 那 a_3 的值就是 a_1
  // 如果控制流是从 else 基本块流入的, 那 a_3 的值就是 a_2
  a_3 = phi (a_1, then), (a_2, else)
  return a_3  // 这里用 a_3
```

控制流图：

```
		entry{
			a = 1
			br ... , then, else
		}
		            |
        +--------------------------+
        |                          |
        v                          v
then{							else{
	a_1 = 2							a_2 = 3
	jump end						jump end
}								}
        |                         |
        +-------------------------+
                    |
                    v
				end{
					a_3 = phi (a_1, then), (a_2, else)
					return a_3
				}
```

这里插入的就是Phi指令（或者$\phi$指令）。因此，这仍然满足SSA。



## 基本块参数

Phi函数可以在解决上述控制流问题的同时保持SSA形式，是解决这个问题的比较经典的方式。同时也有另一种方式，叫“基本块参数”，我相信只要一眼大家都能明白：

```c
entry:
  br ..., %then, %else

%then:
  jump %end(2)

%else:
  jump %end(3)

%end(%a_3: i32):
  ret %a_3
```

从我个人的感觉看，后者是比前者简单的。



## 从load-store形式到SSA形式

实际的llvm是先生成load-store形式的IR，再经过`--mem2reg`优化转成SSA形式IR：

```shell
clang -Xclang -disable-O0-optnone -fno-discard-value-names -emit-llvm -S main.c -o main.ll # load store
opt -S --mem2reg main.ll -o main.ll # ssa
```

运行ast2ls-ir.sh，可以得到main.ls.ll，里面就是load-store形式的IR，其中`main`函数部分（注释是手动添加的）：

```c
define dso_local i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %x = alloca i32, align 4
  %y = alloca i32, align 4
  %z = alloca i32, align 4
  %r = alloca i32, align 4
  store i32 0, i32* %retval, align 4
  // x = getint();
  %call = call i32 (...) @getint()
  store i32 %call, i32* %x, align 4
  // y = getint();
  %call1 = call i32 (...) @getint()
  store i32 %call1, i32* %y, align 4
  // int z = x + y;
  %0 = load i32, i32* %x, align 4
  %1 = load i32, i32* %y, align 4
  %add = add nsw i32 %0, %1
  store i32 %add, i32* %z, align 4
  // x = z * (x + y);
  %2 = load i32, i32* %z, align 4
  %3 = load i32, i32* %x, align 4
  %4 = load i32, i32* %y, align 4
  %add2 = add nsw i32 %3, %4
  %mul = mul nsw i32 %2, %add2
  store i32 %mul, i32* %x, align 4
  // y = z + x;
  %5 = load i32, i32* %z, align 4
  %6 = load i32, i32* %x, align 4
  %add3 = add nsw i32 %5, %6
  store i32 %add3, i32* %y, align 4
  // int r =  -y;
  %7 = load i32, i32* %y, align 4
  %sub = sub nsw i32 0, %7
  store i32 %sub, i32* %r, align 4
  // putint(r);
  %8 = load i32, i32* %r, align 4
  call void @putint(i32 noundef %8)
  // return 0;
  ret i32 0
}
```

`alloca`可以看成开辟一片内存，返回指针给VReg。`load`和`store`分别对应取和存。

可以看出，这个形式的IR非常直接：所有的变量都是存在内存中，之后每次使用都`load`出来、每次更改都`store`进去。



## 实践

前端到IR一般有两种思路：

* 先生成非SSA形式的，然后进入SSA形式。

  llvm的方法。

* 直接生成SSA形式的。

我建议选择前者，这样可以将前端任务和中端任务解耦，两边在完成IR的定义之后就可以同时开干、同时测试，且减少了前端的代码压力（load-store形式的还是更简单的），效率高些。后者需要一个熟悉SSA、编译器中端的同学立即、快速地做完前端，难度有点大。



我们的编译器最好能在中端完成之前就能进行测试，一般有两种测试方式：

* 做一个我们的IR到llvm-ir的转换，然后用llvm的ir做测试。

  大多数参赛队的做法。

* 做一个虚拟机，执行我们的ir。

  21年清华rank1的做法。

优缺点：

| 项                 | 做llvm-ir的转换                                              | 虚拟机执行ir                            |
| ------------------ | ------------------------------------------------------------ | --------------------------------------- |
| 是否方便编码       | 还行，只要ir也照着llvm-ir设计就没问题                        | 需要多一个项目，代码量至少多个几千行    |
| 是否方便debug IR   | 一般，需要通过插入pass的方式做debug，之后通过llvm提供的`lli`运行llvm-ir | 方便，打log啥的只要改我们自己的源码就行 |
| 是否有IR设计自由度 | 不自由，基本就只能仿制llvm-ir了                              | 自由                                    |



# 后续安排

鉴于我们目前有两个队，这里只是我个人推荐的安排。

1. 先完成IR的设计和编码，可以参考之前队伍的。

   因为IR设计本身不算在代码里，不能被查重，所以可以两个组的同学一起讨论做。

   但是IR的编码是需要每个队自己完成的，可以参考现有的项目。个人推荐下MaxXing的[YuLang](https://github.com/MaxXSoft/YuLang)，里面src/mid下的usedef.h、ssa.h、usedef.c、ssa.c就是维护IR的一种方式（双向引用链）。

2. 如果使用虚拟机执行ir，就完成虚拟机的编写。

   同样，由于这个虚拟机不算在提交的代码里，不能被查重，所以可以两个组的同学一起做。

3. 在完成IR设计后，前端的同学开始测试驱动开发

   同时，中端可以做一下`--mem2reg`，将IR变成SSA形式的。

4. 上面几个做完基本上这学期差不多过去了（还是考虑大家不摸鱼、做得快的情况



# 参考资料

* [CMU Compiler课对SSA介绍的课件](https://www.cs.cmu.edu/~fp/courses/15411-f08/lectures/09-ssa.pdf)
* [MaxX对基本块参数的介绍文章](https://blog.maxxsoft.net/index.php/archives/143/)
* [LLVM的IR的manual](https://llvm.org/docs/LangRef.html)

