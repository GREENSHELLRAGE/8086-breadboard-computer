cpu 8086

; IO Device constants
; 8259 Interrupt Controller
pic_init_addr equ 0x00
pic_oper_addr equ 0x02
pic_icw1 equ 00010011b ; initialization command 4 needed, single mode, call interval 8 (ignored), edge trigger mode
pic_icw2 equ 00100000b ; Set interrupt vectors to start at 32 (IR0 pin -> interrupt 32, IR1 pin -> interrupt 33,... IR7 pin -> interrupt 39)
pic_icw4 equ 00000011b ; 8086 mode, auto eoi (end of interrupt), non buffered mode, not special fully nested mode
pic_ocw1 equ 11111110b ; All hardware interrupts masked except for 0 (uart rxready)
; 8251A UART
uart_data_addr equ 0x04
uart_command_addr equ 0x06
uart_icw1 equ 00000000b ; Reset the UART (sent 3 times)
uart_icw2 equ 01000000b ; Reset the UART
uart_icw3 equ 01001101b ; 1x baud rate, 8 bits, no parity, odd parity (ignored), 1 stop bit
uart_icw4 equ 00110111b ; Transmit enable, data terminal ready, receive enable, normal operation, reset error flags, request to send
; LCD Module
;lcd_data_addr equ 0x08 ; LCD Module
;lcd_command_addr equ 0x0A ; LCD Module





; GSR Memory Editor, the custom operating system for my 8086 breadboard computer
; It's going to be like WOZMON, but with some extra features:
; - Read/write bytes or 16 bit words to memory and IO
; - Trigger software interrupts
; - Step through code 1 instruction at a time and print register contents
; - Load files from SD cards into memory (once I eventually design a fast SD card interface and write FAT32 drivers)





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
; Everything else in ROM will be filled with 0s (for now)
prog_size equ 512 ; Size of ROM allocated to this program (must be power of 2)
; This is the value that a segment register should be set to when referencing any code labels in GSR Memory Editor
; Example: jmp gsr_segment:gsr_start --> jump to gsr_start from another program (CS is set to gsr_segment)
gsr_segment equ ((0x100000 - prog_size) >> 4)





; Memory map of computer:             Memory layout of variables in RAM:
; *------------------------* -------> *-----------------------------------------------*
; | RAM (256k)             |          | Interrupt vector table (1024 bytes)           |
; | 0x00000 - 0x3ffff      |          | 0x00000 - 0x003ff                             |
; *------------------------* ---,     *-----------------------------------------------*
; | Unused (512k)          |    |     | output buffer array (256 bytes)               |
; | 0x40000 - 0xbffff      |    |     | 0x00400 - 0x004ff                             |
; |                        |    |     *-----------------------------------------------*
; |                        |    |     | input buffer array (256 bytes)                |
; |                        |    |     | 0x00500 - 0x005ff                             |
; *------------------------*    |     *-----------------------------------------------*
; | ROM (256k)             |    |     | Other variables (8 bytes)                     |
; | 0xc0000 - 0xfffff      |    |     | output_buffer_read_ptr: 0x00600 (2 bytes)     |
; *------------------------*    |     | output_buffer_write_ptr: 0x00602 (2 bytes)    |
;                               |     | read_buffer_read_ptr: 0x00604 (2 bytes)       |
;                               |     | read_buffer_write_ptr: 0x00606 (2 bytes)      |
;                               |     *-----------------------------------------------*
;                               |     | Unused (195072 bytes)                         |
;                               |     | 0x00620 - 0x2ffff                             |
;                               |     |                                               |
;                               |     |                                               |
;                               |     |                                               |
;                               |     *-----------------------------------------------*
;                               |     | Stack segment (64k)                           |
;                               |     | 0x30000 - 0x3ffff                             |
;                               '---> *-----------------------------------------------*

; Note: CHANGE STACK SEGMENT once you know exactly how much stack GSR memory editor will need

variables_segment equ 0x0040 ; ds register will be set to this value, variables start at 0x00400
; The rest of these values are offsets from ds
; Output buffer array: 0x0000 - 0x00ff
; Input buffer array: 0x0100 - 0x01ff
output_buffer_read_ptr equ 0x0200
output_buffer_write_ptr equ 0x0202
input_buffer_read_ptr equ 0x0204
input_buffer_write_ptr equ 0x0206






org 0 ; Labels start at 0

; Initialize IO devices, interrupt vector table, and other data structures in memory
gsr_start:
    cli ; Disable hardware interrupts
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
    xor bx,bx ; bx = 0x0000
    mov ds,bx ; ds = 0x0000, ds:[bx] now points to 0x00000
    ; Set interrupt 0
    mov word [bx],gsr_division_0_handler ; Write the IP value of the interrupt routine pointer
    mov word [bx+2],cs ; Write the CS value of the interrupt routine pointer
    ; Set interrupt 1
    mov word [bx+4],gsr_trap_handler ; Write the IP value of the interrupt routine pointer
    mov word [bx+6],cs ; Write the CS value of the interrupt routine pointer
    ; Set interrupt 2
    mov word [bx+8],gsr_nmi_handler ; Write the IP value of the interrupt routine pointer
    mov word [bx+10],cs ; Write the CS value of the interrupt routine pointer
    ; Set interrupt 3
    mov word [bx+12],gsr_breakpoint_handler ; Write the IP value of the interrupt routine pointer
    mov word [bx+14],cs ; Write the CS value of the interrupt routine pointer
    ; Set interrupt 4
    mov word [bx+16],gsr_overflow_handler ; Write the IP value of the interrupt routine pointer
    mov word [bx+18],cs ; Write the CS value of the interrupt routine pointer
    ; Set interrupt 32
    mov word [bx+128],gsr_uart_rxready_routine ; Write the IP value of the interrupt routine pointer
    mov word [bx+130],cs ; Write the CS value of the interrupt routine pointer
    ; Set interrupt 33
    mov word [bx+132],gsr_uart_txready_routine ; Write the IP value of the interrupt routine pointer
    mov word [bx+134],cs ; Write the CS value of the interrupt routine pointer
    
    ; Initialize buffer read/write pointers to 0
    mov di,variables_segment ; Set es to base address of variables
    mov es,di ; es = 0x0040
    mov di,output_buffer_read_ptr ; es:[di] now points to output_buffer_read_ptr
    mov ax,bx ; ax = 0x0000
    cld ; Set direction flag to 0 (so string instructions increment di)
    stosw ; Set output_buffer_read_ptr to 0x0000, es:[di] now points to output_buffer_write_ptr
    stosw ; Set output_buffer_write_ptr to 0x0000, es:[di] now points to input_buffer_read_ptr
    inc ah ; ax = 0x0100
    stosw ; Set input_buffer_read_ptr to 0x0100, es:[di] now points to input_buffer_write_ptr
    stosw ; Set input_buffer_write_ptr to 0x0100

    ; Set stack segment to upper 64k of RAM
    mov ah,0x30 ; ax = 0x3000
    mov ss,ax ; ss = 0x3000
    mov sp,bx ; sp = 0x0000
    
    ; Print "*** Welcome to GSR Memory Editor! ***"
    ; System is initialized and ready to accept interrupts
    sti ; Enable hardware interrupts
_idle_loop:
    hlt ; Idle the CPU until an interrupt occurs
    jmp _idle_loop ; If an interrupt service routine returned back here, keep idling
    ; Note:
    ; Interrupt service routines triggered during the idle loop may return elsewhere.
    ; For example, the UART service routine may modify the return address pushed to
    ; the stack during the interrupt and "return" to a different memory address to
    ; begin executing a program.





; General flow of characters through GSR memory editor:
;
;                   ,---> gsr_uart_rxready_routine -------*--> *----------------*
;                   |      _handle_carriage_return <--,   |    | input_buffer   |
; *------------* ---'                            |    '---)--- *----------------*
; | 8251A UART |                                 |        |
; *------------* <--,                            |        '--> *----------------*
;                   |                            '-----------> | output_buffer  |
;                   '---- gsr_uart_txready_routine <---------- *----------------*

; Note to self:
; 0x0a -> line feed '\n' (macos won't send this)
; 0x0d -> carriage return '\r' (macos sends this when pressing enter, should echo "\r\n": 0x0d, 0x0a)
; 0x7f -> backspace '\b' (should echo '\b \b': 0x08, 0x20, 0x08)
; 0x1b, 0x5b, 0x41 -> up arrow
; 0x1b, 0x5b, 0x42 -> down arrow
; 0x1b, 0x5b, 0x43 -> right arrow
; 0x1b, 0x5b, 0x44 -> left arrow
; 0x1b, 0x5b, 0x33, 0x7e -> delete (fn+backspace on macos)



; Interrupt service routine for the uart receiving a character
; Register usage: ax,bx,ds,si
; General algorithm:
; read character from uart
; if (character is carriage return: 0x0d) {
;     jump to _handle_carriage_return
; } else if (character is backspace: 0x7f) {
;     if (input buffer is empty: write pointer = read pointer) {
;         return
;     } else {
;         decrement input buffer write pointer
;         write 0x08, 0x20, 0x08 into the output buffer (echo '\b \b')
;         increment output buffer write pointer by 3
;         mask the uart rxready interrupt
;         unmask the uart txready interrupt
;         return
;     }
; } else if (ascii character is text character: 0x20-0x7f) {
;     if (input buffer is full: write pointer + 1 = read pointer) {
;         return
;     } else {
;         write character into input buffer
;         increment input buffer write pointer by 1
;         write character into output buffer
;         increment output buffer write pointer by 1
;         mask the uart rxready interrupt
;         unmask the uart txready interrupt
;         return
;     }
; } else {
;     return
; }
gsr_uart_rxready_routine:
    ; Push used registers to stack
    push ax
    push bx
    push ds
    push si
    mov si,variables_segment
    mov ds,si ; ds = 0x0040
    mov si,input_buffer_write_ptr ; ds:[si] now points to input_buffer_write_ptr
    std ; Set direction flag to 1 (so string instruction decrement si)
    lodsw ; ax = input_buffer_write_ptr, ds:[si] now points to input_buffer_read_ptr
    mov bx,ax ; bx = input_buffer_write_ptr
    ; Get character from the uart
    in al,uart_data_addr ; Get character from the uart
    cmp al,0x0d ; Check if character is a carriage return
    je _handle_carriage_return
    cmp al,0x7f ; Check if character is a backspace
    je _handle_backspace
    add al,0x80 ; Map characters 0x20-0x7f --> 0xa0-0xff
    cmp al,0xa0 ; Check is character was valid (between 0x20-0x7f)
    jc _end_rxready_routine ; Character was not between 0x20-0x7f
    sub al,0x80 ; Map 0xa0-0xff --> 0x20-0x7f
    inc bl ; bx = input buffer write ptr + 1
    cmp bl,byte [si] ; Check for full input buffer
    je _end_rxready_routine ; Input buffer is full
    ; Write character into input buffer
    mov byte [si+2],bl ; update input_buffer_write_ptr
    dec bl ; bx = input buffer write ptr
    mov byte [bx],al ; write character to input buffer
    ; Write character into output buffer
    dec si
    dec si ; ds:[si] now points to output_buffer_write_ptr
    mov bx,word [si] ; bx = output_buffer_write_ptr
    mov byte [bx],al ; write character to output buffer
    inc bl
    mov byte [si],bl ; update output_buffer_write_ptr
    ; Change interrupt masks
    in al,pic_oper_addr ; Read interrupt mask register
    ; Using xor to toggle the interrupt masks is faster than setting the interrupt masks using:
    ;     or al,00000001b ; Mask uart rxready interrupt (interrupt 1 on the 8259)
    ;     and al,11111101b ; Unmask uart txready interrupt (interrupt 0 on the 8259)
    ; but it can also set them to the wrong value if the interrupt masks are set incorrectly by anything else
    xor al,00000011b ; Toggle interrupt 0 and interrupt 1 masks
    out pic_oper_addr,al ; Write interrupt mask register
    ; Pop used registers from stack and return
    pop si
    pop ds
    pop bx
    pop ax
    iret
_handle_backspace:
    cmp bl,byte [si] ; Check for empty input buffer
    je _end_rxready_routine
    dec bl ; bx = input_buffer_write_ptr
    mov byte [si+2],bl ;18 ; update input_buffer_write_ptr
    ; Write characters into output buffer
    dec si
    dec si ; ds:[si] now points to output_buffer_write_ptr
    mov bx,word [si] ; bx = output_buffer_write_ptr
    mov byte [bx],0x08 ; write backspace to output buffer
    inc bl
    mov byte [bx],0x20 ; write space to output buffer
    inc bl
    mov byte [bx],0x08 ; write backspace to output buffer
    inc bl
    mov byte [si],bl ; update output_buffer_write_ptr
    ; Change interrupt masks
    in al,pic_oper_addr ; Read interrupt mask register
    ; Using xor to toggle the interrupt masks is faster than setting the interrupt masks using:
    ;     or al,00000001b ; Mask uart rxready interrupt (interrupt 1 on the 8259)
    ;     and al,11111101b ; Unmask uart txready interrupt (interrupt 0 on the 8259)
    ; but it can also set them to the wrong value if the interrupt masks are set incorrectly by anything else
    xor al,00000011b ; Toggle interrupt 0 and interrupt 1 masks
    out pic_oper_addr,al ; Write interrupt mask register
_end_rxready_routine:
    ; Pop used registers from stack and return
    pop si
    pop ds
    pop bx
    pop ax
    iret

; gsr_uart_rxready_routine jumps here when a carriage return character was read
; This is where commands are read from the input buffer and processed
; General algorithm:
; write 0x0d, 0x0a into the output buffer (echo '\r\n')
; increment output buffer write pointer by 2
; process input buffer (not implelemted yet)
; set input buffer read pointer equal to input buffer write pointer
; mask the uart rxready interrupt
; unmask the uart txready interrupt
_handle_carriage_return:
    ; Set input buffer read pointer equal to the input buffer write pointer
    ; Note to self: this should be done as the input string is being processed (when that gets implemented)
    mov byte [si],bl

    ; Write characters into output buffer
    dec si
    dec si ; ds:[si] now points to output_buffer_write_ptr
    mov bx,word [si] ; bx = output_buffer_write_ptr
    mov byte [bx],0x0d ; write carriage return to output buffer
    inc bl
    mov byte [bx],0x0a ; write line feed to output buffer
    inc bl
    mov byte [si],bl ; update output buffer write pointer
    ; Process input buffer (not implemented yet)
    
    ; Copy test string into output buffer
    push es
    push di
    mov si,gsr_segment
    mov ds,si
    mov si,hello_world_string ; ds:[si] now points to hello world string
    ; Note to self: Remove this function call and put the copying code here to optimize
    call gsr_copy_string_to_output_buffer
    ; Change interrupt masks
    in al,pic_oper_addr ; Read interrupt mask register
    ; Using xor to toggle the interrupt masks is faster than setting the interrupt masks using:
    ;     or al,00000001b ; Mask uart rxready interrupt (interrupt 1 on the 8259)
    ;     and al,11111101b ; Unmask uart txready interrupt (interrupt 0 on the 8259)
    ; but it can also set them to the wrong value if the interrupt masks are set incorrectly by anything else
    xor al,00000011b ; Toggle interrupt 0 and interrupt 1 masks
    out pic_oper_addr,al ; Write interrupt mask register
    ; Pop used registers from stack and return
    pop di
    pop es
    pop si
    pop ds
    pop bx
    pop ax
    iret



; Copies a null-terminated string to the output buffer
; Parameters:
; - ds:[si] --> Pointer to the string to copy
; Register usage: ax,bx,ds,si,es,di
; Notes:
; - The string should not be larger than the output buffer (256 bytes)
; - For best performance, the string should start on an even byte
gsr_copy_string_to_output_buffer:
    mov di,variables_segment
    mov es,di
    mov di,output_buffer_write_ptr ; es:[di] now points to output buffer write pointer
    mov di,word es:[di] ; es:[di] now points to next character in output buffer
    mov bx,0x00ff
    cld
copy_loop:
    ; Note to self: It might be faster to use the MOVS instructon here
    lodsw ; Load 2 characters of string
    test al,bl ; Check of the first character is 0
    jz end_copy_loop ; Character was 0
    ; Character is not 0, write it to the output buffer
    stosb ; Copy character to output buffer
    and di,bx ; Ensure the write pointer stays between 0 and 255
    test ah,bl ; Check of the second character is 0
    jz end_copy_loop ; Character was 0
    ; Character is not 0, write it to the output buffer
    mov al,ah ; Copy second character to al
    stosb ; Copy character to output buffer
    and di,bx ; Ensure the write pointer stays between 0 and 255
    jmp copy_loop
end_copy_loop:
    mov bx,output_buffer_write_ptr ; es:[bx] now points to the output buffer write pointer
    mov word es:[bx],di ; Update the output buffer write pointer
    ret




; Interrupt service routine for the uart ready to transmit a character
; THIS INTERRUPT SHOULD BE MASKED IF THE OUTPUT BUFFER IS EMPTY!!!
; Register usage: ax,ds,si
; General algorithm:
; read next character
; output next character
; increment read pointer
; if (output buffer is empty) {
;     mask the uart txready interrupt
;     unmask the uart rxready interrupt
;     return
; } else {
;     return
; }
gsr_uart_txready_routine:
    ; Push used registers to stack
    push ax
    push ds
    push si
    mov si,variables_segment
    mov ds,si ; ds = 0x0040
    mov si,output_buffer_read_ptr ; ds:[si] now points to output_buffer_read_ptr
    mov si,word [si] ; si = output_buffer_read_ptr, ds:[si] now points to next character in output buffer
    cld ; Set direction flag to 0 (so string instruction increment si)
    lodsb ; load next character into al
    out uart_data_addr,al ; Output next character to uart
    mov ax,si ; ax = output_buffer_read_ptr
    mov si,output_buffer_read_ptr ; ds:[si] now points to output_buffer_read_ptr
    mov byte [si],al ; update output_buffer_read_ptr
    cmp al,byte [si+2] ; Check if output buffer is empty (output_buffer_read_ptr = output_buffer_write_ptr)
    je _mask_txready_interrupt ; Output buffer is empty
    pop si
    pop ds
    pop ax
    iret
_mask_txready_interrupt:
    ; Change interrupt masks
    in al,pic_oper_addr ; Read interrupt mask register
    ; Using xor to toggle the interrupt masks is faster than setting the interrupt masks using:
    ;     or al,00000010b ; Mask uart rxready interrupt (interrupt 1 on the 8259)
    ;     and al,11111110b ; Unmask uart txready interrupt (interrupt 0 on the 8259)
    ; but it can also set them to the wrong value if the interrupt masks are set incorrectly by anything else
    xor al,00000011b ; Toggle interrupt 0 and interrupt 1 masks
    out pic_oper_addr,al ; Write interrupt mask register
    ; Pop used registers from stack and return
    pop si
    pop ds
    pop ax
    iret



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


align 2 ; Ensure that strings start on even addresses so they can be read with 16-bit string instructions (2 characters at a time)
hello_world_string db "Hello world, input string processing isn't implemented yet, this response is hardcoded!", 0x0d, 0x0a, 0x00


; Insert a jump instruction at 0xffff0 (where the CPU starts executing after powering on)
times prog_size-($-$$)-0x10 db 0x00 ; Fill bytes from the end of GSR memory editor to the reset jump instruction
jmp gsr_segment:gsr_start ; Start GSR Memory Editor
align prog_size,db 0x00 ; Fill remaining bytes of ROM