# 8086 Breadboard Computer

This project may take a few years to complete, I'll be working on it every now and then whenever I have free time. The end goal is to make a video game and run it on this computer.

# Specs

CPU: Intel 8086 8MHz

FPU (math coprocessor): Intel 8087

RAM: 256KB

ROM: 256KB

Display: 240x128 graphic LCD module (UltraChip UCi6963C)

IO: 2 Sega Genesis controller inputs, Intel 8251 RS-232 UART

I plan on runnign the computer at 10MHz, since the 8086 CPU still works when overclocked to 10MHz. I still need to test if the LCD controller, Sega Genesis controller interface, and RS-232 UART also work when overclocking the system. If not, I'll probably use a clock divider circuit or maybe I'll figure out a better way of connecting them to the computer.

# Progress

So far, I have tested the CPU, FPU, RAM, and ROM in real life on a breadboard and they all work. Currently, I'm figuring out how the LCD controller works and how the 8087 FPU works. Eventually, I'll build and test the RS-232 UART and the Sega Genesis controller interface.

# Dependencies

NASM: This is the assembler that will compile the assembly code into binary executables, download from https://www.nasm.us/ 

You'll also need an EEPROM programmer to flash the binary ROM images onto the actual ROM chips.

# Compiling

Maybe one day I'll set up a C compiler for this computer, but for now, all code must be written in 16-bit x86 assembly.

To compile the assembly code, type ```nasm -o test.bin test.asm```. This will create a binary ROM image called ```test.bin```. However, this ROM image needs to be split into even and odd bytes due to how the ROM chips are connected to the CPU. To split the bytes, you can run my included Python script by typing ```python bytesplitter.py test.bin```. There will now be 2 files called ```test even bytes.bin``` and ```test odd bytes.bin```.
