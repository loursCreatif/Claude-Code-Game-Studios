# Integration tests for Story 003 — EnemySpawner.spawn_for_scene().
# Couvre AC-ENM-08 (3 EnemySlot → 3 Grunts au bon endroit), AC-ENM-09 (rotation
# 45° basis copiée à FacingPivot), AC-ENM-10 (archetype unknown fallback grunt).
#
# Pattern : construire un scene_root synthétique (Node3D + 3 Marker3D enfants nommés
# `EnemySlot_01..03`), appeler `EnemySpawner.spawn_for_scene(root)`, asserter sur
# le nombre + positions + orientations + warnings.
#
# Story Type : Integration. Test Evidence path : tests/integration/enemy/.
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const POSITION_TOLERANCE: float = 0.001


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

var _scene_root: Node3D = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	_scene_root = Node3D.new()
	_scene_root.name = "TestSceneRoot"
	add_child(_scene_root)
	await get_tree().process_frame


func after_test() -> void:
	if _scene_root != null and is_instance_valid(_scene_root):
		_scene_root.queue_free()
	_scene_root = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add_slot(name: String, pos: Vector3, basis: Basis = Basis.IDENTITY) -> Marker3D:
	var slot: Marker3D = Marker3D.new()
	slot.name = name
	slot.transform = Transform3D(basis, pos)
	_scene_root.add_child(slot)
	return slot


# ---------------------------------------------------------------------------
# AC-ENM-08 — 3 EnemySlot → 3 Grunts spawnés aux bonnes positions
# ---------------------------------------------------------------------------

func test_spawn_three_slots_creates_three_grunts_at_correct_positions() -> void:
	# Arrange — 3 slots à des positions distinctes.
	var pos1: Vector3 = Vector3(5.0, 0.0, 10.0)
	var pos2: Vector3 = Vector3(-3.0, 1.5, 8.0)
	var pos3: Vector3 = Vector3(0.0, 0.0, 20.0)
	_add_slot("EnemySlot_01", pos1)
	_add_slot("EnemySlot_02", pos2)
	_add_slot("EnemySlot_03", pos3)
	await get_tree().process_frame

	# Act
	var spawned: Array[Grunt] = EnemySpawner.spawn_for_scene(_scene_root)
	await get_tree().process_frame

	# Assert — 3 grunts.
	assert_int(spawned.size()) \
		.override_failure_message("AC-ENM-08: 3 EnemySlot → 3 Grunts spawnés") \
		.is_equal(3)

	# Positions matchent (DFS preorder retourne ordre d'ajout dans la scène).
	var positions: Array[Vector3] = []
	for g: Grunt in spawned:
		positions.append(g.global_position)

	assert_bool(positions.has(pos1)) \
		.override_failure_message("AC-ENM-08: position EnemySlot_01 (%s) doit être assignée à un grunt" % str(pos1)) \
		.is_true()
	assert_bool(positions.has(pos2)) \
		.override_failure_message("AC-ENM-08: position EnemySlot_02 (%s) assignée" % str(pos2)) \
		.is_true()
	assert_bool(positions.has(pos3)) \
		.override_failure_message("AC-ENM-08: position EnemySlot_03 (%s) assignée" % str(pos3)) \
		.is_true()

	# Tous les Grunts sont dans le scene_root (parent assignment).
	for g: Grunt in spawned:
		assert_object(g.get_parent()) \
			.override_failure_message("AC-ENM-08: grunt parent doit être scene_root") \
			.is_equal(_scene_root)


# ---------------------------------------------------------------------------
# AC-ENM-09 — orientation 45° → FacingPivot.global_basis matche orthonormalisé
# ---------------------------------------------------------------------------

func test_spawn_slot_with_rotation_copies_orthonormalized_basis_to_facing_pivot() -> void:
	# Arrange — slot rotation 45° around Y.
	var rotated_basis: Basis = Basis.IDENTITY.rotated(Vector3.UP, PI / 4.0)
	_add_slot("EnemySlot_01", Vector3(5.0, 0.0, 10.0), rotated_basis)
	await get_tree().process_frame

	# Act
	var spawned: Array[Grunt] = EnemySpawner.spawn_for_scene(_scene_root)
	await get_tree().process_frame
	assert_int(spawned.size()).is_equal(1)

	# Assert — FacingPivot.global_basis ≈ rotated_basis.orthonormalized().
	var grunt: Grunt = spawned[0]
	var pivot: Node3D = grunt.get_node("%FacingPivot") as Node3D
	assert_object(pivot).is_not_null()

	var expected: Basis = rotated_basis.orthonormalized()
	var actual: Basis = pivot.global_basis

	# Compare each axis avec tolerance — les comparaisons de Basis exactes peuvent
	# subir précision flottante après orthonormalize.
	assert_vector(actual.x) \
		.override_failure_message("AC-ENM-09: basis.x doit matcher orthonormalisé attendu") \
		.is_equal_approx(expected.x, Vector3.ONE * 0.001)
	assert_vector(actual.y) \
		.override_failure_message("AC-ENM-09: basis.y doit matcher") \
		.is_equal_approx(expected.y, Vector3.ONE * 0.001)
	assert_vector(actual.z) \
		.override_failure_message("AC-ENM-09: basis.z doit matcher") \
		.is_equal_approx(expected.z, Vector3.ONE * 0.001)


# ---------------------------------------------------------------------------
# AC-ENM-10 — archetype "drone" unknown au MVP → fallback grunt + warning
# ---------------------------------------------------------------------------

func test_spawn_unknown_archetype_falls_back_to_grunt() -> void:
	# Arrange — slot avec meta archetype="drone" (Tier 2+ pas livré).
	var slot: Marker3D = _add_slot("EnemySlot_01", Vector3(5.0, 0.0, 10.0))
	slot.set_meta("archetype", &"drone")
	await get_tree().process_frame

	# Act — spawn (warning push expected mais pas assert car GdUnit4 console capture
	# n'est pas standard ; on vérifie la robustesse — pas de crash, fallback grunt
	# instancié).
	var spawned: Array[Grunt] = EnemySpawner.spawn_for_scene(_scene_root)
	await get_tree().process_frame

	# Assert — un grunt instancié malgré archetype unknown.
	assert_int(spawned.size()) \
		.override_failure_message("AC-ENM-10: archetype 'drone' unknown → fallback grunt instancié") \
		.is_equal(1)

	var grunt: Grunt = spawned[0]
	assert_object(grunt) \
		.override_failure_message("AC-ENM-10: instance doit être Grunt (cast réussi)") \
		.is_not_null()
	# Position inchangée par le fallback.
	assert_vector(grunt.global_position) \
		.override_failure_message("AC-ENM-10: position assignée correctement malgré fallback") \
		.is_equal_approx(Vector3(5.0, 0.0, 10.0), Vector3.ONE * POSITION_TOLERANCE)


# ---------------------------------------------------------------------------
# Bonus — scene_root null retourne [] sans crash
# ---------------------------------------------------------------------------

func test_spawn_null_scene_root_returns_empty() -> void:
	var spawned: Array[Grunt] = EnemySpawner.spawn_for_scene(null)
	assert_int(spawned.size()) \
		.override_failure_message("Bonus: scene_root null → [] (robustesse)") \
		.is_equal(0)


# ---------------------------------------------------------------------------
# Bonus — scene_root sans EnemySlot retourne [] (étage onboarding sans grunt légal)
# ---------------------------------------------------------------------------

func test_spawn_scene_without_slots_returns_empty() -> void:
	# EC-ENM-15 : étage légal sans menace.
	# Aucun slot ajouté.
	var spawned: Array[Grunt] = EnemySpawner.spawn_for_scene(_scene_root)
	assert_int(spawned.size()) \
		.override_failure_message("EC-ENM-15: scène sans EnemySlot_* → [] (onboarding salle calme)") \
		.is_equal(0)


# ---------------------------------------------------------------------------
# Bonus — meta absent → default grunt sans warning
# ---------------------------------------------------------------------------

func test_spawn_slot_without_archetype_meta_uses_default_grunt() -> void:
	# Arrange — slot sans meta archetype (default = grunt).
	_add_slot("EnemySlot_01", Vector3(5.0, 0.0, 10.0))
	await get_tree().process_frame

	# Act
	var spawned: Array[Grunt] = EnemySpawner.spawn_for_scene(_scene_root)
	await get_tree().process_frame

	# Assert
	assert_int(spawned.size()) \
		.override_failure_message("Bonus: slot sans meta → grunt default") \
		.is_equal(1)
