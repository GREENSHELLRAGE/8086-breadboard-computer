nasm -o ${1%.*}.bin $1
python3 bytesplitter.py ${1%.*}.bin