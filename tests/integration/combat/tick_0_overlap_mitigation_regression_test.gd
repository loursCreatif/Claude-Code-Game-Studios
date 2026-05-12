# Test régression Story-010 — AC-CMB-47 tick 0 overlap mitigation.
#
# Couvre AC-CMB-47 + AC-3 régression :
#   AC-CMB-47 : MockEnemy à `_prev_position + aim_forward × 0.5` (overlap à l'origine
#               du sweep tick 0) → `_collect_swing_hits()` retourne son instance_id,
#               `_resolve_kills()` appelle `die()`, `enemy_killed` émis.
#   AC-3      : Comportement natif Godot 4.6 + Jolt sans code mitigation
#               `_tick0_intersect_shape_overlap()` ajouté (Variante B confirmée
#               empiriquement — voir `docs/engine-reference/godot/modules/physics.md`
#               section "ShapeCast3D overlap at origin Godot 4.6 + Jolt empirical test").
#
# Approche : test d'intégration réelle avec ShapeCast3D + MockEnemy + Jolt physics
# step. Pas de mock physics — on vérifie que le comportement empirique observé
# (story-010 prelim 2026-05-04) reste stable post-merge. Si Jolt change ce
# comportement futur, ce test devient rouge et signale qu'il faut soit (a) ajouter
# `_tick0_intersect_shape_overlap()` mitigation, soit (b) re-runner le prelim
# empirique pour confirmer que la mitigation n'est plus requise.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-010-tick-0-overlap-mitigation-gap2.md
# ADR     : ADR-0006 (Combat tick model)
# GDD     : design/gdd/player-combat-system.md AC-CMB-47

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const MockEnemyScript: GDScript = preload("res://tests/unit/combat/mock_enemy.gd")

# Geometry per CombatSystem constants (KATANA_REACH=1.8 m, KATANA_RADIUS=0.45 m)
# AC-CMB-47 spec : enemy à `_prev_position + aim_forward × 0.5` — overlap origin sweep tick 0
# (avant que le shapecast ne parcoure target_position).
const ENEMY_OVERLAP_OFFSET: float = 0.5

# Aim Combat default sans Camera = Vector3.FORWARD = (0, 0, -1)
const AIM_DEFAULT: Vector3 = Vector3.FORWARD

# Physics frames d'attente pour Jolt body registration + AABB stabilisation
const PHYSICS_FRAMES_WAIT: int = 3


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_combat() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)
	return combat


func _make_mock_enemy_at(position: Vector3) -> StaticBody3D:
	var enemy: StaticBody3D = MockEnemyScript.new()
	enemy.position = position
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	enemy.add_child(shape)
	add_child(enemy)
	return enemy


func _await_physics_frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


# ---------------------------------------------------------------------------
# AC-CMB-47 — Overlap origin tick 0 native detection (Variante B empirique)
# ---------------------------------------------------------------------------

## AC-CMB-47 régression : MockEnemy à `_prev_position + aim × 0.5` overlap origin
## → `_collect_swing_hits()` retourne son instance_id sans mitigation `_tick0_*`.
##
## Si ce test échoue, soit (a) Jolt a changé le comportement et il faut re-runner
## `tests/empirical/shapecast_overlap_origin_test.gd` pour confirmer la nouvelle
## variante, soit (b) ajouter `_tick0_intersect_shape_overlap()` mitigation.
func test_combat_tick0_overlap_origin_enemy_detected_natively() -> void:
	# Arrange : Combat à origine, prev_position = origine, enemy à overlap origin.
	var combat: CombatSystem = _make_combat()
	await _await_physics_frames(1)  # _ready setup ShapeCast3D

	var player: CharacterBody3D = combat.get_parent() as CharacterBody3D
	player.global_position = Vector3.ZERO
	combat._prev_position = player.global_position

	# Enemy positionné à `prev + aim × 0.5` — overlap au début du sweep substep 0.
	var enemy_target: Vector3 = combat._prev_position + AIM_DEFAULT * ENEMY_OVERLAP_OFFSET
	var enemy: StaticBody3D = _make_mock_enemy_at(enemy_target)
	var enemy_id: int = enemy.get_instance_id()

	# Wait Jolt body registration + AABB stabilisation.
	await _await_physics_frames(PHYSICS_FRAMES_WAIT)

	# Act : déclenche la collecte tick 0 sweep, comportement natif sans mitigation.
	var hit_ids: Array[int] = combat._collect_swing_hits()

	# Assert : enemy détecté nativement par les 3 substeps (substep 0 origin overlap).
	assert_array(hit_ids) \
		.override_failure_message(
			"AC-CMB-47 régression : MockEnemy à overlap origin (prev + aim × 0.5) "
			+ "doit être détecté par `_collect_swing_hits()` natif Godot 4.6 + Jolt. "
			+ "Si rouge → re-runner `tests/empirical/shapecast_overlap_origin_test.gd` "
			+ "et vérifier verdict Variante A vs B. Cf. story-010 + "
			+ "docs/engine-reference/godot/modules/physics.md."
		) \
		.contains([enemy_id])


## AC-CMB-47 sequel : `_resolve_kills()` post-detection appelle `die()` 1× et
## ajoute instance_id à `_hit_this_swing`.
##
## Note : MockEnemy n'émet PAS `enemy_killed` (signal réservé au Grunt réel testé
## en suite Enemy — cf. mock_enemy.gd l.9-10). L'assertion sur die() count et
## `_hit_this_swing` populé suffit à couvrir AC-CMB-47 régression côté Combat.
func test_combat_tick0_overlap_origin_resolves_kill_via_die_contract() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat()
	await _await_physics_frames(1)

	var player: CharacterBody3D = combat.get_parent() as CharacterBody3D
	player.global_position = Vector3.ZERO
	combat._prev_position = player.global_position

	var enemy_target: Vector3 = combat._prev_position + AIM_DEFAULT * ENEMY_OVERLAP_OFFSET
	var enemy: StaticBody3D = _make_mock_enemy_at(enemy_target)
	var enemy_id: int = enemy.get_instance_id()
	await _await_physics_frames(PHYSICS_FRAMES_WAIT)

	# Act : full pipeline (collect → resolve).
	var hit_ids: Array[int] = combat._collect_swing_hits()
	combat._resolve_kills(hit_ids)

	# Assert : die() appelé 1×, _hit_this_swing contient instance_id (chemin overlap origin).
	assert_int(enemy.get("_die_count")) \
		.override_failure_message("AC-CMB-47 : die() doit être appelé exactement 1 fois") \
		.is_equal(1)
	assert_bool(enemy.call("is_dead")) \
		.override_failure_message("AC-CMB-47 : enemy.is_dead() doit être true post-resolve") \
		.is_true()
	assert_array(combat._hit_this_swing) \
		.override_failure_message("AC-CMB-47 : `_hit_this_swing` doit contenir l'instance_id post-resolve") \
		.contains([enemy_id])
