# boot/Makefile — Boot phase build
#
# Compiles: boot/arch/start.S (reset entry)
# Links with: kernel objects using boot/linker/kernel.ld
# Output: build/kernel.elf, build/kernel.bin

# Inherit toolchain + flags from top-level Makefile
BOOT_ASM_SRCS := arch/start.S
KERNEL_C_SRCS := ../kernel/main.c \
                 ../bsp/drivers/uart/uart.c

BOOT_OBJS   := $(BUILD_DIR)/start.o
KERNEL_OBJS := $(BUILD_DIR)/main.o $(BUILD_DIR)/uart.o

LD_SCRIPT   := linker/kernel.ld
ELF_OUT     := $(BUILD_DIR)/kernel.elf
BIN_OUT     := $(BUILD_DIR)/kernel.bin

INCLUDE_DIRS := -I../bsp/include -I../bsp/drivers/uart

.PHONY: all clean

all: $(ELF_OUT) $(BIN_OUT)

# Assemble reset entry
$(BUILD_DIR)/start.o: arch/start.S
	$(CC) $(CFLAGS) -c $< -o $@

# Compile kernel C entry
$(BUILD_DIR)/main.o: ../kernel/main.c
	$(CC) $(CFLAGS) $(INCLUDE_DIRS) -c $< -o $@

# Compile UART driver
$(BUILD_DIR)/uart.o: ../bsp/drivers/uart/uart.c
	$(CC) $(CFLAGS) $(INCLUDE_DIRS) -c $< -o $@

# Link
$(ELF_OUT): $(BOOT_OBJS) $(KERNEL_OBJS)
	$(LD) -T $(LD_SCRIPT) $^ -o $@

# Raw binary (for U-Boot tftp / SD card)
$(BIN_OUT): $(ELF_OUT)
	$(OBJCOPY) -O binary $< $@

clean:
	rm -f $(BUILD_DIR)/start.o $(BUILD_DIR)/main.o \
	      $(BUILD_DIR)/uart.o $(ELF_OUT) $(BIN_OUT)
