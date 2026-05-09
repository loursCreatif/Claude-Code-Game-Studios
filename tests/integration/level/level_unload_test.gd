# Tests d'intégration Story-003 — unload_current() + transition UNLOADING + signal level_unloading
# + rejet de chargement concurrent.
# Couvre AC-LVL-4, AC-LVL-5, AC-LVL-10 (end-to-end), AC-LVL-28, AC-LVL-39.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Fixtures : tests/fixtures/levels/test_etage_01.tscn (PlayerStart à (10, 2, 5)).
# Chaque test crée sa propre instance de LevelSystemScript — aucun état partagé.
#
# Note architecture : level_unloading est émis de façon SYNCHRONE depuis unload_current()
# (exception ADR-0005 D-4 — ADR-0011 D-5). Le signal arrive donc avant le retour de
# unload_current(). Les tests capturent via un handler connecté avant l'appel,
# pas via await_signal_on() post-appel.

extends GdUnitTestSuite

const _FIXTURE_PATH_TEMPLATE: String = "res://tests/fixtures/levels/test_etage_%02d.tscn"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée un LevelSystemScript avec la fixture de test et l'attache au scene tree.
## scene_path_template doit être défini AVANT add_child() (DI principle).
func _make_level() -> LevelSystemScript:
	var level: LevelSystemScript = LevelSystemScript.new()
	level.scene_path_template = _FIXTURE_PATH_TEMPLATE
	add_child(level)
	return level


## Charge l'étage 1 et attend le signal level_active.
## Helper partagé entre les tests qui démarrent depuis l'état ACTIVE.
func _make_loaded_level() -> LevelSystemScript:
	var level: LevelSystemScript = _make_level()
	level.load_etage(1)
	await await_signal_on(level, "level_active", [], 2000)
	return level

# ---------------------------------------------------------------------------
# AC-LVL-4 + AC-LVL-39 — Rejet du chargement concurrent quand état != UNLOADED
# ---------------------------------------------------------------------------

## Vérifie que load_etage() depuis l'état ACTIVE rejette le chargement concurrent.
## L'implémentation utilise pattern push_error → assert(false) (level_system.gd l.176-177) :
## GdUnit4 `assert_error(...).is_push_error(...)` capture le push_error AVANT que l'assert
## halt l'exécution de la fonction (pattern story-001 B2). Le test fonctionne donc en debug
## et release. Le message inclut le suffix "(state=ACTIVE)" car push_error et assert partagent
## le même `msg` (level_system.gd l.173) — AC-LVL-39 satisfait : "concurrent load" + "unload first".
## Couvre AC-LVL-4 (state inchangé) + AC-LVL-39 (message).
func test_load_etage_rejected_when_active() -> void:
	# Arrange — amener le level en état ACTIVE
	var level: LevelSystemScript = await _make_loaded_level()

	assert_int(level.get_state()) \
		.override_failure_message("Precondition: état doit être ACTIVE avant le rejet") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)

	# Act + Assert — push_error capturé avant halt assert(false)
	assert_error(
		func() -> void: level.load_etage(2)
	).is_runtime_error("Assertion failed: concurrent load rejected — unload first (state=ACTIVE)")

	# Assert post-rejet — état et etage_id inchangés (AC-LVL-4)
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-4: état doit rester ACTIVE après rejet concurrent") \
		.is_equal(LevelSystemScript.LevelState.ACTIVE)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-39: etage_id doit rester 1 après rejet concurrent") \
		.is_equal(1)

	# Cleanup
	level.queue_free()


## Vérifie que load_etage() depuis l'état LOADING rejette aussi (edge case story spec).
## On capture le moment exact entre load_threaded_request et resources_ready en appelant
## load_etage(2) immédiatement après load_etage(1), AVANT d'attendre level_active.
## Couvre AC-LVL-4 + AC-LVL-39 pour le sous-état LOADING (T-1 ADR-0011 D-4).
func test_load_etage_rejected_when_loading() -> void:
	# Arrange — démarrer le chargement sans attendre level_active
	var level: LevelSystemScript = _make_level()
	level.load_etage(1)

	assert_int(level.get_state()) \
		.override_failure_message("Precondition: état doit être LOADING immédiatement après load_etage()") \
		.is_equal(LevelSystemScript.LevelState.LOADING)

	# Act + Assert — second load_etage pendant LOADING doit être rejeté
	assert_error(
		func() -> void: level.load_etage(2)
	).is_runtime_error("Assertion failed: concurrent load rejected — unload first (state=LOADING)")

	# Assert post-rejet — état LOADING préservé, etage_id reste celui du load initial (1)
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-4: état doit rester LOADING après rejet concurrent") \
		.is_equal(LevelSystemScript.LevelState.LOADING)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-39: etage_id doit rester 1 (load initial) après rejet") \
		.is_equal(1)

	# Cleanup — laisser level_active se résoudre puis cleanup
	await await_signal_on(level, "level_active", [], 2000)
	level.queue_free()


## Vérifie que load_etage() depuis l'état UNLOADING rejette aussi (edge case story spec).
## unload_current() est synchrone : state passe immédiatement à UNLOADING avant le retour
## (avant le tick _physics_process suivant qui transitera UNLOADING→UNLOADED). On exploite
## cette fenêtre pour tester le reject.
## Couvre AC-LVL-4 + AC-LVL-39 pour le sous-état UNLOADING (T-1 ADR-0011 D-4).
func test_load_etage_rejected_when_unloading() -> void:
	# Arrange — amener à ACTIVE puis déclencher unload sans attendre le tick physique
	var level: LevelSystemScript = await _make_loaded_level()
	level.unload_current()

	assert_int(level.get_state()) \
		.override_failure_message("Precondition: état doit être UNLOADING immédiatement après unload_current()") \
		.is_equal(LevelSystemScript.LevelState.UNLOADING)

	# Act + Assert — load_etage pendant UNLOADING doit être rejeté
	assert_error(
		func() -> void: level.load_etage(2)
	).is_runtime_error("Assertion failed: concurrent load rejected — unload first (state=UNLOADING)")

	# Assert post-rejet — état UNLOADING préservé, etage_id encore 1 (réinitialisé au prochain tick)
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-4: état doit rester UNLOADING après rejet concurrent") \
		.is_equal(LevelSystemScript.LevelState.UNLOADING)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-39: etage_id doit rester 1 pendant UNLOADING (reset à -1 au prochain physics tick)") \
		.is_equal(1)

	# Cleanup — laisser le tick UNLOADING→UNLOADED se compléter
	await get_tree().physics_frame
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-5 — level_unloading émis AVANT queue_free(), scène libérée après 1 frame
# ---------------------------------------------------------------------------

## Vérifie que :
##   1. unload_current() depuis ACTIVE émet level_unloading(1) de façon synchrone
##   2. Au moment du signal, la scène N'EST PAS encore queued_for_deletion
##      (signal arrive AVANT queue_free — ADR-0011 D-4 T-3)
##   3. Un tick physique après, l'état est UNLOADED et etage_id == -1
## Note : level_unloading est synchrone (ADR-0011 D-5) — le signal est reçu
## pendant l'appel à unload_current(), avant son retour.
## Couvre AC-LVL-5.
func test_unload_emits_signal_before_queue_free() -> void:
	# Arrange
	var level: LevelSystemScript = await _make_loaded_level()

	# Capturer la référence au scene root AVANT unload pour vérifier is_queued_for_deletion
	var scene_root_ref: Node3D = level._current_scene_root

	assert_object(scene_root_ref) \
		.override_failure_message("AC-LVL-5: _current_scene_root ne doit pas être null en ACTIVE") \
		.is_not_null()

	var signal_received: bool = false
	var signal_etage_id: int = -1
	var scene_queued_at_signal: bool = true  # pessimiste — doit être false si spec respectée

	# Connexion SYNC (mode par défaut) — handler appelé pendant l'emit, avant le retour
	# de level_unloading.emit(). À ce moment, queue_free() n'a pas encore été appelé.
	level.level_unloading.connect(func(eid: int) -> void:
		signal_received = true
		signal_etage_id = eid
		# Au moment du signal : queue_free() n'a PAS encore été appelé (ordre spec :
		# emit → queue_free → null). Donc is_queued_for_deletion() doit être false.
		scene_queued_at_signal = scene_root_ref.is_queued_for_deletion()
	)

	# Act — signal synchrone : émis et reçu pendant cet appel
	level.unload_current()

	# Assert immédiat — signal reçu pendant l'appel à unload_current()
	assert_bool(signal_received) \
		.override_failure_message("AC-LVL-5: signal level_unloading doit avoir été émis (sync)") \
		.is_true()
	assert_int(signal_etage_id) \
		.override_failure_message("AC-LVL-5: level_unloading.etage_id doit être 1") \
		.is_equal(1)

	# Assert — au moment du signal, la scène n'était PAS encore libérée (signal AVANT queue_free)
	assert_bool(scene_queued_at_signal) \
		.override_failure_message("AC-LVL-5: scène ne doit PAS être queued_for_deletion pendant l'émission du signal") \
		.is_false()

	# Vérifier l'état immédiatement après : UNLOADING (pas encore UNLOADED)
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-5: état doit être UNLOADING immédiatement après unload_current()") \
		.is_equal(LevelSystemScript.LevelState.UNLOADING)

	# Attendre un tick physique pour que UNLOADING → UNLOADED se complète dans _physics_process
	await get_tree().physics_frame

	# Assert — état final UNLOADED et etage_id réinitialisé
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-5: état doit être UNLOADED après 1 physics tick") \
		.is_equal(LevelSystemScript.LevelState.UNLOADED)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-5: get_current_etage_id() doit être -1 après unload complet") \
		.is_equal(-1)

	# Cleanup
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-10 — unload_current() idempotent depuis UNLOADED (end-to-end)
# ---------------------------------------------------------------------------

## Vérifie que 3 appels consécutifs à unload_current() depuis l'état UNLOADED :
##   - Ne crashent pas
##   - Ne changent pas l'état (reste UNLOADED)
##   - N'émettent PAS le signal level_unloading
## Couvre AC-LVL-10 (idempotence end-to-end avec signal guard).
func test_unload_idempotent_from_unloaded() -> void:
	# Arrange
	var level: LevelSystemScript = _make_level()
	await get_tree().process_frame

	var signal_count: int = 0
	level.level_unloading.connect(func(_eid: int) -> void:
		signal_count += 1
	)

	# Act — 3 appels consécutifs depuis UNLOADED
	level.unload_current()
	level.unload_current()
	level.unload_current()

	# Attendre quelques ticks pour s'assurer qu'aucun signal ne part en différé
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assert — état inchangé, aucun signal émis
	assert_int(level.get_state()) \
		.override_failure_message("AC-LVL-10: état doit rester UNLOADED après 3× unload_current()") \
		.is_equal(LevelSystemScript.LevelState.UNLOADED)
	assert_int(level.get_current_etage_id()) \
		.override_failure_message("AC-LVL-10: etage_id doit rester -1 après 3× unload_current()") \
		.is_equal(-1)
	assert_int(signal_count) \
		.override_failure_message("AC-LVL-10: level_unloading ne doit PAS être émis depuis UNLOADED (count doit être 0)") \
		.is_equal(0)

	# Cleanup
	level.queue_free()

# ---------------------------------------------------------------------------
# AC-LVL-28 — Un peer peut se désabonner proprement dans le handler level_unloading
# ---------------------------------------------------------------------------

## Vérifie qu'un peer connecté à level_active peut se déconnecter proactivement
## dans le handler level_unloading (pattern cleanup AVANT queue_free).
## Après le handler, level_active ne doit plus avoir de connexion du peer.
## Source : ADR-0011 D-4 T-3, ADR-0005 D-5 (désabonnement sync autorisé).
## Couvre AC-LVL-28.
func test_peer_unsubscribes_on_level_unloading() -> void:
	# Arrange
	var level: LevelSystemScript = await _make_loaded_level()

	var peer: Node = Node.new()
	add_child(peer)
	await get_tree().process_frame

	var peer_active_handler_called_before_unload: bool = false

	# Handler peer sur level_active (connexion existante à déconnecter)
	var peer_active_callable: Callable = func(_eid: int, _pos: Vector3) -> void:
		peer_active_handler_called_before_unload = true

	level.level_active.connect(peer_active_callable)

	# Vérification précondition — connexion peer sur level_active est présente
	var connections_before: Array[Dictionary] = level.get_signal_connection_list("level_active")
	var peer_connected_before: bool = false
	for conn: Dictionary in connections_before:
		if conn.get("callable", Callable()) == peer_active_callable:
			peer_connected_before = true
			break

	assert_bool(peer_connected_before) \
		.override_failure_message("AC-LVL-28: connexion peer sur level_active doit être présente avant unload") \
		.is_true()

	# Le peer se déconnecte proactivement de level_active dans le handler level_unloading
	level.level_unloading.connect(func(_eid: int) -> void:
		if level.level_active.is_connected(peer_active_callable):
			level.level_active.disconnect(peer_active_callable)
	)

	# Act — signal synchrone : le handler level_unloading s'exécute pendant cet appel
	level.unload_current()

	# Attendre un tick pour laisser se propager
	await get_tree().process_frame

	# Assert — le peer a réussi à se déconnecter de level_active pendant l'emit level_unloading
	var connections_after: Array[Dictionary] = level.get_signal_connection_list("level_active")
	var peer_still_connected: bool = false
	for conn: Dictionary in connections_after:
		if conn.get("callable", Callable()) == peer_active_callable:
			peer_still_connected = true
			break

	assert_bool(peer_still_connected) \
		.override_failure_message("AC-LVL-28: le peer doit avoir réussi à se désabonner de level_active dans le handler level_unloading") \
		.is_false()

	# Cleanup
	peer.queue_free()
	level.queue_free()
