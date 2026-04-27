# Tests unitaires Story-006 — CombatSystem ShapeCast3D collision layers + shape config.
#
# Couvre AC-1 à AC-5 (cf. story-006) + AC-CMB-09 :
#   AC-1 : layer bit 1 (Player) only — autres bits 2..32 false.
#   AC-2 : mask bit 2 (Enemy) only — bit 1 (Player self) false.
#   AC-3 : aucun bitmask littéral dans `combat_system.gd` (lint statique source).
#   AC-4 : project.godot contient `[layer_names]/3d_physics/layer_1..5` aux noms exacts.
#   AC-5 : ShapeCast3D.shape est CapsuleShape3D radius=0.45, height=1.8, max_results ≥ 8.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-006-shapecast3d-collision-layers-config.md
# ADR     : ADR-0008 D-2/D-3/D-6 (collision layer taxonomy + 1-indexed API)
# GDD     : design/gdd/player-combat-system.md AC-CMB-09

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const COMBAT_SOURCE_PATH: String = "res://src/gameplay/combat/combat_system.gd"
const PROJECT_GODOT_PATH: String = "res://project.godot"

const EXPECTED_LAYER_NAMES: Dictionary = {
	1: "LAYER_PLAYER",
	2: "LAYER_ENEMY",
	3: "LAYER_ENEMY_HITBOX",
	4: "LAYER_ENVIRONMENT",
	5: "LAYER_INTERACTIVE",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_combat_from_scene() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var combat: CombatSystem = packed.instantiate() as CombatSystem
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	player.add_child(combat)
	return combat


# ---------------------------------------------------------------------------
# AC-1 — Collision layer = Player bit only
# ---------------------------------------------------------------------------

## AC-1 : après _ready(), `set_collision_layer_value(1)` seul est true.
func test_combat_shapecast_collision_layer_player_bit_only() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_object(sc).is_not_null()

	# Assert — bit 1 true, bits 2..32 false
	assert_bool(sc.get_collision_layer_value(CollisionLayers.LAYER_PLAYER)) \
		.override_failure_message("AC-1: layer bit 1 (LAYER_PLAYER) doit être true") \
		.is_true()

	var stray_bits: Array[int] = []
	for i: int in range(2, 33):
		if sc.get_collision_layer_value(i):
			stray_bits.append(i)
	assert_int(stray_bits.size()) \
		.override_failure_message(
			"AC-1: aucun bit 2..32 ne doit être set sur collision_layer — stray: %s"
			% str(stray_bits)
		) \
		.is_equal(0)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-2 — Collision mask = Enemy bit only
# ---------------------------------------------------------------------------

## AC-2 : après _ready(), `set_collision_mask_value(2)` seul est true.
## Bit 1 (Player self) DOIT être false — Combat ne hit pas le Player lui-même.
func test_combat_shapecast_collision_mask_enemy_bit_only() -> void:
	var combat: CombatSystem = _make_combat_from_scene()
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_object(sc).is_not_null()

	assert_bool(sc.get_collision_mask_value(CollisionLayers.LAYER_ENEMY)) \
		.override_failure_message("AC-2: mask bit 2 (LAYER_ENEMY) doit être true") \
		.is_true()

	# Bit 1 explicitement false — protection contre auto-hit Player.
	assert_bool(sc.get_collision_mask_value(CollisionLayers.LAYER_PLAYER)) \
		.override_failure_message(
			"AC-2: mask bit 1 (LAYER_PLAYER) DOIT être false — Combat ne doit jamais hit le Player"
		) \
		.is_false()

	# Bits 3..32 false (notamment bit 3 EnemyHitbox — protection Rule 15)
	var stray_bits: Array[int] = []
	for i: int in range(3, 33):
		if sc.get_collision_mask_value(i):
			stray_bits.append(i)
	assert_int(stray_bits.size()) \
		.override_failure_message(
			"AC-2: aucun bit 3..32 ne doit être set sur collision_mask — stray: %s"
			% str(stray_bits)
		) \
		.is_equal(0)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-3 — Lint statique : aucun bitmask littéral dans combat_system.gd
# ---------------------------------------------------------------------------

## AC-3 : scan source `combat_system.gd` — aucune assignation `collision_layer = <int>`
## ou `collision_mask = <int>` avec valeur littérale (bitmask) ou hexadécimale.
## Patterns interdits :
##   collision_layer = 0b...
##   collision_layer = 0x...
##   collision_layer = 1 << N
##   collision_layer |= ...
## Lignes commentées (`#`) exemptées.
func test_combat_source_no_bitmask_literal() -> void:
	var file: FileAccess = FileAccess.open(COMBAT_SOURCE_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("AC-3: combat_system.gd doit être lisible") \
		.is_not_null()
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	var regex: RegEx = RegEx.new()
	# Match : collision_layer/mask suivi de = ou |= avec valeur 0b/0x/N<<X/digit pur.
	regex.compile(
		"\\bcollision_(layer|mask)\\s*(=|\\|=|\\&=)\\s*(0b|0x|\\d+\\s*$|\\d+\\s*[^_a-zA-Z]|.*<<)"
	)

	var violations: Array[String] = []
	for i: int in range(lines.size()):
		var line: String = lines[i]
		if line.strip_edges().begins_with("#"):
			continue
		# Exempt l'API 1-indexée légitime : set_collision_layer_value(...)
		if "set_collision_layer_value" in line or "set_collision_mask_value" in line:
			continue
		if "get_collision_layer_value" in line or "get_collision_mask_value" in line:
			continue
		if regex.search(line) != null:
			violations.append("L%d: %s" % [i + 1, line])

	assert_int(violations.size()) \
		.override_failure_message(
			"AC-3: aucun bitmask littéral autorisé sur collision_layer/mask. " +
			"Utiliser API 1-indexée set_collision_layer_value(N, true). Violations : %s"
			% str(violations)
		) \
		.is_equal(0)


# ---------------------------------------------------------------------------
# AC-4 — project.godot layer_names présents
# ---------------------------------------------------------------------------

## AC-4 : project.godot contient `3d_physics/layer_1..5` aux noms exacts.
func test_project_godot_contains_five_layer_names() -> void:
	var file: FileAccess = FileAccess.open(PROJECT_GODOT_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("AC-4: project.godot doit être lisible") \
		.is_not_null()
	var content: String = file.get_as_text()
	file.close()

	for layer_idx: int in EXPECTED_LAYER_NAMES.keys():
		var expected_name: String = EXPECTED_LAYER_NAMES[layer_idx]
		var pattern: String = '3d_physics/layer_%d="%s"' % [layer_idx, expected_name]
		assert_bool(pattern in content) \
			.override_failure_message(
				"AC-4: project.godot doit contenir `%s` (layer %d)" % [pattern, layer_idx]
			) \
			.is_true()


# ---------------------------------------------------------------------------
# AC-5 — ShapeCast3D shape config (CapsuleShape3D radius/height + max_results)
# ---------------------------------------------------------------------------

## AC-5 : shape est CapsuleShape3D avec radius=KATANA_RADIUS, height=KATANA_REACH,
## et max_results ≥ MAX_KILLS_PER_SWING + 2 (buffer dedup).
func test_combat_shapecast_capsule_shape_dimensions_and_max_results() -> void:
	var combat: CombatSystem = _make_combat_from_scene()
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D

	# Shape type
	assert_object(sc.shape) \
		.override_failure_message("AC-5: ShapeCast3D.shape doit être assignée") \
		.is_not_null()
	assert_bool(sc.shape is CapsuleShape3D) \
		.override_failure_message("AC-5: shape doit être CapsuleShape3D, reçu %s" % str(sc.shape)) \
		.is_true()

	var capsule: CapsuleShape3D = sc.shape as CapsuleShape3D

	# Radius
	assert_float(capsule.radius) \
		.override_failure_message(
			"AC-5: capsule.radius doit être KATANA_RADIUS (%.3f) — reçu %.3f"
			% [CombatSystem.KATANA_RADIUS, capsule.radius]
		) \
		.is_between(CombatSystem.KATANA_RADIUS - 0.001, CombatSystem.KATANA_RADIUS + 0.001)

	# Height
	assert_float(capsule.height) \
		.override_failure_message(
			"AC-5: capsule.height doit être KATANA_REACH (%.3f) — reçu %.3f"
			% [CombatSystem.KATANA_REACH, capsule.height]
		) \
		.is_between(CombatSystem.KATANA_REACH - 0.001, CombatSystem.KATANA_REACH + 0.001)

	# max_results buffer
	var min_results: int = CombatSystem.MAX_KILLS_PER_SWING + 2
	assert_int(sc.max_results) \
		.override_failure_message(
			"AC-5: ShapeCast3D.max_results doit être ≥ MAX_KILLS_PER_SWING + 2 (%d) — reçu %d"
			% [min_results, sc.max_results]
		) \
		.is_greater_equal(min_results)

	# Margin forcé à 0 par _ready() (ADR-0006 Gap 8)
	assert_float(sc.margin) \
		.override_failure_message("AC-5: ShapeCast3D.margin doit être 0.0 (ADR-0006 Gap 8)") \
		.is_equal(0.0)

	# enabled=false au démarrage (state IDLE)
	assert_bool(sc.enabled) \
		.override_failure_message("AC-5: ShapeCast3D.enabled doit être false en IDLE") \
		.is_false()

	combat.get_parent().queue_free()
