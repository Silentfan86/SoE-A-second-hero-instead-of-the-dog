; SoE_A-second-hero-instead-of-the-dog (player 2 plays a second hero instead of the Dog)
; Assembler: asar 1.91 (hirom). Applied to a Casual Run 2.0 ROM after fix_p2_signature.asm and
; fix_ring_pad.asm.
;
; Contents
;  - Hero mode: while player 2 controls the Dog ($F2 bit 3), the Dog slot becomes the hero every frame:
;    animations/attacks of P2's weapon, hit class "weapon" (+$30 = 8), own palette (slot 7).
;    When P2 gives up the Dog, the current Dog form is restored natively via $8F946B.
;  - Weapon choice: P2 freely cycles through the owned weapons with L/R, including the Bazooka
;    (the ammunition type $2349 is shared by both players). Attack = the Boy's base attack + weapon power
;    (formula as $CF8485), max. charge = weapon level * $400 (as $CF8260). Kills by P2 give weapon
;    experience to P2's weapon (wrapper around $C57410 at the weapon hit handler $CFB777).
;    In towns and interiors ($23BF) the hero is unarmed like the Boy.
;  - Own palette: palette source as for the Boy, body colors 6-11 replaced by a hero ramp
;    (sprite palette 7, object +$0C = $0E).
;  - In hero mode the Dog controls skip their L/R special path (L/R switch the weapon).
;  - Message "P2: <weapon>" on joining and on every weapon change (native message system).
;  - P2's weapon per save slot: stored in the slot on saving, taken over on loading.
;  - Rings for P2: X on P2's controller opens the native Ring (owner Dog, input from P2's controller).
;    Order: Weapon, Alchemy, and Item Rings (native, e.g. healing with target selection).
;    Weapon list as native (Bazooka with ammunition ring), cursor on P2's weapon, preview against
;    P2's weapon; the choice goes to !P2W, the Boy's weapon stays.
;  - Interaction: for scripts the P2 hero is "the Boy" (opening gourds and chests; loot goes to the
;    shared inventory).
;  - Dialogues: P2 advances pages only with newly pressed buttons; the Boy is released after the
;    hero's conversation; P2's action buttons are masked while a dialogue is open.
;  - HUD: in hero mode the right HUD shows the Boy's face in the hero palette.
;  - Enemies: while P2 is active, damage to enemies is reduced to 2/3 (= 150 % HP).
;  - Hero/Dog toggle: Y on P2's controller (e.g. for sniffing). If the Boy is absent
;    ($2261 bit 1, e.g. Dog maze), hero mode pauses automatically and P2 controls the Dog.
;
; P2's state lives in SRAM behind the four save slots (offset $1F00), never used by the game
; (runtime: accesses only up to $0A33; data: $0CC6-$1FFF unchanged $FF).
; In addition, one copy per slot ($307F40 + slot*2), written on saving, read on loading.

hirom

!KH_MAGIC   = $307F00	; "HK" = $4B48 once initialized
!P2W        = $307F02	; P2's weapon selector ($02..$1A, 0 = none)
!P2RING     = $307F04	; <> 0: the Ring just requested/open belongs to the P2 hero
!P2DOG      = $307F06	; <> 0: P2 switched to the Dog with Y (hero mode paused)
!DMG_REM    = $307F08	; damage remainder (division by 3) for the target hit last
!DMG_TGT    = $307F0A	; target hit last
!SLOTTBL    = $307F40	; P2's weapon per save slot (4 words, $FFFF = unknown)
!TMP_SEL    = $307F10
!TMP_POW    = $307F12
!TMP_SRC    = $307F14
!TMP_VAR    = $307F16
!TMP_DIRTY  = $307F18
!TMP_START  = $307F1A
!TMP_STEP   = $307F1C
!TMP_CNT    = $307F1E
!TMP_CUR    = $307F20
!DLGPREV    = $307F22	; controller 2 at the last dialogue poll
!DLGNEW     = $307F24
!DEADPTR    = $307F26	; KO: last frame of the hero's collapse animation (address)
!DEADBANK   = $307F28	; KO: its bank (0 = not captured yet)
!TMP_FRM    = $307F2A	; HeroDogFrame: bank of the frame being tested (high byte)

; ---------------------------------------------------------------------------
; Hooks in native code
; ---------------------------------------------------------------------------
; --- HUD: in hero mode the Boy's face in the hero palette (slot 7) instead of the Dog's head ---
org $CFC68C			; was LDA $4FA5 / STA $26 / LDA $4FA7 / STA $28 (10 bytes)
	JSL HeroAvatarSrc
	NOP #6

org $CFD0A8			; Dog think dispatch (table $CFCBE0, entry 3)
	JML HeroSync		; was JML $F002A0 (FuSoYa); HeroSync continues there

org $CFCFA2			; Dog controls: was LDA $00FC / BIT #$0030 (6 bytes)
	JSL HeroSniffGate	; returns Z as BIT #$0030, always Z=1 in hero mode
	NOP #2

org $CFB777			; weapon hit handler: was JSL $C57410 (Casual Run, weapon experience)
	JSL HeroExpCredit

org $CDB470			; end of saving: was LDX $2E / STA $0000,X / PLB / RTL
	JML HeroOnSave		; HeroOnSave executes these instructions itself

org $CDB7D1			; end of loading: was STA $7E22EE / RTL
	JML HeroOnLoad

; --- Weapon Ring for P2 ---
org $CE99D2			; build weapon ring list: was PHB / PEA $7E7E
	JML HeroRingBuild

org $CE91E8			; weapon confirmed in the Ring: was STA $7E2441
	JSL HeroRingCommit

org $CE9224			; ammunition confirmed in the Ring: was STA $7E2441 (A = $1A Bazooka)
	JSL HeroRingCommit

org $CEA49A			; Ring preview "old -> new": was LDX $0ABA / LDA $C43874,X
	JSL HeroRingCurW
	NOP #3

org $CEE534			; main loop, open the Dog's Ring: was LDA #$9998 / STA $97
	JSL HeroRingList
	NOP

; --- Enemy HP 150 % while player 2 is active ---
org $CFC237			; apply damage: was LDA $002A,Y / SEC / SBC $0076,Y / BPL / TDC / STA $002A,Y (13 bytes)
	JSL HeroDamage
	NOP #9

; --- Interaction (gourds, chests, ...) by the P2 hero ---
; --- Dialogues/choices (FuSoYa $F00965): in hero mode P2 advances only with newly pressed buttons and
;     consumes them ($FA). Otherwise the pressed button stayed in $FA: pages flew by and the hero
;     immediately talked to the character again afterwards (dialogue 2-3 times). ---
org $F00965			; was LDA $F2 / BIT #$000C
	JML HeroDlgKey
	NOP

; --- Script command "release character" ($F0072D, expression $50/$52): as for halting ($F00580), the
;     hero in the Dog slot counts as the Boy. Otherwise the Boy stayed halted after the hero's conversation. ---
org $F0072D			; was LDA $EC / BNE / LDA $0F42 / STA $02 / RTS (10 bytes)
	JSL HeroUnfreezeActor
	RTS
	NOP #5

; --- Object think prolog ($CFCC1E, runs for every object, also during scripts and while the Dog slot is
;     halted): while a Dog animation would play on the hero (script, e.g. sleeping at an inn, or the walk-in
;     after a map change), the hero shows the Boy's current frame instead; the hero palette is kept. ---
org $CFCC1E			; was LDA $0010,Y / STA $0EB6
	JSL HeroScriptPose
	NOP #2

; --- Animation engine, frame opcode $2n ($908418): when a Dog frame for the hero would be stored,
;     store the Boy's current frame instead (same conditions as HeroScriptPose; avoids one-frame flashes). ---
org $908421			; was LDA [$5D] / STA $0006,Y (5 bytes)
	JSL HeroFrameSet
	NOP

; --- KO: after the death collapse the game reloads the Dog's palette into slot 7 ($90CDDC -> $90CE05).
;     In hero mode the hero keeps his own palette (otherwise the collapse shows in Dog colors). ---
org $90CE05			; was PHX / PHY / TAX / LDA $0A79 (continues at $90CE09, RTL at $90CE14)
	JML HeroPalRestore

org $F00580			; FuSoYa: script expression $52 "acting character" (LDA $EA / LDA $0F42 / STA $EC / STA $02)
	JSL HeroActor
	RTS
	NOP #6			; rest of the old 12 bytes ($F00580-$F0058B)

; ---------------------------------------------------------------------------
; New code, previously unused area of the expansion
; ---------------------------------------------------------------------------
org $FC8100

; Entry: from JMP ($CBE0,X) with 16-bit A/X/Y, Y = Dog object ($4F37).
; All registers, P, DB, and D are preserved; exit JML $F002A0 (FuSoYa, unchanged).
HeroSync:
	PHP
	REP #$30
	PHA
	PHX
	PHY
	PHB
	PHD
	PEA $7E7E
	PLB
	PLB
	PEA $0000		; D = 0 (palette upload uses $26/$28/$2E like $90CFB8)
	PLD
	LDA.w $00F2		; FuSoYa assignment
	AND #$0008		; bit 3: player 2 controls the Dog
	BNE .p2Dog
	LDA #$0000		; P2 does not control the Dog: reset the toggle
	STA.l !P2DOG
	BRA .noHero
.p2Dog:
	JSR HeroToggleInput	; Y (controller 2): hero <-> Dog
	LDA.l !P2DOG
	BNE .noHero		; P2 switched to the Dog
	LDA $2261		; bit 1: Boy absent (native: Boy HUD off, $CFC648) -> Dog required
	AND #$0002
	BNE .noHero
	LDA $0AA0
	CMP #$0008
	BEQ .active
	JSR HeroInit		; transition Dog -> hero
.active:
	JSR HeroRingFlag
	JSR HeroWeaponInput
	JSR HeroEquip
	JSR HeroPalette
	LDA $4F61		; Dog slot +$2A: HP
	BNE .alive
	JSR HeroDeadPose	; KO: keep the hero lying in the last frame of his collapse
	BRA .done
.alive:
	LDA #$0000
	STA.l !DEADBANK
	LDA $4E99		; Boy halted (dialogue/script, +$10 bit $20): block the hero's action buttons
	AND #$0020		; (otherwise P2 talked to the character again during the dialogue). Walking stays
	BEQ .done		; possible, as for FuSoYa's P2 Dog (bit $20 is also set during short hit stuns).
	LDA $FE
	AND #$7F7F
	STA $FE
	LDA $FC
	AND #$7F7F
	STA $FC
	BRA .done
.noHero:
	LDA #$0000
	STA.l !P2RING
	LDA $0AA0
	CMP #$0008
	BNE .done		; hero mode was not active
	; --- return to the Dog ---
	LDA #$000A		; +$30 hit class bite (value from ROM record 1)
	STA $0AA0
	LDA $0B07		; Dog's max. charge as native $CF97D6: high byte($0B07) * $400
	AND #$FF00
	ASL
	ASL
	STA $0A9C
	LDA $2363		; current Dog form
	BEQ .statsOnly
	STA $2443		; mark as "pending"
	JSL $8F946B		; sets +$13/+$32..+$48/+$6E, palette $0E/$0E0E, loads the palette, calls $8F857D
	BRA .done
.statsOnly:
	JSL $8F857D		; recalculate the Dog's stats (e.g. attack +$19)
.done:
	PLD
	PLB
	PLY
	PLX
	PLA
	PLP
	JML $F002A0

; --- KO (HP = 0): the native code would show the hero standing again (idle animation from his record)
;     and later the Dog's lying pose. The first call after the collapse still sees its last frame:
;     remember it, then hold it (frame timer +$05 kept high) and ignore P2's input until revived. ---
HeroDeadPose:
	LDA.l !DEADBANK
	BNE .have
	LDA $4F3D		; object +$06/+$08: current frame of the collapse animation
	STA.l !DEADPTR
	LDA $4F3F
	AND #$00FF
	STA.l !DEADBANK
.have:
	LDA.l !DEADPTR
	STA $4F3D
	SEP #$20
	LDA.l !DEADBANK
	STA $4F3F
	LDA #$7F		; +$05: frame timer, do not advance
	STA $4F3C
	REP #$20
	STZ $FC			; no movement or actions while knocked out
	STZ $FE
	RTS

; --- Y of player 2 (press buffer controller 2): switch between hero and Dog ---
HeroToggleInput:
	LDA.w $00FA
	AND #$4000
	BEQ .end
	TRB.w $00FA		; consume the press
	LDA.l !P2DOG
	EOR #$0001
	STA.l !P2DOG
	BEQ .end		; back to the hero: HeroInit announces the weapon
	LDA.w #HeroDogText&$FFFF
	JSR HeroMessage		; "P2: Dog"
.end:
	RTS

; --- Transition Dog -> hero: check the SRAM state, make P2's weapon valid ---
HeroInit:
	LDA #$0000
	STA.l !P2RING
	LDA.l !KH_MAGIC
	CMP #$4B48
	BEQ .magicOk
	LDA #$4B48
	STA.l !KH_MAGIC
	LDA #$0000
	STA.l !P2W
	LDA #$FFFF		; per-slot weapons: nothing stored yet
	STA.l !SLOTTBL
	STA.l !SLOTTBL+2
	STA.l !SLOTTBL+4
	STA.l !SLOTTBL+6
.magicOk:
	LDA.l !P2W
	JSR IsSelectable
	BCS .ok
	LDA $0ABA		; otherwise: take the Boy's weapon
	JSR IsSelectable
	BCS .set
	LDA #$001A		; otherwise: first owned weapon from $02
	LDY #$0002
	JSR NextSelectable
	JSR IsSelectable
	BCS .set
	LDA #$0000
.set:
	STA.l !P2W
.ok:
	LDA.l !P2W
	BEQ .noMessage
	JSR HeroAnnounce
.noMessage:
	RTS

; --- A = selector. C=1 if $02..$1A (even) and owned (tables as $CF927F). A is preserved. ---
IsSelectable:
	CMP #$0002
	BCC .no
	CMP #$001C		; $02..$1A (including the Bazooka)
	BCS .no
	BIT #$0001
	BNE .no
	PHA
	TAX
	LDA.l $C459A4,x		; address of the inventory word
	TAY
	LDA $0000,y		; DB = $7E
	AND.l $C459C0,x		; bit mask of the weapon
	BEQ .noPla
	PLA
	SEC
	RTS
.noPla:
	PLA
.no:
	CLC
	RTS

; --- A = start, Y = step ($0002 / $FFFE). Returns A = next selectable selector, otherwise start ---
NextSelectable:
	STA.l !TMP_START
	TYA
	STA.l !TMP_STEP
	LDA #$000E
	STA.l !TMP_CNT
	LDA.l !TMP_START
.loop:
	CLC
	ADC.l !TMP_STEP
	CMP #$0002
	BCS .notBelow
	LDA #$001A
.notBelow:
	CMP #$001C
	BCC .notAbove
	LDA #$0002
.notAbove:
	JSR IsSelectable
	BCS .done
	STA.l !TMP_CUR
	LDA.l !TMP_CNT
	DEC
	STA.l !TMP_CNT
	BEQ .none
	LDA.l !TMP_CUR
	BRA .loop
.none:
	LDA.l !TMP_START
.done:
	RTS

; --- L/R of player 2 (press buffer $FE): switch weapon, R forward, L backward ---
HeroWeaponInput:
	LDA.l !P2W
	BEQ .end
	LDA.w $00FE
	AND #$0030
	BEQ .end
	TRB.w $00FE		; consume the press
	LDY #$0002
	AND #$0010		; R?
	BNE .direction
	LDY #$FFFE
.direction:
	LDA.l !P2W
	JSR NextSelectable
	CMP.l !P2W
	BEQ .end
	STA.l !P2W
	JSR HeroAnnounce
.end:
	; X of player 2: open the Weapon Ring (as native $CFCDF1 for the Dog, window as Casual Run $F50200)
	LDA.w $00FA		; press buffer controller 2 (FuSoYa filters X out of $FE in two-player mode)
	AND #$0040
	BEQ .noRing
	TRB.w $00FA		; consume the press
	LDA.l !P2W
	BEQ .noRing		; no Ring without a weapon
	LDA $4F47		; Dog +$10: absent/busy (native BIT #$1021)
	BIT #$1021
	BNE .noRing
	LDA $05A9		; Ring already requested (bit 1 Boy, bit 2 Dog)?
	AND #$0006		; (bit 15 natively stays set after cancelling and does not count here)
	BNE .noRing
	LDA #$0001
	STA.l !P2RING
	LDA $4FC7		; Dog +$90: position in the ring order (0 weapons, 2 alchemy, 4 items)
	CMP #$0005		; keep the last position, otherwise weapons
	BCC .posOk
	STZ $4FC7
.posOk:
	STZ $32F0		; FuSoYa: Ring input from the owner's controller (Dog -> P2)
	LDA #$1944
	STA $0B15
	LDA #$000E
	STA $0B17
	PHB
	PEA $8080
	PLB
	PLB
	JSL $8CAC16		; window graphics as $F50200
	PLB
	LDA #$4F37
	STA $05A7
	LDA #$0004
	TSB $05A9		; main loop $CEE527 opens the Ring
.noRing:
	RTS

; --- Reset the Ring flag as soon as no Ring request is pending ---
; The Ring runs modally in the main loop; meanwhile the Dog think code is not executed
; (verified at runtime: the flag survives the whole Ring). So here the Ring is closed.
HeroRingFlag:
	LDA $05A9
	AND #$0004
	BNE .open
	LDA #$0000
	STA.l !P2RING
.open:
	RTS

; --- C=1 if the current Ring belongs to the P2 hero (flag, owner Dog, hero mode) ---
IsP2Ring:
	LDA.l !P2RING
	BEQ .no
	LDA.l $7E05A7
	CMP #$4F37
	BNE .no
	LDA.l $7E0AA0
	CMP #$0008
	BNE .no
	SEC
	RTS
.no:
	CLC
	RTS

; Main loop (16-bit A, D = 0): choose the ring order for the Dog's Ring.
HeroRingList:
	LDA.l !P2RING
	BEQ .native
	LDA.l $7E0AA0
	CMP #$0008
	BNE .native
	; Ring order for P2: weapons (ID 4), alchemy (ID 2), items (ID 8); without status/options.
	; Lives in low RAM (bank $8E mirrors $0000-$1FFF): $0806-$080D belongs to the alchemy list
	; ($07EC: count, cursor, entries from $07F0), whose builder $CE9B3A writes at most 9 entries
	; ($07F0-$0801); $0802-$080F stays free.
	LDA #$0003
	STA.l $7E0806		; count
	LDA #$0004
	STA.l $7E0808		; Weapon Ring
	LDA #$0002
	STA.l $7E080A		; Alchemy Ring
	LDA #$0008
	STA.l $7E080C		; Item Ring
	LDA #$0806
	BRA .set
.native:
	LDA #$9998		; native: the Dog's order
.set:
	STA $97
	RTL

; Weapon ring list ($8E99D2). Native: all weapons including the Bazooka, cursor on $0ABA.
; P2: cursor on !P2W instead of $0ABA, otherwise identical (icon from weapon record +$1E, Bazooka $40).
HeroRingBuild:
	JSR IsP2Ring
	BCS .p2
	PHB			; native instructions, then back
	PEA $7E7E
	JML $CE99D6
.p2:
	PHB
	PEA $7E7E
	PLB
	PLB
	STZ $07A4		; count
	STZ $07A6		; cursor
	LDY #$0000
	STY $14
	LDX #$001A		; downwards from $1A (Bazooka), as native
.loop:
	LDA.l $C459A4,x
	TAY
	LDA.l $C459C0,x
	AND $0000,y
	BEQ .next
	STX $12
	LDA #$0040		; Bazooka: fixed ring icon $40 (native $CE99FB)
	CPX #$001A
	BEQ .icon
	LDA.l $C43874,x
	TAX
	LDA.l $C4001E,x		; ring icon of the weapon
.icon:
	LDY $14
	STA $07A8,y
	LDA.l !P2W
	CMP $12
	BNE .notCurrent
	LDA $07A4
	STA $07A6
.notCurrent:
	INC $07A4
	INC $14
	INC $14
	LDX $12
.next:
	DEX
	DEX
	BNE .loop
	PLB
	RTL

; Choice confirmed: A = selector. P2 Ring -> !P2W, otherwise native STA $7E2441 (Boy).
HeroRingCommit:
	PHA
	JSR IsP2Ring
	BCC .native
	PLA
	STA.l !P2W
	RTL
.native:
	PLA
	STA.l $7E2441
	RTL

; Preview: A = weapon table entry of the "old" weapon (P2 Ring: !P2W, otherwise $0ABA).
HeroRingCurW:
	JSR IsP2Ring
	BCC .native
	LDA.l !P2W
	JSR WeaponRecord	; Bazooka: record of the selected ammunition (as native $CEA58B)
	RTL
.native:
	LDA.l $7E0ABA
	TAX
	LDA.l $C43874,x
	RTL

; --- A = selector. Returns A = weapon record (bank $C4); Bazooka ($1A): record of the selected
;     ammunition $C4388E[$2349] as $CF81CE. ---
WeaponRecord:
	CMP #$001A
	BEQ .bazooka
	TAX
	LDA.l $C43874,x
	RTS
.bazooka:
	LDA.l $7E2349
	AND #$00FF
	TAX
	LDA.l $C4388E,x
	RTS

; Script expression $52 (FuSoYa $F00580): acting character. Natively, scripts such as the gourds
; ("Found some Clay", script $0771: 50 29 52 22) check "acting character == Boy". For scripts the P2
; hero is a human: in hero mode the expression returns the Boy for the Dog slot. $EC (controller
; assignment for dialogue input, $F00965) stays the real character.
; $F0072D: acting character for "release" (like HeroActor, without setting $EC).
HeroUnfreezeActor:
	LDA $EC
	BNE .set
	LDA.l $7E0F42
.set:
	CMP #$4F37
	BNE .done
	LDA.l $7E0AA0
	CMP #$0008
	BNE .dog
	LDA #$4E89
	BRA .done
.dog:
	LDA #$4F37
.done:
	STA $02
	RTL

; $F00965: buttons for dialogues. Hero mode ($0AA0 = 8): controller 1 ($F6) OR newly pressed buttons of
; controller 2; the dialogue buttons are consumed in $FA. Returns via the RTS at $F00961.
; $CFCC1E: Y = object. In hero mode the Dog slot shows the Boy's current frame (+$06..+$08) instead of
;  a) while a script runs the Dog slot (+$10 bit $40): any frame that is not one of the Boy's (bank $CA),
;     e.g. the Dog's sleeping pose at an inn; the Dog's own script keeps running, its state is not copied
;     (copying the Boy's script state broke the sprites when waking up);
;  b) otherwise: Dog frames (bank $CB) while the hero is alive, e.g. the walk-in after a map change, where
;     the Dog slot is halted, the think routine (HeroSync) does not run, and the map loader has restored the
;     Dog's animations and palette.
; The hero palette is kept here too (HeroPalKeep), because HeroSync does not run while the slot is halted.
; Then the replaced instructions.
HeroScriptPose:
	CPY #$4F37
	BNE .orig
	LDA.l $7E0AA0
	CMP #$0008
	BNE .orig
	JSR HeroPalKeep
	JSR HeroDogFrame
	BCC .orig
	LDA.l $7E4E8F		; Boy +$06/+$07
	STA.l $7E4F3D
	SEP #$20
	LDA.l $7E4E91		; Boy +$08: bank
	STA.l $7E4F3F
	REP #$20
.orig:
	LDA $0010,y
	STA $0EB6
	RTL

; C=1 if the Dog slot's frame (A = +$07/+$08, bank in the high byte) must be replaced by the Boy's frame:
; script running (+$10 bit $40) and bank <> $CA, or no script, hero alive, and bank = $CB. Uses $7E4F3E
; when called with A = 0 (prolog), otherwise A from the caller. A is destroyed.
HeroDogFrameA:
	AND #$FF00
	STA.l !TMP_FRM
	BRA HeroDogFrame_test
HeroDogFrame:
	LDA.l $7E4F3E		; +$07/+$08: address high byte and bank
	AND #$FF00
	STA.l !TMP_FRM
HeroDogFrame_test:
	LDA.l $7E4F47
	AND #$0040
	BEQ .noScript
	LDA.l !TMP_FRM
	CMP #$CA00
	BEQ .no
	SEC
	RTS
.noScript:
	LDA.l $7E4F61		; KO: HeroDeadPose handles the hero's pose
	BEQ .no
	LDA.l !TMP_FRM
	CMP #$CB00
	BNE .no
	SEC
	RTS
.no:
	CLC
	RTS

; Keep the hero palette while hero mode is active (same conditions as HeroSync: P2 controls the Dog slot,
; not switched to the Dog, Boy present). Preserves all registers, P, DB, and D.
HeroPalKeep:
	PHP
	REP #$30
	PHA
	PHX
	PHY
	PHB
	PHD
	PEA $7E7E
	PLB
	PLB
	PEA $0000
	PLD
	LDA.w $00F2
	AND #$0008
	BEQ .skip
	LDA.l !P2DOG
	BNE .skip
	LDA $2261
	AND #$0002
	BNE .skip
	JSR HeroPalette
.skip:
	PLD
	PLB
	PLY
	PLX
	PLA
	PLP
	RTS

; $908421: Y = object, +$08 already holds the new frame's bank, [$5D] = new frame. 16-bit A/X.
HeroFrameSet:
	CPY #$4F37
	BNE .native
	LDA.l $7E0AA0
	CMP #$0008
	BNE .native
	LDA $0007,y		; +$08 (high byte): bank of the new frame
	JSR HeroDogFrameA
	BCC .native
	LDA.l $7E4E8F		; Boy's current frame instead
	STA $0006,y
	SEP #$20
	LDA.l $7E4E91
	STA $0008,y
	REP #$20
	RTL
.native:
	LDA [$5D]
	STA $0006,y
	RTL

; $90CE05: palette restore for the Dog slot (A = $0E, Y = object). Hero mode: keep the hero palette.
HeroPalRestore:
	CPY #$4F37
	BNE .native
	PHA
	LDA.l $7E0AA0
	CMP #$0008
	BNE .nativePla
	PLA
	RTL
.nativePla:
	PLA
.native:
	PHX			; original instructions $90CE05-$90CE14
	PHY
	TAX
	LDA $0A79
	STA $1278,x
	JSL $90CF3A
	PLY
	PLX
	RTL

HeroDlgKey:
	LDA.l $7E0AA0
	CMP #$0008
	BNE .original
	LDA.l $7E00F8
	PHA
	LDA.l !DLGPREV
	EOR #$FFFF
	AND $01,s
	STA.l !DLGNEW
	PLA
	STA.l !DLGPREV
	LDA.l $7E00FA
	AND #$2F3F		; consume confirm/cancel (D0C0)
	STA.l $7E00FA
	LDA.l !DLGNEW
	ORA.l $7E00F6
	JML $F00961
.original:
	LDA $F2
	BIT #$000C
	JML $F0096A

HeroActor:
	LDA.l $7E00EA
	BNE .set
	LDA.l $7E0F42
.set:
	STA.l $7E00EC
	CMP #$4F37
	BNE .done
	LDA.l $7E0AA0
	CMP #$0008
	BEQ .hero
	LDA #$4F37
	BRA .done
.hero:
	LDA #$4E89
.done:
	STA $02			; as native (DP)
	RTL

; Apply damage ($CFC237): Y = target, +$76 = damage (the display keeps the full value, $CFC24C).
; If player 2 is active ($F2 bit 2/3) and the target is not the Boy/Dog, only 2/3 takes effect (the
; remainder is carried per target) -> same effect as 150 % HP, without changing the max. HP from the
; enemy record (healing, status displays, AI thresholds).
HeroDamage:
	LDA $0076,y
	PHA
	LDA.l $7E00F2
	AND #$000C
	BEQ .full
	CPY #$4E89
	BEQ .full
	CPY #$4F37
	BEQ .full
	TYA
	CMP.l !DMG_TGT
	BEQ .same
	STA.l !DMG_TGT
	LDA #$0000
	STA.l !DMG_REM
.same:
	PLA
	ASL			; damage * 2
	BCS .clamp
	CLC
	ADC.l !DMG_REM
	BCC .div
.clamp:
	LDA #$FFFF
.div:
	STA.l $004204		; dividend (hardware divider)
	SEP #$20
	LDA #$03
	STA.l $004206		; divisor 3: damage * 2/3 (150 % HP)
	REP #$20
	NOP #8			; wait 16 cycles
	LDA.l $004216		; remainder
	STA.l !DMG_REM
	LDA.l $004214		; quotient = effective damage
	PHA
.full:
	PLA
	STA.l !TMP_CUR
	LDA $002A,y
	SEC
	SBC.l !TMP_CUR
	BPL .ok
	LDA #$0000
.ok:
	STA $002A,y
	RTL

; --- Set the Dog slot's record/object to the hero with P2's weapon (every frame) ---
HeroEquip:
	LDA $23BF		; towns/interiors: unarmed like the Boy (take over his animations)
	BNE .unarmed
	LDA.l !P2W
	BNE .weapon
.unarmed:
	; without an own weapon: the Boy's animations, the Dog slot's stats stay
	LDX #$0000
.copy:
	LDA $0A58,x
	STA $0AA2,x
	INX
	INX
	CPX #$0018
	BCC .copy
	LDA $0A39
	STA $0A83
	BRL .common
.weapon:
	STA.l !TMP_SEL
	JSR WeaponRecord	; weapon table -> record (as $CF81C9)
	TAX
	LDA.l $C40006,x : STA $0A83	; +$13
	LDA.l $C40008,x : STA $0AA2	; +$32 standing
	LDA.l $C4000A,x : STA $0AA4	; +$34 walking
	LDA.l $C4000C,x : STA $0AA6	; +$36 running
	LDA.l $C4000E,x : STA $0AA8	; +$38 attack level 0
	LDA.l $C40010,x : STA $0AAA	; +$3A level 1
	LDA.l $C40012,x : STA $0AAC	; +$3C level 2
	LDA.l $C40014,x : STA $0AAE	; +$3E level 3
	LDA.l $C40016,x : STA $0AB8	; +$48
	LDA.l $C40018,x : STA $0AB0	; +$40
	LDA #$414E : STA $0AB6		; +$46 (as $CF8234)
	; attack = the Boy's base attack + power of P2's weapon (same strength with the same weapon)
	LDA $0ABA
	BEQ .baseUnarmed
	CMP #$001A
	BNE .baseWeapon
	LDA $1468		; Bazooka: $1468 = base attack + $12 ($CF8465)
	SEC
	SBC #$0012
	BRA .baseDone
.baseWeapon:
	JSR WeaponPower		; power of the Boy's weapon
	STA.l !TMP_POW
	LDA $0A3F
	SEC
	SBC.l !TMP_POW
	BRA .baseDone
.baseUnarmed:
	LDA $0A3F
.baseDone:
	STA.l !TMP_CUR
	LDA.l !TMP_SEL
	CMP #$001A
	BNE .attackWeapon
	JSR WeaponPower		; Bazooka: attack = power of the ammunition (Boy: $0A3F, $CF846F-$CF84AF)
	BRA .attackDone
.attackWeapon:
	JSR WeaponPower
	CLC
	ADC.l !TMP_CUR
.attackDone:
	STA $0A89
	LDA.l !TMP_SEL
	TAX
	; max. charge = weapon level * $400 (as $CF8265: level = low byte of $0ADE+selector)
	LDA $0ADE,x
	AND #$00FF
	XBA
	ASL
	ASL
	STA $0A9C
.common:
	LDA #$0008		; +$30 hit class "weapon" (handler $CFB75A)
	STA $0AA0
	LDA #$000E		; object +$0C: sprite palette 7 (own hero palette)
	STA $4F43
	LDA #$0E0E		; object +$74
	STA $4FAB
	RTS

; --- A = selector ($02..$1A). Returns A = weapon power as $CF8485: power (+ power/4 if $C459DC = 0) ---
WeaponPower:
	STA.l !TMP_START
	JSR WeaponRecord
	TAX
	LDA.l $C40000,x
	STA.l !TMP_STEP
	LDA.l !TMP_START
	CMP #$001A		; Bazooka: power of the ammunition without bonus
	BEQ .noBonus
	LDA.l !TMP_START
	TAX
	LDA.l $C459DC,x
	BNE .noBonus
	LDA.l !TMP_STEP
	LSR
	LSR
	CLC
	ADC.l !TMP_STEP
	RTS
.noBonus:
	LDA.l !TMP_STEP
	RTS

; --- Keep the hero palette in slot 7 (buffer $7E6369 = color 1); upload again on any difference ---
HeroPalette:
	LDA $23CD		; source as $CF8246
	BEQ .normal
	CLC
	ADC #$A7CB
	BRA .source
.normal:
	LDA $23BF		; unarmed: palette like the Boy
	BNE .boyPal
	LDA.l !P2W
	BEQ .boyPal
	JSR WeaponRecord
	TAX
	LDA.l $C40004,x		; weapon record +$04: palette (bank $D0)
	BRA .source
.boyPal:
	LDA $0A2F
.source:
	STA.l !TMP_SRC
	TAX
	LDA.l $D0000C,x		; color 6 of the source determines the body variant
	LDY #$0000
	CMP #$728B
	BNE .notA
	LDY.w #HeroRampA&$FFFF
.notA:
	CMP #$7EAA
	BNE .notB
	LDY.w #HeroRampB&$FFFF
.notB:
	CMP #$462D		; the Boy's map palette ($23CD = $60, Omnitopia, source $A82B)
	BNE .notC
	LDY.w #HeroRampC&$FFFF
.notC:
	TYA
	STA.l !TMP_VAR
	LDA #$0000
	STA.l !TMP_DIRTY
	LDY #$0000
.color:
	TYA
	CLC
	ADC.l !TMP_SRC
	TAX
	LDA.l $D00002,x		; color (Y/2 + 1) of the source
	CPY #$000A		; replace colors 6..11 (Y = $0A..$14)
	BCC .compare
	CPY #$0016
	BCS .compare
	PHA
	LDA.l !TMP_VAR
	BEQ .noVariant
	PLA
	TYA
	SEC
	SBC #$000A
	CLC
	ADC.l !TMP_VAR
	TAX
	LDA.l $FC0000,x		; replacement color (table in bank $FC)
	BRA .compare
.noVariant:
	PLA
	JSR HeroGenColor	; unknown palette: derive the hero color from the source color
.compare:
	CMP $6369,y
	BEQ .same
	STA $6369,y
	LDA #$0001
	STA.l !TMP_DIRTY
.same:
	INY
	INY
	CPY #$001E
	BCC .color
	LDA.l !TMP_DIRTY
	BEQ .end
	; upload as $90CFB8 -> $8085FA: source $7E6369, target CGRAM color $F1, 30 bytes
	PHB
	PEA $8080		; DB = $80 (PPU/DMA registers and low RAM reachable)
	PLB
	PLB
	LDA #$6369
	STA $26
	LDA #$007E
	STA $28
	LDA #$00F1
	STA $2E
	LDX #$001E
	JSL $8085FA
	PLB
.end:
	RTS

; --- Unknown source palette (no ramp): A = source color (BGR555), Y = $0A..$14 (colors 6..11).
;     Colors 6-8 (clothes) become grey of the same brightness ((r+g+b)*5/16), colors 9-11 (hair) blond:
;     red = brightest channel M, green = M - M/8 - 1, blue = M/8 (fits ramp A against the normal palette).
;     Returns A = hero color; Y preserved, X clobbered. ---
HeroGenColor:
	PHA
	AND #$001F
	STA.l !TMP_START	; r
	LDA $01,s
	LSR
	LSR
	LSR
	LSR
	LSR
	AND #$001F
	STA.l !TMP_STEP		; g
	PLA
	XBA
	LSR
	LSR
	AND #$001F
	STA.l !TMP_CNT		; b
	CPY #$0010
	BCS .hair
	CLC
	ADC.l !TMP_START
	ADC.l !TMP_STEP		; sum = r + g + b (max 93)
	STA.l !TMP_POW
	ASL
	ASL
	CLC
	ADC.l !TMP_POW		; *5
	LSR
	LSR
	LSR
	LSR			; /16
	CMP #$0020
	BCC .greyOk
	LDA #$001F
.greyOk:
	STA.l !TMP_POW
	ASL
	ASL
	ASL
	ASL
	ASL
	ORA.l !TMP_POW
	ASL
	ASL
	ASL
	ASL
	ASL
	ORA.l !TMP_POW		; grey | grey<<5 | grey<<10
	RTS
.hair:
	LDA.l !TMP_START	; M = max(r, g, b)
	CMP.l !TMP_STEP
	BCS .m1
	LDA.l !TMP_STEP
.m1:
	CMP.l !TMP_CNT
	BCS .m2
	LDA.l !TMP_CNT
.m2:
	STA.l !TMP_POW		; M
	LSR
	LSR
	LSR
	STA.l !TMP_CNT		; M/8 = blue
	LDA.l !TMP_POW
	SEC
	SBC.l !TMP_CNT
	DEC			; green = M - M/8 - 1
	BPL .gOk
	LDA #$0000
.gOk:
	ASL
	ASL
	ASL
	ASL
	ASL
	ORA.l !TMP_POW		; red | green<<5
	STA.l !TMP_STEP
	LDA.l !TMP_CNT
	XBA
	ASL
	ASL			; blue<<10
	ORA.l !TMP_STEP
	RTS

; Replacement colors 6..11 (BGR555): trousers grey, hair/vest blond/yellow
HeroRampA:			; body variant A (color 6 = $728B)
	dw $4E52, $358C, $1CC6, $0F7E, $1277, $11B1
HeroRampB:			; body variant B (color 6 = $7EAA)
	dw $5273, $2D4A, $1CC6, $0F9F, $131C, $1656
HeroRampC:			; dark map palette (color 6 = $462D): ramp A darkened per channel by the
	dw $31F5, $14E8, $0C86, $058F, $110B, $10C6	; ratio map palette / normal palette

; --- Weapon experience: a kill by the P2 hero is credited to P2's weapon ---
; Entry from the weapon hit handler ($CFB777), attacker in $4C, 16-bit, DB as the caller.
HeroExpCredit:
	LDA $4C
	CMP #$4F37
	BNE .native
	LDA.l $7E0AA0
	CMP #$0008
	BNE .native
	LDA.l !P2W
	BEQ .native
	LDA.l $7E0ABA		; save the Boy's selector and max. charge
	PHA
	LDA.l $7E0A52		; ($8F973E sets $0A52 on a weapon level-up)
	PHA
	LDA.l !P2W
	STA.l $7E0ABA
	JSL $C57410
	PLA
	STA.l $7E0A52
	PLA
	STA.l $7E0ABA
	RTL
.native:
	JML $C57410

; --- Message "P2: <weapon name>" via the native message system (as $8F973E) ---
; Requires D = 0, DB = $7E (set in HeroSync). Uses $22..$28 like the game.
HeroAnnounce:
	JSL $80B37A		; reserve a text buffer -> $22..$24
	LDA $22
	PHA
	LDA.w #HeroP2Text&$FFFF
	STA $26
	LDA #$00FC
	STA $28
	JSL $80B149		; copy "P2: ", Y = length
	TYA
	CLC
	ADC $22
	STA $22
	LDA.l !P2W
	JSR WeaponRecord	; Bazooka: name of the ammunition
	TAX
	LDA.l $C40002,x		; weapon record +$02: name (bank $C4)
	STA $26
	LDA #$00C4
	STA $28
	JSL $80B149
	PLA
	STA $22
	JSL $8CC521		; queue the message
	RTS

HeroP2Text:
	db "P2: ", $00

; --- Fixed message: A = text address in bank $FC (like HeroAnnounce, without a weapon name) ---
HeroMessage:
	PHA
	JSL $80B37A		; reserve a text buffer -> $22..$24
	PLA
	STA $26
	LDA #$00FC
	STA $28
	JSL $80B149
	JSL $8CC521		; queue the message
	RTS

HeroDogText:
	db "P2: Dog", $00

; --- End of saving: native instructions, then store P2's weapon for this slot ---
; Entry: A = checksum, DB = $30, $2E = slot base ($6002 + slot*$331), 16-bit.
HeroOnSave:
	LDX $2E
	STA $0000,x		; store the checksum (native)
	TXA
	SEC
	SBC #$6002
	LDY #$0000
.divide:
	CMP #$0331
	BCC .slot
	SBC #$0331
	INY
	BRA .divide
.slot:
	CPY #$0004
	BCS .end
	TYA
	ASL
	TAX
	LDA.l !KH_MAGIC
	CMP #$4B48
	BEQ .valid
	LDA #$FFFF		; P2 was never active: unknown
	BRA .write
.valid:
	LDA.l !P2W
.write:
	STA.l !SLOTTBL,x
.end:
	PLB			; native
	RTL

; --- End of loading: native STA $7E22EE, then take over P2's weapon of the loaded slot ---
; Entry: 16-bit A, DB = caller; $7E0B3B = slot*2 (index for $C4599A).
HeroOnLoad:
	STA.l $7E22EE		; native
	LDA.l $7E0B3B
	CMP #$0008
	BCS .end
	TAX
	LDA.l !SLOTTBL,x	; only a valid selector counts ($02..$1A, even); $FFFF = never saved with P2,
	CMP #$0002		; anything else = uninitialized SRAM: keep the current value
	BCC .end
	CMP #$001C
	BCS .end
	BIT #$0001
	BNE .end
	STA.l !P2W
	LDA #$4B48
	STA.l !KH_MAGIC
.end:
	LDA #$0000
	STA.l !P2RING
	RTL

; Entry: Dog controls, 16-bit A. Replaces LDA $00FC / BIT #$0030.
; Returns: A = Dog hold buffer (without L/R in hero mode), flags as BIT #$0030.
HeroSniffGate:
	LDA.l $7E0AA0
	CMP #$0008
	BNE .normal
	LDA.l $7E00FC
	AND #$FFCF
	BIT #$0030
	RTL
.normal:
	LDA.l $7E00FC
	BIT #$0030
	RTL

; $CFC68C: source of the right HUD avatar. Hero mode ($0AA0 = 8, hit class weapon): the Boy's avatar
; ($4EF7/$4EF9); the palette still comes from object +$0C of the Dog slot (= hero palette).
HeroAvatarSrc:
	LDA.l $7E0AA0
	CMP #$0008
	BNE .dog
	LDA.l $7E4EF7
	STA $26
	LDA.l $7E4EF9
	STA $28
	RTL
.dog:
	LDA.l $7E4FA5
	STA $26
	LDA.l $7E4FA7
	STA $28
	RTL
