cpu 8086

; NOTE TO SELF:
; The method of converting bytes to ascii characters (Example:
; 0x5a --> 0x35, 0x41) is not optimal, using a 512 byte lookup
; table would be slightly faster. I really wish I discovered
; this sooner before writing thousands of lines of assembly.
; Despite not being optimal, the current method is branchless
; and quite fast so I'll probably work on SD card support before
; rewriting a good portion of the operating system lol

; INPORTANT THING TO IMPLEMENT
; To avoid missing input characters, make sure the RTS (request
; to send) and CTS (clear to send) pins on the UART indicate to
; the terminal that we are not ready to receive characters until
; we are finished processing user input.



; First parameter is the index of the string relative to gsr_segment
; Second parameter is the length of the string divided by 2
%macro copy_string_to_outbuf 2
    mov di,ds
    mov es,di
    xor di,di ; es:[di] points to outbuf[0]
    mov si,cs
    mov ds,si
    mov si,%1 ; ds:[si] points to string
    mov cx,%2 ; cx has number of string copy operations to do
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
    mov word es:[outbuf_writeptr],di ; update outbuf_writeptr
    xor al,al
    mov byte es:[inbuf_writeptr],al ; set inbuf_writeptr to 0
%endmacro

%macro toggle_interrupt_masks 0
    ; Change interrupt masks
    in al,pic_oper_addr ; Read interrupt mask register
    ; Using xor to toggle the interrupt masks is faster than setting the interrupt masks using:
    ;     or al,00000001b ; Mask uart rxready interrupt (interrupt 1 on the 8259)
    ;     and al,11111101b ; Unmask uart txready interrupt (interrupt 0 on the 8259)
    ; but it can also set them to the wrong value if the interrupt masks are set incorrectly by anything else
    xor al,00000011b ; Toggle interrupt 0 and interrupt 1 masks
    out pic_oper_addr,al ; Write interrupt mask register
%endmacro

%macro pop_and_return 0
    pop bp
    pop di
    pop es
    pop dx
    pop cx
    pop bx
    pop si
    pop ds
    pop ax
    iret
%endmacro



; Interrupt service routine for the uart receiving a character
; char <-- UART
; if (char == 0x0d) {
;     if (inbuf_writeptr == 0) {
;         outbuf[0] = 0x0d
;         outbuf[1] = 0x0a
;         outbuf[2] = 0x3e
;         outbuf[3] = 0x20
;         outbuf_writeptr = 4
;         mask the uart rxready interrupt
;         unmask the uart txready interrupt
;         return
;     } else {
;         goto gsr_run_command
;     }
; }
; if (char == 0x7f) {
;     if (inbuf_writeptr == 0) {
;         return
;     } else {
;         outbuf[0] = 0x08
;         outbuf[1] = 0x20
;         outbuf[2] = 0x08
;         outbuf_writeptr = 3
;         mask the uart rxready interrupt
;         unmask the uart txready interrupt
;         return
;     }
; }
; if (char >= 0x20 && char <= 0x7f) {
;     if (inbuf_writeptr == 0x1ff) {
;         return
;     } else {
;         inbuf[inbuf_writeptr] = char
;         inbuf_writeptr++
;         outbuf[0] = char
;         outbuf_writeptr = 1
;         mask the uart rxready interrupt
;         unmask the uart txready interrupt
;         return
;     }
; }
gsr_uart_rxready_routine:
    push ax
    push ds
    push si
    mov si,variables_segment
    mov ds,si ; ds = 0x0040
    mov si,inbuf_writeptr ; ds:[si] now points to inbuf_writeptr
    in al,uart_data_addr ; Read character from the uart
    cmp al,0x0d ; Check if character is a carriage return
    je _handle_carriage_return
    cmp al,0x7f ; Check if character is a backspace
    je _handle_backspace
    add al,0x80 ; Map characters 0x20-0x7f --> 0xa0-0xff
    cmp al,0xa0 ; Check is character was valid (between 0x20-0x7f)
    jb _end_rxready_routine ; Character was not between 0x20-0x7f
    sub al,0x80 ; Map 0xa0-0xff --> 0x20-0x7f
    cmp byte [si],0xff ; Check for full input buffer
    je _end_rxready_routine
    mov si,word[si] ; ds:[si] points to inbuf[inbuf_writeptr]
    mov byte [si],al ; inbuf[inbuf_writeptr] = char
    inc word [inbuf_writeptr] ; inbuf_writeptr++
    mov byte [0x0000],al ; outbuf[0] = char
    mov al,0x01
    mov byte [outbuf_writeptr],al ; outbuf_writeptr = 1
    toggle_interrupt_masks
_end_rxready_routine:
    ; Pop used registers from stack and return
    pop si
    pop ds
    pop ax
    iret
_handle_backspace:
    mov ax,word [si] ; ax = inbuf_writeptr
    cmp al,ah ; ah will always be 0x01 here
    jb _end_rxready_routine ; inbuf is empty, return
    dec ax ; inbuf_writeptr--
    mov word [si],ax
    mov ax,0x2008
    mov word [0x0000],ax ; outbuf[0] = 0x08, outbuf[1] = 0x20
    mov byte [0x0002],al ; outbuf[2] = 0x08
    mov al,0x03
    mov byte [outbuf_writeptr],al ; outbuf_writeptr = 3
    toggle_interrupt_masks
    ; Pop used registers from stack and return
    pop si
    pop ds
    pop ax
    iret
_handle_carriage_return:
    mov ax,word [si] ; ax = inbuf_writeptr
    cmp al,ah ; ah will always be 0x01 here
    ja gsr_run_command ; inbuf has characters, parse and run command
    je single_character_command ; inbuf has exactly 1 character
    ; inbuf is empty, no command to parse
    ; Output carriage return + line feed
    mov ax,0x0a0d
    mov word [0x0000],ax
    ; Output "> "
    mov ax,0x203e
    mov word [0x0002],ax
    mov al,0x04
    mov byte [outbuf_writeptr],al
    toggle_interrupt_masks
    ; Pop used registers from stack and return
    pop si
    pop ds
    pop ax
    iret



; This is where single character commands are handled
; These are typically used for just printing out a certain string
single_character_command:
    mov al,byte [0x0100] ; Read command
    or al,0x20
    cmp al,0x68 ; 'h'
    ; Push more used registers to stack
    push cx
    push es
    push di
    mov di,ds
    mov es,di
    xor di,di ; es:[di] points to outbuf[0]
    mov si,cs
    mov ds,si
    cmp al,0x68 ; 'h'
    jne invalid_address_1 ; Character was not h
    ; Character was h, print help string
    ; THIS IS SKETCHY!!!
    ; The help string is larger than the outbuf and will spill into the inbuf
    ; This should be ok since the contents of the inbuf are not needed right now
    mov si,help_string
    mov cx,help_string_half_length
    jmp copy_string
invalid_address_1:
    mov si,invalid_address_string
    mov cx,invalid_address_string_half_length
copy_string:
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
    mov word es:[outbuf_writeptr],di ; update outbuf_writeptr
    xor al,al
    mov byte es:[inbuf_writeptr],al ; set inbuf_writeptr to 0
    toggle_interrupt_masks
    ; Pop used registers from stack and return
    pop di
    pop es
    pop cx
    pop si
    pop ds
    pop ax
    iret



; This is where user commands are read from the input buffer and executed
gsr_run_command:
    ; Push used registers
    push bx
    push cx
    push dx
    push es
    push di
    push bp

    ; Single character commands may be implemented in the future
    ;je single_character_command
    ; ** More checks can be added here for implementing future commands **

    ; Assuming that the command starts with a memory or IO address
    cmp al,0x05
    jb invalid_address ; Command is less than 5 characters
    ; Load first 2 characters of inbuf
    mov si,0x0100 ; ds:[si] points to inbuf[0]
    mov di,ax
    lodsw
    ; Set up registers with frequently used values
    mov bx,0x2089
    mov cx,0xfa0a
    mov bp,0x0f0f ; Using pointer registers for data to make this slightly faster lol
    ; Parse first 4 ascii values of address into dx
    xor ax,0x3030 ;3 map 0x3*->0x0*, 0x4*->0x7*, 0x6*->0x5*
    cmp al,cl
    jb addr_char2
    or al,bh
    add al,bl
    cmp al,ch
    jb invalid_address
addr_char2:
    cmp ah,cl
    jb addr_char3
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb invalid_address
addr_char3:
    mov dx,ax
    lodsw
    xor ax,0x3030 ;3 map 0x3*->0x0*, 0x4*->0x7*, 0x6*->0x5*
    cmp al,cl
    jb addr_char4
    or al,bh
    add al,bl
    cmp al,ch
    jb invalid_address
addr_char4:
    cmp ah,cl
    jb addr_next
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb invalid_address
addr_next:
    xchg ah,dl
    and ax,bp
    shl ax,1
    shl ax,1
    and dx,bp
    shl ax,1
    shl ax,1
    or dx,ax ; Most significant 16 bits of address in dx
    ; Load next 2 characters fron inbuf
    lodsw
    ; Finish parsing address
    xor al,0x30
    cmp al,cl
    jb memory_address_parsed
    ; Check if this is an IO address
    cmp al,0x59 ; Check if next character is 'i' (after xor al,0x30)
    je io8 ; 8 bit IO address
    cmp al,0x79 ; Check if next character is 'I' (after xor al,0x30)
    je io16 ; 16 bit IO address
    or al,bh
    add al,bl
    cmp al,ch
    jae memory_address_parsed
invalid_address:
    copy_string_to_outbuf invalid_address_string, invalid_address_string_half_length
    toggle_interrupt_masks
    pop_and_return


io8:
    ; Check inbuf_writeptr
    cmp di,si ; si is always 0x0106 here
    jae jump_to_io_write ; Command is at least 6 characters
    jmp io8_read ; Command is exactly 5 characters, read IO address
io16:
    ; Check inbuf_writeptr
    cmp di,si ; si is always 0x0106 here
    jae jump_to_io_write ; Command is at least 6 characters
    jmp io16_read ; Command is exactly 5 characters, read IO address
jump_to_io_write:
    jmp io_write ; Command is at least 6 characters


memory_address_parsed:
    ; Check inbuf_writeptr
    cmp di,si ; si is always 0x0106 here
    jb memory_read_single_byte ; Command is exactly 5 characters, read byte from memory
    ; Command is at least 6 characters, check the next character after the address
    cmp ah,0x21 ; '!'
    je execute_memory
    cmp ah,0x3f ; '?'
    je execute_memory
    cmp ah,0x2d ; '-'
    je memory_read_many_bytes
    ; Assuming that this is a memory write command
    jmp memory_write


execute_memory:
    mov bl,al
    and bx,bp ; ds and bx have the values of cs and ip to put onto the return stack
    mov bp,sp ; ss:[bp] points to the stack
    xor al,al
    mov byte [inbuf_writeptr],al ; set inbuf_writeptr to 0
    ; Change the return address of this interrupt to the parsed address from the user
    mov word [bp+18],bx
    mov word [bp+20],dx
    ; Since si is always 0x0106 here, and ax is either 0x2100 or 0x3f00 here, this will set ax to 0x0100 only if ax is 0x3f00
    shr ah,1
    and ax,si
    ; If ax is 0x0100, this will trigger the trap interrupt after executing the first instruction that this interrupt returns to
    or word [bp+22],ax
    pop_and_return


memory_read_single_byte:
    mov di,ds
    mov es,di
    xor di,di ; es:[di] points to outbuf[0]
    mov bl,al
    and bx,bp
    mov ds,dx ; ds:[bx] points to the desired memory location
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Manually set the auxiliary carry flag to 0
    ; This ensures that the upcoming daa instruction correctly performs the first step of the conversion
    sahf ;4,1 ah is always 0x0a here, so SF, ZF, AF, PF, and CF are all set to 0
    ; Read byte into al
    mov al,byte [bx]
    ; Split byte into nibbles
    mov ah,al
    shr ah,1
    shr ah,1
    shr ah,1
    shr ah,1
    and ax,bp
    ; Convert nibbles to ascii
    daa ;4 Map 0x00-0x09 -> 0x00-0x09 and 0x0a-0x0f -> 0x10-0x15
    cmp cl,al ;3 Set carry flag if al is 0x10-0x15
    adc al,0x30 ;4 Map 0x00-0x09 -> 0x30-0x39 and 0x10-0x15 -> 0x41-0x46
    xchg al,ah
    daa
    cmp cl,al
    adc al,0x30
    ; Output ascii bytes
    stosw
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Output "> "
    mov ax,0x203e
    stosw
    mov word es:[outbuf_writeptr],di ; update outbuf_writeptr
    xor al,al
    mov byte es:[inbuf_writeptr],al ; set inbuf_writeptr to 0
    toggle_interrupt_masks
    pop_and_return


memory_read_many_bytes:
    ; Update startptr
    and ax,0x000f
    mov word [startptr_ip],ax
    mov ax,dx
    mov word [startptr_cs],ax
    ; Parse next address
    lodsw
    xor ax,0x3030 ;3 map 0x3*->0x0*, 0x4*->0x7*, 0x6*->0x5*
    cmp al,cl
    jb next_addr_char2
    or al,bh
    add al,bl
    cmp al,ch
    ; This jump instruction is exactly 127 bytes away from the place it jumps to
    ; Adding a single byte of code after here will make this jump slower
    jb invalid_address_2
next_addr_char2:
    cmp ah,cl
    jb next_addr_char3
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb invalid_address_2
next_addr_char3:
    mov dx,ax
    lodsw
    xor ax,0x3030
    cmp al,cl
    jb next_addr_char4
    or al,bh
    add al,bl
    cmp al,ch
    jb invalid_address_2
next_addr_char4:
    cmp ah,cl
    jb next_addr_char5
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb invalid_address_2
next_addr_char5:
    xchg ah,dl
    and ax,bp
    shl ax,1
    shl ax,1
    and dx,bp
    shl ax,1
    shl ax,1
    or dx,ax
    ; Load next character fron inbuf
    lodsb
    ; Check that the correct number of characters for the next address have been entered
    cmp si,di
    jne invalid_address_2
    xor al,0x30
    cmp al,cl
    jb next_addr_next
    or al,bh
    add al,bl
    cmp al,ch
    jb invalid_address_2
next_addr_next:
    ; Update endptr
    and ax,bp
    mov word [endptr_ip],ax
    mov word [endptr_cs],dx
    ; Output carriage return + line feed
    xor si,si
    mov ax,0x0a0d
    mov word [si],ax
    ; Update inbuf_writeptr
    ; Note: These 2 mov instructions can be combined into a slower mov instruction:
    ; mov word [inbuf_writeptr],si
    ; Only do this if you need to save 1 byte of space to make the first jump instruction to invalid_address_2 fast
    mov ax,si
    mov byte [inbuf_writeptr],al
    ; Update outbuf_writeptr
    mov al,0x02
    mov word [outbuf_writeptr],ax
    ; Change txready interrupt routine
    mov ds,si
    mov ax,gsr_uart_txready_memread_routine
    mov word [0x0084],ax
    toggle_interrupt_masks
    pop_and_return
invalid_address_2:
    copy_string_to_outbuf invalid_address_string, invalid_address_string_half_length
    toggle_interrupt_masks
    pop_and_return



load_file_to_memory:
    ; Note:
    ; When implementing this, keep the code as small as possible to ensure the
    ; conditional jump to here is within 127 bytes
    jmp not_implemented


memory_invalid_command:
    copy_string_to_outbuf invalid_command_string, invalid_command_string_half_length
    toggle_interrupt_masks
    pop_and_return
memory_write:
    cmp ah,0x3d ; '='
    jne memory_invalid_command
    ; Set up registers
    mov ah,bh
    and ax,bp
    mov es,dx
    mov bp,di
    mov di,ax ; es:[di] point to the desired memory locaton
    ; Parse sequence of ascii bytes/words separated by any non-hex characters
    lodsw ; Read next 2 characters of inbuf
    cmp al,0x2f ; '/'
    je load_file_to_memory ; String is actually a file name
    xor ax,0x3030
    ; Attempt to parse byte
    cmp al,cl
    jb memory_data_parse_char2_0 ; Valid hex character
    or al,bh
    add al,bl
    cmp al,ch
    jae memory_data_parse_char2_0 ; Valid hex character
    jmp memory_data_parse_loop_1
memory_data_parse_loop_0:
    lodsw ; Read next 2 characters of inbuf
    xor ax,0x3030
    ; Attempt to parse byte
    cmp al,cl
    jb memory_data_parse_char2_0 ; Valid hex character
    or al,bh
    add al,bl
    cmp al,ch
    jae memory_data_parse_char2_0 ; Valid hex character
    jmp memory_data_parse_loop_1
memory_invalid_data_0:
    copy_string_to_outbuf invalid_data_string, invalid_data_string_half_length
    toggle_interrupt_masks
    pop_and_return
memory_data_parse_char2_0:
    cmp ah,cl
    jb memory_data_parse_char3_0
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb memory_invalid_data_0
memory_data_parse_char3_0:
    and ax,0x0f0f ; First 2 nibbles in ax
    cmp bp,si ; Check inbuf_writeptr
    jb memory_invalid_data_0 ; Only 1 ascii character given for this byte
    je memory_write_final_byte
    mov dx,ax
    lodsw ; Read next 2 characters of inbuf
    xor ax,0x3030
    ; Parse next byte
    cmp al,cl
    jb memory_data_parse_char4_0
    or al,bh
    add al,bl
    cmp al,ch
    jb memory_write_byte_0 ; Treating this like a separator character
memory_data_parse_char4_0:
    cmp ah,cl
    jb memory_data_parse_next_0
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb memory_invalid_data_0
memory_data_parse_next_0:
    and ax,0x0f0f
    xchg ah,dl
    shl ax,1
    shl ax,1
    shl ax,1
    shl ax,1
    or ax,dx ; Word in ax
    cmp bp,si ; Check inbuf_writeptr
    jb memory_invalid_data_0 ; Only 3 ascii characters given for this word
    ; Write word to memory
    stosw
    je memory_data_parse_loop_finish_0
    lodsw
    xor ax,0x3030
    jmp memory_data_parse_loop_1
memory_write_final_byte:
    shl al,1
    shl al,1
    shl al,1
    shl al,1
    or al,ah
    ; Write byte to memory
    stosb
memory_data_parse_loop_finish_0:
    ; Output carriage return + line feed
    mov ax,0x0a0d
    mov word [0x0000],ax
    ; Output "> "
    mov ax,0x203e
    mov word [0x0002],ax
    mov al,0x04
    mov byte [outbuf_writeptr],al ; set outbuf_writeptr to 4
    xor al,al
    mov byte [inbuf_writeptr],al ; set inbuf_writeptr to 0
    toggle_interrupt_masks
    pop_and_return
memory_write_byte_0:
    shl dl,1
    shl dl,1
    shl dl,1
    shl dl,1
    or dl,dh
    mov al,dl
    ; Write byte to memory
    stosb
memory_data_parse_loop_1:
    ; Attempt to parse next byte
    cmp ah,cl
    jb memory_data_parse_char2_1 ; Valid hex character
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb memory_data_parse_last_check
memory_data_parse_char2_1:
    ; First nibble of byte/word in ah
    cmp bp,si ; Check inbuf_writeptr
    jb memory_data_parse_loop_finish_0
    je memory_invalid_data_1
    mov dl,ah
    lodsw ; Read next 2 characters of inbuf
    xor ax,0x3030
    ; Attempt to parse next bytes
    cmp al,cl
    jb memory_data_parse_char3_1
    or al,bh
    add al,bl
    cmp al,ch
    jb memory_invalid_data_1
memory_data_parse_char3_1:
    mov dh,al ; First 2 nibbles in dx
    and dx,0x0f0f
    ; Parse next byte
    cmp ah,cl
    jb memory_data_parse_char4_1
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb memory_write_byte_1 ; Treating this like a separator character
memory_data_parse_char4_1:
    cmp bp,si ; Check inbuf_writeptr
    jb memory_write_byte_1
    je memory_invalid_data_1
    lodsb
    inc si
    xor ax,0x3030
    cmp al,cl
    jb memory_data_parse_next_1
    or al,bh
    add al,bl
    cmp al,ch
    jb memory_invalid_data_1
memory_data_parse_next_1:
    and ax,0x0f0f
    xchg al,dl
    ror ax,1
    ror ax,1
    ror ax,1
    ror ax,1
    or ax,dx
    ; Write word to memory
    stosw
memory_data_parse_last_check:
    cmp bp,si ; Check inbuf_writeptr
    jbe memory_data_parse_loop_finish_1
    jmp memory_data_parse_loop_0
memory_write_byte_1:
    shl dl,1
    shl dl,1
    shl dl,1
    shl dl,1
    or dl,dh
    mov al,dl
    ; Write byte to memory
    stosb
    cmp bp,si ; Check inbuf_writeptr
    jbe memory_data_parse_loop_finish_1
    jmp memory_data_parse_loop_0
memory_invalid_data_1:
    copy_string_to_outbuf invalid_data_string, invalid_data_string_half_length
    toggle_interrupt_masks
    pop_and_return
memory_data_parse_loop_finish_1:
    ; Output carriage return + line feed
    mov ax,0x0a0d
    mov word [0x0000],ax
    ; Output "> "
    mov ax,0x203e
    mov word [0x0002],ax
    mov al,0x04
    mov byte [outbuf_writeptr],al ; set outbuf_writeptr to 4
    xor al,al
    mov byte [inbuf_writeptr],al ; set inbuf_writeptr to 0
    toggle_interrupt_masks
    pop_and_return


io8_read:
    mov di,ds
    mov es,di
    xor di,di ; es:[di] points to outbuf[0]
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Manually set the auxiliary carry flag to 0
    ; This ensures that the upcoming daa instruction correctly performs the first step of the conversion
    sahf ;4,1 ah is always 0x0a here, so SF, ZF, AF, PF, and CF are all set to 0
    ; Read IO device
    in al,dx
    ; Split byte into nibbles
    mov ah,al
    shr ah,1
    shr ah,1
    shr ah,1
    shr ah,1
    and ax,bp
    ; Convert nibbles to ascii
    daa ;4 Map 0x00-0x09 -> 0x00-0x09 and 0x0a-0x0f -> 0x10-0x15
    cmp cl,al ;3 Set carry flag if al is 0x10-0x15
    adc al,0x30 ;4 Map 0x00-0x09 -> 0x30-0x39 and 0x10-0x15 -> 0x41-0x46
    xchg al,ah
    daa
    cmp cl,al
    adc al,0x30
    ; Output ascii bytes
    stosw
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Output "> "
    mov ax,0x203e
    stosw
    mov word [outbuf_writeptr],di ; update outbuf_writeptr
    xor al,al
    mov byte [inbuf_writeptr],al ; set inbuf_writeptr to 0
    toggle_interrupt_masks
    pop_and_return


io16_read:
    ; Command is exactly 5 characters, read IO address
    mov di,ds
    mov es,di
    xor di,di ; es:[di] points to outbuf[0]
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Manually set the auxiliary carry flag to 0
    ; This ensures that the upcoming daa instruction correctly performs the first step of the conversion
    sahf ;4,1 ah is always 0x0a here, so SF, ZF, AF, PF, and CF are all set to 0
    ; Read IO device
    in ax,dx
    ; Split word into nibbles
    mov dx,ax
    rol dx,1
    rol dx,1
    rol dx,1
    rol dx,1
    and ax,bp
    and dx,bp
    ; Convert nibbles to ascii
    daa ;4 Map 0x00-0x09 -> 0x00-0x09 and 0x0a-0x0f -> 0x10-0x15
    cmp cl,al ;3 Set carry flag if al is 0x10-0x15
    adc al,0x30 ;4 Map 0x00-0x09 -> 0x30-0x39 and 0x10-0x15 -> 0x41-0x46
    xchg al,ah
    daa
    cmp cl,al
    adc al,0x30
    xchg al,dh
    daa
    cmp cl,al
    adc al,0x30
    xchg ax,dx
    daa
    cmp cl,al
    adc al,0x30
    ; Output ascii bytes
    stosw
    mov ax,dx
    stosw
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Output "> "
    mov ax,0x203e
    stosw
    mov word [outbuf_writeptr],di ; update outbuf_writeptr
    xor al,al
    mov byte [inbuf_writeptr],al ; set inbuf_writeptr to 0
    toggle_interrupt_masks
    pop_and_return


io_invalid_command:
    copy_string_to_outbuf invalid_command_string, invalid_command_string_half_length
    toggle_interrupt_masks
    pop_and_return
io_write:
    cmp ah,0x3d ; Check if the next character is '='
    jne io_invalid_command ; Next character is not '='
    ; Set up registers
    mov es,dx ; es will temporarily hold the IO address while dx is used for parsing data
    ; Parse sequence of ascii bytes/words separated by any non-hex characters
io_data_parse_loop_0:
    lodsw ; Read next 2 characters of inbuf
    xor ax,0x3030
    ; Parse byte
    cmp al,cl
    jb io_data_parse_char2_0
    or al,bh
    add al,bl
    cmp al,ch
    jae io_data_parse_char2_0
    jmp io_data_parse_loop_1
io_invalid_data_0:
    copy_string_to_outbuf invalid_data_string, invalid_data_string_half_length
    toggle_interrupt_masks
    pop_and_return
io_data_parse_char2_0:
    cmp ah,cl
    jb io_data_parse_char3_0
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb io_invalid_data_0
io_data_parse_char3_0:
    ; Combine nibbles into byte
    and ax,bp
    cmp di,si ; Check inbuf_writeptr
    jb io_invalid_data_0 ; Only 1 ascii character given for this byte
    je io_write_final_byte
    mov dx,ax
    lodsw ; Read next 2 characters of inbuf
    xor ax,0x3030
    ; Parse next byte
    cmp al,cl
    jb io_data_parse_char4_0
    or al,bh
    add al,bl
    cmp al,ch
    jb io_write_byte_0 ; Treating this like a separator character
io_data_parse_char4_0:
    cmp ah,cl
    jb io_data_parse_next_0
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb io_invalid_data_0
io_data_parse_next_0:
    and ax,bp
    xchg ah,dl
    shl ax,1
    shl ax,1
    shl ax,1
    shl ax,1
    or ax,dx ; Word in ax
    cmp di,si ; Check inbuf_writeptr
    jb io_invalid_data_0 ; Only 3 ascii characters given for this word
    mov dx,es
    ; Write word to IO device
    out dx,ax
    je io_data_parse_loop_finish_0
    lodsw ; Read next 2 characters of inbuf
    xor ax,0x3030
    jmp io_data_parse_loop_1
io_write_final_byte:
    shl al,1
    shl al,1
    shl al,1
    shl al,1
    or al,ah
    ; Write byte to IO device
    out dx,al
io_data_parse_loop_finish_0:
    ; Output carriage return + line feed
    mov ax,0x0a0d
    mov word [0x0000],ax
    ; Output "> "
    mov ax,0x203e
    mov word [0x0002],ax
    mov al,0x04
    mov byte [outbuf_writeptr],al ; set outbuf_writeptr to 4
    xor al,al
    mov byte [inbuf_writeptr],al ; set inbuf_writeptr to 0
    toggle_interrupt_masks
    pop_and_return
io_write_byte_0:
    shl dl,1
    shl dl,1
    shl dl,1
    shl dl,1
    or dl,dh
    mov al,dl
    mov dx,es
    ; Write byte to IO device
    out dx,al
io_data_parse_loop_1:
    ; Parse byte
    cmp ah,cl
    jb io_data_parse_char2_1
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb io_data_parse_last_check
io_data_parse_char2_1:
    ; First nibble of byte/word in ah
    cmp di,si ; Check inbuf_writeptr
    jb io_data_parse_loop_finish_0
    je io_invalid_data_1
    mov dl,ah
    lodsw ; Read next 2 characters of inbuf
    xor ax,0x3030
    ; Attempt to parse next bytes
    cmp al,cl
    jb io_data_parse_char3_1
    or al,bh
    add al,bl
    cmp al,ch
    jb io_invalid_data_1
io_data_parse_char3_1:
    mov dh,al ; First 2 nibbles in dx
    and dx,bp
    ; Parse next byte
    cmp ah,cl
    jb io_data_parse_char4_1
    or ah,bh
    add ah,bl
    cmp ah,ch
    jb io_write_byte_1 ; Treating this like a separator character
io_data_parse_char4_1:
    cmp di,si ; Check inbuf_writeptr
    jb io_write_byte_1
    je io_invalid_data_1
    lodsb
    inc si
    xor ax,0x3030
    cmp al,cl
    jb io_data_parse_next_1
    or al,bh
    add al,bl
    cmp al,ch
    jb io_invalid_data_1
io_data_parse_next_1:
    and ax,bp
    xchg al,dl
    ror ax,1
    ror ax,1
    ror ax,1
    ror ax,1
    or ax,dx
    mov dx,es
    ; Write word to IO device
    out dx,ax
io_data_parse_last_check:
    cmp di,si ; Check inbuf_writeptr
    jbe io_data_parse_loop_finish_1
    jmp io_data_parse_loop_0
io_write_byte_1:
    shl dl,1
    shl dl,1
    shl dl,1
    shl dl,1
    or dl,dh
    mov al,dl
    mov dx,es
    ; Write byte to IO device
    out dx,al
    cmp di,si ; Check inbuf_writeptr
    jbe io_data_parse_loop_finish_1
    jmp io_data_parse_loop_0
io_invalid_data_1:
    copy_string_to_outbuf invalid_data_string, invalid_data_string_half_length
    toggle_interrupt_masks
    pop_and_return
io_data_parse_loop_finish_1:
    mov ax,0x0a0d
    mov word [0x0000],ax
    ; Output "> "
    mov ax,0x203e
    mov word [0x0002],ax
    mov al,0x04
    mov byte [outbuf_writeptr],al ; set outbuf_writeptr to 4
    xor al,al
    mov byte [inbuf_writeptr],al ; set inbuf_writeptr to 0
    toggle_interrupt_masks
    pop_and_return


not_implemented:
    copy_string_to_outbuf not_implemented_string, not_implemented_string_half_length
    toggle_interrupt_masks
    pop_and_return