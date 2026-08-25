#!/usr/bin/env bash
#
# Build the shipping addon from dev/.
#
# dev/ holds the real source, comments and all. FlightControl/ holds what
# players install. Never edit FlightControl/*.lua by hand: this overwrites them.
#
# Every file is verified before it is copied. Comments cannot change behaviour,
# so both versions must disassemble to the same opcodes and constants. Line
# numbers, source names and pointers are normalised away, since those legitimately
# shift when comment lines disappear. Comparing raw bytecode does NOT work:
# luac -s leaves linedefined/lastlinedefined in every function prototype.
# If the disassembly differs at all, the stripper changed the meaning of the
# code and the build stops rather than shipping it.

disassemble() {
    luac -p -l -l "$1" 2>&1 \
        | sed -E 's/0x[0-9a-f]+/PTR/g' \
        | sed -E 's/^(\t[0-9]+)\t\[[0-9]+\]\t/\1\t/' \
        | sed -E 's/<[^>]*:[0-9]+,[0-9]+>/<>/'
}

set -euo pipefail
cd "$(dirname "$0")/.."

FILES=(FlightControl.lua FlightControlUI.lua)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/a" "$tmp/b"

for f in "${FILES[@]}"; do
    python3 tools/strip-comments.py "dev/$f" > "$tmp/$f"
    luac -p "$tmp/$f"

    disassemble "dev/$f"  > "$tmp/a/dis"
    disassemble "$tmp/$f" > "$tmp/b/dis"

    if ! cmp -s "$tmp/a/dis" "$tmp/b/dis"; then
        echo "ERROR: $f does not compile identically after stripping." >&2
        echo "The stripper has changed the meaning of the code. Not copying." >&2
        exit 1
    fi
done

for f in "${FILES[@]}"; do
    cp "$tmp/$f" "FlightControl/$f"
done

echo "built from dev/ -> FlightControl/"
for f in "${FILES[@]}"; do
    printf '  %-20s %7s -> %7s bytes\n' \
        "$f" "$(wc -c < "dev/$f")" "$(wc -c < "FlightControl/$f")"
done
