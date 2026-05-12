# Tests unitaires Story-008 — CombatSystem `_prev_position` per-tick + KATANA_REACH constant.
#
# Couvre AC-1 à AC-5 (cf. story-008) + AC-CMB-43/44 :
#   AC-1 : reach constant (KATANA_REACH=1.8) indépendamment de player.velocity.
#   AC-2 : per-tick repositionnement du sweep (suit le Player tick par tick).
#   AC-3 : `_prev_position` capturé à la FIN de `_physics_process`.
#   AC-4 : `_prev_position` initialisé à `_ready()` = player.global_position.
#   AC-5 : ownership grep — `_prev_position` writes uniquement dans combat_system.gd.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-008-prev-position-per-tick-reach-constant.md
# ADR     : ADR-0006 D-3 (`_prev_position` ownership exclusive Combat, end-of-tick capture)
# GDD     : design/gdd/player-combat-system.md AC-CMB-43/44 + Rule 6/Rule 11

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const SRC_DIR: String = "res://src/"
const DELTA_60HZ: float = 1.0 / 60.0


# ---------------------------------------------------------------------------
# Mock CameraSystem (réutilisé du pattern story-007)
# ---------------------------------------------------------------------------

class MockCameraSystem extends Node3D:
	var aim_forward: Vector3 = Vector3(0.0, 0.0, -1.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_combat_at(player_pos: Vector3) -> Array:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	player.global_position = player_pos

	var mock_cam: MockCameraSystem = MockCameraSystem.new()
	mock_cam.name = "CameraArm"
	player.add_child(mock_cam)

	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)

	return [combat, mock_cam]


# ---------------------------------------------------------------------------
# AC-4 — `_prev_position` init at _ready() = player.global_position
# ---------------------------------------------------------------------------

## AC-4 : Combat `_ready()` capture la position du Player.
func test_combat_prev_position_initialized_to_player_position_at_ready() -> void:
	var pair: Array = _make_combat_at(Vector3(5.0, 0.0, 0.0))
	var combat: CombatSystem = pair[0]

	assert_vector(combat._prev_position) \
		.override_failure_message(
			"AC-4: _prev_position doit être initialisé à player.global_position au _ready() — reçu %s"
			% str(combat._prev_position)
		) \
		.is_equal_approx(Vector3(5.0, 0.0, 0.0), Vector3.ONE * 0.001)

	combat.get_parent().queue_free()


## AC-4 player @ origin : init = ZERO.
func test_combat_prev_position_initialized_to_origin_when_player_at_origin() -> void:
	var pair: Array = _make_combat_at(Vector3.ZERO)
	var combat: CombatSystem = pair[0]

	assert_vector(combat._prev_position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-3 — `_prev_position` end-of-tick capture
# ---------------------------------------------------------------------------

## AC-3 : 1 tick `_physics_process` doit capturer la position courante du Player.
func test_combat_prev_position_captured_end_of_physics_process() -> void:
	var pair: Array = _make_combat_at(Vector3.ZERO)
	var combat: CombatSystem = pair[0]
	var player: CharacterBody3D = combat.get_parent() as CharacterBody3D

	# Move player avant le tick
	player.global_position = Vector3(1.0, 0.0, 0.0)

	# Act
	combat._physics_process(DELTA_60HZ)

	# Assert
	assert_vector(combat._prev_position) \
		.override_failure_message(
			"AC-3: _prev_position doit être capturé à fin _physics_process — reçu %s"
			% str(combat._prev_position)
		) \
		.is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3.ONE * 0.001)

	combat.get_parent().queue_free()


## AC-3 edge : DEAD state → `_prev_position` PAS mis à jour ce tick (early return).
func test_combat_prev_position_not_updated_when_state_is_dead() -> void:
	var pair: Array = _make_combat_at(Vector3(2.0, 0.0, 0.0))
	var combat: CombatSystem = pair[0]
	var player: CharacterBody3D = combat.get_parent() as CharacterBody3D

	combat._state = CombatSystem.State.DEAD
	# Player bouge mais Combat est DEAD → no update
	player.global_position = Vector3(99.0, 0.0, 0.0)

	combat._physics_process(DELTA_60HZ)

	# _prev_position figé à la valeur du _ready (Vector3(2,0,0))
	assert_vector(combat._prev_position) \
		.override_failure_message(
			"AC-3 edge: _prev_position doit rester figé en DEAD (early return) — reçu %s"
			% str(combat._prev_position)
		) \
		.is_equal_approx(Vector3(2.0, 0.0, 0.0), Vector3.ONE * 0.001)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-1 — Reach constant under any velocity (KATANA_REACH = 1.8)
# ---------------------------------------------------------------------------

## AC-1 : KATANA_REACH constant indépendamment de player.velocity (Rule 11 — pas de
## velocity lookahead).
func test_combat_katana_reach_constant_regardless_of_player_velocity() -> void:
	var pair: Array = _make_combat_at(Vector3.ZERO)
	var combat: CombatSystem = pair[0]
	var player: CharacterBody3D = combat.get_parent() as CharacterBody3D

	# Test à plusieurs vélocités — la shape height ne doit jamais varier.
	var velocities: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(0.0, 0.0, -10.0),  # vitesse standard
		Vector3(0.0, 0.0, -30.0),  # dash
		Vector3(0.0, 0.0, -1000.0),  # synthétique extrême
	]

	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	var capsule: CapsuleShape3D = sc.shape as CapsuleShape3D

	for v: Vector3 in velocities:
		player.velocity = v
		# La height n'est jamais mutée par Combat — elle est fixée dans la scène
		# à KATANA_REACH=1.8 via la sub-resource CapsuleShape3D_katana (story 006).
		assert_float(capsule.height) \
			.override_failure_message(
				"AC-1: capsule.height doit être KATANA_REACH=%.3f peu importe velocity=%s — reçu %.3f"
				% [CombatSystem.KATANA_REACH, str(v), capsule.height]
			) \
			.is_between(
				CombatSystem.KATANA_REACH - 0.001,
				CombatSystem.KATANA_REACH + 0.001
			)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-2 — Per-tick sweep position update (suit le Player)
# ---------------------------------------------------------------------------

## AC-2 : pendant SWINGING, le sweep doit suivre le Player tick par tick.
## Joueur déplace de 0.5 m sur Z entre tick 2 et tick 3 → ShapeCast3D origin
## reflète la nouvelle position, pas figé au tick 0.
func test_combat_shapecast_origin_updated_per_tick_during_swinging() -> void:
	var pair: Array = _make_combat_at(Vector3.ZERO)
	var combat: CombatSystem = pair[0]
	var player: CharacterBody3D = combat.get_parent() as CharacterBody3D

	# Démarrer un swing (aim = -Z, position = origin)
	combat.attacked()
	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)

	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	var origin_tick_0: Vector3 = sc.global_transform.origin

	# Tick 1 + Tick 2 (player immobile)
	combat._physics_process(DELTA_60HZ)
	combat._physics_process(DELTA_60HZ)
	var origin_tick_2: Vector3 = sc.global_transform.origin

	# Player avance de 0.5 m sur -Z entre tick 2 et tick 3
	player.global_position = Vector3(0.0, 0.0, -0.5)

	# Tick 3
	combat._physics_process(DELTA_60HZ)
	var origin_tick_3: Vector3 = sc.global_transform.origin

	# Assert — origin tick 3 a bougé de -0.5 sur Z par rapport à tick 0
	var expected_tick_3: Vector3 = Vector3(0.0, 0.0, -0.5 - CombatSystem.KATANA_REACH / 2.0)
	assert_vector(origin_tick_3) \
		.override_failure_message(
			"AC-2: origin tick 3 doit refléter player.position - REACH/2 sur Z — " +
			"attendu %s, reçu %s (tick 0 était %s, tick 2 était %s)"
			% [str(expected_tick_3), str(origin_tick_3), str(origin_tick_0), str(origin_tick_2)]
		) \
		.is_equal_approx(expected_tick_3, Vector3.ONE * 0.001)

	# Sanity check : tick 0 et tick 2 sont identiques (player immobile)
	assert_vector(origin_tick_2) \
		.override_failure_message("AC-2 sanity: origin tick 0 == tick 2 si player immobile") \
		.is_equal_approx(origin_tick_0, Vector3.ONE * 0.001)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-5 — Ownership grep : `_prev_position` writes uniquement dans combat_system.gd
# ---------------------------------------------------------------------------

## AC-5 : aucun fichier `.gd` hors `src/gameplay/combat/` n'écrit
## `._prev_position` (assignment ou augmented assignment).
##
## Note TD-008 split : tous les fichiers `src/gameplay/combat/*.gd` sont des
## composition handlers appartenant à CombatSystem (combat_system.gd +
## combat_tick_handler.gd + combat_hit_handler.gd + combat_lifecycle_handler.gd +
## combat_slow_mo_handler.gd). L'invariant ADR-0006 D-3 reste préservé : seul
## CombatSystem (et ses handlers internes) écrit `_prev_position` — pas de
## consommateur externe (camera/VFX/audio/level).
##
## Pattern recherché : `\._prev_position\s*=` (assignment direct).
## Lignes commentées (`#`) exemptées.
func test_no_external_writes_to_combat_prev_position() -> void:
	var combat_dir: String = "res://src/gameplay/combat/"
	var regex: RegEx = RegEx.new()
	regex.compile("\\._prev_position\\s*=")

	var violations: Array[String] = []
	_scan_dir_recursive(SRC_DIR, regex, combat_dir, violations)

	assert_int(violations.size()) \
		.override_failure_message(
			"AC-5: aucune écriture externe à _prev_position autorisée. " +
			"Combat owne exclusivement (ADR-0006 D-3). Violations : %s" % str(violations)
		) \
		.is_equal(0)


## Scan récursif du dossier `src/` à la recherche du pattern, en excluant tout
## fichier sous `excluded_dir_prefix` (préfixe de path — autorise un dossier entier
## pour les composition handlers, pattern TD-008).
func _scan_dir_recursive(
		dir_path: String,
		regex: RegEx,
		excluded_dir_prefix: String,
		violations: Array[String]
) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var sub_path: String = dir_path + entry
		if dir.current_is_dir():
			_scan_dir_recursive(sub_path + "/", regex, excluded_dir_prefix, violations)
		elif entry.ends_with(".gd") and not sub_path.begins_with(excluded_dir_prefix):
			var file: FileAccess = FileAccess.open(sub_path, FileAccess.READ)
			if file == null:
				entry = dir.get_next()
				continue
			var lines: PackedStringArray = file.get_as_text().split("\n")
			file.close()
			for i: int in range(lines.size()):
				var line: String = lines[i]
				if line.strip_edges().begins_with("#"):
					continue
				if regex.search(line) != null:
					violations.append("%s:%d: %s" % [sub_path, i + 1, line])
		entry = dir.get_next()
	dir.list_dir_end()
