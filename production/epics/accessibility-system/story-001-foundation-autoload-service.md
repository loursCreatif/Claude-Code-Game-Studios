# Story 001: Foundation autoload `AccessibilityService` + Resource schema

> **Epic**: Accessibility System
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**ADR Governing Implementation**: ADR-0015 Accessibility Interface Layer (Accepted 2026-05-02)
**ADR Decision Summary** (D-1 / D-2 / D-3 / D-5 / D-6 / D-7 / D-8 / D-11) :

- Autoload `AccessibilityService` position #5 dans `project.godot [autoload]` (entre `SaveLoadSystem` et `CreditEconomy`).
- Persistance déléguée ADR-0014 via `SettingsResource.load_or_default("accessibility", ...)`.
- API pull-pattern read-only typed accessors (`is_reduce_motion_enabled`, `get_camera_tilt_mult`, `get_disable_slow_mo`, `get_slow_mo_scale_mult`, `get_flash_mult`, `get_camera_fov_kick_mult`, `get_camera_shake_mult`, `get_enemy_death_tween_ms`) + signal `settings_changed`.
- Bridge `OS.is_reduce_motion_enabled()` (Godot 4.5+ AccessKit) OR-mergé au `_ready()` (jamais downgrade user toggle).
- Bornes clamping service-level (consumers ne re-clampent pas).
- Defaults invariant garanti : tous flags OFF / multipliers=1.0 / override=0 → comportement bit-identique MVP non-accessibility.
- Outbound-zero (D-8) : aucune référence consumer.
- `class_name AccessibilityServiceScript` (éviter collision class_name vs autoload `AccessibilityService`).

**Engine**: Godot 4.6 | **Risk**: LOW (logic — interface ratifiée ADR-0015, tests deterministic)

**Control Manifest Rules (Foundation layer)**:
- Required: autoload registered position #5, `class_name AccessibilityServiceScript`.
- Forbidden: `OS.is_reduce_motion_enabled()` direct hors `accessibility_service.gd`, `@export var reduce_motion: bool` ad-hoc dans systèmes consumers.
- Guardrail: `_process` / `_physics_process` interdits (D-11 stateful pas tick-based).

---

## Acceptance Criteria

- [ ] **AC-1 — Autoload registered** : `project.godot [autoload]` contient `AccessibilityService="*res://src/core/accessibility_service.gd"` position #5 (après SaveLoadSystem, avant CreditEconomy).
- [ ] **AC-2 — Resource schema valid** : `AccessibilitySettings` Resource avec 9 properties (`_settings_version: int = 1`, `reduce_motion: bool = false`, `reduce_flash: bool = false`, `slow_mo_scale_mult: float = 1.0` [1.0..3.33], `disable_slow_mo: bool = false`, `flash_mult: float = 1.0` [0.0..1.0], `tilt_mult: float = 1.0` [0.0..1.0], `fov_kick_mult: float = 1.0` [0.0..1.0], `shake_mult: float = 1.0` [0.0..1.0], `enemy_death_tween_ms_override: int = 0` [100..600]) + factory `create_defaults()` + migration `migrate_from(version, raw)`.
- [ ] **AC-3 — Defaults invariant** : avec `accessibility_settings.tres` absent (first launch) ou defaults factory, tous getters retournent valeurs neutres (`is_reduce_motion_enabled() == false`, `get_camera_tilt_mult() == 1.0`, `get_disable_slow_mo() == false`, `get_slow_mo_scale_mult() == 1.0`, `get_flash_mult() == 1.0`, `get_camera_fov_kick_mult() == 1.0`, `get_camera_shake_mult() == 1.0`, `get_enemy_death_tween_ms() == 150`).
- [ ] **AC-4 — Reduce_motion derived getters** : avec `reduce_motion=true` et autres defaults, `get_camera_tilt_mult() == 0.25`, `get_camera_fov_kick_mult() == 0.5`, `get_camera_shake_mult() == 0.0`, `get_enemy_death_tween_ms() == 400`.
- [ ] **AC-5 — Bornes clamping service-level** : `slow_mo_scale_mult=5.0` (out-of-range) → `get_slow_mo_scale_mult() == 3.33` ; `flash_mult=2.0` → `get_flash_mult() == 1.0` ; `flash_mult=-0.5` → `0.0`.
- [ ] **AC-6 — apply_settings + signal** : `apply_settings(new)` mute `_settings`, émet `settings_changed`. Connect/disconnect testé.
- [ ] **AC-7 — save_settings explicit** : `save_settings()` retourne `OK` si `_settings != null`, écrit `user://settings/accessibility.tres`. Round-trip identity vérifié (load suivant retourne 9 properties bit-identiques).
- [ ] **AC-8 — OS bridge OR-merge** : si `_settings.reduce_motion=false` et `OS.is_reduce_motion_enabled()` retourne `true`, post `_ready()` `_settings.reduce_motion == true` (OR-merge). Si OS retourne `false` et user toggle `true`, `reduce_motion` reste `true`.
- [ ] **AC-9 — Outbound-zero** : grep `(CameraSystem|CombatSystem|MovementController|EnemySystem|VFXManager|HUDController)` dans `src/core/accessibility_service.gd` retourne 0 match.

---

## Implementation Notes

**Files** (NEW) :
- `src/core/settings/accessibility_settings.gd` — `class_name AccessibilitySettings extends Resource`, 9 properties + factory + migration.
- `src/core/accessibility_service.gd` — `class_name AccessibilityServiceScript extends Node`, signal `settings_changed`, 7 typed getters, `apply_settings`, `save_settings`. `_ready()` charge via `SettingsResource.load_or_default` + OR-merge OS.
- `tests/unit/accessibility/accessibility_settings_test.gd` — schema (9 properties), version match, migrate v0/v1.
- `tests/unit/accessibility/accessibility_service_defaults_test.gd` — defaults invariant (AC-3) + reduce_motion derived (AC-4) + bornes clamping (AC-5).
- `tests/integration/accessibility/accessibility_lifecycle_test.gd` — boot first-launch silent, apply_settings + signal, save_settings round-trip, OS bridge OR-merge.

**Files** (MODIFIED) :
- `project.godot` — append `AccessibilityService="*res://src/core/accessibility_service.gd"` position #5.
- `.godot/global_script_class_cache.cfg` — 2 entries (`AccessibilitySettings`, `AccessibilityServiceScript`).

---

## Out of Scope

- Settings Menu UI accessibility section (Tier 2+ Menu epic).
- Combat story-022 implementation (séparée — câblage `AccessibilityService.get_*` dans CombatSystem).
- Camera Polish P4 (séparée — remplace flag local par `AccessibilityService.get_camera_*_mult`).
- VFX flash mult application (différé ADR-0016).
- HUD pulse disable (Tier 3).

---

## QA Test Cases

- **AC-1** Autoload registered : grep `project.godot` → entry présent position attendue.
- **AC-2** Schema : `AccessibilitySettings.new()` instancie sans erreur, 9 properties exposed via `get_property_list()`.
- **AC-3** Defaults invariant : créer service avec defaults, asserter 7 getters retournent valeurs neutres.
- **AC-4** Reduce_motion derived : muter `_settings.reduce_motion=true`, asserter 4 getters camera/enemy.
- **AC-5** Bornes clamping : muter `slow_mo_scale_mult=5.0`, asserter `get_slow_mo_scale_mult() == 3.33`.
- **AC-6** apply_settings + signal : connect lambda recorder, call apply, asserter signal émis 1 fois + `_settings` muté.
- **AC-7** save_settings round-trip : save + load_or_default → identity 9 properties.
- **AC-8** OS bridge : mock `OS.is_reduce_motion_enabled()` retournant true, asserter post-`_ready()` `_settings.reduce_motion == true`.
- **AC-9** Outbound-zero : test_static grep regex sur file content.

---

## Test Evidence

**Story Type**: Logic
**Required evidence** : `tests/unit/accessibility/*_test.gd` + `tests/integration/accessibility/accessibility_lifecycle_test.gd` PASS.

**Status**: [x] **PASSED** — 19/19 tests OK 0 errors 0 failures 227 ms (`reports/report_228`).

---

## Completion Notes

**Completed**: 2026-05-02
**Criteria**: 9/9 COVERED
**Deviations**: NONE (forbidden patterns D-8/D-9 clean : `is_reduce_motion_enabled` confiné au service ; `@export var reduce_motion/reduce_flash` confinés au Resource ; outbound-zero confirmé)
**Test Evidence**: `tests/unit/accessibility/accessibility_settings_test.gd` (4 tests) + `tests/unit/accessibility/accessibility_service_defaults_test.gd` (8 tests) + `tests/integration/accessibility/accessibility_lifecycle_test.gd` (7 tests) — 19 PASSED `reports/report_228`
**Code Review**: Skipped (Solo mode auto-skip Phase 5)

### Test-Criterion Traceability

| AC | Test | Status |
|----|------|--------|
| AC-1 Autoload registered | manual grep project.godot | COVERED |
| AC-2 Resource schema 9 properties | accessibility_settings_test::defaults_has_safe_invariant_values + version_matches | COVERED |
| AC-3 Defaults invariant 7 getters | accessibility_service_defaults_test::defaults_invariant_neutral_getters + null_settings_falls_back | COVERED |
| AC-4 Reduce_motion derived | accessibility_service_defaults_test::reduce_motion_derives_camera_multipliers + reduce_motion_derives_enemy_death_tween + override_primes | COVERED |
| AC-5 Bornes clamping | accessibility_service_defaults_test::slow_mo_scale_clamps_above_max + below_min + flash_mult_clamps_unit_interval | COVERED |
| AC-6 apply_settings + signal | accessibility_lifecycle_test::apply_settings_emits_settings_changed_once | COVERED |
| AC-7 save_settings round-trip | accessibility_lifecycle_test::round_trip_identity_nine_properties + save_writes_prod_file + unconfigured | COVERED |
| AC-8 OS bridge OR-merge | accessibility_lifecycle_test::or_merge_never_downgrades + or_merge_promotes_when_os_reports | COVERED |
| AC-9 Outbound-zero | accessibility_lifecycle_test::does_not_reference_any_consumer | COVERED |

### Files livrés

NEW :
- `src/core/settings/accessibility_settings.gd` (Resource, 9 properties + factory + migration)
- `src/core/accessibility_service.gd` (autoload `class_name AccessibilityServiceScript`, 7 getters + apply + save + OS bridge)
- `tests/unit/accessibility/accessibility_settings_test.gd`
- `tests/unit/accessibility/accessibility_service_defaults_test.gd`
- `tests/integration/accessibility/accessibility_lifecycle_test.gd`

MODIFIED :
- `project.godot` — autoload `AccessibilityService` position #5 (entre SaveLoadSystem et CreditEconomy)
- `.godot/global_script_class_cache.cfg` — 2 entries (`AccessibilitySettings`, `AccessibilityServiceScript`)

---

## Dependencies

- **Depends on** : ADR-0015 (Accepted 2026-05-02), ADR-0014 helper `SettingsResource` (déjà mergé PR #2).
- **Unlocks** : Combat story-022 (TR-cmb-016), Camera Polish P4 (Rule 14 wiring), Enemy `DEATH_TWEEN_DURATION_MS`.
