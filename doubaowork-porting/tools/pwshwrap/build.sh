#!/bin/sh
set -e
cd "$(dirname "$0")"
x86_64-w64-mingw32-gcc -O2 -o pwshwrap.exe pwshwrap.c
echo "built pwshwrap.exe"
