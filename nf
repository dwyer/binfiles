#!/bin/sh
# Print the last element of a string separated by arg 1.
echo $2 | awk -F$1 '{print $NF}'
