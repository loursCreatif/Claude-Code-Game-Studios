# Story 005: Accessibility Pull — reduce_flash + flash_mult + reduce_motion (ADR-0015 D-1 Option A)

> **Epic**: VFX System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-05-04
> **Estimate**: S (2-3 h, pull boot + listener `settings_changed` + apply mults sur trail/cone/flash brightness)

## Context

**GDD**: `design/gdd/vfx-system.md` (Designed r1)
**Requirements**:
- R-VFX-5 (partial — flash brightness reduce_flash gris substitute body story-004)
- R-VFX-11 : reduce_motion mults — trail opacity × `REDUCE_MOTION_TRAIL_MULT = 0.5` + cone angle × `REDUCE_MOTION_PARTICLE_ANGLE_MULT = 0.5` ; effets 2D (flash kill / flash respawn) inchangés
- R-VFX-15 (partial — flash respawn reduce_flash ON → supprimé entièrement body story-004)
- F-VFX-2 : Flash brightness reduce_flash — `flash_mult ∈ [0.0, 1.0]` ; `flash_mult = 0.625` → gris neutre `#A0A0A0`

**ADR Governing Implementation**:
- **ADR-0015 D-1 Option A** (pull-pattern côté consumer) — VFX pull `AccessibilityService.reduce_flash` + `flash_mult` + `reduce_motion` au `_ready()` puis live via signal `settings_changed`. Pas de lecture directe `OS.is_reduce_motion_enabled()` — délégué au Service (single source of truth).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Pull pattern stable Godot 4.0+. Signal `settings_changed` no-payload — VFX pull explicite après réception (cohérent autres consumers Camera/Combat/Movement).

**Control Manifest Rules (Presentation layer)**:
- Required : pull `AccessibilityService.reduce_flash` + `flash_mult` + `reduce_motion` au `_ready()` (avec guard `is_instance_valid` EC-VFX-08) ; listener `_on_accessibility_settings_changed` CONNECT_DEFERRED re-pull live ; apply mults sur trail opacity (R-VFX-7) + cone angle particles (R-VFX-8) + flash brightness (R-VFX-5).
- Forbidden : lecture directe `OS.is_reduce_motion_enabled()` (ADR-0015 D-1 — délégué au Service) ; mutation `AccessibilityService.*` (read-only consumer outbound-zero) ; cache stale (re-pull à chaque `settings_changed`).
- Guardrail : defaults safe si `AccessibilityService` non initialisé (`reduce_flash = false`, `flash_mult = 1.0`, `reduce_motion = false`) — EC-VFX-08.

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1, scoped à cette story (Integration) :*

- [ ] **AC-VFX-12** [BLOCKING][AUTO] **GIVEN** `reduce_motion == true`, **WHEN** `enemy_killed` reçu, **THEN** les particules s'émettent mais le cone angle est `30° × REDUCE_MOTION_PARTICLE_ANGLE_MULT = 15°` ; le count reste identique (6 particles) ; aucun mouvement camera VFX généré. *(Story-002 implémente apply ; cette story-005 fournit la valeur `_reduce_motion` mutable pull boot + live.)*
- [ ] **AC-VFX-20** [BLOCKING][AUTO] **GIVEN** Le jeu tourne avec `reduce_flash == false` (flash blanc actif), **WHEN** `AccessibilityService.settings_changed` est émis avec `reduce_flash = true` mid-game, **THEN** le prochain `enemy_killed` produit un flash gris `#A0A0A0` (pas blanc) ; la mise à jour est live (pas de redémarrage requis).
- [ ] **AC-VFX-21** [BLOCKING][AUTO] **GIVEN** `AccessibilityService` n'est pas encore initialisé quand `VFXSystem._ready()` s'exécute, **WHEN** VFX tente le pull initial `AccessibilityService.reduce_flash`, **THEN** Guard `is_instance_valid(AccessibilityService)` appliqué → defaults `reduce_flash = false`, `flash_mult = 1.0` ; pas de crash ; correction via `settings_changed` dès qu'AccessibilityService est prêt.
- [ ] **AC-NEW-07** [BLOCKING][AUTO] **GIVEN** trail katana actif (`swing_started` reçu), **WHEN** `settings_changed` émis avec `reduce_motion = true`, **THEN** trail opacity max passe de `0.7` à `0.7 × REDUCE_MOTION_TRAIL_MULT = 0.35` immédiatement (live update mid-swing OK).

---

## Implementation Notes

```gdscript
# story-005 ajoute / refactore dans src/core/vfx_system.gd

const REDUCE_MOTION_TRAIL_MULT: float = 0.5  # tuning knob R-VFX-11
const REDUCE_MOTION_PARTICLE_ANGLE_MULT: float = 0.5

# State variables (déclarées story-002 stub) :
# var _reduce_motion: bool = false
# var _reduce_flash: bool = false
# var _flash_mult: float = 1.0

func _ready() -> void:
    # ... story-001 pool boot ...

    # ADR-0015 D-1 — pull initial avec guard EC-VFX-08
    _pull_accessibility_settings()

    # ... story-001 connect upstream signals ...
    # AccessibilityService.settings_changed CONNECT_DEFERRED → _on_accessibility_settings_changed

func _pull_accessibility_settings() -> void:
    # AC-VFX-21 — guard AccessibilityService non initialisé (race ordering autoload)
    if not is_instance_valid(AccessibilityService):
        # Defaults safe MVP — corrigés par settings_changed live dès Service prêt
        _reduce_flash = false
        _flash_mult = 1.0
        _reduce_motion = false
        push_warning("VFX: AccessibilityService not yet initialized at _ready() — using defaults")
        return

    _reduce_flash = AccessibilityService.reduce_flash
    _flash_mult = AccessibilityService.flash_mult
    _reduce_motion = AccessibilityService.reduce_motion

func _on_accessibility_settings_changed() -> void:
    # ADR-0015 D-1 — re-pull live à chaque settings_changed
    var prev_reduce_motion: bool = _reduce_motion
    _pull_accessibility_settings()

    # AC-NEW-07 — apply live update mid-swing si reduce_motion changé
    if _trail_active and prev_reduce_motion != _reduce_motion:
        var trail_color: Color = TRAIL_COLOR
        trail_color.a = KATANA_TRAIL_OPACITY_MAX * (REDUCE_MOTION_TRAIL_MULT if _reduce_motion else 1.0)
        _set_trail_modulate(trail_color)

    # Note : flash kill en cours n'est PAS rétroactivement modifié par change reduce_flash
    # (durée 80 ms trop courte ; le flash suivant utilise la nouvelle valeur — AC-VFX-20)

# Refactor story-002 _spawn_blood_spurt — utilise _reduce_motion live
# Note : story-002 implémente déjà apply mult sur cone angle ; cette story-005 fournit la valeur
```

**Apply mults summary** (cross-stories) :

| Multiplier | Where applied | Story owns body | Live update |
|------------|---------------|-----------------|-------------|
| `_reduce_motion` → trail opacity × 0.5 | `_on_swing_started` + `_set_trail_modulate` | story-002 (apply) + story-005 (pull) | story-005 (`_on_accessibility_settings_changed` re-apply mid-swing) |
| `_reduce_motion` → cone angle × 0.5 | `_spawn_blood_spurt` ParticleProcessMaterial.spread | story-002 (apply) + story-005 (pull) | Pas de live update mi-particle (lifetime court 400 ms — apply au prochain spawn) |
| `_reduce_flash` → gris substitute `#A0A0A0` | `_apply_flash_kill_color` | story-004 (apply) + story-005 (pull) | story-004 lit `_flash_kill_use_grey` capturé au `_trigger_flash_kill()` — flash en cours non rétroactif (AC-VFX-20 next flash) |
| `_reduce_flash` → flash respawn supprimé | `_trigger_flash_respawn` early return | story-004 (apply) + story-005 (pull) | Pas de flash respawn en cours simultané (durée 50 ms) |

**Pattern Pull Defensive (EC-VFX-08)** :

```gdscript
# CORRECT — guard is_instance_valid avant pull
if not is_instance_valid(AccessibilityService):
    # Defaults safe ; corrigés au prochain settings_changed
    _reduce_flash = false
    _flash_mult = 1.0
    _reduce_motion = false
    return

# INCORRECT — accès direct sans guard (crash si Service pas registered AVANT VFX dans project.godot)
_reduce_flash = AccessibilityService.reduce_flash  # null reference risk
```

**ADR-0015 D-1 Option A pull-pattern cohérence** :
- Camera GDD Rule 14 — pull `reduce_motion` au `_ready()` + live `settings_changed` (tilt × 0.25, FOV pulse × 0.5, shake × 0).
- Combat story-022 — pull `disable_slow_mo` + `slow_mo_scale_mult` + `flash_mult` au `_ready()`.
- VFX story-005 (cette story) — pull `reduce_flash` + `flash_mult` + `reduce_motion` cohérent pattern Camera/Combat.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Apply `_reduce_motion` mult sur cone angle particles (`ParticleProcessMaterial.spread`) — story-002 (handler `_spawn_blood_spurt` body).
- Apply `_reduce_flash` gris substitute sur `_flash_overlay_rect.color` — story-004 (`_apply_flash_kill_color` body).
- Apply `_reduce_motion` mult sur trail opacity initial (`_on_swing_started`) — story-002 (handler trail activation).
- GSM visibility gating MENU/PAUSED/BOSS_DEFEATED → flash overlay forced hidden — story-006.
- Lints statiques anti-patterns (zero `OS.is_reduce_motion_enabled()` direct grep) — story-007.
- Visual/Feel playtest verbatims (lexique court/sec/désaturé/percussif) — story-008.
- Persistence accessibility settings (Save/Load `accessibility_settings.tres`) — déjà couvert ADR-0015 / accessibility-system epic 1/1 Complete.

---

## QA Test Cases

*Integration — automated integration tests requis :*

**AC-VFX-12** : reduce_motion live update cone × 0.5
- Setup : VFXSystem ready, mock AccessibilityService initial `reduce_motion = false`.
- Action : émettre `enemy_killed` → cone effective 30° (story-002 logic).
- Action : `AccessibilityService.reduce_motion = true` + émettre `settings_changed`.
- Verify post-DEFERRED tick : `vfx._reduce_motion == true`.
- Action : émettre 2ème `enemy_killed`.
- Verify : cone effective 15° (`30 × 0.5`) appliqué sur 2ème spawn.
- Pass : 2 asserts cone angle.

**AC-VFX-20** : reduce_flash live update gris substitute
- Setup : `_reduce_flash = false` initial.
- Action : `AccessibilityService.reduce_flash = true` + émettre `settings_changed`.
- Verify post-DEFERRED tick : `vfx._reduce_flash == true`.
- Action : émettre `enemy_killed`.
- Verify : `_flash_overlay_rect.color.r == 0.625` (#A0A0A0 substitute), pas Color(1, 1, 1, 1.0).
- Pass : `assert_float(rect.color.r).is_equal_approx(0.625, 0.01)`.

**AC-VFX-21** : Boot defensive si AccessibilityService null
- Setup : VFXSystem `_ready()` exécuté AVANT autoload AccessibilityService disponible (mock retourne `is_instance_valid(AccessibilityService) == false`).
- Action : `_pull_accessibility_settings()`.
- Verify : `_reduce_flash == false`, `_flash_mult == 1.0`, `_reduce_motion == false` ; aucun crash ; `push_warning` capturé "VFX: AccessibilityService not yet initialized...".
- Action : Service prêt + `settings_changed` émis avec `reduce_flash = true`.
- Verify post-DEFERRED tick : `_reduce_flash == true` (correction live).
- Pass : 4 asserts.

**AC-NEW-07** : Live update mid-swing trail opacity
- Setup : VFXSystem ready, `_reduce_motion = false`, trail actif (`_on_swing_started(Vector3.FORWARD)`).
- Verify : trail opacity == `KATANA_TRAIL_OPACITY_MAX = 0.7`.
- Action : `AccessibilityService.reduce_motion = true` + `settings_changed`.
- Verify post-DEFERRED tick : trail opacity == `0.7 × 0.5 = 0.35` (live update mid-swing).
- Pass : 2 asserts opacity.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/vfx/vfx_accessibility_pull_test.gd` (NEW, ~180 lignes) couvrant AC-VFX-12/20/21 + AC-NEW-07 + EC-VFX-08.
- Mock `MockAccessibilityService` avec `reduce_flash` / `flash_mult` / `reduce_motion` settable + signal `settings_changed`.
- Smoke check : test suite green run via GdUnit4 headless.

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** : story-001 (`_on_accessibility_settings_changed` stub + connect upstream signal) + story-002 (apply `_reduce_motion` cone + trail) + story-004 (apply `_reduce_flash` gris substitute + flash respawn skip).
- **Cross-system** :
  - **AccessibilityService Ready** : ADR-0015 Accepted 2026-05-02 + accessibility-system epic 1/1 Complete ✅. APIs `reduce_flash` / `flash_mult` / `reduce_motion` + signal `settings_changed` disponibles production.
- **Unlocks** : aucune downstream — close-out ADR-0015 D-1 pattern pull-côté-consumer pour VFX.
