# Baud rate of the breadboard computer's serial interface
BAUD_RATE = 38400

# To connect with flow control enabled:
# screen /dev/`ls /dev | grep tty.usbserial` $(BAUD_RATE) -f

gsr_memory_editor.bin: *.asm
	nasm -o gsr_memory_editor.bin gsr_start.asm
	python3 bytesplitter.py gsr_memory_editor.bin

connect:
	screen /dev/`ls /dev | grep tty.usbserial` $(BAUD_RATE) -f

clean:
	rm -f *.bin