; Secret of Evermore: Casual Run -- fix for two-player input
; Assembler: asar 1.91 (hirom). Standalone bug fix, independent of the SoE_A-second-hero-instead-of-the-dog changes.
;
; FuSoYa's two-player code compares three words of the ROM title ($FFCD/$FFCF/$FFD1, DB=$80)
; with "Fu"/"So"/"Ya". Since the title became "SoE Casual Run", these comparisons fail:
;  - $F0001C: controller 2 is never read ($F8/$FA stay 0)
;  - $F0008D: join/HUD logic is skipped
;  - $F000E6: Start on controller 2 is ignored
; Verified in the emulator (MesenCE): without the fix $F2 stays $0011; with the signature in ROM
; memory, P2 joins ($F2=$0019) and controls the Dog.
; Minimal fix: CMP #imm -> CMP abs on the same address (comparison always equal). The title stays.
; Side effect: FuSoYa's player icons next to the HP bars are drawn again.

hirom

; ---------------------------------------------------------------------------
; 1. Neutralize the signature comparisons (FuSoYa)
; ---------------------------------------------------------------------------
org $F0001F
	CMP $FFCD		; was CMP #$7546 ("Fu"): read controller 2
org $F00090
	CMP $FFCF		; was CMP #$6F53 ("So"): join/HUD logic
org $F000E9
	CMP $FFD1		; was CMP #$6159 ("Ya"): Start on controller 2

