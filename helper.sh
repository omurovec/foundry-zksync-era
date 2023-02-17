#!/usr/bin/env sh
$1 --bin $2 | awk -F': ' '/bytecode: /{print $2}'
