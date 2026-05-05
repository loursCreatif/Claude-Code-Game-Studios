# Story 001: Autoload Skeleton + CanvasLayer + Pattern Pull Boot

> **Epic**: HUD System
> **Status**: Ready
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-04
> **Estimate**: S (3-4 h, autoload skeleton + project.godot registration + scene tree minimal)

## Context

**GDD**: `design/gdd/hud-system.md` (In Design r1.1)
**Requirement**: R-HUD-1 (autoload data-light + ordre `project.godot`), R-HUD-2 (pattern pull boot `get_current_state()` + `get_total()`), R-HUD-11 (CanvasLayer.layer = 50 < 100), R-HUD-12 (outbound-only zero couplage cross-feature).
*(TR-hud-* IDs non encore présents dans `tr-registry.yaml` — référence directe R-HUD/AC-HUD GDD r1.1.)*

**ADR Governing Implementation**:
- **ADR-0007 D-1** (autoload order) — `InputManager → GameStateManager → CreditEconomy → HUDSystem` ordre `project.godot` figé. Inversion = AC-HUD-04/17/18 fail au boot.
- **ADR-0007 D-9** (pattern pull boot) — `GSM.get_current_state()` synchrone au `_ready()` HUD, jamais d'attente signal `game_booted` (n'existe pas — GSM Rule 12 minimisation API).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: APIs `Node` + `CanvasLayer` + `Label` + `Control.LayoutPreset.PRESET_TOP_RIGHT` stables Godot 4.0+. Aucun breaking change 4.4-4.6 attendu.

**Control Manifest Rules (Presentation layer)**:
- Required : autoload registered AVANT 1ère scene Game ; `CanvasLayer.layer < 100` (GSM owns 100) ; `Label` ancré `PRESET_TOP_RIGHT` natif Godot ; assert ordre autoload defensive (`assert(GameStateManager != null and CreditEconomy != null)`).
- Forbidden : appel `get_node("/root/CombatSystem")` ou tout consumer downstream (R-HUD-12 outbound-only) ; AnimationPlayer / ParallaxBackground / shader / gradient (anti-patterns Chrome Zen K.7/K.8) ; `Engine.time_scale` mutation (autorité GSM seul).
- Guardrail : pas de hot path runtime dans cette story — autoload skeleton boot one-shot uniquement (alloc tolérée `_ready()`).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1.1, scoped à cette story (Logic) :*

- [ ] **AC-HUD-01** [BLOCKING][AUTO] **GIVEN** HUD instancié comme autoload, **WHEN** `_ready()` s'exécute et `GameStateManager.get_current_state() == State.MENU`, **THEN** `Label.visible == false` et aucune erreur loggée.
- [ ] **AC-HUD-02** [BLOCKING][AUTO] **GIVEN** HUD instancié et `CreditEconomy.get_total()` retourne `N >= 0`, **WHEN** `_ready()` s'exécute, **THEN** `Label.text == str(N)` avant tout signal `credits_changed` reçu (boot pull, hard set).
- [ ] **AC-HUD-03** [BLOCKING][AUTO] **GIVEN** HUD possède un `CanvasLayer`, **WHEN** le node est prêt, **THEN** `CanvasLayer.layer < HUD_LAYER_MAX` (`< 100`) — assertion sur la propriété directe (`HUD_CANVAS_LAYER = 50`).
- [ ] **AC-HUD-04** [BLOCKING][AUTO] **GIVEN** HUD instancié, **WHEN** `_ready()` s'exécute, **THEN** HUD connecté au signal `CreditEconomy.credits_changed` ET `GameStateManager.state_changed` (vérifiable via `Signal.get_connections()`), avant tout tick `_physics_process`.
- [ ] **AC-HUD-17** [BLOCKING][AUTO] **GIVEN** processus vient de démarrer (1ère frame), **WHEN** `HUDSystem._ready()` s'exécute, **THEN** `GameStateManager.get_current_state()` appelé exactement 1× (spy/mock vérifiable) ET `CreditEconomy.get_total()` appelé exactement 1× ; HUD n'attend pas de signal `game_booted`.
- [ ] **AC-HUD-18** [BLOCKING][AUTO] **GIVEN** `CreditEconomy` émet `credits_changed(N, 0, SourceKind.BOOT_HYDRATE)` au démarrage (post-`_ready()`), **WHEN** HUD reçoit ce signal, **THEN** counter hard-set à `str(N)` (delta == 0 → pas de tween) ; `Tween.is_running() == false` après traitement. *(Note : story-002 implémente le handler ; cette story s'assure que la connexion est en place.)*

---

## Implementation Notes

1. **Fichier `src/gameplay/hud/hud_system.gd`** (autoload skeleton ~80 lignes) :
   ```gdscript
   class_name HUDSystemScript
   extends Node

   const HUD_CANVAS_LAYER: int = 50
   const HUD_MARGIN_RIGHT_PX: int = 24
   const HUD_MARGIN_TOP_PX: int = 20

   var _canvas_layer: CanvasLayer
   var _credit_counter_label: Label

   func _ready() -> void:
       # R-HUD-1 — assert autoload order broken garde-fou EC-HUD-01
       assert(GameStateManager != null, "HUD: GSM autoload missing — check project.godot order")
       assert(CreditEconomy != null, "HUD: CreditEconomy autoload missing — check project.godot order")

       # CanvasLayer enfant + Label — R-HUD-11 layer=50 < 100
       _canvas_layer = CanvasLayer.new()
       _canvas_layer.layer = HUD_CANVAS_LAYER
       _canvas_layer.name = "HUDCanvasLayer"
       add_child(_canvas_layer)

       var container: Control = Control.new()
       container.name = "CreditCounterContainer"
       container.set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_TOP_RIGHT)
       container.offset_right = -HUD_MARGIN_RIGHT_PX
       container.offset_top = HUD_MARGIN_TOP_PX
       _canvas_layer.add_child(container)

       _credit_counter_label = Label.new()
       _credit_counter_label.name = "CreditCounterLabel"
       container.add_child(_credit_counter_label)

       # R-HUD-2 pattern pull boot — synchrone, jamais signal game_booted
       var initial_state: int = GameStateManager.get_current_state()
       var initial_total: int = CreditEconomy.get_total()
       _credit_counter_label.text = str(initial_total)
       _apply_visibility(initial_state)

       # R-HUD-3 + R-HUD-4 connexions (handlers stub story-002 + story-003)
       CreditEconomy.credits_changed.connect(_on_credits_changed)              # SYNC (Pillar 1)
       GameStateManager.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)  # consumer lourd

   func _apply_visibility(state: int) -> void:
       # Implémenté pleinement dans story-003 — stub minimal MENU=hidden ici
       _canvas_layer.visible = (state != 0)  # State.MENU == 0 hypothèse, à confirmer GSM enum

   # Stubs pour story-002 + story-003 — connectés ici, implémentés downstream
   func _on_credits_changed(_total: int, _delta: int, _source: int) -> void:
       pass  # story-002 implémente

   func _on_state_changed(_new_state: int) -> void:
       pass  # story-003 implémente
   ```

2. **`project.godot` registration** : ajouter `HUDSystem="*res://src/gameplay/hud/hud_system.gd"` dans `[autoload]` APRÈS `InputManager`, `GameStateManager`, `CreditEconomy`. Position `>= 4` (R-HUD-1 + Tuning Knob `HUD_AUTOLOAD_ORDER_INDEX`).

3. **Scene tree garanti** post-`_ready()` :
   ```
   HUDSystem (autoload, Node)
   └── HUDCanvasLayer (CanvasLayer, layer = 50)
       └── CreditCounterContainer (Control, anchor TOP_RIGHT, offsets -24/20)
           └── CreditCounterLabel (Label, text = str(initial_total))
   ```
   *(`CreditIcon` Label opacity 0.6 ajouté Tier 2+ ou story dédiée Visual Chrome Zen — non-bloquant Logic story.)*

4. **Test fixture** : autoload mocks `MockGSM` + `MockCreditEconomy` dans `tests/unit/hud/` exposant `get_current_state() / get_total()` + signaux `state_changed / credits_changed`. Autoload register-order assert bypass via dependency injection setter `_inject_dependencies(gsm, credit)` pour test isolation (pattern Combat MockAudioHandler référence canonique).

5. **Verbose log** : `print("[HUDSystem] boot — state=%d total=%d layer=%d" % [initial_state, initial_total, HUD_CANVAS_LAYER])` au `_ready()` (debug-only, supprimable post-validation).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Listener `_on_credits_changed` SYNC body (hard set + tween différencié source) — story-002.
- Listener `_on_state_changed` body (visibility table PLAYING/RESPAWNING true / MENU/PAUSED/BOSS_DEFEATED false + tween kill PAUSED) — story-003.
- Pulse de scale différencié source KILL=100ms / SECRET=150ms + invariant balance — story-004.
- Lints statiques anti-patterns + outbound-only enforce — story-005.
- Visual/Feel frame-perfect playtest evidence — story-006.
- `CreditIcon` Label opacity 0.6 + JetBrainsMono font + responsive font_size scaling F-HUD-2 — UI dédiée future story (Tier 2+ Chrome Zen polish).

---

## QA Test Cases

*Logic — automated unit/integration tests requis :*

**AC-HUD-01** : MENU boot hidden
- Setup : autoload `HUDSystem` instancié, mock `GSM.get_current_state() -> State.MENU`, mock `CreditEconomy.get_total() -> 0`.
- Action : `_ready()` s'exécute (await idle frame).
- Verify : `_credit_counter_label.visible == false` ou `_canvas_layer.visible == false` ; aucune `push_error` / `push_warning` loggée.
- Pass : `assert_bool(hud._canvas_layer.visible).is_false()`.

**AC-HUD-02** : Boot pull total hard set
- Setup : mock `CreditEconomy.get_total() -> 47`, mock `GSM.get_current_state() -> State.PLAYING`.
- Action : `_ready()` s'exécute, **avant** émission de tout signal `credits_changed`.
- Verify : `_credit_counter_label.text == "47"`.
- Pass : `assert_str(hud._credit_counter_label.text).is_equal("47")`.

**AC-HUD-03** : CanvasLayer.layer = 50
- Setup : autoload instancié.
- Action : `_ready()` complet.
- Verify : `_canvas_layer.layer == 50` ET `_canvas_layer.layer < 100` (HUD_LAYER_MAX).
- Pass : `assert_int(hud._canvas_layer.layer).is_equal(50)` + `assert_int(hud._canvas_layer.layer).is_less(100)`.

**AC-HUD-04** : Connexions signals
- Setup : autoload instancié, mocks GSM + CreditEconomy.
- Action : `_ready()` complet.
- Verify : `CreditEconomy.credits_changed.get_connections().size() == 1` ET la connection cible le HUD ; `GameStateManager.state_changed.get_connections().size() == 1` ET flag `CONNECT_DEFERRED` set.
- Pass : asserts sur `get_connections()[0].callable.get_object() == hud` + flag check.

**AC-HUD-17** : Pull boot exactement 1×
- Setup : spy injecté sur `MockGSM.get_current_state()` + `MockCreditEconomy.get_total()`.
- Action : `_ready()` complet.
- Verify : `MockGSM.get_current_state.call_count == 1` ET `MockCreditEconomy.get_total.call_count == 1`.

**AC-HUD-18** : BOOT_HYDRATE no tween
- Setup : `_ready()` terminé, Label.text = "0". Mock CreditEconomy émet `credits_changed.emit(15, 0, SourceKind.BOOT_HYDRATE)`.
- Action : await 1 idle frame.
- Verify : `Label.text == "15"` ET aucun Tween actif (`get_tree().get_processed_tweens().size() == 0` ou équivalent). *(Implémentation story-002 ; cette story vérifie la connexion stub no-op ne crash pas.)*

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/hud/hud_system_boot_test.gd` (NEW, ~150 lignes) couvrant AC-HUD-01/02/03/04/17/18.
- Mocks `tests/unit/hud/mock_gsm.gd` + `mock_credit_economy.gd` (référence pattern Combat MockAudioHandler).
- Smoke check : test suite green run via GdUnit4 headless (`godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/unit/hud/hud_system_boot_test.gd --ignoreHeadlessMode`).

**Status**: [ ] Not yet created.

---

## Dependencies

- **Hard upstream** :
  - **CreditEconomy autoload Ready** : 7/8 Complete (story-008 Blocked sur HUD epic — débloqué par cette epic). Stories 001-007 livrées (autoload + signals `credits_changed` + `get_total()` + `request_new_run` + persistence). ✅
  - **GameStateManager autoload Not Started** : ADR-0007 Accepted, GSM GDD APPROVED r1, mais GSM autoload `src/core/game_state_manager.gd` n'est **pas encore implémenté**. **Mitigation Sprint HUD** : utiliser mocks `MockGSM` test fixture pattern (référence Combat `mock_audio_handler.gd` 171 lignes). Production HUD attend GSM autoload boot Sprint A multi-epic.
- **Soft upstream** : Save/Load 8/8 Complete (HUD ne référence jamais SaveLoad — AC-HUD-35 grep enforce, mais SaveLoad Ready garantit Credit Economy boot hydrate fonctionne en prod).
- **Unlocks** : story-002 (listener credits_changed body) + story-003 (visibility state machine body) + story-004 (pulse différencié source) + story-005 (lints) + story-006 (playtest).
