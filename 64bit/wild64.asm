; wild64.asm — 512B BIOS boot sector that enters x86-64 long mode
; and fills VGA text with random chars + random attributes (blink/bg/fg).
; Tiny debug marks at (0,0..2): 'R','P','L'.
;
; Assemble: nasm -f bin wild64.asm -o wild64.img
; Run:      qemu-system-x86_64 -drive format=raw,file=wild64.img

BITS 16
ORG 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld

    ; Debug 'R' in top-left
    mov ax, 0xB800
    mov es, ax
    mov word [es:0], 0x0A52   ; attr=0x0A (green), 'R'(0x52)

    ; Enable A20 (port 0x92 fast gate)
    in  al, 0x92
    or  al, 0x02
    and al, 0xFE
    out 0x92, al

    ; Load GDT (valid for 32/64-bit)
    lgdt [gdt_desc]

    ; Enter Protected Mode (CR0.PE=1), then far jump with 32-bit offset.
    mov eax, cr0
    or  eax, 1
    mov cr0, eax
    db 0x66, 0xEA                ; ljmp ptr16:32 encoding
    dd pm32_entry
    dw 0x0008                    ; selector: code32

; ------------------------------- GDT ------------------------------------
gdt:
    dq 0x0000000000000000        ; null
    ; code32: base=0, limit=4G, G=1, D=1
    dw 0xFFFF, 0x0000
    db 0x00, 0x9A, 0xCF, 0x00
    ; data: base=0, limit=4G, G=1, D=1
    dw 0xFFFF, 0x0000
    db 0x00, 0x92, 0xCF, 0x00
    ; code64: L=1, G=1, D=0
    dw 0x0000, 0x0000
    db 0x00, 0x9A, 0xA0, 0x00
gdt_end:
gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt

; ======================= 32-bit protected mode ==========================
[BITS 32]
pm32_entry:
    mov ax, 0x10                ; data selector
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x90000

    ; Debug 'P' at column 1
    mov edi, 0xB8000
    mov word [edi + 2], 0x0B50  ; attr=0x0B (cyan), 'P'

    ; Identity map first 1 GiB with 2 MiB pages:
    ; PML4 @ 0x1000, PDPT @ 0x2000, PD @ 0x3000
    ; PML4[0] -> PDPT
    mov edi, 0x1000
    mov dword [edi], 0x2003
    mov dword [edi+4], 0
    ; PDPT[0] -> PD
    mov edi, 0x2000
    mov dword [edi], 0x3003
    mov dword [edi+4], 0
    ; PD entries: 512 * 2 MiB
    mov edi, 0x3000
    xor eax, eax
    mov ecx, 512
.pm32_pd_loop:
    mov ebx, eax
    shl ebx, 21                ; base = i * 2MiB
    or  ebx, 0x083             ; P|RW|PS
    mov dword [edi], ebx
    mov dword [edi+4], 0
    add edi, 8
    inc eax
    loop .pm32_pd_loop

    ; Enable PAE, load CR3 with PML4
    mov eax, cr4
    or  eax, 1<<5              ; PAE
    mov cr4, eax
    mov eax, 0x1000
    mov cr3, eax

    ; Enable Long Mode (EFER.LME)
    mov ecx, 0xC0000080
    rdmsr
    or  eax, 1<<8
    wrmsr

    ; Enable paging (CR0.PG) -> IA-32e compat mode
    mov eax, cr0
    or  eax, 1<<31
    mov cr0, eax

    ; Far RET to 64-bit: push selector then offset, retf pops EIP then CS
    push 0x18
    push lm64_entry
    retf

; ========================= 64-bit long mode =============================
[BITS 64]
lm64_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x90000

    ; Debug 'L' at column 2
    mov rdi, 0xB8000
    mov word [rdi + 4], 0x0D4C  ; attr=0x0D (magenta), 'L'

    ; Seed RNG state (RSI) from TSC
    rdtsc
    shl rdx, 32
    or  rax, rdx
    mov rsi, rax
    test rsi, rsi
    jnz .seeded
    mov rsi, 0x123456789ABCDEF0
.seeded:

    mov rbx, 2000               ; 80*25 cells

.main_loop:
    mov rcx, rbx
    mov rdi, 0xB8000
.fill_loop:
    ; xorshift64 in RSI (small & fast)
    mov rax, rsi
    mov rdx, rax
    shl rax, 13
    xor rax, rdx
    mov rdx, rax
    shr rax, 7
    xor rax, rdx
    mov rdx, rax
    shl rax, 17
    xor rax, rdx
    mov rsi, rax

    ; Use two different bytes of the new state:
    ; - BL = random char
    ; - AH = random attribute (may blink, random bg/fg)
    mov bl, al
    shr rax, 8
    mov ah, al

    ; self-modify: patch imm8 of 'mov al, imm8 ; ret' and execute
    lea rdx, [rel smc_mov_al + 1]
    mov [rdx], bl
    call smc_mov_al             ; returns AL = BL (patched)

    ; write AX = [attr:char]
    stosw
    dec rcx
    jnz .fill_loop
    jmp .main_loop

; 3-byte SMC snippet we patch every cell: mov al, imm8 ; ret
smc_mov_al:
    db 0xB0, 0x41, 0xC3

; ----------------------- boot sector terminator --------------------------
times 510-($-$$) db 0
dw 0xAA55
