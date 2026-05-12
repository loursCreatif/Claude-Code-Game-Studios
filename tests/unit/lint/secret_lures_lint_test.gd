# Tests unitaires story-018 — LevelLint.validate_secret_lures().
#
# Couvre :
#   AC-LVL-53 : Cohérence triplet Secret — pour chaque NN, les 3 sous-arbres
#               (SpawnMarkers, InteractiveVolumes, SpawnMarkers) doivent contenir
#               un élément NN ; required_ability doit être dans les valeurs valides.
#   AC-LVL-46 : Count ∈ [3, 5] ; ≥ 1 secret require wall_run ou wall_run_long.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures  : construites programmatiquement — aucun fichier .tscn requis.
#
# Story : production/epics/level-system/story-018-secret-split-contract-validate-lures.md
# Req   : AC-LVL-46, AC-LVL-53

extends GdUnitTestSuite

## preload de LevelLint : class_name non résolu en CI headless sans SceneTree complet.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")


# ---------------------------------------------------------------------------
# Helpers — construction des fixtures programmatiques
# ---------------------------------------------------------------------------

## Structure canonique d'une fixture de scène d'étage :
##   TestRoot (Node3D)
##   ├── StaticEnvironment (Node3D)
##   ├── InteractiveVolumes (Node3D)
##   ├── SpawnMarkers (Node3D)
##   └── EtageExitTrigger (Area3D)
##
## Retourne la racine (auto_free enregistré). Retourne aussi spawn_markers et
## interactive_volumes via les params [out].
func _make_root_with_subtrees(
	out_spawn: Array,
	out_volumes: Array
) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))

	var static_env: Node3D = Node3D.new()
	static_env.name = "StaticEnvironment"
	root.add_child(static_env)

	var interactive_volumes: Node3D = Node3D.new()
	interactive_volumes.name = "InteractiveVolumes"
	root.add_child(interactive_volumes)

	var spawn_markers: Node3D = Node3D.new()
	spawn_markers.name = "SpawnMarkers"
	root.add_child(spawn_markers)

	var exit_trigger: Area3D = Area3D.new()
	exit_trigger.name = "EtageExitTrigger"
	root.add_child(exit_trigger)

	out_spawn.append(spawn_markers)
	out_volumes.append(interactive_volumes)
	return root


## Ajoute un triplet complet (Lure + Volume + Anchor) avec l'ability donnée.
func _add_triplet(
	spawn_markers: Node3D,
	interactive_volumes: Node3D,
	idx: String,
	ability: StringName
) -> void:
	# SecretLureMarker extends Marker3D — instance doit être Marker3D pour set_script.
	var lure: Marker3D = Marker3D.new()
	lure.name = "SecretLureMarker_" + idx
	var lure_script: GDScript = preload("res://src/gameplay/level/secret_lure_marker.gd")
	lure.set_script(lure_script)
	lure.required_ability = ability
	spawn_markers.add_child(lure)

	var volume: Area3D = Area3D.new()
	volume.name = "SecretCollectVolume_" + idx
	interactive_volumes.add_child(volume)

	var anchor: Node3D = Node3D.new()
	anchor.name = "SecretAnchor_" + idx
	spawn_markers.add_child(anchor)


## Ajoute uniquement un SecretLureMarker_NN (Lure orphelin — pas de Volume ni Anchor).
func _add_orphan_lure(spawn_markers: Node3D, idx: String, ability: StringName) -> void:
	# SecretLureMarker extends Marker3D — instance doit être Marker3D pour set_script.
	var lure: Marker3D = Marker3D.new()
	lure.name = "SecretLureMarker_" + idx
	var lure_script: GDScript = preload("res://src/gameplay/level/secret_lure_marker.gd")
	lure.set_script(lure_script)
	lure.required_ability = ability
	spawn_markers.add_child(lure)


# ---------------------------------------------------------------------------
# AC-LVL-53 — FAIL : lure orphelin sans volume
# ---------------------------------------------------------------------------

## Vérifie que validate_secret_lures signale un SecretLureMarker_01 dont
## le SecretCollectVolume_01 est absent (lure orphelin côté volume).
## Source : story-018 AC-LVL-53.
func test_validate_secret_lures_fails_orphan_lure_without_volume() -> void:
	# Arrange — Lure_01 présent, Volume_01 absent, Anchor_01 présent
	var out_spawn: Array = []
	var out_volumes: Array = []
	var root: Node3D = _make_root_with_subtrees(out_spawn, out_volumes)
	var spawn_markers: Node3D = out_spawn[0]
	var interactive_volumes: Node3D = out_volumes[0]

	# Lure orphelin : pas de volume correspondant
	_add_orphan_lure(spawn_markers, "01", &"dash")
	# Anchor présent (pas d'orphan anchor violation)
	var anchor: Node3D = Node3D.new()
	anchor.name = "SecretAnchor_01"
	spawn_markers.add_child(anchor)
	# Pas de SecretCollectVolume_01

	# Ajouter 2 triplets complets pour remplir le minimum de count (évite false positive count < 3)
	_add_triplet(spawn_markers, interactive_volumes, "02", &"wall_run")
	_add_triplet(spawn_markers, interactive_volumes, "03", &"none")

	# Act
	var errors: Array[String] = LevelLintScript.validate_secret_lures(root)

	# Assert — doit contenir "missing SecretCollectVolume"
	var found: bool = false
	for e: String in errors:
		if "Secret tuple incomplete at index 01" in e and "missing SecretCollectVolume" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-53: violation 'Secret tuple incomplete at index 01 — missing SecretCollectVolume' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-53 — FAIL : volume orphelin sans lure (branche miroir orphan_lure)
# ---------------------------------------------------------------------------

## Vérifie que validate_secret_lures signale un SecretCollectVolume_NN dont
## le SecretLureMarker_NN correspondant est absent (orphelin côté volume).
## Couvre la branche lint validate_secret_lures lignes 838-843 (volume sans lure).
## Source : story-018 AC-LVL-53.
func test_validate_secret_lures_fails_orphan_volume_without_lure() -> void:
	# Arrange — Volume_99 isolé (pas de Lure_99 ni Anchor_99)
	# + 3 triplets complets pour satisfaire le count minimum.
	var out_spawn: Array = []
	var out_volumes: Array = []
	var root: Node3D = _make_root_with_subtrees(out_spawn, out_volumes)
	var spawn_markers: Node3D = out_spawn[0]
	var interactive_volumes: Node3D = out_volumes[0]

	_add_triplet(spawn_markers, interactive_volumes, "01", &"wall_run")
	_add_triplet(spawn_markers, interactive_volumes, "02", &"none")
	_add_triplet(spawn_markers, interactive_volumes, "03", &"dash")

	# Volume orphelin : pas de Lure ni Anchor correspondant
	var orphan_volume: Area3D = Area3D.new()
	orphan_volume.name = "SecretCollectVolume_99"
	interactive_volumes.add_child(orphan_volume)

	# Act
	var errors: Array[String] = LevelLintScript.validate_secret_lures(root)

	# Assert — doit contenir "SecretCollectVolume_99 orphan"
	var found: bool = false
	for e: String in errors:
		if "SecretCollectVolume_99 orphan" in e and "missing SecretLureMarker_99" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-53: violation 'SecretCollectVolume_99 orphan — missing SecretLureMarker_99' attendue. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-53 — FAIL : required_ability manquant (empty StringName)
# ---------------------------------------------------------------------------

## Vérifie que validate_secret_lures signale SecretLureMarker_02 dont
## required_ability est une StringName vide (annotation manquante).
## Source : story-018 AC-LVL-53.
func test_validate_secret_lures_fails_missing_required_ability() -> void:
	# Arrange — 3 triplets complets ; Lure_02 a required_ability = &"" (vide)
	var out_spawn: Array = []
	var out_volumes: Array = []
	var root: Node3D = _make_root_with_subtrees(out_spawn, out_volumes)
	var spawn_markers: Node3D = out_spawn[0]
	var interactive_volumes: Node3D = out_volumes[0]

	_add_triplet(spawn_markers, interactive_volumes, "01", &"wall_run")
	_add_triplet(spawn_markers, interactive_volumes, "02", &"")  # required_ability vide
	_add_triplet(spawn_markers, interactive_volumes, "03", &"none")

	# Act
	var errors: Array[String] = LevelLintScript.validate_secret_lures(root)

	# Assert — doit contenir le message exact pour Lure_02
	var found: bool = false
	for e: String in errors:
		if "SecretLureMarker_02 required_ability not in {none, dash, double_jump, wall_run, wall_run_long}" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-53: message 'SecretLureMarker_02 required_ability not in {...}' attendu. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-46 — count ∈ [3, 5] : 3 pass, 4 pass, 5 pass, 2 fail, 6 fail
# ---------------------------------------------------------------------------

## Vérifie les bornes du count de secrets : [3, 5] = PASS ; 2 = FAIL ; 6 = FAIL.
## Source : story-018 AC-LVL-46, GDD F7.
func test_secret_count_within_3_to_5() -> void:
	# Sous-test count = 3 (floor — PASS)
	var out_spawn_3: Array = []
	var out_volumes_3: Array = []
	var root_3: Node3D = _make_root_with_subtrees(out_spawn_3, out_volumes_3)
	for i: int in range(1, 4):
		var ability: StringName = &"wall_run" if i == 1 else &"none"
		_add_triplet(out_spawn_3[0], out_volumes_3[0], "%02d" % i, ability)
	var errors_3: Array[String] = LevelLintScript.validate_secret_lures(root_3)
	var count_violation_3: bool = false
	for e: String in errors_3:
		if "secret count" in e:
			count_violation_3 = true
	assert_bool(count_violation_3) \
		.override_failure_message("AC-LVL-46: 3 secrets = floor, aucune violation count attendue") \
		.is_false()

	# Sous-test count = 4 (nominal — PASS)
	var out_spawn_4: Array = []
	var out_volumes_4: Array = []
	var root_4: Node3D = _make_root_with_subtrees(out_spawn_4, out_volumes_4)
	for i: int in range(1, 5):
		var ability: StringName = &"wall_run" if i == 1 else &"none"
		_add_triplet(out_spawn_4[0], out_volumes_4[0], "%02d" % i, ability)
	var errors_4: Array[String] = LevelLintScript.validate_secret_lures(root_4)
	var count_violation_4: bool = false
	for e: String in errors_4:
		if "secret count" in e:
			count_violation_4 = true
	assert_bool(count_violation_4) \
		.override_failure_message("AC-LVL-46: 4 secrets = nominal, aucune violation count attendue") \
		.is_false()

	# Sous-test count = 5 (cap — PASS)
	var out_spawn_5: Array = []
	var out_volumes_5: Array = []
	var root_5: Node3D = _make_root_with_subtrees(out_spawn_5, out_volumes_5)
	for i: int in range(1, 6):
		var ability: StringName = &"wall_run" if i == 1 else &"none"
		_add_triplet(out_spawn_5[0], out_volumes_5[0], "%02d" % i, ability)
	var errors_5: Array[String] = LevelLintScript.validate_secret_lures(root_5)
	var count_violation_5: bool = false
	for e: String in errors_5:
		if "secret count" in e:
			count_violation_5 = true
	assert_bool(count_violation_5) \
		.override_failure_message("AC-LVL-46: 5 secrets = cap, aucune violation count attendue") \
		.is_false()

	# Sous-test count = 2 (< 3 — FAIL)
	var out_spawn_2: Array = []
	var out_volumes_2: Array = []
	var root_2: Node3D = _make_root_with_subtrees(out_spawn_2, out_volumes_2)
	for i: int in range(1, 3):
		_add_triplet(out_spawn_2[0], out_volumes_2[0], "%02d" % i, &"wall_run")
	var errors_2: Array[String] = LevelLintScript.validate_secret_lures(root_2)
	var found_under: bool = false
	for e: String in errors_2:
		if "secret count 2 < 3" in e:
			found_under = true
	assert_bool(found_under) \
		.override_failure_message(
			"AC-LVL-46: 2 secrets doit produire 'secret count 2 < 3'. Erreurs : %s" % str(errors_2)
		) \
		.is_true()

	# Sous-test count = 6 (> 5 — FAIL)
	var out_spawn_6: Array = []
	var out_volumes_6: Array = []
	var root_6: Node3D = _make_root_with_subtrees(out_spawn_6, out_volumes_6)
	for i: int in range(1, 7):
		var ability: StringName = &"wall_run" if i == 1 else &"none"
		_add_triplet(out_spawn_6[0], out_volumes_6[0], "%02d" % i, ability)
	var errors_6: Array[String] = LevelLintScript.validate_secret_lures(root_6)
	var found_over: bool = false
	for e: String in errors_6:
		if "secret count 6 > 5" in e:
			found_over = true
	assert_bool(found_over) \
		.override_failure_message(
			"AC-LVL-46: 6 secrets doit produire 'secret count 6 > 5'. Erreurs : %s" % str(errors_6)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-46 — contrainte économique : ≥ 1 wall_run ou wall_run_long
# ---------------------------------------------------------------------------

## Vérifie que validate_secret_lures signale l'absence de wall_run/wall_run_long
## quand tous les secrets ont required_ability=dash, et que la présence d'1 secret
## wall_run_long fait passer le check.
## Source : story-018 AC-LVL-46, GDD F7 pillar 4.
func test_at_least_one_secret_requires_wall_run() -> void:
	# Arrange — 4 triplets tous avec required_ability=dash (aucun wall_run)
	var out_spawn_fail: Array = []
	var out_volumes_fail: Array = []
	var root_fail: Node3D = _make_root_with_subtrees(out_spawn_fail, out_volumes_fail)
	for i: int in range(1, 5):
		_add_triplet(out_spawn_fail[0], out_volumes_fail[0], "%02d" % i, &"dash")

	# Act
	var errors_fail: Array[String] = LevelLintScript.validate_secret_lures(root_fail)

	# Assert — doit contenir la violation économique
	var found_constraint: bool = false
	for e: String in errors_fail:
		if "economic constraint: ≥ 1 secret must require wall_run or wall_run_long" in e:
			found_constraint = true
			break
	assert_bool(found_constraint) \
		.override_failure_message(
			"AC-LVL-46: violation économique attendue quand aucun wall_run. Erreurs : %s" % str(errors_fail)
		) \
		.is_true()

	# Arrange — 4 triplets, 1 avec wall_run_long (PASS)
	var out_spawn_pass: Array = []
	var out_volumes_pass: Array = []
	var root_pass: Node3D = _make_root_with_subtrees(out_spawn_pass, out_volumes_pass)
	_add_triplet(out_spawn_pass[0], out_volumes_pass[0], "01", &"dash")
	_add_triplet(out_spawn_pass[0], out_volumes_pass[0], "02", &"wall_run_long")
	_add_triplet(out_spawn_pass[0], out_volumes_pass[0], "03", &"none")
	_add_triplet(out_spawn_pass[0], out_volumes_pass[0], "04", &"double_jump")

	# Act
	var errors_pass: Array[String] = LevelLintScript.validate_secret_lures(root_pass)

	# Assert — aucune violation économique
	var found_violation: bool = false
	for e: String in errors_pass:
		if "economic constraint" in e:
			found_violation = true
			break
	assert_bool(found_violation) \
		.override_failure_message(
			"AC-LVL-46: aucune violation économique attendue avec 1 wall_run_long. Erreurs : %s" % str(errors_pass)
		) \
		.is_false()
