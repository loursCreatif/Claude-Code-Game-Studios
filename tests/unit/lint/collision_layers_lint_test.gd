# Tests unitaires story-013 — LevelLint.validate_collision_layers(),
# validate_wall_thickness() et validate_level_shapes().
#
# Couvre :
#   AC-LVL-12 : Layer 4 exclusive for static geometry (StaticBody3D sous
#               StaticEnvironment — layer LAYER_ENVIRONMENT actif, mask == 0).
#   AC-LVL-13 : Layer 5 exclusive for interactive triggers (Area3D sous
#               InteractiveVolumes — layer LAYER_INTERACTIVE, monitorable=false,
#               monitoring=true, mask ⊃ LAYER_PLAYER).
#   AC-LVL-17 : Minimal wall thickness ≥ 0.3 m (BoxShape3D min(x, z) ≥ 0.3).
#   validate_level_shapes : WorldBoundsVolume must use BoxShape3D only.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures  : construites programmatiquement — aucun fichier .tscn requis.
# Chaque test configure sa propre fixture via add_child + auto_free.
#
# Story : production/epics/level-system/story-013-collision-layers-validate-shapes.md
# Req   : TR-lvl-007, TR-lvl-008, TR-lvl-019
# ADR   : ADR-0008 D-1/D-2/D-3, ADR-0001 (Jolt CCD)

extends GdUnitTestSuite

## preload de LevelLint : class_name non résolu en CI headless sans SceneTree complet.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")

## preload de CollisionLayers : class_name non résolu en CI headless.
## Fournit LAYER_PLAYER (1), LAYER_ENVIRONMENT (4), LAYER_INTERACTIVE (5).
const CollisionLayersScript: GDScript = preload("res://src/core/collision_layers.gd")


# ---------------------------------------------------------------------------
# Helpers — construction des fixtures programmatiques
# ---------------------------------------------------------------------------

## Crée un Node3D racine avec StaticEnvironment et InteractiveVolumes comme
## enfants directs. Enregistre root avec auto_free pour nettoyage GdUnit4.
## [return] : [root, static_env, interactive_vol]
func _make_root_with_hierarchy() -> Array[Node3D]:
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"

	var static_env: Node3D = Node3D.new()
	static_env.name = "StaticEnvironment"
	root.add_child(static_env)

	var interactive_vol: Node3D = Node3D.new()
	interactive_vol.name = "InteractiveVolumes"
	root.add_child(interactive_vol)

	add_child(auto_free(root))
	return [root, static_env, interactive_vol]


## Crée un StaticBody3D correctement configuré pour AC-LVL-12 :
## layer LAYER_ENVIRONMENT actif, collision_mask == 0.
func _make_compliant_static_body() -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.collision_layer = 0  # réinitialisation explicite avant set per-bit
	sb.set_collision_layer_value(CollisionLayersScript.LAYER_ENVIRONMENT, true)
	sb.collision_mask = 0
	return sb


## Crée un Area3D correctement configuré pour AC-LVL-13 :
## layer LAYER_INTERACTIVE, monitorable=false, monitoring=true, mask ⊃ LAYER_PLAYER.
func _make_compliant_area() -> Area3D:
	var a: Area3D = Area3D.new()
	a.collision_layer = 0
	a.set_collision_layer_value(CollisionLayersScript.LAYER_INTERACTIVE, true)
	a.collision_mask = 0
	a.set_collision_mask_value(CollisionLayersScript.LAYER_PLAYER, true)
	a.monitorable = false
	a.monitoring = true
	return a


# ---------------------------------------------------------------------------
# AC-LVL-12 — PASS : StaticBody3D layer 4 + mask 0
# ---------------------------------------------------------------------------

## Vérifie que validate_collision_layers() retourne [] quand un StaticBody3D
## sous StaticEnvironment a le layer LAYER_ENVIRONMENT (4) et collision_mask == 0.
## Source : ADR-0008 D-2, story-013 AC-LVL-12.
func test_static_body_on_layer_4_with_zero_mask_passes() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	var sb: StaticBody3D = _make_compliant_static_body()
	static_env.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_collision_layers(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-12: aucune violation attendue pour StaticBody3D layer 4 mask 0. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-12 — FAIL : StaticBody3D sans layer 4
# ---------------------------------------------------------------------------

## Vérifie que validate_collision_layers() signale un StaticBody3D sous
## StaticEnvironment qui n'a pas le layer LAYER_ENVIRONMENT (4).
## Source : ADR-0008 D-2, story-013 AC-LVL-12.
func test_static_body_missing_layer_4_flagged() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	var sb: StaticBody3D = StaticBody3D.new()
	# Layer 1 par défaut — LAYER_ENVIRONMENT (4) non activé
	sb.set_collision_layer_value(CollisionLayersScript.LAYER_PLAYER, true)
	sb.collision_mask = 0
	static_env.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_collision_layers(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-12: violation 'missing layer 4' attendue mais tableau vide") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "missing layer 4" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-12: message contenant 'missing layer 4' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-12 — FAIL : StaticBody3D avec mask non nul
# ---------------------------------------------------------------------------

## Vérifie que validate_collision_layers() signale un StaticBody3D sous
## StaticEnvironment dont collision_mask est non nul (doit être 0).
## Source : ADR-0008 D-2, story-013 AC-LVL-12.
func test_static_body_with_nonzero_mask_flagged() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	var sb: StaticBody3D = StaticBody3D.new()
	sb.collision_layer = 0
	sb.set_collision_layer_value(CollisionLayersScript.LAYER_ENVIRONMENT, true)
	# Violation : mask non nul
	sb.set_collision_mask_value(CollisionLayersScript.LAYER_PLAYER, true)
	sb.set_collision_mask_value(CollisionLayersScript.LAYER_ENEMY, true)
	sb.set_collision_mask_value(CollisionLayersScript.LAYER_ENEMY_HITBOX, true)
	# mask résultant = layers 1+2+3 actifs = valeur 7
	static_env.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_collision_layers(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-12: violation 'collision_mask must be 0, got 7' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "collision_mask must be 0, got 7" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-12: message 'collision_mask must be 0, got 7' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-13 — PASS : Area3D layer 5, monitoring correct, mask LAYER_PLAYER
# ---------------------------------------------------------------------------

## Vérifie que validate_collision_layers() retourne [] quand un Area3D sous
## InteractiveVolumes est entièrement conforme : layer 5, monitorable=false,
## monitoring=true, mask ⊃ LAYER_PLAYER.
## Source : ADR-0008 D-2, story-013 AC-LVL-13.
func test_interactive_area_layer_5_monitoring_correct_passes() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	var a: Area3D = _make_compliant_area()
	interactive_vol.add_child(a)

	# Act
	var errors: Array[String] = LevelLintScript.validate_collision_layers(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-13: aucune violation attendue pour Area3D conforme. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-13 — FAIL : Area3D sans layer 5
# ---------------------------------------------------------------------------

## Vérifie que validate_collision_layers() signale un Area3D sous
## InteractiveVolumes qui n'a pas le layer LAYER_INTERACTIVE (5).
## Source : ADR-0008 D-2, story-013 AC-LVL-13.
func test_interactive_area_missing_layer_5_flagged() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	var a: Area3D = Area3D.new()
	a.collision_layer = 0
	# Layer 5 (LAYER_INTERACTIVE) NON activé
	a.set_collision_mask_value(CollisionLayersScript.LAYER_PLAYER, true)
	a.monitorable = false
	a.monitoring = true
	interactive_vol.add_child(a)

	# Act
	var errors: Array[String] = LevelLintScript.validate_collision_layers(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-13: violation 'missing layer 5' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "missing layer 5" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-13: message contenant 'missing layer 5' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-13 — FAIL : Area3D monitorable == true
# ---------------------------------------------------------------------------

## Vérifie que validate_collision_layers() signale un Area3D dont monitorable=true.
## Les triggers interactifs doivent être signal-only (monitorable=false).
## Source : ADR-0008 D-2, story-013 AC-LVL-13.
func test_interactive_area_monitorable_true_flagged() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	var a: Area3D = _make_compliant_area()
	a.monitorable = true  # Violation
	interactive_vol.add_child(a)

	# Act
	var errors: Array[String] = LevelLintScript.validate_collision_layers(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-13: violation 'monitorable must be false' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "monitorable must be false" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-13: message 'monitorable must be false' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-13 — FAIL : Area3D monitoring == false
# ---------------------------------------------------------------------------

## Vérifie que validate_collision_layers() signale un Area3D dont monitoring=false.
## Les triggers interactifs doivent détecter les corps entrants (monitoring=true).
## Source : ADR-0008 D-2, story-013 AC-LVL-13.
func test_interactive_area_monitoring_false_flagged() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	var a: Area3D = _make_compliant_area()
	a.monitoring = false  # Violation
	interactive_vol.add_child(a)

	# Act
	var errors: Array[String] = LevelLintScript.validate_collision_layers(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-13: violation 'monitoring must be true' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "monitoring must be true" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-13: message 'monitoring must be true' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-13 — FAIL : Area3D mask ne comprend pas LAYER_PLAYER
# ---------------------------------------------------------------------------

## Vérifie que validate_collision_layers() signale un Area3D dont le
## collision_mask n'inclut pas LAYER_PLAYER (1).
## Source : ADR-0008 D-2, story-013 AC-LVL-13.
func test_interactive_area_mask_missing_player_flagged() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	var a: Area3D = Area3D.new()
	a.collision_layer = 0
	a.set_collision_layer_value(CollisionLayersScript.LAYER_INTERACTIVE, true)
	a.collision_mask = 0  # LAYER_PLAYER absent du mask
	a.monitorable = false
	a.monitoring = true
	interactive_vol.add_child(a)

	# Act
	var errors: Array[String] = LevelLintScript.validate_collision_layers(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-13: violation 'must include LAYER_PLAYER' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "must include LAYER_PLAYER" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-13: message 'must include LAYER_PLAYER' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-17 — PASS : BoxShape3D thickness == 0.3m
# ---------------------------------------------------------------------------

## Vérifie que validate_wall_thickness() retourne [] quand un BoxShape3D a
## min(size.x, size.z) == 0.3 m (valeur limite acceptée).
## Source : TR-lvl-019, ADR-0001 (Jolt CCD), story-013 AC-LVL-17.
func test_wall_thickness_0_3m_passes() -> void:
	# Arrange
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))

	var sb: StaticBody3D = StaticBody3D.new()
	root.add_child(sb)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(3.0, 4.0, 0.3)  # min(3.0, 0.3) = 0.3 — PASS exact boundary
	cs.shape = box
	sb.add_child(cs)

	# Act
	var errors: Array[String] = LevelLintScript.validate_wall_thickness(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-17: aucune violation attendue pour thickness 0.3m. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-17 — FAIL : BoxShape3D thickness < 0.3m
# ---------------------------------------------------------------------------

## Vérifie que validate_wall_thickness() signale un BoxShape3D dont
## min(size.x, size.z) < 0.3 m.
## Source : TR-lvl-019, ADR-0001 (Jolt CCD), story-013 AC-LVL-17.
func test_wall_thickness_below_0_3m_flagged() -> void:
	# Arrange
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))

	var sb: StaticBody3D = StaticBody3D.new()
	root.add_child(sb)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(3.0, 4.0, 0.25)  # min(3.0, 0.25) = 0.25 — FAIL
	cs.shape = box
	sb.add_child(cs)

	# Act
	var errors: Array[String] = LevelLintScript.validate_wall_thickness(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-17: violation 'thickness 0.25m < 0.3m' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "thickness 0.25m < 0.3m" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-17: message contenant 'thickness 0.25m < 0.3m' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# validate_level_shapes — PASS : WorldBoundsVolume avec BoxShape3D
# ---------------------------------------------------------------------------

## Vérifie que validate_level_shapes() retourne [] quand un WorldBoundsVolume
## utilise une BoxShape3D comme shape de CollisionShape3D.
## Source : TR-lvl-019, story-013 / story-008.
func test_world_bounds_volume_box_shape_passes() -> void:
	# Arrange
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))

	var wbv: Area3D = Area3D.new()
	wbv.name = "WorldBoundsVolume"
	root.add_child(wbv)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(100.0, 50.0, 100.0)
	cs.shape = box
	wbv.add_child(cs)

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_shapes(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"validate_level_shapes: aucune violation attendue pour WorldBoundsVolume BoxShape3D. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# validate_level_shapes — FAIL : WorldBoundsVolume avec ConcavePolygonShape3D
# ---------------------------------------------------------------------------

## Vérifie que validate_level_shapes() signale un WorldBoundsVolume qui utilise
## ConcavePolygonShape3D au lieu de BoxShape3D.
## Source : TR-lvl-019, ADR-0001 (Jolt), story-013 / story-008.
func test_world_bounds_volume_concave_shape_flagged() -> void:
	# Arrange
	var root: Node3D = Node3D.new()
	root.name = "EtageTest"
	add_child(auto_free(root))

	var wbv: Area3D = Area3D.new()
	wbv.name = "WorldBoundsVolume"
	root.add_child(wbv)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var concave: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	cs.shape = concave
	wbv.add_child(cs)

	# Act
	var errors: Array[String] = LevelLintScript.validate_level_shapes(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("validate_level_shapes: violation 'must use BoxShape3D' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "must use BoxShape3D" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"validate_level_shapes: message 'must use BoxShape3D' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()
