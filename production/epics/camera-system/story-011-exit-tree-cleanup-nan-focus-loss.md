# Story 011: _exit_tree cleanup + NaN safeguard + focus-loss behavior

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-001` (lifecycle discipline — ownership/ségrégation par étage garantit l'absence de drift post-cleanup)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0004 (Input API & Focus Handling)
**ADR Decision Summary**: GDD Rule 16 acte pattern canonique Godot `_exit_tree()` disconnect explicite (symétrie `_ready()` ↔ `_exit_tree()`) — évite `"Signal target was freed"` au scene reload. GDD Edge Cases : NaN reset à 0 + `push_warning` (channel `camera`, severity WARN) ; focus-loss auto-pause via `InputManager.enabled = false` → Camera entre en Paused naturellement → tilt figé, reprend sa convergence au retour si state WallRunning maintenu.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Godot `_exit_tree()` appelé avant free ; pattern idiomatique pour disconnect signals. `is_finite(float)` GDScript standard depuis 4.0. `push_warning` avec prefix `[camera]` pour filtrage logs. Dual-focus 4.6 (VR-3) advisory : Camera ne réagit pas directement à FOCUS_OUT/IN (Input en est consumer primaire), donc pas de trap spécifique ici — mais le gate `InputManager.enabled` story 003 couvre indirectement.

**Control Manifest Rules (Presentation layer)**:
- Required : symétrie `_ready()` connect ↔ `_exit_tree()` disconnect pour tous signals Input/Movement consommés ; NaN detection sur `_camera_effects.rotation.z` chaque frame + fallback 0 + `push_warning`
- Forbidden : laisser des signaux connectés après free (produit `"Signal target was freed"` au scene reload) ; clamp silencieux NaN sans log (perte de signal diagnostic)
- Guardrail : zero overhead cleanup normal path (disconnect = metadata op) ; NaN check cost ≤ 0.005 ms/frame (1 bool check)

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [ ] **AC-CAM-63** : `GIVEN` scene reload (Player node free + reconstruit), `WHEN` Camera `_exit_tree()` s'exécute, `THEN` tous signals Input/Movement connectés dans `_ready()` sont explicitement disconnectés ; aucun log `"Signal target was freed"` ne doit apparaître au next spawn (Rule 16).
- [ ] **AC-CAM-64** : `GIVEN` app perd le focus pendant un tilt wall-run actif (alt-tab), `WHEN` focus restauré et `Player.state` encore WallRunning, `THEN` tilt reprend sa convergence vers `WALL_RUN_TILT_ANGLE * wall_side` sans glitch visible > 1 frame.
- [ ] **AC-CAM-NAN-1** : `GIVEN` `_camera_effects.rotation.z` devient NaN (simulation via test), `WHEN` next `_process` frame, `THEN` reset à 0 + `push_warning("[camera] rotation.z NaN detected, reset")` émis.

---

## Implementation Notes

*Derived from GDD Rule 16 + Edge Cases + Formulas r2 stability note :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
# Cleanup — symétrie _ready() ↔ _exit_tree() (Rule 16)
func _exit_tree() -> void:
    # Disconnect explicite de tous les signals connectés dans _ready()
    if InputManager.mouse_motion.is_connected(_on_mouse_motion):
        InputManager.mouse_motion.disconnect(_on_mouse_motion)
    var player: CharacterBody3D = get_parent()
    if player and is_instance_valid(player):
        if player.wall_jumped.is_connected(_on_wall_jumped):
            player.wall_jumped.disconnect(_on_wall_jumped)
        if player.died.is_connected(_on_died):
            player.died.disconnect(_on_died)
        if player.respawned.is_connected(_on_respawned):
            player.respawned.disconnect(_on_respawned)

# NaN safeguard — GDD Edge Case « camera_effects.rotation.z NaN »
# Appelé en début de _process, avant tilt lerp
func _safeguard_rotation() -> void:
    if not is_finite(_camera_effects.rotation.z):
        _camera_effects.rotation.z = 0.0
        push_warning("[camera] camera_effects.rotation.z NaN/Inf detected, reset to 0")

func _process(delta: float) -> void:
    _safeguard_rotation()     # this story — run first, avant tout calcul
    _update_tilt_wall_run(delta)  # Story 005
    _update_fov_dash(delta)        # Story 006
    _update_shake(delta)           # Story 007
```

- **`is_instance_valid(player)` check** : garde contre scene reload où `get_parent()` peut déjà avoir free le parent avant `_exit_tree` de Camera (ordre dépendant de l'arbre). `is_connected` ajoute une deuxième couche idempotent.
- **`disconnect` exceptions** : disconnect sans connection produit error GDScript — d'où les guards `is_connected`.
- **Focus-loss AC-CAM-64** : **pas de code spécifique cette story** — le comportement attendu découle naturellement de :
  1. Focus-out → Input auto-pause (`InputManager.enabled = false` via `request_disable` pattern, côté Input)
  2. `_process` continue de tourner (Godot continue `_process` et `_physics_process` même en focus-out par défaut)
  3. `_on_mouse_motion` gated par `enabled` story 003 → rotation figée
  4. Tilt lerp continue sa convergence vers `target_roll` qui reste calculé depuis `player.wall_normal` stable (Movement `_physics_process` gated aussi)
  5. Focus-in → enabled = true → motions reprennent, tilt continue lerp normal
  - Donc **test AC-CAM-64 valide le pattern** mais ne requiert pas de nouveau code spécifique. Test : simuler focus-out via `InputManager.request_disable(test_owner)` puis `release_enable_request(test_owner)`, vérifier continuité tilt.
- **NaN detection** : check seulement `_camera_effects.rotation.z` (le seul target lerp risqué — `_camera3d.fov` reste scalaire, `_shake_offset` déjà capé par `limit_length` qui retourne ZERO si NaN). Si d'autres valeurs deviennent suspectes empiriquement en prod, étendre.
- **Log level** : `push_warning` (WARN) — pas `push_error` (n'arrête pas debug run). Préfixe `[camera]` pour filtrer.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- InputManager `_notification(FOCUS_OUT/IN)` handling — owned par Input GDD (ADR-0004 D-5, D-6).
- Story 012 : mesure perf du cleanup (négligeable mais noté dans budget total).
- Full scene reload test harness (multi-respawn → multi-reload enchaînés) : relève de /soak-test en phase Polish.

---

## QA Test Cases

**AC-CAM-63 (cleanup disconnect)** — Integration

- Given : Player instancié, Camera `_ready()` exécuté, tous signals connectés (mouse_motion, wall_jumped, died, respawned)
- When : `player.queue_free()` → `_exit_tree()` de Camera s'exécute ; puis re-instantier un nouveau Player (`Player.tscn.instantiate()`)
- Then : aucun log `"Signal target was freed"` ou équivalent warning Godot dans la sortie ; le nouveau Player + Camera connectent leurs propres signals sans conflit
- Edge cases : free Camera avant Player (Camera est child du Player donc normalement Player free en premier) — le guard `is_instance_valid(player)` couvre le cas inverse ; double free Camera (via queue_free x2) — Godot gère, idempotence dans `_exit_tree` via `is_connected` check

**AC-CAM-64 (focus-loss tilt behavior)** — Integration

- Given : Player en WallRunning (wall_normal = Vector3(-1,0,0), wall_side = +1), `_camera_effects.rotation.z = 0.35` (tilt full)
- When : `InputManager.request_disable(focus_owner)` → `enabled = false` pendant 500 ms (simule focus-out) ; pendant ce temps `player.wall_normal` reste `Vector3(-1,0,0)` (Movement figé) ; puis `InputManager.release_enable_request(focus_owner)` → `enabled = true`
- Then : pendant `enabled = false`, le tilt reste à 0.35 (ou lerp vers 0.35 si déjà) car target stable et `_process` continue ; après `enabled = true`, tilt reste à 0.35 tant que wall_normal inchangé — aucun glitch visible > 1 frame
- Edge cases : focus-out pendant transition tilt (t=125ms, tilt à mi-chemin) → lerp continue pendant le pause (target stable), converge pendant le blocage ; focus-in synchronisé avec exit wall-run (wall_normal = ZERO) → tilt target bascule à 0, lerp vers 0 normal

**AC-CAM-NAN-1 (NaN reset + warning)** — Logic

- Given : `_camera_effects.rotation.z = NAN` (assigné via test `_camera_effects.rotation = Vector3(0, 0, NAN)`)
- When : `_process(1.0/60.0)` exécuté
- Then : `_camera_effects.rotation.z == 0.0` ; push_warning log contient `[camera]` et `NaN`
- Edge cases : `INF` positif / négatif → même traitement via `is_finite` ; NaN sur `.x` ou `.y` → pas couvert (hors scope — pitch/tilt vivent sur noeuds différents)

---

## Test Evidence

**Story Type** : Integration
**Required evidence** : `tests/integration/camera/story-011-exit-tree-nan-focus_test.gd` — AC-CAM-63 (scene reload test) + AC-CAM-64 (focus simulation via enabled) + AC-CAM-NAN-1 (inject NaN)

**Status** : [x] Created — 12/12 PASSED 265ms (`reports/report_162`)

---

## Dependencies

- Depends on : Story 001 (scene tree), Story 002 (mouse_motion connect), Story 005/006/007 (_process + handlers), Story 008 (died/respawned connects)
- Unlocks : Scene reload robustness (multi-respawn sessions), soak-test readiness

---

## Completion Notes

**Completed** : 2026-05-02
**Criteria** : 3/3 passing (AC-CAM-63 + AC-CAM-64 + AC-CAM-NAN-1) — 12 integration tests PASSED 265ms (`reports/report_162`)
**Files** :
- `src/gameplay/camera/camera_system.gd` (MODIFIED) — `_exit_tree()` lifecycle cleanup + `_safeguard_rotation()` NaN detection + `_process()` integration + cosmetic `= null` defaults pour `_canvas_layer`/`_overlay`/`_respawn_tween`
- `tests/integration/camera/story_011_exit_tree_nan_focus_test.gd` (NEW, 458L) — 12 GdUnit4 integration tests + cleanup défensif InputManager.enabled
**Deviations** :
- ADVISORY : Pre-existing tech debt RC-1 — `_update_tilt_wall_run` polls `_player.wall_normal` violant ADR-0002 Amendment A-1 (introduit story-005, hors scope story-011) — logged en tech debt
- ADVISORY : Pre-existing tech debt — stories 005-007 test harness fragility (13 failures en suite complète, setup sans injection manuelle `_camera_effects`/`_camera3d`) — logged en tech debt
**Test Evidence** : `tests/integration/camera/story_011_exit_tree_nan_focus_test.gd` (12/12 PASSED, AC-CAM-63 ×4 + AC-CAM-64 ×3 + AC-CAM-NAN-1 ×5)
**Code Review** : Complete (v1 CHANGES REQUIRED → v2 APPROVED WITH SUGGESTIONS après application RC-2 isolation test + RC-3 cosmétique ; RC-1 hors scope)
