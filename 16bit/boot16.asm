; Random screen filler boot sector (16-bit real mode, VGA text)
; NASM + Intel syntax, flat binary output
; Assemble with: nasm -f bin boot16.asm -o boot16.img

bits 16
org 0x7C00

start:
    cli
    xor     ax, ax
    mov     ss, ax
    mov     sp, 0x7C00            ; tiny stack just above our code
    sti

    ; Make DS point at our code/data (whatever CS is)
    push    cs
    pop     ds

    ; Set 80x25 color text mode (clears screen)
    mov     ax, 0x0003
    int     0x10

    ; Seed RNG from BIOS tick counter at 0x40:0x6C
    mov     ax, 0x0040
    mov     ds, ax
    mov     bx, [0x006C]
    mov     dx, [0x006E]
    xor     bx, dx                 ; mix high+low

    ; Restore DS to our code segment
    push    cs
    pop     ds
    mov     [seed], bx

    ; ES -> VGA text memory
    mov     ax, 0xB800
    mov     es, ax

    ; RNG multiplier stays in BX for MUL
    mov     bx, 25173              ; 0x6265

    cld

frame_loop:
    xor     di, di                 ; start of text buffer
    mov     cx, 2000               ; 80*25 cells

cell_loop:
    ; Random char in DL: visible ASCII range 0x20..0x7F
    call    rand16
    mov     dl, al
    and     dl, 0x5F               ; keep 0..95
    add     dl, 0x20               ; -> 0x20..0x7F

    ; Random attribute in AH: fg 0..15, bg 0..7
    call    rand16
    mov     ah, al
    and     ah, 0x0F               ; FG (4 bits)
    and     al, 0x70               ; BG (bits 6..4), bit 7 (blink) kept 0
    or      ah, al                 ; AH = attribute

    ; AX = [AL=char, AH=attr]
    mov     al, dl
    stosw                          ; write 2 bytes, advance DI by 2

    loop    cell_loop
    jmp     frame_loop

; 16-bit LCG RNG:
;   state = state * 25173 + 13849   (mod 2^16)
; Returns: AL = low 8 bits of new state (AX has full 16 bits)
; Uses: AX, DX (MUL), preserves BX (multiplier constant)
rand16:
    mov     ax, [seed]
    mul     bx                     ; DX:AX = AX * BX (unsigned)
    add     ax, 13849              ; 0x3619
    mov     [seed], ax
    ret

; RNG state (lives in code section)
seed:
    dw 0

times 510-($-$$) db 0
dw 0xAA55
