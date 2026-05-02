# Unit tests for Story 002 — FacingPivot orthonormalization (AC-ENM-07c, EC-ENM-6).
# Verifies que _ready normalize toute basis non-orthonormale (auteur niveau scaled le Marker3D).
#
# Pattern : load Grunt.tscn, set FacingPivot.transform.basis non-uniformément AVANT add_child,
# add_child → _ready runs → assert global_basis orthonormalized.
#
# Story Type : Logic. Test Evidence path : tests/unit/enemy/.
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite


const GRUNT_SCENE_PATH: String = "res://src/gameplay/enemy/Grunt.tscn"


var _grunt: Grunt = null


func after_test() -> void:
	if _grunt != null and is_instance_valid(_grunt):
		_grunt.queue_free()
	_grunt = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-ENM-07c — Non-uniform scale basis → orthonormalized post-_ready
# ---------------------------------------------------------------------------

func test_facing_pivot_orthonormalized_when_spawn_basis_non_uniform() -> void:
	# Arrange — instantiate sans add_child (pas encore en scene tree).
	var packed: PackedScene = load(GRUNT_SCENE_PATH) as PackedScene
	_grunt = packed.instantiate() as Grunt
	var pivot: Node3D = _grunt.get_node("%FacingPivot") as Node3D
	assert_object(pivot).is_not_null()

	# Inject non-uniform scale basis sur FacingPivot AVANT add_child (donc avant _ready).
	pivot.transform = Transform3D(
		Basis.IDENTITY.scaled(Vector3(2.0, 1.0, 1.0)),
		Vector3.ZERO,
	)
	# Sanity check — basis non-orthonormale au boot.
	var pre_basis: Basis = pivot.transform.basis
	assert_float(pre_basis.x.length()) \
		.override_failure_message("Setup: pre_basis.x doit avoir length=2.0 avant orthonormalization") \
		.is_equal_approx(2.0, 0.001)

	# Act — add_child → _ready → orthonormalize.
	add_child(_grunt)
	await get_tree().process_frame

	# Assert — global_basis orthonormalized (chaque axe length ≈ 1.0, orthogonal).
	var basis: Basis = pivot.global_basis
	assert_float(basis.x.length()) \
		.override_failure_message("AC-ENM-07c: basis.x.length() ≈ 1.0 post orthonormalize") \
		.is_equal_approx(1.0, 0.001)
	assert_float(basis.y.length()) \
		.override_failure_message("AC-ENM-07c: basis.y.length() ≈ 1.0") \
		.is_equal_approx(1.0, 0.001)
	assert_float(basis.z.length()) \
		.override_failure_message("AC-ENM-07c: basis.z.length() ≈ 1.0") \
		.is_equal_approx(1.0, 0.001)

	# Orthogonalité — produits scalaires nuls.
	assert_float(basis.x.dot(basis.y)) \
		.override_failure_message("AC-ENM-07c: basis.x ⊥ basis.y") \
		.is_equal_approx(0.0, 0.001)
	assert_float(basis.x.dot(basis.z)) \
		.override_failure_message("AC-ENM-07c: basis.x ⊥ basis.z") \
		.is_equal_approx(0.0, 0.001)
	assert_float(basis.y.dot(basis.z)) \
		.override_failure_message("AC-ENM-07c: basis.y ⊥ basis.z") \
		.is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------------------
# Bonus — basis IDENTITY déjà orthonormale reste IDENTITY
# ---------------------------------------------------------------------------

func test_facing_pivot_identity_basis_unchanged() -> void:
	var packed: PackedScene = load(GRUNT_SCENE_PATH) as PackedScene
	_grunt = packed.instantiate() as Grunt
	add_child(_grunt)
	await get_tree().process_frame

	var pivot: Node3D = _grunt.get_node("%FacingPivot") as Node3D
	var basis: Basis = pivot.global_basis
	# IDENTITY → orthonormalized() == IDENTITY.
	assert_vector(basis.x).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.001)
	assert_vector(basis.y).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
	assert_vector(basis.z).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)
