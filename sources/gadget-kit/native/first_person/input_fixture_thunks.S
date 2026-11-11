/* Positive Win64 ABI fixture only: executes calls in a private fake image. */
.text
.globl InputFixtureNativeCycle
.def InputFixtureNativeCycle; .scl 2; .type 32; .endef
.seh_proc InputFixtureNativeCycle
InputFixtureNativeCycle:
 pushq %r15
 .seh_pushreg %r15
 pushq %r14
 .seh_pushreg %r14
 pushq %r13
 .seh_pushreg %r13
 pushq %r12
 .seh_pushreg %r12
 pushq %rsi
 .seh_pushreg %rsi
 pushq %rbx
 .seh_pushreg %rbx
 subq $0x208,%rsp
 .seh_stackalloc 0x208
 .seh_endprologue
 movq %rcx,%r15
 movq %rdx,0x80(%rsp)
 movq %r8,%r14
 movq %r9,%r13
 movl 0x260(%rsp),%ebx
 movss 0x268(%rsp),%xmm0
 movss %xmm0,0xa0(%rsp)
 movq $0,0x48(%rsp)
 movq 0x90(%r13),%rax
 movl 12(%r15),%ecx
 xorl %edx,%edx
 leaq 0x111863c(%r14),%r12
 jmp *%r12
.globl InputFixtureAfter90
InputFixtureAfter90:
 movq %rax,%r8
 movq %r15,%rcx
 movq %rsp,%rdx
 call InputFixtureNativeBetween
 movq 0(%r13),%r8
 movl %ebx,%ecx
 movl $50,%edx
 leaq 0x1119a81(%r14),%r12
 jmp *%r12
.globl InputFixtureAfter00
InputFixtureAfter00:
 addq $0x208,%rsp
 popq %rbx
 popq %rsi
 popq %r12
 popq %r13
 popq %r14
 popq %r15
 ret
.seh_endproc
