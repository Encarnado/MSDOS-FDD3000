# Z86.SYS part 04 dictionary (DFF8h-E416h)

Renamed numbered locals of the string/REP region. All are referenced only
inside part 04 (searched Z86.SYS.lst and CPMZ80.lst). No new equates.

### SI_STEP_B — SI += STEP1 (+1 / -1 by DF): byte string step; AF' untouched
- class: routine
- addresses: z86 E0E9
- aliases: NSI1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### DI_STEP_B — DI += STEP1 (+1 / -1 by DF): byte string step; AF' untouched
- class: routine
- addresses: z86 E0F5
- aliases: NDI1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### SI_STEP_W — SI += STEP2 (+2 / -2 by DF): word string step
- class: routine
- addresses: z86 E101
- aliases: NSI2 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### DI_STEP_W — DI += STEP2 (+2 / -2 by DF): word string step
- class: routine
- addresses: z86 E10D
- aliases: NDI2 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### CMPSB_STEP — one CMPSB iteration: 8086 flags of [DS:SI] - [ES:DI] into AF', SI and DI stepped; body shared by O_CMPSB and R_CMPSB
- class: routine
- addresses: z86 E142
- aliases: CMPSB1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### CMPSW_STEP — one CMPSW iteration (AF from bit 11); shared by O_CMPSW and R_CMPSW
- class: routine
- addresses: z86 E15E
- aliases: CMPSW1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### SCASB_STEP — one SCASB iteration: flags of AL - [ES:DI], DI stepped; shared by O_SCASB and R_SCASB (also the CPIR path's final compare)
- class: routine
- addresses: z86 E1BF
- aliases: SCASB1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### SCASW_STEP — one SCASW iteration; shared by O_SCASW and R_SCASW
- class: routine
- addresses: z86 E1CF
- aliases: SCASW1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### REP_FETCH — O_REP: read the next instruction byte and route it (REPTAB, override, prefix, or DISPA)
- class: routine
- addresses: z86 E1E8
- aliases: REP1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### REP_TRY_SEG — O_REP: byte below A4h - a segment override (26/2E/36/3E) goes to SEGSET, else REP_OTHER
- class: routine
- addresses: z86 E201
- aliases: REP2 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### REP_OTHER — O_REP: another REP (last wins), LOCK skipped, anything else dispatched as if no REP
- class: routine
- addresses: z86 E20E
- aliases: REP3 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RMOVSB_GO — R_MOVSB with CX >= 1: set up the LDIR/LDDR
- class: routine
- addresses: z86 E282
- aliases: RMB1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RMOVSB_DOWN — R_MOVSB, DF = 1: LDDR
- class: routine
- addresses: z86 E297
- aliases: RMB2 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RMOVSB_DONE — R_MOVSB: IP back, SI/DI advance via RADVSD
- class: routine
- addresses: z86 E299
- aliases: RMB3 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RMOVSW_GO — R_MOVSW with CX >= 1: 2*CX-byte LDIR/LDDR
- class: routine
- addresses: z86 E2A7
- aliases: RMW1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RMOVSW_DOWN — R_MOVSW, DF = 1: start at the first word's high byte, LDDR
- class: routine
- addresses: z86 E2BD
- aliases: RMW2 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RMOVSW_DONE — R_MOVSW: IP back, advance by 2*CX via RADVSD
- class: routine
- addresses: z86 E2C1
- aliases: RMW3 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSTOSB_GO — R_STOSB with CX >= 1: first byte by hand, then the overlapping fill
- class: routine
- addresses: z86 E2D1
- aliases: RSB1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSTOSB_DOWN — R_STOSB, DF = 1: fill downwards with LDDR
- class: routine
- addresses: z86 E2ED
- aliases: RSB2 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSTOSB_DONE — R_STOSB: IP back, DI advance via RADVDN
- class: routine
- addresses: z86 E2F0
- aliases: RSB3 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSTOSW_GO — R_STOSW with CX >= 1: first word by hand, then the period-2 fill
- class: routine
- addresses: z86 E2FF
- aliases: RSW1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSTOSW_DOWN — R_STOSW, DF = 1: DI+1 -> DI-1 downwards
- class: routine
- addresses: z86 E321
- aliases: RSW2 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSTOSW_DONE — R_STOSW: IP back, DI advance by 2*CX via RADVDN
- class: routine
- addresses: z86 E325
- aliases: RSW3 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RLODSB_LOOP — R_LODSB: load / step / CX-1 loop
- class: routine
- addresses: z86 E335
- aliases: RLB1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RLODSW_LOOP — R_LODSW: load / step / CX-1 loop
- class: routine
- addresses: z86 E353
- aliases: RLW1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### REPGO_ZF1 — REPGO, 8086 ZF = 1: stop if REPNE
- class: routine
- addresses: z86 E384
- aliases: REPGO1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RCMPSB_LOOP — R_CMPSB iteration loop (CMPSB_STEP + REPGO)
- class: routine
- addresses: z86 E390
- aliases: RCB1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RCMPSW_LOOP — R_CMPSW iteration loop
- class: routine
- addresses: z86 E3A1
- aliases: RCW1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASB_GO — R_SCASB with CX >= 1: choose the CPIR fast path (REPNE, CX >= 2, no DI wrap) or the ordinary loop
- class: routine
- addresses: z86 E3B2
- aliases: RSC0 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASB_FWD — R_SCASB fast path, DF = 0: wrap test DI + n
- class: routine
- addresses: z86 E3CD
- aliases: RSCF (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASB_WRAP_CHK — R_SCASB fast path: carry = DI would wrap -> ordinary loop
- class: routine
- addresses: z86 E3CE
- aliases: RSCF1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASB_CPDR — R_SCASB fast path, DF = 1: CPDR
- class: routine
- addresses: z86 E3E0
- aliases: RSCD (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASB_PASSED — R_SCASB fast path after CPIR/CPDR: hand a matched byte back
- class: routine
- addresses: z86 E3E2
- aliases: RSCE (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASB_SET_CX — R_SCASB fast path: new CX, DI advanced by the bytes passed over
- class: routine
- addresses: z86 E3E5
- aliases: RSCE1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASB_SLOW — R_SCASB: IP back, then the ordinary loop (also the wrap exit)
- class: routine
- addresses: z86 E3FB
- aliases: RSCX (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASB_LOOP — R_SCASB ordinary loop (SCASB_STEP + REPGO); makes the final compare after CPIR
- class: routine
- addresses: z86 E3FC
- aliases: RSC1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)

### RSCASW_LOOP — R_SCASW iteration loop
- class: routine
- addresses: z86 E40D
- aliases: RSCW1 (source)
- status: verified (code + I86.ASM + cpu86.py op_string)
