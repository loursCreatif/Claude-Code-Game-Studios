# Story 006: GSM Visibility Gating — state_changed CONNECT_DEFERRED Freeze MENU/PAUSED/BOSS_DEFEATED

> **Epic**: VFX System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-04
> **Estimate**: S (2-3 h, listener state_changed CONNECT_DEFERRED + freeze pool + restoration PLAYING)

## Context

**GDD**: `design/gdd/vfx-system.md` (Designed r1)
**Requirements**:
- R-VFX-12 : GSM visibility gating — `state_changed` CONNECT_DEFERRED ; PLAYING+RESPAWNING actif / MENU+PAUSED+BOSS_DEFEATED freeze
- R-VFX-3 : Signal consumer CONNECT_DEFERRED par défaut

**ADR Governing Implementation**:
- **ADR-0007 D-2** (matrice états interdits) — VFX gelé pendant MENU / PAUSED / BOSS_DEFEATED ; VFX actif PLAYING + RESPAWNING (Pillar 3 — counter visible pendant respawn 50 ms).
- **ADR-0007 D-9** (pull pattern) — `GSM.get_current_state() -> State` au `_ready()` (initial pull).
- **ADR-0007 D-10** (signal `state_changed` SYNC côté GSM consommé via CONNECT_DEFERRED côté consumer) — pattern HUD R-HUD-4 + Menu R-MNU-4.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `GPUParticles3D.process_mode = PROCESS_MODE_DISABLED` stable Godot 4.0+. `process_mode = PROCESS_MODE_INHERIT` restoration au retour PLAYING.

**Control Manifest Rules (Presentation layer)**:
- Required : listener `_on_state_changed` CONNECT_DEFERRED (consumer lourd visibility logic) ; transition vers MENU/PAUSED/BOSS_DEFEATED → `GPUParticles3D.emitting = false` + `process_mode = PROCESS_MODE_DISABLED` + flash overlay masqué + trail désactivé ; retour PLAYING → restoration `process_mode = PROCESS_MODE_INHERIT`.
- Forbidden : mutation `Engine.time_scale` (autorité GSM seul) ; mutation `get_tree().paused` (ownership GSM via `request_pause`/`request_resume`) ; flash overlay rouge concurrent (R-VFX-6 Camera owns mort).
- Guardrail : pull `GSM.get_current_state()` au `_ready()` initial state ; tous les handlers signaux gated par `if not _is_active: return` early-out (R-VFX-12).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1, scoped à cette story (Logic) :*

- [ ] **AC-VFX-15** [BLOCKING][AUTO] **GIVEN** `state_changed(MENU)` reçu pendant swing_started → swing_ended window, **WHEN** GSM bascule en MENU, **THEN** Trail désactivé immédiatement (`visible = false`) ; `swing_ended` ultérieur ignoré (guard `_is_active == false`).
- [ ] **AC-VFX-16** [BLOCKING][AUTO] **GIVEN** `state_changed(PAUSED)` reçu pendant blood particles actives, **WHEN** GSM bascule en PAUSED, **THEN** `GPUParticles3D.emitting = false` + `process_mode = PROCESS_MODE_DISABLED` sur tous les slots pool actifs ; flash overlay masqué ; trail désactivé.
- [ ] **AC-VFX-17** [BLOCKING][AUTO] **GIVEN** `state_changed(PLAYING)` reçu après PAUSED, **WHEN** GSM retour en PLAYING, **THEN** `GPUParticles3D.process_mode = PROCESS_MODE_INHERIT` restauré ; trail en Idle (pas de trail orphelin) ; flash overlay prêt pour prochain kill.
- [ ] **AC-NEW-08** [BLOCKING][AUTO] **GIVEN** VFXSystem `_ready()` s'exécute avec `GSM.get_current_state() == State.MENU`, **THEN** `_is_active == false` initial ; pool nodes `process_mode = PROCESS_MODE_DISABLED` ; aucun spawn possible jusqu'à `state_changed(PLAYING)` reçu.

---

## Implementation Notes

```gdscript
# story-006 ajoute dans src/core/vfx_system.gd

# State variable (déjà déclarée story-001 stub) :
# var _is_active: bool = true

# Constants — État GSM (à confirmer GSM enum)
const STATE_MENU: int = 0
const STATE_PLAYING: int = 1
const STATE_PAUSED: int = 2
const STATE_RESPAWNING: int = 3
const STATE_BOSS_DEFEATED: int = 4

func _ready() -> void:
    # ... story-001 pool boot ...
    # ... story-005 pull accessibility ...

    # ADR-0007 D-9 — pull initial state
    _pull_initial_gsm_state()

    # ... story-001 connect upstream signals ...
    # GameStateManager.state_changed CONNECT_DEFERRED → _on_state_changed (this story body)

func _pull_initial_gsm_state() -> void:
    if GameStateManager == null:
        push_warning("VFX: GSM not available at _ready() — defaulting _is_active = true (PLAYING assumption)")
        _is_active = true
        return

    var initial_state: int = GameStateManager.get_current_state()
    _apply_visibility_for_state(initial_state)

func _on_state_changed(new_state: int) -> void:
    _apply_visibility_for_state(new_state)

func _apply_visibility_for_state(state: int) -> void:
    var was_active: bool = _is_active
    _is_active = (state == STATE_PLAYING or state == STATE_RESPAWNING)

    if not _is_active:
        # AC-VFX-15/16 — freeze pool + trail + flash overlay
        _freeze_vfx()
    elif not was_active and _is_active:
        # AC-VFX-17 — restoration retour PLAYING
        _restore_vfx()

func _freeze_vfx() -> void:
    # GPUParticles3D pool freeze
    for p in _blood_particle_pool:
        p.emitting = false
        p.process_mode = Node.PROCESS_MODE_DISABLED

    # Trail désactivé
    _trail_mesh.visible = false
    _trail_active = false

    # Flash overlay masqué (kill + respawn)
    _flash_overlay_rect.visible = false
    _flash_kill_active = false
    _flash_respawn_active = false

    # Note : _decal_pool slots restent visibles (decals = mémoire physique salle Pillar 2)
    # PAUSED ne doit PAS effacer les decals — seul respawn ou MENU transition reset (story-003)

func _restore_vfx() -> void:
    # AC-VFX-17 — process_mode restauré, trail Idle (pas orphelin)
    for p in _blood_particle_pool:
        p.process_mode = Node.PROCESS_MODE_INHERIT
        # emitting reste false (sera re-trigger par prochain enemy_killed)

    # Trail Idle — pas de trail orphelin (visible reste false jusqu'à swing_started)
    _trail_mesh.visible = false
    _trail_active = false

    # Flash overlay prêt — visible reste false jusqu'à prochain trigger
    _flash_overlay_rect.visible = false
```

**Refactor handlers cross-stories pour respecter `_is_active`** :

```gdscript
# story-002 _on_enemy_killed — guard early-out
func _on_enemy_killed(enemy: Node, position: Vector3) -> void:
    if not _is_active:
        return  # AC-VFX-16 — gated par GSM
    _spawn_blood_spurt(position)
    _spawn_decal_on_surface(position)
    _trigger_flash_kill()

# story-002 _on_swing_started — guard early-out
func _on_swing_started(direction: Vector3) -> void:
    if not _is_active:
        return  # AC-VFX-15 — trail not spawned si MENU
    _swing_aim_forward = direction.normalized()
    _trail_active = true
    _trail_mesh.visible = true
    # ...

# story-002 _on_swing_ended — guard early-out
func _on_swing_ended() -> void:
    if not _is_active or not _trail_active:
        return  # AC-VFX-15 — swing_ended post-MENU ignoré

# story-004 _trigger_flash_kill — guard already by _flash_last_msec WCAG
# (mais ajouter explicit early-out pour MENU)
func _trigger_flash_kill() -> void:
    if not _is_active:
        return
    # ... WCAG guard + flash trigger
```

**Pattern cohérent HUD R-HUD-4 + Menu R-MNU-4** :
- HUD : `state_changed.connect(_on_state_changed, CONNECT_DEFERRED)` + visibility table PLAYING/RESPAWNING true / MENU/PAUSED/BOSS_DEFEATED false.
- Menu : `state_changed.connect(_on_state_changed, CONNECT_DEFERRED)` + matrice transitions interdites.
- VFX : `state_changed.connect(_on_state_changed, CONNECT_DEFERRED)` + freeze/restore pool + trail + flash overlay.

**EC-VFX-05 — GSM transition vers MENU pendant trail katana actif** :
- Joueur ouvre menu (`state_changed(MENU)`) pendant `swing_started` → `swing_ended` window.
- Garde R-VFX-12 : `_trail_active = false` immédiatement, `MeshInstance3D.visible = false`.
- Si `swing_ended` arrive après la transition menu (signal CONNECT_DEFERRED), il est ignoré (guard `_is_active == false`).
- Pas de trail orphelin à la réouverture du jeu (AC-VFX-15).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Decal pool reset au respawn (`_room_decal_count = 0`, all `visible = false`) — story-003 (`_on_respawned` body).
- Flash respawn trigger (50 ms blanc pur ou skip si reduce_flash) — story-004.
- Pull `_reduce_flash` / `_reduce_motion` boot + live — story-005.
- Lints statiques anti-patterns (zero `Engine.time_scale`, zero `get_tree().paused` mutation) — story-007.
- Visual/Feel playtest — story-008.
- Persistence GSM autoload boot order — délégué GSM autoload Sprint A multi-epic (mocks `MockGSM` test fixture pour Sprint VFX MVP).

---

## QA Test Cases

*Logic — automated unit tests requis :*

**AC-VFX-15** : MENU pendant swing → trail désactivé + swing_ended ignoré
- Setup : VFXSystem ready, `_is_active = true`, émettre `swing_started(Vector3.FORWARD)`.
- Verify : `_trail_active == true`, `_trail_mesh.visible == true`.
- Action : émettre `state_changed(STATE_MENU)` puis await DEFERRED tick.
- Verify : `_is_active == false`, `_trail_active == false`, `_trail_mesh.visible == false`.
- Action : émettre `swing_ended()` (post-MENU).
- Verify : aucun side-effect (`_trail_active` reste `false`, pas de fade-out déclenché).
- Pass : 5 asserts cross-tick.

**AC-VFX-16** : PAUSED freeze pool + flash overlay masqué
- Setup : `_is_active = true`, 3 slots `GPUParticles3D` actifs (`emitting = true`), flash kill actif (`_flash_kill_active = true`).
- Action : émettre `state_changed(STATE_PAUSED)` puis await DEFERRED tick.
- Verify : tous slots `emitting == false`, `process_mode == PROCESS_MODE_DISABLED` ; `_flash_overlay_rect.visible == false` ; `_flash_kill_active == false` ; `_trail_mesh.visible == false`.
- Pass : 5 asserts.

**AC-VFX-17** : PAUSED → PLAYING restoration
- Setup : VFXSystem en PAUSED state (post AC-VFX-16).
- Action : émettre `state_changed(STATE_PLAYING)` puis await DEFERRED tick.
- Verify : `_is_active == true` ; tous slots `process_mode == PROCESS_MODE_INHERIT` (restoré) ; `_trail_mesh.visible == false` (Idle, pas trail orphelin) ; `_flash_overlay_rect.visible == false` (prêt prochain trigger).
- Pass : 4 asserts.

**AC-NEW-08** : Boot MENU initial state
- Setup : mock `GSM.get_current_state() -> STATE_MENU`.
- Action : `VFXSystem._ready()` exécuté (incluant `_pull_initial_gsm_state()`).
- Verify : `_is_active == false`, tous slots `process_mode == PROCESS_MODE_DISABLED`, aucun spawn possible.
- Action : émettre `enemy_killed(mock, Vector3.ZERO)` (gated).
- Verify : aucun blood spurt, aucun decal, aucun flash.
- Pass : 4 asserts.

**EC-VFX-05** : GSM MENU pendant trail actif (full sequence)
- Setup : `_is_active = true`, `swing_started(Vector3.FORWARD)`.
- Action : `state_changed(MENU)` DEFERRED.
- Verify : trail désactivé.
- Action : `swing_ended` (post-MENU ignoré).
- Verify : aucun side-effect.
- Action : `state_changed(PLAYING)` (retour).
- Verify : trail Idle (`visible == false`), pas orphelin.
- Pass : 5 asserts cross-state.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/vfx/vfx_gsm_visibility_test.gd` (NEW, ~200 lignes) couvrant AC-VFX-15/16/17 + AC-NEW-08 + EC-VFX-05.
- Mock `MockGSM` avec `get_current_state()` settable + signal `state_changed`.
- Smoke check : test suite green run via GdUnit4 headless.

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** : story-001 (autoload skeleton + connect `state_changed`) + story-002 (handlers Combat refactorés avec guard `_is_active`) + story-004 (handlers flash refactorés avec guard).
- **Cross-system** :
  - **GameStateManager autoload Not Started** : ADR-0007 Accepted, GSM GDD APPROVED r1, mais GSM autoload pas implémenté. **Mitigation Sprint VFX** : utiliser mocks `MockGSM` test fixture pattern (référence Combat MockAudioHandler 171 lignes). Production VFX attend GSM autoload boot Sprint A multi-epic.
- **Unlocks** : aucune downstream — close-out R-VFX-12 + ADR-0007 D-2/D-9/D-10 pattern visibility consumer pour VFX. **Débloque AC-VFX-15 deferred story-004** (GSM gating criterion strict).

---

## Completion Notes

**Completed** : 2026-05-09 (chain auto post story-005 done)
**Verdict** : COMPLETE
**Criteria** : 4/4 BLOCKING + 1 EC + 2 NEW edge cases — AC-VFX-15/16/17 + AC-NEW-08 + EC-VFX-05 + BOSS_DEFEATED freeze + RESPAWNING actif
**Re-confirm tests** : 41/41 PASS cumulé exit 0 / 3.07 s (`reports/report_461/results.xml`) — story-001 7 + story-002 10 + story-003 5 + story-004 8 + story-005 4 + story-006 7
**Deviations** : None — toutes corrigées pendant `/code-review` :
  - Cross-stories early-out guards 7/7 handlers `if not _is_active: return`
  - `_on_respawned` no-guard intentional confirmed (reset cleanup pas spawn)
  - AC-VFX-16 manque assert `_flash_respawn_active == false` → ajouté
  - 2 NEW edge cases (BOSS_DEFEATED + RESPAWNING) ajoutés pour protection régression enum GSM
  - Cross-stories tests fix 4 fichiers legacy `_make_vfx()` inject `mock_gsm`
  - Manifest 2026-05-04 newer non-flagable
**Test Evidence** : `tests/unit/vfx/vfx_gsm_visibility_test.gd` (7 tests post-fixes incl. NEW BOSS_DEFEATED + RESPAWNING)
**Code Review** : Complete — godot-gdscript-specialist APPROVED WITH SUGGESTIONS (6 ADRs/Rules tous PASS : ADR-0007 D-2/D-9/D-10 + R-VFX-2/12/14, cross-stories guards 7/7) + qa-tester TESTABLE (4 ACs + EC COVERED + 2 NEW edge cases ajoutés)

**AC-VFX-15 GSM gating criterion strict RÉSOLU** — débloque AC-VFX-15 deferred story-004 (story-004 Completion Notes peut être amendé "AC-VFX-15 covered story-006").

**Pattern HUD R-HUD-4 + Menu R-MNU-4 visibility consumer cross-system standardisé** : VFX rejoint HUD + Menu dans le pattern `state_changed` CONNECT_DEFERRED + freeze/restore.

**Cross-stories tests fix critique** (4 fichiers legacy MODIF) : `vfx_combat_handlers_test.gd` + `vfx_decal_lru_test.gd` + `vfx_flash_events_test.gd` + `vfx_accessibility_pull_test.gd` — `_make_vfx()` helpers updates pour inject `mock_gsm` (overrider autoload réel `/root/GameStateManager` qui retourne STATE_MENU=0 default headless → `_is_active=false` → handlers gated). Fix purement infrastructure test (zéro changement prod).

**Files livrés (6)** :
- `src/core/vfx_system.gd` (MODIF, +90 L) — STATE_* constants + `_gsm_ref` + body `_on_state_changed` + 4 helpers (`_apply_visibility_for_state`/`_freeze_vfx`/`_restore_vfx`/`_pull_initial_gsm_state`) + `_ready` boot pull + cross-stories early-out guards 7/7 handlers
- `tests/unit/vfx/vfx_gsm_visibility_test.gd` (NEW, ~470 L post-fixes) — 7 tests
- `tests/integration/vfx/vfx_combat_handlers_test.gd` (MODIF) — inject mock_gsm
- `tests/unit/vfx/vfx_decal_lru_test.gd` (MODIF) — inject mock_gsm
- `tests/integration/vfx/vfx_flash_events_test.gd` (MODIF) — inject mock_gsm
- `tests/integration/vfx/vfx_accessibility_pull_test.gd` (MODIF) — inject mock_gsm + standalone force `_is_active = true`

**Out of Scope strict respecté** : zéro decal pool reset (story-003), zéro flash respawn body (story-004), zéro accessibility (story-005), zéro lints (story-007), zéro playtest (story-008).

**Tech debt** : aucun loggé (3 documentation suggestions cosmétiques absorbées + 3 ROI fixes appliqués inline + 1 mystère `_on_respawned` no-guard clarifié intentional).
