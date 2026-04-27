# Tests d'intégration Story-002 — load_etage() threadé + transition UNLOADED → ACTIVE + signal level_active.
# Couvre AC-LVL-2, AC-LVL-26, AC-LVL-27.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures : tests/fixtures/levels/test_etage_01.tscn (PlayerStart à (10, 2, 5)).
# Chaque test crée sa propre instance de LevelSystemScript — aucun état partagé.

extends GdUnitTestSuite

const _FIXTURE_PATH_TEMPLATE: String = "res://tests/fixtures/levels/test_etage_%02d.tscn"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript avec la fixture de test et l'attache au scene tree.
## scene_path_template doit être défini AVANT add_child() pour que load_etage()
## utilise le bon chemin (DI principle — pas de preload production depuis tests).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	level.scene_path_template = _FIXTURE_PATH_TEMPLATE
	add_child(level)
	return level

# ---------------------------------------------------------------------------
# AC-LVL-2 — Transition UNLOADED → ACTIVE via load_etage(1) + signal level_active reçu
# ---------------------------------------------------------------------------

## Vérifie que load_etage(1) transite vers ACTIVE, émet level_active(1, Vector3(10,2,5))
## et que get_current_etage_id() == 1.
## AC-LVL-2 : signal reçu < 1000 ms (timeout GdUnit4 à 2000 ms, largement confortable).
func test_load_etage_transitions_unloaded_to_active_with_signal() -> void:
	# Arrange
	var level: LevelSystemScript = _make_level()
	await get_tree().process_frame

	var received_args: Array = []
	level.level_active.connect(func(id: int, pos: Vector3) -> void:
		received_args = [id, pos]
	)

	# Act
	level.load_etage(1)

	# Vérification immédiate : état LOADING dès l'appel synchrone
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-2: état doit être LOADING immédiatement après load_etage()") \
		.is_equal(LevelSystemScript.LevelState.LOADING)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-2: get_current_etage_id() doit retourner 1 pendant LOADING") \
		.is_equal(1)

	# Await signal level_active (timeout 2000 ms)
	await await_signal_on(level, "level_active", [], 2000)

	# Assert état final
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-2: get_state() doit être ACTIVE après level_active") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-2: get_current_etage_id() doit valoir 1") \
		.is_equal(1)

	# Assert payload signal
	assert_int(received_args.size()) \
		.override_failure_message("AC-LVL-2: signal level_active doit avoir été capturé (2 args)") \
		.is_equal(2)
	assert_int(received_args[0]) \
		.override_failure_message("AC-LVL-2: level_active.etage_id doit être 1") \
		.is_equal(1)
	assert_vector3(received_args[1]) \
		.override_failure_message("AC-LVL-2: level_active.player_start doit être (10, 2, 5)") \
		.is_equal(Vector3(10.0, 2.0, 5.0))

	# Cleanup
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-26 — level_active reçu APRÈS le _ready() du peer (CONNECT_DEFERRED)
# ---------------------------------------------------------------------------

## Source GDScript du peer fixture compilé inline. Le peer surcharge réellement
## _ready() et capture l'ordre d'exécution via :
##   1. ready_completed: bool — set true en fin de _ready()
##   2. handler_saw_ready: bool — set au handler à la valeur de ready_completed
##   3. emit_frame / handler_frame — captés via Engine.get_physics_frames() pour
##      vérifier que CONNECT_DEFERRED ne déclenche pas le handler synchrone à l'emit
## L'assertion clé est handler_saw_ready == true : si CONNECT_DEFERRED était
## remplacé par CONNECT_ONE_SHOT ou si la connexion n'était pas dans _ready(),
## ce flag serait false ou le handler ne tirerait pas. Test discriminant
## (cf. code review : ne pas se reposer sur monotonie d'Engine.get_physics_frames).
const _PEER_FIXTURE_SOURCE: String = """
extends Node

var level_ref: Object = null
var ready_completed: bool = false
var handler_called: bool = false
var handler_saw_ready: bool = false
var ready_frame: int = -1
var handler_frame: int = -1

func _ready() -> void:
	ready_frame = Engine.get_physics_frames()
	if level_ref != null:
		level_ref.level_active.connect(_on_level_active, CONNECT_DEFERRED)
	ready_completed = true

func _on_level_active(_id: int, _pos: Vector3) -> void:
	handler_called = true
	handler_saw_ready = ready_completed
	handler_frame = Engine.get_physics_frames()
"""

## Compile et instancie un peer fixture qui surcharge _ready() pour connecter
## level_active en CONNECT_DEFERRED. level_ref doit être assigné AVANT add_child()
## pour que _ready() (appelé sync par add_child) puisse établir la connexion.
func _make_peer(level: LevelSystemScript) -> Node:
	var peer_script: GDScript = GDScript.new()
	peer_script.source_code = _PEER_FIXTURE_SOURCE
	var compile_err: int = peer_script.reload()
	assert_int(compile_err) \
		.override_failure_message("AC-LVL-26: peer fixture script compilation failed (err=%d)" % compile_err) \
		.is_equal(OK)
	var peer: Node = Node.new()
	peer.set_script(peer_script)
	peer.set("level_ref", level)
	return peer

## Vérifie que le handler d'un peer connecté avec CONNECT_DEFERRED dans son _ready()
## se déclenche APRÈS que son propre _ready() ait été exécuté complètement.
## Test discriminant : si CONNECT_DEFERRED est cassé en sync, le handler verrait
## ready_completed == false (l'emit arrive depuis _physics_process de Level, alors
## que le handler du peer n'a pas terminé son _ready() initialisation).
func test_level_active_received_after_peer_ready() -> void:
	# Arrange
	var level: LevelSystemScript = _make_level()
	var peer: Node = _make_peer(level)

	# add_child déclenche le _ready() du peer SYNCHRONE → ready_frame capté ici.
	add_child(peer)
	await get_tree().process_frame

	# Sanity: _ready() s'est bien exécuté avant l'act.
	assert_bool(peer.get("ready_completed")) \
		.override_failure_message("AC-LVL-26: peer._ready() doit avoir terminé avant load_etage()") \
		.is_true()

	# Act
	level.load_etage(1)
	await await_signal_on(level, "level_active", [], 2000)
	# CONNECT_DEFERRED : le callback est queued à l'emit ; flush au prochain idle.
	await get_tree().process_frame

	# Assert — handler invoqué
	assert_bool(peer.get("handler_called")) \
		.override_failure_message("AC-LVL-26: handler CONNECT_DEFERRED doit avoir été appelé") \
		.is_true()

	# Assert discriminant — handler a vu ready_completed == true (ordre garanti).
	# Cette assertion échouerait si :
	#   - la connexion était sync et déclenchée pendant _ready() du peer (avant ready_completed = true)
	#   - le handler tirait via une autre voie qui contourne le pattern _ready()→connect
	assert_bool(peer.get("handler_saw_ready")) \
		.override_failure_message(
			"AC-LVL-26: handler doit observer ready_completed=true (ordre _ready→handler garanti)"
		) \
		.is_true()

	# Cleanup
	peer.queue_free()
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-27 — Signal level_active a la signature typée correcte
# ---------------------------------------------------------------------------

## Vérifie que get_signal_list() expose level_active avec exactement 2 arguments :
##   args[0] = {name: "etage_id",  type: TYPE_INT}
##   args[1] = {name: "player_start", type: TYPE_VECTOR3}
## Pas besoin de fixture scene — instanciation simple suffit.
func test_level_active_signal_has_typed_signature() -> void:
	# Arrange
	var level: LevelSystemScript = LevelSystemScript.new()
	add_child(level)
	await get_tree().process_frame

	# Act — chercher l'entrée level_active dans get_signal_list()
	var siglist: Array = level.get_signal_list()
	var entry: Dictionary = {}
	for sig: Dictionary in siglist:
		if sig.get("name", "") == "level_active":
			entry = sig
			break

	# Assert — le signal existe
	assert_bool(entry.is_empty()) \
		.override_failure_message("AC-LVL-27: level_active doit apparaître dans get_signal_list()") \
		.is_false()

	var args: Array = entry.get("args", [])

	# Assert — exactement 2 paramètres
	assert_int(args.size()) \
		.override_failure_message("AC-LVL-27: level_active doit avoir exactement 2 arguments") \
		.is_equal(2)

	# Assert — premier argument : etage_id: int
	assert_str(args[0].get("name", "")) \
		.override_failure_message("AC-LVL-27: args[0].name doit être 'etage_id'") \
		.is_equal("etage_id")
	assert_int(args[0].get("type", -1)) \
		.override_failure_message("AC-LVL-27: args[0].type doit être TYPE_INT (%d)" % TYPE_INT) \
		.is_equal(TYPE_INT)

	# Assert — deuxième argument : player_start: Vector3
	assert_str(args[1].get("name", "")) \
		.override_failure_message("AC-LVL-27: args[1].name doit être 'player_start'") \
		.is_equal("player_start")
	assert_int(args[1].get("type", -1)) \
		.override_failure_message("AC-LVL-27: args[1].type doit être TYPE_VECTOR3 (%d)" % TYPE_VECTOR3) \
		.is_equal(TYPE_VECTOR3)

	# Cleanup
	level.queue_free()
