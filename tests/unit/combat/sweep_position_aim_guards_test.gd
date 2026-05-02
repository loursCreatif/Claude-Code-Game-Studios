# Tests unitaires Story-007 — CombatSystem sweep position + aim_forward consumption + guards.
#
# Couvre AC-1 à AC-6 (cf. story-007) :
#   AC-1 : forme close yaw=0/pitch=0 → Vector3(0,0,-1) ± 0.001 (vérifié indirectement
#          via la lecture aim_forward du mock dans AC-2).
#   AC-2 : ShapeCast3D origin = player.global_position + aim × KATANA_REACH/2.
#   AC-3 : roll-corrected wall-run → testé en intégration (DEFERRED — pas dans cette unit suite).
#   AC-4 : guard `Vector3.ZERO` → swing ignoré, _state reste IDLE.
#   AC-5 : guard NaN/inf → swing ignoré, _state reste IDLE.
#   AC-6 : forbidden grep `camera.basis.z` / `player.transform.basis.z` / `.global_transform.basis.z`.
#
# Pattern test : MockCameraSystem (RefCounted-like Node) avec property `aim_forward`
# settable depuis le test. Attaché en sibling sous le parent Player du Combat.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-007-sweep-position-aim-forward-guards.md
# ADR     : ADR-0002 D-2 (aim_forward read-only roll-corrigé), ADR-0006 D-7
# GDD     : design/gdd/player-combat-system.md AC-CMB-15/16/26/27/48

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const COMBAT_DIR: String = "res://src/gameplay/combat/"


# ---------------------------------------------------------------------------
# Mock CameraSystem
# ---------------------------------------------------------------------------

## Node3D minimal exposant `aim_forward: Vector3` settable.
## Sibling de CombatSystem sous le parent Player pour que `_resolve_camera_system`
## le trouve via `get_parent().get_node_or_null("CameraArm")`.
class MockCameraSystem extends Node3D:
	var aim_forward: Vector3 = Vector3(0.0, 0.0, -1.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un Player parent (CharacterBody3D) avec un MockCameraSystem nommé "CameraArm"
## et le CombatSystem instancié en sibling. Retourne (combat, mock_camera).
##
## Ordre d'attachement critique : CameraArm doit être ajoutée AVANT le CombatSystem
## pour que `_ready()` de Combat puisse la trouver via `get_parent().get_node_or_null`.
func _make_combat_with_mock_camera() -> Array:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)

	var mock_cam: MockCameraSystem = MockCameraSystem.new()
	mock_cam.name = "CameraArm"
	player.add_child(mock_cam)

	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)

	return [combat, mock_cam]


# ---------------------------------------------------------------------------
# AC-2 — Sweep position formula (player + aim × REACH/2)
# ---------------------------------------------------------------------------

## AC-2 : `player.global_position = Vector3(0, 1.8, 0)`, `aim = Vector3(0, 0, -1)` →
## ShapeCast3D origin = `Vector3(0, 1.8, -0.9)` (= 0 + (-1) × 1.8/2).
func test_combat_sweep_origin_equals_player_pos_plus_aim_times_half_reach() -> void:
	var pair: Array = _make_combat_with_mock_camera()
	var combat: CombatSystem = pair[0]
	var mock_cam: MockCameraSystem = pair[1]

	var player: CharacterBody3D = combat.get_parent() as CharacterBody3D
	player.global_position = Vector3(0.0, 1.8, 0.0)
	mock_cam.aim_forward = Vector3(0.0, 0.0, -1.0)

	# Act — déclencher swing via test seam direct
	combat.attacked()

	# Assert — ShapeCast3D positionnée
	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	var expected_origin: Vector3 = Vector3(0.0, 1.8, -CombatSystem.KATANA_REACH / 2.0)
	assert_vector(sc.global_transform.origin) \
		.override_failure_message(
			"AC-2: ShapeCast3D origin doit être player + aim × REACH/2 = %s — reçu %s"
			% [str(expected_origin), str(sc.global_transform.origin)]
		) \
		.is_equal_approx(expected_origin, Vector3.ONE * 0.001)

	player.queue_free()


## AC-2 cardinal +X : `aim = Vector3(1, 0, 0)`, player @ origin → origin = (REACH/2, 0, 0).
func test_combat_sweep_origin_cardinal_x_aim() -> void:
	var pair: Array = _make_combat_with_mock_camera()
	var combat: CombatSystem = pair[0]
	var mock_cam: MockCameraSystem = pair[1]

	combat.get_parent().global_position = Vector3.ZERO
	mock_cam.aim_forward = Vector3(1.0, 0.0, 0.0)

	combat.attacked()

	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	var expected: Vector3 = Vector3(CombatSystem.KATANA_REACH / 2.0, 0.0, 0.0)
	assert_vector(sc.global_transform.origin) \
		.override_failure_message(
			"AC-2 cardinal +X: origin doit être (%.2f, 0, 0) — reçu %s"
			% [CombatSystem.KATANA_REACH / 2.0, str(sc.global_transform.origin)]
		) \
		.is_equal_approx(expected, Vector3.ONE * 0.001)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-4 — Zero aim guard (swing ignoré)
# ---------------------------------------------------------------------------

## AC-4 : `aim_forward = Vector3.ZERO` → swing ignoré silencieusement.
##  - `_state` reste IDLE
##  - `_cooldown_timer` reste 0 (le joueur peut ré-essayer immédiatement)
##  - `ShapeCast3D.enabled` reste false
func test_combat_swing_ignored_when_aim_is_zero() -> void:
	var pair: Array = _make_combat_with_mock_camera()
	var combat: CombatSystem = pair[0]
	var mock_cam: MockCameraSystem = pair[1]

	mock_cam.aim_forward = Vector3.ZERO

	# Act — tenter un swing
	combat.attacked()

	# Assert
	assert_int(combat._state) \
		.override_failure_message("AC-4: _state doit rester IDLE quand aim est ZERO") \
		.is_equal(CombatSystem.State.IDLE)
	assert_float(combat._cooldown_timer) \
		.override_failure_message("AC-4: cooldown ne doit PAS être armé sur swing ignoré") \
		.is_equal(0.0)
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_bool(sc.enabled) \
		.override_failure_message("AC-4: ShapeCast3D.enabled doit rester false") \
		.is_false()

	combat.get_parent().queue_free()


## AC-4 quasi-zéro : `aim ≈ Vector3(0.0001, 0, 0)` — encore considéré ZERO par
## `is_zero_approx()` (tolérance interne Godot ~0.00001), donc swing ignoré.
func test_combat_swing_ignored_when_aim_is_quasi_zero() -> void:
	var pair: Array = _make_combat_with_mock_camera()
	var combat: CombatSystem = pair[0]
	var mock_cam: MockCameraSystem = pair[1]

	# Vector3 dont chaque composante est < CMP_EPSILON (1e-5 dans Godot 4).
	mock_cam.aim_forward = Vector3(1e-7, 1e-7, 1e-7)

	combat.attacked()

	assert_int(combat._state) \
		.override_failure_message("AC-4 quasi-zéro: _state doit rester IDLE") \
		.is_equal(CombatSystem.State.IDLE)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-5 — NaN/inf guard
# ---------------------------------------------------------------------------

## AC-5 : `aim = Vector3(NaN, 0, NaN)` → swing ignoré.
func test_combat_swing_ignored_when_aim_contains_nan() -> void:
	var pair: Array = _make_combat_with_mock_camera()
	var combat: CombatSystem = pair[0]
	var mock_cam: MockCameraSystem = pair[1]

	var nan: float = NAN
	mock_cam.aim_forward = Vector3(nan, 0.0, nan)

	combat.attacked()

	assert_int(combat._state) \
		.override_failure_message("AC-5 NaN: _state doit rester IDLE") \
		.is_equal(CombatSystem.State.IDLE)

	combat.get_parent().queue_free()


## AC-5 inf : `aim = Vector3(INF, 0, 0)` → swing ignoré.
func test_combat_swing_ignored_when_aim_contains_inf() -> void:
	var pair: Array = _make_combat_with_mock_camera()
	var combat: CombatSystem = pair[0]
	var mock_cam: MockCameraSystem = pair[1]

	mock_cam.aim_forward = Vector3(INF, 0.0, 0.0)

	combat.attacked()

	assert_int(combat._state) \
		.override_failure_message("AC-5 inf: _state doit rester IDLE") \
		.is_equal(CombatSystem.State.IDLE)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-6 — Forbidden grep : aucune lecture directe basis.z dans src/gameplay/combat/
# ---------------------------------------------------------------------------

## AC-6 : aucun fichier `.gd` du dossier combat ne lit `camera.basis.z`,
## `player.transform.basis.z`, ni `*.global_transform.basis.z` directement.
## Lignes commentées (`#`) exemptées.
func test_combat_source_no_direct_basis_z_read() -> void:
	var dir: DirAccess = DirAccess.open(COMBAT_DIR)
	assert_object(dir).is_not_null()

	var gd_files: PackedStringArray = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".gd"):
			gd_files.append(COMBAT_DIR + entry)
		entry = dir.get_next()
	dir.list_dir_end()

	var regex: RegEx = RegEx.new()
	# Match : `camera.basis.z`, `player.transform.basis.z`, `*.global_transform.basis.z`.
	# `aim_forward` autorisé (lecture API publique CameraSystem).
	regex.compile("\\b(camera|player\\.transform|\\.global_transform)\\.basis\\.z\\b")

	var violations: Array[String] = []
	for path: String in gd_files:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var lines: PackedStringArray = file.get_as_text().split("\n")
		file.close()
		for i: int in range(lines.size()):
			var line: String = lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			if regex.search(line) != null:
				violations.append("%s:%d: %s" % [path, i + 1, line])

	assert_int(violations.size()) \
		.override_failure_message(
			"AC-6: lecture directe basis.z interdite dans src/gameplay/combat/. " +
			"Utiliser CameraSystem.aim_forward (ADR-0002 D-2). Violations : %s"
			% str(violations)
		) \
		.is_equal(0)


# ---------------------------------------------------------------------------
# Behavior preservation : aim valide → SWINGING + cooldown armé
# ---------------------------------------------------------------------------

## Régression : avec aim valide, le comportement de la state machine reste identique
## (cooldown armé, _hit_this_swing vide, ShapeCast enabled).
func test_combat_swing_with_valid_aim_arms_cooldown_and_enables_shapecast() -> void:
	var pair: Array = _make_combat_with_mock_camera()
	var combat: CombatSystem = pair[0]
	var mock_cam: MockCameraSystem = pair[1]
	mock_cam.aim_forward = Vector3(0.0, 0.0, -1.0)

	combat.attacked()

	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)
	var expected_cd: float = CombatSystem.ATTACK_COOLDOWN_MS / 1000.0
	assert_float(combat._cooldown_timer) \
		.is_between(expected_cd - 0.001, expected_cd + 0.001)
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_bool(sc.enabled).is_true()
	assert_bool(combat._hit_this_swing.is_empty()).is_true()

	combat.get_parent().queue_free()
