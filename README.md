# 8086 Breadboard Computer

This is by far the craziest personal project I've ever worked on, and I'll be working on it every once in a while whenever I have free time.

Circuit schematics and images of the computer can be found in the schematics and images folders.

![8086 on breadboard](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/breadboard.JPG)

![Processors](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/processors.JPG)

# Specs

CPU: Intel 8086 with Intel 8087 math coprocessor, both running at 10MHz

RAM: 256KB (expandable to 768KB)

ROM: 256KB

IO:
- Intel 8259 Interrupt Controller
- Intel 8251 UART
- Custom high speed SD card interface (made from 74 series logic)
- 240x128 graphic LCD module (UltraChip UCi6963C) NOT CONNECTED YET

It's actually a miracle this computer even works at all since almost everything is running above its rated speed!

# Progress

My custom operating system is currently capable of reading and writing to memory and IO devices, and is also capable of executing code in memory. It has built-in documentation and absolutely no restrictions on how badly you can corrupt memory and mess up IO devices!

![terminal](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/terminal.jpg)

Here are some example commands you can enter:

- Set UART to 9600 baud (happens immediately upon pressing enter)
```0003i=00 00 00 40 4f 37```
- Set UART to 38400 baud (happens immediately upon pressing enter)
```0003i=00 00 00 40 4e 37```
- Load/execute a program that resets the computer (see image below for program result)
```00610=ea 00 00 ff ff```
```00610!```
Here's what happens when that program is executed:
![resetprogram](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/resetprogram.jpg)

The SD card interface hardware is complete, and I have sucessfully gotten an 8GB microSD card to respond to CMD0 (seen in the oscilloscope waveform below). I am still working on the code to fully initialize the SD card and read blocks of data.

![sdcardonboard](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/sdcardonboard.jpg)
![sdcardresponse](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/sdcardresponse.jpg)

Once I can read files from the SD card, I'll connect the LCD
display and see how quickly I can stream video data from
the card (Bad Apple at 240x128 at 60fps should theoretically be possible unless I encounter some major issue with the display).

# Dependencies

NASM: This is the assembler that will compile the assembly code into binary executables, you can download it from [here](https://www.nasm.us/).

You'll also need an EEPROM programmer to flash the binary ROM images onto the actual ROM chips. I'm using the TL866II plus EEPROM programmer and [MiniPro-GUI](https://github.com/DLXXV-Kelvin/MiniPro-GUI). Instructions for MiniPro-GUI can be found [here](https://kosciuskomedia.com/?p=717).

# Compiling and Flashing the Code

Maybe one day I'll set up a C compiler for this computer, but for now I'm writing everything in 16-bit x86 assembly.

To compile the code, run ```make```. The makefile will compile the code and then run a python script which splits the odd/even bytes. There should be 2 files called ```gsr_memory_editor_even_bytes.bin``` and ```gsr_memory_editor_odd_bytes.bin```, which are both 256KB files which can be flashed directly onto the ROM chips.

Finally, use an EEPROM programmer to flash the 2 ROM chips. Flash ```gsr_memory_editor_even_bytes.bin``` onto the ROM chip connected to the lower data bus (DO-D7), and flash ```gsr_memory_editor_odd_bytes.bin``` onto the ROM chip connected to the upper data bus (D8-D15).

# Hardware Testing

If the CPU was a static CMOS CPU, I would be able to connect LEDs to the pins of the CPU and connect a button with a pull-up resistor to the clock input to clock the system manually. Unfortunately, Intel used DRAM to make the CPU registers to save space on the silicon die, which need to be refreshed frequently. This means that the processors draw significantly more power than most logic chips (about 350mA EACH) and need a MINIMUM clock speed of 2MHz! This also means that I cannot see what the system is doing by just connecting LEDs directly to the CPU since they would blink 2 million times per second.

I'm using an HP 1631D logic analyzer to probe the address, data, bus control, interrupt, clock, and reset lines of the computer. I then set the logic analyzer to trigger either on the reset pulse of the CPU or an interrupt line, depending on what I'm tesing. I am also using an oscilloscope to probe the RS-232 serial lines to ensure that the computer is sending the correct characters back to my laptop. This setup allows me to see exactly what the computer is doing, and even see the state of the computer on every clock cycle of the CPU.

This image shows the computer echoing a lowercase i character (0x69) back to my laptop. The oscilloscope is showing the RS-232 input and output lines, and the logic analyzer is showing the computer reading 0x69 (the lowercase i) from IO address 0x00004 (the 8251 UART chip).

EDIT: I've given the UART a different address since taking this image, it's now at address 0x00001 and 0x00003

![test setup](https://raw.githubusercontent.com/GREENSHELLRAGE/8086-breadboard-computer/main/images/logicanalyzer.JPG)