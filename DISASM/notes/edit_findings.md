# EDIT.COM — findings (2026-11-08)

Gate: PASS (`tools/roundtrip.sh edit`, NASM -O0, byte-identical, 4 653 bytes).
Every one of the 310 labels assembles at the address that EDIT.LST gives its
author name (checked by script). 137 numbered or cryptic locals were renamed
(the `$ST1`/`$DR0` escapes are gone). Numeric operands are now written as the
author's expressions (`BUFFERS+STKOFF`, `FCB+18`, `DIRTY-1`, `OBSZ-128`,
`MSGC+6`...) plus new equates for PSP/FCB fields, INT 21h functions, BIOS
functions and VT52 codes (dict/edit.md). Comment coverage is about 97% of
instruction lines.

Evidence tags: *verified* = code and source (or MSDOS.LST / z86sys.asm /
test_edit.py) agree. *code reading* = follows from the bytes, not exercised
by test_edit.py. Hardware: notes/hardware_run.md (2026-11-07, real FDD3000 +
TT3000 by recollection; "EDIT worked"). The `HW-PENDING` tags written before
that report are resolved below.

## Design (confirmed)

1. **Gap buffer invariants.** BUFS <= GAPS <= GAPE <= TEND; text =
   BUFS..GAPS-1 + GAPE..TEND-1; TEND = end of our memory (min(FFF0h,
   (PSP[2]-CS)*16)), fixed; GAPS = GAPE is "Memory full". LF only inside;
   CR LF + ^Z on disk. LSOF scans backward only below GAPS. TOP and CLS_ are
   line starts before the gap; CROW = LINE - TOPLN. A move backward past the
   top line leaves TOP pointing into the gap until FIXSCR repairs it, which
   always runs before DRAW. *verified (code + EDIT.ASM + test_edit.py, which
   rebuilds the text from these words after every step).*
2. **Row marks instead of a screen copy.** DIRTY[r] = FFh clean, else the first
   screen column to resend (0 = whole row); marks only move left (MARKC uses
   CF from an unsigned compare). DELB cannot know its row in advance, so it
   sets MARKF and FIXSCR marks after recomputing CCOL/CROW. *verified.*
3. **DRAW examines only what it must.** Two REPE SCASB find the first and last
   mark. Rows are walked from TOP only when the first mark is above the
   cursor's row, otherwise from the cursor's own line (known: CLS_ and the
   gap), down to the last mark. The README's "only the rows from the first
   mark to the last are even looked at" is a slight simplification: when the
   first mark is above the cursor, rows 0..first-1 are still walked (NEXTLF per
   line), only not sent; when it is below, the walk starts at the cursor row.
   *verified (code).*
4. **Drawing yields to the keyboard.** KEYRDY (INT 16h AH=1) before every marked
   row; on a key DRAW returns CF=1, MAIN skips STATUS and PLACE, FULL stays
   set, the remaining marks finish later. MAIN also skips DRAW entirely when a
   key is already waiting. *verified.*
5. **Terminal scrolling for one-line moves.** SCRUP = ESC Y (bottom row) + LF;
   SCRDN = ESC Y 0 0 + ESC I. The whole screen moves, status line included, so
   DIRTY is shifted with the rows, the incoming row is marked whole and STFULL
   forces the status line. No scroll while FULL (a full redraw is pending).
   test_edit.py demands exactly one terminal scroll per one-line move.
   *verified; worked on real hardware (hardware_run.md) - was HW-PENDING,
   resolved.*
6. **Status line by shadow fields.** SHMOD/SHLINE/SHCOL/SHMSG hold what the
   terminal shows; only differing fields are sent. PROMPT sets SHMSG = 1 (a
   value no message pointer has) to force the message area to be rewritten.
   The `*` column (MODC) is measured: OPTR - (OBUF+6) - STCUT, i.e. the bytes
   queued since ESC Y r c ESC L. *verified.*
7. **Never the last column.** W = COLS-1; ROWOUT expands only to LEFT+W; PLACE
   clamps to W-1; the longest message ends at column 62 of 64. *verified
   (test_edit.py checks no character in the last column after every step);
   worked on a real TT3000 - was HW-PENDING, resolved.*
8. **VT52 / Terminal 3000 codes** ESC Y row+32 col+32, ESC H ESC J, ESC K,
   ESC L / ESC M inverse, ESC I: named VT_* equates. *verified against
   OVERVIEW 2.7 and the test's terminal model; confirmed on a real
   Terminal-3000-family terminal (hardware_run.md) - was HW-PENDING,
   resolved.*
9. **No traps in EDIT.** INT 10h -> IO.SYS stub TRAP 10h (TRAP_INT10) ->
   T_I10 in z86sys.asm; INT 16h -> TRAP 16h (TRAP_INT16) -> T_I16. FLUSH sets
   AH=0Eh once for the whole buffer, relying on T_I10 not writing AX back for
   function 0Eh (true: it jumps to CONOUT). BH is never set: harmless here, on
   a PC BH is the video page. *verified (z86sys.asm).*
10. **INT 24h hook.** CRIT sets ERRF and chains `JMP FAR CS:[OLD24]`; AFTDOS
    redraws after a save if it ran. OLD24 is read from 0000:0090h because DOS
    1.25 has no AH=35h (MAXCOM = 2Eh in MSDOS.LST). DOS restores INT 24h on
    exit: INT 20h -> QUIT -> function 0 = ABORT, which copies PSP 0Ah-15h back
    to vectors 22h-24h (MSDOS.LST). The hook is installed after LOADF, so a
    load error is not flagged (none is needed: REDRAW follows). *verified.*
11. **LOADF in one DOS call:** record size 1, random block read of the whole
    file into the text room, ^Z search in the last 128 bytes, then in-place CR
    removal, then GAPMV(BUFS) moves the text to the top. *verified.*
12. **SAVE order** delete name.$$$, make, write (WBUF 2 KB blocks, random block
    write, record size 1), ^Z, close; disk full -> delete name.$$$, old file
    untouched; else delete name.BAK, rename name.ext -> .BAK, name.$$$ ->
    name.ext. *verified (test_edit.py: .BAK, new file, full disk,
    write-protect + Retry).*

## Edges and bugs (code reading; not covered by test_edit.py)

13. **Every CR is dropped on load**, not only CR before LF (LOADF_CR_LOOP
    copies the runs between any CRs). A file with bare CRs loses them; on save
    they do not come back. The source comment "drop the CRs" is accurate, the
    README's "CRs are dropped" too; the consequence is not stated. *code reading.*
14. **Arrow keys at a prompt insert a letter.** At ^K/^Q (PREFIX) and at the
    abandon question, ESC folds to '[' (no match, prefix dropped) and the
    following 'A'-'D' is read by MAIN and inserted into the text. At "Find:"
    (PROMPT) ESC gives up and the letter is likewise inserted. *code reading;
    depends on the terminal sending ESC A..D as ESCK assumes.*
15. **^Y answers Y** at "Abandon changes (Y/N)?" (PREFIX adds 40h to control
    codes), as do y and Y; ^KD = ^KX. *code reading.*
16. **Abort at DOS's question during a save ends EDIT** (DOS's ABORT
    terminates the program) with name.$$$ left on the disk and the edits lost;
    Ignore lets DOS carry on as if the sector were written, and EDIT then says
    "Saved". Only Retry was tested. *code reading (MSDOS.LST HARDERR/ABORT);
    the Ignore outcome is provisional.*
17. **Unchecked results:** CLOSE and both RENAMEs are not checked, so a failure
    there still shows "Saved" and clears MODIF. Only block writes set DFULL.
    *code reading.*
18. **OPTS multiplies with an 8-bit MUL**, so the total is taken mod 256 before
    each step: "/2624" is accepted as 64. Harmless. NR is never changed (24-line
    terminal assumed); COLS is stored and never read. *code reading.*
19. **No room check against TEND < BUFS.** If DOS gave less memory than
    BUFFERS+TXOFF (243Dh = 9.3 KB), TEND - BUFS wraps and any file "fits".
    Impossible with DOS 1.25's 52 KB on this machine. *code reading.*
20. **Cursor beyond column 1023** (LMAX): LEFT stops at LMAX-W, the cursor is
    off the window and PLACE parks the terminal cursor on column W-1. Lines
    are never cut. *code reading.*
21. **Search skips the byte at the cursor** (starts at GAPE+1, by design for
    ^L), does not wrap, and searches only after the gap. With no previous
    string, ^L and an empty ^QF do nothing silently. *verified (code; ^L and
    empty ^QF repeat tested).*

## Oddities

22. **Two dead NOPs** after `JMP SHORT PUTC` in INVON and INVOFF: the source
    writes `JMP PUTC`, a forward reference, for which MASM 1.10 reserved 3
    bytes, then emitted EB xx + 90. *verified (EDIT.LST).*
23. **SP starts odd** (BUFFERS = 132Dh, SP = BUFFERS+STKOFF = 243Dh): every
    stack word is misaligned. Costs bus cycles on a real 8086, nothing on the
    interpreter. *verified (bytes).*
24. **Source comment:** "the test (test_fdd86.py) finds these by the signature"
    - it is test_edit.py (`Ed.vars()`), which imports test_fdd86. *verified.*
25. **Source comment on LD2:** "a scan costs 300 T a byte" predates the
    interpreter's CPIR-based REPNE SCASB (README: loading BIG.TXT fell from
    5.5 s to 3.3 s). Kept and annotated. *verified (README).*

## Timings

All timings in the volume (0.03-0.07 s a key, ~1 s a page, 3 900 T per
character through INT 10h) are emulator figures at an assumed 4 MHz
(project README / test_edit.py). hardware_run.md has no timings ("slow but
bearable"); they stay emulator figures.

## Cross-volume

- INT 10h / INT 16h wording follows iosys.asm's TRAP_INT10 / TRAP_INT16 and
  z86sys.asm's T_I10 / T_I16. No conflict found.
- OVERVIEW 2.7 / README say "only rows between first and last mark are
  looked at": see item 3 for the precise rule.
