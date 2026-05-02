# Integration tests for Story 005 — Grunt pause / state lifecycle.
# Couvre AC-ENM-19 (tween wall-clock 150 ms hors pause via TWEEN_PAUSE_BOUND default
# + set_ignore_time_scale(true)) + AC-ENM-20 (LaserCone.monitoring inchangé sous pause).
#
# Pattern : load Grunt.tscn, manipuler `get_tree().paused = true/false` directement
# (simule l'effet GSM autorité D-4 sans coupler à l'état autoload). Wall-clock test
# driver via create_timer(t, process_always=true, _, ignore_time_scale=true) — fire
# même quand tree.paused.
#
# Story Type : Integration. Test Evidence path : tests/integration/enemy/.
# Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRUNT_SCENE_PATH: String = "res://src/gameplay/enemy/Grunt.tscn"
const PHASE_1_WALL_CLOCK_S: float = 0.075   # 75 ms : tween en cours, scale > EPSILON.
const PHASE_2_PAUSE_WALL_CLOCK_S: float = 0.10  # 100 ms : pause active, scale figé.
const PHASE_3_RESUME_WALL_CLOCK_S: float = 0.15  # 150 ms : marge confortable pour 75 ms restants + buffer CI.
const SCALE_TOLERANCE: float = 0.01


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

var _grunt: Grunt = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	var grunt_scene: PackedScene = load(GRUNT_SCENE_PATH)
	_grunt = grunt_scene.instantiate() as Grunt
	add_child(_grunt)
	await get_tree().process_frame


func after_test() -> void:
	# Toujours libérer la pause d'abord — éviter qu'un test pollue le suivant.
	if get_tree().paused:
		get_tree().paused = false
	if _grunt != null and is_instance_valid(_grunt):
		_grunt.queue_free()
	_grunt = null
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# AC-ENM-19 — Pause pendant DYING fige le tween, resume reprend, completion @ 150 ms wall-clock hors pause
# ---------------------------------------------------------------------------

func test_pause_during_dying_freezes_tween_resume_completes_at_150ms_wall_clock_excluding_pause() -> void:
	# Arrange — Grunt en ALIVE avec MeshInstance3D (Grunt.tscn fournit le mesh).
	var mesh: MeshInstance3D = _grunt.get_node("MeshInstance3D") as MeshInstance3D
	assert_object(mesh) \
		.override_failure_message("Setup: Grunt.tscn doit fournir un MeshInstance3D enfant") \
		.is_not_null()
	assert_vector(mesh.scale).is_equal_approx(Vector3.ONE, Vector3.ONE * SCALE_TOLERANCE)

	# Act 1 — die() lance le tween scale 1.0 → EPSILON sur 150 ms wall-clock.
	_grunt.die()
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-19: Grunt en DYING immédiatement post-die()") \
		.is_equal(Grunt.State.DYING)

	# Phase 1 — 75 ms wall-clock : tween partiellement en cours.
	# Timer process_always=true, ignore_time_scale=true → wall-clock pur.
	await get_tree().create_timer(PHASE_1_WALL_CLOCK_S, true, false, true).timeout

	# Vérifier que le tween a progressé (scale réduit mais pas EPSILON).
	var scale_at_pause: Vector3 = mesh.scale
	assert_bool(scale_at_pause.x < 1.0 - SCALE_TOLERANCE) \
		.override_failure_message("AC-ENM-19 phase 1: scale a progressé après 75 ms (got %s)" % str(scale_at_pause)) \
		.is_true()
	assert_bool(scale_at_pause.x > Grunt.EPSILON + SCALE_TOLERANCE) \
		.override_failure_message("AC-ENM-19 phase 1: scale pas encore EPSILON (got %s)" % str(scale_at_pause)) \
		.is_true()
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-19 phase 1: toujours DYING") \
		.is_equal(Grunt.State.DYING)

	# Phase 2 — pause + 100 ms wall-clock : tween figé via TWEEN_PAUSE_BOUND default.
	get_tree().paused = true
	await get_tree().create_timer(PHASE_2_PAUSE_WALL_CLOCK_S, true, false, true).timeout

	# Vérifier scale figé pendant la pause.
	assert_vector(mesh.scale) \
		.override_failure_message("AC-ENM-19 phase 2 / EC-ENM-9: scale figé pendant pause (was %s, now %s)" % [str(scale_at_pause), str(mesh.scale)]) \
		.is_equal_approx(scale_at_pause, Vector3.ONE * SCALE_TOLERANCE)
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-19 phase 2: state DYING figé pendant pause") \
		.is_equal(Grunt.State.DYING)

	# Phase 3 — resume + 150 ms wall-clock (75 ms restants + buffer).
	get_tree().paused = false
	await get_tree().create_timer(PHASE_3_RESUME_WALL_CLOCK_S, true, false, true).timeout

	# Assert — completion : DEAD + scale ≈ EPSILON.
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-19 phase 3: tween complété post-resume → DEAD") \
		.is_equal(Grunt.State.DEAD)
	assert_vector(mesh.scale) \
		.override_failure_message("AC-ENM-19 phase 3: scale ≈ EPSILON post-completion") \
		.is_equal_approx(Vector3(Grunt.EPSILON, Grunt.EPSILON, Grunt.EPSILON), Vector3.ONE * SCALE_TOLERANCE)


# ---------------------------------------------------------------------------
# AC-ENM-20 — Pause sur Grunt ALIVE laisse LaserCone.monitoring = true (no-fire est Godot natif)
# ---------------------------------------------------------------------------

func test_paused_alive_grunt_keeps_laser_cone_monitoring_enabled() -> void:
	# Arrange — Grunt ALIVE (default post _ready), LaserCone monitoring=true.
	assert_int(_grunt._state) \
		.override_failure_message("Setup: Grunt ALIVE par default") \
		.is_equal(Grunt.State.ALIVE)

	var cone: Area3D = _grunt.get_node("%LaserCone") as Area3D
	assert_object(cone).is_not_null()
	assert_bool(cone.monitoring) \
		.override_failure_message("Setup: LaserCone.monitoring=true post _ready") \
		.is_true()

	# Act — pause tree (autorité GSM D-4 simulée).
	get_tree().paused = true
	await get_tree().process_frame

	# Assert — monitoring inchangé.
	# Note : "no body_entered fire pendant pause" est garanti par Godot natif (physics paused
	# = pas de collision queries). Reproduire hermétiquement nécessiterait physics frame
	# complète + body. Le contrat BLOCKING est : monitoring reste true (pas désactivé par pause).
	assert_bool(cone.monitoring) \
		.override_failure_message("AC-ENM-20: LaserCone.monitoring reste true sous pause (no-fire est Godot natif)") \
		.is_true()
	assert_int(_grunt._state) \
		.override_failure_message("AC-ENM-20: state ALIVE figé pendant pause") \
		.is_equal(Grunt.State.ALIVE)


# ---------------------------------------------------------------------------
# Bonus régression EC-ENM-9 — scale ne progresse pas pendant la pause (test isolé court)
# ---------------------------------------------------------------------------

func test_tween_scale_does_not_progress_during_pause() -> void:
	# Arrange — die() puis pause immédiate (pas d'attente phase 1 — focus sur figement).
	var mesh: MeshInstance3D = _grunt.get_node("MeshInstance3D") as MeshInstance3D
	_grunt.die()
	await get_tree().process_frame  # un tick pour lancer le tween

	var scale_at_pause: Vector3 = mesh.scale
	get_tree().paused = true
	await get_tree().create_timer(0.20, true, false, true).timeout  # 200 ms wall-clock pause

	# Assert — sans la pause, le tween aurait largement complété (200 ms > 150 ms total).
	# Avec TWEEN_PAUSE_BOUND, le scale doit rester ≈ scale_at_pause.
	assert_vector(mesh.scale) \
		.override_failure_message("EC-ENM-9: scale figé 200 ms pendant pause (pas d'avancement TWEEN_PAUSE_BOUND)") \
		.is_equal_approx(scale_at_pause, Vector3.ONE * SCALE_TOLERANCE)
	assert_int(_grunt._state) \
		.override_failure_message("EC-ENM-9: state DYING figé pendant pause prolongée") \
		.is_equal(Grunt.State.DYING)


# ---------------------------------------------------------------------------
# Bonus régression Rule 11.b — pause pendant DYING n'altère pas le monitoring (déjà false post-die)
# ---------------------------------------------------------------------------

func test_pause_during_dying_keeps_laser_cone_monitoring_disabled() -> void:
	# Arrange — die() désactive monitoring IMMÉDIATEMENT (Rule 11.b story-002).
	var cone: Area3D = _grunt.get_node("%LaserCone") as Area3D
	_grunt.die()
	await get_tree().process_frame
	assert_bool(cone.monitoring) \
		.override_failure_message("Rule 11.b: monitoring=false post-die() pré-pause") \
		.is_false()

	# Act — pause.
	get_tree().paused = true
	await get_tree().process_frame

	# Assert — monitoring reste false (pause ne réactive pas).
	assert_bool(cone.monitoring) \
		.override_failure_message("Rule 11.b sous pause: monitoring=false reste false (anti-régression EC-ENM-4)") \
		.is_false()
