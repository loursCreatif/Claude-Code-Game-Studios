# ShopController — story-002 catalogue MVP + cost formula F-CRD-3 0-based.
# class_name ShopControllerScript : suffixe -Script anti-collision (memory
# `feedback_godot_class_name_autoload_collision`). Pas un autoload.
# Hydration / purchase / signals : stories 003-007.
class_name ShopControllerScript
extends Control

const N_UPGRADES_MVP: int = 2

const _CATALOG: Array[Dictionary] = [
	{ "id": &"double_jump",     "display_name": "Saut Double",     "n_index": 0 },
	{ "id": &"dash_horizontal", "display_name": "Dash Horizontal", "n_index": 1 },
]

# Story-013 — animation timings (§J.3 / §J.5).
const _COUNTER_TWEEN_DURATION_S: float = 0.300    # §J.3 counter EASE_OUT TRANS_QUAD
const _PULSE_DURATION_S: float = 0.150            # §J.5 pulse achat scale 1.0→1.03→1.0
const _PULSE_SCALE: float = 1.03
const _SHAKE_DURATION_S: float = 0.200            # §J.5 shake DISABLED ±4 px
const _SHAKE_AMPLITUDE_PX: float = 4.0
const _SHAKE_COOLDOWN_MS: int = 400               # EC-SHP-30 anti-spam ≤ 3 Hz a11y

# TODO Sprint 2 — replace fallbacks par CreditEconomy.BASE_UPGRADE_COST /
# TIER_COST_STEP quand exposés (Credit Economy story-008+).
const _BASE_COST_FALLBACK: int = 20
const _TIER_COST_STEP_FALLBACK: int = 20

const _SAVE_KEY: String = "owned_upgrades"
const _MAIN_MENU_SCENE_PATH: String = "res://scenes/menus/main_menu.tscn"

var _owned_upgrades: Array[StringName] = []
var _closing: bool = false    # story-008 — double-press guard EC-SHP-18
var _ready_completed: bool = false    # story-009 — guard ESC pendant LOADING (AC-SHP-27)

# Story-008 test seam — callable indirection pour `GameStateManager.request_scene_transition`.
# Production runtime : null → fallback appel direct GSM. Tests : injection d'une
# Callable qui capture l'appel sans déclencher `change_scene_to_file` destructif.
var _transition_callable: Callable = Callable()
var _credit_display_text: String = ""    # story-004 — pull depuis CreditEconomy
var _purchase_in_progress: bool = false  # story-005/006 — double-click guard

# Story-007 — affordability state recalculée par handler credits_changed.
# Map id → bool (true = peut acheter, false = solde insuffisant ou owned).
var _affordable_state: Dictionary[StringName, bool] = {}

# Test seam — journal d'ordre d'appels (5b → 5c) pour AC-SHP-8 séquencement strict.
# Production runtime : pas d'overhead (append seulement debug-introspectable).
var _call_order_log: Array[String] = []

# Story-013 — animations state.
# `_reduce_motion` Tier 3 hook (EC-SHP-29) : MVP par défaut false ; Accessibility
# Manager Tier 3 pourra le passer à true → counter tween hard-set, pulse/shake skip.
var _reduce_motion: bool = false
# `_displayed_credit_value` track la valeur affichée (départ counter tween).
var _displayed_credit_value: int = 0
# `_shake_cooldown_until_ms` map id → ticks_msec déadline shake (EC-SHP-30 anti-spam).
var _shake_cooldown_until_ms: Dictionary[StringName, int] = {}
# `_animation_log` test seam — track événements anim (counter/pulse/shake/skip).
var _animation_log: Array[String] = []


func _ready() -> void:
	if OS.has_feature("debug"):
		assert(_CATALOG.size() == N_UPGRADES_MVP,
			"Catalogue size %d != N_UPGRADES_MVP %d" % [_CATALOG.size(), N_UPGRADES_MVP])
	_hydrate_owned_upgrades()
	_pull_initial_credit_display()
	# Story-007 — connect credits_changed CONNECT_DEFERRED (verrou AC-SHP-4 anti-réentrance EC-SHP-23)
	_connect_credits_changed_deferred()
	# Compute initial affordability state (avant tout signal)
	_recalc_affordability(CreditEconomy.get_total())
	# Story-009 — guard ESC pendant LOADING : flag à la toute fin de _ready()
	_ready_completed = true


# Story-009 — ESC = Continue (R-SHP-11 anti-friction Pillar 1).
# Action `ui_cancel` Godot stdlib (ESC + B/Circle gamepad mappés InputMap).
# Délègue à `_on_continue_pressed` qui contient déjà `_closing` guard EC-SHP-18.
# AC-SHP-27 : pendant LOADING (`_ready_completed == false`), ESC ignoré.
func _unhandled_input(event: InputEvent) -> void:
	if not _ready_completed:
		return    # AC-SHP-27 LOADING guard
	if event.is_action_pressed(&"ui_cancel"):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		_on_continue_pressed()


# Test seam story-009 — manipulation `_ready_completed` flag pour AC-SHP-27.
func set_ready_completed_for_test(value: bool) -> void:
	_ready_completed = value


func get_ready_completed_for_test() -> bool:
	return _ready_completed


func _connect_credits_changed_deferred() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed):
		return    # idempotent — ré-instanciation safe
	var err: int = CreditEconomy.credits_changed.connect(
		_on_credits_changed, CONNECT_DEFERRED)
	if err != OK:
		push_error("ShopController: failed to connect credits_changed (err=%d)" % err)


# Story-007 handler — invoqué via DEFERRED idle frame (anti-réentrance EC-SHP-23).
# Update label cache + recalc affordability tous BuyButtons non-owned (F-SHP-2 + EC-SHP-14).
# Story-013 — hook counter tween (§J.3) sur changement solde.
func _on_credits_changed(total: int, _delta: int, _source: int) -> void:
	_animate_credit_counter(_displayed_credit_value, total)
	_credit_display_text = str(total)
	_recalc_affordability(total)


# Recalc affordability state pour chaque entry catalog non-owned.
# Owned → false (already disabled OWNED, pas affordable=achat).
# Non-owned → total >= cost_n.
func _recalc_affordability(total: int) -> void:
	for entry in _CATALOG:
		var id: StringName = entry["id"]
		var n_index: int = entry["n_index"]
		if _owned_upgrades.has(id):
			_affordable_state[id] = false
			continue
		var cost: int = _compute_cost(n_index)
		_affordable_state[id] = total >= cost


# Story-004 — boot pull pattern (ADR-0007 D-9, EC-SHP-4 BOOT_HYDRATE perdu protégé).
# Lecture passive non-mutante du total credits courant. À appeler dans _ready()
# AVANT toute connexion `credits_changed` ou `await`. Stocke le texte formaté
# pour assignation au CreditValueLabel quand le scene est ready (story-005+).
func _pull_initial_credit_display() -> void:
	var total: int = CreditEconomy.get_total()
	_credit_display_text = str(total)
	_displayed_credit_value = total    # story-013 — initial value pour counter tween


# Test seam — lecture publique du texte credit affiché (post-pull initial).
func get_credit_display_text() -> String:
	return _credit_display_text


# Story-003 : boot hydration depuis SaveLoadSystem.
# SaveLoadSystem.load_string_array filtre déjà les éléments non-StringName/String
# côté SaveLoad (ADR-0010 D-2 + R-SAV-12), donc le retour typé Array[StringName]
# est trusty. IDs inconnus (Tier 2+) conservés silencieusement (EC-SHP-8 forward-safe).
func _hydrate_owned_upgrades() -> void:
	_owned_upgrades = SaveLoadSystem.load_string_array(
		_SAVE_KEY, [] as Array[StringName])


# Test seam — get_owned_upgrades() lecture publique pour assert tests integration.
func get_owned_upgrades() -> Array[StringName]:
	return _owned_upgrades.duplicate() as Array[StringName]


func _compute_cost(n: int) -> int:
	if n < 0:
		push_warning("ShopSystem: _compute_cost called with negative n (%d)" % n)
		return 0
	if n >= N_UPGRADES_MVP:
		push_error("ShopSystem: _compute_cost n=%d > MAX_UPGRADE_INDEX=%d" % [n, N_UPGRADES_MVP - 1])
		return 0
	return _BASE_COST_FALLBACK + _TIER_COST_STEP_FALLBACK * n


# Story-005 — purchase cycle 6 étapes déterministes SYNC.
# (1) guard already_owned (R-SHP-7 silent no-op idempotence partielle)
# (2) guard _purchase_in_progress (story-006 double-click)
# (3) _compute_cost + EC-SHP-2 assert cost > 0
# (4) pre-check affordability passive get_total() < cost (F-SHP-2 non-mutant)
# (5a) try_spend SYNC atomique  (5b) _owned.append + save_string_array
# (5c) Upgrade.apply_upgrade SYNC (chain-blocked Upgrade r1 ✅ Sprint 1 ready)
# (6) BuyButton.disabled=true (test seam : skip if button absent)
# Aucun await/yield entre étapes — atomicité call stack EC-SHP-23.
func _on_buy_pressed(id: StringName, n_index: int) -> void:
	# Étape 1 — already owned silent no-op (R-SHP-7)
	if _owned_upgrades.has(id):
		return

	# Étape 2 — double-click guard (story-006 raffinement)
	if _purchase_in_progress:
		return

	# Étape 3 — cost computation + EC-SHP-2 guard.
	# `_compute_cost` retourne 0 sur n_index invalide (négatif/OOB) avec
	# warning/error. Early return sans crash : assert remplacé par soft guard
	# pour rester runtime-safe (debug + release identiques).
	var cost: int = _compute_cost(n_index)
	if cost <= 0:
		return    # EC-SHP-2: cost invalide ou n_index pathologique

	# Étape 4 — pre-check affordability passive (F-SHP-2 — pas de mutation)
	if CreditEconomy.get_total() < cost:
		# Story-013 — DISABLED click feedback (§J.5 shake + EC-SHP-30 cooldown)
		_animate_disabled_shake(id, n_index)
		return

	_purchase_in_progress = true

	# Étape 5a — atomic try_spend SYNC (peut échouer si race solde EC-SHP-1)
	if not CreditEconomy.try_spend(cost):
		_purchase_in_progress = false
		return

	# Étape 5b — RAM mark + persist disk SYNC (ordre 5b AVANT 5c — EC-SHP-16/23 atomicity)
	_owned_upgrades.append(id)
	SaveLoadSystem.save_string_array(_SAVE_KEY, _owned_upgrades)
	_call_order_log.append("save")

	# Étape 5c — gameplay activation SYNC
	Upgrade.apply_upgrade(id)
	_call_order_log.append("apply")

	# Étape 6 — UI button disable (test seam — skip if not in scene tree)
	_disable_buy_button_for(id)
	# Story-013 — pulse achat (§J.5 scale 1.0 → 1.03 → 1.0 sur 150 ms)
	_animate_purchase_pulse(id, n_index)

	_purchase_in_progress = false


# Story-005 helper — résout BuyButton via NodePath unique-name OU skip silently
# si pas attaché au scene (test seam pour unit tests hors scene tree).
func _disable_buy_button_for(id: StringName) -> void:
	var button_name: StringName = "BuyButton_%s" % id
	var button: Button = get_node_or_null(NodePath("%" + str(button_name))) as Button
	if button == null:
		return    # scene-attach context absent (story-005+ scene wiring)
	button.disabled = true
	button.text = "POSSÉDÉ"


# Test seam — lecture publique journal séquencement (AC-SHP-8 ordre 5b→5c).
func get_call_order_log() -> Array[String]:
	return _call_order_log.duplicate() as Array[String]


# Test seam — reset entre tests (autoload-free instance bare).
func reset_call_order_log_for_test() -> void:
	_call_order_log.clear()


# Test seams story-006 — accès `_purchase_in_progress` pour simuler race
# window in-flight (impossible en GDScript SYNC sans injection manuelle).
func set_purchase_in_progress_for_test(value: bool) -> void:
	_purchase_in_progress = value


func get_purchase_in_progress_for_test() -> bool:
	return _purchase_in_progress


# Test seam story-007 — lecture publique état affordability (post-recalc).
func is_affordable(id: StringName) -> bool:
	return _affordable_state.get(id, false)


# Story-008 — Continue button handler (R-SHP-10 + EC-SHP-18 double-press guard).
# Toujours actif (jamais disabled par état upgrade). Click → GSM scene transition
# vers main menu. _closing flag bloque double-press dans la fenêtre transition.
func _on_continue_pressed() -> void:
	if _closing:
		return    # EC-SHP-18 double-press silent guard
	_closing = true
	if _transition_callable.is_valid():
		_transition_callable.call(_MAIN_MENU_SCENE_PATH)
	else:
		GameStateManager.request_scene_transition(_MAIN_MENU_SCENE_PATH)


# Test seams story-008 — accès `_closing` flag + injection callable.
func set_transition_callable_for_test(c: Callable) -> void:
	_transition_callable = c


func get_closing_for_test() -> bool:
	return _closing


func reset_closing_for_test() -> void:
	_closing = false


# =============================================================================
# Story-013 — animations Tween (counter / pulse / shake) + reduce motion hook
# =============================================================================

# §J.3 counter tween — solde label tween 300 ms `EASE_OUT TRANS_QUAD`.
# `_reduce_motion=true` → hard-set immédiat (EC-SHP-29).
# Hors scene tree (test) ou label absent → log "counter" sans créer Tween (skip safe).
func _animate_credit_counter(old_value: int, new_value: int) -> void:
	if old_value == new_value:
		return    # no-op si delta nul (pas d'anim inutile)
	if _reduce_motion:
		_displayed_credit_value = new_value
		_animation_log.append("counter_skip_reduce_motion")
		return
	_animation_log.append("counter")
	var label: Label = _find_credit_value_label()
	if label == null:
		_displayed_credit_value = new_value    # update tracker même hors scene
		return
	if not is_inside_tree():
		_displayed_credit_value = new_value
		return
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)    # AC-SHP-31
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(
		func(v: float) -> void: label.text = str(int(v)),
		float(old_value), float(new_value), _COUNTER_TWEEN_DURATION_S
	)
	_displayed_credit_value = new_value


# §J.5 pulse achat — UpgradeCard scale 1.0 → 1.03 → 1.0 sur 150 ms `TRANS_SINE`.
# `_reduce_motion=true` → skip (EC-SHP-29).
# Hors scene tree → log "pulse_skip_no_card" (test seam).
func _animate_purchase_pulse(_id: StringName, n_index: int) -> void:
	if _reduce_motion:
		_animation_log.append("pulse_skip_reduce_motion")
		return
	var card: PanelContainer = _find_upgrade_card(n_index)
	if card == null or not is_inside_tree():
		_animation_log.append("pulse_skip_no_card")
		return
	_animation_log.append("pulse")
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)    # AC-SHP-31
	tween.set_trans(Tween.TRANS_SINE)
	var half: float = _PULSE_DURATION_S * 0.5
	tween.tween_property(card, "scale", Vector2.ONE * _PULSE_SCALE, half)
	tween.tween_property(card, "scale", Vector2.ONE, half)


# §J.5 shake DISABLED — `position:x : 0→4→-4→2→0` sur 200 ms `TRANS_SINE`.
# EC-SHP-30 cooldown 400 ms anti-spam (≤ 3 Hz a11y).
# `_reduce_motion=true` → skip (EC-SHP-29).
func _animate_disabled_shake(id: StringName, n_index: int) -> void:
	if _reduce_motion:
		_animation_log.append("shake_skip_reduce_motion")
		return
	var now_ms: int = Time.get_ticks_msec()
	if _shake_cooldown_until_ms.get(id, 0) > now_ms:
		_animation_log.append("shake_skip_cooldown")
		return    # EC-SHP-30 cooldown actif
	_shake_cooldown_until_ms[id] = now_ms + _SHAKE_COOLDOWN_MS
	var card: PanelContainer = _find_upgrade_card(n_index)
	if card == null or not is_inside_tree():
		_animation_log.append("shake_skip_no_card")
		return
	_animation_log.append("shake")
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)    # AC-SHP-31
	tween.set_trans(Tween.TRANS_SINE)
	var quart: float = _SHAKE_DURATION_S * 0.25
	tween.tween_property(card, "position:x", _SHAKE_AMPLITUDE_PX, quart)
	tween.tween_property(card, "position:x", -_SHAKE_AMPLITUDE_PX, quart)
	tween.tween_property(card, "position:x", _SHAKE_AMPLITUDE_PX * 0.5, quart)
	tween.tween_property(card, "position:x", 0.0, quart)


# Helpers — résolution scene tree (skip silent si bare instance test).
func _find_credit_value_label() -> Label:
	return get_node_or_null(NodePath(
		"ShopRoot/MarginContainer/VBoxContainer/CreditDisplay/CreditValueLabel"
	)) as Label


func _find_upgrade_card(n_index: int) -> PanelContainer:
	return get_node_or_null(NodePath(
		"ShopRoot/MarginContainer/VBoxContainer/UpgradeList/UpgradeCard_%d" % n_index
	)) as PanelContainer


# Test seams story-013.
func set_reduce_motion_for_test(value: bool) -> void:
	_reduce_motion = value


func get_reduce_motion_for_test() -> bool:
	return _reduce_motion


func get_animation_log() -> Array[String]:
	return _animation_log.duplicate() as Array[String]


func reset_animation_log_for_test() -> void:
	_animation_log.clear()


func get_shake_cooldown_until_ms_for_test(id: StringName) -> int:
	return _shake_cooldown_until_ms.get(id, 0)


func reset_shake_cooldown_for_test() -> void:
	_shake_cooldown_until_ms.clear()
