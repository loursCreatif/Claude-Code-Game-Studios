# Tests unitaires story-011 — LevelLint.validate_room_archetypes().
# Couvre :
#   AC-LVL-52  : @export archetype obligatoire sur chaque Room_NN.
#   AC-LVL-52b : compat legacy room_type r1 avec auto-conversion + 0 violation.
#   AC-LVL-50a : S-1 — ≥ 3 archétypes distincts sur l'étage.
#   AC-LVL-50b : S-3 — ≥ 1 SHAFT présent.
#   AC-LVL-50c : S-5 — ≥ 1 SECRET_HUB présent.
#   AC-LVL-50d : S-2 — pas de COMBAT consécutifs.
#   AC-LVL-50e : S-4 — salle finale ∈ {SECRET_HUB, TRAVERSAL}.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Chaque test charge sa propre fixture — aucun état partagé.
#
# Story   : production/epics/level-system/story-011-room-archetype-enum-diversity-lint.md
# Req     : TR-lvl-016
# GDD     : R-2.6 r2 (APPROVED r3), S-1..S-5
# ADR     : N/A — GDD-owned R-2.6

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Charge une fixture .tscn depuis tests/fixtures/level/room_archetype/,
## l'instancie en Node3D et la retourne prête pour le lint.
## Échoue le test si le chargement est impossible.
func _load_fixture(filename: String) -> Node3D:
	var full_path: String = "res://tests/fixtures/level/room_archetype/" + filename
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
# AC-LVL-52 — FAIL : Room_NN sans script Room (pas de @export archetype)
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetypes() signale une violation pour Room_01
## qui n'a pas de script Room attaché (donc pas de propriété archetype).
## Fixture : Room_01 = Node3D sans script ; Room_02 = SHAFT ; Room_03 = SECRET_HUB.
func test_validate_room_archetype_fails_when_missing() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_missing_archetype.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetypes(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-52: violations attendues mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "Room_01 missing @export archetype"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-52: message '%s' absent. Erreurs reçues : %s" % [expected_msg, str(errors)]
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-52b — PASS avec warning : Room_01 a room_type_legacy au lieu d'archetype
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetypes() retourne [] (0 violation) quand Room_01
## utilise room_type_legacy = 0 (ARENA → COMBAT) à la place d'archetype.
## Le push_warning est attendu mais non testable automatiquement (observable en logs).
## Fixture : Room_01=legacy 0 ; Room_02=SHAFT ; Room_03=SECRET_HUB.
func test_validate_room_archetype_accepts_legacy_room_type_with_warning() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_legacy_room_type.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetypes(root)

	# Assert — 0 violation lint (le push_warning legacy est observable en logs uniquement)
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-52b: aucune violation attendue pour legacy room_type valide. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-50a — FAIL : diversité insuffisante (S-1, < 3 archétypes distincts)
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetypes() signale la violation S-1 quand
## toutes les salles partagent le même archétype (TRAVERSAL, 1 distinct < 3).
## Fixture : 5 × Room_NN archetype=TRAVERSAL.
func test_archetype_diversity_requires_3_distinct() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_archetype_low_diversity.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetypes(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-50a: violations S-1 attendues mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "insufficient archetype diversity: 1 distinct, required >= 3"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-50a: message S-1 '%s' absent. Erreurs reçues : %s" % [expected_msg, str(errors)]
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-50b/c — FAIL : SHAFT et SECRET_HUB absents (S-3 et S-5)
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetypes() signale l'absence de SHAFT et SECRET_HUB.
## Fixture : 5 × Room_NN archetype ∈ {TRAVERSAL, COMBAT} — ni SHAFT ni SECRET_HUB.
## Note : S-1 (diversity) échoue aussi dans cette fixture (2 distincts < 3).
## Ce test vérifie uniquement la présence des messages S-3 et S-5 attendus.
func test_archetype_requires_shaft_and_secret_hub_present() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_archetype_no_shaft_no_hub.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetypes(root)

	# Assert — présence des messages S-3 et S-5 (d'autres violations peuvent coexister)
	assert_array(errors) \
		.override_failure_message("AC-LVL-50b/c: violations S-3/S-5 attendues mais tableau vide") \
		.is_not_empty()

	var expected_shaft: String = "missing required archetype: SHAFT"
	assert_bool(errors.has(expected_shaft)) \
		.override_failure_message(
			"AC-LVL-50b: message S-3 '%s' absent. Erreurs reçues : %s" % [expected_shaft, str(errors)]
		) \
		.is_true()

	var expected_hub: String = "missing required archetype: SECRET_HUB"
	assert_bool(errors.has(expected_hub)) \
		.override_failure_message(
			"AC-LVL-50c: message S-5 '%s' absent. Erreurs reçues : %s" % [expected_hub, str(errors)]
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-50d — FAIL : COMBAT consécutifs (S-2)
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetypes() signale des salles COMBAT consécutives.
## Fixture : [TRAVERSAL, COMBAT, COMBAT, SHAFT, SECRET_HUB] — index 1 et 2 consécutifs.
## S-1 ✓ (4 distincts), S-3 ✓, S-4 ✓ (final=SECRET_HUB), S-5 ✓.
func test_no_consecutive_combat_rooms() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_archetype_consecutive_combat.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetypes(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-50d: violation S-2 attendue mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "consecutive COMBAT rooms at index 1 and 2"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-50d: message S-2 '%s' absent. Erreurs reçues : %s" % [expected_msg, str(errors)]
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-50e — FAIL : salle finale hors {SECRET_HUB, TRAVERSAL} (S-4)
# ---------------------------------------------------------------------------

## Vérifie que validate_room_archetypes() signale une salle finale de type COMBAT.
## Fixture : [TRAVERSAL, SHAFT, SECRET_HUB, TRAVERSAL, COMBAT] — final=COMBAT.
## S-1 ✓ (4 distincts), S-2 ✓, S-3 ✓, S-5 ✓.
func test_final_room_must_be_secret_hub_or_traversal() -> void:
	# Arrange
	var root: Node3D = _load_fixture("etage_archetype_final_combat.tscn")

	# Act
	var errors: Array[String] = LevelLint.validate_room_archetypes(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-50e: violation S-4 attendue mais tableau vide") \
		.is_not_empty()

	var expected_msg: String = "final room archetype must be SECRET_HUB or TRAVERSAL, got COMBAT"
	assert_bool(errors.has(expected_msg)) \
		.override_failure_message(
			"AC-LVL-50e: message S-4 '%s' absent. Erreurs reçues : %s" % [expected_msg, str(errors)]
		) \
		.is_true()
