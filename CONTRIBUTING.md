# Working on FlightControl

## Layout

```
dev/                  the real source, comments and all. Edit here.
FlightControl/        what players install. Generated. Do not edit by hand.
tools/build.sh        dev/ -> FlightControl/
tools/strip-comments.py
.scratch/             design notes and the decisions behind them
```

`dev/*.lua` is where the work happens. `FlightControl/*.lua` is built from it with the
comments removed, and is overwritten every build, so anything typed directly into those
files is lost.

`FlightControl.toc` and `logo.tga` are not generated. They live in `FlightControl/` and are
edited in place.

## Building

```sh
./tools/build.sh
```

The addon folder is symlinked into `Interface/AddOns`, so the game sees `FlightControl/`,
not `dev/`. **Run the build before testing in-game** or you will be testing the previous
version.

## Why the build verifies itself

The source has `--` inside string literals, and secure snippets inside long brackets. A
pattern-matching stripper would corrupt both, so `strip-comments.py` scans character by
character and tracks whether it is inside a short string, a long string, or a comment.

To prove it never changes meaning, the build disassembles the original and the stripped file
and requires the opcodes and constants to match. Line numbers, source names and pointers are
normalised away, since those legitimately move when comment lines disappear. Any real
difference stops the build instead of shipping.

Comparing raw bytecode does **not** work here: `luac -s` leaves `linedefined` and
`lastlinedefined` in every function prototype, so shifting a function by one line changes the
output even though the code is identical.

## Releasing

1. Make the change in `dev/`, run `./tools/build.sh`
2. Bump `## Version` in `FlightControl/FlightControl.toc`
3. Add a section to `CHANGELOG.md` with a matching heading
4. Commit, then `git tag vX.Y.Z && git push origin vX.Y.Z`

The workflow refuses to build if the tag and the TOC disagree, or if `FlightControl/` is out
of date with `dev/`. It publishes a GitHub release and uploads to Wago automatically.

Editing only `README.md` needs no release. Push it, then press **Import readme** on the Wago
project page.
