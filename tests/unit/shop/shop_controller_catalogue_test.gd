# Unit test Story-002 — ShopController catalogue + cost formula F-CRD-3 0-based.
# Couvre size invariant + _compute_cost(0/1/-1/99) edge cases.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic.
# Note : load via path (pas class_name direct) — `.godot/global_script_class_cache.cfg`
# CLI-headless ne résout pas les nouveaux class_name avant ouverture éditeur.
extends GdUnitTestSuite

const _EXPECTED_COST_N0: int = 8     # F-CRD-3 r2 B-2 : BASE_UPGRADE_COST=8, cost(0) = 8 + 20×0 = 8
const _EXPECTED_COST_N1: int = 28    # F-CRD-3 r2 B-2 : cost(1) = 8 + 20×1 = 28
const _ShopControllerScript: GDScript = preload("res://src/ui/shop/shop_controller.gd")


# =============================================================================
# Catalogue size invariant — N_UPGRADES_MVP coherent avec _CATALOG.size()
# =============================================================================

## GIVEN ShopControllerScript instance,
## WHEN inspecting constants,
## THEN _CATALOG.size() == N_UPGRADES_MVP == 2.
func test_shop_controller_catalogue_size_matches_n_upgrades_mvp() -> void:
	# Arrange
	var s: Control = _ShopControllerScript.new()

	# Act + Assert
	assert_int(s._CATALOG.size()) \
		.override_failure_message("_CATALOG.size() != N_UPGRADES_MVP — invariant rompu") \
		.is_equal(s.N_UPGRADES_MVP)
	assert_int(s.N_UPGRADES_MVP) \
		.override_failure_message("N_UPGRADES_MVP doit être 2 (Tier 1 MVP)") \
		.is_equal(2)

	# Cleanup
	s.free()


# =============================================================================
# Catalogue payload exact — entries id/display_name/n_index spec story-002
# =============================================================================

## GIVEN ShopControllerScript instance,
## WHEN inspecting _CATALOG entries,
## THEN entry 0 = double_jump n_index=0, entry 1 = dash_horizontal n_index=1.
func test_shop_controller_catalogue_payload_double_jump_dash_horizontal() -> void:
	# Arrange
	var s: Control = _ShopControllerScript.new()

	# Act
	var entry_0: Dictionary = s._CATALOG[0]
	var entry_1: Dictionary = s._CATALOG[1]

	# Assert
	assert_object(entry_0["id"]) \
		.override_failure_message("Entry 0 id != double_jump") \
		.is_equal(&"double_jump")
	assert_int(entry_0["n_index"]) \
		.override_failure_message("Entry 0 n_index != 0") \
		.is_equal(0)
	assert_object(entry_1["id"]) \
		.override_failure_message("Entry 1 id != dash_horizontal") \
		.is_equal(&"dash_horizontal")
	assert_int(entry_1["n_index"]) \
		.override_failure_message("Entry 1 n_index != 1") \
		.is_equal(1)

	# Cleanup
	s.free()


# =============================================================================
# _compute_cost(0) → 8 (F-CRD-3 r2 B-2 : BASE_UPGRADE_COST=8, cost_0 = B = 8)
# =============================================================================

func test_shop_controller_compute_cost_n_zero_returns_base_20() -> void:
	# Arrange
	var s: Control = _ShopControllerScript.new()

	# Act
	var cost: int = s._compute_cost(0)

	# Assert
	assert_int(cost) \
		.override_failure_message("F-CRD-3 cost(0) attendu %d, obtenu %d" % [_EXPECTED_COST_N0, cost]) \
		.is_equal(_EXPECTED_COST_N0)

	# Cleanup
	s.free()


# =============================================================================
# _compute_cost(1) → 28 (F-CRD-3 r2 B-2 : cost_1 = 8 + 20×1 = 28)
# =============================================================================

func test_shop_controller_compute_cost_n_one_returns_base_plus_step_40() -> void:
	# Arrange
	var s: Control = _ShopControllerScript.new()

	# Act
	var cost: int = s._compute_cost(1)

	# Assert
	assert_int(cost) \
		.override_failure_message("F-CRD-3 cost(1) attendu %d, obtenu %d" % [_EXPECTED_COST_N1, cost]) \
		.is_equal(_EXPECTED_COST_N1)

	# Cleanup
	s.free()


# =============================================================================
# _compute_cost(-1) → 0 + push_warning (F-SHP-1 EC negative input)
# =============================================================================

## GIVEN ShopControllerScript instance,
## WHEN _compute_cost(-1),
## THEN return 0 (warning émis stderr, pas capturable GdUnit4 mais retour fait foi).
func test_shop_controller_compute_cost_negative_n_returns_zero_with_warning() -> void:
	# Arrange
	var s: Control = _ShopControllerScript.new()

	# Act
	var cost: int = s._compute_cost(-1)

	# Assert
	assert_int(cost) \
		.override_failure_message("F-SHP-1 EC negative n: cost(-1) doit retourner 0, obtenu %d" % cost) \
		.is_equal(0)

	# Cleanup
	s.free()


# =============================================================================
# _compute_cost(99) → 0 + push_error (n >= MAX_UPGRADE_INDEX = N_UPGRADES_MVP)
# =============================================================================

## GIVEN ShopControllerScript instance,
## WHEN _compute_cost(99),
## THEN return 0 (error émis stderr, pas capturable GdUnit4 mais retour fait foi).
func test_shop_controller_compute_cost_oob_n_returns_zero_with_error() -> void:
	# Arrange
	var s: Control = _ShopControllerScript.new()

	# Act
	var cost: int = s._compute_cost(99)

	# Assert
	assert_int(cost) \
		.override_failure_message("F-SHP-1 EC OOB n: cost(99) doit retourner 0, obtenu %d" % cost) \
		.is_equal(0)

	# Cleanup
	s.free()


# =============================================================================
# Boundary edge case — _compute_cost(N_UPGRADES_MVP=2) doit aussi rejeter
# =============================================================================

## GIVEN ShopControllerScript instance,
## WHEN _compute_cost(2) (== N_UPGRADES_MVP, premier index OOB),
## THEN return 0 (frontière >= MAX_UPGRADE_INDEX).
func test_shop_controller_compute_cost_n_at_boundary_returns_zero() -> void:
	# Arrange
	var s: Control = _ShopControllerScript.new()

	# Act — n == N_UPGRADES_MVP est première valeur OOB (max valid index = N-1 = 1)
	var cost: int = s._compute_cost(s.N_UPGRADES_MVP)

	# Assert
	assert_int(cost) \
		.override_failure_message("Boundary cost(N_UPGRADES_MVP=2) doit retourner 0 (>= MAX_UPGRADE_INDEX), obtenu %d" % cost) \
		.is_equal(0)

	# Cleanup
	s.free()
