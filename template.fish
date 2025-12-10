#!/usr/bin/fish
printf "origin_paramters:\n$argv\n"
set -l ARGS $(getopt -o a,b:,c::,d: -l aa,bb:,cc::,dd: -- $argv)

if test $status -ne 0
    echo "Failed to parse arguments"
    exit 1
end

printf "after_getopt_parameters:\n$ARGS\n"

eval set -- argv $ARGS

echo $argv

set -l a 0
set -l c 0

while test (count $argv) -gt 0
    switch $argv[1]
        case -a --aa
            set -l a 1
            set argv $argv[2..-1]
			echo "a=1"
        case -b --bb
            set -l b  $argv[2]
            set argv $argv[3..-1]
			echo "b=$b"
        case -d --dd
            set -l d  $argv[2]
            set argv $argv[3..-1]
			echo "d=$d"
        case -c --cc
            if test (count $argv) -ge 2 -a "$argv[2]" != "--"
                set -l c $argv[2]
                set argv $argv[3..-1]
				echo "c=$c"
            else
                set argv $argv[2..-1]
				set -l c 1
				echo "c=1"
            end
        case "--"
            set argv $argv[2..-1]
            break
        case '*'
            echo "Unknown option: $argv[1]"
            exit 1
    end
end

echo $argv

echo "$(status filename) start======================================="

echo "$(status filename) end========================================="
