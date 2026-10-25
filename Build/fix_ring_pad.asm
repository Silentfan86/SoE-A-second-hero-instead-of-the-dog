; Secret of Evermore: Casual Run -- fix for Ring input (FuSoYa two-player code)
; Assembler: asar 1.91 (hirom). Applied after fix_p2_signature.asm.
;
; Finding (code + runtime, MesenCE): $F00328 selects the controller for the Ring via "LDA $32F0".
; The Ring runs with DB = $80; $80:32F0 is not WRAM (the low-RAM mirror only covers $0000-$1FFF),
; so it reads open bus (non-zero) -> always controller 1 ($F6). A Ring owned by player 2
; (owner Dog, $32F0 = 0) was therefore operated by player 1.
; Fix: long access to $7E32F0. Same logic, 13 instead of 12 bytes (the following bytes up to $F00334
; were unused zeros; the only reference is JMP $0328 at $F00962).

hirom

org $F00328
RingPadSelect:
	LDA.l $7E32F0		; was LDA $32F0 (depends on DB)
	BEQ .p2
	LDA $F6			; controller 1, pressed
	BRA .done
.p2:
	LDA $FA			; controller 2, pressed
.done:
	RTS
assert pc() <= $F00335
