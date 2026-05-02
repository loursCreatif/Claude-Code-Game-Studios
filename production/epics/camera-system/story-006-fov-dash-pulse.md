# Story 006: FOV dash pulse — lerp camera3d.fov sur signal-driven flag

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Integration
> **Estimate**: 1h
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-001` (FOV sur camera3d ownership — couvert ADR-0002)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm) + ADR-0002 Amendment A-1 + ADR-0005 (Movement Signals Architecture)
**ADR Decision Summary**: ADR-0002 acte FOV sur `camera3d.fov` (lerp `BASE_FOV ± DASH_FOV_KICK`). ADR-0005 D-2 fige les signaux `dash_started(Vector3, float)` + `dash_ended()`. ADR-0002 Amendment A-1 + Manifest 2026-04-23 ligne 161 **interdisent le polling** `player.is_dashing` depuis `src/gameplay/camera/` — Camera consomme les transitions Movement **via signaux exclusivement**. Pattern : connecter `dash_started/dash_ended` au `_ready()` (mode SYNC), handlers mettent à jour un flag privé `_is_dashing`, `_process` lit ce flag pour piloter la lerp FOV.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: `Camera3D.fov` : assignation frame-per-frame OK sur macOS Metal (validé prototype, GDD Edge Case #14). D3D12 Windows 4.6 : prototype encore à vérifier — flag MEDIUM. Pas de post-cutoff API. Valeur FOV en degrés (Godot convention).

**Control Manifest Rules (Presentation layer)**:
- Required : FOV sur `camera3d.fov` (via lerp BASE_FOV ± DASH_FOV_KICK) ; camera logic en `_process` cosmétique only ; connexions `dash_started`/`dash_ended` mode SYNC (flags=0, pas `CONNECT_DEFERRED`) — Manifest 2026-04-23 ligne 149/162
- Forbidden : poller `player.is_dashing`, `player.state ==`, `match player.state` depuis `src/gameplay/camera/` (pattern `camera_polls_movement_state_transitions`) — Manifest 2026-04-23 ligne 161 ; muter `camera3d.fov` depuis `_physics_process` ; `CONNECT_DEFERRED` sur les connexions Camera ↔ Movement
- Guardrail : Camera `_process` cost ≤ 0.2 ms p99

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [x] **AC-CAM-20** : `GIVEN` `_is_dashing == false`, `WHEN` Movement émet `dash_started(dir, speed)`, `THEN` `_is_dashing := true` et `camera3d.fov` converge vers `BASE_FOV + DASH_FOV_KICK = 100°` ; à `t=150 ms`, `fov ≥ 98.5°`.
- [x] **AC-CAM-21** : `GIVEN` `_is_dashing == true`, `WHEN` Movement émet `dash_ended()`, `THEN` `_is_dashing := false` et `camera3d.fov` converge vers `BASE_FOV = 90°` ; `|fov - 90| < 0.5°` dans ≤ 250 ms.
- [x] **AC-CAM-20b** : Aucun grep `player.is_dashing` dans `src/gameplay/camera/camera_system.gd` — lint statique CI Manifest ligne 161 reste clean.

---

## Implementation Notes

*Derived from ADR-0002 Key Interfaces + Amendment A-1 + GDD Rule 6 + Formula 3 + Manifest 2026-04-23 ligne 149 (signal-driven consumption) + ligne 161 (no polling) :*

Ajouter à `src/gameplay/camera/camera_system.gd` :

```gdscript
const BASE_FOV: float = 90.0                  # degrés — prototype validé
const DASH_FOV_KICK: float = 10.0             # degrés
const DASH_FOV_LERP_SPEED: float = 14.0       # unit/s — snap-in ease-out, attrape ~150 ms, relâche ~100 ms

# Cached flag mis à jour par les handlers signaux. Source de vérité Camera-side.
# Manifest 2026-04-23 ligne 161 : interdit de lire player.is_dashing en _process.
var _is_dashing: bool = false

func _ready() -> void:
    # ... existing setup ...
    _camera3d.fov = BASE_FOV  # initialisation explicite

    # Connexions canoniques Camera ↔ Movement — Manifest ligne 149 (les 6 handlers).
    # Mode SYNC (flags=0) — VC-8 ADR-0002 Amendment A-1 (cohérence visuelle frame-précise).
    # Story 011 ajoutera les disconnects symétriques en _exit_tree.
    _player.dash_started.connect(_on_dash_started)
    _player.dash_ended.connect(_on_dash_ended)

func _process(delta: float) -> void:
    _update_tilt_wall_run(delta)   # Story 005
    _update_fov_dash(delta)         # this story
    # (autres _process effets ajoutés par Story 007 etc.)

# Handlers signaux — mutent UNIQUEMENT des flags privés Camera (ADR-0005 D-7
# consumer ne mute pas Movement). Idempotents (ADR-0005 D-8). Légers → SYNC OK.
func _on_dash_started(_dash_dir: Vector3, _dash_speed: float) -> void:
    _is_dashing = true

func _on_dash_ended() -> void:
    _is_dashing = false

func _update_fov_dash(delta: float) -> void:
    # Note : pas de multiplication reduce_motion ici — ajoutée par Story 010.
    var target_fov: float = BASE_FOV + (DASH_FOV_KICK if _is_dashing else 0.0)
    _camera3d.fov = lerp(
        _camera3d.fov,
        target_fov,
        min(DASH_FOV_LERP_SPEED * delta, 1.0)
    )
```

- **Pattern signal-driven** mandaté par Manifest 2026-04-23 ligne 161 (forbidden pattern `camera_polls_movement_state_transitions`). Camera consomme `dash_started` / `dash_ended` exclusivement, jamais `player.is_dashing` ni `player.state`.
- **Flag privé `_is_dashing`** : maintenu par les handlers, lu en `_process`. Cohérent avec le pattern flag (`_is_wall_running`, `_wall_side_cached`) prescrit Manifest ligne 149.
- **Mode connection** : SYNC (flags=0, pas `CONNECT_DEFERRED`) — VC-8 ADR-0002 Amendment A-1, AC-CAM-20b lint compatible.
- **Reduce_motion multiplier** : **PAS DANS CETTE STORY** — ajouté par Story 010 (`DASH_FOV_KICK * 0.5 if reduce_motion` → peak 95° au lieu de 100°).
- **Double dash** (Edge Case GDD) : dash #2 avant retour complet à `BASE_FOV` → `dash_started` re-fire, `_is_dashing` reste `true`, `target_fov=100`, lerp reprend depuis valeur courante. **Kick absolute-target, pas additif.** Comportement voulu, pas de logique spéciale.
- **Respawn reset** : **PAS DANS CETTE STORY** — Story 008 ajoutera `_camera3d.fov = BASE_FOV` + `_is_dashing = false` dans handler `respawned(position)`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 010 : multiplier `fov_kick_mult = 0.5 if reduce_motion else 1.0` sur `DASH_FOV_KICK`.
- Story 008 : reset `_camera3d.fov = BASE_FOV` dans `respawned(position)`.
- Story 012 : mesure perf `_process` incluant `_update_fov_dash`.
- Future Settings menu : FOV slider utilisateur (GDD Open Question, MVP « recommandé mais à acter Menu GDD »).

---

## QA Test Cases

**AC-CAM-20 (dash start → FOV up)** — Integration

- Given : Camera connectée à `player.dash_started`, `_is_dashing == false`, `_camera3d.fov = 90.0`
- When : frame 0 : `player.dash_started.emit(Vector3.FORWARD, 18.0)` (handler set `_is_dashing=true`) ; 9 frames `_process(1.0/60.0)` (t=150ms)
- Then : `_camera3d.fov >= 98.5`
- Edge cases : dash déclenché en plein wall-run (tilt actif) → les deux effets coexistent sur noeuds différents (`_camera_effects.rotation.z` et `_camera3d.fov`), pas de conflit ; dash déclenché en Respawning → Story 008 gère le gate, pas ce test

**AC-CAM-21 (dash end → FOV down)** — Integration

- Given : `_is_dashing == true`, `_camera3d.fov = 100.0`
- When : frame 0 : `player.dash_ended.emit()` (handler set `_is_dashing=false`) ; 15 frames `_process(1.0/60.0)` (t=250ms)
- Then : `abs(_camera3d.fov - 90.0) < 0.5`
- Edge cases : double dash avant retour complet → `dash_started` re-fire, `_is_dashing` reste true, target repasse à 100, lerp reprend sans « saut » ; `delta` variable 30-144 fps → variance ±20% documentée acceptable

**AC-CAM-20b (lint no-polling)** — Static

- Given : `src/gameplay/camera/camera_system.gd` après implémentation story-006
- When : CI grep `grep -rE 'player\.is_dashing|player\.state\s*[!=]=|match\s+player\.state' src/gameplay/camera/ | grep -v '^[^:]*:\s*#'`
- Then : zéro match (hors commentaires) — Manifest 2026-04-23 ligne 161 forbidden pattern `camera_polls_movement_state_transitions`

---

## Test Evidence

**Story Type** : Integration
**Required evidence** : `tests/integration/camera/story-006-fov-dash-pulse_test.gd` — AC-CAM-20/21 via émission `player.dash_started.emit(...)` / `player.dash_ended.emit()` + loop `_process(1/60)` N frames + assertion `_camera3d.fov`. AC-CAM-20b couvert via `tests/static/camera_no_polling_test.gd` (grep regex sur `src/gameplay/camera/`).

**Status** : [x] Tests créés et alignés sur les ACs (5 tests, 4 ACs couvertes dont 1 edge case double-dash bonus)

- `tests/integration/camera/story_006_fov_dash_pulse_test.gd` — AC-CAM-20 (dash up), AC-CAM-20 initial state, AC-CAM-21 (dash down), edge case double-dash
- `tests/static/camera_no_polling_test.gd` — AC-CAM-20b (lint VC-7)
- `tests/helpers/mock_player_with_dash_signals.gd` — mock CharacterBody3D exposant `dash_started` / `dash_ended`

---

## Dependencies

- Depends on : Story 001 (scene tree Camera3D), Story 002 (_process existe)
- Unlocks : Story 008 (reset fov dans respawned), Story 010 (reduce_motion multiplier), Story 022 visuel AC-CAM-22 screenshot before/peak/after (relève d'une story Visual/Feel séparée post-MVP, hors scope ce epic)

---

## Completion Notes

**Completed** : 2026-04-27
**Criteria** : 3/3 passing (AC-CAM-20, AC-CAM-21, AC-CAM-20b)
**Verdict** : COMPLETE WITH NOTES

**Test Evidence** :

- `tests/integration/camera/story_006_fov_dash_pulse_test.gd` (4 tests : dash up / dash down / état initial / double-dash edge case)
- `tests/static/camera_no_polling_test.gd` (1 test : VC-7 lint regex)
- Lint VC-7 live : CLEAN (zéro match `player.is_dashing` / `player.state ==` / `match player.state` hors commentaires)

**Code Review** : Complete — `/code-review` 2026-04-27 verdict APPROVED WITH SUGGESTIONS (zéro change required).

**Deviations** : aucune bloquante. ADR-0002 + Amendment A-1 + ADR-0005 D-5/D-7/D-8/D-10 respectés à la lettre.

**Notes advisory (non-bloquantes)** :

- Test `test_ac_cam_20_dash_started_fov_converges_up` utilise un cast `bool → float` maladroit (`assert_float(_camera_system._is_dashing as float).is_equal(0.0)`) — préférer `assert_bool(...).is_false()`. Cosmétique, à corriger en passe de polish.
- Pattern lint VC-7 `match\s+player\.state` ne couvre pas `match _player.state` (le `_` n'est pas `\s`). Camera ne contient aucun `match` aujourd'hui — gap théorique. À élargir si une future story Camera utilise `match` sur l'état.
- Reset explicite `_camera_system._is_dashing = false` dans `before_test` est redondant avec l'init `var = false` mais sert de garde anti-pollution test → conserver.

**VC-8 status** : connexions `dash_started` / `dash_ended` ajoutées au `_ready()`. Connexions `wall_run_*` déjà présentes (story 005). Connexions `died` / `respawned` ajoutées par story 008 — VC-8 sera complet à ce moment-là (pattern roadmap intentionnel).

**Architecture livrée** :

- `src/gameplay/camera/camera_system.gd` : +83 / -1 lignes. Constantes `BASE_FOV / DASH_FOV_KICK / DASH_FOV_LERP_SPEED`, flag `_is_dashing`, handlers `_on_dash_started` / `_on_dash_ended`, helper `_update_fov_dash` appelé depuis `_process`, init explicite `_camera3d.fov = BASE_FOV` au `_ready()`.
- Pattern signal-driven flag-based (Amendment A-1) appliqué proprement — coexiste avec le pattern dérivation continue de tilt wall-run (story 005) sur `camera_effects.rotation.z` sans conflit (étages scene tree disjoints).
