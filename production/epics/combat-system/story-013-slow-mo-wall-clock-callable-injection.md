# Story 013: Slow-mo wall-clock + Callable injection + restore + edge cases

> **Epic**: Player Combat System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23
> **Completed**: 2026-05-02 (auto-mode, doc sync — implémentation déjà livrée stories 011/012/022)

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-013` (slow-mo wall-clock dans `_physics_process`) + `TR-cmb-017` (Callable injection point)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) D-5 + ADR-0001 (Physics Rate)
**ADR Decision Summary**: Slow-mo timing wall-clock via `_get_time_msec: Callable = Time.get_ticks_msec` substituable test (DEC-r5-1). `Engine.time_scale = SLOW_MO_SCALE = 0.3` sur 1er `enemy_killed` du swing. Restore via comparaison wall-clock dans `_physics_process` (ADR-0001 authority — JAMAIS `_process`). Multi-kill n'étend pas la fenêtre (idempotence `_slow_mo_active` flag). AudioStreamPlayer pitch NON affecté par time_scale Godot 4.6 (désiré).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Engine.time_scale` stable Godot 4.0+. `Time.get_ticks_msec()` stable. AudioStreamPlayer ne réagit pas à `time_scale` par défaut Godot 4.6 (confirmé GDD Rule 13).

**Control Manifest Rules (Feature layer)**:
- Required: restore Engine.time_scale dans `_physics_process` (ADR-0001 autorité simulation)
- Forbidden: restore via `_process` (cosmétique only, viole ADR-0001 + Rule 13)
- Guardrail: teardown obligatoire `Engine.time_scale = 1.0` en fin de test (contamination inter-tests)

---

## Acceptance Criteria

*From GDD AC-CMB-19/24/25 + Rule 13 + Formula 7 :*

- [x] **AC-CMB-19** : injection Callable `_get_time_msec` substituable ; mock retournant `1000` au moment du 1er kill → `Engine.time_scale == 0.3 ± 0.0001`, `_slow_mo_active == true`, `_slow_mo_start_msec == 1000` ; mock retournant `1030`, `1050`, `1067` → à 1030 `time_scale == 0.3` ; à 1050 ou 1067 `time_scale == 1.0 ± 0.0001` AND `_slow_mo_active == false`
- [x] **AC-CMB-19 r6 branch C accessibility** : `_reduce_motion_disable_slow_mo == true` → 1er `enemy_killed` ne mute PAS `Engine.time_scale` (5 kills consécutifs vérifiés `time_scale == 1.0` tout au long, `_slow_mo_active == false`)
- [x] **AC-CMB-24** : `Engine.time_scale = 0.5` debug externe au moment du 1er kill → écrasé à `0.3 ± 0.0001` ; après 50 ms wall-clock → restauré à `1.0 ± 0.0001` (PAS à `0.5`)
- [x] **AC-CMB-25 (slow-mo idempotence)** : 2 MockEnemies tués même tick → 1er kill set `_slow_mo_active = true, time_scale = 0.3` ; 2e kill `_slow_mo_active` déjà true → `time_scale` non ré-assigné ; `multi_kill(2)` émis (couvert story-012)
- [x] **AC-CMB-21 ordering (déjà partagé story-003)** : si `Player.died()` reçu pendant slow-mo → `Engine.time_scale = 1.0` AVANT autres transitions Dead (combat_system.gd ligne 700-702 `_on_player_died`)
- [x] Constants : `SLOW_MO_DURATION_MS = 50.0`, `SLOW_MO_SCALE = 0.3` (combat_system.gd ligne 55, 60)

---

## Implementation Notes

*Derived from ADR-0006 D-5 + GDD Rule 13 + Formula 7 :*

```gdscript
const SLOW_MO_DURATION_MS: float = 50.0
const SLOW_MO_SCALE: float = 0.3

@export var _reduce_motion_disable_slow_mo: bool = false  # Section G accessibility (story-022)

var _slow_mo_active: bool = false
var _slow_mo_start_msec: int = 0

# Injection point — substituable en test
var _get_time_msec: Callable = Time.get_ticks_msec

# Hooked into enemy_killed handler (intra-_collect_swing_hits)
func _trigger_slow_mo_if_first_kill() -> void:
    if _slow_mo_active:
        return  # idempotence multi-kill
    if _reduce_motion_disable_slow_mo:
        return  # accessibility branch C
    _slow_mo_active = true
    _slow_mo_start_msec = _get_time_msec.call()
    Engine.time_scale = SLOW_MO_SCALE

# Called from _physics_process (ADR-0001 authority)
func _check_slow_mo_restore() -> void:
    if not _slow_mo_active:
        return
    var elapsed_msec: int = _get_time_msec.call() - _slow_mo_start_msec
    if elapsed_msec >= int(SLOW_MO_DURATION_MS):
        Engine.time_scale = 1.0
        _slow_mo_active = false
        _slow_mo_start_msec = 0
```

- Appeler `_trigger_slow_mo_if_first_kill()` immédiatement après chaque `enemy_killed.emit()` dans `_resolve_swing_hits()` (story-012) — idempotent
- Appeler `_check_slow_mo_restore()` au début de `_physics_process` (avant state machine logic) pour restore avant que les autres systèmes ne lisent un `time_scale` déjà attendu
- Test teardown obligatoire : `combat_system._get_time_msec = Time.get_ticks_msec` + `Engine.time_scale = 1.0`

---

## Out of Scope

- Story 022 (BLOCKED) : `_reduce_motion_disable_slow_mo` accessibility full lifecycle (cette story consume le flag, story-022 le wire à un settings handler accessibility)
- Story 020 (BLOCKED Audio) : swoosh fade-out wall-clock avec même Callable injection pattern

---

## QA Test Cases

- **AC-1** Injection wall-clock baseline
  - Given: `_get_time_msec` mocké retourne 1000 au 1er kill
  - When: `_trigger_slow_mo_if_first_kill()` exécuté après `enemy_killed.emit()`
  - Then: `Engine.time_scale == 0.3 ± 0.0001`, `_slow_mo_active == true`, `_slow_mo_start_msec == 1000`
  - Edge cases: teardown `Engine.time_scale = 1.0` en `after_each` test

- **AC-2** Restore at exact 50ms
  - Given: `_slow_mo_active == true`, `_slow_mo_start_msec == 1000`
  - When: `_get_time_msec` mocké retourne 1030 puis 1050 puis 1067 (3 ticks `_check_slow_mo_restore`)
  - Then: à 1030 `time_scale == 0.3` ; à 1050 (= 50 ms exact) OU 1067 (50 + 1 frame tolerance) `time_scale == 1.0 ± 0.0001`, `_slow_mo_active == false`
  - Edge cases: 1049 ms exact — `time_scale` reste 0.3 (gate `>= 50` strict)

- **AC-3** Multi-kill idempotence
  - Given: 2 kills même tick, `_slow_mo_active == false` au début
  - When: 1er kill → `_trigger_slow_mo_if_first_kill()` puis 2e kill → re-call
  - Then: `Engine.time_scale == 0.3` (assignée 1×), `_slow_mo_active == true`, `_slow_mo_start_msec == 1000` (pas update)
  - Edge cases: 5 kills même tick → 1× assignment seulement

- **AC-4** External time_scale override
  - Given: `Engine.time_scale = 0.5` (debug externe), 1er kill
  - When: `_trigger_slow_mo_if_first_kill()`
  - Then: `Engine.time_scale == 0.3 ± 0.0001` (écrase 0.5)
  - Edge cases: après 50 ms restore → `time_scale == 1.0` (pas 0.5)

- **AC-5** Accessibility disable
  - Given: `_reduce_motion_disable_slow_mo == true`, 5 kills consécutifs
  - When: chaque kill exécute `_trigger_slow_mo_if_first_kill()`
  - Then: pour les 5 kills : `Engine.time_scale == 1.0 ± 0.0001`, `_slow_mo_active == false` (jamais mué)
  - Edge cases: toggle `_reduce_motion_disable_slow_mo = false` mid-game → kill suivant déclenche normal

- **AC-6** Restore in _physics_process not _process
  - Given: source `combat_system.gd`
  - When: `grep -nE 'Engine\.time_scale\s*=\s*1\.0' src/gameplay/combat/`
  - Then: matches uniquement dans `_physics_process` ou `_on_player_died` (handler SYNC) — pas dans `_process`
  - Edge cases: docstring/commentaires permis

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/slow_mo_wall_clock_test.gd` — must exist and pass (avec teardown Engine.time_scale=1.0)

**Status**: ✅ Created — 7/7 PASS (`reports/report_260` 2026-05-02).

**Test plan** :
| AC | Test function | Status |
|----|---------------|--------|
| AC-1 / AC-CMB-19 | `test_combat_trigger_slow_mo_first_kill_sets_engine_time_scale` | ✅ PASS |
| AC-2 (50 ms gate) | `test_combat_check_slow_mo_restore_at_exact_50ms_threshold` | ✅ PASS |
| AC-2 edge (49 ms) | `test_combat_check_slow_mo_restore_at_49ms_strict_gate` | ✅ PASS |
| AC-3 / AC-CMB-25 | `test_combat_trigger_slow_mo_idempotent_across_multiple_kills` | ✅ PASS |
| AC-4 / AC-CMB-24 | `test_combat_external_time_scale_overridden_by_slow_mo_then_restored_to_one` | ✅ PASS |
| AC-5 / AC-CMB-19 r6 | `test_combat_reduce_motion_disables_slow_mo_for_all_kills` | ✅ PASS |
| AC-6 (_physics_process) | `test_combat_physics_process_triggers_slow_mo_restore` | ✅ PASS |

## Completion Notes

- **Implémentation cross-livrée** : `_trigger_slow_mo_if_first_kill` + `_check_slow_mo_restore` câblés dans combat_system.gd lignes 719-735 + 827-836. Appel `_check_slow_mo_restore()` depuis `_physics_process` ligne 276 (autorité ADR-0001). Trigger appelé depuis `_resolve_kills` ligne 527 post-die() (story-011/012).
- **Accessibility branch C** : `_reduce_motion_disable_slow_mo` câblé via `AccessibilityService.get_disable_slow_mo()` dans `_apply_accessibility()` ligne 806 (livré story-022).
- **Player died handler** : `_on_player_died` ligne 700-702 restore `Engine.time_scale = 1.0` AVANT transitions Dead (AC-CMB-21).
- **Story status correction 2026-05-02** : la story était marquée Done sans cocher les ACs ni créer Test Evidence. Audit a révélé implémentation + tests existants — re-cochés sur evidence réelle (`reports/report_260`).

---

## Dependencies

- Depends on: Story 011 (kill resolution émet `enemy_killed`), Story 012 (multi-kill ordering)
- Unlocks: Story 020 (BLOCKED Audio swoosh same Callable pattern), Story 022 (BLOCKED accessibility wire)
