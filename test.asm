cpu 8086

; Memory map of computer:
; *------------------------*
; | RAM (256k)             |
; | 0x00000 - 0x3ffff      |
; *------------------------*
; | Unused (512k)          |
; | 0x40000 - 0xbffff      |
; |                        |
; |                        |
; |                        |
; *------------------------*
; | ROM (256k)             |
; | 0xc0000 - 0xfffff      |
; *------------------------*



; Memory Address Constants
ram_start_addr equ 0x00400 ; First useable address in RAM (not reserved for interrupt vectors)
ram_size equ 0x40000 ; Size of RAM
rom_start_addr equ 0xc0000 ; Start address of ROM
rom_size equ 0x40000 ; Size of ROM
reset_addr equ 0xffff0 ; Address of first instruction executed by CPU after powering on (stored in first ROM)

; IO Address Constants
lcd_data_addr equ 0x00
lcd_command_addr equ 0x02

; LCD Constants
lcd_text_columns equ 40
lcd_text_rows equ 16
lcd_horizontal_pixels equ 240
lcd_vertical_pixels equ 128



; Main code

org rom_start_addr

; Setup the code and stack segments
setup:
    ; Set stack segment to upper 64k of RAM
    mov ax,0x3000
    mov ss,ax
    ; Set stack pointer to 0
    xor sp,sp
main:
    call lcd_init

    ; Print hello world to the LCD (NOT TESTED)

    ; Set the data segment register to point to the code segment (since the string is stored in ROM with the code)
    mov ax,0xc000
    mov ds,ax
    ; Set the source index to the location of the string within the code
    mov si,hello_world_string
    ; Print the string to the display
    call lcd_print_string
    ; Halt the cpu
    hlt



; LCD subroutines (NOT FINISHED AND NOT TESTED)

; Note to self: subtract 0x20 from the ascii character code when sending text characters to the display

; Initialize the LCD (this subroutine can be optimized, but only after I verify that this code actually works)
lcd_init:
    ; Set text home address to 0x0000
    ; writeData(0x00)
    ; writeData(0x00)
    ; writeCommand(0x40)
    mov ax,0x0000
    call lcd_status_check
    out lcd_data_addr,al
    call lcd_status_check
    out lcd_data_addr,al
    mov al,0x40
    call lcd_status_check
    out lcd_command_addr,al

    ; Set text area
    ; writeData(lcd_text_columns)
    ; writeData(0x00)
    ; writeCommand(0x41)
    mov al,lcd_text_columns
    call lcd_status_check
    out lcd_data_addr,al
    xor al,al
    call lcd_status_check
    out lcd_data_addr,al
    mov al,0x40
    call lcd_status_check
    out lcd_command_addr,al

    ; Set graphics home address to 0x0300
    ; writeData(0x00)
    ; writeData(0x03)
    ; writeCommand(0x42)
    mov ax,0x0300
    call lcd_status_check
    out lcd_data_addr,al
    call lcd_status_check
    mov al,ah
    out lcd_data_addr,al
    mov al,0x30
    call lcd_status_check
    out lcd_command_addr,al

    ; Set graphics area
    ; writeData(lcd_text_columns)
    ; writeData(0x00)
    ; writeCommand(0x43)
    mov al,lcd_text_columns
    call lcd_status_check
    out lcd_data_addr,al
    xor al,al
    call lcd_status_check
    out lcd_data_addr,al
    mov al,0x43
    call lcd_status_check
    out lcd_command_addr,al

    ; Set the display to XOR mode and internal character ROM mode
    ; writeCommand(0x81)
    mov al,0x81
    call lcd_status_check
    out lcd_command_addr,al

    ; Set display mode (text on, graphics on, cursor on, blink on)
    ; writeCommand(0x9f)
    mov al,0x9f
    call lcd_status_check
    out lcd_command_addr,al

    ; Set cursor pattern
    ; writeCommand(0xa7)
    mov al,0xa7
    call lcd_status_check
    out lcd_command_addr,al

    ; Set address pointer to 0x0000
    ; writeData(0x00)
    ; writeData(0x00)
    ; writeCommand(0x24)
    mov ax,0x0000
    call lcd_status_check
    out lcd_data_addr,al
    call lcd_status_check
    out lcd_data_addr,al
    mov al,0x24
    call lcd_status_check
    out lcd_command_addr,al

    ; Set cursor position to 0, 0
    ; writeData(x_address)
    ; writeData(y_address)
    ; writeCommand(0x21)
    mov ax,0x0000 ; Stored as XXYY
    call lcd_status_check
    out lcd_data_addr,al
    call lcd_status_check
    out lcd_data_addr,al
    mov al,0x21
    call lcd_status_check
    out lcd_command_addr,al

    ret


; Repeatedly checks if bits 0 and 1 of the lcd status byte are 1
lcd_status_check:
    push ax
    mov ah,0x03
_status_loop:
    in al,lcd_command_addr
    not al
    test al,ah
    jnz _status_loop
    pop ax
    ret


; Repeatedly checks if bits 2 and 3 of the lcd status byte are 1
lcd_auto_status_check:
    push ax
    mov ah,0x0c
_auto_status_loop:
    in al,lcd_command_addr
    not al
    test al,ah
    jnz _auto_status_loop
    pop ax
    ret


; Prints a null-terminated string located at ds[si]
lcd_print_string:
    ; Start auto write
    ; writeCommand(0xb0)
    mov al,0xb0
    call lcd_status_check
    out lcd_command_addr,al
    ; Set bh register to 0x20 so that "sub al,bh" converts the character in the al register to the byte to send to the display
    ; Set bl register to 0xff so that "test bl,al" sets the zero flag if the al register contains the null character
    mov bx,0x20ff
; Loop throught string and print to display one character at a time
_print_loop:
    ; Reads 2 characters, first one in al register, next one in ah register
    ; Also increments the si register by 2
    lodsw
    ; Test if the first character is null
    test bl,al
    jz _end_print ; Exit if character is null
    ; Send first character to the display
    sub al,bh
    call lcd_auto_status_check
    out lcd_data_addr,al
    ; Test if the second character is null
    test bl,ah
    jz _end_print ; Exit if character is null
    ; Send second character to the display
    mov al,ah
    sub ah,bh
    call lcd_auto_status_check
    out lcd_data_addr,al
    jmp _print_loop
_end_print:
    ; Stop auto write
    ; writeCommand(0xb2)
    mov al,0xb0
    call lcd_auto_status_check
    out lcd_command_addr,al
    ret


; Define hello world string
hello_world_string db "Hello world!", 0





; The following code allows NASM to compile executable binary files that can be flashed
; onto the ROM chips located in the upper 256k of the 8086 address space. The 8086 starts
; executing at 0xFFFF0 (16 bytes before the end of memory) when powered on, so there needs to
; be a jump instruction there to tell the CPU to jump to the start address of the ROM (0xC0000).

times rom_size-($-$$)-0x10 db 0x00 ; Fill bytes from the end of main code to begining of reset jump instruction
jmp 0xc000:0x0 ; Jump to beginning of main code
align rom_size,db 0x00 ; Fill bytes from end of reset code to end of ROM