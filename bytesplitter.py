import sys

file_to_split = str(sys.argv[1])

try:
    with open(file_to_split, 'rb') as f:
        bytes_to_split = f.read()
except FileNotFoundError:
    print('Could not split ' + file_to_split + ', file not found!')
    exit(1)

print('Splitting ' + file_to_split + '...')

num_bytes = len(bytes_to_split)
even_bytes = []
odd_bytes = []

# Fill beginning of ROM with 0s
rom_size = 262144
for i in range(int((rom_size - num_bytes) / 2)):
    even_bytes.append(0)
    odd_bytes.append(0)

# Put assembled binary at end of ROM image
counter = 0
while counter < num_bytes:
    even_bytes.append(bytes_to_split[counter])
    counter += 1
    odd_bytes.append(bytes_to_split[counter])
    counter += 1

with open(file_to_split.split('.')[0] + '_even_bytes.bin', 'wb') as f:
    f.write(bytes(even_bytes))

with open(file_to_split.split('.')[0] + '_odd_bytes.bin', 'wb') as f:
    f.write(bytes(odd_bytes))