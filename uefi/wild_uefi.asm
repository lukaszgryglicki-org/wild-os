; wild_uefi.asm — UEFI x86-64
; Robust GOP init (LocateProtocol → SetMode → QueryMode),
; then fill the screen with **per‑pixel random colors** forever using
; GOP->Blt(BufferToVideo) one scanline at a time.
;
; Build:
;   nasm -f win64 wild_uefi.asm -o wild_uefi.obj
;   lld-link /entry:efi_main /subsystem:efi_application /nodefaultlib ^
;            /out:BOOTX64.EFI wild_uefi.obj

        bits 64
        default rel
        section .text
        global efi_main

; ---------- EFI structure offsets (x64) ----------
%define ST_CONOUT               0x40        ; EFI_SYSTEM_TABLE.ConOut
%define ST_BOOT                 0x60        ; EFI_SYSTEM_TABLE.BootServices

; SIMPLE_TEXT_OUTPUT_INTERFACE
%define TO_OUTPUT_STRING        0x08

; EFI_BOOT_SERVICES
%define BS_HANDLE_PROTOCOL      0x98
%define BS_LOCATE_PROTOCOL_A    0x140       ; common edk2 offset
%define BS_LOCATE_PROTOCOL_B    0x138       ; some builds use this

; EFI_GRAPHICS_OUTPUT_PROTOCOL
%define GOP_QUERYMODE           0x00
%define GOP_SETMODE             0x08
%define GOP_BLT                 0x10
%define GOP_MODEPTR             0x18

; EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE (x64)
%define MODE_INDEX              0x04        ; INT32
%define MODE_INFOPTR            0x08        ; INFO*

; EFI_GRAPHICS_OUTPUT_MODE_INFORMATION
%define INFO_HRES               0x04        ; UINT32
%define INFO_VRES               0x08        ; UINT32

; EFI_GRAPHICS_OUTPUT_BLT_OPERATION
%define EfiBltBufferToVideo     2

; -------------- tiny helpers --------------
; put UTF-16 string at RDX
putws:
        sub     rsp, 32
        mov     rcx, [r15+ST_CONOUT]
        mov     rax, [rcx+TO_OUTPUT_STRING]
        call    rax
        add     rsp, 32
        ret

; put one UTF-16 character from AL
putch:
        mov     [chbuf], al
        lea     rdx, [rel chbuf]
        jmp     putws

; -------------- entry --------------
efi_main:
        mov     r14, rcx           ; ImageHandle
        mov     r15, rdx           ; SystemTable*

        ; banner so you know we started
        lea     rdx, [rel banner]
        call    putws

        ; BootServices*
        mov     rbx, [r15+ST_BOOT]

        ; ---- Locate GOP via LocateProtocol (preferred) ----
        ; RCX = &GOP_GUID, RDX = 0, R8 = &gop_ptr
        lea     rcx, [rel GOP_GUID]
        xor     rdx, rdx
        lea     r8,  [rel gop_ptr]

        ; try offset A
        mov     rax, [rbx+BS_LOCATE_PROTOCOL_A]
        test    rax, rax
        jz      .try_loc_b
        sub     rsp, 32
        call    rax
        add     rsp, 32
        test    rax, rax
        jz      .loc_ok

.try_loc_b:
        ; try offset B
        lea     rcx, [rel GOP_GUID]
        xor     rdx, rdx
        lea     r8,  [rel gop_ptr]
        mov     rax, [rbx+BS_LOCATE_PROTOCOL_B]
        test    rax, rax
        jz      .try_handle
        sub     rsp, 32
        call    rax
        add     rsp, 32
        test    rax, rax
        jz      .loc_ok

.try_handle:
        ; last resort: HandleProtocol(ImageHandle, &GOP_GUID, &gop_ptr)
        mov     rcx, r14
        lea     rdx, [rel GOP_GUID]
        lea     r8,  [rel gop_ptr]
        mov     rax, [rbx+BS_HANDLE_PROTOCOL]
        sub     rsp, 32
        call    rax
        add     rsp, 32

.loc_ok:
        mov     r12, [gop_ptr]     ; r12 = GOP*
        test    r12, r12
        jz      .hang

        ; print 'L' (located)
        mov     al, 'L'
        call    putch

        ; rsi = GOP->Mode*
        mov     rsi, [r12+GOP_MODEPTR]

        ; SetMode(current) to clear splash & ensure Info later
        mov     eax, dword [rsi+MODE_INDEX]
        mov     edx, eax
        mov     rcx, r12
        mov     rax, [r12+GOP_SETMODE]
        sub     rsp, 32
        call    rax
        add     rsp, 32

        ; print 'S' (setmode done)
        mov     al, 'S'
        call    putch

        ; Reload Mode* (some GOPs update it)
        mov     rsi, [r12+GOP_MODEPTR]

        ; If Mode->Info is NULL, QueryMode(current) to get valid Info
        mov     rbx, [rsi+MODE_INFOPTR]
        test    rbx, rbx
        jnz     .have_info

        mov     eax, dword [rsi+MODE_INDEX]
        mov     edx, eax
        lea     r8,  [rel size_info]
        lea     r9,  [rel info_ptr]
        mov     rcx, r12
        mov     rax, [r12+GOP_QUERYMODE]
        sub     rsp, 32
        call    rax
        add     rsp, 32
        mov     rbx, [info_ptr]
        test    rbx, rbx
        jz      .hang

.have_info:
        ; print 'Q' (we have Info)
        mov     al, 'Q'
        call    putch

        ; Persist width/height for BLT
        mov     eax, [rbx+INFO_HRES]
        mov     [width],  eax
        mov     eax, [rbx+INFO_VRES]
        mov     [height], eax

        ; rowbytes = width * 4 (32bpp)
        mov     eax, [width]
        shl     eax, 2
        mov     [rowbytes], eax

        ; seed RNG (xorshift64)
        rdtsc
        shl     rdx, 32
        or      rax, rdx
        test    rax, rax
        jnz     .seed_ok
        mov     rax, 0x9E3779B97F4A7C15
.seed_ok:
        mov     [rng_state], rax

; ======================= per‑pixel noise via scanline BLT ====================
.frame:
        mov     dword [cur_y], 0           ; y = 0

.y_loop:
        ; ---- Build one scanline of random pixels into rowbuf ----
        mov     ecx, [width]               ; number of dwords this row
        lea     rdi, [rel rowbuf]
        mov     rax, [rng_state]           ; local RNG state in RAX

.fill_row:
        ; xorshift64*
        mov     rdx, rax
        shl     rax, 13
        xor     rax, rdx
        mov     rdx, rax
        shr     rax, 7
        xor     rax, rdx
        mov     rdx, rax
        shl     rax, 17
        xor     rax, rdx

        ; write low 32 bits as pixel (B,G,R,Reserved)
        stosd
        dec     ecx
        jnz     .fill_row

        mov     [rng_state], rax           ; persist RNG

        ; ---- BLT this row to (0, y): Width x 1, Delta = rowbytes ----
        ; RCX=this(GOP*), RDX=&rowbuf, R8=2(BufferToVideo), R9=SourceX=0
        ; Stack (after 32B shadow):
        ;   [rsp+32] = SourceY = 0
        ;   [rsp+40] = DestX   = 0
        ;   [rsp+48] = DestY   = y
        ;   [rsp+56] = Width   = width
        ;   [rsp+64] = Height  = 1
        ;   [rsp+72] = Delta   = rowbytes
        sub     rsp, 80
        xor     rax, rax
        mov     [rsp+32], rax
        mov     [rsp+40], rax
        mov     eax, [cur_y]
        mov     [rsp+48], rax
        mov     eax, [width]
        mov     [rsp+56], rax
        mov     qword [rsp+64], 1
        mov     eax, [rowbytes]
        mov     [rsp+72], rax

        mov     rcx, r12                   ; GOP*
        lea     rdx, [rel rowbuf]          ; BltBuffer
        mov     r8d, EfiBltBufferToVideo
        xor     r9d, r9d                   ; SourceX = 0
        mov     rax, [rcx+GOP_BLT]
        call    rax
        add     rsp, 80

        ; print 'B' once (first successful BLT)
        cmp     byte [blt_mark], 0
        jne     .skip_mark
        mov     al, 'B'
        call    putch
        mov     byte [blt_mark], 1
.skip_mark:

        ; next scanline
        inc     dword [cur_y]
        mov     eax, [cur_y]
        cmp     eax, [height]
        jb      .y_loop

        jmp     .frame                     ; next “frame” (new random pixels)

.hang:
        jmp     .hang

; -------------- DATA --------------
section .data
align 8
gop_ptr     dq 0
info_ptr    dq 0
size_info   dq 0

width       dd 0
height      dd 0
rowbytes    dd 0
cur_y       dd 0

rng_state   dq 0
blt_mark    db 0

banner      dw 'U','E','F','I',' ','G','O','P',' ','R','U','N',13,10,0
chbuf       dw 0,0

; GOP GUID {9042A9DE-23DC-4A38-96FB-7ADED080516A}
GOP_GUID:
    dd 0x9042A9DE
    dw 0x23DC, 0x4A38
    db 0x96,0xFB,0x7A,0xDE,0xD0,0x80,0x51,0x6A

; -------------- ROW BUFFER --------------
section .bss
align 16
; 32 KiB row buffer → up to 8192 pixels per row (8192*4 = 32768 bytes).
; If your mode is wider, increase this (e.g., resb 65536 for up to 16384 px).
rowbuf  resb 32768

