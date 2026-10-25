# SoE_A-second-hero-instead-of-the-dog (beta 1) - technical notes

Goal: player 2 controls a second hero with the Boy's weapon mechanics. FuSoYa's existing two-player code stays in
place, and the original game logic is reused wherever possible. The hero takes the Dog's slot (object `$4F37`,
record `$0A70`); hero mode is active while `$0AA0 = 8`.

## Building

**Release (add-on, without Casual Run):**
```
python3 Build/make_addon.py "<Casual Run 2.0 ROM>" <output folder> --asar <asar 1.91>
```
Applies the three asar files to a Casual Run 2.0 ROM (4 MiB, or the 800 bytes shorter variant produced by
Floating IPS) and creates the ROM and the add-on IPS, which contains only the SoE_A-second-hero-instead-of-the-dog changes. The resulting ROM
has SHA-256 `82bea9f123ba0288720ec8eac8bf09512250c00a8bbccbec839e1367a610899c`.

The `.asm` files in `Build/` are the source.

## How it works

| Part | Address | Effect |
|---|---|---|
| Fix: two-player input | `$F0001F`, `$F00090`, `$F000E9` | FuSoYa's ROM title signature checks neutralized; without the fix, Casual Run 2.0 never reads controller 2 |
| `HeroSync` | `$FC8100`, hook `$CFD0A8` (Dog think dispatch) | While P2 controls the Dog (`$F2` bit 3), the Dog slot becomes the hero every frame: animations including attacks from the record of **P2's weapon** (`$C43874`), `+$30 = 8` (weapon hit handler), palette 7 (`+$0C = $0E`). When P2 leaves: `+$30 = $0A`, `$0A9C` restored from `$0B07`, Dog form via native `$8F946B` |
| Weapon choice | `HeroWeaponInput` | **L/R** (P2) cycles through the owned weapons `$02…$1A` (inventory as in `$CF927F`), including the Bazooka. Starts with the Boy's weapon |
| Combat stats | `HeroEquip` | Attack = the Boy's base attack (`$0A3F` − his weapon's power; Bazooka: `$1468 − $12`) + power of P2's weapon (formula `$CF8485`); max. charge = weapon level · `$400` (`$CF8265`). Same weapon ⇒ same strength as P1. In towns and interiors (`$23BF ≠ 0`) the hero is unarmed and uses the Boy's animations |
| Weapon experience | `HeroExpCredit`, hook `$CFB777` | Kill by the hero: save `$0ABA`/`$0A52`, set `$0ABA` = P2's weapon, call `$C57410`, restore |
| Own palette | `HeroPalette` | Source palette as for the Boy: map palette (`$23CD ≠ 0` → `$A7CB + $23CD`), otherwise P2's weapon (record `+$04`, bank `$D0`), unarmed `$0A2F`. Colors 6–11 are replaced by a hero ramp chosen by color 6 of the source (`$728B` → ramp A, `$7EAA` → ramp B, `$462D` → ramp C for the dark map palette `$A82B`; any other source palette: `HeroGenColor` derives the colors, clothes grey of the same brightness, hair blond). Written to buffer `$7E6369` and uploaded via `$8085FA` (as `$90CFB8`); checked every frame, so it also survives map changes |
| HUD avatar | hook `$CFC68C` → `HeroAvatarSrc` | In hero mode the right HUD shows the Boy's face (`$4EF7/$4EF9`) instead of the Dog's head; the palette still comes from the Dog slot (= hero palette) |
| Announcement | `HeroAnnounce` | "P2: <weapon>" on joining and on every change, via the native message system (`$80B37A`, `$80B149`, `$8CC521`, as `$8F973E`) |
| Saving per slot | hooks `$CDB470` (end of save), `$CDB7D1` (end of load) | `HeroOnSave` executes the native instructions (`LDX $2E / STA $0000,X / PLB / RTL`) and stores P2's weapon in the slot entry (slot from `$2E` = `$6002 + slot·$331`); `HeroOnLoad` (native `STA $7E22EE`) takes over the entry of the loaded slot (`$7E0B3B` = slot·2) |
| Fix: Ring input | `$F00328` (`fix_ring_pad.asm`) | FuSoYa selects the Ring's controller via `LDA $32F0`, but the Ring runs with DB = `$80` → open bus → always controller 1. Now `LDA.l $7E32F0` (verified at runtime: DB = `$80` at this point) |
| P2 Weapon Ring | `HeroWeaponInput`, hooks `$CE99D2`, `$CE91E8`, `$CEA49A`, `$CEE534` | **X** on controller 2 opens the native Weapon Ring (requested as in native `$CFCE01`: owner Dog, `$05A9` bit 2; window as in Casual Run `$F50200`). Cursor on P2's weapon, preview "old → new" against P2's weapon. Confirming (twice, as native) writes `!P2W` instead of `$2441`; the Boy's weapon stays. Only while flag `$307F04` is set, the owner is `$4F37`, and hero mode is active |
| P2 Ring order | `HeroRingList` | Ring order for P2 = Weapons (ID 4), Alchemy (ID 2), Items (ID 8), written to `$0806–$080D` (behind the at most 9 entries of the alchemy list, `$CE9B3A`; bank `$8E` mirrors low RAM). Up/down switches; the Ring remembers the last position (Dog `+$90`). Items and alchemy run fully native, including target selection and ingredient use; the P2 hero casts the formula. Status/options remain player 1's |
| Enemies 150 % | hook `$CFC237` → `HeroDamage` | While P2 is active (`$F2` bit 2/3), damage to all targets except Boy/Dog is reduced to 2/3 (damage × 2 / 3); the remainder is carried per target, and the damage number shows the full value. Effect = 150 % HP without changing the max. HP from the enemy record (used by healing, regeneration, and status displays: `$CFC0AC`, `$D1A61E`, `$D1B181` …). Applies from the first hit while P2 is active |
| Bazooka | `WeaponRecord`, hook `$CE9224` | `$1A` selectable (L/R and Ring). Record = ammunition `$C4388E[$2349]` as in `$CF81CE`; attack = power of the ammunition as for the Boy (`$CF846F`). In the Ring the Bazooka leads to the ammunition ring as native; its confirmation (`$CE9221`: `$2349`, `$2441 = $1A`) sets P2's weapon instead of the Boy's in P2's Ring. Ammunition type `$2349` and ammunition supply are shared |
| Gourds and chests | hook `$F00580` → `HeroActor` | Gourd/chest scripts check "acting character == Boy" (script `$0771`: expression `50 29 52 22`; `$52` = FuSoYa operand "acting character" `$EA`/`$0F42`). In hero mode the operand returns the Boy for the Dog slot; `$EC` (controller assignment for dialogue input) stays the real character. Loot goes to the shared inventory. As the Dog (Y) unchanged |
| Dialogues | hooks `$F00965` → `HeroDlgKey`, `$F0072D` → `HeroUnfreezeActor`; `HeroSync` | In hero mode, dialogue pages advance only on newly pressed controller-2 buttons, and the confirm/cancel bits in `$FA` are consumed (before, held buttons skipped pages and the hero talked to the NPC again 2–3 times). "Release character" treats the hero in the Dog slot as the Boy, like "halt character" (`$F00580`); otherwise the Boy stayed frozen after the hero's conversation. While a dialogue is open (`$4E99` bit 5), P2's action buttons are masked |
| Knock-out | hook `$90CE05` → `HeroPalRestore`; `HeroDeadPose` in `HeroSync` | After the collapse the game reloads the Dog's palette into slot 7 (`$90CDDC`); in hero mode this is skipped, so the hero falls in his own colors (his collapse is the Boy's, record `+$46`). The first `HeroSync` call after the collapse still sees its last frame: it is stored (`$307F26/28`) and held (frame timer `+$05` = `$7F`) while HP = 0, P2's input is ignored. Without this the hero stood up again and, after any Ring, showed the Dog's lying pose |
| Script poses (inn) | hooks `$CFCC1E` → `HeroScriptPose`, `$908421` → `HeroFrameSet` | While a script plays a Dog animation on the hero (object `+$10` bit `$40`, frame not in bank `$CA`, e.g. sleeping at an inn), the hero shows the Boy's current frame (`+$06..+$08`): the think prolog copies it every frame, and the frame opcode `$2n` stores it instead of the Dog's frame. The Boy's script state is not copied |
| Hero/Dog | `HeroToggleInput`, `HeroSync` | **Y** on controller 2 switches between hero and Dog ("P2: Dog" or "P2: <weapon>"). If the Boy is absent (`$2261` bit 1; native: Boy HUD off at `$CFC648`), hero mode pauses automatically and P2 controls the Dog; afterwards the hero returns. As the Dog, L/R work natively (sniffing) and X opens no Ring. The toggle is reset when P2 leaves |
| `HeroSniffGate` | hook `$CFCFA2` | In hero mode, no L/R special path of the Dog controls |

### State in SRAM

`$307F00` "HK" signature, `$307F02` P2's weapon (live value), `$307F04` flag "Ring belongs to P2", `$307F06` Dog
toggle, `$307F40…$307F47` P2's weapon per slot (`$FFFF` = never saved with P2), `$307F10…` scratch values.
SRAM offset `$1F00` lies behind the four save slots (`$0002…$0CC5`): at runtime, accesses only reach `$0A33`, and in
a save file used for years `$0CC6…$1FFF` is still `$FF`. P2's weapon is stored per slot on saving and restored on
loading (test: save at Strong Heart, change the live value, reset, load the slot → saved value).

## Verified findings (emulator)

- Graphics come from the animation script (frame opcode `$2n` → bank `$A8+n`); the palette comes from object field
  `+$0C` (`$06` in the sprite setup `$C09390`): Boy `$0C` (palette 6), Dog `$0E` (palette 7).
- Object `+$60` → record: Boy `$0A26`, Dog `$0A70`.
- An attack by the P2 hero with the Bone Crusher animation deals damage (enemy 30 → 0).
- Ring: ring order `[$97]` (bank `$8E`), entry = Ring ID; `$8E9920,ID` → list variable (ID 4 → `$07A4` count,
  `$07A6` cursor, `$07A8…` icons). Owner `+$90` = position in the order. Native weapon selection:
  `$CE91AC` → `$2441` → `$CF9210` sets `$0ABA`. After cancelling, `$05A9` bit 15 natively stays set.
- Without `HeroExpCredit`, a kill by P2 credits weapon experience to `$0ABA` (the Boy's weapon) – existing Casual Run
  behavior (`$C57410`).

## Known limitations

1. **Stats:** attack and charge as above; HP, defense, evasion, level, and character experience remain the Dog
   slot's. Charge rate `+$2E` is fixed at `$000A` for both.
2. **Delayed return:** `HeroSync` runs in the think dispatch; during hit animations it is not called (measured up to
   ~90 frames). On map changes, the Dog's form is visible for one frame.
3. **Dog-specific places:** automatic only where the game marks the Boy as absent (`$2261` bit 1).
   [Hypothesis] The Dog mazes and the Pyramid set this bit; not verified without a matching save file. Fallback: Y
   (controller 2). Tested in the emulator: switching and the pause with the bit set, not an actual sniff spot.
4. **Bazooka:** the ammunition type is shared (one variable `$2349`). If P1 selects different ammunition, P2 fires it too.
5. **Idle animations:** movement and idle animations still run through the Dog controls; the Boy's idle
   in-between animations (`$1460–$1466`) do not exist for the hero.
8. **Knock-out edge cases:** switching to the Dog (Y) while the hero is knocked out shows the hero's lying frame in Dog colors for about two seconds before the Dog's lying pose; on the game-over screen the second hero appears as the lying Dog.

Earlier assumption "attack only with a target" – **disproved** (emulator test): without an enemy, the hero
swings into empty air like the Boy (swing script `$C7146x`, `+$12 = $0800`). Button presses during a running swing
animation are lost – as for the Boy.

## Tests

The add-on was checked with automated emulator tests (headless MesenCE with Lua scripts). They depend on a custom emulator build and private save files, so they are kept in the development repository and are not part of the release.

