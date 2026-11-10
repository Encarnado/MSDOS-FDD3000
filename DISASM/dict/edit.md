# EDIT.COM dictionary (volume 7/7)

Names added or changed by the disassembly of EDIT.COM (`asm/edit.asm`).
Author names (from `symbols/x86/EDIT.COM.sym` / `EDIT.LST`) are kept and
not listed, except where the narration adds a fact.  Addresses are offsets
in the .COM segment (CS = PSP).  Format: dict/CONVENTIONS.md.

All renames were checked mechanically: each new label assembles at the
address the MASM listing gives its old name (310 labels, 0 mismatches),
and the image is byte-identical (tools/roundtrip.sh edit).

## Renamed locals


### START_DRIVE_LETTER — local of START
- class: code label
- addresses: edit 0542
- aliases: DRV1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: 1 -> 'A' for the status line

### START_SET_TEND — local of START
- class: code label
- addresses: edit 055C
- aliases: MEM1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the end of the text's room (never moves)

### MAIN_KEY — local of MAIN
- class: code label
- addresses: edit 059D
- aliases: MAIN1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: send what is queued

### DOKEY_NOT_DEL — local of DOKEY
- class: code label
- addresses: edit 05BA
- aliases: DK1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: printable (or above 7Fh): insert it

### DOKEY_CONTROL — local of DOKEY
- class: code label
- addresses: edit 05C1
- aliases: DK2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: BX = code * 2: CTAB's word

### ESCK_NOT_UP — local of ESCK
- class: code label
- addresses: edit 05D6
- aliases: EK1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ESC B: down

### ESCK_NOT_DOWN — local of ESCK
- class: code label
- addresses: edit 05DD
- aliases: EK2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ESC C: right

### ESCK_NOT_RIGHT — local of ESCK
- class: code label
- addresses: edit 05E4
- aliases: EK3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ESC D: left

### KPRE_NOT_S — local of KPRE
- class: code label
- addresses: edit 05F8
- aliases: KP1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ^KX ...

### QPRE_NOT_S — local of QPRE
- class: code label
- addresses: edit 0632
- aliases: QP1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ^QD: line end

### QPRE_NOT_D — local of QPRE
- class: code label
- addresses: edit 0639
- aliases: QP2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ^QR: file start

### QPRE_NOT_R — local of QPRE
- class: code label
- addresses: edit 0640
- aliases: QP3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ^QC: file end

### QPRE_NOT_C — local of QPRE
- class: code label
- addresses: edit 0647
- aliases: QP4 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ^QF: find

### QPRE_NOT_F — local of QPRE
- class: code label
- addresses: edit 064E
- aliases: QP5 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ^QY: delete to the end of the line

### QPRE_NONE — local of QPRE
- class: code label
- addresses: edit 0655
- aliases: QP6 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: unknown: dropped

### UPPER_X — local of UPPER
- class: code label
- addresses: edit 0679
- aliases: UPX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: AL = the folded key

### OPTS_DIGIT — local of OPTS
- class: code label
- addresses: edit 068F
- aliases: OP1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: next character, as a digit

### OPTS_RANGE — local of OPTS
- class: code label
- addresses: edit 06A4
- aliases: OP2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: 64 ...

### OPTS_X — local of OPTS
- class: code label
- addresses: edit 06B7
- aliases: OPX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (COLS / W changed or not)

### LOADF_OPENED — local of LOADF
- class: code label
- addresses: edit 06D9
- aliases: LD1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: AX = room for text

### LOADF_READ — local of TOOBIG
- class: code label
- addresses: edit 06F5
- aliases: LD2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: an empty file: nothing to read

### LOADF_SCAN_Z — local of TOOBIG
- class: code label
- addresses: edit 0733
- aliases: LD2A (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the first ^Z there ends the text

### LOADF_DROP_CR — local of TOOBIG
- class: code label
- addresses: edit 073C
- aliases: LD3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: drop the CRs: copy what is between them

### LOADF_CR_LOOP — local of TOOBIG
- class: code label
- addresses: edit 0746
- aliases: LD4 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: all scanned: done

### LOADF_PART — local of TOOBIG
- class: code label
- addresses: edit 0755
- aliases: LD5 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ... minus its start = bytes to keep

### LOADF_CR_DONE — local of TOOBIG
- class: code label
- addresses: edit 0763
- aliases: LD6 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the text is BUFS..BX-1, the gap after it

### LOADF_X — local of TOOBIG
- class: code label
- addresses: edit 076D
- aliases: LDX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the text in place, or none

### SAVE_MADE — local of SAVE
- class: code label
- addresses: edit 07B3
- aliases: SV1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: record size 1: blocks of bytes

### SAVE_RENAME — local of SAVE
- class: code label
- addresses: edit 07FF
- aliases: SV2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: name.BAK: delete, then name.ext -> name.BAK

### AFTDOS_X — local of AFTDOS
- class: code label
- addresses: edit 0880
- aliases: AFX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ERRF stays 1 (cleared by the next SAVE)

### WTEXT_COPY — local of WTEXT
- class: code label
- addresses: edit 089F
- aliases: WT1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: bytes before the LF

### WTEXT_NEXT — local of WTEXT
- class: code label
- addresses: edit 08B6
- aliases: WT2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the rest

### WTEXT_X — local of WTEXT
- class: code label
- addresses: edit 08B9
- aliases: WTX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (the LF is not copied as such); also WCOPY's, WBYTE's, WFLUSH's

### WCOPY_FITS — local of WCOPY
- class: code label
- addresses: edit 08D1
- aliases: WC1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: DX = what will be left over

### WCOPY_MORE — local of WCOPY
- class: code label
- addresses: edit 08E4
- aliases: WC2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the rest, if any

### GAPMV_X — local of GAPMV
- class: code label
- addresses: edit 0947
- aliases: GMX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (the gap keeps its size)

### GAPMV_FORWARD — local of GAPMV
- class: code label
- addresses: edit 0948
- aliases: GM2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: forward: CX = AX - GAPE bytes

### MOVETO_FORWARD — local of MOVETO
- class: code label
- addresses: edit 097A
- aliases: MT1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: forward: the LFs in GAPE..AX-1

### MOVETO_GO — local of MOVETO
- class: code label
- addresses: edit 0989
- aliases: MT2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: AX = the target again

### CNTLF_LOOP — local of CNTLF
- class: code label
- addresses: edit 0990
- aliases: CN1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: bytes left?

### CNTLF_X — local of CNTLF
- class: code label
- addresses: edit 0999
- aliases: CNX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: DX = the count

### LSOF_FIRST — local of LSOF
- class: code label
- addresses: edit 09B1
- aliases: LS1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: no LF below: the text's first line

### LSOF_X — local of LSOF
- class: code label
- addresses: edit 09B4
- aliases: LSX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: AX = line start

### NEXTLF_NONE — local of NEXTLF
- class: code label
- addresses: edit 09C4
- aliases: NLN (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the end of the range

### WALK_TABS — local of WALK
- class: code label
- addresses: edit 09D2
- aliases: WK1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: column 0 or an empty line: the start

### WALK_X — local of WALK
- class: code label
- addresses: edit 09E0
- aliases: WKX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: SI = the byte at column DX

### WALK_SLOW — local of WALK
- class: code label
- addresses: edit 09E1
- aliases: WK2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: CX = column of the byte at SI

### WALK_LOOP — local of WALK
- class: code label
- addresses: edit 09E3
- aliases: WK3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: at the line end: stop

### WALK_ONE — local of WALK
- class: code label
- addresses: edit 09F2
- aliases: WK4 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the column after this byte

### ISWD_X — local of ISWD
- class: code label
- addresses: edit 0A12
- aliases: IWX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: CF=1 word, CF=0 not

### ISWD_NO — local of ISWD
- class: code label
- addresses: edit 0A13
- aliases: IWN (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: not a word byte

### MOVE_X — local of RIGHT
- class: code label
- addresses: edit 0A2F
- aliases: MVX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (no change)

### UP_NONE — local of UP
- class: code label
- addresses: edit 0A5B
- aliases: UPN (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: CF=1: no line above

### DOWN_X — local of DOWN
- class: code label
- addresses: edit 0A86
- aliases: DNX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: CF=1 with no line below

### PGDN_LOOP — local of PGDN
- class: code label
- addresses: edit 0A8C
- aliases: PD1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (DOWN corrupts CX)

### PGUP_LOOP — local of PGUP
- class: code label
- addresses: edit 0A9C
- aliases: PU1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (UP corrupts CX)

### WORDR_IN_WORD — local of WORDR
- class: code label
- addresses: edit 0AB6
- aliases: WR1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the end of the text stops it

### WORDR_GAP — local of WORDR
- class: code label
- addresses: edit 0AC3
- aliases: WR2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the end stops it

### WORDR_GO — local of WORDR
- class: code label
- addresses: edit 0AD0
- aliases: WR3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the new cursor

### WORDL_GAP — local of WORDL
- class: code label
- addresses: edit 0AD9
- aliases: WL1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the start of the text stops it

### WORDL_IN_WORD — local of WORDL
- class: code label
- addresses: edit 0AEA
- aliases: WL2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the start stops it

### WORDL_GO — local of WORDL
- class: code label
- addresses: edit 0AFB
- aliases: WL3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the new cursor

### INSCH_X — local of INSCH
- class: code label
- addresses: edit 0B53
- aliases: INX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (the screen catches up in MAIN)

### DELB_X — local of DELB
- class: code label
- addresses: edit 0BA4
- aliases: DBX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (FIXSCR marks the joined row)

### DEL_X — local of DELF
- class: code label
- addresses: edit 0BC7
- aliases: DFX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (shared exit); DELEOL's, DELLN's, DELWD's too

### DELLN_CUT — local of DELLN
- class: code label
- addresses: edit 0BFC
- aliases: DL1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: an empty last line: nothing

### DELWD_WORD — local of DELWD
- class: code label
- addresses: edit 0C22
- aliases: DW0 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: a word byte: the whole word

### DELWD_WORD_LOOP — local of DELWD
- class: code label
- addresses: edit 0C27
- aliases: DW1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the end stops it

### DELWD_BLANKS — local of DELWD
- class: code label
- addresses: edit 0C34
- aliases: DW2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the end stops it

### DELWD_CUT — local of DELWD
- class: code label
- addresses: edit 0C44
- aliases: DW3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (MARKC corrupts AX, BX only)

### FIND_TYPED — local of FIND
- class: code label
- addresses: edit 0C59
- aliases: FI0 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: CX = characters typed

### FIND_COPY — local of FIND
- class: code label
- addresses: edit 0C69
- aliases: FI1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: a typed character

### FIND_CASE — local of FNEXT
- class: code label
- addresses: edit 0C95
- aliases: FN0 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (= FC1 if not a letter: both scans agree)

### FIND_TRY — local of FNEXT
- class: code label
- addresses: edit 0CA8
- aliases: FN1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: AX = the nearer candidate

### FIND_NEAR — local of FNEXT
- class: code label
- addresses: edit 0CB4
- aliases: FN2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: neither case occurs again: not found

### FIND_RENEW_LOWER — local of FNEXT
- class: code label
- addresses: edit 0CD4
- aliases: FN3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ... (both, for a non-letter)

### FIND_X — local of NOTF
- class: code label
- addresses: edit 0CEE
- aliases: FX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (MSG shows on the next STATUS)

### SCANF_NONE — local of SCANF
- class: code label
- addresses: edit 0CFF
- aliases: SFN (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: none

### MATCH_LOOP — local of MATCH
- class: code label
- addresses: edit 0D10
- aliases: MA1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the text's byte

### MATCH_X — local of MATCH
- class: code label
- addresses: edit 0D1D
- aliases: MAX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ZF=1 match, ZF=0 not

### PROMPT_KEY — local of PROMPT
- class: code label
- addresses: edit 0D3A
- aliases: PR1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the echo so far

### MARK_X — local of MARKC
- class: code label
- addresses: edit 0D9E
- aliases: MCX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (DIRTY[CROW] = min(old, column))

### MARKR_FROM — local of MARKR
- class: code label
- addresses: edit 0DA9
- aliases: MR1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: CX = rows from AX to the bottom

### FIXSCR_COUNT — local of FIXSCR
- class: code label
- addresses: edit 0DF2
- aliases: FS2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: a byte

### FIXSCR_ONE — local of FIXSCR
- class: code label
- addresses: edit 0DFB
- aliases: FS2A (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: one column (the tab's last)

### FIXSCR_SETCOL — local of FIXSCR
- class: code label
- addresses: edit 0E00
- aliases: FS3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the cursor's column

### FIXSCR_ROWS — local of FIXSCR
- class: code label
- addresses: edit 0E0F
- aliases: FS4 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the row

### FIXSCR_BOTTOM — local of FIXSCR
- class: code label
- addresses: edit 0E3E
- aliases: FS5 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the cursor on the bottom row

### FIXSCR_ABOVE — local of FIXSCR
- class: code label
- addresses: edit 0E44
- aliases: FSUP (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: exactly one above?

### FIXSCR_TOPROW — local of FIXSCR
- class: code label
- addresses: edit 0E5D
- aliases: FS6 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the cursor on row 0

### FIXSCR_CENTRE — local of FIXSCR
- class: code label
- addresses: edit 0E61
- aliases: FSCEN (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: further: the cursor's line in the middle

### FIXSCR_SETROW — local of FIXSCR
- class: code label
- addresses: edit 0E70
- aliases: FSROW (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the cursor's row

### FIXSCR_HSCROLL — local of FIXSCR
- class: code label
- addresses: edit 0E89
- aliases: FSH (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: LEFT = CCOL - W/2 ...

### FIXSCR_ROUND — local of FIXSCR
- class: code label
- addresses: edit 0E95
- aliases: FSH1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ... a multiple of 8 (tab stops line up),

### FIXSCR_SETLEFT — local of FIXSCR
- class: code label
- addresses: edit 0EA5
- aliases: FSH2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: unchanged (cursor beyond LMAX): no redraw

### FIXSCR_MARKF — local of FIXSCR
- class: code label
- addresses: edit 0EB1
- aliases: FSM (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: DELB's request: now CCOL / CROW are known

### FIXSCR_X — local of FIXSCR
- class: code label
- addresses: edit 0EC0
- aliases: FSX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (the view is right)

### SETTOP_UP — local of SETTOP
- class: code label
- addresses: edit 0EC3
- aliases: ST1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: enough

### SETTOP_SET — local of SETTOP
- class: code label
- addresses: edit 0ED7
- aliases: ST2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the top line

### SETTOP_X — local of SETTOP
- class: code label
- addresses: edit 0EEF
- aliases: ST3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (TOP, TOPLN, CROW set)

### DRAW_SOME — local of DRAW
- class: code label
- addresses: edit 0F4F
- aliases: DR0 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: SCASB stepped one past the first mark

### DRAW_DONE_EARLY — local of DRAW
- class: code label
- addresses: edit 0F85
- aliases: DRDN0 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: everything sent

### DRAW_ABOVE — local of DRAW
- class: code label
- addresses: edit 0F8C
- aliases: DR1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the rows above the cursor's

### DRAW_ABOVE_NEXT — local of DRAW
- class: code label
- addresses: edit 0FC8
- aliases: DR1A (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the next row

### DRAW_CURSOR_ROW — local of DRAW
- class: code label
- addresses: edit 0FCE
- aliases: DR2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the cursor's row: the line in two pieces

### DRAW_CURSOR_LEN — local of DRAW
- class: code label
- addresses: edit 1005
- aliases: DR3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (LF - GAPE)

### DRAW_BELOW — local of DRAW
- class: code label
- addresses: edit 1018
- aliases: DR4 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the rows below

### DRAW_BELOW_LEN — local of DRAW
- class: code label
- addresses: edit 104F
- aliases: DR6 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (LF - start)

### DRAW_SEND — local of DRAW
- class: code label
- addresses: edit 105D
- aliases: DR5 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: send it if marked

### DRAW_X — local of DRAW
- class: code label
- addresses: edit 1062
- aliases: DRX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: CF=1: a key is waiting

### DRAWR_OK — local of DRAWR
- class: code label
- addresses: edit 107E
- aliases: DWX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: CF=0: go on

### DRAWR_X — local of DRAWR
- class: code label
- addresses: edit 107F
- aliases: DWR (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (CF: 1 = stop)

### ROWOUT_SEND — local of ROWOUT
- class: code label
- addresses: edit 10AC
- aliases: RO1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the row

### EXPAND_BYTE — local of EXPAND
- class: code label
- addresses: edit 10F5
- aliases: EX1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: a byte of the line

### EXPAND_PUT — local of EXPAND
- class: code label
- addresses: edit 10FE
- aliases: EX2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: shown as it is

### EXPAND_X — local of EXPAND
- class: code label
- addresses: edit 1101
- aliases: EXX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (DI = past the expanded bytes)

### EXPAND_QUERY — local of EXPAND
- class: code label
- addresses: edit 1102
- aliases: EXQ (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: shown as '?'

### EXPAND_CTL — local of EXPAND
- class: code label
- addresses: edit 1106
- aliases: EXC (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: a tab?

### STATUS_LINE — local of STATUS
- class: code label
- addresses: edit 1156
- aliases: SS1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the line number

### STATUS_COL — local of STATUS
- class: code label
- addresses: edit 1168
- aliases: SS2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the column, 1-based

### STATUS_MSG — local of STATUS
- class: code label
- addresses: edit 117B
- aliases: SS3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the message (compared as a pointer)

### STATUS_X — local of STATUS
- class: code label
- addresses: edit 118D
- aliases: SS4 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (the status line is right)

### SFULL_MARK — local of SFULL
- class: code label
- addresses: edit 11C7
- aliases: SF1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: the column of the mark

### SFULL_PAD — local of SFULL
- class: code label
- addresses: edit 11E3
- aliases: SF2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ESC M

### PUTMOD_PUT — local of PUTMOD
- class: code label
- addresses: edit 1218
- aliases: PM1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (PUTC returns for us)

### PUTNUM_DIV — local of PUTNUM
- class: code label
- addresses: edit 122F
- aliases: PN1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (DX:AX / 10)

### PUTNUM_DIGIT — local of PUTNUM
- class: code label
- addresses: edit 123E
- aliases: PN2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: highest digit first

### PUTNUM_PAD — local of PUTNUM
- class: code label
- addresses: edit 124A
- aliases: PN3 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (none)

### PUTNUM_X — local of PUTNUM
- class: code label
- addresses: edit 1251
- aliases: PNX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (5 columns written); also PUTNM's

### PUTMSG_EOL — local of PUTMSG
- class: code label
- addresses: edit 1261
- aliases: PMS1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ESC K clears the rest of row 0

### PLACE_ROW — local of PLACE
- class: code label
- addresses: edit 1295
- aliases: PL1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: screen row = text row + 1

### PUTS_X — local of PUTS
- class: code label
- addresses: edit 12C8
- aliases: PSX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (SI past the 0)

### FLUSHQ_KEEP — local of FLUSHQ
- class: code label
- addresses: edit 12D9
- aliases: FQ1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (the column base for SFULL)

### FLUSH_LOOP — local of FLUSH
- class: code label
- addresses: edit 12EE
- aliases: FL1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: a byte

### FLUSH_X — local of FLUSH
- class: code label
- addresses: edit 12F3
- aliases: FLX (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: (OBUF empty)

### HELP_CHAR — local of HELP
- class: code label
- addresses: edit 1317
- aliases: HE1 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: ~600 bytes: sent in pieces

### HELP_WAIT — local of HELP
- class: code label
- addresses: edit 1324
- aliases: HE2 (source)
- status: verified (code + EDIT.ASM + EDIT.LST address)
- notes: first line: send the rest

## New equates

### PSP_MEMTOP — first segment past our memory
- class: constant (PSP offset)
- addresses: value 02h
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: first segment past our memory

### PSP_FCB1 — FCB parsed from the first argument
- class: constant (PSP offset)
- addresses: value 5Ch
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: FCB parsed from the first argument

### PSP_TAILLEN — command tail: length byte
- class: constant (PSP offset)
- addresses: value 80h
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: command tail: length byte

### PSP_TAIL — and its text (ends in CR)
- class: constant (PSP offset)
- addresses: value 81h
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: and its text (ends in CR)

### INT24_VEC — 0000:0090h, the critical-error vector
- class: constant (vector address)
- addresses: value 24h*4
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: 0000:0090h, the critical-error vector

### FCB_NAME — 8 name bytes
- class: constant (FCB offset)
- addresses: value 1
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: 8 name bytes

### FCB_EXT — 3 extension bytes
- class: constant (FCB offset)
- addresses: value 9
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: 3 extension bytes

### FCB_RECSZ — record size (word): EDIT sets 1
- class: constant (FCB offset)
- addresses: value 14
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: record size (word): EDIT sets 1

### FCB_SIZE — file size, low word
- class: constant (FCB offset)
- addresses: value 16
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: file size, low word

### FCB_SIZEHI — high word
- class: constant (FCB offset)
- addresses: value 18
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: high word

### FCB_RANDOM — random record, low word
- class: constant (FCB offset)
- addresses: value 33
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: random record, low word

### FCB_RANDOMHI — high word
- class: constant (FCB offset)
- addresses: value 35
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: high word

### REN_NEW — rename FCB: the new name (16 = its drive)
- class: constant (rename-FCB offset)
- addresses: value 17
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: rename FCB: the new name (16 = its drive)

### REN_NEWEXT — the new extension
- class: constant (rename-FCB offset)
- addresses: value 25
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: the new extension

### NAMELEN — 8 + 3, blank-padded
- class: constant
- addresses: value 11
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: 8 + 3, blank-padded

### FCBHEAD — drive byte + name + extension
- class: constant (FCB offset)
- addresses: value 12
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: drive byte + name + extension

### DOS_PRTSTR — print a $-terminated string at DX
- class: constant (INT 21h function)
- addresses: value 09h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: print a $-terminated string at DX

### DOS_OPEN — open FCB
- class: constant (INT 21h function)
- addresses: value 0Fh
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: open FCB

### DOS_CLOSE — close FCB
- class: constant (INT 21h function)
- addresses: value 10h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: close FCB

### DOS_DELETE — delete FCB (wildcards allowed)
- class: constant (INT 21h function)
- addresses: value 13h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: delete FCB (wildcards allowed)

### DOS_MAKE — create FCB
- class: constant (INT 21h function)
- addresses: value 16h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: create FCB

### DOS_RENAME — rename FCB (old name at 1, new at 17)
- class: constant (INT 21h function)
- addresses: value 17h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: rename FCB (old name at 1, new at 17)

### DOS_CURDSK — AL = current drive, 0 = A
- class: constant (INT 21h function)
- addresses: value 19h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: AL = current drive, 0 = A

### DOS_SETDTA — disk transfer address = DX
- class: constant (INT 21h function)
- addresses: value 1Ah
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: disk transfer address = DX

### DOS_SETVEC — vector AL = DS:DX
- class: constant (INT 21h function)
- addresses: value 25h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: vector AL = DS:DX

### DOS_BLKREAD — random block read, CX records
- class: constant (INT 21h function)
- addresses: value 27h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: random block read, CX records

### DOS_BLKWRITE — random block write, CX records
- class: constant (INT 21h function)
- addresses: value 28h
- aliases: none (the source writes the literal or the number)
- status: verified (code + MSDOS.LST dispatch table)
- notes: random block write, CX records

### VID_TTY — INT 10h: AL to the terminal
- class: constant (INT 10h function)
- addresses: value 0Eh
- aliases: none (the source writes the literal or the number)
- status: verified (code + z86sys.asm T_I10 / T_I16)
- notes: INT 10h: AL to the terminal

### KBD_READ — INT 16h: wait, AL = key
- class: constant (INT 16h function)
- addresses: value 00h
- aliases: none (the source writes the literal or the number)
- status: verified (code + z86sys.asm T_I10 / T_I16)
- notes: INT 16h: wait, AL = key

### KBD_PEEK — INT 16h: ZF=0 if a key is waiting
- class: constant (INT 16h function)
- addresses: value 01h
- aliases: none (the source writes the literal or the number)
- status: verified (code + z86sys.asm T_I10 / T_I16)
- notes: INT 16h: ZF=0 if a key is waiting

### VT_CUP — ESC Y row+32 col+32: cursor address
- class: constant (VT52 code)
- addresses: value 'Y'
- aliases: none (the source writes the literal or the number)
- status: verified (code + OVERVIEW 2.7 + test_edit.py terminal model; worked on a real FDD3000 + TC2048 / TC2068, notes/hardware_run.md)
- notes: ESC Y row+32 col+32: cursor address

### VT_BIAS — the bias on row and column
- class: constant (VT52 code)
- addresses: value 32
- aliases: none (the source writes the literal or the number)
- status: verified (code + OVERVIEW 2.7 + test_edit.py terminal model; worked on a real FDD3000 + TC2048 / TC2068, notes/hardware_run.md)
- notes: the bias on row and column

### VT_HOME — ESC H: cursor home
- class: constant (VT52 code)
- addresses: value 'H'
- aliases: none (the source writes the literal or the number)
- status: verified (code + OVERVIEW 2.7 + test_edit.py terminal model; worked on a real FDD3000 + TC2048 / TC2068, notes/hardware_run.md)
- notes: ESC H: cursor home

### VT_EOS — ESC J: clear to the end of the screen
- class: constant (VT52 code)
- addresses: value 'J'
- aliases: none (the source writes the literal or the number)
- status: verified (code + OVERVIEW 2.7 + test_edit.py terminal model; worked on a real FDD3000 + TC2048 / TC2068, notes/hardware_run.md)
- notes: ESC J: clear to the end of the screen

### VT_EOL — ESC K: clear to the end of the line
- class: constant (VT52 code)
- addresses: value 'K'
- aliases: none (the source writes the literal or the number)
- status: verified (code + OVERVIEW 2.7 + test_edit.py terminal model; worked on a real FDD3000 + TC2048 / TC2068, notes/hardware_run.md)
- notes: ESC K: clear to the end of the line

### VT_INVON — ESC L: inverse on (Terminal 3000)
- class: constant (VT52 code)
- addresses: value 'L'
- aliases: none (the source writes the literal or the number)
- status: verified (code + OVERVIEW 2.7 + test_edit.py terminal model; worked on a real FDD3000 + TC2048 / TC2068, notes/hardware_run.md)
- notes: ESC L: inverse on (Terminal 3000)

### VT_INVOFF — ESC M: inverse off
- class: constant (VT52 code)
- addresses: value 'M'
- aliases: none (the source writes the literal or the number)
- status: verified (code + OVERVIEW 2.7 + test_edit.py terminal model; worked on a real FDD3000 + TC2048 / TC2068, notes/hardware_run.md)
- notes: ESC M: inverse off

### VT_RLF — ESC I: cursor up; on row 0 scroll down
- class: constant (VT52 code)
- addresses: value 'I'
- aliases: none (the source writes the literal or the number)
- status: verified (code + OVERVIEW 2.7 + test_edit.py terminal model; worked on a real FDD3000 + TC2048 / TC2068, notes/hardware_run.md)
- notes: ESC I: cursor up; on row 0 scroll down

### KEY_DEL — DEL: delete left (as ^H)
- class: constant (key code)
- addresses: value 7Fh
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: DEL: delete left (as ^H)

### KEY_BS — ^H, accepted by PROMPT
- class: constant (key code)
- addresses: value 08h
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: ^H, accepted by PROMPT

### KEY_CTLU — ^U: give up a prompt
- class: constant (key code)
- addresses: value 'U'-40h
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: ^U: give up a prompt

### ARROW_UP — ESC A .. ESC D: the terminal's arrows
- class: constant (key code)
- addresses: value 'A'
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: ESC A .. ESC D: the terminal's arrows

### ARROW_DOWN — 
- class: constant (key code)
- addresses: value 'B'
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: 

### ARROW_RIGHT — 
- class: constant (key code)
- addresses: value 'C'
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: 

### ARROW_LEFT — 
- class: constant (key code)
- addresses: value 'D'
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: 

### STNAMEW — inverse name field " A:NAME.EXT*"
- class: constant
- addresses: value 17
- aliases: none (the source writes the literal or the number)
- status: verified (code + EDIT.ASM expression)
- notes: inverse name field " A:NAME.EXT*"


## Facts added to author names

### SIG / BUFS..MODIF — the state block at 0103h
- class: variable
- addresses: edit 0103-0123
- aliases: none
- status: verified (code + EDIT.ASM + test_edit.py `vars()`)
- notes: test_edit.py finds "EDIT86" and unpacks `<13HB` after it; the order
  is an interface.  The source comment says test_fdd86.py; it is test_edit.py
  (which imports test_fdd86).  COLS is written by OPTS and never read.

### DIRTY — per-row marks
- class: table
- addresses: edit 015A (24 bytes)
- aliases: none
- status: verified (code + EDIT.ASM)
- notes: FFh clean; else the first screen column (relative to LEFT) to send;
  0 = whole row.  Lowered by MARKC/MARKR, shifted by SCRUP/SCRDN, reset by ROWOUT.

### CTAB — control code -> command
- class: table
- addresses: edit 04C7 (32 words)
- aliases: none
- status: verified (code + EDIT.ASM + test_edit.py every-key test)
- notes: decoded in full in the volume's CTAB header.
