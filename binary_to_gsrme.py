# Converts a file into GSR Memory Editor commands, allowing
# compiled code or other data to easily be loaded into RAM
# on the breadboard computer through GSR Memory Editor

# For example, if test.bin was: [0x11, 0x22, 0x33, 0x44, 0x55]
# python3 binary_to_gsrme test.bin
# Would result in a new file test_gsrme.txt containing:
# 00610=2211 4433 55

# The converted commands will be using (little endian) words
# since they take up less text (and are processed slightly
# faster by GSR Memory Editor)

import sys

file_to_convert = str(sys.argv[1])
start_address = 0x00610 # The address in memory to load the data to

try:
    with open(file_to_convert, 'rb') as f:
        bytes_to_convert = f.read()
except FileNotFoundError:
    print('Could not convert ' + file_to_convert + ', file not found!')
    exit(1)

# Check if a different start address was given and attempt to parse it
if len(sys.argv) > 2:
    try:
        start_address = int(sys.argv[2], 16)
    except ValueError:
        print('Invalid start address! Example of valid start address: 0x12ABC')
        exit(1)
    if start_address > 0xFFFFF:
        print('Invalid start address! Example of valid start address: 0x12ABC')
        exit(1)
    if start_address + len(bytes_to_convert) > 0xFFFFF:
        print('File cannot fit in RAM! Try a smaller file or try a lower start address.')
        exit(1)

output_file_name = file_to_convert.split('.')[0] + '_gsrme.txt'

print('Creating ' + output_file_name)

try:
    with open(output_file_name, 'w+') as output_file:
        print('Generating commands to load ' + file_to_convert + ' to address ' + "{:05x}".format(start_address))
        
        bytes_index = 0 # Index into bytes_to_convert array

        while bytes_index < len(bytes_to_convert):
            # Start of command (address to write to)
            command_string = "{:05x}".format(start_address) + '='
            
            # Rest of command (words/bytes to write to that address)
            # Each command can be up to 255 characters long
            # A command with 50 words will be exactly 255 characters
            while len(command_string) < 255 and bytes_index < len(bytes_to_convert):
                if len(bytes_to_convert) & 1:
                    # Odd number of bytes to parse
                    if len(bytes_to_convert) - bytes_index > 1:
                        # Parse word
                        command_string += "{:02x}".format(bytes_to_convert[bytes_index + 1]) + "{:02x}".format(bytes_to_convert[bytes_index])
                        bytes_index += 2
                        # Add a space after the word
                        if len(command_string) < 255:
                            command_string += ' '
                    else:
                        # Parse byte
                        command_string += "{:02x}".format(bytes_to_convert[bytes_index])
                        bytes_index += 1
                else:
                    # Even number of bytes to parse
                    # Parse word
                    command_string += "{:02x}".format(bytes_to_convert[bytes_index + 1]) + "{:02x}".format(bytes_to_convert[bytes_index])
                    bytes_index += 2
                    # Add a space after the word
                    if len(command_string) < 255:
                        command_string += ' '
            # Write command to text file and increment start address
            output_file.write(command_string + '\n')
            start_address += 100

except FileNotFoundError:
    print('Could not create ' + output_file_name + '!')
    exit(1)
