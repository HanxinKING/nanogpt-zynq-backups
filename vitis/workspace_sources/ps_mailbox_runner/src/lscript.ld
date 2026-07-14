ENTRY(_start)

MEMORY
{
    ps7_ram_0_S_AXI_BASEADDR : ORIGIN = 0x00000000, LENGTH = 0x00030000
}

SECTIONS
{
    .text : {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
        . = ALIGN(8);
    } > ps7_ram_0_S_AXI_BASEADDR

    .data : {
        . = ALIGN(8);
        *(.data*)
        . = ALIGN(8);
    } > ps7_ram_0_S_AXI_BASEADDR

    .bss (NOLOAD) : {
        . = ALIGN(8);
        __bss_start__ = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(8);
        __bss_end__ = .;
    } > ps7_ram_0_S_AXI_BASEADDR

    .stack (NOLOAD) : {
        . = ALIGN(8);
        __stack_bottom__ = .;
        . = . + 0x4000;
        . = ALIGN(8);
        __stack_top__ = .;
    } > ps7_ram_0_S_AXI_BASEADDR
}
