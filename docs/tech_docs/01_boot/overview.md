# 01 — Boot & Bring-up

> Từ power-on đến `kmain()` — tại sao phải đi qua 3 tầng?

---

## Tại sao BBB cần ROM → SPL → Kernel?

AM335x không thể boot thẳng vào kernel. Lý do hoàn toàn là hardware constraint:

1. **ROM Code** (hard-wired trong SoC) — chạy đầu tiên khi cấp nguồn.
   Chỉ biết đọc 109 KB từ SD card vào **internal SRAM** tại `0x402F0400`.
   Không đủ chỗ cho kernel, không biết gì về DDR.

2. **SPL** (Secondary Program Loader, file MLO trên SD) — chạy trong SRAM.
   Nhiệm vụ duy nhất: bật clock, init DDR3, load kernel từ SD vào DDR, rồi nhảy đi.
   Sau khi nhảy, SPL không còn vai trò gì.

3. **Kernel** (`_start` → `kmain()`) — chạy trong DDR.
   Có toàn bộ 512 MB RAM. Bắt đầu thiết lập OS thực sự.

```
 Power-on
    │
    ▼
 ROM Code (SoC internal)
    │  Đọc MLO từ SD card → load vào SRAM 0x402F0400
    ▼
 SPL (boot/spl/)
    │  Init clock → Init DDR3 → Load kernel.bin vào DDR
    │  Jump: ldr pc, =0x80000000
    ▼
 _start (boot/kernel/arch/start.S)
    │  Mask IRQ → Setup stacks → Zero BSS
    │  bl kmain
    ▼
 kmain() (kernel/main.c)
    │  UART init → banner → ...
    ▼
 Kernel đang chạy
```

---

## SPL làm gì (tóm tắt)

SPL không phải trọng tâm của docs này. Chỉ cần biết:

| Stage | Việc | Kết quả |
|-------|------|---------|
| 0 | Enable clock L3/L4 | Peripheral truy cập được |
| 1 | UART init | Debug output hoạt động |
| 2 | DDR PLL + EMIF | 512 MB DDR3 sẵn sàng từ `0x80000000` |
| 3 | MMC init + read | `kernel.bin` nằm trong DDR tại `0x80000000` |
| 4 | Jump | CPU nhảy đến `_start` |

Toàn bộ SPL code nằm trong `boot/spl/`. Không cần đọc SPL code để hiểu kernel boot.

---

## SPL → Kernel Handoff

Đây là thời điểm SPL bàn giao quyền kiểm soát cho kernel. CPU state tại lúc nhảy:

```c
/* boot/spl/src/main.c — jump to kernel */
asm volatile(
    "mov r0, #0\n"          /* reserved (zero) */
    "ldr r1, =0x0E05\n"     /* machine type: BeagleBone Black (3589) */
    "mov r2, #0\n"          /* no ATAGS/DTB pointer */
    "ldr pc, =0x80000000\n" /* jump — không dùng bl vì không cần return */
);
```

**CPU state khi `_start` nhận control:**

| Thanh ghi / Trạng thái | Giá trị |
|--------------------------|---------|
| `r0` | `0` |
| `r1` | `0x0E05` (machine type BBB) |
| `r2` | `0` (no ATAGS) |
| PC | `0x80000000` (đầu `_start`) |
| CPU mode | SVC (Supervisor) |
| MMU | **OFF** — mọi địa chỉ là physical |
| IRQ/FIQ | Không xác định — phải mask ngay |
| SP (stack) | **Không có** — đang trỏ vào SRAM (SPL đã xong, không còn hợp lệ) |
| BSS | **Chứa rác** — chưa được zero |
| DDR | Sẵn sàng: `0x80000000` – `0x9FFFFFFF` (512 MB) |

→ CPU ở trạng thái "trần truồng". `_start` phải thiết lập mọi thứ trước khi C code chạy được.

---

## Các file trong module này

| File | Nội dung |
|------|----------|
| [01_kernel_entry.md](01_kernel_entry.md) | `_start` — tại sao không vào thẳng `kmain()` |
| [02_memory_map.md](02_memory_map.md) | Physical address space và linker script layout |

---

**Tiếp theo:** [02 — Exception & Interrupt](../02_exceptions/overview.md)
