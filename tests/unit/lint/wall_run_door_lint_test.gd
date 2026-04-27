# Tests unitaires story-014 — LevelLint.validate_door_widths(),
# validate_wall_run_surfaces() et validate_static_body_count_per_room().
#
# Couvre :
#   AC-LVL-14 : Door width F1 — RoomTrigger_NN Area3D avec meta is_doorway=true,
#               max(size.x, size.z) >= 3.6 m.
#   AC-LVL-15 : Wall-run surface F8 — StaticBody3D avec meta wall_run_enabled=true,
#               size.y >= 4.0 m, max(size.x, size.z) >= 3.0 m, orientation <= 5°.
#   TR-lvl-013 : StaticBody3D count per Room_NN <= 25 (plafond global).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures  : construites programmatiquement — aucun fichier .tscn requis.
# Chaque test configure sa propre fixture via add_child + auto_free.
#
# Story : production/epics/level-system/story-014-wall-run-surface-door-width-ccd-bench.md
# Req   : TR-lvl-011, TR-lvl-013, TR-lvl-039
# ADR   : ADR-0001 (Jolt CCD), story-014 AC-LVL-14/AC-LVL-15

extends GdUnitTestSuite

## preload de LevelLint : class_name non résolu en CI headless sans SceneTree complet.
const LevelLintScript: GDScript = preload("res://tools/lint/level_lint.gd")


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


## Crée un RoomTrigger_NN Area3D avec meta is_doorway=true et un BoxShape3D
## de la taille spécifiée. Retourne l'Area3D non encore attaché.
## [param trigger_name] : ex. "RoomTrigger_03"
## [param box_size] : full extent du BoxShape3D
func _make_doorway_trigger(trigger_name: String, box_size: Vector3) -> Area3D:
	var area: Area3D = Area3D.new()
	area.name = trigger_name
	area.set_meta("is_doorway", true)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = box_size
	cs.shape = box
	area.add_child(cs)
	return area


## Crée un StaticBody3D avec meta wall_run_enabled=true, un BoxShape3D et
## une transform. Retourne le StaticBody3D non encore attaché.
## [param body_name] : nom du StaticBody3D
## [param box_size] : full extent du BoxShape3D
## [param basis] : orientation du StaticBody3D (Basis.IDENTITY = vertical conforme)
func _make_wall_run_body(body_name: String, box_size: Vector3, basis: Basis) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = body_name
	sb.set_meta("wall_run_enabled", true)
	sb.transform = Transform3D(basis, Vector3.ZERO)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = box_size
	cs.shape = box
	sb.add_child(cs)
	return sb


# ---------------------------------------------------------------------------
# AC-LVL-14 — FAIL : door width < 3.6 m
# ---------------------------------------------------------------------------

## Vérifie que validate_door_widths() signale un RoomTrigger avec is_doorway=true
## dont max(size.x, size.z) = 3.0 m < 3.6 m.
## Source : GDD Formula 1, story-014 AC-LVL-14.
func test_validate_door_widths_below_3_6m_fails() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	# size=(3.0, 3.5, 1.0) → max(3.0, 1.0) = 3.0 < 3.6 — FAIL.
	var area: Area3D = _make_doorway_trigger("RoomTrigger_03", Vector3(3.0, 3.5, 1.0))
	interactive_vol.add_child(area)

	# Act
	var errors: Array[String] = LevelLintScript.validate_door_widths(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-14: violation door width < 3.6m attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "RoomTrigger_03" in e and "door width" in e and "3.6m (F1)" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-14: message 'RoomTrigger_03 door width ... < 3.6m (F1)' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-14 — PASS : door width == 3.6 m (boundary)
# ---------------------------------------------------------------------------

## Vérifie que validate_door_widths() retourne [] quand max(size.x, size.z) == 3.6 m.
## Source : GDD Formula 1, story-014 AC-LVL-14.
func test_validate_door_widths_at_3_6m_passes() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	# size=(3.6, 3.5, 1.0) → max(3.6, 1.0) = 3.6 — boundary exact.
	var area: Area3D = _make_doorway_trigger("RoomTrigger_03", Vector3(3.6, 3.5, 1.0))
	interactive_vol.add_child(area)

	# Act
	var errors: Array[String] = LevelLintScript.validate_door_widths(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-14: aucune violation attendue pour door width 3.6m. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-14 — PASS : RoomTrigger sans opt-in is_doorway → skippé
# ---------------------------------------------------------------------------

## Vérifie que validate_door_widths() ignore les RoomTrigger_NN dont is_doorway=false,
## même si le BoxShape3D est plus étroit que 3.6 m (opt-in obligatoire).
## Source : story-014 AC-LVL-14.
func test_validate_door_widths_skips_trigger_without_opt_in() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	# is_doorway=false → doit être ignoré même si size très étroit.
	var area: Area3D = Area3D.new()
	area.name = "RoomTrigger_05"
	area.set_meta("is_doorway", false)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.0, 3.5, 1.0)
	cs.shape = box
	area.add_child(cs)
	interactive_vol.add_child(area)

	# Act
	var errors: Array[String] = LevelLintScript.validate_door_widths(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-14: aucune violation attendue pour RoomTrigger sans opt-in is_doorway. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-14 — FAIL : RoomTrigger is_doorway=true sans BoxShape3D
# ---------------------------------------------------------------------------

## Vérifie que validate_door_widths() signale un faux négatif silencieux :
## un RoomTrigger marqué is_doorway=true mais sans BoxShape3D (CapsuleShape3D
## ou aucun shape) — la largeur est non vérifiable, le designer doit corriger.
## Source : qa-tester review story-014, story-014 AC-LVL-14 (faux négatif).
func test_validate_door_widths_doorway_without_boxshape_fails() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var interactive_vol: Node3D = nodes[2]

	# RoomTrigger is_doorway=true avec un CapsuleShape3D au lieu de BoxShape3D.
	var area: Area3D = Area3D.new()
	area.name = "RoomTrigger_07"
	area.set_meta("is_doorway", true)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = CapsuleShape3D.new()
	area.add_child(cs)
	interactive_vol.add_child(area)

	# Act
	var errors: Array[String] = LevelLintScript.validate_door_widths(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-14: violation 'doorway sans BoxShape3D' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "RoomTrigger_07" in e and "no BoxShape3D" in e and "(F1)" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-14: message 'RoomTrigger_07 ... no BoxShape3D ... (F1)' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-15 — FAIL : wall-run height < 4.0 m
# ---------------------------------------------------------------------------

## Vérifie que validate_wall_run_surfaces() signale un mur wall_run_enabled=true
## dont size.y = 3.8 m < 4.0 m (hauteur insuffisante).
## Source : GDD Formula 8, story-014 AC-LVL-15.
func test_validate_wall_run_surfaces_height_below_4m_fails() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	# size=(0.3, 3.8, 5.0) → height=3.8 < 4.0 (FAIL), length=5.0 >= 3.0 (PASS).
	var sb: StaticBody3D = _make_wall_run_body("WallRun_A", Vector3(0.3, 3.8, 5.0), Basis.IDENTITY)
	static_env.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_wall_run_surfaces(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-15: violation height < 4.0m attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "WallRun_A" in e and "height" in e and "< 4.0m (F8)" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-15: message 'Wall WallRun_A height ... < 4.0m (F8)' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-15 — FAIL : wall-run length < 3.0 m
# ---------------------------------------------------------------------------

## Vérifie que validate_wall_run_surfaces() signale un mur wall_run_enabled=true
## dont max(size.x, size.z) = 2.5 m < 3.0 m (longueur insuffisante).
## Source : GDD Formula 8, story-014 AC-LVL-15.
func test_validate_wall_run_surfaces_length_below_3m_fails() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	# size=(0.3, 4.5, 2.5) → height=4.5 >= 4.0 (PASS), length=max(0.3,2.5)=2.5 < 3.0 (FAIL).
	var sb: StaticBody3D = _make_wall_run_body("WallRun_B", Vector3(0.3, 4.5, 2.5), Basis.IDENTITY)
	static_env.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_wall_run_surfaces(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-15: violation length < 3.0m attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "WallRun_B" in e and "length" in e and "< 3.0m (F8)" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-15: message 'Wall WallRun_B length ... < 3.0m (F8)' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-15 — FAIL : wall-run orientation > 5°
# ---------------------------------------------------------------------------

## Vérifie que validate_wall_run_surfaces() signale un mur wall_run_enabled=true
## dont transform.basis.y s'écarte de Vector3.UP de 10° > 5°.
## Source : GDD Formula 8, story-014 AC-LVL-15.
func test_validate_wall_run_surfaces_orientation_beyond_5deg_fails() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	# Rotation de 10° autour de Vector3.FORWARD → basis.y dévie de 10° par rapport à UP.
	var tilted_basis: Basis = Basis(Vector3.FORWARD, deg_to_rad(10.0))
	# size conforme pour height et length.
	var sb: StaticBody3D = _make_wall_run_body("WallRun_C", Vector3(0.3, 4.5, 5.0), tilted_basis)
	static_env.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_wall_run_surfaces(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-15: violation orientation > 5° attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "WallRun_C" in e and "orientation deviation > 5°" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-15: message 'Wall WallRun_C orientation deviation > 5° (F8)' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# AC-LVL-15 — PASS : surface wall-run conforme (height 4.0 + length 3.0 + 0° tilt)
# ---------------------------------------------------------------------------

## Vérifie que validate_wall_run_surfaces() retourne [] pour un mur conforme :
## size.y == 4.0, max(size.x, size.z) == 3.0, orientation == 0°.
## Source : GDD Formula 8, story-014 AC-LVL-15.
func test_validate_wall_run_surfaces_compliant_passes() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	# size=(0.3, 4.0, 3.0) → height=4.0 == MIN, length=3.0 == MIN, basis=IDENTITY (0°).
	var sb: StaticBody3D = _make_wall_run_body("WallRun_OK", Vector3(0.3, 4.0, 3.0), Basis.IDENTITY)
	static_env.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_wall_run_surfaces(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"AC-LVL-15: aucune violation attendue pour surface wall-run conforme. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-LVL-15 — FAIL : wall_run_enabled=true sans BoxShape3D
# ---------------------------------------------------------------------------

## Vérifie que validate_wall_run_surfaces() signale un faux négatif silencieux :
## un StaticBody3D marqué wall_run_enabled=true mais sans BoxShape3D enfant
## (height/length non vérifiables — le designer doit corriger).
## Source : qa-tester review story-014, story-014 AC-LVL-15 (faux négatif).
func test_validate_wall_run_surfaces_no_boxshape_fails() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	# StaticBody3D wall_run_enabled=true avec un SphereShape3D au lieu de BoxShape3D.
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = "WallRun_NoBox"
	sb.set_meta("wall_run_enabled", true)
	sb.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = SphereShape3D.new()
	sb.add_child(cs)
	static_env.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_wall_run_surfaces(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("AC-LVL-15: violation 'wall_run sans BoxShape3D' attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "WallRun_NoBox" in e and "no BoxShape3D" in e and "(F8)" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"AC-LVL-15: message 'Wall WallRun_NoBox ... no BoxShape3D ... (F8)' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# TR-lvl-013 — FAIL : StaticBody3D count > 25 par Room_NN
# ---------------------------------------------------------------------------

## Vérifie que validate_static_body_count_per_room() signale une Room_NN
## contenant 30 StaticBody3D > MAX_STATIC_BODIES_PER_ROOM (25).
## Source : TR-lvl-013, story-014.
func test_validate_static_body_count_per_room_count_30_exceeds_cap_fails() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	var room: Node3D = Node3D.new()
	room.name = "Room_01"
	static_env.add_child(room)

	for i: int in range(30):
		var sb: StaticBody3D = StaticBody3D.new()
		sb.name = "Wall_%02d" % i
		room.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_static_body_count_per_room(root)

	# Assert
	assert_array(errors) \
		.override_failure_message("TR-lvl-013: violation StaticBody3D count 30 > 25 attendue") \
		.is_not_empty()

	var found: bool = false
	for e: String in errors:
		if "Room_01" in e and "30" in e and "25 (TR-lvl-013)" in e:
			found = true
			break
	assert_bool(found) \
		.override_failure_message(
			"TR-lvl-013: message 'Room_01 StaticBody3D count 30 > 25 (TR-lvl-013)' absent. Erreurs : %s" % str(errors)
		) \
		.is_true()


# ---------------------------------------------------------------------------
# TR-lvl-013 — PASS : StaticBody3D count == 25 (boundary)
# ---------------------------------------------------------------------------

## Vérifie que validate_static_body_count_per_room() retourne [] pour une Room_NN
## contenant exactement 25 StaticBody3D (valeur limite acceptée).
## Source : TR-lvl-013, story-014.
func test_validate_static_body_count_per_room_at_25_passes() -> void:
	# Arrange
	var nodes: Array[Node3D] = _make_root_with_hierarchy()
	var root: Node3D = nodes[0]
	var static_env: Node3D = nodes[1]

	var room: Node3D = Node3D.new()
	room.name = "Room_02"
	static_env.add_child(room)

	for i: int in range(25):
		var sb: StaticBody3D = StaticBody3D.new()
		sb.name = "Wall_%02d" % i
		room.add_child(sb)

	# Act
	var errors: Array[String] = LevelLintScript.validate_static_body_count_per_room(root)

	# Assert
	assert_array(errors) \
		.override_failure_message(
			"TR-lvl-013: aucune violation attendue pour count == 25. Violations : "
			+ ", ".join(errors)
		) \
		.is_empty()
