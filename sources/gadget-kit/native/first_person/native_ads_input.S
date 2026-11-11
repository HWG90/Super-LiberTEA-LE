/* Win64 SDK data-pointer callbacks. These edit no game executable bytes.
   At entry R15 is the native request; caller S = entry RSP+8. */
.text
.p2align 4
.globl NADSE_Input90Thunk
.def NADSE_Input90Thunk; .scl 2; .type 32; .endef
.seh_proc NADSE_Input90Thunk
NADSE_Input90Thunk:
 subq $56,%rsp
 .seh_stackalloc 56
 .seh_endprologue
 movq %r15,%r8
 leaq 64(%rsp),%r9
 movq 56(%rsp),%rax
 movq %rax,32(%rsp)
 call NADSE_Input90Call
 addq $56,%rsp
 ret
.seh_endproc

/* An explicit language handler is required: MinGW optimization can remove
   C++ __try around an intrinsic atomic, leaving no exception scope at all. */
.p2align 4
.globl NADSE_InputCompareExchange
.def NADSE_InputCompareExchange; .scl 2; .type 32; .endef
.seh_proc NADSE_InputCompareExchange
.seh_handler NADSE_InputCASException,@except
NADSE_InputCompareExchange:
 .seh_endprologue
 movl %edx,%eax
.globl NADSE_InputCASFault
NADSE_InputCASFault:
 lock cmpxchgl %r8d,(%rcx)
 movl %eax,(%r9)
 movl $1,%eax
 ret
.globl NADSE_InputCASRecovery
NADSE_InputCASRecovery:
 xorl %eax,%eax
 ret
.seh_endproc
.p2align 4
.globl NADSE_Input00Thunk
.def NADSE_Input00Thunk; .scl 2; .type 32; .endef
.seh_proc NADSE_Input00Thunk
NADSE_Input00Thunk:
 subq $56,%rsp
 .seh_stackalloc 56
 .seh_endprologue
 movq %r15,%r8
 leaq 64(%rsp),%r9
 movq 56(%rsp),%rax
 movq %rax,32(%rsp)
 call NADSE_Input00Call
 addq $56,%rsp
 ret
.seh_endproc
