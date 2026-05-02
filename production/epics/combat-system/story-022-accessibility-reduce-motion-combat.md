# Story 022: Accessibility `reduce_motion` Combat impact

> **Epic**: Player Combat System
> **Status**: Ready (Polish P3)
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

> **UNBLOCKED 2026-05-02** : ADR-0015 Accessibility Interface Layer Accepted (autoload `AccessibilityService` + persistance déléguée ADR-0014 via `accessibility_settings.tres`). API consommée : `AccessibilityService.get_disable_slow_mo()`, `get_slow_mo_scale_mult()` (clampé service-level [1.0, 3.33]), `get_flash_mult()` (clampé [0.0, 1.0]), signal `settings_changed` pour live update mid-game. Story-013 a déjà implémenté la branche de code locale (`_reduce_motion_disable_slow_mo` flag) — l'implémentation cette story remplace le flag local par l'appel `AccessibilityService.get_*` au `_ready()` + reconnect signal. Polish P3, hors Sprint 1 critical path.

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-016` (accessibility toggles `reduce_motion` impact Combat)

**ADR Governing Implementation**: ADR-0015 Accessibility Interface Layer (Accepted 2026-05-02)
**ADR Decision Summary**: 3 toggles cross-system gérés par autoload `AccessibilityService` (ADR-0015 D-1/D-3/D-4) :
- `reduce_motion_slow_mo_scale_mult ≥ 1.0` (bornes [1.0, 3.33]) — atténue slow-mo (multiplie SLOW_MO_SCALE par mult, ramène vers 1.0)
- `reduce_motion_disable_slow_mo: bool` — toggle complet désactivation
- `reduce_motion_flash_mult ∈ [0.0, 1.0]` — atténue VFX flash alpha (owned VFX, contract Combat→VFX)

Sémantique r1 = "atténuer" (mult ≥ 1.0).

**Engine**: Godot 4.6 | **Risk**: LOW (logic — interface ratifiée ADR-0015)
**Engine Notes**: aucun engine-specific Combat. Persistance settings déléguée ADR-0014 via `accessibility_settings.tres` (Resource typé). OS bridge `OS.is_reduce_motion_enabled()` (Godot 4.5+ AccessKit) géré par `AccessibilityService._ready()` via OR-merge (transparent pour Combat).

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
# Combat lit l'interface ADR-0015 (autoload AccessibilityService)
# Note : bornes [1.0, 3.33] et [0.0, 1.0] clampées service-level (ADR-0015 D-7),
# Combat n'a PAS à clamper à nouveau.
var _reduce_motion_disable_slow_mo: bool = false
var _reduce_motion_slow_mo_scale_mult: float = 1.0
var _reduce_motion_flash_mult: float = 1.0

func _ready() -> void:
    AccessibilityService.settings_changed.connect(_on_accessibility_changed)
    _apply_accessibility()

func _apply_accessibility() -> void:
    _reduce_motion_disable_slow_mo = AccessibilityService.get_disable_slow_mo()
    _reduce_motion_slow_mo_scale_mult = AccessibilityService.get_slow_mo_scale_mult()
    _reduce_motion_flash_mult = AccessibilityService.get_flash_mult()

func _on_accessibility_changed() -> void:
    _apply_accessibility()

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

- ADR-0015 Accessibility Interface Layer création (déjà Accepted 2026-05-02 — implémentation autoload `AccessibilityService` traitée par story dédiée Foundation, pas dans cette story Combat)
- Save/Load persistence accessibility settings (déjà couvert ADR-0014, helper `SettingsResource` consommé par AccessibilityService)
- VFX flash mult application (VFX System story side, lit AccessibilityService directement — différé ADR-0016 VFX)
- Settings Menu UI accessibility section (Tier 2+ Menu epic)

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
**Required evidence**: `tests/unit/combat/accessibility_reduce_motion_test.gd`

**Status**: [ ] Not yet created — implémentation Polish P3 attendue.

---

## Dependencies

- Depends on: Story 013 (slow-mo Callable + flag local déjà implémenté côté Combat — sera câblé à `AccessibilityService.get_disable_slow_mo()`), **ADR-0015 Accessibility Interface Layer (Accepted 2026-05-02) + autoload `AccessibilityService` (story Foundation séparée)**, ADR-0014 (persistance déléguée).
- Unlocks: Combat ↔ Accessibility contract verification (gate-check Polish phase). Couvre TR-cmb-016 + s'aligne avec TR-mov-008 (mutualisé ADR-0015).
