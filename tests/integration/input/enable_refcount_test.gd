# Tests d'intégration Story-004 — Enable refcount multi-owner + auto-cleanup tree_exited.
# Couvre : AC-DS-1, AC-DS-2, AC-DS-3, AC-DS-4/CS-4, AC-CS-2, AC-CS-3.
# Couvre aussi : idempotence guardrail, robustesse release sans prior request.
# AC-CS-5 est advisory (playtest manuel) — voir production/qa/evidence/input-pause-unpause-{date}.md.
# ADR-0004 D-4, TR-inp-005. Framework : GdUnit4 (extends GdUnitTestSuite).

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Helpers & fixtures
# ---------------------------------------------------------------------------

## Crée un InputManager isolé (pas l'autoload) ajouté à la scène, ready.
## L'appelant est responsable de le libérer (manager.queue_free()).
func _make_manager() -> InputManagerScript:
	var manager: InputManagerScript = InputManagerScript.new()
	add_child(manager)
	return manager

## Crée un Node mock générique ajouté à la scène pour servir d'owner blocker.
## L'appelant est responsable de le libérer (mock.queue_free()).
func _make_owner_node() -> Node:
	var mock: Node = Node.new()
	add_child(mock)
	return mock

## Injecte un press d'action via parse_input_event (ADR-0004 D-9 : jamais Input.action_press).
func _inject_action_press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

## Injecte un InputEventMouseMotion avec un delta donné.
func _inject_mouse_motion(delta: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = delta
	Input.parse_input_event(ev)

# ---------------------------------------------------------------------------
# AC-DS-1 — Action gameplay bloquée quand _enabled == false
# ---------------------------------------------------------------------------

func test_ac_ds_1_gameplay_action_blocked_when_disabled() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame
	var owner_a: Node = _make_owner_node()

	var jump_emitted: int = 0
	manager.jump_pressed.connect(func() -> void: jump_emitted += 1)

	manager.request_disable(owner_a)
	assert_bool(manager.enabled).is_false()

	# Act — injecter un press jump pendant que le manager est désactivé
	_inject_action_press(&"jump")
	await get_tree().physics_frame

	# Assert — aucun signal gameplay émis, was_pressed_this_tick retourne false
	assert_int(jump_emitted) \
		.override_failure_message("AC-DS-1: jump_pressed ne doit pas être émis quand _enabled == false") \
		.is_equal(0)
	assert_bool(manager.was_pressed_this_tick(&"jump")) \
		.override_failure_message("AC-DS-1: was_pressed_this_tick doit retourner false quand _enabled == false") \
		.is_false()
	# Note : get_movement_vector() est hors scope (story non implémentée) — assertion skippée.

	owner_a.queue_free()
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-DS-2 — ui_cancel traverse même quand _enabled == false
# ---------------------------------------------------------------------------

func test_ac_ds_2_ui_cancel_passthrough_when_disabled() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame
	var owner_a: Node = _make_owner_node()

	var ui_cancel_count: int = 0
	manager.ui_cancel_pressed.connect(func() -> void: ui_cancel_count += 1)

	manager.request_disable(owner_a)
	assert_bool(manager.enabled).is_false()

	# Act — injecter ui_cancel pendant que le manager est désactivé
	_inject_action_press(&"ui_cancel")
	await get_tree().physics_frame

	# Assert — ui_cancel_pressed doit avoir été émis exactement 1 fois
	assert_int(ui_cancel_count) \
		.override_failure_message("AC-DS-2: ui_cancel_pressed doit traverser le gate _enabled (émis 1×)") \
		.is_equal(1)

	owner_a.queue_free()
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-DS-3 — mouse_motion bloqué quand _enabled == false
# ---------------------------------------------------------------------------

func test_ac_ds_3_mouse_motion_blocked_when_disabled() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame
	var owner_a: Node = _make_owner_node()

	var mouse_emitted: int = 0
	manager.mouse_motion.connect(func(_delta: Vector2) -> void: mouse_emitted += 1)

	manager.request_disable(owner_a)
	assert_bool(manager.enabled).is_false()

	# Act — injecter un InputEventMouseMotion pendant que le manager est désactivé
	_inject_mouse_motion(Vector2(10.0, 0.0))
	await get_tree().physics_frame

	# Assert — mouse_motion ne doit pas être émis (gate story-003, vérifié story-004)
	assert_int(mouse_emitted) \
		.override_failure_message("AC-DS-3: mouse_motion ne doit pas être émis quand _enabled == false") \
		.is_equal(0)

	owner_a.queue_free()
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-DS-4 / AC-CS-4 — Pas de ghost press après re-enable (flags vidés à la transition)
# ---------------------------------------------------------------------------

func test_ac_ds_4_no_ghost_press_after_re_enable() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame
	var owner_a: Node = _make_owner_node()

	manager.request_disable(owner_a)
	assert_bool(manager.enabled).is_false()
	# Note : _update_enabled_state a vidé _pressed_this_tick et _consumed_this_tick sur la transition
	# enabled→disabled (ADR-0004 D-4). Vérifier que le clear a bien eu lieu.
	assert_bool(manager._consumed_this_tick.get(&"jump", false)) \
		.override_failure_message("AC-DS-4 pré-condition: _consumed_this_tick doit être vidé après request_disable") \
		.is_false()

	# Act — injecter un press jump pendant que le manager est désactivé.
	# Le gate _enabled dans _unhandled_input (input_manager.gd:143) doit empêcher le set du flag,
	# donc aucun ghost ne peut survivre à la transition disabled→enabled.
	_inject_action_press(&"jump")
	await get_tree().physics_frame

	# Release → transition enabled=true. Le physics_frame suivant swap les dicts.
	manager.release_enable_request(owner_a)
	assert_bool(manager.enabled).is_true()

	# Avancer un tick pour que le swap se produise et que was_pressed_this_tick soit consultable.
	await get_tree().physics_frame

	# Assert — was_pressed_this_tick doit être false (aucun ghost press).
	# Couvre le chemin complet : clear-on-disable + gate _unhandled_input pendant disabled.
	assert_bool(manager.was_pressed_this_tick(&"jump")) \
		.override_failure_message(
			"AC-DS-4: was_pressed_this_tick(&\"jump\") doit être false après re-enable " +
			"(gate _unhandled_input empêche le set pendant disabled ; clear-on-disable vide les flags pré-existants)"
		) \
		.is_false()

	owner_a.queue_free()
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-CS-2 — Refcount multi-owner : enabled ne passe true qu'à la dernière release
# ---------------------------------------------------------------------------

func test_ac_cs_2_refcount_multi_owner_sequence() -> void:
	# Arrange — 3 owners MVP : Menu, Checkpoint, Cutscene
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame
	var menu: Node = _make_owner_node()
	var checkpoint: Node = _make_owner_node()
	var cutscene: Node = _make_owner_node()

	# Collecter l'historique des états enabled
	var enabled_states: Array[bool] = []
	manager.enabled_changed.connect(func(s: bool) -> void: enabled_states.append(s))

	# Act — séquence : 3 disable, puis 3 release
	manager.request_disable(menu)         # enabled → false (1er blocker)
	manager.request_disable(checkpoint)   # encore false (2ème blocker)
	manager.request_disable(cutscene)     # encore false (3ème blocker)

	# Vérifier l'état intermédiaire
	assert_bool(manager.enabled) \
		.override_failure_message("AC-CS-2: enabled doit être false après 3 request_disable") \
		.is_false()

	manager.release_enable_request(menu)         # encore false (2 blockers restants)
	manager.release_enable_request(checkpoint)   # encore false (1 blocker restant)
	manager.release_enable_request(cutscene)     # enabled → true (plus de blocker)

	# Assert — enabled_changed doit avoir émis : false (1er disable), puis true (dernière release)
	# Les 2ème et 3ème disables n'émettent pas (état déjà false).
	# Les 1ère et 2ème releases n'émettent pas (état reste false).
	assert_bool(manager.enabled) \
		.override_failure_message("AC-CS-2: enabled doit être true après la dernière release") \
		.is_true()

	assert_int(enabled_states.size()) \
		.override_failure_message(
			"AC-CS-2: enabled_changed doit avoir été émis exactement 2 fois (false au 1er disable, true à la dernière release). " +
			"Émissions observées : %s" % str(enabled_states)
		) \
		.is_equal(2)

	assert_bool(enabled_states[0]) \
		.override_failure_message("AC-CS-2: 1ère émission enabled_changed doit être false") \
		.is_false()
	assert_bool(enabled_states[1]) \
		.override_failure_message("AC-CS-2: 2ème émission enabled_changed doit être true") \
		.is_true()

	menu.queue_free()
	checkpoint.queue_free()
	cutscene.queue_free()
	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-CS-3 — Auto-cleanup via tree_exited (queue_free sans release)
# ---------------------------------------------------------------------------

func test_ac_cs_3_auto_cleanup_tree_exited() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame
	var owner_a: Node = _make_owner_node()

	manager.request_disable(owner_a)
	assert_bool(manager.enabled).is_false()
	assert_int(manager._enable_blockers.size()) \
		.override_failure_message("AC-CS-3: _enable_blockers doit contenir 1 entrée après request_disable") \
		.is_equal(1)

	# Act — détruire l'owner sans appeler release_enable_request
	owner_a.queue_free()
	# Laisser Godot propager tree_exited (2 frames pour être sûr)
	await get_tree().process_frame
	await get_tree().process_frame

	# Assert — le blocker a été retiré automatiquement, enabled est revenu à true
	assert_int(manager._enable_blockers.size()) \
		.override_failure_message(
			"AC-CS-3: _enable_blockers doit être vide après tree_exited de l'owner"
		) \
		.is_equal(0)
	assert_bool(manager.enabled) \
		.override_failure_message("AC-CS-3: enabled doit être true après auto-cleanup via tree_exited") \
		.is_true()

	manager.queue_free()

# ---------------------------------------------------------------------------
# Guardrail — Idempotence : même owner N× appels request_disable sans drift
# ---------------------------------------------------------------------------

func test_idempotent_request_disable_same_owner() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame
	var owner_a: Node = _make_owner_node()

	# Act — appeler request_disable 3 fois avec le même owner
	manager.request_disable(owner_a)
	manager.request_disable(owner_a)
	manager.request_disable(owner_a)

	# Assert — seulement 1 entrée dans _enable_blockers (idempotent)
	assert_int(manager._enable_blockers.size()) \
		.override_failure_message(
			"Idempotence: request_disable N× doit produire exactement 1 entrée dans _enable_blockers"
		) \
		.is_equal(1)
	assert_bool(manager.enabled).is_false()

	# Release une seule fois — doit suffire à re-enable
	manager.release_enable_request(owner_a)
	assert_bool(manager.enabled) \
		.override_failure_message(
			"Idempotence: 1 seule release_enable_request doit suffire après N request_disable du même owner"
		) \
		.is_true()
	assert_int(manager._enable_blockers.size()) \
		.override_failure_message("Idempotence: _enable_blockers doit être vide après 1 release") \
		.is_equal(0)

	owner_a.queue_free()
	manager.queue_free()

# ---------------------------------------------------------------------------
# Robustesse — release_enable_request sans prior request → push_warning, pas de crash
# ---------------------------------------------------------------------------

func test_release_without_prior_request_push_warning_safe() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame
	var owner_a: Node = _make_owner_node()

	# Vérifier que le manager est enabled par défaut et sans blockers
	assert_bool(manager.enabled).is_true()
	assert_int(manager._enable_blockers.size()).is_equal(0)

	# Act — appeler release sans jamais avoir appelé request_disable
	# Un push_warning doit être émis mais aucune exception ne doit se lever.
	# GdUnit4 ne peut pas capturer push_warning directement — on teste l'absence de crash
	# et la cohérence de l'état post-appel.
	manager.release_enable_request(owner_a)

	# Assert — le manager reste dans un état cohérent (enabled, pas de crash)
	assert_bool(manager.enabled) \
		.override_failure_message(
			"Robustesse: release_enable_request sans prior request ne doit pas modifier l'état enabled"
		) \
		.is_true()
	assert_int(manager._enable_blockers.size()) \
		.override_failure_message(
			"Robustesse: _enable_blockers doit rester vide après une release sans prior request"
		) \
		.is_equal(0)

	owner_a.queue_free()
	manager.queue_free()
