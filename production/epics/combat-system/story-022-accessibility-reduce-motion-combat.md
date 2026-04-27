# Story 022: Accessibility `reduce_motion` Combat impact

> **Epic**: Player Combat System
> **Status**: Blocked
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

> **BLOCKED**: ADR Accessibility Interface Layer non écrit (Gap G-4 post-MVP). TR-cmb-016 attend décision architecturale mutualisée Movement/Camera/Combat/VFX. Échéance : Polish phase / Tier 3 Full Vision. Story-013 implémente déjà la branche de code (`_reduce_motion_disable_slow_mo` flag) mais le wire au settings handler accessibility est BLOCKED.

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-016` (accessibility toggles `reduce_motion` impact Combat)

**ADR Governing Implementation**: ADR Accessibility Interface Layer (planned, post-MVP)
**ADR Decision Summary**: 3 toggles cross-system gérés par interface Accessibility :
- `reduce_motion_slow_mo_scale_mult ≥ 1.0` (bornes [1.0, 3.33]) — atténue slow-mo (multiplie SLOW_MO_SCALE par mult, ramène vers 1.0)
- `reduce_motion_disable_slow_mo: bool` — toggle complet désactivation
- `reduce_motion_flash_mult ∈ [0.0, 1.0]` — atténue VFX flash alpha (owned VFX, contract Combat→VFX)

Sémantique r1 = "atténuer" (mult ≥ 1.0).

**Engine**: Godot 4.6 | **Risk**: LOW (logic) / MEDIUM (interface architecture pendante)
**Engine Notes**: aucun engine-specific. Settings persistence via Foundation Save/Load (BLOCKED ADR-0014 post-MVP).

**Control Manifest Rules (Feature layer)**:
- Required: lecture flags accessibility via interface centralisée (pas `combat_system._reduce_motion_disable_slow_mo` exposé public)
- Forbidden: hard-code accessibility logic spécifique Combat — utiliser interface ADR Accessibility
- Guardrail: 0 effect quand toutes valeurs default (mult=1.0, disable=false, flash=1.0) — invariant

---

## Acceptance Criteria

*From GDD AC-CMB-19 r6 branche C + AC-CMB-16 r1 + Section G accessibility :*

- [ ] **AC-CMB-19 r6 branch C (déjà couvert story-013)** : `_reduce_motion_disable_slow_mo == true` → 1er kill ne mute PAS `Engine.time_scale` (5 kills consécutifs vérifiés `time_scale == 1.0`, `_slow_mo_active == false`)
- [ ] `reduce_motion_slow_mo_scale_mult ∈ [1.0, 3.33]` (bornes safe range) → `effective_slow_mo_scale = clampf(SLOW_MO_SCALE * mult, 0.0, 1.0)` ; mult=1.0 → 0.3 (default), mult=2.0 → 0.6 (atténuation 50%), mult=3.33 → 1.0 (équivalent disable)
- [ ] `reduce_motion_flash_mult ∈ [0.0, 1.0]` → contract Combat→VFX : `enemy_killed` émis avec metadata `flash_intensity = mult` (ou flag séparé) — VFX System scale alpha en conséquence
- [ ] **Interface Accessibility centralisée** : Combat lit ces 3 valeurs via `AccessibilityService.get_reduce_motion_settings()` (pas variables exportées per-system)
- [ ] **Defaults** : mult_scale=1.0, disable=false, flash_mult=1.0 → comportement Combat identique au MVP non-accessibility (invariant test)

---

## Implementation Notes

*Derived from GDD AC-CMB-19 r6 + Section G accessibility :*

```gdscript
# Combat lit l'interface (BLOCKED ADR Accessibility)
var _reduce_motion_disable_slow_mo: bool = false
var _reduce_motion_slow_mo_scale_mult: float = 1.0
var _reduce_motion_flash_mult: float = 1.0

func _ready() -> void:
    var settings := AccessibilityService.get_reduce_motion_settings()  # ADR Accessibility pendant
    _reduce_motion_disable_slow_mo = settings.disable_slow_mo
    _reduce_motion_slow_mo_scale_mult = clampf(settings.slow_mo_scale_mult, 1.0, 3.33)
    _reduce_motion_flash_mult = clampf(settings.flash_mult, 0.0, 1.0)
    # Reconnect on settings change
    AccessibilityService.settings_changed.connect(_on_accessibility_settings_changed)

func _trigger_slow_mo_if_first_kill() -> void:
    if _slow_mo_active or _reduce_motion_disable_slow_mo:
        return
    _slow_mo_active = true
    _slow_mo_start_msec = _get_time_msec.call()
    var effective_scale := clampf(SLOW_MO_SCALE * _reduce_motion_slow_mo_scale_mult, 0.0, 1.0)
    Engine.time_scale = effective_scale
```

- Émission `enemy_killed` avec metadata flash (story-011 augmenté quand VFX System ready) :
  ```gdscript
  enemy_killed.emit(c, c.global_position)  # signature actuelle
  # Future post-VFX : ajouter param ou utiliser dict, ou laisser VFX appliquer mult depuis sa propre lecture AccessibilityService
  ```

---

## Out of Scope

- ADR Accessibility Interface Layer (architectural decision séparée — Gap G-4)
- Save/Load persistence accessibility settings (BLOCKED ADR-0014 post-MVP)
- VFX flash mult application (VFX System story side, lit AccessibilityService)

---

## QA Test Cases

- **AC-1** Disable slow-mo (already covered story-013 AC-5)
  - Given: `_reduce_motion_disable_slow_mo = true`
  - When: 5 kills consécutifs
  - Then: `Engine.time_scale == 1.0`, `_slow_mo_active == false`
  - Edge cases: toggle false mid-game → kill suivant déclenche normal

- **AC-2** Slow-mo scale mult attenuation
  - Given: `_reduce_motion_slow_mo_scale_mult = 2.0`, `_reduce_motion_disable_slow_mo = false`
  - When: 1er kill
  - Then: `Engine.time_scale == 0.6 ± 0.0001` (0.3 * 2.0)
  - Edge cases: mult=3.33 → time_scale=0.999 ≈ 1.0 (équivalent disable) ; mult=1.0 → 0.3 (default)

- **AC-3** Defaults invariant
  - Given: mult_scale=1.0, disable=false, flash_mult=1.0 (defaults)
  - When: kill normal
  - Then: comportement identique non-accessibility MVP (Engine.time_scale=0.3, slow-mo full)
  - Edge cases: settings_changed signal reçu avec mêmes defaults — pas de side-effect

- **AC-4** Settings reload mid-game
  - Given: `_reduce_motion_disable_slow_mo = false` au boot
  - When: AccessibilityService.settings_changed émis avec disable=true mid-game
  - Then: prochain kill respecte nouveau setting (disable)
  - Edge cases: kill en cours pendant settings change — current swing's slow-mo non affecté (idempotence)

- **AC-5** Bornes clamping
  - Given: settings retournent mult_scale=5.0 (out of bounds [1.0, 3.33])
  - When: Combat read au _ready()
  - Then: `_reduce_motion_slow_mo_scale_mult == 3.33` (clamped), pas de panic
  - Edge cases: mult_scale=0.5 (< 1.0, atténuation négative interdite) → clamped à 1.0

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/accessibility_reduce_motion_test.gd` (BLOCKED ADR Accessibility — settings interface absent)

**Status**: [ ] Not yet created (BLOCKED ADR Accessibility)

---

## Dependencies

- Depends on: Story 013 (slow-mo Callable + flag déjà implémenté côté Combat), **ADR Accessibility Interface Layer (Gap G-4) + AccessibilityService autoload**
- Unlocks: Combat ↔ Accessibility contract verification (gate-check Polish phase)
