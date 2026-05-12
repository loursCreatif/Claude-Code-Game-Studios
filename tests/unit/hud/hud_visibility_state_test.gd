# Tests unitaires Story-003 — HUD Visibility State Machine (CONNECT_DEFERRED + _VISIBLE_STATES).
# Couvre AC-HUD-12/13/14/15/16 + EC-HUD-04 cross-validation.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic — automated unit tests (coding-standards.md §Test Evidence).
#
# Pattern : injection de dépendances via _inject_dependencies(gsm, credit)
# AVANT add_child() pour que _ready() utilise les mocks.
# CONNECT_DEFERRED : chaque emit_state_changed() nécessite
# await get_tree().process_frame pour laisser le DEFERRED dispatch.
#
# Naming : test_hud_[scenario]_[expected_result] (test-standards.md).

extends GdUnitTestSuite

var _MockGSM: GDScript = preload("res://tests/unit/hud/mock_gsm.gd")
var _MockCredit: GDScript = preload("res://tests/unit/hud/mock_credit_economy.gd")
var _HUDScript: GDScript = preload("res://src/gameplay/hud/hud_system.gd")

# =============================================================================
# Helpers — instanciation hermétique
# =============================================================================

## Instancie HUD + mocks. gsm_state est l'état initial au boot.
func _make_hud(gsm_state: int, credit_total: int) -> Array:
	var mock_gsm: Node = _MockGSM.new() as Node
	var mock_credit: Node = _MockCredit.new() as Node
	add_child(mock_gsm)
	add_child(mock_credit)
	mock_gsm.set_state(gsm_state)
	mock_credit.set_total(credit_total)

	var hud: Node = _HUDScript.new() as Node
	hud._inject_dependencies(mock_gsm, mock_credit)
	add_child(hud)  # déclenche _ready()

	return [hud, mock_gsm, mock_credit]


func _free_all(nodes: Array) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()

# =============================================================================
# AC-HUD-12 — MENU → canvas caché
# =============================================================================

## GIVEN HUD en état PLAYING au boot, WHEN state_changed(MENU) émis,
## THEN _canvas_layer.visible == false.
## Source : AC-HUD-12 [BLOCKING][AUTO].
func test_hud_state_menu_hides_canvas() -> void:
	# Arrange — boot PLAYING (canvas visible)
	var nodes: Array = _make_hud(1, 0)  # State.PLAYING = 1
	var hud: Node = nodes[0]
	var mock_gsm: Node = nodes[1]

	# Précondition : visible au boot PLAYING
	assert_bool(hud._canvas_layer.visible) \
		.override_failure_message("AC-HUD-12 (precond): canvas doit être visible en état PLAYING") \
		.is_true()

	# Act — transition vers MENU (CONNECT_DEFERRED → await 1 frame)
	mock_gsm.emit_state_changed(0)  # State.MENU = 0
	await get_tree().process_frame

	# Assert
	assert_bool(hud._canvas_layer.visible) \
		.override_failure_message("AC-HUD-12: _canvas_layer.visible doit être false quand état=MENU(0)") \
		.is_false()

	_free_all(nodes)

# =============================================================================
# AC-HUD-13 — PLAYING → canvas visible
# =============================================================================

## GIVEN HUD en état MENU au boot, WHEN state_changed(PLAYING) émis,
## THEN _canvas_layer.visible == true.
## Source : AC-HUD-13 [BLOCKING][AUTO].
func test_hud_state_playing_shows_canvas() -> void:
	# Arrange — boot MENU (canvas caché)
	var nodes: Array = _make_hud(0, 0)  # State.MENU = 0
	var hud: Node = nodes[0]
	var mock_gsm: Node = nodes[1]

	# Précondition : caché au boot MENU
	assert_bool(hud._canvas_layer.visible) \
		.override_failure_message("AC-HUD-13 (precond): canvas doit être caché en état MENU") \
		.is_false()

	# Act — transition vers PLAYING (CONNECT_DEFERRED → await 1 frame)
	mock_gsm.emit_state_changed(1)  # State.PLAYING = 1
	await get_tree().process_frame

	# Assert
	assert_bool(hud._canvas_layer.visible) \
		.override_failure_message("AC-HUD-13: _canvas_layer.visible doit être true quand état=PLAYING(1)") \
		.is_true()

	_free_all(nodes)

# =============================================================================
# AC-HUD-14 — PAUSED → canvas caché + tween killed + scale reset
# =============================================================================

## GIVEN HUD en PLAYING avec un tween actif (déclenché via credits_changed KILL),
## WHEN state_changed(PAUSED) émis,
## THEN _canvas_layer.visible == false ET tween killed ET Label.scale == Vector2.ONE.
## Source : AC-HUD-14 [BLOCKING][AUTO].
func test_hud_state_paused_kills_active_tween_and_resets_scale() -> void:
	# Arrange — boot PLAYING, lancer un tween via credits_changed positif
	var nodes: Array = _make_hud(1, 0)  # State.PLAYING = 1
	var hud: Node = nodes[0]
	var mock_gsm: Node = nodes[1]
	var mock_credit: Node = nodes[2]

	# Lancer un tween : delta > 0 (source KILL=0) → _start_pulse_tween()
	mock_credit.emit_credits_changed(11, 1, 0)  # SourceKind.KILL = 0
	# Le signal credits_changed est SYNC — le tween est lancé immédiatement
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-14 (precond): tween doit être actif après credits_changed KILL") \
		.is_true()

	# Act — transition vers PAUSED (CONNECT_DEFERRED → await 1 frame)
	mock_gsm.emit_state_changed(2)  # State.PAUSED = 2
	await get_tree().process_frame

	# Assert 1 — canvas caché
	assert_bool(hud._canvas_layer.visible) \
		.override_failure_message("AC-HUD-14: _canvas_layer.visible doit être false quand état=PAUSED(2)") \
		.is_false()

	# Assert 2 — tween killed (null ou invalide)
	var tween_dead: bool = hud._active_pulse_tween == null or not hud._active_pulse_tween.is_valid()
	assert_bool(tween_dead) \
		.override_failure_message("AC-HUD-14: _active_pulse_tween doit être killed (null ou invalide) après PAUSED") \
		.is_true()

	# Assert 3 — scale reset
	assert_vector(hud._credit_counter_label.scale) \
		.override_failure_message("AC-HUD-14: Label.scale doit être Vector2.ONE après PAUSED kill-tween") \
		.is_equal(Vector2.ONE)

	_free_all(nodes)

# =============================================================================
# AC-HUD-15 — RESPAWNING → canvas visible + tween actif préservé (Pillar 3)
# =============================================================================

## GIVEN HUD en PLAYING avec un tween actif,
## WHEN state_changed(RESPAWNING) émis,
## THEN _canvas_layer.visible == true ET tween toujours actif (pas de kill).
## Source : AC-HUD-15 [BLOCKING][AUTO] — Pillar 3 (pas de freeze pendant respawn).
func test_hud_state_respawning_shows_canvas_preserves_tween() -> void:
	# Arrange — boot PLAYING, lancer un tween
	var nodes: Array = _make_hud(1, 0)
	var hud: Node = nodes[0]
	var mock_gsm: Node = nodes[1]
	var mock_credit: Node = nodes[2]

	# Lancer un tween actif
	mock_credit.emit_credits_changed(5, 1, 0)  # KILL, delta > 0
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-15 (precond): tween doit être actif avant transition RESPAWNING") \
		.is_true()

	# Act — transition vers RESPAWNING (CONNECT_DEFERRED → await 1 frame)
	mock_gsm.emit_state_changed(3)  # State.RESPAWNING = 3
	await get_tree().process_frame

	# Assert 1 — canvas visible
	assert_bool(hud._canvas_layer.visible) \
		.override_failure_message("AC-HUD-15: _canvas_layer.visible doit être true quand état=RESPAWNING(3)") \
		.is_true()

	# Assert 2 — tween toujours actif (RESPAWNING ne tue pas le tween — Pillar 3)
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("AC-HUD-15: tween doit rester actif après RESPAWNING (Pillar 3 — pas de freeze)") \
		.is_true()

	_free_all(nodes)

# =============================================================================
# AC-HUD-16 — BOSS_DEFEATED → canvas caché
# =============================================================================

## GIVEN HUD en PLAYING, WHEN state_changed(BOSS_DEFEATED) émis,
## THEN _canvas_layer.visible == false.
## Source : AC-HUD-16 [BLOCKING][AUTO].
func test_hud_state_boss_defeated_hides_canvas() -> void:
	# Arrange — boot PLAYING (canvas visible)
	var nodes: Array = _make_hud(1, 0)
	var hud: Node = nodes[0]
	var mock_gsm: Node = nodes[1]

	# Act — transition vers BOSS_DEFEATED (CONNECT_DEFERRED → await 1 frame)
	mock_gsm.emit_state_changed(4)  # State.BOSS_DEFEATED = 4
	await get_tree().process_frame

	# Assert
	assert_bool(hud._canvas_layer.visible) \
		.override_failure_message("AC-HUD-16: _canvas_layer.visible doit être false quand état=BOSS_DEFEATED(4)") \
		.is_false()

	_free_all(nodes)

# =============================================================================
# EC-HUD-04 — cross-validation : credits_changed SYNC + state_changed DEFERRED même tick
# =============================================================================

## GIVEN HUD en PLAYING,
## WHEN credits_changed(11, 1, KILL) émis SYNC + state_changed(RESPAWNING) émis DEFERRED,
## THEN label.text == "11" immédiatement (SYNC) + canvas visible == true après idle frame
##      + tween actif (Pillar 3).
## Source : EC-HUD-04 cross-validation [BLOCKING][AUTO].
func test_hud_credits_sync_state_deferred_same_tick_cross_validation() -> void:
	# Arrange — boot PLAYING
	var nodes: Array = _make_hud(1, 0)
	var hud: Node = nodes[0]
	var mock_gsm: Node = nodes[1]
	var mock_credit: Node = nodes[2]

	# Act PART 1 — credits_changed SYNC (connexion directe, pas DEFERRED)
	mock_credit.emit_credits_changed(11, 1, 0)  # total=11, delta=1 (KILL), source=KILL

	# Assert label SYNC — visible immédiatement, sans await
	assert_str(hud._credit_counter_label.text) \
		.override_failure_message("EC-HUD-04: label.text doit être '11' immédiatement après credits_changed SYNC") \
		.is_equal("11")

	# Tween lancé par credits_changed SYNC (delta > 0)
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("EC-HUD-04 (precond): tween doit être actif après credits_changed KILL SYNC") \
		.is_true()

	# Act PART 2 — state_changed DEFERRED (même tick logique)
	mock_gsm.emit_state_changed(3)  # State.RESPAWNING = 3

	# Attendre la frame DEFERRED
	await get_tree().process_frame

	# Assert canvas visible après DEFERRED dispatch
	assert_bool(hud._canvas_layer.visible) \
		.override_failure_message("EC-HUD-04: _canvas_layer.visible doit être true après state_changed(RESPAWNING) DEFERRED") \
		.is_true()

	# Assert tween toujours actif (RESPAWNING ne kill pas — Pillar 3)
	assert_bool(hud._active_pulse_tween != null and hud._active_pulse_tween.is_valid()) \
		.override_failure_message("EC-HUD-04: tween doit rester actif après RESPAWNING (Pillar 3)") \
		.is_true()

	_free_all(nodes)
