; gop_test.asm — UEFI x86-64 "Hello GOP + magenta screen"
;
; Build:
;   nasm -f win64 gop_test.asm -o gop_test.obj
;   lld-link /entry:efi_main /subsystem:efi_application /nodefaultlib ^
;            /out:BOOTX64.EFI gop_test.obj

        bits 64
        default rel
        section .text
        global efi_main

; Offsets in EFI_SYSTEM_TABLE
%define ST_CONOUT   0x40
%define ST_BOOT     0x60

; Offsets in SIMPLE_TEXT_OUTPUT_INTERFACE
%define TO_OUTPUT_STRING   0x08

; Offsets in EFI_BOOT_SERVICES
%define BS_HANDLE_PROTOCOL 0x98

; EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE* ST)
efi_main:
        mov     r14, rcx           ; ImageHandle
        mov     r15, rdx           ; SystemTable*

        ; Print "Hello GOP!" using ConOut->OutputString
        mov     rbx, [r15+ST_CONOUT]       ; rbx = ConOut*
        sub     rsp, 40
        mov     rcx, rbx
        lea     rdx, [rel hello_str]
        call    qword [rbx+TO_OUTPUT_STRING]
        add     rsp, 40

        ; Get BootServices
        mov     rbx, [r15+ST_BOOT]

        ; Call BootServices->HandleProtocol(ImageHandle, &GOP_GUID, &gop_ptr)
        mov     rcx, r14                   ; handle
        lea     rdx, [rel GOP_GUID]        ; protocol GUID
        lea     r8,  [rel gop_ptr]         ; out ptr
        mov     rax, [rbx+BS_HANDLE_PROTOCOL]
        call    rax

        mov     rbx, [gop_ptr]             ; rbx = GOP*

        ; Framebuffer base and size
        mov     rdi, [rbx+0x30]            ; FrameBufferBase
        mov     rcx, [rbx+0x38]            ; FrameBufferSize (bytes)
        shr     rcx, 2                     ; DWORD count

        mov     eax, 0x00FF00FF            ; magenta ARGB
        rep stosd                          ; fill

.hang:  jmp .hang                          ; stay forever

; --------------------------------------------------------------------------
section .data
align 8
gop_ptr dq 0

hello_str:  dw 'H','e','l','l','o',' ','G','O','P','!',13,10,0

; EFI_GRAPHICS_OUTPUT_PROTOCOL GUID
; {9042A9DE-23DC-4A38-96FB-7ADED080516A}
GOP_GUID:
    dd 0x9042A9DE
    dw 0x23DC, 0x4A38
    db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A

