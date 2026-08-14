#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

FT_LEX="${FT_LEX:-$ROOT/zig-out/bin/ft_lex}"
LIBDIR="${LIBDIR:-$ROOT/zig-out/lib}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_case() {
    name=$1
    lfile=$2
    infile=$3
    expected=$4

    rm -f lex.yy.c
    "$FT_LEX" "$lfile" || fail "$name: ft_lex failed"
    test -f lex.yy.c || fail "$name: lex.yy.c not written"
    cc -std=c99 -o "$TMP/$name" lex.yy.c -L"$LIBDIR" -ll || fail "$name: cc failed"
    got=$("$TMP/$name" < "$infile")
    if [ "$got" != "$expected" ]; then
        echo "expected:" >&2
        printf '%s\n' "$expected" >&2
        echo "got:" >&2
        printf '%s\n' "$got" >&2
        fail "$name: output mismatch"
    fi
    echo "ok $name"
}

SUBJECT=$(printf '%s\n' \
    'NUMBER: 42' \
    'OPERATOR: +' \
    'NUMBER: 1337' \
    'OPERATOR: +' \
    'OPEN PARENTHESIS' \
    'NUMBER: 21' \
    'OPERATOR: *' \
    'NUMBER: 19' \
    'CLOSED PARENTHESIS' \
    'NEWLINE')

run_case scanner examples/scanner.l examples/scanner.in "$SUBJECT"

KEYWORDS=$(printf '%s\n' \
    'KW if' \
    'ID x' \
    'KW then' \
    'NUM 42' \
    'KW else' \
    'ID y')

run_case keywords examples/keywords.l examples/keywords.in "$KEYWORDS"

LONGEST=$(printf '%s\n' \
    'IF' \
    'ID iffy')

run_case longest examples/longest.l examples/longest.in "$LONGEST"

START=$(printf '%s\n' \
    'WORD hello' \
    'WORD world')

run_case start examples/start.l examples/start.in "$START"

# error on bad regex
rm -f lex.yy.c
set +e
err=$("$FT_LEX" examples/bad_regex.l 2>&1)
status=$?
set -e
[ "$status" -ne 0 ] || fail "bad_regex: expected non-zero exit"
printf '%s\n' "$err" | grep -q "bad_regex.l:2 unexpected token ')'" \
    || fail "bad_regex: message was: $err"
echo "ok bad_regex"

# -t writes to stdout
rm -f lex.yy.c
"$FT_LEX" -t examples/scanner.l > "$TMP/out.c"
test ! -f lex.yy.c || fail "-t: lex.yy.c should not be created"
grep -q "int yylex" "$TMP/out.c" || fail "-t: missing yylex"
echo "ok dash_t"

WC=$(printf '%s\n' '2 3 16')
run_case wc examples/wc.l examples/wc.in "$WC"

echo "all checks passed"
