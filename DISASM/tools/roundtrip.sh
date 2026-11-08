#!/bin/zsh
# roundtrip.sh - assemble every disassembly in asm/ and byte-compare it with
# its reference binary in bin/.  THE gate: run after every edit session;
# everything must be green (edits are comments/labels/symbolic operands
# only - the bytes never change).
#
# Usage:  tools/roundtrip.sh            (from anywhere)
#         tools/roundtrip.sh z86        (only names matching substring)
#
# Z80: Wijnen z80asm v1.8 (the dialect of the TC3256 ROMDIS/TOSDIS corpus).
#   Lexer hazards, both SILENT (see dict/CONVENTIONS.md):
#   - after call/jp/jr/ret, a label spelled <condition>_... is read as the
#     condition (NZ_ Z_ NC_ C_ PO_ PE_ P_ M_);
#   - in an 8-bit operand, a symbol spelled <reg8>_... (B_ES, H_X, R_AX)
#     is read as the register: 'add a,B_ES&0FFh' assembles 'add a,b'.
# 8086: NASM (-f bin), with the TRAP macro for the 0Fh nn BIOS trap.
#   Files not yet written are reported as TODO, not green.

set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
FILTER="${1:-}"
PASS=0; FAIL=0; TODO=0

check() {   # check <name> <asm> <ref> <tool>
  local name="$1" asm="$2" ref="$3" tool="$4"
  [[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && return
  local out="build/${name}.bin"
  if [[ ! -f "asm/$asm" ]]; then
    echo "TODO  $name  (asm/$asm not written yet)"; TODO=$((TODO+1)); return
  fi
  case "$tool" in
    z80)  z80asm -o "$out" "asm/$asm" 2>"build/${name}.err" ;;
    nasm) nasm -O0 -f bin -o "$out" "asm/$asm" 2>"build/${name}.err" ;;
  esac
  if [[ $? -ne 0 ]]; then
    echo "FAIL  $name  (assembly error, see build/${name}.err)"; FAIL=$((FAIL+1)); return
  fi
  if cmp -s "$out" "$ref"; then
    echo "PASS  $name"; PASS=$((PASS+1))
  else
    echo "FAIL  $name  (assembles but BYTES DIFFER vs $ref)"; FAIL=$((FAIL+1))
  fi
}

check boot    boot.asm    bin/BOOT.BIN    z80
check z86sys  z86sys.asm  bin/Z86.SYS     z80
check cpmz80  cpmz80.asm  bin/CPMZ80.BIN  z80
check iosys   iosys.asm   bin/IO.SYS      nasm
check format  format.asm  bin/FORMAT.COM  nasm
check cpmcom  cpmcom.asm  bin/CPM.COM     nasm
check edit    edit.asm    bin/EDIT.COM    nasm
check mode    mode.asm    bin/MODE.COM    nasm
check term    term.asm    bin/TERM.COM    nasm
check termz80 termz80.asm bin/TERMZ80.BIN z80

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL TODO=$TODO"
[[ $FAIL -eq 0 ]] || exit 1
