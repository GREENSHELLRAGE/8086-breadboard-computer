cpu 8086

; Compile command to quickly test on breadboard computer:
; nasm -o test.bin test.asm; python3 binary_to_gsrme.py test.bin 01000

lba_address equ 0x00000000

org 0 ; Labels start at 0

    ; Currently trying to figure out how FAT32 works...

    ; Initialize SD Card
    int 40
    cmp al,ah ; Check for errors
    jnz finish ; Finish program if there was an error

    ; Set es:[di] to point to 0x10000
    mov di,0x1000
    mov es,di
    xor di,di
    ; Read master boot record
    xor bx,bx ; bx = 0x0000
    mov cx,bx ; cx = 0x0000, LBA address set to 0
    int 41 ; Read block
    cmp al,ah ; Check for errors
    jnz finish ; Finish program if there was an error
    
    ; Check master boot record
    cmp word es:[0x01fe],0xaa55
    jne finish ; Pattern at the end is invalid
    ; Check if partition 1 is FAT
    mov di,0x01c2 ; di points to type code of partition
    mov al,byte es:[di] ; al = type code of partition
    cmp al,0x0b ; Check if type code is FAT
    je read_fat_volume_id ; Start reading the FAT volume id
    cmp al,0x0c ; Check if type code is FAT
    je read_fat_volume_id ; Start reading the FAT volume id
    ; Check if partition 2 is FAT
    mov di,0x01d2 ; di points to type code of partition
    mov al,byte es:[di] ; al = type code of partition
    cmp al,0x0b ; Check if type code is FAT
    je read_fat_volume_id ; Start reading the FAT volume id
    cmp al,0x0c ; Check if type code is FAT
    je read_fat_volume_id ; Start reading the FAT volume id
    ; Check if partition 3 is FAT
    mov di,0x01e2 ; di points to type code of partition
    mov al,byte es:[di] ; al = type code of partition
    cmp al,0x0b ; Check if type code is FAT
    je read_fat_volume_id ; Start reading the FAT volume id
    cmp al,0x0c ; Check if type code is FAT
    je read_fat_volume_id ; Start reading the FAT volume id
    ; Check if partition 4 is FAT
    mov di,0x01f2 ; di points to type code of partition
    mov al,byte es:[di] ; al = type code of partition
    cmp al,0x0b ; Check if type code is FAT
    je read_fat_volume_id ; Start reading the FAT volume id
    cmp al,0x0c ; Check if type code is FAT
    jne finish ; Error if partition 4 is also not FAT

read_fat_volume_id:
    ; Set bx and cx to LBA address of FAT volume id
    mov cx,word es:[di+4]
    mov bx,word es:[di+6]
    ; Set es:[di] to point to 0x10000
    xor di,di
    ; Read block
    int 41
    cmp al,ah ; Check for errors
    jnz finish ; Finish program if there was an error
    
    ; Check volume id
    cmp word es:[0x0b],0x0200
    jne finish ; Bytes per sector is invalid
    cmp byte es:[0x10],0x02
    jne finish ; Number of FATs is invalid
    cmp word es:[0x01fe],0xaa55
    jne finish ; Pattern at the end is invalid

finish:
    ; Reset machine
    jmp 0xffff:0x0000