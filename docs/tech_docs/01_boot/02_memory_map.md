# Physical Address Space — BeagleBone Black (Boot Stage)

> Kernel image nằm ở đâu trong RAM? Linker script tổ chức sections như thế nào?

---

## Bối cảnh

Khi kernel `_start` chạy, MMU đang **tắt** — mọi địa chỉ CPU truy cập là physical address.
Linker script (`kernel_bbb.ld`) quyết định mọi thứ nằm ở đâu trong RAM vật lý.

`_start` dùng các linker symbols (`_bss_start`, `_svc_stack_top`...) để thiết lập CPU.
File này giải thích các symbol đó đến từ đâu và chiếm bao nhiêu không gian.

---

## AM335x Physical Address Space (tổng quan)

AM335x là SoC 32-bit — address space 4 GB, nhưng chỉ một phần nhỏ là RAM/peripheral thật.

```text
0x00000000 ┌──────────────────────────────────────────────────┐
           │  Boot ROM / internal SRAM                        │
           │  (ROM: 0x40000000, SRAM: 0x402F0400)             │
0x44E00000 ├──────────────────────────────────────────────────┤
           │  L4_WKUP Peripherals                             │
           │  0x44E00000  CM_PER / CM_WKUP (PRCM clock)      │
           │  0x44E09000  UART0 (NS16550) ← kernel console   │
           │  0x44E10000  Control Module (pinmux, DDR IO)     │
           │  0x44E35000  WDT1 (watchdog timer)               │
0x48000000 ├──────────────────────────────────────────────────┤
           │  L4_PER Peripherals                              │
           │  0x48040000  DMTIMER2 ← future scheduler tick    │
           │  0x48060000  MMC0 (SD card controller)           │
           │  0x48200000  INTC (interrupt controller)         │
0x4C000000 ├──────────────────────────────────────────────────┤
           │  EMIF (DDR controller registers)                 │
           │                                                  │
0x80000000 ├══════════════════════════════════════════════════┤
           │                                                  │
           │  DDR3 — 512 MB                                   │
           │  0x80000000 – 0x9FFFFFFF                         │
           │  ← Kernel image loaded here by SPL               │
           │                                                  │
0xA0000000 ├──────────────────────────────────────────────────┤
           │  unused / unmapped                               │
           │                                                  │
0xFFFFFFFF └──────────────────────────────────────────────────┘
```

**Kernel chỉ dùng vùng DDR: `0x80000000` – `0x9FFFFFFF`.**

Peripheral registers truy cập qua MMIO trực tiếp khi MMU tắt. Sau khi bật MMU, peripherals sẽ được remap vào kernel virtual space tại `0xFF000000` (xem architecture.md).

---

## Tại sao kernel load tại 0x80000000?

Đây là **đầu DDR3 physical**. AM335x EMIF controller map DDR RAM bắt đầu từ `0x80000000` (TRM §2.1).

SPL load file `kernel.bin` vào đúng địa chỉ này rồi `ldr pc, =0x80000000`. Linker script set `ORIGIN = 0x80000000` để tất cả symbol address khớp với vị trí thật trong RAM.

```text
/* kernel_bbb.ld */
MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 512M
}
```

---

## DDR Layout — Kernel Image Sections

Linker script xếp các section theo thứ tự cố định trong DDR. Dưới đây là **địa chỉ thực tế** từ `objdump -h build/bbb/kernel.elf` và `nm`:

```text
                    DDR Physical
                    ─────────────
 0x80000000  ┌──────────────────────────────────────────────────┐
             │                                                  │
             │  .text + .rodata                                 │
             │  776 bytes (0x308)                               │
             │                                                  │
             │  0x80000000  _start          (entry point)       │
             │  0x80000068  kmain                               │
             │  0x800000B8  uart_init                           │
             │  0x80000150  uart_putc                           │
             │  0x800001B0  uart_puts                           │
             │  0x800001FC  uart_print_hex                      │
             │  0x80000270  string literals (.rodata)           │
             │                                                  │
 0x80000308  ├──────────────────────────────────────────────────┤
             │  .data — 0 bytes (hiện tại không có init globals)│
 0x80000308  ├──────────────────────────────────────────────────┤
             │  .bss  — 0 bytes (hiện tại không có uninit globals)│
 0x80000308  ├──────────────────────────────────────────────────┤
             │                                                  │
             │  .stack (NOLOAD) — 11,776 bytes (0x2E00)         │
             │                                                  │
             │  ┌────────────────────────────────────────┐      │
             │  │  FIQ stack — 512 B                     │      │
             │  │  0x80000308 ... 0x80000507              │      │
             │  │  SP_fiq init → 0x80000508               │      │
             │  ├────────────────────────────────────────┤      │
             │  │  IRQ stack — 1 KB                      │      │
             │  │  0x80000508 ... 0x80000907              │      │
             │  │  SP_irq init → 0x80000908               │      │
             │  ├────────────────────────────────────────┤      │
             │  │  Abort stack — 1 KB                    │      │
             │  │  0x80000908 ... 0x80000D07              │      │
             │  │  SP_abt init → 0x80000D08               │      │
             │  ├────────────────────────────────────────┤      │
             │  │  Undefined stack — 1 KB                │      │
             │  │  0x80000D08 ... 0x80001107              │      │
             │  │  SP_und init → 0x80001108               │      │
             │  ├────────────────────────────────────────┤      │
             │  │  SVC stack — 8 KB                      │      │
             │  │  0x80001108 ... 0x80003107              │      │
             │  │  SP_svc init → 0x80003108               │      │
             │  └────────────────────────────────────────┘      │
             │                                                  │
 0x80003108  ├──────────────────────────────────────────────────┤
             │  _heap_start (future kmalloc)                    │
             │  ↓                                               │
             │  free RAM — ~512 MB                              │
             │                                                  │
 0x9FFFFFFF  └──────────────────────────────────────────────────┘
```

### Tổng kernel image = 12,552 bytes (0x3108)

Từ `arm-linux-gnueabihf-size build/bbb/kernel.elf`:

```text
   text    data     bss     dec     hex
    776       0   11776   12552    3108
```

- **text** (776 B): `_start` + `kmain` + UART driver + string literals
- **data** (0 B): chưa có global variable khởi tạo
- **bss** (11776 B): 11.5 KB = toàn bộ là exception stacks (linker đặt .stack trong .bss range)

Kernel image thực sự trên SD card (`kernel.bin`) chỉ **776 bytes** — data/bss/stack không nằm trong file vì là NOLOAD.

---

## Linker Script chi tiết

Dưới đây là từng section trong `kernel_bbb.ld` và tại sao nó được tổ chức như vậy.

### .text — code + read-only data

```text
.text :
{
    _text_start = .;
    *(.text.start)      /* _start — PHẢI ở đầu tiên */
    *(.text*)
    *(.rodata*)
    . = ALIGN(4);
    _text_end = .;
} > RAM
```

**`*(.text.start)` phải là dòng đầu tiên** — đảm bảo `_start` nằm tại `0x80000000`, đúng nơi SPL nhảy đến. Nếu section khác chen trước, SPL nhảy vào data thay vì code.

### .data — initialized globals

```text
.data :
{
    . = ALIGN(4);
    _data_start = .;
    *(.data*)
    . = ALIGN(4);
    _data_end = .;
} > RAM
```

Chứa global/static variables có giá trị khởi tạo (`int x = 42;`). Hiện tại RefixOS kernel chưa có biến nào loại này → section rỗng.

### .bss — zero-initialized globals

```text
.bss (NOLOAD) :
{
    . = ALIGN(8);
    _bss_start = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(8);
    _bss_end = .;
} > RAM
```

`NOLOAD` = không chiếm dung lượng trong file `kernel.bin`. Chỉ chiếm không gian trong RAM — `_start` zero vùng `_bss_start` → `_bss_end` trước khi vào C.

### .stack — exception mode stacks

```text
.stack (NOLOAD) :
{
    . = ALIGN(8);

    . = . + 0x200;              /* FIQ: 512 B */
    PROVIDE(_fiq_stack_top = .);

    . = . + 0x400;              /* IRQ: 1 KB */
    PROVIDE(_irq_stack_top = .);

    . = . + 0x400;              /* Abort: 1 KB */
    PROVIDE(_abt_stack_top = .);

    . = . + 0x400;              /* Undefined: 1 KB */
    PROVIDE(_und_stack_top = .);

    . = . + 0x2000;             /* SVC: 8 KB */
    PROVIDE(_svc_stack_top = .);
} > RAM
```

**Tại sao `_xxx_stack_top` nằm ở cuối mỗi slot?**

ARM stack grow **xuống** (push giảm SP). `_stack_top` = địa chỉ cao nhất = nơi SP bắt đầu. Khi push, SP giảm dần về phía đầu slot.

```text
          ┌─────────┐ ← _fiq_stack_top (SP bắt đầu ở đây)
          │ FIQ 512B│
stack ↓   │  grows  │   push → SP giảm
          │  down   │
          └─────────┘ ← đáy slot (nếu SP xuống quá → stack overflow)
```

**`PROVIDE()`** — nếu symbol chưa được define ở nơi khác, linker tạo ra symbol này. `_start` dùng `ldr sp, =_fiq_stack_top` để load giá trị.

### _heap_start — future kmalloc

```text
PROVIDE(_heap_start = .);
```

Đánh dấu byte đầu tiên sau tất cả sections. Future `kmalloc` sẽ quản lý RAM từ đây đến cuối DDR. Hiện chưa dùng.

---

## Stack Summary (objdump verified)

| Mode      | Range (physical)            | SP init (`_xxx_stack_top`) | Size       |
| --------- | --------------------------- | -------------------------- | ---------- |
| FIQ       | `0x80000308` – `0x80000507` | `0x80000508`               | 512 B      |
| IRQ       | `0x80000508` – `0x80000907` | `0x80000908`               | 1 KB       |
| Abort     | `0x80000908` – `0x80000D07` | `0x80000D08`               | 1 KB       |
| Undefined | `0x80000D08` – `0x80001107` | `0x80001108`               | 1 KB       |
| SVC       | `0x80001108` – `0x80003107` | `0x80003108`               | 8 KB       |
| **Total** |                             |                            | **11.5 KB** |

Sau `_svc_stack_top` (`0x80003108`) → `_heap_start` → toàn bộ RAM còn lại (~512 MB - 12.3 KB) là free.

---

## Gotcha

- **`*(.text.start)` phải đứng đầu `.text` section.** Nếu ai thêm section mới mà chen trước `_start` → kernel không boot. Verify: `arm-linux-gnueabihf-nm build/bbb/kernel.elf | head` → `_start` phải ở `0x80000000`.
- **Stack không có guard page.** Hiện tại chưa có MMU, nên nếu stack overflow, nó ghi đè vào section liền kề mà không có cảnh báo. Cụ thể: FIQ overflow sẽ ghi đè cuối `.text` — silent corruption. MMU sẽ giải quyết vấn đề này ở phase sau.
- **ALIGN(8) cho stack.** ARM ABI yêu cầu SP aligned 8 bytes tại function entry (AAPCS §5.2.1.2). Linker script đảm bảo điều này.
- **`_heap_start` chưa tồn tại trong symbol table.** Linker script có `PROVIDE(_heap_start = .)` nhưng vì chưa có code nào reference symbol này, linker bỏ qua. Sẽ xuất hiện khi `kmalloc` được implement.

---

## Cách verify layout

Khi thay đổi linker script hoặc thêm code mới, dùng các lệnh sau để kiểm tra:

```bash
# Section headers (VMA, size)
arm-linux-gnueabihf-objdump -h build/bbb/kernel.elf

# Symbol table (sorted by address)
arm-linux-gnueabihf-nm build/bbb/kernel.elf | sort

# Total sizes
arm-linux-gnueabihf-size build/bbb/kernel.elf

# Full disassembly
arm-linux-gnueabihf-objdump -d build/bbb/kernel.elf
```

---

## Liên kết

- **Dùng bởi:** `_start` — xem [01_kernel_entry.md](01_kernel_entry.md)
- **Source file:** `boot/kernel/linker/kernel_bbb.ld`
- **Board constants:** `bsp/include/board.h` (`RAM_BASE = 0x80000000`)
- **Tiếp theo:** [02 — Exception & Interrupt](../02_exceptions/overview.md)
