# 8086 Breadboard Computer

This is by far the craziest personal project I've ever worked on, and it will take a few years to complete, I'll be working on it every once in a while whenever I have free time.

Circuit schematics and images of the computer can be found in the schematics and images folders.

![8086 on breadboard](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/breadboard.JPG)

![Processors](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/processors.JPG)

# Specs

CPU: Intel 8086 8MHz

FPU (math coprocessor): Intel 8087 10MHz

RAM: 256KB

ROM: 256KB

IO: Intel 8251 RS-232 UART

Display (not connected yet): 240x128 graphic LCD module (UltraChip UCi6963C)

I eventually plan on running the computer overclocked at 10MHz, since the 8MHz 8086 CPU still works when overclocked to 10MHz. The UART does not work when the processors are running at 10MHz, probably because the read/write pulses become too short. I plan on fixing this at some point with a wait state generator, but for now I've been testing everything at 4.9152MHz.

# Progress

So far, the CPU, FPU, RAM, ROM, interrupt controller, and UART are all working on a breadboard. The computer is currently capable of acting like a serial terminal and can echo characters back to my laptop. All UART inputs/outputs are buffered in memory and handled asynchronously using interrupts.

![terminal](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/terminal.JPG)

This test code in ```gsrme.asm``` will eventually turn into a small operating system for the computer called GSR Memory Editor, which will be similar to WOZMON but with some extra features. Once the operating system is capable of tesing IO devices, I'll connect the LCD display and maybe even design a high speed SD card reader for the computer.

I have also discovered an issue with the UART where it sometimes returns corrupted characters, and I have absolutely no idea why! This issue occurs at all baud rates. I might do some tesing with the parity bit enabled and see if I get any parity errors.

# Dependencies

NASM: This is the assembler that will compile the assembly code into binary executables, you can download it from [here](https://www.nasm.us/).

You'll also need an EEPROM programmer to flash the binary ROM images onto the actual ROM chips. I'm using the TL866II plus EEPROM programmer and [MiniPro-GUI](https://github.com/DLXXV-Kelvin/MiniPro-GUI). Instructions for MiniPro-GUI can be found [here](https://kosciuskomedia.com/?p=717).

# Compiling and Flashing the Code

Maybe one day I'll set up a C compiler for this computer, but for now I'm writing everything in 16-bit x86 assembly.

To compile the assembly code, type ```nasm -o gsrme.bin gsrme.asm```. This will create a binary ROM image called ```gsrme.bin```. However, this ROM image needs to be split into even and odd bytes due to how the ROM chips are connected to the CPU via a 16-bit data bus. To split the bytes, you can run my included Python script by typing ```python bytesplitter.py gsrme.bin```. There will now be 2 files called ```gsrme even bytes.bin``` and ```gsrme odd bytes.bin```, which are both 256KB files with the even/odd bytes of the ROM image at the end of those files.

Alternatively, you can use my shell script that does all of this for you by typing ```sh compile.sh gsrme.asm```. I have also provided the compiled binary images of ```gsrme.asm``` that can be directly flashed onto ROM chips.

Finally, use an EEPROM programmer to flash the 2 ROM chips. Flash ```gsrme even bytes.bin``` onto the ROM chip connected to the lower data bus (DO-D7), and flash ```gsrme odd bytes.bin``` onto the ROM chip connected to the upper data bus (D8-D15).

# Hardware Testing

If the CPU was a static CMOS CPU, I would be able to connect LEDs to the pins of the CPU and connect a button with a pull-up resistor to the clock input to clock the system manually. Unfortunately, Intel used DRAM to make the CPU registers to save space on the silicon die, which need to be refreshed frequently. This means that the processors draw significantly more power than most logic chips (about 350mA EACH) and need a MINIMUM clock speed of 2MHz! This also means that I cannot see what the system is doing by just connecting LEDs directly to the CPU since they would blink 2 million times per second.

I'm using an HP 1631D logic analyzer to probe the address, data, bus control, interrupt, clock, and reset lines of the computer. I then set the logic analyzer to trigger either on the reset pulse of the CPU or an interrupt line, depending on what I'm tesing. I am also using an oscilloscope to probe the RS-232 serial lines to ensure that the computer is sending the correct characters back to my laptop. This setup allows me to see exactly what the computer is doing, and even see the state of the computer on every clock cycle of the CPU.

This image shows the computer echoing a lowercase i character (0x69) back to my laptop. The oscilloscope is showing the RS-232 input and output lines, and the logic analyzer is showing the computer reading 0x69 (the lowercase i) from IO address 0x00004 (the 8251 UART chip).

![test setup](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/logicanalyzer.JPG)