; Interrupt service routine for the uart ready to transmit a character

; This special routine is used for printing multiple bytes of memory to the user like this:
;
; 1233D | DD EE FF
; 12340 | 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF
; 12350 | 00 11 22 33 44
; >
; This routine also switches back to the normal txready routine to print the last line of text and the "> "

; THIS SHOULD NOT BE ACTIVE WHEN THERE ARE NO MORE BYTES OF MEMORY TO DISPLAY TO THE USER!!!

gsr_uart_txready_memread_routine:
    ; Push used registers to stack
    push ax
    push ds
    push si
    mov si,variables_segment
    mov ds,si
    ; Check if the outbuf is empty
    mov ax,word [outbuf_writeptr]
    cmp al,ah
    jz txready_memread_makerow ; outbuf is empty, write a row of text to outbuf
    mov si,word [outbuf_readptr]
    cld ; Set direction flag to 0 (so string instruction increment si)
    lodsb ; load next character into al
    out uart_data_addr,al ; Output next character to uart
    cmp si,word [outbuf_writeptr] ; Check if output buffer is empty (outbuf_readptr = outbuf_writeptr)
    je reset_outbuf_pointers ; Output buffer is empty
    mov word [outbuf_readptr],si ; outbuf_readptr++
    pop si
    pop ds
    pop ax
    iret
reset_outbuf_pointers:
    xor ax,ax
    mov word [outbuf_writeptr],ax
    mov word [outbuf_readptr],ax
    pop si
    pop ds
    pop ax
    iret

txready_memread_makerow:
    ; Make line of text that looks something like one of these:
    ;12ABC | CC DD EE FF
    ;12AC0 | 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF
    ;12AD0 | 00 11 22
    ; Push used registers to stack
    push bx
    push cx
    push dx
    push es
    push di
    push bp
    mov es,si
    xor di,di ; es:[di] points to outbuf[0]
    mov bp,0x0f0f ; Load frequently used value into register
    mov ax,0x0a30 ; Load frequently used value
    ; Manually set the auxiliary carry flag to 0
    ; This ensures that the upcoming daa instruction correctly performs the first step of the conversion
    sahf ; ah is always 0x0a here, so SF, ZF, AF, PF, and CF are all set to 0
    mov cx,ax
    ; Load startptr into ds:[si]
    mov si,word [startptr_ip]
    mov ds,word [startptr_cs] ; ds:[si] now points to the first memory address to be printed on the current line of text
    ; Print pointer to the user
    ; The first character will immediately be sent to the UART, the next characters will be written to outbuf to be printed later
    ; Split ds into nibbles
    mov ax,ds
    rol ax,1
    rol ax,1
    rol ax,1
    rol ax,1
    and ax,bp
    ; Convert nibbles to ascii
    daa ;4 Map 0x00-0x09 -> 0x00-0x09 and 0x0a-0x0f -> 0x10-0x15
    cmp ch,al ;3 Set carry flag if al is 0x10-0x15
    adc al,cl ;4 Map 0x00-0x09 -> 0x30-0x39 and 0x10-0x15 -> 0x41-0x46
    ; Immediately output first character of pointer
    out uart_data_addr,al
    ; Continue converting nibbles to ascii
    mov dx,ds
    and dx,bp
    xchg ax,dx
    daa
    cmp ch,al
    adc al,cl
    xchg al,dh
    daa
    cmp ch,al
    adc al,cl
    xchg al,ah
    daa
    cmp ch,al
    adc al,cl
    ; Write second and third characters of pointer to outbuf
    stosw
    ; Continue converting nibbles to ascii
    mov ax,si
    daa
    cmp ch,al
    adc al,cl
    mov ah,al
    mov al,dh
    ; Write fourth and fifth characters of pointer to outbuf
    stosw
    ; Output " |"
    mov ax,0x7c20
    stosw
    ; Load first 2 bytes of memory to be printed
    mov bx,ax
    lodsw
    ; Split bytes into nibbles
    mov dx,ax
    ror ax,1
    ror ax,1
    and dx,bp
    ror ax,1
    ror ax,1
    and ax,bp
    ; Convert nibbles to ascii
    daa ;4 Map 0x00-0x09 -> 0x00-0x09 and 0x0a-0x0f -> 0x10-0x15
    cmp ch,al ;3 Set carry flag if al is 0x10-0x15
    adc al,cl ;4 Map 0x00-0x09 -> 0x30-0x39 and 0x10-0x15 -> 0x41-0x46
    mov bh,al
    mov al,dh
    daa
    cmp ch,al
    adc al,cl
    xchg al,ah
    daa
    cmp ch,al
    adc al,cl
    xchg ax,dx
    daa
    cmp ch,al
    adc al,cl
    ; Write ascii of first byte to outbuf
    mov ah,bl
    xchg ax,bx
    stosw
    mov ax,bx
    stosw
    mov ax,dx
    ; Check if the upper 16 bits of startptr and the endptr are the same
    mov dx,ds
    cmp dx,word es:[endptr_cs]
    jne finish_row ; Continue printing bytes until si > 0x0010
    ; Check lower 4 bits of pointers
    mov dx,word es:[endptr_ip]
    ; Calculate number of bytes left of this row to print
    inc dx
    inc dx
    sub dx,si
    jz final_row_complete ; Lower 4 bits of pointers match, we're finished the final row
    jc finish_row ; Dest pointer is lower than start pointer, finish this row
    ; Write ascii of second byte to outbuf
    stosw
    dec dx
    jz final_row_complete ; Dest pointer was only 1 higher than start pointer, we're finished the final row
    ; Dest pointer only a little higher than start pointer, finish this row then disable this routine
    mov bp,dx
finish_final_row_loop:
    ; Load next 2 bytes of memory to be printed
    lodsw
    ; Split bytes into nibbles
    mov dx,ax
    ror dx,1
    ror dx,1
    and ax,0x0f0f
    ror dx,1
    ror dx,1
    and dx,0x0f0f
    ; Convert nibbles to ascii
    daa ;4 Map 0x00-0x09 -> 0x00-0x09 and 0x0a-0x0f -> 0x10-0x15
    cmp ch,al ;3 Set carry flag if al is 0x10-0x15
    adc al,cl ;4 Map 0x00-0x09 -> 0x30-0x39 and 0x10-0x15 -> 0x41-0x46
    mov bl,al
    mov al,dl
    daa
    cmp ch,al
    adc al,cl
    xchg al,ah
    daa
    cmp ch,al
    adc al,cl
    xchg al,dh
    daa
    cmp ch,al
    adc al,cl
    mov dl,al
    mov al,bh
    ; Write ascii of first byte to outbuf
    stosw
    mov ax,bx
    stosw
    mov ax,dx
    ; Check if we're finished printing the final row
    dec bp
    jz final_row_complete ; We're finished printing the final row
    ; Write ascii of second byte to outbuf
    stosw
    dec bp
    jnz finish_final_row_loop
final_row_complete:
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Output "> "
    mov ax,0x203e
    stosw
    ; Update outbuf writeptr
    mov word es:[outbuf_writeptr],di
    ; Change interrupt handler for txready back to normal
    xor bp,bp
    mov ds,bp
    mov ax,gsr_uart_txready_routine ; replace with actual value
    mov word [0x0084],ax
    ; Pop used registers and return
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

finish_row:
    ; Check if the next byte should be printed
    mov dx,si
    dec dx
    test cx,dx
    jnz row_complete
    stosw
    test cx,si
    jnz row_complete
finish_row_loop:
    ; Continue parsing bytes
    lodsw
    ; Split bytes into nibbles
    mov dx,ax
    ror dx,1
    ror dx,1
    and ax,bp
    ror dx,1
    ror dx,1
    and dx,bp
    ; Convert nibbles to ascii
    daa ;4 Map 0x00-0x09 -> 0x00-0x09 and 0x0a-0x0f -> 0x10-0x15
    cmp ch,al ;3 Set carry flag if al is 0x10-0x15
    adc al,cl ;4 Map 0x00-0x09 -> 0x30-0x39 and 0x10-0x15 -> 0x41-0x46
    mov bl,al
    mov al,dl
    daa
    cmp ch,al
    adc al,cl
    xchg al,ah
    daa
    cmp ch,al
    adc al,cl
    xchg al,dh
    daa
    cmp ch,al
    adc al,cl
    mov dl,al
    mov al,bh
    ; Write ascii of first byte to outbuf
    stosw
    mov ax,bx
    stosw
    mov ax,dx
    ; Check if the next byte should be printed
    mov dx,si
    dec dx
    test cx,dx
    jnz row_complete
    stosw
    test cx,si
    jz finish_row_loop
row_complete:
    ; Output carriage return + line feed
    mov ax,0x0a0d
    stosw
    ; Update outbuf writeptr
    mov word es:[outbuf_writeptr],di
    ; Update startptr
    xor ax,ax
    mov word es:[startptr_ip],ax
    mov ax,ds
    inc ax
    mov word es:[startptr_cs],ax
    ; Pop used registers and return
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