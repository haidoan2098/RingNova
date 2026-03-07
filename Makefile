# RefixOS — Top-level Makefile
# Usage: make PLATFORM=qemu  |  make PLATFORM=bbb
#
# All output goes to build/

PLATFORM ?= qemu
PLATFORM_UPPER := $(shell echo $(PLATFORM) | tr a-z A-Z)

export PLATFORM
export PLATFORM_UPPER

# Toolchain
CROSS   ?= arm-none-eabi
CC      := $(CROSS)-gcc
AS      := $(CROSS)-as
LD      := $(CROSS)-ld
OBJCOPY := $(CROSS)-objcopy
GDB     := $(CROSS)-gdb

export CC AS LD OBJCOPY GDB

# Mandatory compiler flags (Hard constraint — do NOT remove)
CFLAGS := -nostdlib -ffreestanding -nostartfiles \
          -mcpu=cortex-a8 -marm \
          -DPLATFORM_$(PLATFORM_UPPER) \
          -Wall -Wextra -g

export CFLAGS

BUILD_DIR := $(CURDIR)/build
export BUILD_DIR

.PHONY: all boot kernel clean qemu

# Create build dir if it doesn't exist
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# boot compiles everything (start.S + kernel/main.c + uart.c) and links
all: $(BUILD_DIR)
	$(MAKE) -C boot

boot: $(BUILD_DIR)
	$(MAKE) -C boot

kernel: $(BUILD_DIR)
	$(MAKE) -C kernel

clean:
	$(MAKE) -C boot clean
	rm -f $(BUILD_DIR)/*.o $(BUILD_DIR)/*.elf $(BUILD_DIR)/*.bin

# Launch QEMU
qemu:
	@bash scripts/qemu_run.sh

