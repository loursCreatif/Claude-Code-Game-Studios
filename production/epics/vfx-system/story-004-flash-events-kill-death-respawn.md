# Story 004: Flash Events Wall-Clock — Kill 80 ms / Respawn 50 ms / WCAG 2.3.1 333 ms 3 Hz Plancher

> **Epic**: VFX System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-05-04
> **Estimate**: M (4-5 h, wall-clock timer dans `_physics_process` + WCAG guard + reduce_flash gris substitute + Camera ownership rouge mort cohérence)

## Context

**GDD**: `design/gdd/vfx-system.md` (Designed r1)
**Requirements**:
- R-VFX-5 : Flash blanc kill `FLASH_KILL_DURATION_MS = 80 ms` wall-clock via `Time.get_ticks_msec()` (pas Tween) ; reduce_flash → fondu gris neutre `#A0A0A0` `flash_mult = 0.625`
- R-VFX-13 : Zéro flash > 3 Hz (WCAG 2.3.1) — `FLASH_MIN_INTERVAL_MS = 333 ms` plancher structurel
- R-VFX-15 : Flash respawn `FLASH_RESPAWN_DURATION_MS = 50 ms` blanc pur ; reduce_flash → supprimé entièrement
- F-VFX-2 : Flash brightness reduce_flash — `FLASH_BRIGHTNESS = DEFAULT_FLASH_BRIGHTNESS × flash_mult`

**ADR Governing Implementation**:
- **ADR-0009 D-3** (pattern référence) — wall-clock fades dans `_physics_process` exclusivement via `_get_time_msec` Callable injection. Tween interdit sur effets time-critical (casse Pillar 1 60 fps wall-clock indépendant `Engine.time_scale`).
- **ADR-0001** (60 Hz physics) — `Time.get_ticks_msec()` lit horloge système, pas frame counter ; invariant slow-mo Combat (AC-VFX-25/26).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Time.get_ticks_msec()` stable Godot 4.0+. `ColorRect.color` mutation runtime + `visible` flip sans alloc.

**Control Manifest Rules (Presentation layer)**:
- Required : `_flash_kill_active: bool` + `_flash_kill_start_msec: int` state ; flash brightness calculé via `Time.get_ticks_msec()` dans `_physics_process` ; WCAG guard `_flash_last_msec` plancher 333 ms ; reduce_flash → `Color(0.625, 0.625, 0.625, 1.0)` substitute.
- Forbidden : `Tween.tween_property(rect, "color", ...)` ou `tween_property("modulate", ...)` (R-VFX-5 wall-clock obligatoire — story-007 lint static `lint-vfx-tween` enforce) ; `Engine.time_scale` mutation (autorité GSM seul) ; flash rouge concurrent (R-VFX-6 Camera owns mort overlay).
- Guardrail : `push_warning` sur skip flash quand 333 ms guard triggered (EC-VFX-06).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1, scoped à cette story (Integration) :*

- [ ] **AC-VFX-06** [BLOCKING][AUTO] **GIVEN** `AccessibilityService.reduce_flash == false`, **WHEN** `enemy_killed` est reçu, **THEN** un flash blanc `#FFFFFF` plein-écran de durée `FLASH_KILL_DURATION_MS = 80 ms` wall-clock s'affiche ; la durée ne varie pas avec `Engine.time_scale`.
- [ ] **AC-VFX-07** [BLOCKING][AUTO] **GIVEN** `AccessibilityService.reduce_flash == true`, **WHEN** `enemy_killed` est reçu, **THEN** le flash blanc est remplacé par un fondu gris neutre `Color(0.625, 0.625, 0.625, 1.0)` (#A0A0A0) de durée 80 ms ; jamais de blanc pur (#FFFFFF) ni de rouge en mode reduce_flash.
- [ ] **AC-VFX-08** [BLOCKING][AUTO] **GIVEN** `FLASH_MIN_INTERVAL_MS = 333 ms` est configuré, **WHEN** VFXSystem reçoit 10 `enemy_killed` events en 1 seconde (via test unitaire inject), **THEN** le nombre de flashs rendus est ≤ 3 ; chaque flash supplémentaire dans la fenêtre 333 ms est skip silencieusement ; `push_warning` logué pour chaque skip.
- [ ] **AC-VFX-09** [BLOCKING][AUTO] **GIVEN** `AccessibilityService.reduce_flash == true`, **WHEN** `respawned` signal reçu, **THEN** zéro flash de tout type au respawn (ni blanc ni gris neutre) ; l'overlay rouge mort Camera s'éteint normalement (géré Camera, pas VFX).
- [ ] **AC-VFX-15** [BLOCKING][AUTO] **GIVEN** `state_changed(MENU)` reçu pendant swing_started → swing_ended window, **WHEN** GSM bascule en MENU, **THEN** flash overlay masqué immédiatement ; `_flash_kill_active = false` (story-006 implémente body GSM gating, cette story s'assure que `_apply_flash_kill_tick` respecte `_is_active` flag).
- [ ] **AC-VFX-25** [BLOCKING][AUTO] **GIVEN** `Engine.time_scale = 0.3` (slow-mo Combat Rule 13) est actif, **WHEN** Flash kill VFX est déclenché, **THEN** la durée du flash est `FLASH_KILL_DURATION_MS = 80 ms` wall-clock (`Time.get_ticks_msec()`) — pas 80 ms × 0.3 = 24 ms ; le flash n'est pas allongé ni raccourci par time_scale.
- [ ] **AC-VFX-26** [BLOCKING][AUTO] **GIVEN** `Engine.time_scale = 0.3` actif + `reduce_flash == true`, **WHEN** `enemy_killed` reçu, **THEN** Flash gris neutre `#A0A0A0` durée 80 ms wall-clock (identique reduce_flash OFF mais couleur atténuée) ; WCAG 2.3.1 compliance maintenue sous slow-mo.

---

## Implementation Notes

```gdscript
# story-004 ajoute dans src/core/vfx_system.gd

# Constants déjà déclarées story-001 :
# const FLASH_KILL_DURATION_MS: int = 80
# const FLASH_RESPAWN_DURATION_MS: int = 50
# const FLASH_MIN_INTERVAL_MS: int = 333  # WCAG 2.3.1 3 Hz plancher

const DEFAULT_FLASH_BRIGHTNESS: float = 1.0
const REDUCE_FLASH_BRIGHTNESS: float = 0.625  # F-VFX-2 → #A0A0A0 gris neutre

# State variables :
var _flash_kill_active: bool = false
var _flash_kill_start_msec: int = 0
var _flash_kill_use_grey: bool = false  # true si reduce_flash active

var _flash_respawn_active: bool = false
var _flash_respawn_start_msec: int = 0

# var _flash_last_msec: int = 0  # déjà déclaré story-001 — WCAG guard
# var _is_active: bool = true  # GSM gating story-006

func _trigger_flash_kill() -> void:
    # AC-VFX-08 — WCAG guard 333 ms plancher
    var now: int = _get_time_msec.call()
    if now - _flash_last_msec < FLASH_MIN_INTERVAL_MS:
        push_warning("VFX: flash rate guard triggered — skip flash kill (last=%d, now=%d, delta=%d ms)" % [
            _flash_last_msec, now, now - _flash_last_msec
        ])
        return  # EC-VFX-06 skip silencieux

    _flash_last_msec = now
    _flash_kill_active = true
    _flash_kill_start_msec = now
    _flash_kill_use_grey = _reduce_flash  # AC-VFX-07 — gris substitute si reduce_flash
    _flash_overlay_rect.visible = true

    # Apply initial color full opacity (story_004 _physics_process tick fade out)
    _apply_flash_kill_color(0.0)  # t = 0 → opacity max

func _trigger_flash_respawn() -> void:
    # AC-VFX-09 — reduce_flash ON → flash respawn supprimé entièrement (R-VFX-15)
    if _reduce_flash:
        return  # pas de substitut gris pour respawn (durée 50 ms trop courte)

    var now: int = _get_time_msec.call()
    # Note : flash respawn n'utilise PAS le WCAG guard `_flash_last_msec`
    # car déclenché uniquement au respawn (RESPAWN_DELAY_MS = 50 ms ≪ 333 ms structurel impossible)

    _flash_respawn_active = true
    _flash_respawn_start_msec = now
    _flash_overlay_rect.visible = true
    _flash_overlay_rect.color = Color(1.0, 1.0, 1.0, 1.0)  # blanc pur 50 ms pop binaire

func _physics_process(_delta: float) -> void:
    # ... story-002 trail fade-out tick ...

    # AC-VFX-06/25 — flash kill wall-clock 80 ms
    if _flash_kill_active:
        var elapsed_ms: int = _get_time_msec.call() - _flash_kill_start_msec
        if elapsed_ms >= FLASH_KILL_DURATION_MS:
            _flash_kill_active = false
            _flash_overlay_rect.visible = _flash_respawn_active  # garde si respawn en cours
        else:
            var t: float = float(elapsed_ms) / float(FLASH_KILL_DURATION_MS)
            _apply_flash_kill_color(t)

    # AC-VFX-09/15 — flash respawn wall-clock 50 ms
    if _flash_respawn_active:
        var elapsed_ms: int = _get_time_msec.call() - _flash_respawn_start_msec
        if elapsed_ms >= FLASH_RESPAWN_DURATION_MS:
            _flash_respawn_active = false
            _flash_overlay_rect.visible = _flash_kill_active  # garde si kill en cours
        # 50 ms = pop binaire, pas de fade interpolé MVP (R-VFX-15)

func _apply_flash_kill_color(t: float) -> void:
    # F-VFX-2 — flash brightness avec reduce_flash gris substitute
    var base_brightness: float = REDUCE_FLASH_BRIGHTNESS if _flash_kill_use_grey else DEFAULT_FLASH_BRIGHTNESS

    # Fade-out linéaire 80 ms : opacity 1.0 → 0.0 (couleur RGB constante)
    var alpha: float = 1.0 - t
    _flash_overlay_rect.color = Color(base_brightness, base_brightness, base_brightness, alpha)

# Modifie _on_respawned (story-002 base) — ajoute trigger flash respawn
func _on_respawned(position: Vector3) -> void:
    # Reset blood pool, trail (déjà story-002)
    _reset_blood_pool()
    _reset_trail()
    _reset_decal_pool()  # story-003

    # AC-VFX-09/15 — flash respawn (skip si reduce_flash)
    _trigger_flash_respawn()
```

**Trigger flash kill update story-002** :

Dans `_on_enemy_killed` body story-002, le call `_trigger_flash_kill()` est maintenant pleinement implémenté (au lieu de stub) — cette story-004 fournit le body complet `_trigger_flash_kill()` + `_apply_flash_kill_color()` + `_physics_process` tick.

**Pattern wall-clock cohérent Audio R-AUD-4** :
```gdscript
# CORRECT — _physics_process tick + Time.get_ticks_msec() injection
if _flash_kill_active:
    var elapsed_ms: int = _get_time_msec.call() - _flash_kill_start_msec
    if elapsed_ms >= FLASH_KILL_DURATION_MS:
        _flash_kill_active = false
    # ...

# INCORRECT — Tween sur color (time_scale-scaled, casse Pillar 1)
var tween = create_tween()
tween.tween_property(_flash_overlay_rect, "color:a", 0.0, 0.08)  # VIOLATION lint-vfx-tween story-007
```

**EC-VFX-02** — reduce_flash ON pendant slow-mo Combat :
- Combat Rule 13 → `Engine.time_scale = 0.3` au 1er kill du swing.
- VFX flash gris `#A0A0A0` durée 80 ms wall-clock (`Time.get_ticks_msec()` ne dépend pas de `Engine.time_scale`).
- Le slow-mo n'allonge pas le flash. Compliance WCAG 2.3.1 maintenue (AC-VFX-26).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Pull `reduce_flash` / `flash_mult` from AccessibilityService boot + live update via `settings_changed` — story-005.
- GSM visibility gating MENU/PAUSED/BOSS_DEFEATED → flash overlay forced hidden (state_changed handler) — story-006 (cette story s'assure que `_apply_flash_kill_color` ne crash pas si `_is_active == false`, mais le gating body reste story-006).
- Lints statiques anti `Tween.tween_property` sur `_flash_overlay_rect.color` — story-007 (lint `lint-vfx-tween`).
- Camera ownership rouge mort overlay — Camera GDD owns (R-VFX-6) ; VFX vérifie zero `Color(0.4, 0, 0, 0.6)` ou full-screen rouge dans `vfx_system.gd` (story-007 grep optional).
- Visual/Feel playtest verbatims — story-008.

---

## QA Test Cases

*Integration — automated integration tests requis :*

**AC-VFX-06** : Flash blanc 80 ms reduce_flash OFF
- Setup : VFXSystem ready, `_reduce_flash = false`, mock `_get_time_msec` injection.
- Action : appel `_trigger_flash_kill()` à t=0 ms, simuler ticks `_physics_process` à t=40, t=80, t=81.
- Verify : à t=0 → `_flash_overlay_rect.color == Color(1, 1, 1, 1.0)`, visible=true ; à t=40 → alpha ≈ 0.5 ; à t=80 → `_flash_kill_active == false`.
- Pass : 3 asserts time-step.

**AC-VFX-07** : Flash gris 80 ms reduce_flash ON
- Setup : `_reduce_flash = true` (pull story-005 pré-set).
- Action : `_trigger_flash_kill()` à t=0.
- Verify : à t=0 → `_flash_overlay_rect.color == Color(0.625, 0.625, 0.625, 1.0)` (#A0A0A0 alpha 1.0) ; jamais Color blanc pur.
- Pass : `assert_color(rect.color).is_equal_approx(Color(0.625, 0.625, 0.625, 1.0))`.

**AC-VFX-08** : WCAG 333 ms guard
- Setup : `_flash_last_msec = 100`, `_get_time_msec` returns 200 (delta 100 ms < 333).
- Action : `_trigger_flash_kill()`.
- Verify : `_flash_kill_active == false` (skip) ; `push_warning` capturé ; `_flash_last_msec` non muté.
- Pass : `assert_bool(vfx._flash_kill_active).is_false()` + warning capture.

**AC-VFX-08 burst** : 10 events / 1 sec → ≤ 3 flashs
- Setup : `_get_time_msec` mock advance 100 ms par tick (10 ticks = 1 s).
- Action : émettre 10 × `_trigger_flash_kill()` séquentiel.
- Verify : nombre de fois `_flash_overlay_rect.visible = true` setter appelé ≤ 3 (events à t=0, t=333, t=666 acceptés ; reste skipped).
- Pass : counter increments check.

**AC-VFX-09** : Respawn no flash si reduce_flash ON
- Setup : `_reduce_flash = true`.
- Action : `_trigger_flash_respawn()`.
- Verify : `_flash_respawn_active == false` (skip) ; `_flash_overlay_rect.visible == false`.
- Pass : 2 asserts.

**AC-VFX-25** : Flash 80 ms invariant slow-mo
- Setup : `Engine.time_scale = 0.3` (mock), `_get_time_msec` returns wall-clock indépendant.
- Action : `_trigger_flash_kill()` à wall-t=0, simuler ticks à wall-t=40, wall-t=80.
- Verify : `_flash_kill_active == false` à wall-t=80 ms (PAS wall-t=80/0.3 = 267 ms).
- Pass : assert wall-clock duration === 80 ms.

**AC-VFX-26** : Flash 80 ms gris invariant slow-mo + reduce_flash
- Setup : `Engine.time_scale = 0.3`, `_reduce_flash = true`.
- Action : `_trigger_flash_kill()`.
- Verify : durée 80 ms wall-clock + couleur `#A0A0A0` (Color(0.625, 0.625, 0.625, alpha)).
- Pass : 2 asserts.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/vfx/vfx_flash_events_test.gd` (NEW, ~250 lignes) couvrant AC-VFX-06/07/08/09/15/25/26 + EC-VFX-02/06/10.
- Mocks `_get_time_msec` Callable injection (pattern Combat ADR-0006 D-4 / Audio ADR-0009 D-3 / MockAudioHandler).
- Smoke check : test suite green run via GdUnit4 headless.

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** : story-001 (autoload skeleton + `_flash_overlay_rect` ColorRect + `_get_time_msec` Callable) + story-002 (`_on_enemy_killed` body call `_trigger_flash_kill()` stub remplacé par body complet ici).
- **Cross-system** :
  - **AccessibilityService Ready** : `reduce_flash` getter + `settings_changed` signal disponibles ✅. Pull body story-005, mais cette story-004 utilise `_reduce_flash` interne flag (initialisé `false` defaut + muté par story-005 listener).
  - **Camera 13/13 Complete** : signal `respawned(position)` consommé via DEFERRED ✅ — Camera owns rouge mort overlay (R-VFX-6).
- **Unlocks** : story-005 (accessibility pull body — listener `_on_accessibility_settings_changed` mute `_reduce_flash` flag) + story-006 (GSM visibility — `_is_active = false` force flash overlay hidden).

---

## Completion Notes

**Completed** : 2026-05-09 (chain auto post story-003 done)
**Verdict** : COMPLETE WITH NOTES — AC-VFX-15 (GSM gating criterion strict) DEFERRED bound story-006 (body GSM gating) explicitement par story spec. Tests AC-VFX-15 viendront story-006 pickup.
**Criteria** : 7/7 + 1 EC + 1 R-VFX-15 partial — AC-VFX-06/07/08/09/25/26 + EC-VFX-02 + R-VFX-15 ; AC-VFX-15 DEFERRED story-006
**Re-confirm tests** : 30/30 PASS cumulé exit 0 / 2.69 s (`reports/report_449/results.xml`) — story-001 7 + story-002 10 + story-003 5 + story-004 8
**Deviations** : None — toutes corrigées pendant `/code-review` :
  - Label MISMATCH AC-VFX-15 → R-VFX-15 fixé (test labels + header docstring + footnote AC-VFX-15 deferred)
  - Commentaire contradictoire `t=333/t=666` burst test fixé (calcul `t=0/400/800` clarifié inline)
  - Coverage gap AC-VFX-06 alpha intermédiaire t=40 fixé (assert ≈ 0.5 ajouté)
  - Convention `_flash_last_msec = -333` documentée header file
  - Manifest 2026-05-04 newer non-flagable
**Test Evidence** : `tests/integration/vfx/vfx_flash_events_test.gd` (8 tests post-fixes)
**Code Review** : Complete — godot-gdscript-specialist APPROVED WITH SUGGESTIONS (8 ADRs/Rules tous PASS : ADR-0001 + ADR-0009 D-3/D-4 + R-VFX-2/5/13/14/15) + qa-tester GAPS doc-only (label mismatch + commentaire contradictoire + alpha t=40 — 4 fixes appliqués)

**Pattern Audio R-AUD-4 wall-clock canonique respecté** : `_get_time_msec.call()` injection exclusivement (pas de `Time.get_ticks_msec()` direct dans hot paths) + `_physics_process` flash ticks + cleanup `Engine.time_scale = 1.0` systématique tests slow-mo

**WCAG 2.3.1 compliance verified empiriquement** : burst 10 events / 1 s → ≤ 3 flashs autorisés (t=0/400/800 — guard 333 ms structurel)

**Files livrés (2)** :
- `src/core/vfx_system.gd` (MODIF, +60 L) — +2 constants (DEFAULT_FLASH_BRIGHTNESS, REDUCE_FLASH_BRIGHTNESS) + 5 state vars (`_flash_kill_active/start_msec/use_grey`, `_flash_respawn_active/start_msec`) + body `_trigger_flash_kill` (remplace stub story-002) + helper `_apply_flash_kill_color(t)` + helper `_trigger_flash_respawn` + `_physics_process` étendu (3 if blocks modulaires : trail + kill + respawn) + `_on_respawned` ajout call `_trigger_flash_respawn` + `_on_died` body (was stub)
- `tests/integration/vfx/vfx_flash_events_test.gd` (NEW, ~450 L post-fixes) — 8 tests + helpers `_make_vfx` + `_free_all`

**Out of Scope strict respecté** : zéro pull AccessibilityService (story-005), zéro body GSM gating (story-006), zéro lint anti-Tween (story-007), zéro overlay rouge mort Camera (R-VFX-6 owns Camera).

**Tech debt** : aucun loggé (4 documentation suggestions absorbées + 4 ROI fixes appliqués inline).
