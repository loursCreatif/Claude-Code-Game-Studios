# Story 010: Settings persistence `input_settings.tres` (BLOCKED)

> **Epic**: input-system
> **Status**: **Blocked** — attend ADR-0014 Save/Load Settings Infrastructure
> **Layer**: Foundation
> **Type**: Config/Data
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-inp-009`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: **❌ No ADR** — GAP G-2b (Input side)
**ADR Decision Summary**: Aucune ADR n'a encore figé le pattern Save/Load Settings pour le projet. `TR-cam-006` partage la même dépendance (G-2, Camera side). ADR-0014 Save/Load Settings Infrastructure planifiée en phase Polish per `architecture.md §8.5`. Cette story reste **Blocked** tant que l'ADR n'est pas Accepted.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Resource` + `ResourceSaver.save(res, path)` + `ResourceLoader.load(path)` est le pattern standard Godot (existe pre-cutoff). `user://` path est géré par la plateforme (Windows APPDATA / macOS Application Support / Linux XDG). Points à trancher par ADR-0014 : migration de versions, fallback corruption strategy, ownership du fichier (SaveLoadManager vs système propriétaire), timing (save immediate vs batched).

**Control Manifest Rules (Foundation layer)**:
- Required (post-ADR-0014, à re-générer): à définir par l'ADR
- Forbidden (acquis ADR-0004) : jamais de sensitivity hard-codée en code gameplay (doit venir d'un Resource)

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

> ⚠️ **Story Blocked** — ne pas démarrer avant Accepted de ADR-0014 Save/Load Settings Infrastructure. Les ACs ci-dessous sont un draft à valider contre l'ADR une fois écrite.

- [ ] Resource class `InputSettings extends Resource` créée avec propriétés typed `@export` :
  - [ ] `mouse_sensitivity: float = 0.0022` (safe range [0.0005, 0.012])
  - [ ] `mouse_y_inverted: bool = false`
  - [ ] `mouse_capture_at_boot: bool = false`
  - [ ] `focus_regain_window_ms: int = 50` (safe range [20, 150])
  - [ ] `debug_overlay_default: bool = false`
  - [ ] `latency_anomaly_threshold_ms: float = 0.1` (safe range [0.05, 1.0])
- [ ] `InputManager._ready()` : load `user://input_settings.tres` si présent ; fallback hardcoded defaults sinon + `push_warning` ; re-écrit au prochain save
- [ ] `InputManager.save_settings()` : écrit la resource courante vers `user://input_settings.tres`
- [ ] Validation clamp au load : si `mouse_sensitivity` hors safe range ou NaN → fallback 0.0022 + push_warning
- [ ] **AC-P-1** : `mouse_sensitivity = 0.0035` assigné → `save_settings()` → nouvelle instance `_ready()` → `mouse_sensitivity == 0.0035`
- [ ] **AC-P-2** : fichier absent → `_ready()` → `mouse_sensitivity == 0.0022` (default) ; prochain save écrit fichier valide
- [ ] **AC-P-3** : fichier avec `mouse_sensitivity = NaN` ou hors safe range → `_ready()` → fallback 0.0022 + `push_warning`
- [ ] **Post-ADR-0014** : alignement exact sur le pattern décidé (ownership SaveLoadManager vs InputManager, timing save, migration versions)

---

## Implementation Notes

*Tentative — à aligner avec ADR-0014:*

```gdscript
# src/core/input_settings.gd
class_name InputSettings
extends Resource

@export_range(0.0005, 0.012, 0.0001) var mouse_sensitivity: float = 0.0022
@export var mouse_y_inverted: bool = false
@export var mouse_capture_at_boot: bool = false
@export_range(20, 150, 1) var focus_regain_window_ms: int = 50
@export var debug_overlay_default: bool = false
@export_range(0.05, 1.0, 0.01) var latency_anomaly_threshold_ms: float = 0.1
```

```gdscript
# InputManager
const SETTINGS_PATH: String = "user://input_settings.tres"
const SENSITIVITY_SAFE_MIN: float = 0.0005
const SENSITIVITY_SAFE_MAX: float = 0.012
const SENSITIVITY_DEFAULT: float = 0.0022

var settings: InputSettings

func _load_settings() -> void:
    if ResourceLoader.exists(SETTINGS_PATH):
        settings = ResourceLoader.load(SETTINGS_PATH) as InputSettings
        if settings == null:
            push_warning("input_settings.tres corrompu — fallback defaults")
            settings = InputSettings.new()
        else:
            # Validation clamp
            var s := settings.mouse_sensitivity
            if is_nan(s) or s < SENSITIVITY_SAFE_MIN or s > SENSITIVITY_SAFE_MAX:
                push_warning("mouse_sensitivity hors range (%f) — fallback %f" % [s, SENSITIVITY_DEFAULT])
                settings.mouse_sensitivity = SENSITIVITY_DEFAULT
    else:
        settings = InputSettings.new()

func save_settings() -> void:
    var err := ResourceSaver.save(settings, SETTINGS_PATH)
    if err != OK:
        push_error("save_settings failed: %d" % err)
```

Notes clés :
- **Blocker structurel** : le pattern "qui écrit quand" (InputManager seul ? SaveLoadManager autoload central ?) dépend de ADR-0014. Ne pas implémenter avant que le choix soit acté — risque de refactor complet.
- **Points à résoudre par ADR-0014** :
  - Ownership : chaque système écrit son propre fichier vs centralisation
  - Migration : stratégie versions (ex : champs ajoutés/retirés)
  - Fallback corruption : hardcoded vs last-known-good vs prompt user
  - Timing : save synchrone à chaque mutation vs batched périodique
  - Threading : save async via `WorkerThreadPool` (attention `Input.*` main-thread only ADR-0004 D-7)
- **Tuning knob `focus_regain_window_ms`** (GDD) : une fois cette story déblockée, InputManager lit `settings.focus_regain_window_ms` au `_ready()` et remplace la constante `FOCUS_REGAIN_WINDOW_USEC` de story-005 (× 1000 pour µs).

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

**Story Type**: Config/Data
**Required evidence** (post-unblock):
- `tests/unit/input/settings_persistence_test.gd` — AC-P-1, AC-P-2, AC-P-3
- Smoke check post-save : `production/qa/smoke-{date}.md` — settings modifié via menu, restart jeu, paramètre persisté

**Status**: [ ] **Blocked — ADR-0014 non écrite**

---

## Unblock Checklist

- [ ] `/architecture-decision` ADR-0014 Save/Load Settings Infrastructure écrite + status Accepted
- [ ] ADR-0014 section Engine Compatibility traite `ResourceLoader` / `ResourceSaver` Godot 4.6
- [ ] ADR-0014 tranche ownership (per-system autonomous vs centralized SaveLoadManager)
- [ ] ADR-0014 couvre migration versions + fallback corruption
- [ ] `tr-registry.yaml` : TR-inp-009 `covered_by: [ADR-0014]` après Accepted
- [ ] Re-run `/create-control-manifest` pour capturer les nouvelles règles
- [ ] Cette story re-vérifier et update Implementation Notes contre le pattern final

---

## Dependencies

- Depends on: **ADR-0014 Save/Load Settings Infrastructure (not yet written)**, Story 005 (consommera `focus_regain_window_ms`)
- Unlocks: story équivalente Camera Settings (TR-cam-006 G-2a), fonctionnalité sensitivity slider Settings menu
