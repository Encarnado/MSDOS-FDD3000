# Code/data partition — what the descent found (2026-11-08)

`tools/z80dis.py` decodes from the bytes, seeded only with what
DISASSEMBLY_GUIDE.md names, and checks every instruction against the build
listing (same address, same bytes). All three Z80 skeletons reassemble
byte-identical.

| Image | Code bytes by descent | Disagreements with listing | Unreached listing code |
|---|---|---|---|
| BOOT.BIN | 222 / 254 | 0 | 0 |
| Z86.SYS | 7 032 / 8 737 | 0 | 18 bytes (RADVS, dead) |
| CPMZ80.BIN | 2 226 / 2 506 | 0 | 0 |

## Additions to the guide's seed list (Z86.SYS)

The guide's seeds leave about 600 bytes of handlers unreached. Missing:

- **Three more DW dispatch tables, used via `JP JTAB`:** G3BT (E853h, 8: group
  F6h TEST/NOT/NEG/MUL/IMUL/DIV/IDIV), G3WT (E929h, 8: group F7h), G5T (EAD1h, 8:
  group FFh INC/DEC/CALL/CALLF/JMP/JMPF/PUSH).
- **`LD IX,nn` targets:** IX is the dispatcher, so loading it is a code reference.
  RESTORE (D8A8h) is reached only this way: a segment override points IX at it for
  one instruction.

Proposed guide text: add G3BT, G3WT, G5T to "Seeds for code discovery", and note
that `LD IX,nn` operands are code.

## Dead code

- **RADVS (E25Dh-E26Eh, 18 bytes):** nothing refers to it, in the binary or in
  I86.ASM (its only occurrence is its own label). It is a sibling of RADVSD /
  RADVDN (string-pointer advance after a REP run) that the REP work left
  unused. Kept and labelled as dead.

## Assembler hazards met while round-tripping

- Wijnen z80asm register-lexing (`add a,B_ES&0FFh` → `add a,b`): 5 sites in
  Z86.SYS, guarded. See CONVENTIONS.md rule 3.
- Project assembler JR→JP relaxation: BOOT 2 sites; the skeletons take
  mnemonics from the bytes.
- CPMZ80's listing begins at its ORG, so the equates above it (PBDOS, PSIZE,
  NBUF…) and the Z86.SYS symbols it uses are emitted as an externals block.

## 8086 images (2026-11-08)

Partition source differs from the Z80 side: the MASM listing gives each source
line's offset and whether it is an instruction or data; the bytes come from the
binary (the listing shows words in value order). `ndisasm` decodes every
instruction slice independently, and a decode that does not consume exactly the
slice would be reported. None was, in all four images. This is a consistency check
on the listing, not an independent recursive descent (an 8086 descent tool was
not built: the listing is the author's own final-pass output, and the
byte-identical gate holds either way).

| Image | Instructions | Raw-byte fallbacks |
|---|---|---|
| IO.SYS | 63 | 0 |
| FORMAT.COM | 431 | 0 |
| CPM.COM | 127 (+ the 2 506-byte Z80 image as data) | 0 |
| EDIT.COM | 1 430 | 0 |

Assembler differences found and spelled out (CONVENTIONS): MASM's reg,reg direction
bit (`_d` macros, 203 sites; the traps arrive as data, since the author wrote them as `DB 0FH,nn`), opcode 83h imm8 forms, the `JMP` + `NOP` pad MASM
leaves after a forward short jump (kept as a real `nop`), and author labels that are
NASM reserved words.

## TERMZ80.BIN (2026-11-08, merge with João Encarnado's work)
Descent from T_TERM, FTAB (10 DW, the trap-1Ch functions), every DW of the
ESC / CSI dispatch tables ((char, DW handler) pairs: `seed_listing_dw`), and
DCHS / ECHS / CH1 - reached only by CH0's push-and-RET dispatch (LD HL,handler /
LD DE,CH1 / push / RET: the handler returns into CH1). With those, 3 243 code
bytes, every instruction of TERMZ80.lst, zero disagreements, nothing dead.
MODE.COM / TERM.COM (8086): listing-reconciled, 0 raw-byte fallbacks.
