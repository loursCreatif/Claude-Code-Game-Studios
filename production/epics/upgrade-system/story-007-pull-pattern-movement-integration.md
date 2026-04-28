# Story 007: Pull Pattern Movement Integration (60 Hz Read)

> **Epic**: upgrade-system
> **Status**: Ready
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/upgrade-system.md`
**Requirement** : R-UPG-7 (player-perspective scenario shop→level), R-UPG-8 (Movement pull-only consumer 60 Hz), EC-UPG-20/21/22 (lifecycle Player despawn/respawn), EC-UPG-23 (intra-tick read), EC-UPG-35 (`PROCESS_MODE_ALWAYS` survives engine pause).

**ADR Governing Implementation** : ADR-0001 Physics Rate 60 Hz.
**ADR Decision Summary** : Movement lit `Upgrade.can_*` à 60 Hz dans `_physics_process` (Movement Rules 3, 6, 7). Aucun signal, aucun handshake. La mutation d'un booléen autoload est instantanée et visible au prochain tick `_physics_process` Movement sans race intermediate.

**Engine** : Godot 4.6 | **Risk** : LOW
**Engine Notes** : Godot 4.6 main thread single-threaded — un `bool` 1 octet ne peut pas être torn-read structurellement (AC-UPG-26 documente l'invariant, ne le valide pas). `PROCESS_MODE_ALWAYS` permet `apply_upgrade` pendant `get_tree().paused = true`.

**Control Manifest Rules (Feature Layer)** :
- Required : Movement lit les flags publics directement (pas via méthode getter intermédiaire). Cette story livre **côté Upgrade** la garantie que les flags sont accessibles ; côté Movement, l'integration est déjà locked Movement r3 Rules 3/6/7.
- Forbidden : tout signal Upgrade outbound (R-UPG-6 — verrouillé par AC-UPG-27 grep get_signal_list, story 009).
- Guardrail : pas de coût performance ajouté côté Upgrade — Movement assume O(1) lecture propriété.

---

## Acceptance Criteria

- [ ] **AC-UPG-24 (a)** [BLOCKING MVP] : option (a) mock movement reader fixture lit `Upgrade.can_air_jump == true` après `apply_upgrade` pré-instanciation.
- [ ] **AC-UPG-24 (b)** [ADVISORY MVP, BLOCKING post-Movement-r4] : option (b) scène réelle `scenes/player/player.tscn` Movement lit flag au premier `_physics_process`.
- [ ] **AC-UPG-25** : `apply_upgrade` pendant despawn Player → nouveau Player instancié lit `true` au premier tick.
- [ ] **AC-UPG-26** [ADVISORY] : 100 lectures consécutives `can_air_jump` même tick retournent toutes `true` (documente invariant, ne valide pas — Godot 4.6 single-threaded).
- [ ] **AC-UPG-31** : `get_tree().paused = true` ; `apply_upgrade(&"double_jump")` mute le flag → `can_air_jump == true` immédiatement (PROCESS_MODE_ALWAYS).
- [ ] **AC-UPG-32** : `get_tree().paused = true` + script `PROCESS_MODE_ALWAYS` lit flag → retourne `true` sans exception ni stale value.

---

## Implementation Notes

### Mock Movement Reader fixture (option a)

```gdscript
# tests/helpers/mock_movement_reader.gd
class_name MockMovementReader
extends Node

var first_tick_can_air_jump: bool = false
var first_tick_can_dash: bool = false
var first_tick_can_wall_run: bool = false
var first_tick_observed: bool = false

func _physics_process(_delta: float) -> void:
    if first_tick_observed:
        return
    first_tick_can_air_jump = Upgrade.can_air_jump
    first_tick_can_dash = Upgrade.can_dash
    first_tick_can_wall_run = Upgrade.can_wall_run
    first_tick_observed = true
```

### Test pattern AC-24 (a)

```gdscript
func test_movement_reads_flag_after_apply() -> void:
    Upgrade.apply_upgrade(&"double_jump")    # avant Player instancié
    var reader := MockMovementReader.new()
    add_child(reader)                        # spawn déclenche _physics_process tick suivant
    await get_tree().physics_frame
    await get_tree().physics_frame           # 2 ticks pour s'assurer first_tick_observed
    assert_true(reader.first_tick_can_air_jump)
    assert_false(reader.first_tick_can_dash)
    reader.queue_free()
```

### Test pattern AC-24 (b) — scène réelle

```gdscript
func test_real_player_scene_reads_flag() -> void:
    Upgrade.apply_upgrade(&"dash_horizontal")
    var player_scene := load("res://scenes/player/player.tscn")
    var player := player_scene.instantiate()
    add_child(player)
    await get_tree().physics_frame
    # Note : le test dépend du Movement r3 actuel ; vérifier que MovementController
    # expose un getter test ou que `_can_dash_input_was_active` se déclenche correctement.
    # Hypothèse Sprint 1 : l'autoload Upgrade.can_dash == true suffit (assertion directe sur autoload).
    assert_eq(Upgrade.can_dash, true)
    player.queue_free()
```

L'option (b) est ADVISORY MVP car la scène `player.tscn` Movement r3 peut ne pas être encore disponible Sprint 1 (Movement story queue séparée). Promouvoir BLOCKING post-Movement r4 fresh re-review.

### AC-UPG-25 despawn pattern

```gdscript
func test_apply_during_despawn_propagates_to_new_player() -> void:
    var player1 := MockMovementReader.new()
    add_child(player1)
    await get_tree().physics_frame
    player1.queue_free()
    await get_tree().process_frame    # full despawn cycle

    Upgrade.apply_upgrade(&"double_jump")    # apply pendant absence
    assert_eq(Upgrade.can_air_jump, true)

    var player2 := MockMovementReader.new()
    add_child(player2)
    await get_tree().physics_frame
    await get_tree().physics_frame
    assert_true(player2.first_tick_can_air_jump)
    player2.queue_free()
```

### AC-UPG-31/32 PROCESS_MODE_ALWAYS test

```gdscript
func test_apply_during_pause() -> void:
    get_tree().paused = true
    Upgrade.apply_upgrade(&"double_jump")
    assert_eq(Upgrade.can_air_jump, true)    # AC-31 : mute possible pendant pause

    # AC-32 : reader script avec process_mode = PROCESS_MODE_ALWAYS lit flag
    var reader := MockMovementReader.new()
    reader.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(reader)
    await get_tree().physics_frame
    assert_true(reader.first_tick_can_air_jump)

    get_tree().paused = false    # cleanup
    reader.queue_free()
```

### AC-UPG-26 stabilité intra-tick (ADVISORY)

```gdscript
func test_no_torn_read_intra_tick() -> void:
    Upgrade.apply_upgrade(&"double_jump")
    var all_true: bool = true
    for i in 100:
        if not Upgrade.can_air_jump:
            all_true = false
            break
    assert_true(all_true)    # ADVISORY — documente invariant single-threaded
```

---

## Out of Scope

- Movement-side integration code (Movement r3 Rules 3/6/7 déjà locked dans Movement epic).
- Push pattern signal `capability_unlocked` (OQ-UPG-5 Tier 2+).
- Multi-player Player instances (anti-deps ADR-0005 N+1 player nécessite refactor EventBus).

---

## QA Test Cases

**AC-UPG-24 (a)** — Integration test [BLOCKING]
- Given : Upgrade autoload + `MockMovementReader` fixture node.
- When : `apply_upgrade(&"double_jump")` puis `add_child(reader)` puis 2× `await physics_frame`.
- Then : `reader.first_tick_can_air_jump == true`, `reader.first_tick_can_dash == false`.

**AC-UPG-24 (b)** — Integration test [ADVISORY MVP]
- Given : Upgrade autoload + scène réelle `player.tscn`.
- When : `apply_upgrade(&"dash_horizontal")` puis instanciation player + `await physics_frame`.
- Then : `Upgrade.can_dash == true` (assertion sur autoload, pas sur internals Movement).
- Note : promu BLOCKING post-Movement r4 fresh re-review si push pattern non introduit.

**AC-UPG-25** — Integration test
- Given : sequence MockReader1 spawn → free → `apply_upgrade(&"double_jump")` → MockReader2 spawn.
- When : MockReader2 `_physics_process` premier tick.
- Then : `MockReader2.first_tick_can_air_jump == true` (autoload survival).

**AC-UPG-26** — Integration test [ADVISORY]
- Given : Upgrade.can_air_jump == true.
- When : 100 lectures consécutives même `_physics_process`.
- Then : toutes retournent `true`. Pass tolérant — ADVISORY, single-threaded invariant.

**AC-UPG-31 / AC-UPG-32** — Integration test [pause survival]
- Given : `get_tree().paused = true`.
- When AC-31 : `apply_upgrade(&"double_jump")`.
- Then AC-31 : `Upgrade.can_air_jump == true` immédiatement.
- When AC-32 : reader avec PROCESS_MODE_ALWAYS lit flag.
- Then AC-32 : retourne `true` sans exception ; pas de stale value (compare avec lecture pre-pause).
- Cleanup : `get_tree().paused = false` en `after_each`.

---

## Test Evidence

**Story Type** : Integration
**Required evidence** :
- `tests/integration/upgrade/pull_pattern_movement_test.gd` couvrant AC-24(a)/25/26/31/32 sur autoload + fixture mock.
- `tests/integration/upgrade/pull_pattern_real_player_test.gd` couvrant AC-24(b) ADVISORY (skippable si scène player.tscn non disponible).

**Status** : [ ] Not yet created

---

## Dependencies

- Depends on : 001 (autoload), 003 (apply_upgrade body), 005 (boot hydration — fixtures réinitialisées par scène test).
- Soft : Movement r3 Rules 3/6/7 locked (déjà OK 2026-04-27). Caveat : si Movement r4 fresh re-review introduit push pattern, OQ-UPG-2-bis ouvert et amender cette story.
- Unlocks : aucune dépendance directe — c'est le contrat downstream consommé par Movement epic stories.
