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

## What this is

42 `ft_lex` (subject v1.00). Implement POSIX `lex`: parse a `.l` file, build a DFA, emit a scanner. Implementation language is Zig. Generated scanner language is C (mandatory). `libl` is the tiny runtime you link with `-ll`.

The previous tree tried to be flex-complete plus graph dumps, color cyclers, and a pile of unused Zig. It was hard to defend and easy to lie about. This rewrite keeps one job: produce a working `lex.yy.c` that matches the subject example and does not crash on bad input.

## Pipeline

`.l` → ERE → Thompson NFA → subset DFA → C (or Zig) tables + `yylex`

| file | job |
| --- | --- |
| `src/lexfile.zig` | split definitions / rules / user code |
| `src/regex.zig` | POSIX ERE → AST |
| `src/nfa.zig` | Thompson construction |
| `src/dfa.zig` | subset construction, longest match |
| `src/compress.zig` | `-C`: char classes + unique rows |
| `src/emit.zig` | write `lex.yy.c` |
| `src/emit_zig.zig` | `-z`: write `lex.yy.zig` (real Zig, not a C wrapper) |
| `libl/libl.c` | `yywrap`, default `main`, the usual `yy*` bits |

Generated C and `libl` only use `<stdio.h>`, `<string.h>`, `malloc` / `realloc` / `calloc` / `free`. That is a subject rule, not a style choice.

## Layout

```
build.zig          zig 0.14+
Makefile           wraps zig build, copies ft_lex + libl.a to .
libl/              POSIX libl + its Makefile
examples/          scanner (PDF), keywords, longest match, start conditions, wc, bad regex
scripts/check.sh   used by `zig build test`
ft_lex.subject.pdf
```

## What works / what does not

Works: definitions, rules, user code, ERE, `|` shared actions, start conditions, `yytext` / `yyleng` / `yylex` / `yywrap`, `-t -n -v`, stdin, the PDF scanner, `-z`, `-C`.

`-C` is a bonus. Default tables stay uncompressed so the C output is easy to read. On `examples/scanner.l` the packed file is ~2.8× smaller. That is measured, not a flex-marketing number.

`-z` is the other bonus (second target language). Same `.l` input. C actions like `printf` get lowered to Zig. Do not expect every C snippet in a `.l` to translate.

Not a flex clone. Locale / unspecified POSIX cases are not a goal; the program must not crash. No Graphviz, no leftover dump tools.

## Defense notes

- Binary name is `ft_lex`. Library name is `libl`.
- `cc -o scanner lex.yy.c -Lzig-out/lib -ll` (or `-L. -ll` after `make`).
- User `main` in the `.l` wins over libl's weak `main`.
- Bad regex should print a file:line message and exit, not segfault.
