; These strings are stored in ROM with the code. All strings start on even
; addresses so that the movsw instruction can copy the strings 2 bytes at a
; time (since this computer has a 16 bit data bus). All strings are also an
; even number of characters long.

; The defined length of the strings is half of the actual length because the
; code that copies these strings around memory looks something like this:
;     mov cx,string_half_length
;     rep movsw
; In this code, the movsw instruction gets repeated cx times. Since every movsw
; instruction transfers 2 bytes, cx must be set to half the string length.

; The lengths of these strings are not stored in ROM like the strings
; themselves, but are assembled into the code during compilation.
; For example, this instruction:
;     mov cx,welcome_string_half_length
; Gets converted by the assembler to:
;     mov cx,0x001e
; Which gets compiled into binary:
;     B9 1E 00

align 2 ; Ensure that strings start on even addresses so they can be read with 16-bit string instructions (2 characters at a time)
welcome_string db "Welcome to GreenShellRage Memory Editor!"
db 0x0d, 0x0a, "Enter 'h' for help"
welcome_string_half_length equ 30

align 2
invalid_address_string db "Invalid address."
invalid_address_string_half_length equ 8

align 2
invalid_data_string db "Invalid data. "
invalid_data_string_half_length equ 7

align 2
invalid_command_string db "Invalid Command."
invalid_command_string_half_length equ 8

align 2
not_implemented_string db "Not implemented yet!"
not_implemented_string_half_length equ 10

align 2
help_string db "12ABC           - read byte from memory"
db 0x0d, 0x0a, "12ABC-12ACF     - read bytes from memory"
db 0x0d, 0x0a, "12ABC=12 34 56  - write bytes to memory"
db 0x0d, 0x0a, "12ABC=ABCD EF   - write bytes/words"
db 0x0d, 0x0a, "12ABC!          - execute code in memory"
db 0x0d, 0x0a, "0004i           - read byte from IO (i)"
db 0x0d, 0x0a, "0004I           - read word from IO (I)"
db 0x0d, 0x0a, "0004i=12 34 56  - write bytes to IO"
db 0x0d, 0x0a, "0004i=ABCD EF   - write bytes/words"
db 0x0d, 0x0a, "Not implemented yet:"
db 0x0d, 0x0a, "12ABC=/test.bin - load file to memory"
db 0x0d, 0x0a, "12ABC?          - debug code in memory"
db 0x0d, 0x0a, "Used memory (don't write): 00400-0060d"
help_string_half_length equ 249