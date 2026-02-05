cpu 8086

%include "constants_and_addresses.asm"



; GSR Memory Editor, the custom operating system for my 8086 breadboard computer
; It's going to be like WOZMON, but with some extra features:
; - Read/write bytes or 16 bit words to memory and IO
; - Trigger software interrupts
; - Step through code 1 instruction at a time and print register contents
; - Load files from SD cards into memory (once I eventually design a fast SD card interface and write FAT32 drivers)



; IO Device initialization command bytes
; 8259 Interrupt Controller
pic_icw1 equ 00010011b ; initialization command 4 needed, single mode, call interval 8 (ignored), edge trigger mode
pic_icw2 equ 00100000b ; Set interrupt vectors to start at 32 (IR0 pin -> interrupt 32, IR1 pin -> interrupt 33,... IR7 pin -> interrupt 39)
pic_icw4 equ 00000011b ; 8086 mode, auto eoi (end of interrupt), non buffered mode, not special fully nested mode
pic_ocw1 equ 11111101b ; All hardware interrupts masked except for 1 (uart txready)
; 8251A UART
uart_icw1 equ 00000000b ; Reset the UART (sent 3 times)
uart_icw2 equ 01000000b ; Reset the UART
uart_icw3 equ 01001110b ; 16x baud rate, 8 bits, no parity, odd parity (ignored), 1 stop bit
uart_icw4 equ 00110111b ; Transmit enable, data terminal ready, receive enable, normal operation, reset error flags, request to send



org 0 ; Labels start at 0

; This is the very first code that the CPU will jump to after powering on
; Initialize IO devices, interrupt vector table, and other data structures in memory
gsr_start:
    cli ; Disable hardware interrupts
    cld ; Clear direction flag so string instructions increment pointers
    ; Initialize IO devices
    ; Optimization note:
    ; The expression ((pic_icw2 << 8) + pic_icw1) creates a single 16 bit word from the 2 defined bytes at compile time (using nasm, may not work in other assemblers)
    ; This allows me to load 2 defined bytes into the CPU using just 1 instruction, which saves a few bytes of code and some precious clock cycles
    ; Initialize the 8259 interrupt controller
    mov ax,((pic_icw2 << 8) + pic_icw1) ; al = pic_icw1, ah = pic_icw2
    out pic_init_addr,al
    mov dx,pic_oper_addr ; Loading pic_oper_addr into dx to save some clock cycles when doing repeated writes to the same address
    mov al,ah ; al = pic_icw2
    out dx,al ; pic_oper_addr <-- pic_icw2
    mov ax,((pic_ocw1 << 8) + pic_icw4) ; al = pic_icw4, ah = pic_ocw1
    out dx,al ; pic_oper_addr <-- pic_icw4
    mov al,ah ; al = pic_ocw1
    out dx,al ; pic_oper_addr <-- pic_ocw1
    ; Initialize the 8251A uart
    mov ax,((uart_icw2 << 8) + uart_icw1) ; al = uart_icw1, ah = uart_icw2
    mov dx,uart_command_addr ; Loading uart_command_addr into dx to save some clock cycles when doing repeated writes to the same address
    out dx,al ; uart_command_addr <-- uart_icw1
    out dx,al ; uart_command_addr <-- uart_icw1
    out dx,al ; uart_command_addr <-- uart_icw1
    mov al,ah ; al = uart_icw2
    out dx,al ; uart_command_addr <-- uart_icw2
    mov ax,((uart_icw4 << 8) + uart_icw3) ; al = uart_icw3, ah = uart_icw4
    out dx,al ; uart_command_addr <-- uart_icw3
    mov al,ah ; al = uart_icw4
    out dx,al ; uart_command_addr <-- uart_icw4
    
    ; Set up the interrupt vector table
    xor ax,ax ; ax = 0x0000
    mov es,ax
    mov di,ax ; es:[di] now points to 0x00000
    ; Set interrupt 0
    mov ax,gsr_division_0_handler ; Write the IP value of the interrupt routine pointer
    stosw
    mov ax,cs ; Write the CS value of the interrupt routine pointer
    stosw
    ; Set interrupt 1
    mov ax,gsr_trap_handler ; Write the IP value of the interrupt routine pointer
    stosw
    mov ax,cs ; Write the CS value of the interrupt routine pointer
    stosw
    ; Set interrupt 2
    mov ax,gsr_nmi_handler ; Write the IP value of the interrupt routine pointer
    stosw
    mov ax,cs ; Write the CS value of the interrupt routine pointer
    stosw
    ; Set interrupt 3
    mov ax,gsr_breakpoint_handler ; Write the IP value of the interrupt routine pointer
    stosw
    mov ax,cs ; Write the CS value of the interrupt routine pointer
    stosw
    ; Set interrupt 4
    mov ax,gsr_overflow_handler ; Write the IP value of the interrupt routine pointer
    stosw
    mov ax,cs ; Write the CS value of the interrupt routine pointer
    stosw
    ; Set interrupt 32
    mov di,0x0080 ; es:[di] now points to 0x00080
    mov ax,gsr_uart_rxready_routine ; Write the IP value of the interrupt routine pointer
    stosw
    mov ax,cs ; Write the CS value of the interrupt routine pointer
    stosw
    ; Set interrupt 33
    mov ax,gsr_uart_txready_routine ; Write the IP value of the interrupt routine pointer
    stosw
    mov ax,cs ; Write the CS value of the interrupt routine pointer
    stosw
    
    ; Initialize output buffer
    mov ds,ax
    mov si,welcome_string ; ds:[si] points to welcome string
    mov cx,welcome_string_half_length ; cx has nomber of string copy operations to do
    mov di,(variables_segment << 4) ; di = 0x0400, es:[di] points to outbuf[0]
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Copy string to output buffer
    rep movsw
    ; Output carriage return + line feed
    stosw
    ; Output "> "
    mov ax,0x203e
    stosw
    ; Initialize inbuf and outbuf pointers
    mov di,((variables_segment << 4) + outbuf_writeptr) ; di = 0x0600, es:[di] points to outbuf_writeptr
    mov ax,((welcome_string_half_length << 1) + 6) ; ax = number of characters in outbuf
    stosw ; outbuf_writeptr = number of characters in outbuf, es:[di] points to outbuf_readptr
    mov ax,es ; ax = 0x0000
    stosw ; outbuf_readptr = 0x0000, es:[di] points to inbuf_writeptr
    inc ah ; ax = 0x0100
    stosw ; inbuf_writeptr = 0x0000
    ; startptr_ip, startptr_cs, endptr_ip, endptr_cs do not need to be initialized here
    ; They are always set to the correct value before they are read and used

    ; Set stack segment to upper 64k of RAM (0x3000)
    ; CHANGE THIS once you know exactly how much stack GSR memory editor will need
    mov ah,0x30 ; ax = 0x3000
    mov ss,ax ; ss = 0x3000
    mov sp,es ; sp = 0x0000
    
    ; System is initialized and ready to accept interrupts
    sti ; Enable hardware interrupts
_idle_loop:
    hlt ; Idle the CPU until an interrupt occurs
    jmp _idle_loop ; If an interrupt service routine returned back here, keep idling
    ; Note:
    ; Interrupt service routines triggered during the idle loop may return elsewhere.
    ; For example, the UART rx_ready routine may modify the return address pushed to
    ; the stack during the interrupt and "return" to a different memory address to
    ; begin executing a program.



; General flow of characters through GSR memory editor:
;
;                   ,---> gsr_uart_rxready_routine -------*--> *---------*
;                   |              gsr_run_command <--,   |    | inbuf   |
; *------------* ---'                            |    '---)--- *---------*
; | 8251A UART |                                 |        |
; *------------* <--,                            |        '--> *---------*
;                   |                            '-----------> | outbuf  |
;                   '---- gsr_uart_txready_routine <---------- *---------*

; Note to self:
; 0x0a -> line feed '\n' (macos won't send this)
; 0x0d -> carriage return '\r' (macos sends this when pressing enter, should echo "\r\n": 0x0d, 0x0a)
; 0x7f -> backspace '\b' (should echo '\b \b': 0x08, 0x20, 0x08)
; 0x1b, 0x5b, 0x41 -> up arrow
; 0x1b, 0x5b, 0x42 -> down arrow
; 0x1b, 0x5b, 0x43 -> right arrow
; 0x1b, 0x5b, 0x44 -> left arrow
; 0x1b, 0x5b, 0x33, 0x7e -> delete (fn+backspace on macos)

; These interrupt service routines have not been implemented yet and they currently do absolutely nothing
gsr_nmi_handler:
    ; Print "*** GSR Memory Editor ***\nNMI pin (interrupt 2)\n"
    iret

gsr_trap_handler: ; interrupt 1 service routine
    ; Print "*** Single step (interrupt 1) ***"
gsr_breakpoint_handler: ; interrupt 3 service routine
    ; Print "*** Breakpoint (interrupt 3) ***"
gsr_division_0_handler: ; interrupt 0 service routine
    ; Print: "*** Division by 0 (interrupt 0) ***"
    jmp _print_registers
gsr_overflow_handler: ; interrupt 4 service routine
    ; Print "*** Overflow (interrupt 4) ***"
_print_registers:
    ; Print register contents
    ; Print "--- Debugger Options ---\nS: step, R: run, X: stop executing"
    ; Set the uart rx interrupt routine to one that just receives one character
    ; sti ; Enable hardware interrupts
    ; hlt
    ; character = \n: set trap flag
    ; character = X: jmp gsr_segment:gsr_start
    ; character = R: iret
    ; character = anything else: jump back to hlt instruction
    iret

; Interrupt service routines implemented in other files
%include "gsr_uart_txready_routine.asm"
%include "gsr_uart_txready_memread_routine.asm"
%include "gsr_uart_rxready_routine.asm"
; Strings referenced by the code
%include "strings.asm"

; Memory map of computer:             Memory layout of this ROM:
; *------------------------*    .---> *------------------------*
; | RAM (256k)             |    |     | Currently Unused       |
; | 0x00000 - 0x3ffff      |    |     |                        |
; *------------------------*    |     |                        |
; | Unused (512k)          |    |     |                        |
; | 0x40000 - 0xbffff      |    |     |                        |
; |                        |    |     |                        |
; |                        |    |     |                        |
; |                        |    |     |                        |
; *------------------------* ---'     |                        |
; | ROM (256k)             |          *------------------------*
; | 0xc0000 - 0xfffff      |          | GSR Memory Editor      |
; *------------------------* -------> *------------------------*

; This program will be in the upper portion of the 8086 address space in ROM
; This is the value that a segment register should be set to when referencing any code labels in GSR Memory Editor
; Example: jmp gsr_segment:gsr_start --> jump to gsr_start from another program (CS is set to gsr_segment)
gsr_segment equ ((0x100000 - ($-$$) - 0x10) >> 4)

; Insert a jump instruction at 0xffff0 (where the CPU starts executing after powering on)
align 16,db 0x00 ; Fill bytes from the end of GSR memory editor to the reset jump instruction
jmp gsr_segment:gsr_start ; Start GSR Memory Editor
align 16,db 0x00 ; Fill remaining bytes of ROM