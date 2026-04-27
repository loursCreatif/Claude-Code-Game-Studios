# Tests unitaires story-021 — LevelLint.validate_checkpoint_pairs().
#
# Couvre :
#   AC-LVL-19 : Checkpoint pair coherence — chaque CheckpointVolume_NN doit avoir
#               un CheckpointAnchor_NN paired (même index), distance ≤ 10 m.
#               Volumes orphelins, anchors orphelins, distance > 10 m = violations.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures  : construites programmatiquement — aucun fichier .tscn requis.
# Chaque test configure sa propre fixture via add_child + auto_free.
#
# Story : production/epics/level-system/story-021-validate-checkpoint-anchors-ec7.md
# Req   : TR-lvl-020
# ADR   : ADR-0011

extends GdUnitTestSuite

## preload de LevelLint : class_name non résolu en CI headless sans SceneTree complet.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")


# ---------------------------------------------------------------------------
# Helpers — construction des fixtures programmatiques
# ---------------------------------------------------------------------------

## Crée un Node3D racine vide enregistré avec auto_free pour le nettoyage GdUnit4.
## [return] : Node3D racine prête à recevoir des enfants.
func _make_root() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))
	return root


## Crée un CheckpointVolume_NN Area3D à la position donnée et l'ajoute au root.
## [param idx]  : suffix zero-pad (ex. "01") — produit "CheckpointVolume_01".
## [param pos]  : global_position souhaitée.
## [param root] : Node3D parent.
## [return] : Area3D créé.
func _make_volume(idx: String, pos: Vector3, root: Node3D) -> Area3D:
	var area: Area3D = Area3D.new()
	area.name = "CheckpointVolume_" + idx
	area.position = pos
	root.add_child(area)
	return area


## Crée un CheckpointAnchor_NN Marker3D à la position donnée et l'ajoute au root.
## [param idx]  : suffix zero-pad (ex. "01") — produit "CheckpointAnchor_01".
## [param pos]  : global_position souhaitée.
## [param root] : Node3D parent.
## [return] : Marker3D créé.
func _make_anchor(idx: String, pos: Vector3, root: Node3D) -> Marker3D:
	var marker: Marker3D = Marker3D.new()
	marker.name = "CheckpointAnchor_" + idx
	marker.position = pos
	root.add_child(marker)
	return marker


# ---------------------------------------------------------------------------
# AC-LVL-19 — PASS : paire volume+anchor à distance ≤ 10m
# ---------------------------------------------------------------------------

## Vérifie que validate_checkpoint_pairs() retourne [] quand CheckpointVolume_01
## et CheckpointAnchor_01 sont présents et séparés de 5 m (≤ 10 m).
## Source : TR-lvl-020, story-021 AC-LVL-19.
func test_checkpoint_pair_within_10m_passes() -> void:
	# Arrange
	var root: Node3D = _make_root()
	_make_volume("01", Vector3(0.0, 0.0, 0.0), root)
	_make_anchor("01", Vector3(5.0, 0.0, 0.0), root)

	# Act
	var errors: Array[String] = LevelLintScript.validate_checkpoint_pairs(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-19: aucune violation attendue pour paire à 5 m. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-19 — FAIL : volume sans anchor
# ---------------------------------------------------------------------------

## Vérifie que validate_checkpoint_pairs() signale CheckpointVolume_01 dont
## l'anchor paired CheckpointAnchor_01 est absent.
## Source : TR-lvl-020, story-021 AC-LVL-19.
func test_checkpoint_volume_without_anchor_flagged() -> void:
	# Arrange
	var root: Node3D = _make_root()
	_make_volume("01", Vector3(0.0, 0.0, 0.0), root)
	# Pas d'anchor "01" — anchor orphelin intentionnellement absent

	# Act
	var errors: Array[String] = LevelLintScript.validate_checkpoint_pairs(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-19: violation 'missing paired CheckpointAnchor_01' attendue mais tableau vide"
		) \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "CheckpointVolume_01 missing paired CheckpointAnchor_01" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-19: message 'CheckpointVolume_01 missing paired CheckpointAnchor_01' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-19 — FAIL : anchor sans volume (orphan)
# ---------------------------------------------------------------------------

## Vérifie que validate_checkpoint_pairs() signale CheckpointAnchor_01 dont
## le volume paired CheckpointVolume_01 est absent.
## Source : TR-lvl-020, story-021 AC-LVL-19.
func test_checkpoint_anchor_without_volume_flagged() -> void:
	# Arrange
	var root: Node3D = _make_root()
	# Pas de volume "01" — anchor orpheline
	_make_anchor("01", Vector3(0.0, 0.0, 0.0), root)

	# Act
	var errors: Array[String] = LevelLintScript.validate_checkpoint_pairs(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-19: violation 'CheckpointAnchor_01 orphan' attendue mais tableau vide"
		) \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "CheckpointAnchor_01 orphan" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-19: message 'CheckpointAnchor_01 orphan' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-19 — FAIL : paire volume+anchor distance > 10m
# ---------------------------------------------------------------------------

## Vérifie que validate_checkpoint_pairs() signale la distance excessive (15 m > 10 m)
## entre CheckpointVolume_01 et CheckpointAnchor_01.
## Source : TR-lvl-020, story-021 AC-LVL-19.
func test_checkpoint_pair_distance_over_10m_flagged() -> void:
	# Arrange
	var root: Node3D = _make_root()
	_make_volume("01", Vector3(0.0, 0.0, 0.0), root)
	_make_anchor("01", Vector3(15.0, 0.0, 0.0), root)  # distance = 15 m > 10 m

	# Act
	var errors: Array[String] = LevelLintScript.validate_checkpoint_pairs(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-19: violation 'distance 15.00m > 10m' attendue mais tableau vide"
		) \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "distance 15.00m > 10m" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-19: message 'distance 15.00m > 10m' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()
