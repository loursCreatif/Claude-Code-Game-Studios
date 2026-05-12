# Story 007: Sweep position + aim_forward consumption + invalid/NaN guards

> **Epic**: Player Combat System
> **Status**: Complete
> **Completed**: 2026-05-02 (auto-mode, fix is_equal_approx vector tolerance + tests PASS)
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-007` (sweep orientation read-only `CameraSystem.aim_forward`)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) + ADR-0002 (Camera Scene Tree)
**ADR Decision Summary**: Sweep orientation lit `CameraSystem.aim_forward` (forme close trigonométrique roll-corrigée, ADR-0002 D-2). JAMAIS lecture directe `camera.basis.z` ou `player.transform.basis.z` (forbidden pattern). Guards pour `Vector3.ZERO`, NaN, inf → swing ignoré silencieusement, `push_error` debug build.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Vector3.is_zero_approx()`, `Vector3.is_finite()` stable Godot 4.0+.

**Control Manifest Rules (Feature layer)**:
- Required: lecture `CameraSystem.aim_forward` (read-only)
- Forbidden: `camera.basis.z`, `player.transform.basis.z`, `camera.global_transform.basis.z` directs (lint CI grep)
- Guardrail: `is_finite()` + `is_zero_approx()` checks avant utilisation aim

---

## Acceptance Criteria

*From GDD AC-CMB-15/16/26/27/48 + Formula 1/2 :*

- [x] **AC-CMB-15** : `aim_forward` mocké à `(yaw=0, pitch=0)` → forme close `Vector3(-sin(0)*cos(0), -sin(0), -cos(0)*cos(0)) == Vector3(0, 0, -1) ± 0.001`, `length() == 1.0 ± 0.0001`
- [x] **AC-CMB-16** : `player.global_position = Vector3(0, 1.8, 0)`, `aim_forward = Vector3(0, 0, -1)` → `ShapeCast3D.global_transform.origin == Vector3(0, 1.8, -0.9)` (centre = position + aim × KATANA_REACH/2)
- [x] **AC-CMB-26** : intégration avec CameraSystem réel + `WALL_RUNNING` tilt z=0.3 rad → `aim_forward` lu reste roll-corrigé, `aim_forward.y` non dévié
- [x] **AC-CMB-27** : `CameraSystem.aim_forward = Vector3.ZERO` (mock bug) → swing ignoré, `_state` reste Idle, `push_error` debug
- [x] **AC-CMB-48** : `aim_forward = Vector3(NaN, 0, NaN)` ou `Vector3(inf, 0, 0)` → swing ignoré, `_state` Idle, `push_error` debug
- [x] **Forbidden grep** : aucun match `camera\.basis\.z`, `player\.transform\.basis\.z`, `\.global_transform\.basis\.z` dans `src/gameplay/combat/`

---

## Implementation Notes

*Derived from ADR-0006 D-7 + GDD Formula 1/2 + Edge Case cross-system :*

- Avant `_start_swing()`, valider aim :
  ```gdscript
  func _validate_aim(aim: Vector3) -> bool:
      if not aim.is_finite():
          if OS.is_debug_build():
              push_error("Combat: aim_forward NaN/inf — swing ignored")
          return false
      if aim.is_zero_approx():
          if OS.is_debug_build():
              push_error("Combat: aim_forward zero — swing ignored")
          return false
      return true
  ```
- Au début `_start_swing()` :
  ```gdscript
  var aim := camera_system.aim_forward
  if not _validate_aim(aim):
      return  # _state reste Idle, swing ignoré
  ```
- Position du ShapeCast3D au tick courant :
  ```gdscript
  var sweep_origin := player.global_position + aim * (KATANA_REACH / 2.0)
  $ShapeCast3D.global_transform = Transform3D(_build_capsule_basis(aim), sweep_origin)
  ```
- Référence `camera_system` injectée via `@export var camera_system: CameraSystem` ou `get_node("/root/CameraSystem")` (selon convention projet)

---

## Out of Scope

- Story 005 : helper `_build_capsule_basis()` (déjà disponible)
- Story 008 : per-tick update du sweep (cette story configure tick 0 + position)
- Story 009 : substeps interpolation entre _prev_position et current

---

## QA Test Cases

- **AC-1** Forward cardinal yaw=0 pitch=0
  - Given: yaw = 0, pitch = 0 mocked
  - When: forme close `Vector3(-sin(0)*cos(0), -sin(0), -cos(0)*cos(0))`
  - Then: `aim_forward == Vector3(0, 0, -1) ± 0.001`, `aim_forward.length() == 1.0 ± 0.0001`
  - Edge cases: yaw=π, pitch=0 → `Vector3(0, 0, 1)`

- **AC-2** Sweep position formula
  - Given: `player.global_position = Vector3(0, 1.8, 0)`, `aim_forward = Vector3(0, 0, -1)`, `KATANA_REACH = 1.8`
  - When: ShapeCast3D origin calculé
  - Then: `ShapeCast3D.global_transform.origin == Vector3(0, 1.8, -0.9) ± 0.001`
  - Edge cases: aim diagonal `Vector3(0.5, 0, -0.866).normalized()` — origin offset diagonal

- **AC-3** Roll-corrected wall-run
  - Given: scene Player + Camera + Combat intégrée, Camera tilt z=0.3 rad (WALL_RUNNING simulé)
  - When: `camera_system.aim_forward` consommé pendant swing
  - Then: aim resté forme close yaw/pitch, pas dévié par tilt z (`|aim - expected_no_roll| < 0.001`)
  - Edge cases: tilt négatif (-0.3 rad) — symétrie

- **AC-4** Zero aim guard
  - Given: `camera_system.aim_forward = Vector3.ZERO` (mock)
  - When: `player.attacked.emit()`
  - Then: `_state` reste IDLE, `push_error` reçu (vérifier via `Engine.get_singleton("ErrorMonitor")` mock ou capture)
  - Edge cases: `Vector3(0.001, 0, 0)` (proche zéro mais non-zero) — `is_zero_approx` doit gate

- **AC-5** NaN/inf aim guard
  - Given: aim `Vector3(NAN, 0, NAN)` ou `Vector3(INF, 0, 0)`
  - When: `player.attacked.emit()`
  - Then: `_state` reste IDLE, `push_error` reçu
  - Edge cases: 1 composante NaN suffit pour fail `is_finite()`

- **AC-6** Forbidden pattern grep
  - Given: source `src/gameplay/combat/`
  - When: `grep -nE 'camera\.basis\.z|player\.transform\.basis\.z|\.global_transform\.basis\.z' src/gameplay/combat/`
  - Then: zéro match
  - Edge cases: `camera_system.aim_forward` autorisé, lecture via méthode publique CameraSystem

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/sweep_position_aim_guards_test.gd` — must exist and pass

**Status**: ✅ Created — 8/8 PASS (`reports/report_264` 2026-05-02 — fix `is_equal_approx(vec, Vector3.ONE * tol)` GdUnit4 vector signature).

---

## Dependencies

- Depends on: Story 005 (helper basis), Story 006 (ShapeCast3D config), Camera story `aim_forward` published
- Unlocks: Story 008 (per-tick update), Story 009 (substeps anti-tunneling)
