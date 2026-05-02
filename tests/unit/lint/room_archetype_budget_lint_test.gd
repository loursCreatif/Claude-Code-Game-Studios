# Tests unitaires story-012 — LevelLint.validate_room_archetype_invariants().
# Couvre :
#   AC-LVL-55 : Budget perf par archetype (R-4 r2) — pour chaque Room_NN selon
#               archetype, count DC + StaticBody3D + Area3D + Marker3D ≤ budgets.
#   AC-LVL-55 : SHAFT archetype requires ≥1 VerticalShaftRoom primitive instance.
#   AC-LVL-55 : Aggregate Σ DC_salle + LEVEL_OVERHEAD (=20) ≤ 350 (GDD F2).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Chaque test charge sa propre fixture — aucun état partagé.
#
# Story : production/epics/level-system/story-012-packed-scene-primitives-archetype-budgets.md
# Req   : AC-LVL-55
# GDD   : R-4 r2 (APPROVED r3), F2
# ADR   : ADR-0011 D-13 (budgets per-archetype enforcement)

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Charge une fixture .tscn depuis tests/fixtures/level/room_archetype_budgets/,
## l'instancie en Node3D et la retourne prête pour le lint.
## Échoue le test si le chargement est impossible.
func _load_fixture(filename: String) -> Node3D:
	var full_path: String = "res://tests/fixtures/level/room_archetype_budgets/" + filename
	var packed: PackedScene = load(full_path) as PackedScene
	assert_object(packed) \
		.override_failure_message("Fixture introuvable : " + full_path) \
		.is_not_null()
	var instance: Node = packed.instantiate()
	var root_3d: Node3D = instance as Node3D
	assert_object(root_3d) \
		.override_failure_message("La racine de la fixture n'est pas Node3D : " + full_path) \
		.is_not_null()
	add_child(auto_free(root_3d))
	return root_3d


# ---------------------------------------------------------------------------
# AC-LVL-55 — PASS : TRAVERSAL room dans tous les budgets
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetype_invariants() retourne [] quand un Room
## TRAVERSAL respecte tous les budgets (15 MI / 12 SB / 3 A / 8 M ≤ 22/18/4/10).
func test_traversal_room_within_budget() -> void:
	# Arrange
	var root: Node3D = _load_fixture("room_traversal_within_budget.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetype_invariants(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-55: aucune violation attendue pour TRAVERSAL within budget. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-55 — FAIL : TRAVERSAL DC excède budget (22)
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetype_invariants() signale une violation DC
## quand TRAVERSAL count = 25 > budget 22.
func test_traversal_room_exceeds_dc_budget() -> void:
	# Arrange
	var root: Node3D = _load_fixture("room_traversal_exceeds_dc.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetype_invariants(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-55: violation DC TRAVERSAL attendue mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "Room_01 TRAVERSAL DC=25 exceeds budget 22 (+3)"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-55: message DC TRAVERSAL '%s' absent. Erreurs reçues : %s" % [expected_msg, str(errors)]
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-55 — FAIL : COMBAT StaticBody3D excède budget (32)
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetype_invariants() signale une violation
## StaticBody3D quand COMBAT count = 35 > budget 32.
func test_combat_room_exceeds_sb3d_budget() -> void:
	# Arrange
	var root: Node3D = _load_fixture("room_combat_exceeds_sb3d.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetype_invariants(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-55: violation StaticBody3D COMBAT attendue mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "Room_01 COMBAT StaticBody3D=35 exceeds budget 32 (+3)"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-55: message StaticBody3D COMBAT '%s' absent. Erreurs reçues : %s" % [expected_msg, str(errors)]
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-55 — FAIL : SHAFT room sans primitive VerticalShaftRoom
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetype_invariants() signale qu'une salle SHAFT
## doit contenir au moins une instance VerticalShaftRoom* en enfant direct.
func test_shaft_room_requires_vertical_shaft_room_primitive() -> void:
	# Arrange
	var root: Node3D = _load_fixture("room_shaft_missing_primitive.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetype_invariants(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-55: violation SHAFT primitive obligatoire attendue mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "Room_01 SHAFT archetype requires >=1 VerticalShaftRoom primitive instance"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-55: message SHAFT primitive '%s' absent. Erreurs reçues : %s" % [expected_msg, str(errors)]
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-55 — FAIL : aggregate DC + LEVEL_OVERHEAD excède cap 350 (F2)
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetype_invariants() signale le dépassement
## agrégé : 10 rooms × 34 MI = 340 DC ; 340 + 20 = 360 > cap 350.
## Aucune violation per-room (34 ≤ 38 budget COMBAT).
func test_aggregate_dc_exceeds_formula2_cap() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_aggregate_dc_exceeds.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetype_invariants(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-55: violation aggregate attendue mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "aggregate DC 340 + LEVEL_OVERHEAD 20 = 360 exceeds cap 350"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-55: message aggregate '%s' absent. Erreurs reçues : %s" % [expected_msg, str(errors)]
		) \
		.is_true()


## Vérifie que validate_room_archetype_invariants() ne signale PAS de violation
## quand l'aggregate reste sous le cap : 10 × 31 MI = 310 ; 310 + 20 = 330 ≤ 350.
## Ce test garantit la borne exclusive du cap (côté ≤).
func test_aggregate_dc_within_limit() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_aggregate_dc_within.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetype_invariants(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-55: aucune violation attendue pour aggregate within (330 ≤ 350). Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-55 — Vérification table R4_BUDGETS exact GDD R-4 r2
# ---------------------------------------------------------------------------

## Vérifie que la const R4_BUDGETS contient exactement les 16 valeurs (4 archetypes
## × 4 metrics) attendues par le GDD R-4 r2.
## Garantit que le code source ne dérive pas du GDD sans mise à jour explicite.
func test_all_archetype_budget_tables_correct() -> void:
	# Arrange
	var budgets: Dictionary = LevelLint.R4_BUDGETS

	# Act + Assert — TRAVERSAL
	assert_int(budgets[LevelLint.ARCHETYPE_TRAVERSAL]["dc"]) \
		.override_failure_message("R4_BUDGETS[TRAVERSAL][dc] mismatch") \
		.is_equal(22)
	assert_int(budgets[LevelLint.ARCHETYPE_TRAVERSAL]["sb3d"]) \
		.override_failure_message("R4_BUDGETS[TRAVERSAL][sb3d] mismatch") \
		.is_equal(18)
	assert_int(budgets[LevelLint.ARCHETYPE_TRAVERSAL]["area3d"]) \
		.override_failure_message("R4_BUDGETS[TRAVERSAL][area3d] mismatch") \
		.is_equal(4)
	assert_int(budgets[LevelLint.ARCHETYPE_TRAVERSAL]["marker3d"]) \
		.override_failure_message("R4_BUDGETS[TRAVERSAL][marker3d] mismatch") \
		.is_equal(10)

	# Act + Assert — COMBAT
	assert_int(budgets[LevelLint.ARCHETYPE_COMBAT]["dc"]) \
		.override_failure_message("R4_BUDGETS[COMBAT][dc] mismatch") \
		.is_equal(38)
	assert_int(budgets[LevelLint.ARCHETYPE_COMBAT]["sb3d"]) \
		.override_failure_message("R4_BUDGETS[COMBAT][sb3d] mismatch") \
		.is_equal(32)
	assert_int(budgets[LevelLint.ARCHETYPE_COMBAT]["area3d"]) \
		.override_failure_message("R4_BUDGETS[COMBAT][area3d] mismatch") \
		.is_equal(10)
	assert_int(budgets[LevelLint.ARCHETYPE_COMBAT]["marker3d"]) \
		.override_failure_message("R4_BUDGETS[COMBAT][marker3d] mismatch") \
		.is_equal(30)

	# Act + Assert — SHAFT
	assert_int(budgets[LevelLint.ARCHETYPE_SHAFT]["dc"]) \
		.override_failure_message("R4_BUDGETS[SHAFT][dc] mismatch") \
		.is_equal(32)
	assert_int(budgets[LevelLint.ARCHETYPE_SHAFT]["sb3d"]) \
		.override_failure_message("R4_BUDGETS[SHAFT][sb3d] mismatch") \
		.is_equal(28)
	assert_int(budgets[LevelLint.ARCHETYPE_SHAFT]["area3d"]) \
		.override_failure_message("R4_BUDGETS[SHAFT][area3d] mismatch") \
		.is_equal(6)
	assert_int(budgets[LevelLint.ARCHETYPE_SHAFT]["marker3d"]) \
		.override_failure_message("R4_BUDGETS[SHAFT][marker3d] mismatch") \
		.is_equal(18)

	# Act + Assert — SECRET_HUB
	assert_int(budgets[LevelLint.ARCHETYPE_SECRET_HUB]["dc"]) \
		.override_failure_message("R4_BUDGETS[SECRET_HUB][dc] mismatch") \
		.is_equal(34)
	assert_int(budgets[LevelLint.ARCHETYPE_SECRET_HUB]["sb3d"]) \
		.override_failure_message("R4_BUDGETS[SECRET_HUB][sb3d] mismatch") \
		.is_equal(25)
	assert_int(budgets[LevelLint.ARCHETYPE_SECRET_HUB]["area3d"]) \
		.override_failure_message("R4_BUDGETS[SECRET_HUB][area3d] mismatch") \
		.is_equal(12)
	assert_int(budgets[LevelLint.ARCHETYPE_SECRET_HUB]["marker3d"]) \
		.override_failure_message("R4_BUDGETS[SECRET_HUB][marker3d] mismatch") \
		.is_equal(24)

	# Vérifications complémentaires LEVEL_OVERHEAD + AGGREGATE_DC_CAP (constantes F2)
	assert_int(LevelLint.LEVEL_OVERHEAD) \
		.override_failure_message("LEVEL_OVERHEAD mismatch GDD F2") \
		.is_equal(20)
	assert_int(LevelLint.AGGREGATE_DC_CAP) \
		.override_failure_message("AGGREGATE_DC_CAP mismatch GDD F2") \
		.is_equal(350)
