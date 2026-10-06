; These software interrupts will allow GSR memory editor (or any other program) to interact
; with an SD card using the custom high speed SPI interface!

; Interrupts:
; 40: sd_card_init
; 41: sd_read
; 42: sd_write
; 43: sd_read_sequential (not implemented yet)
; 44: sd_write_sequential (not implemented yet)



; Commands for SD card:
; CMD0:   40 00 00 00 00 95
; CMD8:   48 00 00 01 AA 87
; CMD55:  77 00 00 00 00 01
; ACMD41: 69 00 00 00 00 01 (version 1 card)
; ACMD41: 69 40 00 00 00 01 (version 2 card)
; CMD58:  7a 00 00 00 00 01
; CMD16:  50 00 00 02 00 01 (set block size to 512 bytes, gets ignored by cards larger than 2GB)
; Read commands:
; CMD17:  51 00 00 00 00 01 (read block LBA=0x00000000, master boot record)
; CMD17:  51 12 34 56 78 01 (read block LBA=0x12345678)
; CMD18:  52 12 34 56 78 01 (start reading blocks from LBA=0x12345678)
; CMD12:  4c 00 00 00 00 01 (stop transmission)
; Write commands:
; CMD24:  58 12 34 56 78 01 (write block LBA=0x12345678)

; Every command except for CMD0 and CMD8 can have a CRC of 0
; since it shouldn't be checked by the card

; For CMD17:
; - first wait for response 0x00 (time out after 8 bytes)
; - then wait for start token 0xFE (error if you get anything else or time out)
; - then immediately transfer the next 512 bytes to RAM
; - then read 2-byte checksum (and completely ignore it)


; Initialization flow chart (excluding errors):

; CMD0
; |
; Response=0x01
; |
; |
; |
; CMD8------------------------------,
; |                                 |
; Response=0x01                     Response=0x05
; Valid response (ver 2)            Illegal command (ver 1)
; |                                 |
; |                                 |
; |                                 |
; CMD55 <-----------------------,   CMD55 <-----------------------,
; |                             |   |                             |
; Response=0x01                 |   Response=0x01                 |
; |                             |   |                             |
; |                             |   |                             |
; |                             |   |                             |
; ACMD41 (args=0x40000000)      |   ACMD41 (args=0x00000000)      |
; |               |             |   |               |             |
; Response=0x00   Response=0x01-'   Response=0x00   Response=0x01-'
; |                                 |
; |  ,------------------------------'
; |  |
; CMD58-----------,
; |               |
; CCS flag = 0    CCS flag = 1
; |               |
; |               |
; |               |
; CMD16           |
; |               |
; Response=0x00   |
; |               |
; |  ,------------'
; |  |
; Card is ready!


cpu 8086


sd_interface equ 0x04
sd_interface_cs equ 0x06


%macro set_cs_low 0
    out sd_interface_cs,al ; SD card interface ignores the data for this write
%endmacro

%macro set_cs_high 0
    out sd_interface_cs,ax ; SD card interface ignores the data for this write
%endmacro


; Register usage: ax,bx,cx,dx
; Arguments: none
; Return value in ax register:
; ax = 0x0000 - Success
; ax = 0x0001 - Error, invalid/no response
; ax = 0x0002 - Error, initialization timeout
sd_card_init:
    mov dx,sd_interface
    ; Send 80 clocks to sync SD card
    set_cs_high
    in ax,dx
    in ax,dx
    in ax,dx
    in ax,dx
    in ax,dx
sd_cmd0:
    ; Send command 0 to SD card
    mov ax,0x0040
    set_cs_low
    out dx,ax
    mov al,ah
    out dx,ax
    mov ah,0x95
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    in ax,dx ; Read 2 bytes, start another 16 bit transfer
    add al,ah ; Set zero flag only if one of the 2 bytes was 1 (one of them will be 0xff)
    jz sd_cmd8 ; One of the bytes was 1, send cmd8 to SD card
    ; Invalid response, try again a few more times before giving up
    in ax,dx
    add al,ah
    jz sd_cmd8
    in ax,dx
    add al,ah
    jz sd_cmd8
    in ax,dx
    add al,ah
    jz sd_cmd8
    ; Could not get a valid response, SD card may not be plugged in
sd_cmd0_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret

sd_cmd8:
    ; Send command 8 to SD card
    mov ax,0x0048
    out dx,ax
    mov ax,0x0100
    out dx,ax
    mov ax,0x87aa
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    cmp ah,0x01
    je sd_ver2_init ; Card accepted cmd8, must be a version 2 card
    cmp ah,0x05
    je sd_ver1_init ; Card returned illegal command, must be a version 1 card
    ; Invalid response, try again a few more times before giving up
    in al,dx
    cmp al,0x01
    je sd_ver2_init
    cmp al,0x05
    je sd_ver1_init
    in al,dx
    cmp al,0x01
    je sd_ver2_init
    cmp al,0x05
    je sd_ver1_init
    in al,dx
    cmp al,0x01
    je sd_ver2_init
    cmp al,0x05
    je sd_ver1_init
    in al,dx
    cmp al,0x01
    je sd_ver2_init
    cmp al,0x05
    je sd_ver1_init
    in al,dx
    cmp al,0x01
    je sd_ver2_init
    cmp al,0x05
    je sd_ver1_init
    in al,dx
    cmp al,0x01
    je sd_ver2_init
    cmp al,0x05
    je sd_ver1_init
    in al,dx
    cmp al,0x01
    je sd_ver2_init
    cmp al,0x05
    je sd_ver1_init
    ; Could not get a valid response, SD card may not be plugged in
sd_cmd8_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret

sd_ver1_init:
    ; Set the first 2 bytes of the acmd41 command
    ; This is different for version 1 and version 2 cards
    mov bx,0x0069
    ; Technically I should be sending command 58 here to check the
    ; voltage range of the card, but every card supports 3.3V so
    ; I won't bother with that command.
    jmp sd_cmd55
sd_ver2_init:
    ; Set the first 2 bytes of the acmd41 command
    ; This is different for version 1 and version 2 cards
    mov bx,0x4069
    ; Next 2 bytes of response are in shift register
    ; Make sure the next 4 bytes of the response are 00 00 01 AA
    in ax,dx ; Read next 2 bytes, load final 2 bytes of response into shift register
    cmp ax,0x0000
    jne sd_checkpattern_error ; Bad response
    in ax,dx
    cmp ax,0xaa01
    jne sd_checkpattern_error ; Bad response
    ; Check pattern is correct
    ; Technically I should be sending command 58 here to check the
    ; voltage range of the card, but every card supports 3.3V so
    ; I won't bother with that command.
    jmp sd_cmd55
sd_checkpattern_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret

sd_cmd55:
    ; Set cx to 65535
    ; If the card returns 0x01 to command 41, try sending cmd55 and acmd41
    ; again until it returns 0x00. If it still does not return 0x00 after
    ; 65535 attempts, then give up.
    mov cx,0xffff
    ; Some larger SD cards can take HUNDREDS OF MILLISECONDS to initialize, so
    ; we may need to spam these commands thousands of times before getting the
    ; correct response. This means loop unrolling would not make much sense
    ; here, so I'm using an actual loop to do this.
sd_cmd55_ready_loop:
    ; Send command 55 to SD card
    mov ax,0x0077
    out dx,ax
    mov al,ah
    out dx,ax
    inc ah
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    in ax,dx ; Read shift register, start another 16 bit transfer
    add al,ah ; Set zero flag only if one of the 2 bytes was 1 (one of them will be 0xff)
    jz sd_acmd41 ; One of the bytes was 1, send acmd41 to SD card
    ; Invalid response, try again a few more times before giving up
    in ax,dx
    add al,ah
    jz sd_acmd41
    in ax,dx
    add al,ah
    jz sd_acmd41
    in ax,dx
    add al,ah
    jnz sd_acmd41_error ; Could not get a valid response, SD card may not be plugged in
sd_acmd41:
    ; Send command 41 to SD card
    mov ax,bx
    out dx,ax
    xor ax,ax
    out dx,ax
    inc ah
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    in ax,dx ; Read 2 bytes, start another 16 bit transfer
    and al,ah ; Since one byte will be 0xff, al will be the lowest of the 2 bytes (0xff, 0x01, or 0x00)
    jz sd_cmd58 ; Valid response, read ocr register
    cmp al,0x01
    je sd_acmd41_not_ready_yet ; Valid response, card not ready yet
    ; Invalid response, try again a few more times before giving up
    in ax,dx
    and al,ah
    jz sd_cmd58
    cmp al,0x01
    je sd_acmd41_not_ready_yet
    in ax,dx
    and al,ah
    jz sd_cmd58
    cmp al,0x01
    je sd_acmd41_not_ready_yet
    in ax,dx
    and al,ah
    jz sd_cmd58
    cmp al,0x01
    jne sd_acmd41_error ; Could not get a valid response, SD card may not be plugged in
sd_acmd41_not_ready_yet:
    loop sd_cmd55_ready_loop
    ; Timeout
    set_cs_high
    mov ax,0x0002 ; Return error value
    iret
sd_acmd41_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret

sd_cmd58:
    ; Read the OCR register, send CMD16 if the CCS flag is NOT set
    ; If the CCS flag IS set, the card is ready to be used
    mov ax,0x007a
    out dx,ax
    mov al,ah
    out dx,ax
    inc ah
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    in ax,dx
    cmp ah,0x00
    je read_ocr_register ; Valid response, start reading register
    ; Invalid response, try again a few more times before giving up
    in al,dx
    cmp al,0x00
    je read_ocr_register
    in al,dx
    cmp al,0x00
    je read_ocr_register
    in al,dx
    cmp al,0x00
    je read_ocr_register
    in al,dx
    cmp al,0x00
    je read_ocr_register
    in al,dx
    cmp al,0x00
    je read_ocr_register
    in al,dx
    cmp al,0x00
    je read_ocr_register
    in al,dx
    cmp al,0x00
    je read_ocr_register
    ; Could not get a valid response, SD card may not be plugged in
sd_cmd58_error:
sd_cmd16_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret

read_ocr_register:
    in ax,dx ; Load first 2 bytes of OCR register into ax
    test al,0x40 ; Check CCS flag
    in ax,dx ; Read (and completely ignore for now) next 2 bytes of OCR register
    jnz sd_ready ; CCS flag is 1, card is ready
    ; CCS flag is 0, set the block size to 512 bytes
sd_cmd16:
    ; Send command 16 to SD card
    mov ax,0x0050
    out dx,ax
    mov ax,0x0200
    out dx,ax
    dec ah
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    in ax,dx ; Read 2 bytes, start another 16 bit transfer
    and al,ah ; Since one byte will be 0xff, al will be the lowest of the 2 bytes (0xff, 0x00)
    jz sd_ready ; Valid response, SD card is ready
    ; Invalid response, try again a few more times before giving up
    in ax,dx
    and al,ah
    jz sd_ready
    in ax,dx
    and al,ah
    jz sd_ready
    in ax,dx
    and al,ah
    jnz sd_cmd16_error ; Could not get a valid response, SD card may not be plugged in
sd_ready:
    ; SD card is initialized and ready to be used
    set_cs_high
    xor ax,ax ; Return success
    iret



; Register usage: ax,bx,cx,dx,es,di
; Arguments:
; bx,cx: LBA address of block to read
;     Example:
;     bx=0x1234, cx=0x5678 --> LBA address 0x12345678
; es,di: pointer to memory that the block will be copied to
;     Example:
;     es=0x0061, di=0x0000 --> Copy block to memory address 0x00610
;     Note: di will be incremented by 512 if successful
; Return value in ax register:
; ax = 0x0000 - Success
; ax = 0x0001 - Error, invalid/no response
; ax = 0x0002 - Error, timeout waiting for start of block
sd_read:
    mov dx,sd_interface
sd_cmd17:
    ; Send command 17 to SD card
    mov al,0x51
    mov ah,bh
    set_cs_low
    out dx,ax
    mov al,bl
    mov ah,ch
    out dx,ax
    mov al,cl
    mov ah,0x01
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    ; I'm assuming that there will be at least 1 byte between the
    ; R1 response 0x00 and the start token 0xfe. If the card sends
    ; the start token immediately after the R1 response, then the
    ; code that waits for the start token might miss it.
    in ax,dx ; Read 2 bytes, start another 16 bit transfer
    and al,ah ; Set zero flag only if one of the 2 bytes was 0 (one of them will be 0xff)
    jz wait_for_start_token ; One of the bytes was 0, start waiting for start token
    ; Invalid response, try again a few more times before giving up
    in ax,dx
    and al,ah
    jz wait_for_start_token
    in ax,dx
    and al,ah
    jz wait_for_start_token
    in ax,dx
    and al,ah
    jnz sd_cmd17_error ; Could not get a valid response, SD card may not be plugged in
wait_for_start_token:
    ; Using a loop here because this could potentially take hundreds of milliseconds
    mov dx,cx ; Temporarily using dx to store what was in cx, cx will now be used as a counter
    mov cx,6850 ; The loop will time out after 6850 attempts (about 200ms with a 10MHz clock)
wait_for_start_token_loop:
    in ax,sd_interface ; Read 2 bytes from SD card
    cmp al,0xfe ; Is al (the first byte) the start token?
    je get_second_byte_of_block ; First byte of data is in ah, get the next byte and finish reading the block
    cmp al,ah ; Does al or ah have something else worth checking? (start token or error)
    jne check_for_start_token ; al may have an error byte, ah could have either start token or error byte
    ; Repeat the above checks several more times before looping
    ; This loop unrolling reduces the overhead of the loop instruction
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block
    cmp al,ah
    jne check_for_start_token
    loop wait_for_start_token_loop
    ; SD card is taking way too long to send start token, timeout
    ; Note: only room for 1 more byte of code here for the timeout
    ; error handler without changing previous jump instructions
    mov cx,dx ; Restore contents of cx
    set_cs_high
    mov ax,0x0002 ; Return error value
    iret
sd_cmd17_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret

get_second_byte_of_block:
    mov cx,dx ; Restore contents of cx
    mov dx,sd_interface
    in al,dx ; Read next byte of data
    xchg al,ah ; Ensure that the first 2 bytes of the block are in the correct order
    jmp read_block ; Finish reading the block
check_for_start_token:
    mov cx,dx ; Restore contents of cx
    mov dx,sd_interface
    jb sd_cmd17_error ; If al is less than ah, then al (the first byte) must be an error byte
    cmp ah,0xfe ; Is ah (the second byte) the start token?
    jne sd_cmd17_error ; ah is an error byte
    ; ah is the start token, start reading the block
    in ax,dx
read_block:
    stosw
    ; This times statement is equivalent to typing the previous 2 instructions
    ; another 255 times.
    times 255 dw 0xabed
    ; The reason I'm not using a loop to do this is to eliminate performance
    ; overhead. Looping requires using an extra register (as a counter) and the
    ; loop instruction itself takes 17 extra clock cycles. This unrolled loop is
    ; the fastest way of doing this. The only down side is that this unrolled
    ; loop will take up 512 bytes in ROM, but I have lots of memory to play with
    ; so this is not really an issue.
    in ax,dx ; Read (and completely ignore for now) 2-byte checksum
    ; We're done!
    set_cs_high
    xor ax,ax ; Return success
    iret



; Register usage: ax,bx,cx,dx,es,di,bp
; Arguments:
; bx,cx: LBA address of first block to read
;     Example:
;     bx=0x1234, cx=0x5678 --> LBA address 0x12345678
; es,di: pointer to memory that the blocks will be copied to
;     Example:
;     es=0x0061, di=0x0000 --> Copy block to memory address 0x00610
;     Note: di will be incremented by 512*bp if successful
; bp: number of blocks to read
;     Example:
;     bp=0x0004 --> read 4 blocks
;     Note: bp should NOT be set to 0, this will cause 65536 blocks to be read
; Return value in ax register:
; ax = 0x0000 - Success
; ax = 0x0001 - Error, invalid/no response
; ax = 0x0002 - Error, timeout waiting for start of block
sd_read_sequential:
    mov dx,sd_interface
sd_cmd18:
    ; Send command 18 to SD card
    mov al,0x52
    mov ah,bh
    set_cs_low
    out dx,ax
    mov al,bl
    mov ah,ch
    out dx,ax
    mov al,cl
    mov ah,0x01
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    ; I'm assuming that there will be at least 1 byte between the
    ; R1 response 0x00 and the start token 0xfe. If the card sends
    ; the start token immediately after the R1 response, then the
    ; code that waits for the start token might miss it.
    in ax,dx ; Read 2 bytes, start another 16 bit transfer
    and al,ah ; Set zero flag only if one of the 2 bytes was 0 (one of them will be 0xff)
    jz wait_for_start_token_1 ; One of the bytes was 0, start waiting for start token
    ; Invalid response, try again a few more times before giving up
    in ax,dx
    and al,ah
    jz wait_for_start_token_1
    in ax,dx
    and al,ah
    jz wait_for_start_token_1
    in ax,dx
    and al,ah
    jnz sd_cmd12_error ; Could not get a valid response, SD card may not be plugged in
wait_for_start_token_1:
    ; Using a loop here because this could potentially take hundreds of milliseconds
    mov dx,cx ; Temporarily using dx to store what was in cx, cx will now be used as a counter
    mov cx,6850 ; The loop will time out after 6850 attempts (about 200ms with a 10MHz clock)
wait_for_start_token_loop_1:
    in ax,sd_interface ; Read 2 bytes from SD card
    cmp al,0xfe ; Is al (the first byte) the start token?
    je get_second_byte_of_block_1 ; First byte of data is in ah, get the next byte and finish reading the block
    cmp al,ah ; Does al or ah have something else worth checking? (start token or error)
    jne check_for_start_token_1 ; al may have an error byte, ah could have either start token or error byte
    ; Repeat the above checks several more times before looping
    ; This loop unrolling reduces the overhead of the loop instruction
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    in ax,sd_interface
    cmp al,0xfe
    je get_second_byte_of_block_1
    cmp al,ah
    jne check_for_start_token_1
    loop wait_for_start_token_loop_1
    ; SD card is taking way too long to send start token, timeout
    ; Note: only room for 1 more byte of code here for the timeout
    ; error handler without changing previous jump instructions
    mov cx,dx ; Restore contents of cx
    set_cs_high
    mov ax,0x0002 ; Return error value
    iret
sd_cmd18_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret

get_second_byte_of_block_1:
    mov cx,dx ; Restore contents of cx
    mov dx,sd_interface
    in al,dx ; Read next byte of data
    xchg al,ah ; Ensure that the first 2 bytes of the block are in the correct order
    jmp read_block_1 ; Finish reading the block
check_for_start_token_1:
    mov cx,dx ; Restore contents of cx
    mov dx,sd_interface
    jb sd_cmd18_error ; If al is less than ah, then al (the first byte) must be an error byte
    cmp ah,0xfe ; Is ah (the second byte) the start token?
    jne sd_cmd18_error ; ah is an error byte
    ; ah is the start token, start reading the block
    in ax,dx
read_block_1:
    stosw
    ; This times statement is equivalent to typing the previous 2 instructions
    ; another 255 times.
    times 255 dw 0xabed
    ; The reason I'm not using a loop to do this is to eliminate performance
    ; overhead. Looping requires using an extra register (as a counter) and the
    ; loop instruction itself takes 17 extra clock cycles. This unrolled loop is
    ; the fastest way of doing this. The only down side is that this unrolled
    ; loop will take up 512 bytes in ROM, but I have lots of memory to play with
    ; so this is not really an issue.
    in ax,dx ; Read (and completely ignore for now) 2-byte checksum
    ; Check if there are more blocks to read
    dec bp
    jz sd_cmd12 ; No more blocks left to read
    jmp wait_for_start_token_1 ; There are more blocks to read
sd_cmd12:
    ; Send command 12 to SD card
    mov ax,0x004c
    out dx,ax
    mov al,ah
    out dx,ax
    inc ah
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    in ax,dx ; Read shift register, start another 16 bit transfer
    add al,ah ; Set zero flag only if one of the 2 bytes was 1 (one of them will be 0xff)
    jz read_finished ; One of the bytes was 1, send acmd41 to SD card
    ; Invalid response, try again a few more times before giving up
    in ax,dx
    add al,ah
    jz read_finished
    in ax,dx
    add al,ah
    jz read_finished
    in ax,dx
    add al,ah
    jnz sd_cmd12_error ; Could not get a valid response, SD card may not be plugged in
read_finished:
    ; We're done!
    set_cs_high
    xor ax,ax ; Return success
    iret
sd_cmd12_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret



; Register usage: ax,bx,cx,dx,ds,si
; Arguments:
; bx,cx: LBA address of block to write
;     Example:
;     bx=0x1234, cx=0x5678 --> LBA address 0x12345678
; ds,si: pointer to memory that the block will be copied from
;     Example:
;     ds=0x0061, si=0x0000 --> Copy block from memory address 0x00610
;     Note: si will be incremented by 512 if successful
; Return value in ax register:
; ax = 0x0000 - Success
; ax = 0x0001 - Error, invalid/no response
; ax = 0x0002 - Error, timeout waiting for card to process written block
sd_write:
    mov dx,sd_interface
sd_cmd24:
    ; Send command 24 to SD card
    mov al,0x58
    mov ah,bh
    set_cs_low
    out dx,ax
    mov al,bl
    mov ah,ch
    out dx,ax
    mov al,cl
    mov ah,0x01
    out dx,ax
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    in ax,dx ; Read 2 bytes, start another 16 bit transfer
    and al,ah ; Set zero flag only if one of the 2 bytes was 0 (one of them will be 0xff)
    jz write_block ; One of the bytes was 0, write the 512 byte block
    ; Invalid response, try again a few more times before giving up
    in ax,dx
    and al,ah
    jz write_block
    in ax,dx
    and al,ah
    jz write_block
    in ax,dx
    and al,ah
    jz write_block
    ; If we haven't gotten a response by now, give up and assume error
sd_cmd24_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret

    ; Tests on real hardware showed that the repeated lodsw and out dx,ax instructions execute
    ; slightly faster when started on an odd byte. This align statement + the two instructions
    ; after it guarantee this optimal byte alignment.
    align 2
write_block:
    ; Write start token
    mov al,0xfe
    out dx,al
    ; Repeat these 2 instructions 256 times
    ; Based on tests on actual hardware, it should take approximately
    ; 5120 clocks (512us at 10MHz) to transfer this 512 byte block.
    lodsw
    out dx,ax
    ; This times statement is equivalent to typing the previous 2 instructions
    ; another 255 times.
    ; Just like the code for reading a block, I'm not using a loop here
    times 255 dw 0xefad
    ; Load response from SD card into shift register
    in ax,dx
    ; Check response
    in ax,dx ; Read shift register, start another 16 bit transfer
    and ah,0x1a
    jz wait_for_sd_card ; Valid response, start waiting for sd card to finish processing
    ; Invalid response, try again a few more times before giving up
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    in al,dx
    and al,0x1a
    jz wait_for_sd_card
    ; Could not get a valid response, SD card may not be plugged in
sd_cmd24_data_response_error:
    set_cs_high
    mov ax,0x0001 ; Return error value
    iret
sd_cmd24_data_timeout_error:
    set_cs_high
    mov ax,0x0002 ; Return error value
    iret

wait_for_sd_card:
    ; SD card should be repeatedly sending 0 while block is being programmed
    ; I'm assuming that the SD card will always send at least 2 bytes that are 0 after response
    in ax,dx
    or al,ah
    jnz sd_cmd24_data_response_error ; First 2 bytes are not 0, assume error (maybe the card was unplugged)
    ; SD card is busy programming, wait until the SD card stops sending 0
    ; Using a loop here because this could potentially take several milliseconds
    mov dx,cx ; Temporarily using dx to store what was in cx, cx will now be used as a counter
    mov cx,0xffff ; The loop will time out after 65535 attempts (about 200ms with a 10MHz clock)
wait_for_sd_card_loop:
    in ax,sd_interface ; Read 2 bytes from SD card
    or al,ah
    loopz wait_for_sd_card_loop ; Both of these bytes are 0, check next 2 bytes
    jz sd_cmd24_data_timeout_error ; SD card is taking way too long, assume error
    ; We're done!
    ; NOTE: It is technically possible for errors to be encountered during programming, and
    ; the only way to check for these errors is by using CMD13 to read the status of the card
    ; after the programming is done.
    ; For now I'll just hope everything worked lol
    mov cx,dx
    set_cs_high
    xor ax,ax ; Return success
    iret



; Not implemented yet
sd_write_sequential:
    ; Not implemented yet
    mov ax,0x0001
    iret