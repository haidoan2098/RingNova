# Tại sao không thể vào thẳng kmain()?

> `boot/kernel/arch/start.S` — thiết lập CPU state tối thiểu để C code chạy được

---

## Bối cảnh

SPL nhảy đến `0x80000000` bằng `ldr pc` — CPU đang ở SVC mode nhưng:

- **Không có stack** — SP trỏ vào SRAM cũ của SPL, không còn hợp lệ
- **BSS chứa rác** — DDR vừa init, chưa ai zero
- **Interrupt không xác định** — nếu IRQ fire lúc này, CPU nhảy vào exception handler không tồn tại

C compiler giả định cả 3 thứ trên đã sẵn sàng. Gọi `kmain()` trực tiếp → **undefined behavior**.

`_start` giải quyết lần lượt từng vấn đề, theo thứ tự bắt buộc.

---

## Toàn bộ start.S (BBB path)

```asm
/* boot/kernel/arch/start.S */

    .section .text.start, "ax"
    .align  4
    .global _start

_start:
    cpsid   if                          /* (1) Mask IRQ + FIQ */

    cps     #0x11                       /* (2) FIQ mode — 512 B */
    ldr     sp, =_fiq_stack_top
    cps     #0x12                       /* IRQ mode — 1 KB */
    ldr     sp, =_irq_stack_top
    cps     #0x17                       /* Abort mode — 1 KB */
    ldr     sp, =_abt_stack_top
    cps     #0x1B                       /* Undefined mode — 1 KB */
    ldr     sp, =_und_stack_top
    cps     #0x13                       /* SVC mode — 8 KB */
    ldr     sp, =_svc_stack_top

    ldr     r0, =_bss_start            /* (3) Zero BSS */
    ldr     r1, =_bss_end
    mov     r2, #0
.Lzero_bss:
    cmp     r0, r1
    strlo   r2, [r0], #4
    blo     .Lzero_bss

    bl      kmain                       /* (4) Enter C — never returns */

.Lhalt:
    b       .Lhalt                      /* (5) Safety halt */
```

4 blocks, mỗi block giải quyết 1 vấn đề. Dưới đây giải thích **tại sao** cho từng block.

---

## Block 1 — Mask Interrupt

```asm
cpsid   if          /* CPSR.I=1, CPSR.F=1 → mask cả IRQ và FIQ */
```

**Tại sao phải làm đầu tiên?**

Các bước 2 (stack setup) cần switch CPU mode bằng `cps`. Trong lúc switch, SP đang ở trạng thái chưa thiết lập. Nếu IRQ fire đúng lúc đó:

1. CPU tự động chuyển sang IRQ mode
2. Push return address lên `SP_irq` — nhưng `SP_irq` chưa set → ghi vào địa chỉ rác
3. **Crash không debug được** — PC nhảy lung tung, không có UART output

`cpsid if` đảm bảo không có interrupt nào xen vào suốt quá trình setup.

---

## Block 2 — Exception Mode Stacks

```asm
cps     #0x11                   /* Switch to FIQ mode */
ldr     sp, =_fiq_stack_top     /* Set SP_fiq */
cps     #0x12                   /* Switch to IRQ mode */
ldr     sp, =_irq_stack_top     /* Set SP_irq */
cps     #0x17                   /* Switch to Abort mode */
ldr     sp, =_abt_stack_top     /* Set SP_abt */
cps     #0x1B                   /* Switch to Undefined mode */
ldr     sp, =_und_stack_top     /* Set SP_und */
cps     #0x13                   /* Switch back to SVC mode */
ldr     sp, =_svc_stack_top     /* Set SP_svc — kernel stack */
```

### ARMv7-A Exception Modes — tại sao có 5 cái?

ARMv7-A CPU không phải chỉ có 1 chế độ chạy. Nó có **7 processor modes**, mỗi mode được kích hoạt khi một sự kiện cụ thể xảy ra. Quan trọng nhất: mỗi mode có **bộ thanh ghi SP (stack pointer) riêng** — gọi là "banked registers".

Khi exception xảy ra, CPU **tự động switch mode** và dùng SP của mode đó. Nếu SP chưa được setup → ghi vào địa chỉ rác → crash.

`_start` cần setup 5 modes. Đây là mỗi mode và **tại sao nó tồn tại**:

#### FIQ — Fast Interrupt Request (mode bits: 0x11)

**Khi nào xảy ra:** Hardware kích hoạt đường tín hiệu nFIQ trên CPU.

**Mục đích:** interrupt có độ ưu tiên cao nhất, được thiết kế cho thiết bị cần phản hồi nhanh (DMA, codec). FIQ có thêm 5 banked registers (r8-r12) nên handler không cần push/pop — nhanh hơn IRQ.

**RefixOS hiện tại:** Chưa dùng FIQ. Nhưng vẫn cần setup stack vì nếu FIQ fire vì lý do nào đó (hardware glitch, bug) mà không có stack → CPU crash không debug được.

#### IRQ — Interrupt Request (mode bits: 0x12)

**Khi nào xảy ra:** Hardware kích hoạt đường tín hiệu nIRQ — bất kỳ peripheral nào (timer, UART, GPIO...) đều trigger IRQ thông qua Interrupt Controller (INTC).

**Mục đích:** cơ chế chính để hardware thông báo cho CPU. Timer tick cho scheduler, UART nhận data, GPIO button press — tất cả đều đi qua IRQ.

**RefixOS sẽ dùng:** Timer IRQ cho preemptive scheduler (phase sau). Stack 1 KB đủ cho IRQ handler + context save.

#### Abort (mode bits: 0x17)

**Khi nào xảy ra:** 2 trường hợp, cả 2 đều chuyển CPU sang Abort mode:

- **Prefetch Abort:** CPU fetch instruction từ địa chỉ không hợp lệ (ví dụ: nhảy vào vùng unmapped)
- **Data Abort:** CPU đọc/ghi vào địa chỉ không hợp lệ (ví dụ: null pointer dereference, access vùng không có RAM)

**Mục đích:** tương đương "segfault" trên Linux. Trên bare-metal, abort handler thường in debug info (DFAR, DFSR registers chứa địa chỉ và lý do lỗi) rồi halt.

**RefixOS sẽ dùng:** Khi bật MMU, mỗi lần process truy cập vùng cấm → Data Abort → kernel xử lý (kill process hoặc page fault handling).

#### Undefined Instruction (mode bits: 0x1B)

**Khi nào xảy ra:** CPU gặp instruction mà nó không hiểu — ví dụ: nhảy vào vùng data (data bị decode thành opcode vô nghĩa), hoặc dùng coprocessor instruction mà coprocessor không có.

**Mục đích:** bắt lỗi khi code nhảy lung tung hoặc binary bị corrupt.

**RefixOS hiện tại:** Handler in thông báo lỗi rồi halt — dùng cho debug.

#### SVC — Supervisor Call (mode bits: 0x13)

**Khi nào xảy ra:** 2 cách:
- Instruction `SVC #n` (software interrupt) — user process gọi system call
- CPU default boot vào SVC mode sau reset

**Mục đích:** mode chính của kernel. Tất cả kernel C code chạy ở SVC mode. Sau này khi có user space, `SVC #0` là cách duy nhất user process giao tiếp với kernel (syscall).

**RefixOS:** Stack SVC = 8 KB — lớn nhất vì toàn bộ `kmain()` và kernel C code chạy trên stack này.

#### Tóm tắt bằng sơ đồ

```text
Exception xảy ra                CPU tự động switch mode
─────────────────                ───────────────────────
nFIQ pin active           ───→   FIQ mode  (SP_fiq)
nIRQ pin active           ───→   IRQ mode  (SP_irq)
Invalid memory access     ───→   Abort mode (SP_abt)
Bad instruction           ───→   Undef mode (SP_und)
SVC #n / Reset            ───→   SVC mode  (SP_svc)
                                      │
                                      ▼
                            Mỗi mode dùng SP riêng
                            → phải setup trước khi enable
```

> **Hai mode còn lại:** User mode (mode 0x10) và System mode (mode 0x1F) — không phải exception mode nên không cần setup ở đây. User mode sẽ dùng khi có user process (phase sau). System mode dùng chung SP với User mode.

### Tại sao cần 5 stack riêng biệt?

ARMv7-A có **banked SP** — mỗi exception mode dùng thanh ghi SP vật lý riêng. Khi CPU nhận exception (IRQ, data abort, undefined instruction...), nó **tự động switch mode** và dùng SP của mode đó.

Nếu thiếu stack cho bất kỳ mode nào → exception handler không có stack → double fault.

### Tại sao switch mode bằng CPS thay vì MRS/BIC/ORR/MSR?

SPL dùng MRS/BIC/ORR/MSR (4 lệnh để switch mode). Kernel `_start` dùng `cps` (1 lệnh). Cả hai đều đúng, nhưng `cps` là instruction chuyên dụng cho việc này trên ARMv7-A — ngắn hơn và không cần register tạm.

### Tại sao SVC mode phải switch cuối cùng?

`kmain()` chạy ở SVC mode. `cps #0x13` cuối cùng đảm bảo CPU đang ở SVC khi `bl kmain` thực thi. Nếu quên bước này → `kmain()` chạy ở mode sai → stack sai → crash.

### Stack sizes (từ objdump thực tế)

| Mode | Size | SP init (objdump) | Dùng cho |
| ---- | ---- | ------------------ | -------- |
| FIQ | 512 B | `0x80000508` | Chưa dùng, dự phòng cho handler tối thiểu |
| IRQ | 1 KB | `0x80000908` | Timer IRQ handler + context save (phase sau) |
| Abort | 1 KB | `0x80000D08` | Debug print khi prefetch/data abort |
| Undefined | 1 KB | `0x80001108` | Debug print khi gặp instruction lạ |
| SVC | 8 KB | `0x80003108` | **Kernel C code chạy ở đây** — cần nhiều nhất |

Tổng: **11.5 KB** (0x2E00). Bắt đầu từ `0x80000308` (ngay sau .text), kết thúc tại `0x80003108`.

---

## Block 3 — Zero BSS

```asm
ldr     r0, =_bss_start
ldr     r1, =_bss_end
mov     r2, #0
.Lzero_bss:
    cmp     r0, r1
    strlo   r2, [r0], #4       /* if r0 < r1: *r0 = 0; r0 += 4 */
    blo     .Lzero_bss
```

**Tại sao phải zero thủ công?**

C standard quy định: biến global/static chưa khởi tạo (`int x;`) phải bằng 0. Trên hosted environment, runtime (`crt0`) làm việc này. Trên bare-metal, **không có runtime** — phải tự làm.

`_bss_start` và `_bss_end` là linker symbols đánh dấu vùng BSS trong RAM. Loop trên ghi `0` vào từng word 4 bytes.

**Nếu bỏ qua:** mọi global variable chưa khởi tạo sẽ chứa giá trị rác từ DDR. Bug âm thầm — code có thể chạy "gần đúng" rồi crash ngẫu nhiên.

---

## Block 4 — Jump to C

```asm
bl      kmain           /* Branch with Link — LR = địa chỉ sau bl */

.Lhalt:
    b       .Lhalt      /* Infinite loop nếu kmain() return */
```

**Tại sao `bl` thay vì `b`?**

`bl` lưu return address vào LR. Mặc dù `kmain()` không bao giờ return, nhưng GCC cần `bl` cho calling convention — nếu dùng `b`, compiler có thể optimize sai.

**Safety halt:** nếu vì bug mà `kmain()` return, CPU đứng yên tại `.Lhalt` thay vì chạy vào vùng nhớ rác.

---

## Disassembly thực tế (objdump)

Dưới đây là output từ `arm-linux-gnueabihf-objdump -d build/bbb/kernel.elf`, cho thấy toàn bộ `_start` được compile thành gì:

```text
80000000 <_start>:
80000000:   f10c00c0    cpsid   if
80000004:   f1020011    cps     #17                @ FIQ mode
80000008:   e59fd03c    ldr     sp, [pc, #60]      @ =0x80000508
8000000c:   f1020012    cps     #18                @ IRQ mode
80000010:   e59fd038    ldr     sp, [pc, #56]      @ =0x80000908
80000014:   f1020017    cps     #23                @ Abort mode
80000018:   e59fd034    ldr     sp, [pc, #52]      @ =0x80000D08
8000001c:   f102001b    cps     #27                @ Undefined mode
80000020:   e59fd030    ldr     sp, [pc, #48]      @ =0x80001108
80000024:   f1020013    cps     #19                @ SVC mode
80000028:   e59fd02c    ldr     sp, [pc, #44]      @ =0x80003108
8000002c:   e59f002c    ldr     r0, [pc, #44]      @ =0x80000308 (_bss_start)
80000030:   e59f102c    ldr     r1, [pc, #44]      @ =0x80000308 (_bss_end)
80000034:   e3a02000    mov     r2, #0
80000038:   e1500001    cmp     r0, r1
8000003c:   34802004    strcc   r2, [r0], #4
80000040:   3afffffc    bcc     80000038
80000044:   eb000007    bl      80000068 <kmain>
80000048:   eafffffe    b       80000048           @ .Lhalt
```

Chú ý: `_bss_start == _bss_end == 0x80000308` — hiện tại BSS rỗng (kernel chưa có biến global chưa khởi tạo), nên zero BSS loop chạy 0 vòng. Literal pool (các `.word` cuối) chứa các địa chỉ stack top — đây là cách ARM load 32-bit constant vào register.

---

## kmain() — đầu vào C

```c
/* kernel/main.c */
void kmain(void)
{
    uart_init();

    uart_puts("\r\n");
    uart_puts("================================================\r\n");
    uart_puts("  RefixOS — ARMv7-A bare-metal kernel\r\n");
    uart_puts("  Boot OK — UART online\r\n");
    uart_puts("================================================\r\n");

    for (;;)
        ;
}
```

Hiện tại `kmain()` chỉ:
1. Init UART (NS16550 trên AM335x)
2. In banner xác nhận boot thành công
3. Halt — chờ implement exception vector (bước tiếp theo)

UART driver nằm trong `bsp/drivers/uart/uart.c`, dùng base address từ `bsp/include/board.h`.

---

## Gotcha

- **Thứ tự block 1 → 2 → 3 → 4 là bắt buộc.** Không thể đảo. Mask interrupt trước stack, stack trước BSS zero, BSS zero trước C code.
- **Không có vector table.** `_start` hiện tại chưa set VBAR — nếu exception xảy ra trong `kmain()`, CPU nhảy vào địa chỉ `0x00000000` (default vector). Đây là việc của module tiếp theo (02_exceptions).
- **CPS chỉ có trên ARMv7-A trở lên.** SPL dùng MRS/BIC/ORR/MSR vì lý do khác (comment style). Cả hai cách đều hoạt động trên Cortex-A8.

---

## Liên kết

- **Phụ thuộc:** SPL handoff — xem [overview.md](overview.md)
- **Linker symbols** (`_bss_start`, `_svc_stack_top`...): [02_memory_map.md](02_memory_map.md)
- **Tiếp theo:** [02 — Exception & Interrupt](../02_exceptions/overview.md)
