import sys

file_to_split = str(sys.argv[1])
print('Splitting', file_to_split, '...')

with open(file_to_split, 'rb') as f:
    bytes_to_split = f.read()

even_bytes = []
odd_bytes = []

num_bytes = len(bytes_to_split)
counter = 0

while counter < num_bytes:
    even_bytes.append(bytes_to_split[counter])
    counter += 1
    odd_bytes.append(bytes_to_split[counter])
    counter += 1

with open(file_to_split.split('.')[0] + ' even bytes.bin', 'wb') as f:
    f.write(bytes(even_bytes))

with open(file_to_split.split('.')[0] + ' odd bytes.bin', 'wb') as f:
    f.write(bytes(odd_bytes))