# Story 013: camera_settings.tres save/load lifecycle (persist + migration + corruption fallback)

> **Epic**: Camera System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23
> **Estimate**: M (4-6 h, Resource class + integration CameraSystem._ready load + save explicit + 4 ACs tests)
> **Performance**: settings load < 1 ms boot one-shot ; save < 5 ms rare event off-hot-path (ADR-0014 Performance Implications).

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: **ADR-0014 Save/Load Settings Infrastructure** (Accepted 2026-05-02)
**ADR Decision Summary**: Resource (.tres) typé pour settings (D-1, divergence justifiée vs ConfigFile savegame ADR-0010) + helper static class `SettingsResource` zero autoload (D-5) + sub-folder `user://settings/<system>.tres` (D-2) + versioning `_settings_version: int` + migration forward-only (D-3) + corruption fallback defaults+warning+rewrite-on-next-save (D-4) + factory function `create_defaults()` obligatoire (D-7) + outbound-zero (D-10).

**Engine**: Godot 4.6 | **Risk**: LOW (`Resource` + `ResourceSaver.save` + `ResourceLoader.load` API stables 3.x — validé dans ADR-0014 Engine Compatibility)
**Engine Notes**: `duplicate(true)` only (pas `duplicate_deep()` 4.5+ — schémas settings flat MVP, ADR-0014 D-8). `make_dir_recursive_absolute()` pour bootstrap sub-folder. Pas d'API post-cutoff requise.

---

## Acceptance Criteria

*Path canonique (ADR-0014 D-2) : `user://settings/camera.tres` (sub-folder, pas racine `user://`).*

- [ ] **AC-CAM-SAVE-1** : `GIVEN` `mouse_sensitivity = 0.0040`, `mouse_y_inverted = true`, `fov_user_offset = +5.0`, `WHEN` `CameraSystem.save_settings()` triggered, `THEN` `user://settings/camera.tres` contient les 3 valeurs sérialisées + `_settings_version = CURRENT_VERSION`.
- [ ] **AC-CAM-SAVE-2** : `GIVEN` `user://settings/camera.tres` `_settings_version = 1` actuel, `WHEN` `CameraSettings.CURRENT_VERSION` bumped à 2 (champ ajouté), `THEN` `migrate_from(1, raw)` remplit le champ nouveau avec default + retourne resource v2 + `push_warning("[camera-settings] migrating v1 → v2")` loggé + pas de crash.
- [ ] **AC-CAM-SAVE-3** : `GIVEN` `user://settings/camera.tres` corrompu (bytes flippés, header invalide, etc.), `WHEN` `CameraSystem._ready()` boot, `THEN` `SettingsResource.load_or_default()` retourne `CameraSettings.create_defaults()` (`mouse_sensitivity = 0.0022`, `mouse_y_inverted = false`, `fov_user_offset = 0.0`, `_settings_version = CURRENT_VERSION`) + `push_warning("[settings] user://settings/camera.tres corrupted, using defaults")` loggé + fichier corrompu **non-réécrit au boot** (réécriture only on next explicit `save_settings()` per ADR-0014 D-4).
- [ ] **AC-CAM-SAVE-4** : `GIVEN` first launch (no `user://settings/camera.tres`, sub-folder peut ne pas exister), `WHEN` `CameraSystem._ready()` boot, `THEN` defaults appliqués sans warning + `_ensure_dir()` crée `user://settings/` idempotent + création fichier au premier `save_settings()` event.

**Bonus tests recommandés** :
- `test_camera_settings_defaults_version_matches_current` : asserte `CameraSettings.create_defaults()._settings_version == CameraSettings.CURRENT_VERSION` (mitigation Risk schema drift, ADR-0014 Risks).
- `test_round_trip_identity` : save → reload → asserte les 3 valeurs identiques (full lifecycle).

---

## Implementation Notes

**Files à créer/modifier** :

1. `src/core/settings/settings_resource.gd` (NEW) — helper static class `SettingsResource extends RefCounted` exposant `load_or_default(system, default_factory, migrate)` + `save(resource, system)` + `_resolve_path(system)` + `_ensure_dir()`. **Réutilisable** pour input-010 + futures audio/accessibility settings.
2. `src/core/settings/camera_settings.gd` (NEW) — Resource class `CameraSettings extends Resource` avec `CURRENT_VERSION = 1`, `_settings_version` exporté, 3 `@export` properties (mouse_sensitivity range [0.0005, 0.012] default 0.0022, mouse_y_inverted default false, fov_user_offset range [-15.0, 15.0] default 0.0), `static create_defaults()` + `static migrate_from(version, raw)`.
3. `src/gameplay/camera/camera_system.gd` (MODIFIED) — `_ready()` charge settings via `SettingsResource.load_or_default("camera", Callable(CameraSettings, "create_defaults"), Callable(CameraSettings, "migrate_from")) as CameraSettings` ; remplacer hardcoded values par lecture de `_settings.mouse_sensitivity` / `.mouse_y_inverted` / `.fov_user_offset` ; exposer `save_settings() -> Error` qui delegate à `SettingsResource.save(_settings, "camera")`.
4. `tests/unit/settings/camera_settings_test.gd` (NEW) — 4 ACs + 2 bonus tests (defaults version + round-trip identity).
5. `tests/integration/settings/camera_settings_lifecycle_test.gd` (NEW) — corruption fallback + first-launch + sub-folder bootstrap (utilise `user://test_settings/` mock path pour cleanup).

**Ordre d'implémentation suggéré** :
1. SettingsResource helper (réutilisable, isolé) → tests unit dédiés.
2. CameraSettings resource → tests unit defaults + migration round-trip.
3. CameraSystem integration → tests integration lifecycle + corruption.

---

## QA Test Cases

| AC | Test type | File | Pre-conditions | Steps | Expected |
|----|-----------|------|----------------|-------|----------|
| AC-CAM-SAVE-1 | Integration | `tests/integration/settings/camera_settings_lifecycle_test.gd::test_save_serializes_three_values` | sub-folder existe (test isolated mock path) | Instancier CameraSettings avec valeurs custom, `SettingsResource.save(s, "test_camera")`, reload via `SettingsResource.load_or_default(...)`. | 3 valeurs identiques + `_settings_version == CURRENT_VERSION`. |
| AC-CAM-SAVE-2 | Unit | `tests/unit/settings/camera_settings_test.gd::test_migrate_from_v0_returns_current_version` | n/a | Instancier CameraSettings avec `_settings_version = 0`, appeler `CameraSettings.migrate_from(0, raw)`. | Retourne resource avec `_settings_version == CURRENT_VERSION` + warning loggé. |
| AC-CAM-SAVE-3 | Integration | `tests/integration/settings/camera_settings_lifecycle_test.gd::test_corruption_fallback_defaults_no_rewrite` | Écrire bytes corrompus dans `user://test_settings/camera.tres` | Appeler `SettingsResource.load_or_default("test_camera", ...)`. | Retourne defaults + warning loggé + fichier sur disque inchangé (pas réécrit). |
| AC-CAM-SAVE-4 | Integration | `tests/integration/settings/camera_settings_lifecycle_test.gd::test_first_launch_defaults_silent` | Aucun fichier sur disque, sub-folder potentiellement absent | `SettingsResource.load_or_default("test_camera", ...)`. | Retourne defaults + AUCUN warning loggé + sub-folder créé (idempotent). |
| Bonus | Unit | `tests/unit/settings/camera_settings_test.gd::test_defaults_version_matches_current` | n/a | `CameraSettings.create_defaults()._settings_version`. | `== CameraSettings.CURRENT_VERSION`. |
| Bonus | Integration | `tests/integration/settings/camera_settings_lifecycle_test.gd::test_round_trip_identity` | n/a | save → load → compare. | 3 valeurs identiques. |

**Cleanup obligatoire** : `after_test()` doit `DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings/camera.tres"))` pour éviter pollution cross-test (ADR-0014 Risks).

---

## Test Evidence

- [ ] `tests/unit/settings/camera_settings_test.gd` — 4 unit tests (2 ACs + 2 bonus). Type Logic → automatic test BLOCKING.
- [ ] `tests/integration/settings/camera_settings_lifecycle_test.gd` — 4 integration tests (3 ACs + 1 bonus round-trip). Type Integration → automatic test BLOCKING.

---

## Out of Scope

- Input settings persistence (`input_settings.tres` TR-inp-009) — story séparée `production/epics/input-system/story-010-settings-persistence.md`, même ADR-0014.
- Menu UI de toggle/slider pour édition settings — owned par Menu/Settings epic (Tier 2+).
- Cloud sync, chiffrement, multi-profile — déférés Tier 2+/3 (ADR-0014 §Constraints).

---

## Dependencies

- **Depends on** : ADR-0014 Save/Load Settings Infrastructure (Accepted 2026-05-02).
- **Soft depends on** (consumers existants à brancher) : Story 002 (mouse_sensitivity consommé via InputManager — settings devra propager vers InputManager via setter), Story 006 (`fov_user_offset` appliqué sur `BASE_FOV` dans CameraSystem._update_fov_dash).
- **Unlocks** : Settings menu persistence cohérente Tier 2+ ; Pillar UX « settings respectés entre sessions ».

---

## Notes

Cette story est **Polish P3** (non-MVP, post-Sprint 1). Implémentation peut être programmée après MVP release. SettingsResource helper créé ici est **réutilisable** pour input story-010 (création parallèle ou séquentielle).
