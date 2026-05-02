# Tests unitaires story-006 enemy-system — LevelLint enemy slot triplet.
#
# Couvre :
#   AC-ENM-23 : EnemySlot scale uniform — validate_enemy_slot_marker3d() (EC-ENM-6).
#   AC-ENM-24 : EnemySlot min distance 1.0 m — validate_enemy_slot_min_distance() (EC-ENM-8).
#   AC-ENM-25 : EnemySlot clearance (pas dans wall) — validate_enemy_slot_clearance() (EC-ENM-7).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures : construites programmatiquement — aucun fichier .tscn requis.
#
# Story : production/epics/enemy-system/story-006-authoring-lints-enemy-slot.md
# GDD   : design/gdd/enemy-system.md r2 EC-ENM-6/7/8, AC-ENM-23/24/25.

extends GdUnitTestSuite

## preload de LevelLint : class_name non résolu en CI headless sans SceneTree complet.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")


# ---------------------------------------------------------------------------
# Helpers — fixtures programmatiques
# ---------------------------------------------------------------------------

## Crée Node3D root + SpawnMarkers + StaticEnvironment.
## [return] : [root, spawn_markers, static_env]
func _make_root() -> Array[Node3D]:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"

	var spawn_markers: Node3D = Node3D.new()
	spawn_markers.name = "SpawnMarkers"
	root.add_child(spawn_markers)

	var static_env: Node3D = Node3D.new()
	static_env.name = "StaticEnvironment"
	root.add_child(static_env)

	add_child(auto_free(root))
	return [root, spawn_markers, static_env]


## Crée un Marker3D EnemySlot_NN à pos avec basis. Pas encore parenté.
func _make_enemy_slot(slot_name: String, pos: Vector3, basis: Basis = Basis.IDENTITY) -> Marker3D:
	var marker: Marker3D = Marker3D.new()
	marker.name = slot_name
	marker.transform = Transform3D(basis, pos)
	return marker


## Crée un StaticBody3D avec BoxShape3D enfant à pos + size. Pas encore parenté.
func _make_box_static_body(body_name: String, pos: Vector3, size: Vector3) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = body_name
	sb.transform = Transform3D(Basis.IDENTITY, pos)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	return sb


# ---------------------------------------------------------------------------
# AC-ENM-23 — validate_enemy_slot_marker3d : scale uniform
# ---------------------------------------------------------------------------

func test_enemy_slot_marker3d_uniform_identity_scale_passes() -> void:
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3(0, 0, 0)))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_marker3d(arr[0])
	assert_array(errors) \
		.override_failure_message("AC-ENM-23: scale IDENTITY → 0 violations") \
		.is_empty()


func test_enemy_slot_marker3d_non_uniform_scale_fails() -> void:
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	# Scale (2, 1, 1) — non-uniform.
	var non_uniform: Basis = Basis.IDENTITY.scaled(Vector3(2.0, 1.0, 1.0))
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3.ZERO, non_uniform))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_marker3d(arr[0])
	assert_int(errors.size()) \
		.override_failure_message("AC-ENM-23: scale (2,1,1) → 1 violation") \
		.is_equal(1)
	assert_str(errors[0]) \
		.override_failure_message("AC-ENM-23: message contient le slot name + 'scale not uniform'") \
		.contains("EnemySlot_01")
	assert_str(errors[0]).contains("scale not uniform")


func test_enemy_slot_marker3d_uniform_2x_scale_also_fails() -> void:
	# Tolérance EC-ENM-6 : Vector3.ONE attendu — un Marker3D scaled à 2× est incorrect même uniformément.
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	var uniform_2x: Basis = Basis.IDENTITY.scaled(Vector3(2.0, 2.0, 2.0))
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3.ZERO, uniform_2x))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_marker3d(arr[0])
	assert_int(errors.size()) \
		.override_failure_message("AC-ENM-23: scale (2,2,2) uniform mais != 1.0 → 1 violation") \
		.is_equal(1)


func test_enemy_slot_marker3d_no_slots_returns_empty() -> void:
	var arr: Array[Node3D] = _make_root()
	# Aucun EnemySlot_* ajouté.
	var errors: Array[String] = LevelLintScript.validate_enemy_slot_marker3d(arr[0])
	assert_array(errors) \
		.override_failure_message("AC-ENM-23: étage sans EnemySlot → [] (EC-ENM-15 onboarding)") \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-ENM-24 — validate_enemy_slot_min_distance : distance ≥ 1.0 m
# ---------------------------------------------------------------------------

func test_enemy_slot_min_distance_3m_apart_passes() -> void:
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3(0, 0, 0)))
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_02", Vector3(3, 0, 0)))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_min_distance(arr[0])
	assert_array(errors) \
		.override_failure_message("AC-ENM-24: 3 m d'écart → 0 violations") \
		.is_empty()


func test_enemy_slot_min_distance_below_threshold_fails() -> void:
	# 0.5 m d'écart < 1.0 m → FAIL.
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3(0, 0, 0)))
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_02", Vector3(0.5, 0, 0)))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_min_distance(arr[0])
	assert_int(errors.size()) \
		.override_failure_message("AC-ENM-24: 0.5 m → 1 violation") \
		.is_equal(1)
	assert_str(errors[0]) \
		.override_failure_message("AC-ENM-24: message liste les 2 slots") \
		.contains("EnemySlot_01")
	assert_str(errors[0]).contains("EnemySlot_02")
	assert_str(errors[0]).contains("< 1.0m")


func test_enemy_slot_min_distance_three_close_slots_reports_three_pairs() -> void:
	# 3 slots tous à < 1m les uns des autres → C(3,2) = 3 pairs flaggées.
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3(0, 0, 0)))
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_02", Vector3(0.3, 0, 0)))
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_03", Vector3(0.6, 0, 0)))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_min_distance(arr[0])
	assert_int(errors.size()) \
		.override_failure_message("AC-ENM-24: 3 slots collés → 3 pairs (01-02, 01-03, 02-03)") \
		.is_equal(3)


func test_enemy_slot_min_distance_exactly_at_threshold_passes() -> void:
	# 1.0 m exactement (boundary) — la règle est « < 1.0 m » strict, donc 1.0 m PASSE.
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3(0, 0, 0)))
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_02", Vector3(1.0, 0, 0)))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_min_distance(arr[0])
	assert_array(errors) \
		.override_failure_message("AC-ENM-24: distance == 1.0 m exact → 0 violations (boundary inclusive)") \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-ENM-25 — validate_enemy_slot_clearance : pas dans wall
# ---------------------------------------------------------------------------

func test_enemy_slot_clearance_open_space_passes() -> void:
	# Slot @ (0, 0, 0), wall lointain @ (10, 0, 0).
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	var static_env: Node3D = arr[2]

	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3(0, 0, 0)))
	static_env.add_child(_make_box_static_body("Wall_01", Vector3(10, 0, 0), Vector3(1, 4, 1)))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_clearance(arr[0])
	assert_array(errors) \
		.override_failure_message("AC-ENM-25: slot loin du wall → 0 violations") \
		.is_empty()


func test_enemy_slot_clearance_inside_wall_fails() -> void:
	# Slot @ (0, 0, 0), wall AABB englobant l'origine.
	var arr: Array[Node3D] = _make_root()
	var spawn_markers: Node3D = arr[1]
	var static_env: Node3D = arr[2]

	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3(0, 0, 0)))
	# Wall à (0, 0, 0) avec size (4, 4, 4) → AABB englobe origine.
	static_env.add_child(_make_box_static_body("Wall_01", Vector3.ZERO, Vector3(4, 4, 4)))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_clearance(arr[0])
	assert_int(errors.size()) \
		.override_failure_message("AC-ENM-25: slot dans wall AABB → 1 violation") \
		.is_equal(1)
	assert_str(errors[0]).contains("EnemySlot_01")
	assert_str(errors[0]).contains("Wall_01")


func test_enemy_slot_clearance_no_static_env_returns_empty() -> void:
	# Cas dégénéré : pas de StaticEnvironment (lint hierarchy capture cette erreur séparément).
	var root: Node3D = Node3D.new()
	root.name = "EtageNoEnv"
	var spawn_markers: Node3D = Node3D.new()
	spawn_markers.name = "SpawnMarkers"
	root.add_child(spawn_markers)
	spawn_markers.add_child(_make_enemy_slot("EnemySlot_01", Vector3.ZERO))
	add_child(auto_free(root))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_clearance(root)
	assert_array(errors) \
		.override_failure_message("AC-ENM-25: pas de StaticEnvironment → silently empty (hierarchy lint flag séparé)") \
		.is_empty()


func test_enemy_slot_clearance_no_slots_returns_empty() -> void:
	# Étage onboarding sans grunt (EC-ENM-15) → pas de slot, pas de violation.
	var arr: Array[Node3D] = _make_root()
	var static_env: Node3D = arr[2]
	static_env.add_child(_make_box_static_body("Wall_01", Vector3.ZERO, Vector3(4, 4, 4)))

	var errors: Array[String] = LevelLintScript.validate_enemy_slot_clearance(arr[0])
	assert_array(errors).is_empty()
