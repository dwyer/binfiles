#!/bin/sh
# delete file
while [ $# -ne 0 ]; do
    filename="$1"
    filepath="$PWD/$filename"
    filehash=$(echo "$filepath" | md5)
    mv "$filename" "$HOME/.deleted/$filehash"
    shift
done
