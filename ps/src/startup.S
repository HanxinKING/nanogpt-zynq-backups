    .section .vectors, "ax"
    .global _start
_start:
    b reset_handler
    b .
    b .
    b .
    b .
    b .
    b .
    b .

    .text
reset_handler:
    cpsid if
    ldr sp, =__stack_top__
    bl zero_bss
    bl main
halt:
    b halt

zero_bss:
    ldr r0, =__bss_start__
    ldr r1, =__bss_end__
    mov r2, #0
1:
    cmp r0, r1
    bge 2f
    str r2, [r0], #4
    b 1b
2:
    bx lr
