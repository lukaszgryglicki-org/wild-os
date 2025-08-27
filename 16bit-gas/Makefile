# Build a 512-byte boot sector with GAS and run it in QEMU.

BOOT = boot.bin
ELF  = boot.elf
OBJ  = boot.o
ASM  = boot.S

all: $(BOOT)

$(OBJ): $(ASM)
	as --32 -o $@ $<

$(ELF): $(OBJ)
	ld -m elf_i386 -Ttext 0x7C00 --nmagic -nostdlib -e _start -o $@ $<

$(BOOT): $(ELF)
	# Only keep .text (we placed data in .text)
	objcopy -O binary -j .text $< $@
	@printf "Built %s (%s bytes)\n" $@ "$$(stat -c%s $@)"
	@if [ "$$(stat -c%s $@)" -ne 512 ]; then \
	  echo "ERROR: boot image must be exactly 512 bytes"; exit 1; \
	fi

# GUI run (explicit raw format removes the QEMU warning)
run: $(BOOT)
	qemu-system-i386 -boot a -drive file=$(BOOT),if=floppy,format=raw

# Kept for convenience; same as 'run' but named like before
run-gui: $(BOOT)
	qemu-system-i386 -boot a -drive file=$(BOOT),if=floppy,format=raw

clean:
	rm -f $(OBJ) $(ELF) $(BOOT)

