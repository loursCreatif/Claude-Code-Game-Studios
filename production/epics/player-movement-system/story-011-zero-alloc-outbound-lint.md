# Story 011: Zero-alloc signals benchmark + outbound-only lint

> **Epic**: player-movement-system
> **Status**: Complete
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0005 (Movement Signals Architecture) — D-9 zero-alloc dispatch + VC-2, D-10 outbound-only (zero knowledge of consumers) + VC-5/VC-6
**Decision Summary**: Payloads Vector3/float value types exclusivement (zero-alloc). MovementController ne référence aucun consumer par nom / NodePath / preload. Lint rule `movement-no-consumer-refs.md` + `movement-emit-physics-only.md` enforce.

**Engine**: Godot 4.6 | **Risk**: LOW

**Control Manifest Rules**:
- Required: payloads Vector3/float value types ; MovementController outbound-only (zéro référence `CameraSystem`/`CombatSystem`/`VFXManager`/`AudioManager`/`HUD`/`HUDController`) ; lint grep no-alloc-hot-paths + no-emit-from-process.
- Forbidden: `emit_signal("name", {...})` Dict literal ; `preload("res://src/gameplay/camera.gd")` depuis Movement ; `$NodePath` / `get_node("/root/...")` vers système aval.
- Guardrail: MEMORY_STATIC delta < 64 KB sur 3000 emits / 60s (VC-2 ADR-0005).

---

## Acceptance Criteria

*From ADR-0005 D-9 + D-10 + VC-2 + VC-5 + VC-6 :*

- [ ] **VC-2 — Zero-alloc dispatch** : `tests/performance/movement_signals_zero_alloc_test.gd` — GIVEN MovementController + 3 consumers stub attachés. WHEN 1000 `dash_started.emit()` + 1000 `wall_jumped.emit()` + 1000 `attacked.emit()` sur 60 s. THEN `Performance.get_monitor(Performance.MEMORY_STATIC)` delta < 64 KB.
- [ ] **VC-5 — Lint outbound-only** : `tests/static/movement_no_consumer_references_test.gd` OU `.claude/rules/movement-no-consumer-refs.md` grep — GIVEN parse de `src/core/movement_controller.gd` (ou path réel). THEN 0 match sur : `CameraSystem`, `CombatSystem`, `VFXManager`, `AudioManager`, `HUD`, `HUDController`, `get_node("/root/...` vers système aval, `preload("res://src/gameplay/...")`.
- [ ] **VC-6 — Lint emit physics only** : `.claude/rules/movement-emit-physics-only.md` — scan `<signal_name>.emit(` à l'intérieur de `func _process(`, `func _input(`, `func _unhandled_input(`, `func _ready(` dans `movement_controller.gd`. THEN 0 match.
- [ ] **Payloads typés stricts** : aucun emit `dash_started.emit({dir=..., speed=...})` (Dict literal) — grep détecte `emit_signal("..."`, `.emit({`, `.emit([` patterns → 0 match.
- [ ] **Règle lint enregistrée** : fichiers `.claude/rules/movement-no-consumer-refs.md` + `.claude/rules/movement-emit-physics-only.md` créés avec patterns grep explicites et rationale ADR-0005 D-9/D-10.

---

## Implementation Notes

*Derived from ADR-0005 D-9 / D-10 + VCs :*

- Test zero-alloc `tests/performance/movement_signals_zero_alloc_test.gd` :
  ```
  # Pattern identique à Input zero-alloc stress (story-008 Input)
  func test_zero_alloc_3000_emits_60s():
      if not OS.has_feature("debug"):
          return  # gate release build
      var player = preload("res://src/core/movement_controller.gd").new()
      add_child(player)
      var consumer_a := StubConsumer.new() ; var consumer_b := StubConsumer.new() ; var consumer_c := StubConsumer.new()
      player.dash_started.connect(consumer_a._on_dash_started)
      player.wall_jumped.connect(consumer_b._on_wall_jumped)
      player.attacked.connect(consumer_c._on_attacked)
      var baseline := Performance.get_monitor(Performance.MEMORY_STATIC)
      var dash_dir := Vector3(1, 0, 0)
      var wall_normal := Vector3(0, 0, 1)
      var launch_vel := Vector3(0, 6.5, 7.0)
      for i in 1000:
          player.dash_started.emit(dash_dir, 30.0)
          player.wall_jumped.emit(wall_normal, launch_vel)
          player.attacked.emit()
      # Attendre 60s simulation (ou simplement mesurer post-loop)
      var delta_mem := Performance.get_monitor(Performance.MEMORY_STATIC) - baseline
      assert_lt(delta_mem, 65536, "VC-2 ADR-0005 zero-alloc signal dispatch MEMORY_STATIC delta = %d bytes" % delta_mem)
  ```
- `.claude/rules/movement-no-consumer-refs.md` : pattern Markdown identique aux règles Input existantes (`.claude/rules/no-alloc-hot-paths.md` + `input-singleton-main-thread-only.md`). Contenu :
  ```
  # movement-no-consumer-refs
  
  **Source** : ADR-0005 D-10 + VC-5
  
  ## Forbidden patterns dans `src/core/movement_controller.gd` (ou futur path) :
  
  - grep `CameraSystem|CombatSystem|VFXManager|AudioManager|HUDController` → 0 match
  - grep `get_node("/root/` suivi d'un autoload consumer → 0 match
  - grep `preload("res://src/gameplay/(camera|combat|vfx|audio|hud)` → 0 match
  - grep `\\$(CameraSystem|CombatSystem|VFXManager|HUD)` NodePath → 0 match
  
  Rationale : MovementController est outbound-only. Zero knowledge of consumers. Consumers se connectent depuis leur propre `_ready()` via référence scene tree.
  ```
- `.claude/rules/movement-emit-physics-only.md` :
  ```
  # movement-emit-physics-only
  
  **Source** : ADR-0005 D-4 + VC-6
  
  ## Forbidden patterns :
  
  - scan fonctions `_process`, `_input`, `_unhandled_input`, `_ready`, `_notification` dans `movement_controller.gd`
  - rechercher `<signal_name>.emit(` pour chaque signal de la liste D-2
  - 0 match autorisé
  
  Rationale : Movement signals doivent être émis uniquement depuis `_physics_process` pour respecter l'autorité gameplay ADR-0001 et garantir la cohérence avec l'état.
  ```
- Tests static lint : peut être un script GDScript `tests/static/movement_lint_test.gd` qui utilise `FileAccess.open("res://src/core/movement_controller.gd")` + regex checks, OU un script CI shell qui grep directement.

---

## Out of Scope

- Signal dispatch performance cumulé ≤ 0.1 ms/frame amorti → Story 014
- Ajout d'un consumer spécifique (Camera, Combat) → epics downstream

---

## QA Test Cases

**VC-2 — zero-alloc 3000 emits** :
- Given : debug build GUT, MovementController + 3 stubs connected
- When : 1000 × (dash_started + wall_jumped + attacked).emit()
- Then : `MEMORY_STATIC` delta < 65536 bytes (64 KB)
- Edge cases : gate release build (early return si not debug) ; si échec → identifier signal incriminé via bisect.

**VC-5 — lint outbound-only** :
- Given : `src/core/movement_controller.gd` existe
- When : `Grep pattern=CameraSystem|CombatSystem|VFXManager|AudioManager|HUDController path=src/core/movement_controller.gd`
- Then : 0 match
- Edge cases : commentaires `# see CameraSystem consumer` autorisés uniquement si le match pattern les exclut (grep regex soigné).

**VC-6 — lint emit physics only** :
- Given : `src/core/movement_controller.gd` existe
- When : parse fonction bodies, identifier toutes les occurrences `<signal_name>.emit(` et leur fonction englobante
- Then : chaque match est dans `_physics_process` ou fonction appelée depuis lui (whitelist : `die`, `respawn`, `_try_dash_entry`, `_try_wall_run_entry`, etc.)
- Edge cases : rule initial peut être version simple "grep dans blocs `_process`/`_input`/`_unhandled_input`/`_ready`/`_notification`".

**Payloads value-types stricts** :
- Given : parse `movement_controller.gd`
- When : grep `.emit\(\{` ou `.emit\(\[`
- Then : 0 match (pas de Dict/Array literal).
- Edge cases : `emit_signal("..."` deprecated forme aussi interdite.

**Rules files** :
- Given : `.claude/rules/` directory
- When : listing
- Then : `movement-no-consumer-refs.md` + `movement-emit-physics-only.md` présents, syntaxe Markdown valide, ≥ 1 section Forbidden avec patterns grep explicites.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/performance/movement_signals_zero_alloc_test.gd` — must pass debug build CI (blocking).
- `tests/static/movement_lint_test.gd` OU `.claude/rules/movement-*.md` lint pipe shell — must pass CI.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 009 (signals déclarés)
- Unlocks: Story 014 (dispatch perf cumul), Story 015 (mocks respectent pattern consumer self-connect)
