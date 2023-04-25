; ModuleID = 'main.c'
source_filename = "main.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-pc-linux-gnu"

; Function Attrs: noinline nounwind uwtable
define dso_local i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %x = alloca i32, align 4
  %y = alloca i32, align 4
  %z = alloca i32, align 4
  %r = alloca i32, align 4
  store i32 0, i32* %retval, align 4
  %call = call i32 (...) @getint()
  store i32 %call, i32* %x, align 4
  %call1 = call i32 (...) @getint()
  store i32 %call1, i32* %y, align 4
  %0 = load i32, i32* %x, align 4
  %1 = load i32, i32* %y, align 4
  %add = add nsw i32 %0, %1
  store i32 %add, i32* %z, align 4
  %2 = load i32, i32* %z, align 4
  %3 = load i32, i32* %x, align 4
  %4 = load i32, i32* %y, align 4
  %add2 = add nsw i32 %3, %4
  %mul = mul nsw i32 %2, %add2
  store i32 %mul, i32* %x, align 4
  %5 = load i32, i32* %z, align 4
  %6 = load i32, i32* %x, align 4
  %add3 = add nsw i32 %5, %6
  store i32 %add3, i32* %y, align 4
  %7 = load i32, i32* %y, align 4
  %sub = sub nsw i32 0, %7
  store i32 %sub, i32* %r, align 4
  %8 = load i32, i32* %r, align 4
  call void @putint(i32 noundef %8)
  ret i32 0
}

declare i32 @getint(...) #1

declare void @putint(i32 noundef) #1

attributes #0 = { noinline nounwind uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!llvm.module.flags = !{!0, !1, !2, !3, !4}
!llvm.ident = !{!5}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"PIC Level", i32 2}
!2 = !{i32 7, !"PIE Level", i32 2}
!3 = !{i32 7, !"uwtable", i32 1}
!4 = !{i32 7, !"frame-pointer", i32 2}
!5 = !{!"Ubuntu clang version 14.0.0-1ubuntu1"}
