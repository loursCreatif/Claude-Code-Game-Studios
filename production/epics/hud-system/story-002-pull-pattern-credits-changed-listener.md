# Story 002: Pull Pattern Credits Changed Listener — SYNC Same-Frame Update

> **Epic**: HUD System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Integration
> **Manifest Version**: 2026-05-04
> **Estimate**: M (4-6 h, listener body + multi-kill collision tween.kill() + handlers SOURCE branch)

## Context

**GDD**: `design/gdd/hud-system.md` (In Design r1.1)
**Requirement**: R-HUD-3 (connexion SYNC same-frame Pillar 1), R-HUD-5 (pulse increment KILL/SECRET — corps dans story-004), R-HUD-6 (delta < 0 hard set sans tween), R-HUD-7 (delta == 0 hard set garde-fou faux pulse boot).
*(TR-hud-* IDs non encore présents dans `tr-registry.yaml` — référence directe R-HUD/AC-HUD GDD r1.1.)*

**ADR Governing Implementation**:
- **ADR-0001** (Physics rate 60 Hz) — handler SYNC s'exécute dans le `_physics_process` tick de Credit Economy. Pillar 1 FLOW garde-fou — `Label.text = str(total)` dans le **même tick** que `enemy_killed → credits_changed`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Tween.kill()` + `create_tween()` + `set_ignore_time_scale(true)` stables Godot 4.0+. Pas d'API post-cutoff utilisée.

**Control Manifest Rules (Presentation layer)**:
- Required : connexion `CreditEconomy.credits_changed.connect(_on_credits_changed)` SANS flag (SYNC) — pas `CONNECT_DEFERRED` ; handler ≤ 0.5 ms wall-clock (AC-HUD-27) ; zero alloc hot path tolérée (1 alloc String boxing `str(total)`).
- Forbidden : `CONNECT_DEFERRED` sur `credits_changed` (casse Pillar 1 same-frame update) ; appel `get_node("/root/CombatSystem")` ou consumer downstream R-HUD-12 ; SFX `AudioServer.*` (R-HUD-15 zero SFX MVP) ; Input `InputManager.*` (R-HUD-14).
- Guardrail : multi-kill collision tween `tween.kill()` puis `create_tween()` — pas de pool de tweens pré-instanciés (Godot Tween léger, alloc acceptable cold path).

**Cross-reference unblock** : Cette story débloque `production/epics/credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` AC-CRD-46 BLOCKING dépendance externe HUD listener `_on_credits_changed`. Convergence finale via story-006 (playtest evidence frame-by-frame).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1.1, scoped à cette story (Integration) :*

- [ ] **AC-HUD-05** [BLOCKING][AUTO] **GIVEN** State.PLAYING actif et counter affiche `N`, **WHEN** `credits_changed(N+1, +1, SourceKind.KILL)` émis SYNC, **THEN** tween de pulse démarre dans le **même tick `_physics_process`** ; valeur finale `Label.text == str(N+1)` dans `≤ CREDIT_COUNTER_TWEEN_KILL_MS = 100 ms` wall-clock. *(Tween durée différenciée enforcée story-004 ; ici on vérifie le hard set + démarrage tween.)*
- [ ] **AC-HUD-06** [BLOCKING][AUTO] **GIVEN** State.PLAYING et counter `N`, **WHEN** `credits_changed(N+5, +5, SourceKind.SECRET)` émis, **THEN** `Label.text == str(N+5)` instantanément (Rule 5 — hard set du chiffre, pulse parallèle) ; aucune frame intermédiaire avec `Label.text == str(N+1)..str(N+4)`.
- [ ] **AC-HUD-07** [BLOCKING][AUTO] **GIVEN** counter `N` et tween d'incrément en cours (delta > 0), **WHEN** second `credits_changed(N+2, +1, KILL)` arrive pendant le tween actif, **THEN** tween précédent tué (`tween.kill()`) + nouveau démarre à scale courante ; valeur finale `Label.text == str(N+2)` après `≤ 2 × CREDIT_COUNTER_TWEEN_KILL_MS = 200 ms` sans rester bloquée sur valeur intermédiaire.
- [ ] **AC-HUD-08** [BLOCKING][AUTO] **GIVEN** counter `N` et `try_spend(cost)` réussit (`N >= cost`), **WHEN** `credits_changed(N-cost, -cost, SourceKind.SPEND_SHOP)` émis SYNC, **THEN** `Label.text` hard-set à `str(N-cost)` immédiatement (pas de tween descendant) ; aucune animation roll-up ; `Label.scale == Vector2.ONE`.
- [ ] **AC-HUD-09** [BLOCKING][AUTO] **GIVEN** counter `N`, **WHEN** `credits_changed(_, delta, SPEND_SHOP)` reçu avec `delta < 0`, **THEN** `Label.text` mis à jour dans le **même `_physics_process` tick** (frame-synchronous, pas DEFERRED).
- [ ] **AC-HUD-10** [BLOCKING][AUTO] **GIVEN** counter `N` et `try_spend(cost)` échoue (`N < cost`), **WHEN** aucun signal `credits_changed` émis (Credit Rule 4 atomicité), **THEN** counter reste `str(N)` ; aucun tween déclenché ; aucune mutation `Label.text` observée dans 200 ms suivant l'appel.
- [ ] **AC-HUD-11** [BLOCKING][AUTO] **GIVEN** HUD connecté à `credits_changed` via spy, **WHEN** spy capture les connexions, **THEN** spy ne reçoit aucun appel suite à `try_spend` échoué — HUD ne réagit pas à un événement non émis (test intégration : real CreditEconomy + real HUD).
- [ ] **AC-HUD-19** [BLOCKING][AUTO] **GIVEN** State.PLAYING et counter `N`, **WHEN** 3 signals `credits_changed` séquentiels (delta=+1, KILL) arrivent dans le **même tick `_physics_process`** (`MAX_KILLS_PER_SWING = 3`), **THEN** valeur finale après `≤ 3 × CREDIT_COUNTER_TWEEN_KILL_MS = 300 ms` est `str(N+3)` ; valeur intermédiaire jamais > `N+3` ni < `N`.
- [ ] **AC-HUD-20** [BLOCKING][AUTO] **GIVEN** 3 signals `credits_changed` séquentiels même tick, **WHEN** chaque signal reçu, **THEN** HUD ne produit pas 3 tweens superposés causant overshoot — `Label.text` ne dépasse jamais `str(N+3)` à aucune frame.
- [ ] **AC-HUD-21** [BLOCKING][AUTO] **GIVEN** joueur meurt et `Checkpoint._restore_from_snapshot()` s'exécute, **WHEN** `_restore_from_snapshot` ne réémet pas `credits_changed` (Credit Rule 2 irréversibilité mort), **THEN** counter HUD reste à valeur pré-mort `N` ; aucune variation observée dans 200 ms post-State.RESPAWNING.
- [ ] **AC-HUD-22** [BLOCKING][AUTO] **GIVEN** State passe `PLAYING → RESPAWNING → PLAYING`, **WHEN** State.PLAYING restauré, **THEN** counter affiche toujours `str(N)` (valeur pré-mort) — HUD ne re-pull pas `get_total()` au retour PLAYING (pas de double-hydration).
- [ ] **AC-HUD-24** [BLOCKING][AUTO] **GIVEN** `credits_changed(total, 0, SourceKind.BOOT_HYDRATE)` reçu, **WHEN** HUD traite le signal, **THEN** aucun tween lancé (delta == 0 → hard set uniquement) ; `Tween.is_running() == false` après traitement.

---

## Implementation Notes

1. **Listener `_on_credits_changed` body** dans `src/gameplay/hud/hud_system.gd` :
   ```gdscript
   var _active_pulse_tween: Tween = null

   func _on_credits_changed(total: int, delta: int, source: int) -> void:
       # R-HUD-3 SYNC same-frame — hard set du chiffre AVANT tween (toujours)
       _credit_counter_label.text = str(total)

       # R-HUD-7 BOOT_HYDRATE garde-fou — delta==0 jamais de tween
       if delta == 0:
           return

       # R-HUD-6 SPEND_SHOP — delta<0 hard set sans tween, scale reset
       if delta < 0:
           if _active_pulse_tween != null and _active_pulse_tween.is_valid():
               _active_pulse_tween.kill()
               _active_pulse_tween = null
           _credit_counter_label.scale = Vector2.ONE
           return

       # R-HUD-5 increment positive — tween différencié source (corps story-004)
       _start_pulse_tween(source)

   func _start_pulse_tween(_source: int) -> void:
       # Multi-kill collision (AC-HUD-07/19/20) — kill tween précédent
       if _active_pulse_tween != null and _active_pulse_tween.is_valid():
           _active_pulse_tween.kill()

       # Story-004 implémente durée différenciée KILL=100ms / SECRET=150ms
       # Ici stub minimal MVP intégration : durée fixe 100ms, KILL/SECRET indistinct
       _active_pulse_tween = create_tween()
       _active_pulse_tween.set_ignore_time_scale(true)  # OQ-HUD-5 wall-clock recommandé MVP
       _active_pulse_tween.tween_property(_credit_counter_label, "scale", Vector2(1.05, 1.05), 0.05) \
           .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
       _active_pulse_tween.tween_property(_credit_counter_label, "scale", Vector2.ONE, 0.05) \
           .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
   ```

2. **SourceKind enum reference** : `CreditEconomy.SourceKind { KILL = 0, SECRET = 1, SPEND_SHOP = 2, BOOT_HYDRATE = 3 }` (ou enum int — vérifier registry `design/registry/entities.yaml` au moment d'impl).

3. **Idempotence respawn (AC-HUD-21/22)** : aucune logique HUD spécifique requise — le HUD ne re-pull jamais `get_total()` post-`_ready()`. La garantie est portée par Credit Economy Rule 2 (`_restore_from_snapshot` ne réémet pas `credits_changed`). Test intégration : simuler die → respawn → verify `Label.text` inchangé.

4. **Multi-kill collision pattern** : `_active_pulse_tween` réf membre + `tween.kill() + create_tween()` à chaque nouveau signal increment. Pas de pool pré-instancié (Godot Tween léger, cold path acceptable). Pattern référence Combat `MockAudioHandler` ligne ~120 (`_kill_sound_played_this_swing` flag idempotent).

5. **Wall-clock invariance OQ-HUD-5** : `set_ignore_time_scale(true)` recommandé MVP — quand Combat slow-mo `Engine.time_scale = 0.3` au même tick que kill, le pulse HUD doit rester wall-clock 100/150 ms (sinon perçu 333/500 ms, rivalise avec slow-mo visuel).

6. **Test fixture intégration** : utiliser real `CreditEconomy` autoload (Ready Sprint 1) + real `HUDSystem` autoload (story-001 Ready). Test intégration `tests/integration/hud/credit_counter_listener_test.gd`. Pas de mock Credit Economy pour cette story (preuve de bout-en-bout).

7. **Verbose log** : `print("[HUD] credits_changed total=%d delta=%d source=%d" % [total, delta, source])` (debug-only, supprimable).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Pulse durée différenciée KILL=100ms / SECRET=150ms + invariant balance — story-004 (cette story implémente durée stub 100ms).
- Visibility state machine `_on_state_changed` body — story-003.
- Lints statiques anti-patterns + outbound-only enforce — story-005.
- Visual/Feel frame-perfect playtest evidence — story-006.

---

## QA Test Cases

*Integration — automated GdUnit4 tests requis :*

**AC-HUD-05** : KILL increment SYNC same-frame
- Setup : real CreditEconomy + real HUDSystem post-`_ready()`. State.PLAYING. Counter `N=10`.
- Action : `CreditEconomy.credits_changed.emit(11, 1, SourceKind.KILL)` (simulé via méthode test exposée OR call kill scenario).
- Verify : **avant** `await idle_frame` — `Label.text == "11"` (SYNC garantit même tick).
- Pass : `assert_str(hud._credit_counter_label.text).is_equal("11")`.

**AC-HUD-06** : SECRET +5 hard set instant
- Setup : Counter `N=10`.
- Action : `credits_changed.emit(15, 5, SourceKind.SECRET)`.
- Verify : `Label.text == "15"` instant (pas "11" "12" "13" "14" intermédiaire).

**AC-HUD-07** : Multi-kill collision tween.kill()
- Setup : Counter `N=10`. Émettre `credits_changed(11, 1, KILL)`. Capturer ref tween.
- Action : 50ms plus tard (tween en cours), émettre `credits_changed(12, 1, KILL)`.
- Verify : tween 1er `is_valid() == false` (killed) ; nouveau tween créé ; `Label.text == "12"` ; après 200ms total, `Label.text == "12"` final stable.

**AC-HUD-08/09** : SPEND_SHOP hard set sans tween
- Setup : Counter `N=20`.
- Action : `credits_changed.emit(15, -5, SourceKind.SPEND_SHOP)`.
- Verify : `Label.text == "15"` même tick ; `Label.scale == Vector2.ONE` ; `_active_pulse_tween == null` ou invalid.

**AC-HUD-10/11** : try_spend fail no emit
- Setup : real CreditEconomy `total=5`. Connect HUD.
- Action : `CreditEconomy.try_spend(10)` — fail (`5 < 10`).
- Verify : aucun signal `credits_changed` émis (spy `get_signal_emit_count()` = 0) ; `Label.text == "5"` inchangé 200ms.

**AC-HUD-19/20** : 3 emits same tick MAX_KILLS_PER_SWING
- Setup : Counter `N=10`. State.PLAYING.
- Action : dans même `_physics_process` tick, `credits_changed.emit(11, 1, KILL); credits_changed.emit(12, 1, KILL); credits_changed.emit(13, 1, KILL)`.
- Verify : à chaque emit, `Label.text` saute `10 → 11 → 12 → 13` ; après `300ms` total, `Label.text == "13"` ; jamais > 13 ni < 10 capturé via `process_frame` polling.

**AC-HUD-21/22** : Idempotence respawn
- Setup : Counter `N=20` State.PLAYING. Capture `pre_death_text == "20"`.
- Action : simulate die → `state_changed.emit(RESPAWNING)` → 50ms → `state_changed.emit(PLAYING)`. Pas d'émission `credits_changed`.
- Verify : `Label.text == "20"` constant durant 200ms post-PLAYING ; `MockGSM.get_current_state.call_count == 1` (boot pull seul, pas de re-pull).

**AC-HUD-24** : BOOT_HYDRATE no tween
- Setup : `_ready()` terminé.
- Action : `credits_changed.emit(15, 0, SourceKind.BOOT_HYDRATE)`.
- Verify : `Label.text == "15"` ; `_active_pulse_tween == null` ou invalid ; aucun tween dans `get_tree()` actif.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/hud/credit_counter_listener_test.gd` (NEW, ~250 lignes) couvrant AC-HUD-05/06/07/08/09/10/11/19/20/21/22/24 (12 ACs).
- Smoke check : test suite green run via GdUnit4 headless.
- **Cross-reference** : evidence partielle pour `production/epics/credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` AC-CRD-46 (la garantie technique SYNC est validée ici ; la perception frame-perfect est validée story-006 playtest).

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** : story-001 Complete (autoload skeleton + connexion `_on_credits_changed` stub déjà en place + `_credit_counter_label` instancié).
- **Soft upstream** : CreditEconomy stories 001-007 Complete (signal `credits_changed` émis SYNC + enum SourceKind défini + `try_spend` atomicité Rule 4).
- **Unlocks** : `production/epics/credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` AC-CRD-46 (cross-reference convergence story-006). story-004 (pulse différencié source — réutilise `_start_pulse_tween()` helper).
