cpu 8086



; Interrupt service routine for the uart ready to transmit a character
; THIS INTERRUPT SHOULD BE MASKED IF THE OUTPUT BUFFER IS EMPTY!!!
; Register usage: ax,ds,si

; outbuf[outbuf_readptr] --> UART
; if (outbuf_readptr == outbuf_writeptr) {
;     outbuf_readptr = 0
;     outbuf_writeptr = 0
;     mask uart txready interrupt
;     unmask the uart rxready interrupt
;     return
; } else {
;     outbuf_readptr++
;     return
; }
gsr_uart_txready_routine:
    ; Push used registers to stack
    push ax
    push ds
    push si
    mov si,variables_segment
    mov ds,si ; ds = 0x0040
    mov si,word [outbuf_readptr] ; si = outbuf_readptr, ds:[si] now points to outbuf[outbuf_readptr]
    cld ; Set direction flag to 0 (so string instruction increment si)
    lodsb ; load next character into al
    out uart_data_addr,al ; Output next character to uart
    cmp si,word [outbuf_writeptr] ; Check if output buffer is empty (outbuf_readptr = outbuf_writeptr)
    je _mask_txready_interrupt ; Output buffer is empty
    mov word [outbuf_readptr],si ; outbuf_readptr++
    pop si
    pop ds
    pop ax
    iret
_mask_txready_interrupt:
    ; Set outbuf_readptr and outbuf_writeptr to 0
    xor ax,ax ; ax = 0
    mov word [outbuf_readptr],ax ; outbuf_readptr = 0
    mov word [outbuf_writeptr],ax ; outbuf_writeptr = 0
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