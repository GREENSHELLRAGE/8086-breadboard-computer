# 8086 Breadboard Computer

This is by far the craziest personal project I've ever worked on, and it may take a few years to complete, I'll be working on it every once in a while whenever I have free time. The end goal is to make a video game and run it on this computer.

Circuit schematics and images of the computer can be found in the schematics folder.

![8086 on breadboard](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/schematics/breadboard.JPG)

# Specs

CPU: Intel 8086 8MHz

FPU (math coprocessor): Intel 8087 10MHz

RAM: 256KB

ROM: 256KB

Display: 240x128 graphic LCD module (UltraChip UCi6963C)

IO: 2 Sega Genesis controller inputs, Intel 8251 RS-232 UART

I plan on running the computer at 10MHz, since the 8MHz 8086 CPU still works when overclocked to 10MHz. I still need to test if the LCD controller, Sega Genesis controller interface, and RS-232 UART also work when overclocking the system. If not, I'll probably use a clock divider circuit or maybe I'll figure out a better way of connecting them to the computer.

# Progress

So far, I have tested the CPU, FPU, RAM, and ROM in real life on a breadboard and they all work. Currently, I'm figuring out how the LCD controller works and how the 8087 FPU works. Eventually, I'll build and test the RS-232 UART and the Sega Genesis controller interface.

# Dependencies

NASM: This is the assembler that will compile the assembly code into binary executables, you can download it from [here](https://www.nasm.us/).

You'll also need an EEPROM programmer to flash the binary ROM images onto the actual ROM chips.

# Compiling and Flashing the Code

Maybe one day I'll set up a C compiler for this computer, but for now, all code must be written in 16-bit x86 assembly.

To compile the assembly code, type ```nasm -o test.bin test.asm```. This will create a binary ROM image called ```test.bin```. However, this ROM image needs to be split into even and odd bytes due to how the ROM chips are connected to the CPU via a 16-bit data bus. To split the bytes, you can run my included Python script by typing ```python bytesplitter.py test.bin```. There will now be 2 files called ```test even bytes.bin``` and ```test odd bytes.bin```.

Alternatively, you can use my shell script that does all of this for you by typing ```sh compile.sh test.asm```.

Finally, use an EEPROM programmer to flash the 2 ROM chips. Flash ```test even bytes.bin``` onto the ROM chip connected to the lower data bus (DO-D7), and flash ```test odd bytes.bin``` onto the ROM chip connected to the upper data bus (D8-D15). I'll add more detailed instructions on how to use the EEPROM programmer when I resume working on this project.

# Hardware Testing

If the CPU was a static CMOS CPU, I would be able to connect LEDs to the pins of the CPU and connect a button with a pull-up resistor to the clock input to clock the system manually. Unfortunately, Intel used DRAM to make the CPU registers to save space on the silicon die, which need to be refreshed frequently. This means that it draws significantly more power than most logic chips (about 1W) and needs a clock speed of 2MHz MINIMUM!

Unfortunately I can't push a button 2 million times per second, so I built a clock generator circuit using a 10MHz crystal oscillator and a couple of 74HC04 CMOS inverter gates (this circuit can be found in the schematics). I then connected the output of the clock generator circuit to a 74HC390 decade counter chip to give me 2MHz, 5MHz, and 10MHz clock signals so I could test the system at different clock speeds. I'm using an HP 1631D logic analyzer to probe the address, data, bus control, clock, and reset lines of the computer. I then set the logic analyzer to trigger on the reset pulse so it starts recording as soon as the computer powers on. This setup allows me to see the state of the address, data, and bus control lines of the computer on every clock cycle of the CPU.

The included image of the logic analyzer shows the Intel 8087 writing its hardwired value of pi (0x400921FB54442D18) into memory address 0x01000, and apparently it's writing this value backwards.

![HP1631D trace](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/schematics/logicanalyzer.JPG)
