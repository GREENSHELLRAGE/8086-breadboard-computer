; THIS CODE IS NOT USED ANYWHERE YET AND HAS NOT BEEN COMPILED OR TESTED AT ALL!!!

; This code will eventually allow GSR memory editor to load programs from an
; SD card using a custom high speed SPI interface!


; Every command except for CMD0 and CMD8 can have a CRC of 0
; since it shouldn't be checked by the card

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
; Write commands:
; CMD24:  58 12 34 56 78 01 (write block LBA=0x12345678)

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



sd_interface equ 0x04
sd_interface_cs equ 0x06


%macro set_cs_low 0
    out sd_interface_cs,al ; SD card interface ignores the data for this write
%endmacro

%macro set_cs_high 0
    out sd_interface_cs,ax ; SD card interface ignores the data for this write
%endmacro



; Not sure if this should be an interrupt or a function

; Also not sure how error handling should work, should I return a
; certain value for an error or call a software interrupt with an
; error handling routine?

; Or should I make everything a macro?

sd_card_init:
    cli ; Disable hardware interrupts
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
    in ax,dx ; Read shift register, start another 16 bit transfer
    cmp ah,0x01
    je sd_cmd8 ; Valid response, send cmd8 to SD card
    ; Invalid response, try again a few more times before giving up
    in al,dx
    cmp al,0x01
    je sd_cmd8
    in al,dx
    cmp al,0x01
    je sd_cmd8
    in al,dx
    cmp al,0x01
    je sd_cmd8
    in al,dx
    cmp al,0x01
    je sd_cmd8
    in al,dx
    cmp al,0x01
    je sd_cmd8
    in al,dx
    cmp al,0x01
    je sd_cmd8
    in al,dx
    cmp al,0x01
    je sd_cmd8
    ; Could not get a valid response, SD card may not be plugged in
sd_cmd0_error:
    set_cs_high
    sti ; Enable hardware interrupts
    ret

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
    in ax,dx ; Read shift register, start another 16 bit transfer
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
    sti ; Enable hardware interrupts
    ret

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
    sti ; Enable hardware interrupts
    ret

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
    cmp ah,0x01
    je sd_acmd41 ; Valid response, send acmd41 to SD card
    ; Invalid response, try again a few more times before giving up
    in al,dx
    cmp al,0x01
    je sd_acmd41
    in al,dx
    cmp al,0x01
    je sd_acmd41
    in al,dx
    cmp al,0x01
    je sd_acmd41
    in al,dx
    cmp al,0x01
    je sd_acmd41
    in al,dx
    cmp al,0x01
    je sd_acmd41
    in al,dx
    cmp al,0x01
    je sd_acmd41
    in al,dx
    cmp al,0x01
    jne sd_acmd41_error ; Could not get a valid response, SD card may not be plugged in
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
    in ax,dx ; Read shift register, start another 16 bit transfer
    cmp ah,0x01
    jb sd_cmd58 ; Valid response, set the block length to 512
    je sd_acmd41_not_ready_yet ; Valid response, card not ready yet
    ; Invalid response, try again a few more times before giving up
    in al,dx
    cmp al,0x01
    jb sd_cmd58
    je sd_acmd41_not_ready_yet
    in al,dx
    cmp al,0x01
    jb sd_cmd58
    je sd_acmd41_not_ready_yet
    in al,dx
    cmp al,0x01
    jb sd_cmd58
    je sd_acmd41_not_ready_yet
    in al,dx
    cmp al,0x01
    jb sd_cmd58
    je sd_acmd41_not_ready_yet
    in al,dx
    cmp al,0x01
    jb sd_cmd58
    je sd_acmd41_not_ready_yet
    in al,dx
    cmp al,0x01
    jb sd_cmd58
    je sd_acmd41_not_ready_yet
    in al,dx
    cmp al,0x01
    jb sd_cmd58
    jne sd_acmd41_error ; Could not get a valid response, SD card may not be plugged in
sd_acmd41_not_ready_yet:
    loop sd_cmd55_ready_loop
sd_acmd41_error:
    set_cs_high
    sti ; Enable hardware interrupts
    ret

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
    ; Load response from SD card into shift register
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
    sti ; Enable hardware interrupts
    ret

read_ocr_register:
    in ax,dx ; Load first 2 bytes of OCR register into ax
    test al,0x40 ; Check CCS flag
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
    in ax,dx ; Read shift register, start another 16 bit transfer
    cmp ah,0x00
    je sd_ready ; Valid response, SD card is ready
    ; Invalid response, try again a few more times before giving up
    in al,dx
    cmp al,0x00
    je sd_ready
    in al,dx
    cmp al,0x00
    je sd_ready
    in al,dx
    cmp al,0x00
    je sd_ready
    in al,dx
    cmp al,0x00
    je sd_ready
    in al,dx
    cmp al,0x00
    je sd_ready
    in al,dx
    cmp al,0x00
    je sd_ready
    in al,dx
    cmp al,0x00
    jne sd_cmd16_error ; Could not get a valid response, SD card may not be plugged in
sd_ready:
    ; SD card is initialized and ready to be used
    set_cs_high
    sti ; Enable hardware interrupts
    ret




; Register usage: ax,bx,cx,dx,es,di
; Arguments:
; bx,cx: LBA address of block to read
; es,di: pointer to memory that the block will be copied to (di will be incremented by 512 if successful)

; Example:
; bx=0x1234, cx=0x5678 --> LBA address 0x12345678
; es=0x0061, di=0x0000 --> Copy block to memory address 0x00610
sd_read_lba_block_into_memory:
    cli ; Disable hardware interrupts
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
    in ax,dx ; Read shift register, start another 16 bit transfer
    cmp ah,0x00
    je wait_for_start_token ; Valid response, start waiting for start token
    ; Invalid response, try again a few more times before giving up
    in al,dx
    cmp al,0x00
    je wait_for_start_token
    in al,dx
    cmp al,0x00
    je wait_for_start_token
    in al,dx
    cmp al,0x00
    je wait_for_start_token
    in al,dx
    cmp al,0x00
    je wait_for_start_token
    in al,dx
    cmp al,0x00
    je wait_for_start_token
    in al,dx
    cmp al,0x00
    je wait_for_start_token
    in al,dx
    cmp al,0x00
    jne sd_cmd17_error ; Could not get a valid response, SD card may not be plugged in
wait_for_start_token:
    ; Wait 12 bytes for the SD card to send the start token.
    ; I actually have no idea how long SD cards typically take to
    ; send the start token, so this is just a guess. It's entirely
    ; possible that the card will take longer than 12 bytes to
    ; send the start token, in which case we're fucked and can't
    ; read the card.
    in al,dx ; Read shift register, start another 8 bit transfer
    cmp al,0xfe
    je read_block ; Start token was sent, start copying the block into memory
    jb sd_cmd17_error ; Something else was sent, error
    ; Try this again 11 more times
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    jb sd_cmd17_error
    in al,dx
    cmp al,0xfe
    je read_block
    ; If we haven't gotten the start token by now, give up and assume error
sd_cmd17_error:
    set_cs_high
    sti ; Enable hardware interrupts
    ret

    ; Since the "in ax,dx" and "stosw" are both 1 byte, this would guarantee that
    ; the CPU reads 2 instructions at a time while copying the block of data.
    ; This should minimize the number of bus cycles used
    align 2
read_block:
    ; Repeat these 2 instructions 256 times
    in ax,dx
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
    sti ; Enable hardware interrupts
    ret



; Register usage: ax,bx,cx,dx,ds,si
; Arguments:
; bx,cx: LBA address of block to write
; ds,si: pointer to memory that the block will be copied from (si will be incremented by 512 if successful)

; Example:
; bx=0x1234, cx=0x5678 --> LBA address 0x12345678
; ds=0x0061, si=0x0000 --> Copy block from memory address 0x00610
sd_write_memory_to_lba_block:
    cli ; Disable hardware interrupts
    mov dx,sd_interface
sd_cmd24:
    ; Send command 17 to SD card
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
    in ax,dx ; Read shift register, start another 16 bit transfer
    cmp ah,0x00
    je write_block ; Valid response, start waiting for start token
    ; Invalid response, try again a few more times before giving up
    in al,dx
    cmp al,0x00
    je write_block
    in al,dx
    cmp al,0x00
    je write_block
    in al,dx
    cmp al,0x00
    je write_block
    in al,dx
    cmp al,0x00
    je write_block
    in al,dx
    cmp al,0x00
    je write_block
    in al,dx
    cmp al,0x00
    je write_block
    in al,dx
    cmp al,0x00
    je write_block
    ; If we haven't gotten a response by now, give up and assume error
sd_cmd24_error:
    set_cs_high
    sti ; Enable hardware interrupts
    ret

write_block:
    ; Write start token
    mov al,0xfe
    out dx,al
    align 2
    ; Repeat these 2 instructions 256 times
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
    sti ; Enable hardware interrupts
    ret

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
    jz sd_cmd24_data_response_error ; SD card is taking way too long, assume error
    mov cx,dx
    ; We're done!
    ; NOTE: It is technically possible for errors to be encountered during programming, and
    ; the only way to check for these errors is by using CMD13 to read the status of the card
    ; after the programming is done.
    ; For now I'll just hope everything worked lol
    set_cs_high
    sti ; Enable hardware interrupts
    ret