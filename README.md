# ft_lex

POSIX.1-2024 `lex` in Zig. Reads a `.l` file and writes `lex.yy.c` containing a compiled DFA.

## Build

Requires [Zig](https://ziglang.org/download/) 0.14 or later, plus a C compiler for generated scanners.

```sh
zig build
# or: make
```

`zig build` installs `zig-out/bin/ft_lex` and `zig-out/lib/libl.a`. `make` also copies them to the project root so `cc ... -L. -ll` works.

## Subject example

```sh
./zig-out/bin/ft_lex examples/scanner.l
cc -o scanner lex.yy.c -Lzig-out/lib -ll
echo "42+1337+(21*19)" | ./scanner
```

Expected output:

```
NUMBER: 42
OPERATOR: +
NUMBER: 1337
OPERATOR: +
OPEN PARENTHESIS
NUMBER: 21
OPERATOR: *
NUMBER: 19
CLOSED PARENTHESIS
NEWLINE
```

## Options

```
ft_lex [-t] [-n|-v] [-z] [-C] [file...]
```

- `-t` write the scanner to stdout instead of `lex.yy.c` / `lex.yy.zig`
- `-n` do not print statistics
- `-v` print NFA/DFA statistics (stderr)
- `-z` emit a Zig scanner (`lex.yy.zig`), not C
- `-C` pack DFA tables (equivalence classes + unique rows). Default is uncompressed.
- no file, or `-`, reads stdin; several files are concatenated

```sh
./zig-out/bin/ft_lex -z examples/scanner.l
zig run lex.yy.zig < examples/scanner.in
```

On `examples/scanner.l`, `-t` is 26961 bytes and `-tC` is 9459 bytes (~2.8×).

## Tests

```sh
zig build test
```
