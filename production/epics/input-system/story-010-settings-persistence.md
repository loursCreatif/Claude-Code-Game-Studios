# Story 010: Settings persistence `input_settings.tres`

> **Epic**: input-system
> **Status**: Ready
> **Layer**: Foundation
> **Type**: Config/Data
> **Manifest Version**: 2026-04-23
> **Estimate**: M (4-6 h, Resource class + InputManager._ready load + save explicit + 6 properties + 3 ACs tests)
> **Performance**: settings load < 1 ms boot one-shot ; save < 5 ms rare event off-hot-path (ADR-0014 Performance Implications).

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-inp-009`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: **ADR-0014 Save/Load Settings Infrastructure** (Accepted 2026-05-02)
**ADR Decision Summary**: Resource (.tres) typé pour settings (D-1) + helper static class `SettingsResource` zero autoload (D-5) + sub-folder `user://settings/<system>.tres` (D-2 — path canonique : `user://settings/input.tres`) + versioning `_settings_version: int` + migration forward-only (D-3) + corruption fallback defaults+warning+rewrite-on-next-save (D-4) + factory function `create_defaults()` obligatoire (D-7) + outbound-zero (D-10).

**Engine**: Godot 4.6 | **Risk**: LOW (`Resource` + `ResourceSaver.save` + `ResourceLoader.load` API stables 3.x — validé dans ADR-0014 Engine Compatibility)
**Engine Notes**: `duplicate(true)` only (pas `duplicate_deep()` 4.5+ — ADR-0014 D-8). `make_dir_recursive_absolute()` pour bootstrap sub-folder. Pas d'API post-cutoff requise.

**Control Manifest Rules (Foundation layer)**:
- Required (post-ADR-0014, à re-générer): à définir par l'ADR
- Forbidden (acquis ADR-0004) : jamais de sensitivity hard-codée en code gameplay (doit venir d'un Resource)

---

## Acceptance Criteria

*Path canonique (ADR-0014 D-2) : `user://settings/input.tres` (sub-folder, pas racine `user://`).*

- [ ] **AC-INP-SAVE-1 (schema)** : Resource class `InputSettings extends Resource` créée avec :
  - [ ] `CURRENT_VERSION: int = 1` (constant)
  - [ ] `_settings_version: int = CURRENT_VERSION` (@export)
  - [ ] `mouse_sensitivity: float = 0.0022` (@export_range [0.0005, 0.012])
  - [ ] `mouse_y_inverted: bool = false` (@export)
  - [ ] `mouse_capture_at_boot: bool = false` (@export)
  - [ ] `focus_regain_window_ms: int = 50` (@export_range [20, 150])
  - [ ] `debug_overlay_default: bool = false` (@export)
  - [ ] `latency_anomaly_threshold_ms: float = 0.1` (@export_range [0.05, 1.0])
  - [ ] `static create_defaults() -> InputSettings`
  - [ ] `static migrate_from(version: int, raw: InputSettings) -> InputSettings` (forward-only)
- [ ] **AC-INP-SAVE-2 (boot load)** : `InputManager._ready()` charge settings via `SettingsResource.load_or_default("input", Callable(InputSettings, "create_defaults"), Callable(InputSettings, "migrate_from")) as InputSettings`. Stocke dans `var settings: InputSettings` member.
- [ ] **AC-INP-SAVE-3 (save explicit)** : `InputManager.save_settings() -> Error` delegate à `SettingsResource.save(settings, "input")`. Logger Error si != OK.
- [ ] **AC-P-1 (round-trip identity)** : `settings.mouse_sensitivity = 0.0035`, `save_settings()`, recharger via helper → `mouse_sensitivity == 0.0035` + `_settings_version == CURRENT_VERSION`.
- [ ] **AC-P-2 (first launch defaults silent)** : aucun fichier sur disque, sub-folder potentiellement absent → `_ready()` → defaults appliqués (`mouse_sensitivity == 0.0022`) + AUCUN warning + sub-folder créé idempotent.
- [ ] **AC-P-3 (corruption fallback)** : fichier corrompu (bytes flippés ou `_settings_version = 999` invalide) → `_ready()` → `SettingsResource.load_or_default()` retourne `InputSettings.create_defaults()` + `push_warning("[settings] user://settings/input.tres corrupted, using defaults")` + fichier corrompu **non-réécrit au boot** (réécriture only on next explicit `save_settings()` per ADR-0014 D-4).

**Bonus tests recommandés** :
- `test_input_settings_defaults_version_matches_current` : asserte `InputSettings.create_defaults()._settings_version == InputSettings.CURRENT_VERSION` (mitigation Risk schema drift, ADR-0014 Risks).
- `test_migrate_from_v0` : vérifie migration v0 → CURRENT_VERSION (futur bump).

---

## Implementation Notes

**Files à créer/modifier** :

1. `src/core/settings/settings_resource.gd` — helper static class réutilisable. **Si déjà créé par camera story-013, sinon créer ici** (mêmes 3 verbes : `load_or_default`, `save`, `_resolve_path`, `_ensure_dir`).
2. `src/core/settings/input_settings.gd` (NEW) — Resource class :

```gdscript
class_name InputSettings extends Resource

const CURRENT_VERSION: int = 1

@export var _settings_version: int = CURRENT_VERSION
@export_range(0.0005, 0.012, 0.0001) var mouse_sensitivity: float = 0.0022
@export var mouse_y_inverted: bool = false
@export var mouse_capture_at_boot: bool = false
@export_range(20, 150, 1) var focus_regain_window_ms: int = 50
@export var debug_overlay_default: bool = false
@export_range(0.05, 1.0, 0.01) var latency_anomaly_threshold_ms: float = 0.1

static func create_defaults() -> InputSettings:
    var s := InputSettings.new()
    s._settings_version = CURRENT_VERSION
    return s

static func migrate_from(version: int, raw: InputSettings) -> InputSettings:
    if version >= CURRENT_VERSION:
        return raw
    push_warning("[input-settings] migrating v%d → v%d" % [version, CURRENT_VERSION])
    raw._settings_version = CURRENT_VERSION
    return raw
```

3. `src/core/input_manager.gd` (MODIFIED) :

```gdscript
var settings: InputSettings

func _ready() -> void:
    # ... existing code ...
    settings = SettingsResource.load_or_default(
        "input",
        Callable(InputSettings, "create_defaults"),
        Callable(InputSettings, "migrate_from"),
    ) as InputSettings
    # consume settings.mouse_sensitivity, focus_regain_window_ms, etc.

func save_settings() -> Error:
    return SettingsResource.save(settings, "input")
```

4. `tests/unit/input/input_settings_test.gd` (NEW) — 3 ACs (schema + version match + migration round-trip) + 2 bonus.
5. `tests/integration/input/input_settings_lifecycle_test.gd` (NEW) — corruption fallback + first-launch + round-trip identity.

**Notes clés** :
- **Tuning knob `focus_regain_window_ms`** (GDD) : InputManager lit `settings.focus_regain_window_ms` au `_ready()` et remplace la constante `FOCUS_REGAIN_WINDOW_USEC` de story-005 (× 1000 pour µs). **Cette migration est in-scope cette story** (1 ligne change dans story-005 hot path).
- **Validation clamp redondance** : `@export_range` enforce les bornes au boot via Godot validation (rejected si `_settings_version` corrompu détecté côté ADR-0014 D-4 fallback). NaN edge case : `@export_range` ne couvre pas NaN explicitement → ajouter `if is_nan(s.mouse_sensitivity): s = create_defaults()` après load (ou dans `migrate_from`).
- **Coordination camera-013** : si camera story-013 implémentée AVANT input-010, `settings_resource.gd` existe déjà — réutiliser. Sinon, input-010 crée le helper. **Convention : ne pas dupliquer.**

---

## Out of Scope

*Handled by neighbouring stories / post-MVP:*

- Remap UI (post-MVP Tier 2+) : bindings sliders + conflict detection — hors cette story
- Sensitivity slider Settings menu : ownership Menu System GDD (à écrire)
- Migration versions : couvert par ADR-0014 générique pour tous les systèmes (InputSettings + CameraSettings + futurs)
- Story 005 : consommateur `focus_regain_window_ms` une fois chargé

---

## QA Test Cases

> Draft — à valider après ADR-0014 Accepted.

- **AC-P-1** : round-trip save/load
  - Given : InputManager instancié, `settings.mouse_sensitivity = 0.0035`, `save_settings()` appelé
  - When : nouvelle instance InputManager via test fixture (reload ou nouvelle scène test)
  - Then : `settings.mouse_sensitivity == 0.0035`

- **AC-P-2** : fallback absent
  - Given : `user://input_settings.tres` supprimé (test fixture clean)
  - When : `InputManager._ready()`
  - Then : `settings.mouse_sensitivity == 0.0022` (default) ; aucun warning ; `save_settings()` appelé ensuite écrit le fichier

- **AC-P-3** : fallback corruption
  - Given : `input_settings.tres` écrit manuellement avec `mouse_sensitivity = NaN` ou `= 10.0` (hors range)
  - When : `InputManager._ready()`
  - Then : `settings.mouse_sensitivity == 0.0022` + `push_warning` visible dans logs

---

## Test Evidence

**Story Type**: Config/Data (test evidence ADVISORY — mais la story embarque assez de logique unit-testable pour mériter Logic ACs : adopter Logic + Integration tests parallèle camera-013 pattern).

**Required evidence**:
- `tests/unit/settings/input_settings_test.gd` — AC-INP-SAVE-1 schema + bonus version match + migration v0→v1.
- `tests/integration/settings/input_settings_lifecycle_test.gd` — AC-P-1 round-trip + AC-P-2 first-launch silent + AC-P-3 corruption fallback.
- Smoke check post-save Tier 2+ Settings menu (manual) : `production/qa/smoke-{date}.md` — settings modifié via menu, restart jeu, paramètre persisté.

**Status**: [ ] To be created during implementation per ADR-0014 D-3 + D-4 + D-5 patterns.

---

## Unblock Status — RESOLVED 2026-05-02

- [x] `/architecture-decision` ADR-0014 Save/Load Settings Infrastructure écrite + status **Accepted** (2026-05-02).
- [x] ADR-0014 §Engine Compatibility traite `ResourceLoader` / `ResourceSaver` Godot 4.6 (LOW risk).
- [x] ADR-0014 D-5 tranche ownership : helper static class `SettingsResource` + per-system autonomous load au `_ready()` consumer (zero autoload).
- [x] ADR-0014 D-3 migration forward-only par champ `_settings_version` + factory `create_defaults()` ; D-4 corruption fallback defaults+warning+rewrite-on-next-save.
- [x] `tr-registry.yaml` : TR-inp-009 `covered_by: [ADR-0014]`.
- [ ] Re-run `/create-control-manifest` (à programmer prochain manifest version bump — pas blocking implémentation).

**Story Ready** — implémentation peut démarrer.

---

## Dependencies

- **Depends on** : ADR-0014 Save/Load Settings Infrastructure (Accepted 2026-05-02).
- **Soft depends on** : Story 005 (consommera `focus_regain_window_ms` après cette story livrée).
- **Coordination** : camera story-013 partage le helper `SettingsResource` — implémenter en parallèle ou séquentiellement (pas de duplication).
- **Unlocks** : sensitivity slider Settings menu Tier 2+ ; camera story-013 (peut s'appuyer sur le helper si cette story livrée en premier).
