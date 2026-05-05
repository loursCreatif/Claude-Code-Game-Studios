# Story 003: Visibility State Changed Gating — CONNECT_DEFERRED + State Machine

> **Epic**: HUD System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-04
> **Estimate**: S (2-3 h, listener body + visibility table + tween kill PAUSED)

## Context

**GDD**: `design/gdd/hud-system.md` (In Design r1.1)
**Requirement**: R-HUD-4 (CONNECT_DEFERRED state_changed), R-HUD-8 (visibility par State machine binaire), R-HUD-9 (RESPAWNING reste visible Pillar 3), R-HUD-10 (PAUSED masqué Menu owns full-screen overlay).
*(TR-hud-* IDs non encore présents dans `tr-registry.yaml` — référence directe R-HUD/AC-HUD GDD r1.1.)*

**ADR Governing Implementation**:
- **ADR-0007 D-2** (matrice états GSM) — `State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }` enum 5 valeurs ; transitions interdites ne concernent pas HUD (consumer outbound-only).
- **ADR-0007 D-10** (5 verbes publics figés + signal `state_changed(new_state: State)` SYNC côté GSM consommé via CONNECT_DEFERRED côté HUD — visibility logic implique potentiellement rebuild structurel + tween kill).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `CONNECT_DEFERRED` flag stable Godot 3.x+. Pas d'erratum process_mode pour HUD (autoload Node hérite default `PROCESS_MODE_INHERIT`, pas besoin `ALWAYS = 3` car HUD ne tick rien en `_physics_process` — Frame budget ligne 459 GDD).

**Control Manifest Rules (Presentation layer)**:
- Required : connexion `GameStateManager.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)` flag explicite ; visibility table appliquée via `_apply_visibility(state)` helper réutilisable boot pull + state_changed handler.
- Forbidden : connexion SYNC sur `state_changed` (rebuild structurel mid-physics-frame casse R-HUD-4 contract) ; mutation `Engine.time_scale` ou `get_tree().paused` (autorité GSM seul AC-MNU-49/50 layer convention).
- Guardrail : tween d'incrément en cours quand state passe PLAYING → PAUSED → killed (R-HUD-10) ; PLAYING → RESPAWNING → continue (R-HUD-9 Pillar 3).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1.1, scoped à cette story (Logic) :*

- [ ] **AC-HUD-12** [BLOCKING][AUTO] **GIVEN** HUD initialized, **WHEN** `state_changed(State.MENU)` reçu, **THEN** `Label.visible == false` dans le même tick de traitement du signal (CONNECT_DEFERRED → idle frame N+1).
- [ ] **AC-HUD-13** [BLOCKING][AUTO] **GIVEN** counter hidden (State.MENU), **WHEN** `state_changed(State.PLAYING)` reçu, **THEN** `Label.visible == true` avant le prochain `_physics_process` tick.
- [ ] **AC-HUD-14** [BLOCKING][AUTO] **GIVEN** counter visible (State.PLAYING), **WHEN** `state_changed(State.PAUSED)` reçu, **THEN** `Label.visible == false` ; le pause overlay (Menu System) reste seul élément UI visible de sa couche.
- [ ] **AC-HUD-15** [BLOCKING][AUTO] **GIVEN** State.RESPAWNING actif (durée ≤ `RESPAWN_DELAY_S = 50 ms`), **WHEN** `state_changed(State.RESPAWNING)` reçu, **THEN** `Label.visible == true` ; aucun freeze, aucun hide pendant la fenêtre respawn (Pillar 3 — transition invisible).
- [ ] **AC-HUD-16** [BLOCKING][AUTO] **GIVEN** State.PLAYING, **WHEN** `state_changed(State.BOSS_DEFEATED)` reçu, **THEN** `Label.visible == false`.

---

## Implementation Notes

1. **Listener `_on_state_changed` body** dans `src/gameplay/hud/hud_system.gd` :
   ```gdscript
   # Visibility table — État qui rend le HUD visible (PLAYING + RESPAWNING uniquement)
   const _VISIBLE_STATES: Array[int] = [1, 3]  # State.PLAYING == 1, State.RESPAWNING == 3
   # Note: enum values à confirmer via GSM enum registry au moment d'impl

   func _on_state_changed(new_state: int) -> void:
       _apply_visibility(new_state)

   func _apply_visibility(state: int) -> void:
       var should_be_visible: bool = state in _VISIBLE_STATES
       _canvas_layer.visible = should_be_visible

       # R-HUD-10 — tween en cours killed à PAUSED (EC-HUD-06 propreté)
       # State.PAUSED == 2
       if state == 2 and _active_pulse_tween != null and _active_pulse_tween.is_valid():
           _active_pulse_tween.kill()
           _active_pulse_tween = null
           _credit_counter_label.scale = Vector2.ONE
   ```

2. **Référence enum State** : copier valeurs depuis `design/gdd/game-state-manager.md` enum State au moment d'impl. Hypothèse MVP : `MENU=0, PLAYING=1, PAUSED=2, RESPAWNING=3, BOSS_DEFEATED=4`. Confirmation via ADR-0007 ou GSM registry au moment d'impl.

3. **CONNECT_DEFERRED flag déjà en place** (story-001) — vérifier dans test que `Signal.get_connections()[0].flags & CONNECT_DEFERRED != 0` (analogue AC-MNU-33/34 menu state sync test).

4. **EC-HUD-04 (state_changed + credits_changed même tick)** : ordre déterministe garanti par contracts SYNC vs DEFERRED — `credits_changed` SYNC s'exécute en premier (handler met à jour Label, lance pulse) ; `state_changed` CONNECT_DEFERRED s'exécute idle frame N+1 (hide ou maintien selon RESPAWNING). Aucun race condition observable. Test intégration story-006 playtest confirme.

5. **EC-HUD-07 (PLAYING → RESPAWNING tween continue)** : Pillar 3 — tween reste actif. RESPAWN_DELAY = 50 ms < CREDIT_COUNTER_TWEEN_KILL_MS = 100 ms ; le tween peut donc finir post-respawn (back en PLAYING). Pas de freeze visuel. Validé par test intégration multi-state.

6. **Verbose log** : `print("[HUD] state_changed new_state=%d visible=%s" % [new_state, _canvas_layer.visible])` (debug-only).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Listener `_on_credits_changed` SYNC body — story-002.
- Pulse différencié source KILL=100ms / SECRET=150ms — story-004.
- Lints statiques (R-HUD-12 outbound-only, AC-HUD-31..35) — story-005.
- Layer ordering verification AC-HUD-25/26 — story-005.

---

## QA Test Cases

*Logic — automated GdUnit4 tests requis :*

**AC-HUD-12** : MENU → hidden
- Setup : `_ready()` terminé. Mock GSM émet `state_changed.emit(State.MENU)`.
- Action : `await idle_frame` (CONNECT_DEFERRED).
- Verify : `_canvas_layer.visible == false`.

**AC-HUD-13** : MENU → PLAYING → visible
- Setup : Counter hidden (post-MENU).
- Action : `state_changed.emit(State.PLAYING)`. `await idle_frame`.
- Verify : `_canvas_layer.visible == true` ; vérifié AVANT prochain `_physics_process` tick.

**AC-HUD-14** : PLAYING → PAUSED → hidden + tween killed
- Setup : Counter visible (PLAYING). Démarrer un tween d'incrément (mock `credits_changed.emit(11, 1, KILL)`).
- Action : `state_changed.emit(State.PAUSED)`. `await idle_frame`.
- Verify : `_canvas_layer.visible == false` ; `_active_pulse_tween == null` ou invalid (`is_valid() == false`) ; `Label.scale == Vector2.ONE`.

**AC-HUD-15** : RESPAWNING reste visible Pillar 3
- Setup : Counter visible (PLAYING) avec tween d'incrément actif (`credits_changed.emit(11, 1, KILL)`).
- Action : `state_changed.emit(State.RESPAWNING)`. `await idle_frame`.
- Verify : `_canvas_layer.visible == true` (pas d'hide) ; tween reste actif (`_active_pulse_tween.is_valid() == true`) ; après 50ms wall-clock, tween peut continuer (Pillar 3 — pas de freeze).

**AC-HUD-16** : BOSS_DEFEATED → hidden
- Setup : Counter visible (PLAYING).
- Action : `state_changed.emit(State.BOSS_DEFEATED)`. `await idle_frame`.
- Verify : `_canvas_layer.visible == false`.

**EC-HUD-04 cross-validation** : state_changed + credits_changed même tick
- Setup : State.PLAYING. Counter `N=10`.
- Action : dans même tick, émettre `credits_changed.emit(11, 1, KILL)` (SYNC) puis `state_changed.emit(State.RESPAWNING)` (DEFERRED).
- Verify : `Label.text == "11"` immédiat (SYNC) ; `_canvas_layer.visible == true` après idle frame (RESPAWNING reste visible) ; tween actif `_active_pulse_tween.is_valid() == true`.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/hud/hud_visibility_state_test.gd` (NEW, ~150 lignes) couvrant AC-HUD-12/13/14/15/16 + EC-HUD-04 cross-validation.
- Smoke check : test suite green run via GdUnit4 headless.

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** : story-001 Complete (autoload skeleton + connexion `_on_state_changed` stub + `_canvas_layer` instancié + connect `CONNECT_DEFERRED` flag).
- **Soft upstream** : GSM autoload Not Started — utiliser `MockGSM` test fixture pour Sprint HUD. Production HUD attend GSM autoload boot Sprint A.
- **Unlocks** : story-005 (lints peuvent vérifier visibility table cohérente avec layer convention).
