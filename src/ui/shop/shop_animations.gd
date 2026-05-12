## ShopAnimations — helper animations story-013 (counter / pulse / shake).
## Possédé et instancié par ShopControllerScript (composition). Reçoit une
## référence injectée au Control parent pour create_tween() + get_node_or_null()
## + is_inside_tree(). PAS un autoload — pas de class_name (bypass class cache CI).
## Pattern miroir audio_combat_handler.gd (RefCounted + référence injectée).
## Tween sur scale / position:x autorisé — pas de volume_db (hors scope audio ADR-0009).

# NOTE : pas de `class_name` — référencé via `const ShopAnimations := preload(...)`
# dans shop_controller.gd pour bypass l'absence de class cache en CI GdUnit4.
# Miroir pattern AudioCombatHandler (audio_combat_handler.gd).

extends RefCounted


# ---------------------------------------------------------------------------
# Animation constants (§J.3 / §J.5 story-013)
# ---------------------------------------------------------------------------

const COUNTER_TWEEN_DURATION_S: float = 0.300    # §J.3 counter EASE_OUT TRANS_QUAD
const PULSE_DURATION_S: float = 0.150            # §J.5 pulse achat scale 1.0→1.03→1.0
const PULSE_SCALE: float = 1.03
const SHAKE_DURATION_S: float = 0.200            # §J.5 shake DISABLED ±4 px
const SHAKE_AMPLITUDE_PX: float = 4.0
const SHAKE_COOLDOWN_MS: int = 400               # EC-SHP-30 anti-spam ≤ 3 Hz a11y


# ---------------------------------------------------------------------------
# Injected references
# ---------------------------------------------------------------------------

## Référence injectée au ShopControllerScript (Control) — pour create_tween(),
## get_node_or_null(), is_inside_tree(). Injectée dans ShopControllerScript._ready().
var _owner: Control = null

## Référence injectée au flag reduce_motion de ShopControllerScript.
## Lue via Callable pour éviter toute dépendance cyclique ou polling d'état.
## Production : Callable(shop_controller, "get_reduce_motion_for_test") ou accès direct.
var _get_reduce_motion: Callable = Callable()

## Référence injectée au journal d'animation (test seam).
## Partagé avec ShopControllerScript._animation_log.
var _animation_log: Array[String] = []

## Référence injectée à la map cooldown shake (test seam).
## Partagé avec ShopControllerScript._shake_cooldown_until_ms.
var _shake_cooldown_until_ms: Dictionary[StringName, int] = {}

## Référence injectée à la variable _displayed_credit_value de ShopControllerScript.
## Mise à jour via Callable pour éviter le couplage bidirectionnel.
var _set_displayed_credit_value: Callable = Callable()


# ---------------------------------------------------------------------------
# Public animation API
# ---------------------------------------------------------------------------

## §J.3 counter tween — solde label tween 300 ms EASE_OUT TRANS_QUAD.
## reduce_motion=true → hard-set immédiat (EC-SHP-29).
## Hors scene tree (test) ou label absent → log "counter" sans créer Tween (skip safe).
func animate_credit_counter(old_value: int, new_value: int) -> void:
	if old_value == new_value:
		return    # no-op si delta nul (pas d'anim inutile)
	if _get_reduce_motion.call():
		_set_displayed_credit_value.call(new_value)
		_animation_log.append("counter_skip_reduce_motion")
		return
	_animation_log.append("counter")
	var label: Label = _find_credit_value_label()
	if label == null:
		_set_displayed_credit_value.call(new_value)    # update tracker même hors scene
		return
	if not _owner.is_inside_tree():
		_set_displayed_credit_value.call(new_value)
		return
	var tween: Tween = _owner.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)    # AC-SHP-31
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(
		func(v: float) -> void: label.text = str(int(v)),
		float(old_value), float(new_value), COUNTER_TWEEN_DURATION_S
	)
	_set_displayed_credit_value.call(new_value)


## §J.5 pulse achat — UpgradeCard scale 1.0 → 1.03 → 1.0 sur 150 ms TRANS_SINE.
## reduce_motion=true → skip (EC-SHP-29).
## Hors scene tree → log "pulse_skip_no_card" (test seam).
func animate_purchase_pulse(_id: StringName, n_index: int) -> void:
	if _get_reduce_motion.call():
		_animation_log.append("pulse_skip_reduce_motion")
		return
	var card: PanelContainer = _find_upgrade_card(n_index)
	if card == null or not _owner.is_inside_tree():
		_animation_log.append("pulse_skip_no_card")
		return
	_animation_log.append("pulse")
	var tween: Tween = _owner.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)    # AC-SHP-31
	tween.set_trans(Tween.TRANS_SINE)
	var half: float = PULSE_DURATION_S * 0.5
	tween.tween_property(card, "scale", Vector2.ONE * PULSE_SCALE, half)
	tween.tween_property(card, "scale", Vector2.ONE, half)


## §J.5 shake DISABLED — position:x : 0→4→-4→2→0 sur 200 ms TRANS_SINE.
## EC-SHP-30 cooldown 400 ms anti-spam (≤ 3 Hz a11y).
## reduce_motion=true → skip (EC-SHP-29).
func animate_disabled_shake(id: StringName, n_index: int) -> void:
	if _get_reduce_motion.call():
		_animation_log.append("shake_skip_reduce_motion")
		return
	var now_ms: int = Time.get_ticks_msec()
	if _shake_cooldown_until_ms.get(id, 0) > now_ms:
		_animation_log.append("shake_skip_cooldown")
		return    # EC-SHP-30 cooldown actif
	_shake_cooldown_until_ms[id] = now_ms + SHAKE_COOLDOWN_MS
	var card: PanelContainer = _find_upgrade_card(n_index)
	if card == null or not _owner.is_inside_tree():
		_animation_log.append("shake_skip_no_card")
		return
	_animation_log.append("shake")
	var tween: Tween = _owner.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)    # AC-SHP-31
	tween.set_trans(Tween.TRANS_SINE)
	var quart: float = SHAKE_DURATION_S * 0.25
	tween.tween_property(card, "position:x", SHAKE_AMPLITUDE_PX, quart)
	tween.tween_property(card, "position:x", -SHAKE_AMPLITUDE_PX, quart)
	tween.tween_property(card, "position:x", SHAKE_AMPLITUDE_PX * 0.5, quart)
	tween.tween_property(card, "position:x", 0.0, quart)


# ---------------------------------------------------------------------------
# Scene tree helpers (résolution node — skip silent si bare instance test)
# ---------------------------------------------------------------------------

func _find_credit_value_label() -> Label:
	return _owner.get_node_or_null(NodePath(
		"ShopRoot/MarginContainer/VBoxContainer/CreditDisplay/CreditValueLabel"
	)) as Label


func _find_upgrade_card(n_index: int) -> PanelContainer:
	return _owner.get_node_or_null(NodePath(
		"ShopRoot/MarginContainer/VBoxContainer/UpgradeList/UpgradeCard_%d" % n_index
	)) as PanelContainer
