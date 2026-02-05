cpu 8086

; IO Device addresses

; 8259 Interrupt Controller
pic_init_addr equ 0x00
pic_oper_addr equ 0x02
; 8251A UART
uart_data_addr equ 0x01
uart_command_addr equ 0x03
; LCD Module
;lcd_data_addr equ 0x08 ; LCD Module
;lcd_command_addr equ 0x0A ; LCD Module


; Memory constants

; Memory map of computer:             Memory layout of variables in RAM:
; *------------------------* -------> *-----------------------------------------------*
; | RAM (256k)             |          | Interrupt vector table (1024 bytes)           |
; | 0x00000 - 0x3ffff      |          | 0x00000 - 0x003ff                             |
; *------------------------* ---,     *-----------------------------------------------*
; | Unused (512k)          |    |     | outbuf (256 bytes)                            |
; | 0x40000 - 0xbffff      |    |     | 0x00400 - 0x004ff                             |
; |                        |    |     *-----------------------------------------------*
; |                        |    |     | inbuf (256 bytes)                             |
; |                        |    |     | 0x00500 - 0x005ff                             |
; *------------------------*    |     *-----------------------------------------------*
; | ROM (256k)             |    |     | Other variables (14 bytes)                    |
; | 0xc0000 - 0xfffff      |    |     | outbuf_writeptr: 0x00600 (2 bytes)            |
; *------------------------*    |     | outbuf_readptr: 0x00602 (2 bytes)             |
;                               |     | inbuf_writeptr: 0x00604 (2 bytes)             |
;                               |     | startptr_ip: 0x00606 (2 bytes)                |
;                               |     | startptr_cs: 0x00608 (2 bytes)                |
;                               |     | endptr_ip: 0x0060a (2 bytes)                  |
;                               |     | endptr_cs: 0x0060c (2 bytes)                  |
;                               |     *-----------------------------------------------*
;                               |     | Unused                                        |
;                               |     | 0x0060e - 0x2ffff                             |
;                               |     |                                               |
;                               |     |                                               |
;                               |     |                                               |
;                               |     *-----------------------------------------------*
;                               |     | Stack segment (64k)                           |
;                               |     | 0x30000 - 0x3ffff                             |
;                               '---> *-----------------------------------------------*

variables_segment equ 0x0040 ; ds register will be set to this value, variables start at 0x00400
; The rest of these values are offsets from variables_segment
outbuf_writeptr equ 0x0200
outbuf_readptr equ 0x0202
inbuf_writeptr equ 0x0204
startptr_ip equ 0x0206
startptr_cs equ 0x0208
endptr_ip equ 0x020a
endptr_cs equ 0x020c