+++
title = "STM32 'Hello, world!' with Zig"
date = "2024-09-23"
+++

# Introduction

I've been using Zig [a
lot](https://github.com/weskoerber?tab=repositories&q=&type=&language=zig&sort=stargazers)
over the past few months writing wide variety of projects. From
[kewpie](https://github.com/weskoerber/kewpie), a simple query string parser,
to [dirtstache](https://github.com/weskoerber/dirtstache), a
[Mustache](https://mustache.github.io/) implementation -- even a
[libcurl](https://curl.se/libcurl/) wrapper with
[zig-curl](https://github.com/weskoerber/zig-curl) -- I have experience with
Zig across a wide range of domains.

However, I've always wanted to use Zig on an embedded target. On paper, Zig is
an excellent choice for embedded programming: no implicit allocations, no
hidden control flow, seamless integration with the C ABI, a fantastic build
system[^1], etc. However, that's on paper. I wanted to see for myself if the
advertised strengths of Zig held up when put to the test, especially in a
resource-constrained embedded environment.

Well, I did just that. In this post I'll retrace my steps in how I went from an
empty `main.zig` to printing `Hello, World!` to my terminal.

# Goals

Before writing any Zig code, I set some goals for this project in order to
maximize my learning potential:
1. No dependencies
2. 100% Zig code
3. A 3-day time limit

# What we're working with

## Hardware

I have a few Cortex-M4 development boards laying around: an
[MSP432P4](https://docs.rs-online.com/3934/A700000006811369.pdf)
([RIP](https://e2e.ti.com/support/microcontrollers/arm-based-microcontrollers-group/arm-based-microcontrollers/f/arm-based-microcontrollers-forum/1007640/msp432p401r-is-the-msp432-line-discontinued)),
a [NUCLEO-F4](https://www.st.com/en/evaluation-tools/nucleo-f401re.html), and a
[NUCLEO-L4](https://www.st.com/en/evaluation-tools/nucleo-l496zg.html). For
this experiment, I decided to go with the NUCLEO-F4 for no reason other than it
was sitting closest to me at the time.

The process is quite similar for other Cortex-M4-based MCUs, so feel free to
follow along with your own hardware. The peripherals on your device may vary,
so consult your device's reference manual.

## Software

### Flash programming

You'll need a way to flash the code to your MCU. I'm using
[OpenOCD](https://openocd.org/) to flash mine. However, there are several other
utilities out there you may choose from.

### Compiler and binary utilities

I'm using Zig master version `0.14.0-dev.1632+d83a3f174`, installed via
[zvm](https://github.com/weskoerber/zvm). Note that this version is in
development and has some [planned breaking
changes](https://github.com/ziglang/zig/issues?q=is%3Aissue+is%3Aopen+milestone%3A0.14.0+label%3Abreaking),
so this may not work in the future.

In addition to the Zig compiler (and its suite of binary utilities), the [GNU
binutils](https://www.gnu.org/software/binutils/) will help us out immensely if
things go wrong. Notably, Zig doesn't ship with
[`nm`](https://sourceware.org/binutils/docs-2.39/binutils/nm.html) or
[`objdump`](https://sourceware.org/binutils/docs-2.39/binutils/objdump.html)
utilities. I strongly recommend installing the [GCC toolchain for
ARM](https://developer.arm.com/Tools%20and%20Software/GNU%20Toolchain) before
continuing.

## Literature

You'll absolutely need the documentation on your MCU, unless you're some
superhuman that's memorized everything. At the very least, you'll need:
- MCU reference manual
- Cortex-M4 reference manual
- Device-specific datasheet
- Development board user manual

# Getting started

I was excited. I finally sat down and was ready to make some LEDs blink. I
created my project and an empty `build.zig` and `main.zig` with an empty while
loop:
```zig
pub fn build(b: *std.Build) void {}

const std = @import("std");
```

`main.zig`:
```zig
pub fn main() void {
    asm volatile ("nop"); // Prevents optimizing the loop away
}
```

# Build my thing

The first logical step here was to get *something* to build. Since we know
we're only going to run this code on a Cortex-M4 MCU, we can hard-code the
target field using
[`b.resolveTargetQuery`](https://ziglang.org/documentation/master/std/#std.Build.resolveTargetQuery)
instead of using the usual
[`b.standardTargetOptions`](https://ziglang.org/documentation/master/std/#std.Build.standardTargetOptions).
```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "stm32-test",
        .root_source_file = b.path("src/main.zig"),
        .optimize = b.standardOptimizeOption(.{}),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .thumb,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
            .os_tag = .freestanding,
            .abi = .eabihf,
        }),
    });

    const install_exe = b.addInstallArtifact(exe, .{});

    b.getInstallStep().dependOn(&install_exe.step);
}

const std = @import("std");
```

After running `zig build`, `stm32-test` was put in `zig-out/bin`:
```
❯ file zig-out/bin/stm32-test
zig-out/bin/stm32-test: ELF 32-bit LSB executable, ARM, EABI5 version 1 (SYSV), statically linked, with debug_info, not stripped
```

Theoretically, we could flash this to the MCU right now, but it wouldn't work.

# Convert ELF to binary {#convert-elf-to-binary}

I said that flashing the `ELF` file we created in the previous step won't work.
Let's dive into why it won't work.

The Cortex-M4 doesn't know about the `ELF` file format. It loads
programs in a very specific way, and just executes instructions sequentially.
In my case, the STM32F4 has a few different boot modes but we'll stick with the
default -- booting from main flash memory. The reference manual says this about
booting:
> \[T\]he CPU fetches the top-of-stack value from address 0x0000 0000, then
> starts code execution from the boot memory starting from 0x0000 0004.

We won't get too deep into the startup process here. It's covered in [Cortex M4
startup](#cortex-m4-startup).

The first 4 bytes of the `ELF` file header are `7f 45 4c 46`. If we flashed
this to the MCU, it would fetch this value and set it to the stack pointer,
then start executing spurious instructions. Who knows what would happen in this
case. At best, an invalid instruction execution causes an interrupt that resets
the MCU. Additionally, the `ELF` file contains other non-binary data, such as
debug sympols, section tables, etc. We don't want the MCU interpreting these
data as instructions, so we'll need to convert to a different format.

This is where `objcopy` comes into play. We'll convert our `ELF` file into a
`BIN` file. `objcopy`'s man page says this:
> objcopy can be used to generate a raw binary file by using an output target
> of ‘binary’ (e.g., use -O binary). When objcopy generates a raw binary file,
> it will essentially produce a memory dump of the contents of the input object
> file. All symbols and relocation information will be discarded. The memory
> dump will start at the load address of the lowest section copied into the
> output file.

This is what we want -- raw instructions and data to flash onto the MCU. Zig
ships with an implementation of `objcopy`. Let's update our `build.zig` file to
convert the `ELF` file into a binary file:

```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable({
        // -- snip
    });

    const bin = exe.addObjCopy(.{ .format = .bin });
    const install_exe = b.addInstallArtifact(exe, .{});
    const install_bin = b.addInstallBinFile(bin.getOutput(), bin.basename);

    b.getInstallStep().dependOn(&install_bin.step);
    install_bin.step.dependOn(&install_exe.step);
}
```

After re-running `zig build`, we now get `stm32-test.bin` alongside
`stm32-test` in `zig-out/bin`. Sweet!

# Memory map and linking

We can avoid this topic no longer. We must now talk about linking and the
memory map.

Embedded devices typically have small amounts of flash and SRAM. My STM32F401RE
has 512K of flash and 92K of SRAM. In addition to flash and data memory, the
Cortex-M4 has memory-mapped peripherals. Even though the *amount* flash and
data memory is small, the *address space* is quite large with 4G of addressable
memory.

First, lets take a look at how the linker put our `ELF` together:
```
❯ arm-none-eabi-objdump -h zig-out/bin/stm32-test

zig-out/bin/stm32-test:     file format elf32-littlearm

Sections:
Idx Name          Size      VMA       LMA       File off  Algn
  0 .ARM.exidx    00000a50  000100f4  000100f4  000000f4  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  1 .rodata       00001db8  00010b48  00010b48  00000b48  2**3
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  2 .ARM.extab    00000b7c  00012900  00012900  00002900  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  3 .text         0001f604  0002347c  0002347c  0000347c  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  4 .data         00000004  00052a80  00052a80  00022a80  2**2

// -- snip
```

Note two key headings in the output of `objdump`: VMA and LMA. GNU's ld has a
great description of VMA and LMA, so I'll let them do the talking:
> Every loadable or allocatable output section has two addresses. The first is
> the VMA, or virtual memory address. This is the address the section will have
> when the output file is run. The second is the LMA, or load memory address.
> This is the address at which the section will be loaded. In most cases the
> two addresses will be the same. An example of when they might be different is
> when a data section is loaded into ROM, and then copied into RAM when the
> program starts up (this technique is often used to initialize global
> variables in a ROM based system). In this case the ROM address would be the
> LMA, and the RAM address would be the VMA.

In other words, LMA is the physical address in the MCU's memory, whereas VMA is
the address within the MCU's memory map.

We need to tell the linker how to lay out each section of our `ELF` file so
that we can flash it to the target and ensure it executes the instructions we
want it to. In order to do this, we'll need a custom linker script.

## Linker script

There are so many good resources out there regarding linker scripts. I will
only briefly explain the parts of the linker script as it relates to the
Cortext-M4. If you want more in-depth information on linker scripts, refer to
the references below.

Before we get started, let's tell Zig to use this linker script:
```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable({
        // -- snip
    });
    exe.setLinkerScript(b.path("stm32f401re.ld"));

    // -- snip
}
```

### Memory Regions

We need to tell our linker about the memory layout of our target. We do so
using the
[`MEMORY`](https://ftp.gnu.org/old-gnu/Manuals/ld-2.9.1/html_node/ld_16.html)
keyword:
```ld
FLASH_SIZE = 0x80000; /* 512k flash */
SRAM_SIZE = 0x17000; /* 92k sram */
STACK_SIZE = 0x800; /* 2k stack */

MEMORY
{
    flash (rx) : ORIGIN = 0x08000000, LENGTH = FLASH_SIZE
    sram (rwx) : ORIGIN = 0x20000000, LENGTH = SRAM_SIZE
}
```

Here, we define our flash as a 512K region of read-only memory beginning at
address `0x0800_0000` and our sram as a 92K region of read-write memory
beginning at address `0x2000_0000`. We'll use the `STACK_SIZE` variable later.

### Entry point {#entry-point}

The linker needs an entry point. Let's define our entry point as the first vector in our vector table, `resetHandler` (see [vector table](#vector-table) below):
```ld
ENTRY(resetHandler)
```

### Sections

Next we define the layout of our output file with the
[`SECTIONS`](https://ftp.gnu.org/old-gnu/Manuals/ld-2.9.1/html_node/ld_18.html#SEC18)
keyword:
```ld
SECTIONS
{
}
```

#### `.text` section

```ld
SECTIONS
{
    /* snip */

    .text :
    {
        . = ALIGN(4);
        LONG(__initial_stack_pointer)
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > flash

    /* snip */
}
```

Quite a lot is happening here. Let's break it down line-by-line:
- align the `.text` section on a 4-byte boundary
- reserve 4-bytes at the start of the `.text` section for the initial stack pointer
- place the vector table immediatly after our initial stack pointer
- place the code following the reset vectors
- place read-only data after the code
- align the end of the `.text` section on a 4-byte boundary

#### `.stack` section

Next comes the stack section. We'll reserve spack for our stack using the
`STACK_SIZE` variable we created earlier. Note that the [ARM Procedure Call
Standard
(AAPCS)](https://github.com/ARM-software/abi-aa/blob/main/aapcs32/aapcs32.rst)
says that the stack must be double word (8-byte) aligned, not single word
(4-byte).

```ld
SECTIONS
{
    /* snip */

    .stack (NOLOAD) :
    {
        . = ALIGN(8);
        . = . + STACK_SIZE;
        . = ALIGN(8);
        __initial_stack_pointer = .;
    } > sram

    /* snip */
}
```

- align the bottom of the stack on an 8-byte boundary
- reserve space for stack defined by `STACK_SIZE`
- align the top of the stack on an 8-byte boundary
- set the `__initial_stack_pointer` to the current position

#### `.data` section

```ld
SECTIONS
{
    /* snip */

    .data :
    {
        _sdata = .;
        . = ALIGN(4);
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > sram AT> flash

    _ldata = LOADADDR(.data);

    /* snip */
}
```

- align the `.data` section on a 4-byte boundary
- define a symbol `_sdata` that marks the start of the `.data` section
- place initialized data in the output file
- define a symbol `_edata` that marks the end of the `.data` section
- align the `.data` section on a 4-byte boundary
- define a symbol `_ldata` that holds the LMA of our `.data` section

Note the last part `> sram AT> flash`. This tells the linker that we want to
put the data in the `sram` region of memory, but we're going to load it from
the `flash` region. This is important for understanding [what happens before
`main()`](#before-main).

#### `.bss` section

```ld
SECTIONS
{
    /* snip */

    .bss (NOLOAD) :
    {
        _szero = .;
        . = ALIGN(4);
        *(.bss*)
        . = ALIGN(4);
        _ezero = .;
    } > sram

    /* snip */
}
```

- align the `.bss` section on a 4-byte boundary
- define a symbol `_szero` that marks the start of the `.bss` section
- place initialized data in the output file
- define a symbol `_ezero` that marks the end of the `.bss` section
- the `.bss` section on a 4-byte boundary

References: [^2] [^3]

# The vector table {#vector-table}

In the previous section, we put the vector table (`.vectors`) at the start of
the `.text` section preceded only by the 4-byte initial stack pointer. Let's
define our vector table in Zig:
```zig
pub fn main() void {
}

export fn resetHandler() callconv(.C) void {}
export fn nmiHandler() callconv(.C) void {}
export fn hardFaultHandler() callconv(.C) void {}
export fn memManageHandler() callconv(.C) void {}
export fn busFaultHandler() callconv(.C) void {}
export fn usageFaultHandler() callconv(.C) void {}
export fn svCallHandler() callconv(.C) void {}
export fn debugMonitorHandler() callconv(.C) void {}
export fn pendSvHandler() callconv(.C) void {}
export fn sysTickHandler() callconv(.C) void {}

export const vectors linksection(".vectors") = [_]?*const fn () callconv(.C) void{
    resetHandler,
    nmiHandler,
    hardFaultHandler,
    memManageHandler,
    busFaultHandler,
    usageFaultHandler,
    null, // reserved
    null, // reserved
    null, // reserved
    null, // reserved
    svCallHandler,
    debugMonitorHandler,
    null, // reserved
    pendSvHandler,
    sysTickHandler,
    // -- snip: continued for MCU-specific interrupts; consult datasheet
};
```

Here, we create our vector table, which is an array of function pointers having
the signature:
```zig
const fn () callconv(.C) void
```

Each index in the array corresponds to an interrupt vector. The elements
containing `null` values are reserved. The first 15 bytes of this table will be
identical across all Cortex-M4 MCUs. After that, each MCU will have its own
order for device-specific interrupts.

The `linksection(".vectors")` tells the linker that we want to put this
declaration in the `.vectors` section of the file. This is analogous to
`__attribute__((section(".vectors")))` in GCC.

# Cortex-M4 startup {#cortex-m4-startup}

Now that we told the linker where to put our code, let's talk about why we put
it there. Recall the quote from the datasheet in the [Convert ELF to
binary](#convert-elf-to-binary) section:
> \[T\]he CPU fetches the top-of-stack value from address 0x0000 0000, then
> starts code execution from the boot memory starting from 0x0000 0004.

When the MCU boots up, the first thing it does is fetch the value at address
`0x0000_0000` and uses it as its stack pointer. There are a couple of
interesting things to note here. First, the address `0x0000_0000` is aliased to
`0x0800_0000` (see footnote [^4] for more info). This means that our
`__initial_stack_pointer` we put at `0x0800_0000` is accessible also from
`0x0000_0000`.

After our stack pointer is loaded, the MCU proceeds to `0x0000_0004` and starts
executing instructions.

Let's take a closer look at our output file. First, let's check out the section table:

```
❯ arm-none-eabi-objdump -h zig-out/bin/stm32-test

zig-out/bin/stm32-test:     file format elf32-littlearm

Sections:
Idx Name          Size      VMA       LMA       File off  Algn
  0 .text         0000000c  08000000  08000000  00010000  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  1 .ARM.exidx    00000010  0800000c  0800000c  0001000c  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  2 .stack        00000800  20000000  20000000  00020000  2**0
                  ALLOC, READONLY
  3 .data         00000000  20000800  20000000  00020000  2**0
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  4 .bss          00000000  20000800  20000800  00020000  2**0
                  ALLOC
  5 .ARM.attributes 0000003f  00000000  00000000  00020000  2**0
                  CONTENTS, READONLY
  6 .comment      00000067  00000000  00000000  0002003f  2**0
                  CONTENTS, READONLY
```

Here, we see:
- `.text` section starting at `0x0800_0000` corresponding with the start of the `flash` region
- `.stack` section starting at `0x2000_0000` corresponding with the start of the `sram` region and having a length of `0x800`
- `.data` section starting immediately after our `.stack` section
- `.bss` section starting immediately after our `.data` section

```asm
❯ arm-none-eabi-objdump -d -j .text zig-out/bin/stm32-test | head -n 20

zig-out/bin/stm32-test:     file format elf32-littlearm


Disassembly of section .text:

08000000 <vectors-0x4>:
 8000000:       20000800        andcs   r0, r0, r0, lsl #16

08000004 <vectors>:
 8000004:       08000059 0800005d 08000061 08000065     Y...]...a...e...
 8000014:       08000069 0800006d 00000000 00000000     i...m...........
        ...
 800002c:       08000071 08000075 00000000 08000079     q...u.......y...
 800003c:       0800007d                                }...
```

Here, we see the value `20000800`, which corresponds to the top of our stack.
This is the `__initial_stack_pointer` we reserved in the `.text` section and
defined in the `.stack` section of our linker script. The following few
addresses are our interrupt vectors that were placed in the `.text` section.
How cool is that!

# What happens before `main()`? {#before-main}

When we compile an application on our PCs, we might assume that the entry point
for the application is the `main()` function. If you assumed that, you're half
right. The `main` function is the entry point *your* application, but that's
not what the operating system calls. The operating system calls the `_start()`
function, which is usually provided by your libc.

When you build a C/C++ application for Linux, your system's libc implementation
is implicitly linked to your application, which includes a piece of code called
the "startup code". The startup code does things like initilize `argc` and
`argv`, call constructors, and so on. I won't get into too much detail here.
Instead, check out the references below for some deep-dives.

Even though we set our [entry point](#entry-point) above, we'll still need to
define our `_start()` symbol, otherwise the linker complains at us. Let's add the following to our `main.zig`:
```zig
export fn _start() void {
    main();

    while (true) {
        asm volatile ("nop");
    }
}
```

We implement an exported `_start()` function that just calls `main()`. If main
returns (which it shouldn't), we'll just hang in an infinite loop.

Here's what code got generated:
```asm
08000040 <_start>:
 8000040:       b580            push    {r7, lr}
 8000042:       466f            mov     r7, sp
 8000044:       f000 f804       bl      8000050 <main.main>
 8000048:       e7ff            b.n     800004a <_start+0xa>
 800004a:       bf00            nop
 800004c:       e7fd            b.n     800004a <_start+0xa>
 800004e:       bf00            nop

08000050 <main.main>:
 8000050:       e7ff            b.n     8000052 <main.main+0x2>
 8000052:       bf00            nop
 8000054:       e7fd            b.n     8000052 <main.main+0x2>
 8000056:       bf00            nop

08000058 <resetHandler>:
 8000058:       4770            bx      lr
 800005a:       bf00            nop
```

Awesome, we made it to `main()`! You'd expect this to work once flashed to the
MCU, right? Well, you're in for disappointment. Review the Cortex-M4 startup
process: we fetch the stack pointer and begin executing instructions at
`0x0000_0004`, which is our reset handler. However, our reset handler doesn't
do anything, so main will never be called.

In order to fix this, `resetHandler()` needs to call `_start()`:
```zig
export fn resetHandler() callconv(.C) void {
    _start();
}
```

That gives us the following:
```asm
08000040 <_start>:
 8000040:       b580            push    {r7, lr}
 8000042:       466f            mov     r7, sp
 8000044:       f000 f804       bl      8000050 <main.main>
 8000048:       e7ff            b.n     800004a <_start+0xa>
 800004a:       bf00            nop
 800004c:       e7fd            b.n     800004a <_start+0xa>
 800004e:       bf00            nop

08000050 <main.main>:
 8000050:       e7ff            b.n     8000052 <main.main+0x2>
 8000052:       bf00            nop
 8000054:       e7fd            b.n     8000052 <main.main+0x2>
 8000056:       bf00            nop

08000058 <resetHandler>:
 8000058:       b580            push    {r7, lr}
 800005a:       466f            mov     r7, sp
 800005c:       f7ff fff0       bl      8000040 <_start>
 8000060:       bd80            pop     {r7, pc}
 8000062:       bf00            nop
```

Now we can see that `resetHandler()` calls `_start()`, which calls `main()`.
Are we there yet? Technically, yes - but we still have work to do. If you're
working entirely on the stack and don't rely on preinitialized memory, you can
get started, and even make an LED blink.

However, in most cases, you'll want to load up your memory from the `.data` and
`.bss` sections -- this is not done for you automatically like it is when you
run a program on your computer. Embedded startup code must explicitly perform
this step.

To do this, we'll need to refer back to the symbols we created in the linker script:
- `_sdata`: the start of the `.data` section
- `_edata`: the end of the `.data` section
- `_ldata`: the LMA of the `.data` section
- `_szero`: the start of the `.bss` section
- `_ezero`: the end of the `.bss` section

For our `.bss` section, we need to zero out all memory between `_szero` and
`_ezero`. For the `.data` section, we need to copy the memory from `_ldata`
into the memory from `_sdata` to `_edata`. Let's do this in our `_start()` function:
```zig
extern var _szero: u32;
extern var _ezero: u32;
extern var _sdata: u32;
extern var _edata: u32;
extern var _ldata: u32;

export fn _start() void {
    const szero: [*]u32 = @ptrCast(&_szero);
    const sdata: [*]u32 = @ptrCast(&_sdata);
    const ldata: [*]u32 = @ptrCast(&_ldata);

    const bss_len = _ezero - _szero;
    if (bss_len > 0) {
        @memset(szero[0 .. _ezero - _szero], 0);
    }

    const data_len = _edata - _sdata;
    if (data_len > 0) {
        @memcpy(sdata[0..data_len], ldata[0..data_len]);
    }

    main();

    while (true) {
        asm volatile ("nop");
    }
}
```

And there you have it! We've reached main! That's a lot of stuff happening
under the hood... Note that your startup code isn't limited to initilizing
system memory. The possibilities are endless. One thing you might consider
putting in your startup code is system clock setup. But that's outside the
scope of this project, for now at least.

References: [^5] [^6]

# Flashing

As I mentioned earlier, I'm using OpenOCD to flash the MCU. I created a step in `build.zig` that would do this for me:
```zig
pub const build(b: *std.Build) void {
    // -- snip

    const flash_run = b.addSystemCommand(&.{
        "openocd",
        "-f",
        "/usr/share/openocd/scripts/board/st_nucleo_f4.cfg",
        "-c",
        "init",
        "-c",
        "reset halt; flash write_image erase zig-out/bin/stm32-test.bin 0x08000000 bin",
        "-c",
        "flash verify_image zig-out/bin/stm32-test.bin 0x08000000 bin",
        "-c",
        "reset run; shutdown",
    });
    const flash_step = b.step("flash", "Flash the code to the target");

    flash_run.step.dependOn(&install_bin.step);
    flash_step.dependOn(&flash_run.step);

    // -- snip
}
const std = @import("std");
```

To flash the MCU, all I need to do is `zig build flash`. The artifacts are
rebuilt only when needed, and flashing is handled via the system command to
`openocd`.

# Blink a damn LED

The NUCLEO-F401RE development board has an LED wired up to GPIO `PA5`. Before
anything else, the GPIO A clocks need to be enabled on the `AHB1` bus. We do
this by setting the `GPIOA EN` bit in the `RCC_AHB1ENR` register. After that'
we're free to configure the GPIO pin as an output and toggle the `ODR` register
to turn the LED on and off.

```zig
const rcc_ahb1enr: *volatile u32 = @ptrFromInt(0x4002_3830);
const gpio_a_mode: *volatile u32 = @ptrFromInt(0x4002_0000);
const gpio_a_odr: *volatile u32 = @ptrFromInt(0x4002_0014);

pub fn main() void {
    rcc_ahb1enr.* |= 1;
    gpio_a_mode.* |= (1 << 10);
    gpio_a_odr.* = 0;

    while (true) {
        for (0..1000000) |_| {
            asm volatile ("nop");
        }

        gpio_a_odr.* ^= 1 << 5;
    }
}
```

# Hello, world!

Next, we need to enable the UART. On my board, USART2 (GPIO `PA2` & `PA3`) is
exposed over to the ST-Link. In rough steps, we need to do the following:
1. enable `APB1` bus clocks for USART2
2. set GPIO mode to alternate function
3. configure alternate function to USART2
5. enable USART2
4. configure the baud rate
5. enable the transmitter
6. send data

Here's what I came up with:
```zig
const rcc_ahb1enr: *volatile u32 = @ptrFromInt(0x4002_3830);
const rcc_apb1enr: *volatile u32 = @ptrFromInt(0x4002_3840);
const gpio_a_moder: *volatile u32 = @ptrFromInt(0x4002_0000);
const gpio_a_odr: *volatile u32 = @ptrFromInt(0x4002_0014);
const gpio_a_aflr: *volatile u32 = @ptrFromInt(0x4002_0020);
const usart_2_sr: *volatile u32 = @ptrFromInt(0x4000_4400);
const usart_2_dr: *volatile u32 = @ptrFromInt(0x4000_4404);
const usart_2_brr: *volatile u32 = @ptrFromInt(0x4000_4408);
const usart_2_cr1: *volatile u32 = @ptrFromInt(0x4000_440c);

pub fn main() void {
    rcc_ahb1enr.* |= 1;
    rcc_apb1enr.* |= (1 << 17);

    gpio_a_moder.* |= (1 << 10);
    gpio_a_odr.* = 0;

    gpio_a_moder.* |= (2 << 6) | (2 << 4);
    gpio_a_aflr.* |= (7 << 8) | (7 << 12);

    usart_2_cr1.* |= (1 << 13);
    usart_2_brr.* |= 0xffff & ((8 << 4) | (11));
    usart_2_cr1.* |= (1 << 3);

    const xmit_str = "Hello, world!\r\n";
    var xmit = false;

    while (true) {
        if (!xmit) {
            xmit = true;

            for (xmit_str) |c| {
                while (usart_2_sr.* & (1 << 7) == 0) {}
                usart_2_dr.* |= c;
            }
        }

        for (0..1000000) |_| {
            asm volatile ("nop");
        }

        gpio_a_odr.* ^= 1 << 5;
    }
}
```

Attaching to the serial port and flashing the code gives me what I want:
```
Hello, world!
```

# Conclusion

If you couldn't tell, I'm getting burned out writing this. This post has taken
me the better part of a day. Even though it's somewhat laborious, I
accomplished my goal of getting "Hello, World!" printed to my terminal from an
embedded device without any dependencies within the time limit I imposed on
myself.

The code is not particularly readable, though. The register access is esoteric,
and there's no documentation about what each value means. However, there are
some pretty elegant ways of solving that problem that I hope to share in a
follow-up post. However, that's all for today.

Zig has quickly become my favorite language since I picked it up back in
February when it was in `0.11.0`. We're now in `0.13.0`. So much has changed,
and the `0.14.0-dev` branch has seemingly more changes than ever. Since
`0.11.0`, the language, its standard library, and its build system have seem
massive improvements. If you're looking to try out Zig, there's no better time
than now!.

---

[^1]: I have a lot to say about the Zig build system. Stay tuned for that post!

[^2]: [Basic Linker Script Concepts](https://sourceware.org/binutils/docs/ld/Basic-Script-Concepts.html)

[^3]: [The most thoroughly commented linker script (probably)](https://blog.thea.codes/the-most-thoroughly-commented-linker-script/)

[^4]: The STM32F401RE aliases address `0x0000_0000` to flash memory at
    `0x0800_0000` up to 256KB. In other words, when we reference `0x0000_0000`,
    the address is translated to `0x0800_0000`; when `0x0000_0004` is accessed,
    the address is translated to `0x0800_0004`; and so on. This means that our
    LMA for flash may be either of these values. This is relevant to understand
    the [Cortex-M4 startup](#cortex-m4-startup) proccess.

[^5]: [A Whirlwind Tutorial on Creating Really Teensy ELF Executables for Linux](https://www.muppetlabs.com/~breadbox/software/tiny/teensy.html)

[^6]: [Linux x86 Program Start Up](http://dbp-consulting.com/tutorials/debugging/linuxProgramStartup.html)

