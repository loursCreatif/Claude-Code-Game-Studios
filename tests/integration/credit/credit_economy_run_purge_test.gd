# Tests d'intégration Story-005 — CreditEconomy run-purge via GSM.new_run_requested.
# Couvre AC-CRD-10 (purge _credited_this_run sur request_new_run, total intact)
# et AC-CRD-50 (absence de handler Checkpoint → no side-effect, idempotence preservée).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration.
# Naming : test_credit_economy_[scenario]_[expected_result] per .claude/rules/test-standards.md.
#
# GDD   : design/gdd/credit-economy-system.md (R-CRD-6, Rule 10 idempotence)
# Story : production/epics/credit-economy-system/story-005-run-purge-gsm-checkpoint-defensive.md

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# EnemyStub — minimal node pour AC-CRD-50 (phase d : idempotence re-kill).
# ---------------------------------------------------------------------------

class EnemyStub extends Node:
	signal enemy_killed(enemy: Node, position: Vector3)

	func _ready() -> void:
		add_to_group(&"enemies")

	func die(position: Vector3 = Vector3.ZERO) -> void:
		enemy_killed.emit(self, position)


# ---------------------------------------------------------------------------
# Signal spies
# ---------------------------------------------------------------------------

var _credits_emit_calls: Array[Array] = []
var _new_run_emit_count: int = 0
## Stocke les états reçus via state_changed. Untyped pour accepter les valeurs
## enum GameStateManagerScript.State sans erreur de cast GdUnit4.
var _state_changed_calls: Array = []

func _on_credits_changed_capture(total: int, delta: int, source: int) -> void:
	_credits_emit_calls.append([total, delta, source])

func _on_new_run_requested_capture() -> void:
	_new_run_emit_count += 1

func _on_state_changed_capture(new_state: GameStateManagerScript.State) -> void:
	_state_changed_calls.append(new_state)


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

## État GSM sauvegardé pour restauration propre après tests qui le mutent.
var _saved_gsm_state: GameStateManagerScript.State = GameStateManagerScript.State.MENU

func before_test() -> void:
	_saved_gsm_state = GameStateManager._current_state
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = true
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	GameStateManager._current_state = GameStateManager.State.PLAYING
	_credits_emit_calls = [] as Array[Array]
	_new_run_emit_count = 0
	_state_changed_calls = []
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)
	if GameStateManager.new_run_requested.is_connected(_on_new_run_requested_capture):
		GameStateManager.new_run_requested.disconnect(_on_new_run_requested_capture)
	if GameStateManager.state_changed.is_connected(_on_state_changed_capture):
		GameStateManager.state_changed.disconnect(_on_state_changed_capture)
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._total_credits = 0
	# Restaurer GSM dans l'état sauvegardé (évite de polluer les tests suivants).
	GameStateManager._current_state = _saved_gsm_state


## Helper : connecte un spy sur new_run_requested pour compter les emits.
func _connect_new_run_spy() -> void:
	if not GameStateManager.new_run_requested.is_connected(_on_new_run_requested_capture):
		GameStateManager.new_run_requested.connect(_on_new_run_requested_capture)


## Spawns an EnemyStub, adds it as child, returns it.
func _spawn_enemy_stub() -> EnemyStub:
	var stub: EnemyStub = auto_free(EnemyStub.new())
	add_child(stub)
	return stub


# ---------------------------------------------------------------------------
# AC-CRD-10 — request_new_run purge set, total intact
# ---------------------------------------------------------------------------

func test_credit_economy_request_new_run_purges_set_and_keeps_total() -> void:
	# Arrange — set peuplé, total non-nul.
	CreditEconomy._credited_this_run[1001] = true
	CreditEconomy._credited_this_run[1002] = true
	CreditEconomy._credited_this_run[1003] = true
	CreditEconomy._total_credits = 12
	assert_int(CreditEconomy._credited_this_run.size()).is_equal(3)

	# Act — émettre directement le signal GSM (handler doit réagir).
	GameStateManager.new_run_requested.emit()

	# Assert — set purgé, total préservé.
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("AC-CRD-10 a: _credited_this_run doit etre vide apres new_run_requested") \
		.is_equal(0)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-10 b: _total_credits ne doit PAS etre touche") \
		.is_equal(12)


func test_credit_economy_request_new_run_handler_on_empty_set_is_no_op() -> void:
	# Arrange — set déjà vide, total à 0.
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._total_credits = 0

	# Act — émettre le signal sur set vide (cas no-op défensif).
	GameStateManager.new_run_requested.emit()

	# Assert — aucun crash, état inchangé.
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("AC-CRD-10 (no-op): set vide reste vide, pas de crash") \
		.is_equal(0)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-10 (no-op): total reste 0") \
		.is_equal(0)


func test_credit_economy_request_new_run_via_gsm_verb_emits_signal() -> void:
	# Arrange — GSM en BOSS_DEFEATED + set peuplé.
	GameStateManager._current_state = GameStateManager.State.BOSS_DEFEATED
	CreditEconomy._credited_this_run[4001] = true
	CreditEconomy._credited_this_run[4002] = true
	CreditEconomy._total_credits = 7

	# Connecter les spies AVANT l'appel.
	_connect_new_run_spy()
	if not GameStateManager.state_changed.is_connected(_on_state_changed_capture):
		GameStateManager.state_changed.connect(_on_state_changed_capture)

	# Act — appel du verbe public GSM.
	GameStateManager.request_new_run()

	# Assert — GSM transitionne MENU.
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("AC-CRD-10 verb: GSM doit etre en State.MENU apres request_new_run") \
		.is_equal(GameStateManager.State.MENU)
	# Signal new_run_requested émis exactement 1 fois.
	assert_int(_new_run_emit_count) \
		.override_failure_message("AC-CRD-10 verb: new_run_requested doit etre emis exactement 1 fois") \
		.is_equal(1)
	# state_changed(MENU) reçu.
	assert_bool(GameStateManager.State.MENU in _state_changed_calls) \
		.override_failure_message("AC-CRD-10 verb: state_changed(MENU) doit etre recu") \
		.is_true()
	# Set Credit purgé par le handler.
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("AC-CRD-10 verb: Credit._credited_this_run doit etre vide") \
		.is_equal(0)
	# Total préservé.
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-10 verb: _total_credits doit rester intact") \
		.is_equal(7)


# ---------------------------------------------------------------------------
# AC-CRD-50 + NB-CRD-4 — triggers non-canoniques ne purgent ni n'émettent
# ---------------------------------------------------------------------------

## Couvre AC-CRD-50 phases a/b/c en émettant un trigger qui POURRAIT être
## confondu avec un restore Checkpoint (state_changed RESPAWNING) — vérifie
## activement que ce signal ne déclenche AUCUN side-effect côté Credit.
## Couvre AUSSI NB-CRD-4 (forbidden trigger : RESPAWNING ne doit jamais
## purger _credited_this_run).
func test_credit_economy_state_changed_respawning_does_not_purge_set_or_emit() -> void:
	# Arrange — set peuplé, total non-nul, spy credits_changed armé via before_test.
	CreditEconomy._credited_this_run[2001] = true
	CreditEconomy._credited_this_run[2002] = true
	CreditEconomy._total_credits = 7

	# Act — émettre un signal voisin d'un Checkpoint restore : state_changed(RESPAWNING).
	# Ce signal est dans le domaine Credit (state_changed est connecté pour persistance MENU)
	# mais NE DOIT PAS déclencher la purge du set (NB-CRD-4 forbidden pattern).
	GameStateManager.state_changed.emit(GameStateManagerScript.State.RESPAWNING)

	# Assert — AC-CRD-50 a : set préservé (b : total inchangé ; c : 0 emit credits_changed).
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("AC-CRD-50 a / NB-CRD-4: state_changed(RESPAWNING) ne doit pas purger _credited_this_run") \
		.is_equal(2)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-50 b: _total_credits doit rester intact sur RESPAWNING") \
		.is_equal(7)
	assert_int(_credits_emit_calls.size()) \
		.override_failure_message("AC-CRD-50 c: zero credits_changed emit pendant un trigger non-canonique") \
		.is_equal(0)


## Edge case AC-CRD-10 verb : request_new_run depuis état non-BOSS_DEFEATED est
## idempotent côté GSM (no-op silencieux) — donc new_run_requested n'est pas
## émis et Credit ne purge pas le set. Garde-fou contre régression future.
func test_credit_economy_request_new_run_from_non_boss_defeated_state_is_silent() -> void:
	# Arrange — set peuplé, GSM en PLAYING (état non-canonique pour request_new_run).
	CreditEconomy._credited_this_run[3001] = true
	CreditEconomy._credited_this_run[3002] = true
	CreditEconomy._total_credits = 5
	GameStateManager._current_state = GameStateManagerScript.State.PLAYING
	_connect_new_run_spy()

	# Act — verbe GSM appelé depuis état illégal pour cette transition.
	GameStateManager.request_new_run()

	# Assert — GSM n'a rien fait (pas de transition, pas d'emit), Credit set intact.
	assert_int(GameStateManager.get_current_state()) \
		.override_failure_message("Edge: GSM doit rester en PLAYING (request_new_run no-op hors BOSS_DEFEATED)") \
		.is_equal(GameStateManagerScript.State.PLAYING)
	assert_int(_new_run_emit_count) \
		.override_failure_message("Edge: new_run_requested NE DOIT PAS etre emis sur transition illegale") \
		.is_equal(0)
	assert_int(CreditEconomy._credited_this_run.size()) \
		.override_failure_message("Edge: set doit rester peuple (purge UNIQUEMENT sur trigger canonique)") \
		.is_equal(2)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("Edge: _total_credits intact") \
		.is_equal(5)


func test_credit_economy_re_kill_after_checkpoint_restore_is_idempotent_silent() -> void:
	# Arrange — set contient ennemi 2001 (déjà récompensé avant checkpoint).
	CreditEconomy._credited_this_run[2001] = true
	CreditEconomy._total_credits = 7
	CreditEconomy._is_hydrated = true
	GameStateManager._current_state = GameStateManager.State.PLAYING

	# Spawner un stub avec instance_id connu (le même noeud = même instance_id).
	var stub: EnemyStub = _spawn_enemy_stub()
	# Forcer l'id connu dans le set via l'instance_id réel du stub.
	var stub_id: int = stub.get_instance_id()
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._credited_this_run[stub_id] = true
	# Connecter Credit au stub comme le ferait level_active.
	if not stub.enemy_killed.is_connected(CreditEconomy._on_enemy_killed):
		stub.enemy_killed.connect(CreditEconomy._on_enemy_killed)

	# Act — re-kill du même ennemi (post-checkpoint restore simulation).
	stub.die(Vector3.ZERO)
	CreditEconomy._physics_process(0.0)

	# Assert — idempotence : total inchangé, zéro emit credits_changed.
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-50 d: _total_credits ne doit pas changer (idempotence re-kill)") \
		.is_equal(7)
	assert_int(_credits_emit_calls.size()) \
		.override_failure_message("AC-CRD-50 d: zero credits_changed emit sur re-kill idempotent") \
		.is_equal(0)
