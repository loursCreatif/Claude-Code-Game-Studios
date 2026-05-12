class_name HUDSystemScript
extends Node

## HUDSystem — Presentation layer autoload. Outbound-only (R-HUD-12).
##
## Pull boot pattern (ADR-0007 D-9) : lit get_current_state() + get_total()
## de façon synchrone dans _ready(), jamais d'attente signal game_booted.
## CanvasLayer.layer = 50 (< 100 réservé GSM) — R-HUD-11.
##
## Autoload position : LAST dans project.godot (après LevelSystem).
## Forbidden (Control Manifest Presentation) : AnimationPlayer, Engine.time_scale,
## tout consumer downstream (CombatSystem, LevelSystem, etc.).
##
## Stories : story-001 (skeleton boot) → 002 (credits handler) → 003 (visibility).

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const HUD_CANVAS_LAYER: int = 50
const HUD_MARGIN_RIGHT_PX: int = 24
const HUD_MARGIN_TOP_PX: int = 20

## Durées pulse différenciées par source (R-HUD-5 r1.1 + Pillar 4 différenciation perceptive).
const CREDIT_COUNTER_TWEEN_KILL_MS: int = 100
const CREDIT_COUNTER_TWEEN_SECRET_MS: int = 150
const PULSE_SCALE_MAGNITUDE: float = 1.05

## États où le HUD est visible — PLAYING (gameplay actif) + RESPAWNING (Pillar 3 transition invisible).
const _VISIBLE_STATES: Array[int] = [1, 3]  # State.PLAYING, State.RESPAWNING
const _STATE_PAUSED: int = 2  # State.PAUSED — déclenche tween kill (R-HUD-10)

# ---------------------------------------------------------------------------
# State (private)
# ---------------------------------------------------------------------------

var _canvas_layer: CanvasLayer
var _credit_counter_label: Label

## Active pulse tween — ref kept pour multi-kill collision kill + restart.
## null ou is_valid()==false quand aucun tween en cours.
var _active_pulse_tween: Tween = null

## Dependency injection refs — overridden by tests, fallback to autoloads in prod.
var _gsm_ref: Node = null
var _credit_ref: Node = null

# ---------------------------------------------------------------------------
# Virtual
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Fallback production : utilise les vrais autoloads si pas injectés
	if _gsm_ref == null:
		assert(GameStateManager != null, "HUD: GSM autoload missing — check project.godot order")
		_gsm_ref = GameStateManager
	if _credit_ref == null:
		assert(CreditEconomy != null, "HUD: CreditEconomy autoload missing — check project.godot order")
		_credit_ref = CreditEconomy

	# CanvasLayer enfant — R-HUD-11 layer=50 < 100
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = HUD_CANVAS_LAYER
	_canvas_layer.name = "HUDCanvasLayer"
	add_child(_canvas_layer)

	var container: Control = Control.new()
	container.name = "CreditCounterContainer"
	container.set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_TOP_RIGHT)
	container.offset_right = -HUD_MARGIN_RIGHT_PX
	container.offset_top = HUD_MARGIN_TOP_PX
	_canvas_layer.add_child(container)

	_credit_counter_label = Label.new()
	_credit_counter_label.name = "CreditCounterLabel"
	container.add_child(_credit_counter_label)

	# R-HUD-2 pull boot synchrone — jamais de signal game_booted (n'existe pas, GSM R-12)
	var initial_state: int = _gsm_ref.get_current_state()
	var initial_total: int = _credit_ref.get_total()
	_credit_counter_label.text = str(initial_total)
	_apply_visibility(initial_state)

	# Connexions : credits_changed SYNC (Pillar 1 latence), state_changed DEFERRED (consumer lourd)
	_credit_ref.credits_changed.connect(_on_credits_changed)
	_gsm_ref.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)

	print("[HUDSystem] boot — state=%d total=%d layer=%d" % [initial_state, initial_total, HUD_CANVAS_LAYER])

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Injecte des dépendances de remplacement pour l'isolation des tests.
## Appeler AVANT add_child() pour que _ready() utilise les mocks.
func _inject_dependencies(gsm: Node, credit: Node) -> void:
	_gsm_ref = gsm
	_credit_ref = credit

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _apply_visibility(state: int) -> void:
	# R-HUD-8 — visibility table binaire : PLAYING + RESPAWNING true, autres false
	_canvas_layer.visible = state in _VISIBLE_STATES

	# R-HUD-10 — tween en cours killed quand PAUSED (EC-HUD-06 propreté visuelle)
	if state == _STATE_PAUSED and _active_pulse_tween != null and _active_pulse_tween.is_valid():
		_active_pulse_tween.kill()
		_active_pulse_tween = null
		_credit_counter_label.scale = Vector2.ONE

# ---------------------------------------------------------------------------
# Signal callbacks (stubs — implémentés story-002 et story-003)
# ---------------------------------------------------------------------------

func _on_credits_changed(total: int, delta: int, source: int) -> void:
	# R-HUD-3 SYNC same-frame — hard set du chiffre AVANT tween (toujours).
	_credit_counter_label.text = str(total)

	# R-HUD-7 BOOT_HYDRATE garde-fou — delta==0 jamais de tween.
	if delta == 0:
		return

	# R-HUD-6 SPEND_SHOP — delta<0 hard set sans tween, scale reset.
	if delta < 0:
		if _active_pulse_tween != null and _active_pulse_tween.is_valid():
			_active_pulse_tween.kill()
			_active_pulse_tween = null
		_credit_counter_label.scale = Vector2.ONE
		return

	# R-HUD-5 increment positif — tween différencié source (durée stub MVP).
	_start_pulse_tween(source)


## Lance le tween de pulse sur le label compteur.
## Multi-kill collision (AC-HUD-07/19/20 + AC-HUD-36 (e)) : kill le tween précédent avant création.
## Durée différenciée par source (R-HUD-5 r1.1) : KILL=100ms / SECRET=150ms (Pillar 4).
func _start_pulse_tween(source: int) -> void:
	# Multi-kill collision (AC-HUD-07/19/20 + AC-HUD-36 (e)) — kill tween précédent
	if _active_pulse_tween != null and _active_pulse_tween.is_valid():
		_active_pulse_tween.kill()

	# R-HUD-5 r1.1 — durée différenciée par source
	var duration_ms: int = CREDIT_COUNTER_TWEEN_KILL_MS  # default KILL
	if source == 1:  # SourceKind.SECRET == 1
		duration_ms = CREDIT_COUNTER_TWEEN_SECRET_MS

	# Invariant balance debug-only assert (AC-HUD-36 (c))
	assert(CREDIT_COUNTER_TWEEN_SECRET_MS > CREDIT_COUNTER_TWEEN_KILL_MS, \
		"Pillar 4 différenciation perceptive cassée — secret pulse durée doit dépasser kill pulse durée")

	var half_duration: float = (duration_ms / 1000.0) / 2.0

	_active_pulse_tween = create_tween()
	_active_pulse_tween.set_ignore_time_scale(true)  # OQ-HUD-5 wall-clock invariance
	_active_pulse_tween.tween_property(_credit_counter_label, "scale", \
		Vector2(PULSE_SCALE_MAGNITUDE, PULSE_SCALE_MAGNITUDE), half_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_active_pulse_tween.tween_property(_credit_counter_label, "scale", Vector2.ONE, half_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _on_state_changed(new_state: int) -> void:
	_apply_visibility(new_state)
