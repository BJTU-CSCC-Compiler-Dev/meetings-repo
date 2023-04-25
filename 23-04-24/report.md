# Intro

今天主要介绍LLVM-IR，然后介绍一点前端的坑（借用LLVM-IR）



# LLVM-IR

补一点之前没涉及的细节。



## alloca-load-store

### 返回值

我们看代码的时候会发现，llvm总会在函数的入口放`%retval = alloca ...`。

我们可以看这个代码解释为什么这么设计（例子来自于`try-ret.sysy`）：

```c
int main(){
	int cond = getint();
	
	if(cond){
		return 1;
	}else{
		return 0;
	}
}
```

生成的llvm-ir：

```scala
define dso_local i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %cond = alloca i32, align 4
  store i32 0, i32* %retval, align 4
  %call = call i32 bitcast (i32 (...)* @getint to i32 ()*)()
  store i32 %call, i32* %cond, align 4
  %0 = load i32, i32* %cond, align 4
  %tobool = icmp ne i32 %0, 0
  br i1 %tobool, label %if.then, label %if.else

if.then:                                          ; preds = %entry
  store i32 1, i32* %retval, align 4
  br label %return

if.else:                                          ; preds = %entry
  store i32 0, i32* %retval, align 4
  br label %return

return:                                           ; preds = %if.else, %if.then
  %1 = load i32, i32* %retval, align 4
  ret i32 %1
}
```

这个可以从几个方面解释：

1. 从程序流的角度说，由于函数可能在任何位置`return`，而`return`的语义有两个：

   1. 跳转到函数末尾。
   2. 返回某个值。

   可以看出，IR中的`br label %return`就是为了第一个语义；IR中的`store ..., i32* %retval`就是为了第二个语义。

2. 从体系结构的角度说，返回值本身就是存在某个寄存器或内存的（对于Arm架构来说，是`r11`，你可以通过看汇编了解这一点），也可以看作一个变量，所以`alloca`一个空间也合理。



### 数组

我们上次演示的时候没有展示数组的数据的存取，这里介绍下（例子来自于`get-from-arr.*`）：

源代码很简单，分别是一维和二维的数据存取：

```c
int main(){
	int idx = getint();

	int ar[3] = {0,1,2};
	ar[idx] = getint();

	int ar2[3][3] = {{0,1}, {2,3,4}};
	ar2[idx][idx] = getint();

	putint(ar[idx] + ar2[idx][idx + idx]);

	return 0;
}
```

在不经过`-mem2reg`之前：

* 对于`idx`，也就是一般变量：

  ```scala
  //	alloca
  	%idx = alloca i32, align 4
  //	getint()
  	%call = call i32 bitcast (i32 (...)* @getint to i32 ()*)()
  //	store to idx
  	store i32 %call, i32* %idx, align 4
  //	load from idx
      %10 = load i32, i32* %idx, align 4
  ```

* 对于`ar[3]`，也就是一维数组：

  ```scala
  //	alloca
  	%ar = alloca [3 x i32], align 4
  //	init
  	%0 = bitcast [3 x i32]* %ar to i8*
  	call void @llvm.memcpy.p0i8.p0i8.i32(i8* align 4 %0, i8* align 4 bitcast ([3 x i32]* @__const.main.ar to i8*), i32 12, i1 false)
  
  //	store new value
  	%call1 = call i32 bitcast (i32 (...)* @getint to i32 ()*)()
  	%1 = load i32, i32* %idx, align 4
  //	get the pointer to the position to store value
  	%arrayidx = getelementptr inbounds [3 x i32], [3 x i32]* %ar, i32 0, i32 %1
  //	store
  	store i32 %call1, i32* %arrayidx, align 4
  
  //	load ar[idx]
  	%12 = load i32, i32* %idx, align 4
  	%arrayidx5 = getelementptr inbounds [3 x i32], [3 x i32]* %ar, i32 0, i32 %12
  	%13 = load i32, i32* %arrayidx5, align 4
  ```

  这里和标量有两个区别：

  * 初始化的时候，不是`store`，而是调用了一个llvm的函数`llvm.memcpy.p0i8.p0i8.i32`。
  * 存取值的时候，不是简单的`load`，而需要先算出存取数据的地址，再从该地址`load`。

* 对于`ar2[3][3]`，也就是二维数组：

  ```scala
  //	alloca
  	%ar2 = alloca [3 x [3 x i32]], align 4
  //	init
  	%2 = bitcast [3 x [3 x i32]]* %ar2 to i8*
  	call void @llvm.memset.p0i8.i32(i8* align 4 %2, i8 0, i32 36, i1 false)
  //	ar2[idx][idx] = getint()
  	%call2 = call i32 bitcast (i32 (...)* @getint to i32 ()*)()
   	%10 = load i32, i32* %idx, align 4
   	%arrayidx3 = getelementptr inbounds [3 x [3 x i32]], [3 x [3 x i32]]* %ar2, i32 0, i32 %10
   	%11 = load i32, i32* %idx, align 4
   	%arrayidx4 = getelementptr inbounds [3 x i32], [3 x i32]* %arrayidx3, i32 0, i32 %11
   	store i32 %call2, i32* %arrayidx4, align 4
  //	get ar2[idx][idx + idx]
  	%12 = load i32, i32* %idx, align 4
  	%arrayidx5 = getelementptr inbounds [3 x i32], [3 x i32]* %ar, i32 0, i32 %12
  	%13 = load i32, i32* %arrayidx5, align 4
  	%14 = load i32, i32* %idx, align 4
  	%arrayidx6 = getelementptr inbounds [3 x [3 x i32]], [3 x [3 x i32]]* %ar2, i32 0, i32 %14
  	%15 = load i32, i32* %idx, align 4
  	%16 = load i32, i32* %idx, align 4
  	%add = add nsw i32 %15, %16
  	%arrayidx7 = getelementptr inbounds [3 x i32], [3 x i32]* %arrayidx6, i32 0, i32 %add
  ```

  这里和标量、一维数组的区别：

  * 同样，初始化的时候，不是`store`，而是调用了一个llvm的函数`llvm.memcpy.p0i8.p0i8.i32`。
  * 存取值的时候，不是简单的`load`，而需要先算出存取数据的地址，再从该地址`load`。只不过作为二维数组，需要算两次。



### 优化后的数组

之前我们说过，标量会在`-mem2reg`之后会消除`alloca`，进入SSA形式，但是对于数组来说不是这样（例子还是`get-from-arr.*`）：

```scala
//	get-from-arr.opt.ll
define dso_local i32 @main() #0 {
entry:
  %ar = alloca [3 x i32], align 4
  %ar2 = alloca [3 x [3 x i32]], align 4
  ...
```

可以看出，还是存在`alloca`信息。其实也好理解：以数组`arr`和未知变量`idx`来说，`arr[idx]`是需要从`arr`拿到第`idx`个位置的元素，而`idx`是编译时未知的，自然不可能将`arr[idx]`变成一个IR的变量。而普通的变量`x`则不存在这样的问题，直接变成IR的一个变量就行。



### 全局变量

上一次讲的时候，我们提到：对于变量，llvm会先`alloca`出来，取值的时候`load`，存值的时候`store`，但是忽略了全局变量的情况。

实际上，全局变量的表现是这样的（例子来自`global-var.*`）：

```scala
@global_var = dso_local global i32 10, align 4
@global_arr = dso_local global [3 x [4 x i32]] [[4 x i32] [i32 1, i32 2, i32 0, i32 0], [4 x i32] [i32 3, i32 4, i32 5, i32 0], [4 x i32] [i32 5, i32 0, i32 0, i32 0]], align 4

define dso_local i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %idx = alloca i32, align 4
  store i32 0, i32* %retval, align 4
  %call = call i32 bitcast (i32 (...)* @getint to i32 ()*)()
  store i32 %call, i32* %idx, align 4
  %0 = load i32, i32* %idx, align 4
  %arrayidx = getelementptr inbounds [3 x [4 x i32]], [3 x [4 x i32]]* @global_arr, i32 0, i32 %0
  %1 = load i32, i32* %idx, align 4
  %add = add nsw i32 %1, 1
  %arrayidx1 = getelementptr inbounds [4 x i32], [4 x i32]* %arrayidx, i32 0, i32 %add
  %2 = load i32, i32* %arrayidx1, align 4
  call void @putint(i32 noundef %2)
  ret i32 0
}
```

可以看出：

1. 这里不是一个`alloca`了，而是直接赋值了。
2. 全局变量的开头是`@`而不是`%`。
3. 全局变量和局部变量的使用是一样的，`@v`是一个指针，使用的时候需要`load`、`store`。



### 优化后的全局变量

和函数内的变量不同，优化后的全局变量不能变成IR的变量，还是指针（例子来自`global-var.*`）：

```scala
@global_var = dso_local global i32 10, align 4
@global_arr = dso_local global [3 x [4 x i32]] [[4 x i32] [i32 1, i32 2, i32 0, i32 0], [4 x i32] [i32 3, i32 4, i32 5, i32 0], [4 x i32] [i32 5, i32 0, i32 0, i32 0]], align 4

; Function Attrs: nounwind
define dso_local i32 @main() #0 {
entry:
  %call = call i32 bitcast (i32 (...)* @getint to i32 ()*)()
  %arrayidx = getelementptr inbounds [3 x [4 x i32]], [3 x [4 x i32]]* @global_arr, i32 0, i32 %call
  %add = add nsw i32 %call, 1
  %arrayidx1 = getelementptr inbounds [4 x i32], [4 x i32]* %arrayidx, i32 0, i32 %add
  %0 = load i32, i32* %arrayidx1, align 4, !tbaa !9
  call void @putint(i32 noundef %0)
  ret i32 0
}
//	函数里已经SSA了，全局变量@global_var还是指针
```

不这么做的原因：

* IR的变量也有一个名字，叫虚拟寄存器（VReg），这是因为IR的变量是有可能被分配在寄存器里的，而全局变量并不能放进寄存器。
* IR的变量是SSA形式的，它的值不会变，但是全局变量的值不能保证这点（全局变量的指针可以）。



## 特殊的记号

### `zeroinitializer`

在`large-arr.*`的例子中，可以看到：

```
@small_arr_inited = dso_local global <{ <{ i32, [9 x i32] }>, [9 x <{ i32, [9 x i32] }>] }> <{ <{ i32, [9 x i32] }> <{ i32 1, [9 x i32] zeroinitializer }>, [9 x <{ i32, [9 x i32] }>] zeroinitializer }>, align 4
@large_arr_inited = dso_local global <{ <{ i32, i32, [998 x i32] }>, <{ i32, i32, [998 x i32] }>, [998 x <{ i32, i32, [998 x i32] }>] }> <{ <{ i32, i32, [998 x i32] }> <{ i32 1, i32 2, [998 x i32] zeroinitializer }>, <{ i32, i32, [998 x i32] }> <{ i32 3, i32 4, [998 x i32] zeroinitializer }>, [998 x <{ i32, i32, [998 x i32] }>] zeroinitializer }>, align 4
@small_arr_uninited = dso_local global [100 x i32] zeroinitializer, align 4
@large_arr_uninited = dso_local global [1000 x [1000 x [10 x i32]]] zeroinitializer, align 4
```

这里的`zeroinitializer`是指：全是0地初始化。



## SysY的条件表达式和一般的不同

SysY的条件表达式只能在条件语句中出现。所以下面这种语句是不行的：

```c
int x = (y != 0);
```

此外，由于SysY语法一些设计问题，下面的语句也不能通过编译：

```c
if ( (a!=0) || (b!=0) ){
	...	
}
```



# IR和前端设计的一些坑

## bss段和data段

其实更多算后端的bug。。。不过就在这说了吧。

如果我们有全局数组，有的大有的小（例子来自`large-arr.*`）：

```c
int small_arr_inited[10][10] = {1,0};
int small_arr_uninited[100];
int large_arr_inited[1000][1000]={{1,2},{3,4}};
int large_arr_uninited[1000][1000][10];

int main(){
	return 0;
}
```

在LLVM-IR上基本上没什么差异：

```scala
@small_arr_inited = dso_local global <{ <{ i32, [9 x i32] }>, [9 x <{ i32, [9 x i32] }>] }> <{ <{ i32, [9 x i32] }> <{ i32 1, [9 x i32] zeroinitializer }>, [9 x <{ i32, [9 x i32] }>] zeroinitializer }>, align 4
@large_arr_inited = dso_local global <{ <{ i32, i32, [998 x i32] }>, <{ i32, i32, [998 x i32] }>, [998 x <{ i32, i32, [998 x i32] }>] }> <{ <{ i32, i32, [998 x i32] }> <{ i32 1, i32 2, [998 x i32] zeroinitializer }>, <{ i32, i32, [998 x i32] }> <{ i32 3, i32 4, [998 x i32] zeroinitializer }>, [998 x <{ i32, i32, [998 x i32] }>] zeroinitializer }>, align 4
@small_arr_uninited = dso_local global [100 x i32] zeroinitializer, align 4
@large_arr_uninited = dso_local global [1000 x [1000 x [10 x i32]]] zeroinitializer, align 4
```

但是在汇编上：

```assembly
	.type	small_arr_inited,%object        @ @small_arr_inited
	.data
	.globl	small_arr_inited
	.p2align	2
small_arr_inited:
	.long	1                               @ 0x1
	.zero	36
	.zero	360
	.size	small_arr_inited, 400

	.type	large_arr_inited,%object        @ @large_arr_inited
	.globl	large_arr_inited
	.p2align	2
large_arr_inited:
	.long	1                               @ 0x1
	.long	2                               @ 0x2
	.zero	3992
	.long	3                               @ 0x3
	.long	4                               @ 0x4
	.zero	3992
	.zero	3992000
	.size	large_arr_inited, 4000000

	.type	small_arr_uninited,%object      @ @small_arr_uninited
	.bss
	.globl	small_arr_uninited
	.p2align	2
small_arr_uninited:
	.zero	400
	.size	small_arr_uninited, 400

	.type	large_arr_uninited,%object      @ @large_arr_uninited
	.globl	large_arr_uninited
	.p2align	2
large_arr_uninited:
	.zero	40000000
	.size	large_arr_uninited, 40000000
```

需要注意：一个是`.bss`段，一个是`.data`段！

在C语言里，所有的全局变量/静态变量都是有初始值的，但是为了减少ELF文件（或者说可执行文件）的大小，编译器会将全是0的变量放在`.bss`段上，将有别的初始化值的变量放在`.data`段上。

在比赛中，会有一个checkpoint，其中包括了一个巨大的全0数组，如果你将数组放在了`.data`段，这个点就过不了。

关于`.bss`段和`.data`段的讨论，可以参考：

* [BSS vs DATA segment in memory](https://stackoverflow.com/q/72470836)
* [why-is-the-bss-segment-required](https://stackoverflow.com/questions/9535250/)



## 建议实现`zeroinitializer`

去年BJTU的两个队都因为“存了全局变量的全部值”导致编译器运行时内存特别大，进而导致CE。



## 数组初始化

赛方提供的checkpoint代码中有很多奇奇怪怪的数组初始化方法，你需要小心地实现它们。

```c
int ar0[3][3] = {1,2,3,4,5,6};
int ar1[3][3] = {{1}, {2,3}, {4,5,6}};
int ar2[3][3] = {{1,2,3,4,5,6}};
int ar3[3][3] = {{1}, {}};
int ar4[3][3] = {{}, {1,2,3,4,5}};
int ar5[3][3] = {{}, 1,2,3, {}};
// int ar6[3][3] = {{}, 1,2,3,4,5, {}};
int ar7[3][3] = {1,2,3,{},4,5};
int ar8[3][3] = {{1,2}, {3}, {}};
// int ar9[3] = {0, ar9[0], ar9[1]};

int main(){
	int ar9[3] = {0, ar9[0], ar9[1]};
	return 0;
}

```

上述代码中，除了被注释的行外，都是可以过C语言编译的，其中`ar2`和`ar4`在`clang`下会报warning，按照组委会的说法，会报warning就不符合SysY语法。所以这里出了`ar2`、`ar4`、`ar6`、`ar9`都需要实现。

这事最烦的是：去年我没找到啥文档解释这个定义。。。最后是测试驱动开发，过了就是没bug。



# 附录

* 关于怎么让llvm生成未被优化的、可以在之后被`opt`优化的llvm-ir：

  [why-is-clang-automatically-adding-attributes-to-my-functions](https://stackoverflow.com/questions/47504219/)

  （或者直接看`Makefile`的`clangOptions`）

* [llvm-language-reference-manual](https://llvm.org/docs/LangRef.html#llvm-language-reference-manual)

* [ProgrammersManual](https://llvm.org/docs/ProgrammersManual.html)

