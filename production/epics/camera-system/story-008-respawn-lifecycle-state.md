# Story 008: Respawn lifecycle — died/respawned handlers + state + idempotence + pitch/yaw preservation

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: M (4-6 heures) — 2 handlers + state enum + pré-création overlay au `_ready()` + patch story-003 mouse_motion gate + suite de 3 tests Integration GdUnit4

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-001` (reset effets post-respawn, partie ownership scene tree)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0005 (Movement Signals Architecture)
**ADR Decision Summary**: ADR-0005 D-2 fige signaux canoniques `died()` et `respawned(position: Vector3)` ; D-6 acte ordre intra-tick (`died` terminal, `respawned` reset implicite) ; D-8 acte idempotence (signals transition 1× par changement avec guard `if _state == NEW: return`). Camera consume ces deux signals et maintient son propre mini-state `Active ↔ Respawning` pour gater le handler mouse_motion pendant `RESPAWN_DELAY=50ms` (owned par Movement). Décision creative-director r1 : **pitch ET yaw préservés** au respawn (Ghostrunner approach, évite désorientation Pillar 3 die-retry).

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Consumer `CONNECT_DEFERRED` iff allocation Node / > 256 B / > 0.5 ms (ADR-0005 D-5). Ici : handler `_on_died` crée **dynamiquement** un `ColorRect` + `CanvasLayer` via `.new()` au premier appel si absent (cf. GDD Edge Case « overlay ColorRect n'existe pas »). Alloc Node = **consumer lourd** → `CONNECT_DEFERRED` recommandé. Mais : on peut pre-créer l'overlay au `_ready()` (one-shot alloc hors hot-path) → handler devient léger (toggle `visible` + `modulate`) → `CONNECT_0` synchrone OK. **Préférer pré-création au `_ready`.**

**Control Manifest Rules (Presentation layer + Core consumer)**:
- Required : handler `_on_died` idempotent (guard `if _state == RESPAWNING: return` première ligne) ; reset `camera_effects.rotation.z = 0`, `camera3d.fov = BASE_FOV`, `camera3d.rotation = Vector3.ZERO`, `_shake_offset = Vector3.ZERO` dans `_on_respawned` ; **ne PAS toucher** `camera_arm.rotation.x` ni `player.rotation.y` (préservés) ; consumer synchrone si overlay pré-créé au `_ready()`
- Forbidden : muter `player.*` depuis handler signal (`mutate_movement_state_from_signal_handler` forbidden) ; muter pitch/yaw au respawn (décision Ghostrunner) ; créer Node en handler signal runtime (pré-créer au `_ready`)
- Guardrail : handler zero-alloc après init

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [x] **AC-CAM-40** : `GIVEN` Camera Active, `WHEN` Movement émet `died()`, `THEN` dans le même tick : Camera entre en Respawning, overlay `ColorRect` visible à `alpha=0.6` couleur `(0.4, 0.0, 0.0, 0.6)`, signals `mouse_motion` suivants ignorés (rotation figée).
- [x] **AC-CAM-41** : `GIVEN` Camera Respawning depuis `RESPAWN_DELAY=50ms`, `WHEN` Movement émet `respawned(Vector3(10, 2, 5))`, `THEN` `camera_effects.rotation.z == 0`, `camera3d.fov == BASE_FOV == 90°`, `camera3d.rotation == Vector3.ZERO`, `_shake_offset == Vector3.ZERO`, ET **`camera_arm.rotation.x` inchangé (pitch préservé)**, ET **`player.rotation.y` inchangé (yaw préservé)** — Ghostrunner approach.
- [x] **AC-CAM-43** : `GIVEN` Camera en état Respawning, `WHEN` Movement émet un second `died()` dans le délai (cas edge idempotence), `THEN` aucun second cycle de fade n'est déclenché (early return `if state == Respawning: return` en première ligne du handler `died`). Miroir de Movement AC-MV-41.

> AC-CAM-42 (Visual/Feel fade 100ms + flash 50ms) couvert par Story 009.

---

## Implementation Notes

*Derived from GDD Rule 9 + Rule 15 gate + ADR-0005 D-6/D-8 :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
enum State { ACTIVE, RESPAWNING }

const RESPAWN_OVERLAY_COLOR: Color = Color(0.4, 0.0, 0.0, 0.6)

var _state: State = State.ACTIVE
var _canvas_layer: CanvasLayer
var _overlay: ColorRect

func _ready() -> void:
    # ... existing setup ...
    _setup_overlay()  # pré-création one-shot au boot, hors hot-path
    var player: CharacterBody3D = get_parent()
    player.died.connect(_on_died)
    player.respawned.connect(_on_respawned)

func _setup_overlay() -> void:
    _canvas_layer = CanvasLayer.new()
    _canvas_layer.layer = 100  # au-dessus du HUD
    add_child(_canvas_layer)
    _overlay = ColorRect.new()
    _overlay.anchor_right = 1.0
    _overlay.anchor_bottom = 1.0
    _overlay.color = RESPAWN_OVERLAY_COLOR
    _overlay.visible = false
    _canvas_layer.add_child(_overlay)

func _on_died() -> void:
    # Idempotence — AC-CAM-43, miroir Movement AC-MV-41
    if _state == State.RESPAWNING:
        return
    _state = State.RESPAWNING
    _overlay.color = RESPAWN_OVERLAY_COLOR
    _overlay.visible = true
    # Note : gate mouse_motion pendant Respawning — voir Story 003 `_on_mouse_motion`,
    # il faut ajouter `if _state == State.RESPAWNING: return` dans le handler
    # (patch croisé documenté dans "Out of Scope" et valid with existing test updates)

func _on_respawned(_position: Vector3) -> void:
    # Reset effets visuels SAUF pitch (camera_arm.rotation.x) et yaw (player.rotation.y)
    # — Ghostrunner approach, décision creative-director r1 2026-04-21
    _camera_effects.rotation.z = 0.0
    _camera3d.fov = BASE_FOV
    _camera3d.rotation = Vector3.ZERO
    _shake_offset = Vector3.ZERO
    _overlay.visible = false
    # Note : fade alpha 0.6→0 + flash blanc 50ms → Story 009
    _state = State.ACTIVE
```

**Patch story-003 requis** : ajouter gate `_state == RESPAWNING` dans `_on_mouse_motion` :

```gdscript
func _on_mouse_motion(delta: Vector2) -> void:
    if _state == State.RESPAWNING:  # nouveau gate
        return
    if not InputManager.is_mouse_captured():  # story 003
        return
    if not InputManager.enabled:                # story 003
        return
    # ... Story 002 apply logic ...
```

- **Pré-création overlay `_ready()`** : one-shot alloc au boot, hors hot-path → zero-alloc respecté à runtime.
- **Overlay créé dynamiquement par Camera** (GDD Rule 9 + Edge Case) : pas de dépendance à une scène externe préfaite. Si un setup futur fournit un `ColorRect` enfant nommé (pattern `%RespawnOverlay`), on peut l'utiliser à la place — non requis MVP.
- **Reset checklist exhaustive** : `camera_effects.rotation.z`, `camera3d.fov`, `camera3d.rotation`, `_shake_offset`. **Ne touche PAS** `camera_arm.rotation.x` (pitch), `player.rotation.y` (yaw) — Ghostrunner approach.
- **Idempotence `_on_died`** : early return si déjà `RESPAWNING`. Second `died()` dans le délai 50ms = no-op. Miroir AC-MV-41 Movement.
- **Connection synchrone `CONNECT_0`** : possible après pré-création overlay (handler léger = toggle bool + color reset + scalar assigns). Zero-alloc respecté.
- **Fade alpha + flash blanc** : **PAS DANS CETTE STORY** — Story 009 ajoute la trajectoire alpha `0.6 → 0` 100 ms avec `Color(1,1,1,0.9)` intercalé 50 ms.
- **Paused state (menu open)** : handler `_on_died` inchangé (mouse_motion déjà gated par enabled story 003). Respawning pendant Paused → comportement naturel du state `RESPAWNING` qui n'interagit pas avec `enabled`.
- **Performance budget** : impact négligeable. `_on_died` (toggle bool + color assign + visible=true) ≤ 0.05 ms par appel ; `_on_respawned` (4 scalar resets + visible=false) ≤ 0.05 ms par appel ; tous deux émis 1× par cycle die→respawn (~50 ms d'écart, fréquence non hot-path). Reste largement sous le budget caméra ADR-0002 VC-6 (`_process` ≤ 0.2 ms p99). Zero-alloc respecté (overlay pré-créé au `_ready()`, color reuse `RESPAWN_OVERLAY_COLOR` const). Pas de mesure dédiée requise MVP — perf vérifiée en aval par Story 012.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 009 : trajectoire fade alpha `0.6 → 0` sur 100 ms + flash blanc `(1,1,1,0.9)` 50 ms — Visual/Feel, screenshot evidence.
- Story 011 : `_exit_tree()` disconnect `player.died` + `player.respawned`.
- Story 012 : mesure perf du handler `_on_died` + `_on_respawned`.

---

## QA Test Cases

**AC-CAM-40 (died → Respawning + overlay + mouse gate)** — Integration

- Given : Camera Active, `_state == ACTIVE`, `_overlay.visible == false`, mouse en état actif
- When : `player.died.emit()` puis 1 frame `_process` ; puis `player.mouse_motion.emit(Vector2(100, 0))` (ou simulate via InputManager)
- Then : `_state == RESPAWNING` ; `_overlay.visible == true` ; `_overlay.color == Color(0.4, 0, 0, 0.6)` ; `player.rotation.y` inchangé après l'émission mouse_motion post-death
- Edge cases : `died()` pendant shake actif (`_shake_offset != 0`) → shake continue son decay (pas reset dans `_on_died`, seulement dans `_on_respawned`) ; `died()` avec `_state == ACTIVE` mais overlay pré-existant visible (cas dev) → réinitialise `color` au default

**AC-CAM-41 (respawned → reset effets sauf pitch/yaw)** — Integration

- Given : `_state == RESPAWNING`, `_camera_effects.rotation.z = 0.35`, `_camera3d.fov = 100`, `_camera3d.rotation = Vector3(0.1, 0, 0.05)`, `_shake_offset = Vector3(0, 0, 0.05)`, `_camera_arm.rotation.x = -0.7` (pitch), `player.rotation.y = 1.5` (yaw)
- When : `player.respawned.emit(Vector3(10, 2, 5))`
- Then :
  - `_camera_effects.rotation.z == 0.0`
  - `_camera3d.fov == 90.0`
  - `_camera3d.rotation == Vector3.ZERO`
  - `_shake_offset == Vector3.ZERO`
  - `_camera_arm.rotation.x == -0.7` (PRÉSERVÉ)
  - `player.rotation.y == 1.5` (PRÉSERVÉ)
  - `_overlay.visible == false`
  - `_state == ACTIVE`
- Edge cases : respawned sans died précédent (dev test) → handler s'exécute quand même (pas de guard) — reset effets même si déjà à leurs valeurs default, idempotent ; position ignorée pour ce test (Camera ne déplace pas le Player — c'est Movement qui le fait)

**AC-CAM-43 (died idempotence)** — Logic

- Given : `_state == RESPAWNING` (un premier `died()` déjà émis)
- When : second `player.died.emit()` émis
- Then : aucune modification de `_overlay.color`, `_overlay.visible`, `_state` ; early return effectif (miroir Movement AC-MV-41)
- Edge cases : 10× `died()` consécutifs dans le même tick → un seul effet ; `died()` → `respawned()` → `died()` à nouveau → deuxième cycle fonctionne normalement (state a été remis à `ACTIVE` entre les deux)

---

## Test Evidence

**Story Type** : Integration
**Required evidence** : `tests/integration/camera/story-008-respawn-lifecycle_test.gd` — AC-CAM-40/41/43 via émission `player.died` / `player.respawned` + assertions état + reset effets + préservation pitch/yaw

**Status** : [x] Created — `tests/integration/camera/story_008_respawn_lifecycle_test.gd` (underscore convention vs hyphen spec, cohérent stories 005/006/007). 5/5 PASSED 101 ms (`reports/report_145`).

---

## Dependencies

- Depends on : Story 005 (`_camera_effects.rotation.z` tilt existe pour reset), Story 006 (`_camera3d.fov` FOV existe), Story 007 (`_shake_offset` + `_camera3d.rotation` shake existent), Story 003 (`_on_mouse_motion` gate patché — requiert ajout `_state == RESPAWNING` check)
- Unlocks : Story 009 (fade alpha + flash blanc overlay), Story 010 (reduce_motion aux effets reset ici)

---

## Completion Notes

**Completed** : 2026-05-02
**Verdict** : COMPLETE WITH NOTES
**Criteria** : 3/3 passing (AC-CAM-40, AC-CAM-41, AC-CAM-43) — 5/5 tests PASSED 101 ms (`reports/report_145`).

**Files livrés** :
- `src/gameplay/camera/camera_system.gd` (MODIFIED) — enum State {ACTIVE, RESPAWNING} + RESPAWN_OVERLAY_COLOR/RESPAWN_OVERLAY_LAYER consts + `_setup_overlay()` (one-shot alloc `_ready()` hors hot-path) + `_on_died()` idempotent (AC-CAM-43 early return) + `_on_respawned()` reset effets SAUF pitch/yaw (Ghostrunner) + getters publics (`get_respawn_overlay`, `is_respawning`) + gate Respawning dans `_on_mouse_motion` (AC-CAM-40).
- `tests/helpers/mock_player_with_dash_signals.gd` (MODIFIED +9 L) — ajout signaux `died()` + `respawned(position: Vector3)` ADR-0005 D-2 canonical.
- `tests/integration/camera/story_008_respawn_lifecycle_test.gd` (NEW 270 L) — 5 tests GdUnit4 couvrant AC-CAM-40 ×2 + AC-CAM-41 + AC-CAM-43 ×2 (incluant cycle complet died→respawned→died).

**Test-Criterion Traceability** : 5/5 COVERED (100%).

| Criterion | Test | Status |
|-----------|------|--------|
| AC-CAM-40 (overlay show) | `test_ac_cam_40_died_enters_respawning_and_shows_overlay` | COVERED |
| AC-CAM-40 (mouse gate) | `test_ac_cam_40_mouse_motion_during_respawning_does_not_rotate_player` | COVERED |
| AC-CAM-41 (reset + pitch/yaw préservés) | `test_ac_cam_41_respawned_resets_effects_but_preserves_pitch_yaw` | COVERED |
| AC-CAM-43 (early return) | `test_ac_cam_43_second_died_during_respawning_is_noop` | COVERED |
| AC-CAM-43 (cycle complet) | `test_ac_cam_43_died_respawned_died_cycle_works_normally` | COVERED |

**ADR Compliance** : COMPLIANT
- ADR-0002 ownership matrice respectée (tilt = camera_effects.rotation.z, FOV = camera3d.fov, shake = camera3d.rotation assignation, pitch/yaw NON touchés au reset)
- ADR-0005 D-2 (signaux canoniques) + D-5 (SYNC consumer léger post pré-création) + D-7 (no Movement mutation) + D-8 (idempotence guard)
- Manifest 2026-04-23 zero-alloc handler ✓ (overlay pré-créé `_ready()`)

**Deviations** :
- ADVISORY-1 : Test filename `story_008_respawn_lifecycle_test.gd` (underscores) au lieu du spec `story-008-respawn-lifecycle_test.gd` (hyphens). Convention projet underscores cohérente avec stories 005/006/007.
- ADVISORY-2 : Test setup workaround injection manuelle `_camera_system._camera_effects/_camera3d/_player` car `%CameraEffects` ne résout pas headless sans scene owner. Pattern hérité tech debt camera (commun stories 005/006/007). Refacto post-MVP via PackedScene mock ou set_owner discipline.
- ADVISORY-3 : Code review S-1 (`anchors_preset` idiom Godot 4) + S-2 (test pattern refacto) + S-3 (defensive `_overlay.color` reset). Tous non-bloquants.

**Code Review** : APPROVED WITH SUGGESTIONS (Solo mode — LP-CODE-REVIEW gate skipped, manual review pass clean).
- Engine specialist : `godot-gdscript-specialist` (review direct effectué, aucune API post-cutoff)
- Standards : 6/6 passing
- Architecture : CLEAN
- SOLID : COMPLIANT
- Game-specific : CLEAN

**Camera Epic Progress** : 8/12 stories Complete (001-008). Stories 009-012 Ready.

**Next Recommended** : `/story-readiness production/epics/camera-system/story-009-*` (fade alpha + flash blanc — Visual/Feel, dépend story-008 just closed) puis `/dev-story`.

