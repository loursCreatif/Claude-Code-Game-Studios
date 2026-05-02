# Tests unitaires story-020 — LevelLint.validate_level_formulas().
#
# Couvre :
#   AC-LVL-18 : PlayerStart unique (count == 1).
#   AC-LVL-20 : Room count [8, 10] (RoomTrigger_* Area3D).
#   AC-LVL-46 : Secret count [3, 5] (SecretCollectVolume_* Area3D, F7).
#   AC-LVL-47 : Checkpoint count cohérence (CheckpointVolume_* Area3D, F3).
#   AC-LVL-48 : Etage height [15, 60] m (F5).
#   AC-LVL-49 : WorldBoundsVolume encloses union + 3 m margin (F6).
#   AC-LVL-51 : Checkpoint spacing floor(N/K) ∈ [2, 3] (F3).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures  : construites programmatiquement — aucun fichier .tscn requis.
# Chaque test configure sa propre fixture via add_child + auto_free.
#
# Story : production/epics/level-system/story-020-formula-lints-aggregate.md
# Req   : TR-lvl-009, TR-lvl-012, TR-lvl-014, TR-lvl-015
# ADR   : ADR-0011 D-7, story-020 AC-LVL-18/20/46/47/48/49/51

extends GdUnitTestSuite

## preload de LevelLint : class_name non résolu en CI headless sans SceneTree complet.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")


# ---------------------------------------------------------------------------
# Helpers — construction des fixtures programmatiques
# ---------------------------------------------------------------------------

## Crée un Node3D racine minimal avec StaticEnvironment et InteractiveVolumes.
## Enregistre root avec auto_free pour nettoyage GdUnit4.
## [return] : Node3D racine attaché au SceneTree du test.
func _make_bare_root() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	var static_env: Node3D = Node3D.new()
	static_env.name = "StaticEnvironment"
	root.add_child(static_env)
	var interactive_vol: Node3D = Node3D.new()
	interactive_vol.name = "InteractiveVolumes"
	root.add_child(interactive_vol)
	add_child(auto_free(root))
	return root


## Crée la fixture canonique : N rooms, K checkpoints, 1 PlayerStart Marker3D,
## 1 EtageExitTrigger Area3D positionné à etage_height sur Y, et secret_count
## SecretCollectVolume_NN Area3D sous InteractiveVolumes.
##
## [param n] : nombre de RoomTrigger_NN Area3D créés.
## [param k] : nombre de CheckpointVolume_NN Area3D créés.
## [param with_player_start] : crée le Marker3D PlayerStart si true.
## [param with_exit] : crée l'Area3D EtageExitTrigger si true.
## [param secret_count] : nombre de SecretCollectVolume_NN Area3D créés.
## [param etage_height] : position Y de l'EtageExitTrigger (PlayerStart est à Y=0).
## [return] : Node3D racine attaché au SceneTree du test.
func _make_root_with_n_rooms_and_k_checkpoints(
	n: int,
	k: int,
	with_player_start: bool = true,
	with_exit: bool = true,
	secret_count: int = 4,
	etage_height: float = 30.0
) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"

	var static_env: Node3D = Node3D.new()
	static_env.name = "StaticEnvironment"
	root.add_child(static_env)

	var interactive_vol: Node3D = Node3D.new()
	interactive_vol.name = "InteractiveVolumes"
	root.add_child(interactive_vol)

	if with_player_start:
		var ps: Marker3D = Marker3D.new()
		ps.name = "PlayerStart"
		ps.position = Vector3(0.0, 0.0, 0.0)
		root.add_child(ps)

	if with_exit:
		var exit: Area3D = Area3D.new()
		exit.name = "EtageExitTrigger"
		exit.position = Vector3(0.0, etage_height, 0.0)
		root.add_child(exit)

	for i: int in range(n):
		var rt: Area3D = Area3D.new()
		rt.name = "RoomTrigger_%02d" % (i + 1)
		interactive_vol.add_child(rt)

	for i: int in range(k):
		var cv: Area3D = Area3D.new()
		cv.name = "CheckpointVolume_%02d" % (i + 1)
		interactive_vol.add_child(cv)

	for i: int in range(secret_count):
		var sv: Area3D = Area3D.new()
		sv.name = "SecretCollectVolume_%02d" % (i + 1)
		interactive_vol.add_child(sv)

	add_child(auto_free(root))
	return root


## Crée une fixture minimale pour tester uniquement le check WorldBoundsVolume F6.
## Un StaticBody3D avec BoxShape3D de taille static_size centré à l'origine,
## et un WorldBoundsVolume Area3D avec BoxShape3D de taille bounds_size centré à l'origine.
##
## [param static_size] : taille du BoxShape3D du StaticBody3D (full extent).
## [param bounds_size] : taille du BoxShape3D du WorldBoundsVolume (full extent).
## [return] : Node3D racine attaché au SceneTree du test.
func _make_minimal_root_with_world_bounds(static_size: Vector3, bounds_size: Vector3) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"

	# StaticBody3D avec BoxShape3D centré à l'origine.
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = "StaticEnv_Wall"
	sb.position = Vector3.ZERO
	var sb_cs: CollisionShape3D = CollisionShape3D.new()
	var sb_box: BoxShape3D = BoxShape3D.new()
	sb_box.size = static_size
	sb_cs.shape = sb_box
	sb.add_child(sb_cs)
	root.add_child(sb)

	# WorldBoundsVolume Area3D avec CollisionShape3D/BoxShape3D centré à l'origine.
	var wbv: Area3D = Area3D.new()
	wbv.name = "WorldBoundsVolume"
	wbv.position = Vector3.ZERO
	var wbv_cs: CollisionShape3D = CollisionShape3D.new()
	wbv_cs.name = "CollisionShape3D"
	var wbv_box: BoxShape3D = BoxShape3D.new()
	wbv_box.size = bounds_size
	wbv_cs.shape = wbv_box
	wbv.add_child(wbv_cs)
	root.add_child(wbv)

	add_child(auto_free(root))
	return root


# ---------------------------------------------------------------------------
# AC-LVL-18 — FAIL : PlayerStart count != 1
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() signale un count PlayerStart != 1
## quand 2 Marker3D "PlayerStart" sont présents sous root.
## Source : story-020 AC-LVL-18.
func test_level_lint_player_start_count_not_1_fails() -> void:
	# Arrange
	var root: Node3D = _make_bare_root()
	var ps1: Marker3D = Marker3D.new()
	ps1.name = "PlayerStart"
	root.add_child(ps1)
	var ps2: Marker3D = Marker3D.new()
	ps2.name = "PlayerStart"
	root.add_child(ps2)

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_formulas(root)

	# Assert — violation présente
	assert_array(errors) \
		.override_failure_message("AC-LVL-18: violation PlayerStart count != 1 attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "PlayerStart count 2 != 1" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-18: message 'PlayerStart count 2 != 1' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-20 — FAIL : Room count outside [8, 10]
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() signale un count de salles hors [8, 10].
## Sous-cas : N=7 fails, N=11 fails, N=9 passes.
## Source : story-020 AC-LVL-20.
func test_level_lint_room_count_outside_8_10_fails() -> void:
	# --- Sous-cas A : N=7 (< 8) → FAIL ---
	var root_7: Node3D = _make_root_with_n_rooms_and_k_checkpoints(7, 3)
	var errors_7: Array[String] = LevelLintScript.validate_level_formulas(root_7)

	assert_array(errors_7) \
		.override_failure_message("AC-LVL-20: violation Room count outside [8, 10] attendue pour N=7") \
		.is_not_empty()

	var found_7: bool = false
	for e: String in errors_7:
		if "Room count 7 outside [8, 10]" in e:
			found_7 = true
			break
	assert_bool(found_7) \
		.override_failure_message(
			"AC-LVL-20: message 'Room count 7 outside [8, 10]' absent. Erreurs : %s" % str(errors_7)
		) \
		.is_true()

	# --- Sous-cas B : N=11 (> 10) → FAIL ---
	var root_11: Node3D = _make_root_with_n_rooms_and_k_checkpoints(11, 4)
	var errors_11: Array[String] = LevelLintScript.validate_level_formulas(root_11)

	var found_11: bool = false
	for e: String in errors_11:
		if "Room count 11 outside [8, 10]" in e:
			found_11 = true
			break
	assert_bool(found_11) \
		.override_failure_message(
			"AC-LVL-20: message 'Room count 11 outside [8, 10]' absent. Erreurs : %s" % str(errors_11)
		) \
		.is_true()

	# --- Sous-cas C : N=9 (∈ [8, 10]) → PASS (aucune violation Room count) ---
	var root_9: Node3D = _make_root_with_n_rooms_and_k_checkpoints(9, 4)
	var errors_9: Array[String] = LevelLintScript.validate_level_formulas(root_9)

	var room_violation_9: bool = false
	for e: String in errors_9:
		if "Room count" in e and "outside [8, 10]" in e:
			room_violation_9 = true
			break
	assert_bool(room_violation_9) \
		.override_failure_message(
			"AC-LVL-20: aucune violation Room count attendue pour N=9. Erreurs : %s" % str(errors_9)
		) \
		.is_false()


# ---------------------------------------------------------------------------
# AC-LVL-51 + Spacing — PASS : N=10 K=4 → spacing=2 (conforme)
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() retourne [] pour la fixture canonique :
## N=10 rooms, K=4 checkpoints, 4 secrets, height=30 m, PlayerStart + EtageExit.
## floor(10/4) = 2 ∈ [2, 3] → PASS.
## Source : story-020 AC-LVL-51, F3.
func test_level_lint_checkpoint_spacing_passes_for_n10_k4() -> void:
	# Arrange — N=10, K=4, 4 secrets, height=30 conforme
	var root: Node3D = _make_root_with_n_rooms_and_k_checkpoints(
		10, 4, true, true, 4, 30.0
	)

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_formulas(root)

	# Assert — aucune violation attendue
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-51: aucune violation attendue pour N=10 K=4 height=30. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-51 — FAIL : K=0 (aucun checkpoint)
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() signale "K=0 fail"
## quand aucun CheckpointVolume_NN n'est présent.
## Source : story-020 AC-LVL-51, F3.
func test_level_lint_checkpoint_spacing_k_0_fails() -> void:
	# Arrange — N=8, K=0
	var root: Node3D = _make_root_with_n_rooms_and_k_checkpoints(8, 0)

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_formulas(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-51: violation K=0 fail attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "checkpoint spacing: K=0 fail" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-51: message 'checkpoint spacing: K=0 fail' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-51 — FAIL : K=1 avec N=9 (N >= 4)
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() signale "K=1 on N>=4 fail"
## quand K=1 et N=9 >= 4 (spacing >= 4 viole Pillar 3).
## Source : story-020 AC-LVL-51, F3.
func test_level_lint_checkpoint_spacing_k_1_on_n_9_fails() -> void:
	# Arrange — N=9, K=1
	var root: Node3D = _make_root_with_n_rooms_and_k_checkpoints(9, 1)

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_formulas(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-51: violation K=1 on N>=4 fail attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "K=1 on N>=4 fail" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-51: message 'K=1 on N>=4 fail' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-51 — FAIL : K==N (spacing=1, viole Pillar 1 FLOW)
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() signale "K==N fail"
## quand K==N=10 (un checkpoint par salle, spacing=1).
## Source : story-020 AC-LVL-51, F3.
func test_level_lint_checkpoint_spacing_k_equals_n_fails() -> void:
	# Arrange — N=10, K=10
	var root: Node3D = _make_root_with_n_rooms_and_k_checkpoints(10, 10)

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_formulas(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-51: violation K==N fail attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "K==N fail" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-51: message 'K==N fail' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-46 — FAIL : Secret count outside [3, 5]
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() signale un count de secrets hors [3, 5].
## Sous-cas : 2 fails, 6 fails, 4 passes.
## Source : story-020 AC-LVL-46, F7.
func test_level_lint_secret_count_outside_3_5_fails() -> void:
	# --- Sous-cas A : 2 secrets (< 3) → FAIL ---
	var root_2: Node3D = _make_root_with_n_rooms_and_k_checkpoints(
		10, 4, true, true, 2, 30.0
	)
	var errors_2: Array[String] = LevelLintScript.validate_level_formulas(root_2)

	assert_array(errors_2) \
		.override_failure_message("AC-LVL-46: violation Secret count outside [3, 5] (F7) attendue pour 2 secrets") \
		.is_not_empty()

	var found_2: bool = false
	for e: String in errors_2:
		if "Secret count 2 outside [3, 5] (F7)" in e:
			found_2 = true
			break
	assert_bool(found_2) \
		.override_failure_message(
			"AC-LVL-46: message 'Secret count 2 outside [3, 5] (F7)' absent. Erreurs : %s" % str(errors_2)
		) \
		.is_true()

	# --- Sous-cas B : 6 secrets (> 5) → FAIL ---
	var root_6: Node3D = _make_root_with_n_rooms_and_k_checkpoints(
		10, 4, true, true, 6, 30.0
	)
	var errors_6: Array[String] = LevelLintScript.validate_level_formulas(root_6)

	var found_6: bool = false
	for e: String in errors_6:
		if "Secret count 6 outside [3, 5] (F7)" in e:
			found_6 = true
			break
	assert_bool(found_6) \
		.override_failure_message(
			"AC-LVL-46: message 'Secret count 6 outside [3, 5] (F7)' absent. Erreurs : %s" % str(errors_6)
		) \
		.is_true()

	# --- Sous-cas C : 4 secrets (∈ [3, 5]) → PASS (aucune violation Secret count) ---
	var root_4: Node3D = _make_root_with_n_rooms_and_k_checkpoints(
		10, 4, true, true, 4, 30.0
	)
	var errors_4: Array[String] = LevelLintScript.validate_level_formulas(root_4)

	var secret_violation_4: bool = false
	for e: String in errors_4:
		if "Secret count" in e and "outside [3, 5]" in e:
			secret_violation_4 = true
			break
	assert_bool(secret_violation_4) \
		.override_failure_message(
			"AC-LVL-46: aucune violation Secret count attendue pour 4 secrets. Erreurs : %s" % str(errors_4)
		) \
		.is_false()


# ---------------------------------------------------------------------------
# AC-LVL-48 — FAIL : Etage height outside [15, 60] m
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() signale une hauteur d'étage hors [15, 60] m.
## Sous-cas : y=10 fails (< 15), y=70 fails (> 60), y=30 passes.
## Source : story-020 AC-LVL-48, F5.
func test_level_lint_etage_height_outside_15_60_fails() -> void:
	# --- Sous-cas A : height=10 m (< 15 m) → FAIL ---
	var root_10: Node3D = _make_root_with_n_rooms_and_k_checkpoints(
		10, 4, true, true, 4, 10.0
	)
	var errors_10: Array[String] = LevelLintScript.validate_level_formulas(root_10)

	assert_array(errors_10) \
		.override_failure_message("AC-LVL-48: violation etage height outside [15, 60]m (F5) attendue pour y=10") \
		.is_not_empty()

	var found_10: bool = false
	for e: String in errors_10:
		if "etage height 10.00m outside [15, 60]m (F5)" in e:
			found_10 = true
			break
	assert_bool(found_10) \
		.override_failure_message(
			"AC-LVL-48: message 'etage height 10.00m outside [15, 60]m (F5)' absent. Erreurs : %s" % str(errors_10)
		) \
		.is_true()

	# --- Sous-cas B : height=70 m (> 60 m) → FAIL ---
	var root_70: Node3D = _make_root_with_n_rooms_and_k_checkpoints(
		10, 4, true, true, 4, 70.0
	)
	var errors_70: Array[String] = LevelLintScript.validate_level_formulas(root_70)

	var found_70: bool = false
	for e: String in errors_70:
		if "etage height 70.00m outside [15, 60]m (F5)" in e:
			found_70 = true
			break
	assert_bool(found_70) \
		.override_failure_message(
			"AC-LVL-48: message 'etage height 70.00m outside [15, 60]m (F5)' absent. Erreurs : %s" % str(errors_70)
		) \
		.is_true()

	# --- Sous-cas C : height=30 m (∈ [15, 60]) → PASS (aucune violation etage height) ---
	var root_30: Node3D = _make_root_with_n_rooms_and_k_checkpoints(
		10, 4, true, true, 4, 30.0
	)
	var errors_30: Array[String] = LevelLintScript.validate_level_formulas(root_30)

	var height_violation_30: bool = false
	for e: String in errors_30:
		if "etage height" in e and "outside [15, 60]m" in e:
			height_violation_30 = true
			break
	assert_bool(height_violation_30) \
		.override_failure_message(
			"AC-LVL-48: aucune violation etage height attendue pour y=30. Erreurs : %s" % str(errors_30)
		) \
		.is_false()


# ---------------------------------------------------------------------------
# AC-LVL-49 — Deux assertions : PASS marge 3 m / FAIL marge < 3 m
# ---------------------------------------------------------------------------

## Vérifie AC-LVL-49 (F6) dans deux scenarios :
##
## Setup A (PASS) : StaticBody3D BoxShape3D size=(20,7,20) centré à l'origine.
##   AABB statique = [-10,-3.5,-10] → [10,3.5,10].
##   Union AABB = idem. required = union.grow(3) = [-13,-6.5,-13] → [13,6.5,13].
##   WorldBoundsVolume BoxShape3D size=(26,14,26) centré à l'origine.
##   bounds_aabb = [-13,-7,-13] → [13,7,13] → encloses required → PASS F6.
##
## Setup B (FAIL) : StaticBody3D identique.
##   WorldBoundsVolume BoxShape3D size=(25,14,26) centré à l'origine.
##   bounds_aabb = [-12.5,-7,-13] → [12.5,7,13] → ne contient pas [-13,-6.5,-13] → FAIL F6.
##
## Source : story-020 AC-LVL-49, F6.
func test_level_lint_worldbounds_encloses_static_union_with_3m_margin() -> void:
	# --- Setup A : PASS — bounds 26x14x26, static 20x7x20 → margin 3 exact ---
	var root_pass: Node3D = _make_minimal_root_with_world_bounds(
		Vector3(20.0, 7.0, 20.0),
		Vector3(26.0, 14.0, 26.0)
	)

	var errors_all_pass: Array[String] = LevelLintScript.validate_level_formulas(root_pass)

	# Filtrer uniquement les erreurs F6 (les autres checks peuvent violer sur cette fixture minimale).
	var f6_errors_pass: Array[String] = []
	for e: String in errors_all_pass:
		if "WorldBoundsVolume" in e:
			f6_errors_pass.append(e)

	assert_array(f6_errors_pass) \
		.override_failure_message(
			"AC-LVL-49 Setup A: aucune violation F6 attendue avec bounds 26x14x26. Violations F6 : "
			+ ", ".join(f6_errors_pass)
		) \
		.is_empty()

	# --- Setup B : FAIL — bounds 25x14x26, margin x = 2.5 < 3 ---
	var root_fail: Node3D = _make_minimal_root_with_world_bounds(
		Vector3(20.0, 7.0, 20.0),
		Vector3(25.0, 14.0, 26.0)
	)

	var errors_all_fail: Array[String] = LevelLintScript.validate_level_formulas(root_fail)

	# Filtrer uniquement les erreurs F6.
	var f6_errors_fail: Array[String] = []
	for e: String in errors_all_fail:
		if "WorldBoundsVolume" in e:
			f6_errors_fail.append(e)

	assert_array(f6_errors_fail) \
		.override_failure_message(
			"AC-LVL-49 Setup B: violation F6 attendue avec bounds 25x14x26 (margin x=2.5 < 3)"
		) \
		.is_not_empty()

	var found_fail: bool = false
	for e: String in f6_errors_fail:
		if "WorldBoundsVolume does not enclose union + 3m margin (F6)" in e:
			found_fail = true
			break
	assert_bool(found_fail) \
		.override_failure_message(
			"AC-LVL-49 Setup B: message 'WorldBoundsVolume does not enclose union + 3m margin (F6)' absent. Erreurs F6 : %s" % str(f6_errors_fail)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-18 — FAIL : PlayerStart count == 0 (cas authoring le plus fréquent)
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() signale "PlayerStart count 0 != 1"
## quand aucun Marker3D "PlayerStart" n'est présent sous root.
## Couvre le sous-cas count=0 distinct du count=2 testé ci-dessus.
## Source : story-020 AC-LVL-18 (review-fix GAP-1).
func test_level_lint_player_start_count_0_fails() -> void:
	# Arrange — root sans aucun PlayerStart
	var root: Node3D = _make_bare_root()

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_formulas(root)

	# Assert — violation count=0 présente
	var found: bool = false
	for e: String in errors:
		if "PlayerStart count 0 != 1" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-18: message 'PlayerStart count 0 != 1' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-48 — Silent skip : PlayerStart absent → aucune violation F5
# ---------------------------------------------------------------------------

## Vérifie que validate_level_formulas() ne lève PAS de violation F5 (etage
## height) quand PlayerStart est absent. La règle F5 est gardée par les autres
## lints (count == 1) ; un faux positif F5 ici masquerait la cause réelle.
## Source : story-020 AC-LVL-48 implémentation l. 988-995 (review-fix GAP-2).
func test_level_lint_etage_height_skip_silently_when_player_start_absent() -> void:
	# Arrange — fixture sans PlayerStart, EtageExitTrigger présent à y=70 (hors plage)
	var root: Node3D = _make_root_with_n_rooms_and_k_checkpoints(
		10, 4, false, true, 4, 70.0
	)

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_formulas(root)

	# Assert — aucune erreur F5 émise (skip silencieux), même si y=70 serait hors [15,60]
	var f5_violation: bool = false
	for e: String in errors:
		if "etage height" in e and "outside [15, 60]m" in e:
			f5_violation = true
			break
	assert_bool(f5_violation) \
		.override_failure_message(
			"AC-LVL-48: aucune violation F5 attendue quand PlayerStart absent (skip silencieux). Erreurs : %s" % str(errors)
		) \
		.is_false()
