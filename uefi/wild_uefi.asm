; wild_uefi.asm — UEFI x86-64
; Prints a banner, then fills the entire screen with a new random color
; every frame using GOP->Blt(EfiBltVideoFill). Continuous, full-screen change.

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

; EFI_GRAPHICS_OUTPUT_PROTOCOL
%define GOP_QUERYMODE           0x00        ; QueryMode()
%define GOP_SETMODE             0x08        ; SetMode()
%define GOP_BLT                 0x10        ; Blt()
%define GOP_MODEPTR             0x18        ; Mode*

; EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE (x64)
%define MODE_INDEX              0x04        ; UINT32
%define MODE_INFOPTR            0x08        ; INFO*

; EFI_GRAPHICS_OUTPUT_MODE_INFORMATION
%define INFO_HRES               0x04        ; UINT32
%define INFO_VRES               0x08        ; UINT32

; EFI_GRAPHICS_OUTPUT_BLT_OPERATION
%define EfiBltVideoFill         0

; ------------ helpers: print UTF-16 string in RDX ------------
putws:
        sub     rsp, 32
        mov     rcx, [r15+ST_CONOUT]
        mov     rax, [rcx+TO_OUTPUT_STRING]
        call    rax
        add     rsp, 32
        ret

; ---------------- Entry: EFI_STATUS efi_main(EFI_HANDLE, EFI_SYSTEM_TABLE*) --
efi_main:
        mov     r14, rcx                   ; ImageHandle (non-volatile)
        mov     r15, rdx                   ; SystemTable* (non-volatile)

        ; Banner so we know we started
        lea     rdx, [rel banner]
        call    putws

        ; BootServices*
        mov     rbx, [r15+ST_BOOT]

        ; GOP via HandleProtocol(ImageHandle, &GOP_GUID, &gop_ptr)
        mov     rcx, r14
        lea     rdx, [rel GOP_GUID]
        lea     r8,  [rel gop_ptr]
        mov     rax, [rbx+BS_HANDLE_PROTOCOL]
        sub     rsp, 32
        call    rax
        add     rsp, 32

        mov     r12, [gop_ptr]            ; r12 = GOP*
        test    r12, r12
        jz      .hang

        ; rsi = GOP->Mode*
        mov     rsi, [r12+GOP_MODEPTR]

        ; Reapply current mode: clears splash and ensures Info is valid
        mov     eax, dword [rsi+MODE_INDEX]
        mov     edx, eax                   ; RDX = Mode
        mov     rcx, r12                   ; RCX = GOP*
        mov     rax, [r12+GOP_SETMODE]
        sub     rsp, 32
        call    rax
        add     rsp, 32

        ; Reload Mode* (some GOPs update it)
        mov     rsi, [r12+GOP_MODEPTR]

        ; Require Info* now present
        mov     rbx, [rsi+MODE_INFOPTR]
        test    rbx, rbx
        jz      .hang

        ; Persist width & height (as UINT32 in memory)
        mov     eax, [rbx+INFO_HRES]
        mov     [width],  eax
        mov     eax, [rbx+INFO_VRES]
        mov     [height], eax

        ; Seed RNG (xorshift64) in memory
        rdtsc
        shl     rdx, 32
        or      rax, rdx
        test    rax, rax
        jnz     .seed_ok
        mov     rax, 0x9E3779B97F4A7C15
.seed_ok:
        mov     [rng_state], rax

; ---- Main: every iteration pick a new random 32-bit pixel and VideoFill ----
.frame:
        ; xorshift64*
        mov     rax, [rng_state]
        mov     rdx, rax
        shl     rax, 13
        xor     rax, rdx
        mov     rdx, rax
        shr     rax, 7
        xor     rax, rdx
        mov     rdx, rax
        shl     rax, 17
        xor     rax, rdx
        mov     [rng_state], rax

        ; random pixel to bltpix (BGRA)
        mov     eax, dword [rng_state]
        mov     dword [bltpix], eax

        ; Blt( GOP*, &bltpix, EfiBltVideoFill, 0,0, 0,0, Width, Height, 0 )
        sub     rsp, 80                   ; 32 shadow + 6 qwords
        xor     rax, rax
        mov     [rsp+32], rax             ; SourceY = 0
        mov     [rsp+40], rax             ; DestX   = 0
        mov     [rsp+48], rax             ; DestY   = 0
        xor     rax, rax
        mov     eax, [width]              ; zero-extend to RAX
        mov     [rsp+56], rax             ; Width (UINTN)
        xor     rax, rax
        mov     eax, [height]
        mov     [rsp+64], rax             ; Height (UINTN)
        xor     rax, rax
        mov     [rsp+72], rax             ; Delta = 0

        mov     rcx, r12                  ; this = GOP*
        lea     rdx, [rel bltpix]         ; BltBuffer
        mov     r8d, EfiBltVideoFill
        xor     r9d, r9d                  ; SourceX = 0
        mov     rax, [rcx+GOP_BLT]
        call    rax
        add     rsp, 80

        jmp     .frame                    ; forever

.hang:
        jmp     .hang

; -------------------- DATA --------------------
section .data
align 8
gop_ptr     dq 0

width       dd 0
height      dd 0
rng_state   dq 0

banner      dw 'U','E','F','I',' ','G','O','P',' ','R','u','n',13,10,0

; one pixel for VideoFill (BGRA)
bltpix      dd 0

; GOP GUID {9042A9DE-23DC-4A38-96FB-7ADED080516A}
GOP_GUID:
    dd 0x9042A9DE
    dw 0x23DC, 0x4A38
    db 0x96,0xFB,0x7A,0xDE,0xD0,0x80,0x51,0x6A

