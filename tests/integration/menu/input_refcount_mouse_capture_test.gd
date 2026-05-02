extends GdUnitTestSuite

## AC-MNU-26/27/28/29/30/31 — refcount InputManager + mouse capture coordination (story-008).
##
## Pattern : `_apply_visibility(show, recapture_mouse)` orchestre côté Pause Overlay :
##   show=true  → request_disable(self) + set_mouse_captured(false) + grab_focus
##   show=false → release_enable_request(self) [si blocker actif] + set_mouse_captured(true) si recapture
##
## On observe directement l'état réel de InputManager (`_enable_blockers` dict, `enabled`
## getter) et `Input.mouse_mode` — pas de mock. Les invariants ADR-0004 D-4 (refcount
## idempotent + multi-owner) sont propriétés de InputManager ; Menu vérifie l'intégration.
##
## tree_exiting auto-cleanup (AC-MNU-28) testé via `tree_exiting.emit()` manuel — déclenche
## le handler connecté `_on_tree_exiting` sans détruire effectivement le node.

const PAUSE_OVERLAY_SCENE: PackedScene = preload("res://scenes/menus/pause_overlay.tscn")

var _pause: CanvasLayer
var _saved_gsm_state: int
var _saved_mouse_mode: int


func before_test() -> void:
	_saved_gsm_state = GameStateManager._current_state
	_saved_mouse_mode = Input.mouse_mode


func after_test() -> void:
	# Cleanup InputManager._enable_blockers AVANT queue_free pour neutraliser
	# le tree_exiting auto-cleanup qui sinon retoucherait le dict pendant après_test.
	if _pause != null and is_instance_valid(_pause):
		var id: int = _pause.get_instance_id()
		if InputManager._enable_blockers.has(id):
			InputManager._enable_blockers.erase(id)
		_pause.queue_free()
		_pause = null
	if get_tree().paused:
		get_tree().paused = false
	GameStateManager._current_state = _saved_gsm_state
	Input.mouse_mode = _saved_mouse_mode
	# Snapshot final : tous les blockers de cette suite doivent être purgés. On ne touche
	# pas aux blockers d'autres suites (ex. tests parallèles si applicable).
	await get_tree().process_frame


func _spawn() -> CanvasLayer:
	GameStateManager._current_state = GameStateManager.State.PLAYING
	var layer: CanvasLayer = PAUSE_OVERLAY_SCENE.instantiate()
	auto_free(layer)
	add_child(layer)
	return layer


func test_ac_mnu_26_apply_visibility_show_invokes_request_disable() -> void:
	# AC-MNU-26 : `_apply_visibility(true, false)` doit poser un blocker InputManager
	# au nom du Pause Overlay (`self.get_instance_id()`).
	_pause = _spawn()
	await get_tree().process_frame

	var id: int = _pause.get_instance_id()
	# Pre-condition : aucun blocker pour cet owner (le _ready en MENU/PLAYING n'en pose pas).
	if InputManager._enable_blockers.has(id):
		InputManager._enable_blockers.erase(id)
	assert_bool(InputManager._enable_blockers.has(id)) \
		.override_failure_message("AC-MNU-26 setup: no blocker should be active before show") \
		.is_false()

	_pause.call("_apply_visibility", true, false)

	assert_bool(InputManager._enable_blockers.has(id)) \
		.override_failure_message("AC-MNU-26: request_disable(self) must register a blocker after show") \
		.is_true()
	assert_bool(InputManager.enabled) \
		.override_failure_message("AC-MNU-26: InputManager.enabled must be false while a blocker is active") \
		.is_false()


func test_ac_mnu_27_apply_visibility_hide_invokes_release_enable_request() -> void:
	# AC-MNU-27 : `_apply_visibility(false, true)` doit retirer le blocker
	# si ce dernier est actif (sortie pause vers PLAYING).
	_pause = _spawn()
	await get_tree().process_frame

	# Setup : blocker actif au nom de Pause Overlay.
	InputManager.request_disable(_pause)
	var id: int = _pause.get_instance_id()
	assert_bool(InputManager._enable_blockers.has(id)).is_true()

	_pause.call("_apply_visibility", false, true)

	assert_bool(InputManager._enable_blockers.has(id)) \
		.override_failure_message("AC-MNU-27: release_enable_request must clear the blocker after hide") \
		.is_false()
	assert_bool(InputManager.enabled) \
		.override_failure_message("AC-MNU-27: InputManager.enabled must return true once last blocker released") \
		.is_true()


func test_ac_mnu_28_tree_exiting_auto_releases_active_blocker() -> void:
	# AC-MNU-28 : tree_exiting handler doit auto-libérer le blocker si encore actif
	# (crash path : change_scene_to_file sans `_apply_visibility(false)` explicite préalable).
	_pause = _spawn()
	await get_tree().process_frame

	InputManager.request_disable(_pause)
	var id: int = _pause.get_instance_id()
	assert_bool(InputManager._enable_blockers.has(id)) \
		.override_failure_message("AC-MNU-28 setup: blocker must be active before tree_exiting") \
		.is_true()

	# Émet tree_exiting manuellement — déclenche le handler connecté sans détruire le node.
	_pause.tree_exiting.emit()

	assert_bool(InputManager._enable_blockers.has(id)) \
		.override_failure_message("AC-MNU-28: tree_exiting handler must auto-release the blocker") \
		.is_false()


func test_ac_mnu_28_ext_tree_exiting_idempotent_when_blocker_already_released() -> void:
	# AC-MNU-28 edge : si blocker déjà release par voie normale (`_apply_visibility(false)`
	# avant scene change), tree_exiting handler doit être no-op (pas de push_warning).
	_pause = _spawn()
	await get_tree().process_frame

	# Setup : blocker actif puis release explicite (voie normale story-007).
	InputManager.request_disable(_pause)
	InputManager.release_enable_request(_pause)
	var id: int = _pause.get_instance_id()
	assert_bool(InputManager._enable_blockers.has(id)).is_false()

	# Émet tree_exiting — handler doit no-op via guard `_enable_blockers.has(id)`.
	_pause.tree_exiting.emit()

	# Si le handler avait fait release sans guard, push_warning serait émis. Le test passe
	# tant qu'aucun crash n'a lieu et que le blocker reste absent.
	assert_bool(InputManager._enable_blockers.has(id)) \
		.override_failure_message("AC-MNU-28 ext: tree_exiting must remain idempotent when blocker already released") \
		.is_false()


func test_ac_mnu_29_release_pause_only_keeps_other_owners_active() -> void:
	# AC-MNU-29 : multi-owner ; release `&"PauseMenu"` seul → InputManager reste disabled
	# si un autre owner (ex. CutsceneSystem) est encore actif.
	_pause = _spawn()
	await get_tree().process_frame

	var other: Node = Node.new()
	auto_free(other)
	add_child(other)

	InputManager.request_disable(_pause)
	InputManager.request_disable(other)

	assert_int(InputManager._enable_blockers.size()) \
		.override_failure_message("AC-MNU-29 setup: 2 blockers should be active") \
		.is_equal(2)
	assert_bool(InputManager.enabled).is_false()

	InputManager.release_enable_request(_pause)

	assert_bool(InputManager._enable_blockers.has(_pause.get_instance_id())) \
		.override_failure_message("AC-MNU-29: pause blocker must be released") \
		.is_false()
	assert_bool(InputManager._enable_blockers.has(other.get_instance_id())) \
		.override_failure_message("AC-MNU-29: other owner's blocker must remain active") \
		.is_true()
	assert_bool(InputManager.enabled) \
		.override_failure_message("AC-MNU-29: InputManager must remain disabled while another owner is active") \
		.is_false()

	# Cleanup other.
	InputManager.release_enable_request(other)
	other.queue_free()


func test_ac_mnu_30_apply_visibility_show_calls_set_mouse_captured_false() -> void:
	# AC-MNU-30 : show → set_mouse_captured(false). Headless rejette `Input.mouse_mode`
	# silencieusement, donc on observe via test seam `_set_mouse_captured_handler`.
	_pause = _spawn()
	await get_tree().process_frame

	var calls: Array[bool] = []
	_pause._set_mouse_captured_handler = func(captured: bool) -> void:
		calls.append(captured)

	_pause.call("_apply_visibility", true, false)

	assert_array(calls) \
		.override_failure_message("AC-MNU-30: show must call set_mouse_captured(false) exactly 1× — got %s" % str(calls)) \
		.is_equal([false])


func test_ac_mnu_31_apply_visibility_hide_recaptures_mouse_when_recapture_true() -> void:
	# AC-MNU-31 : hide + recapture_mouse=true → set_mouse_captured(true) appelé.
	# (Resume vers PLAYING : le Movement reprend autorité, mouse capturée.)
	_pause = _spawn()
	await get_tree().process_frame

	InputManager.request_disable(_pause)

	var calls: Array[bool] = []
	_pause._set_mouse_captured_handler = func(captured: bool) -> void:
		calls.append(captured)

	_pause.call("_apply_visibility", false, true)

	assert_array(calls) \
		.override_failure_message("AC-MNU-31: hide+recapture_mouse=true must call set_mouse_captured(true) exactly 1× — got %s" % str(calls)) \
		.is_equal([true])


func test_ac_mnu_31_ext_hide_no_recapture_does_not_call_set_mouse_captured() -> void:
	# AC-MNU-31 corollaire : hide + recapture_mouse=false → set_mouse_captured PAS
	# appelé (transition vers MENU ou Quit — Implementation Notes story-008 §1).
	_pause = _spawn()
	await get_tree().process_frame

	InputManager.request_disable(_pause)

	var calls: Array[bool] = []
	_pause._set_mouse_captured_handler = func(captured: bool) -> void:
		calls.append(captured)

	_pause.call("_apply_visibility", false, false)

	assert_array(calls) \
		.override_failure_message("AC-MNU-31 ext: hide+recapture_mouse=false must NOT call set_mouse_captured — got %s" % str(calls)) \
		.is_equal([])
