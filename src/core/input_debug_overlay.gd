# InputDebugOverlay — Overlay debug F3 affichant latency p99, dernière action et mouse mode.
# Instancié automatiquement par InputManager._ready() en build debug uniquement.
# Binary gate release : queue_free() en _ready() si not OS.has_feature("debug").
# ADR-0004 D-9 (fixtures debug-only via OS.has_feature), D-5 (one-way focus signals).
# Story-009.
class_name InputDebugOverlay
extends CanvasLayer

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Seuil d'alerte latence en millisecondes. Si p99 dépasse ce seuil,
## LatencyLabel passe en rouge. Valeur debug relâchée (5× la cible release 0.1 ms).
## ADR-0004 D-8, GDD Tuning Knobs.
const LATENCY_ANOMALY_THRESHOLD_MS: float = 0.5

## Durée d'affichage d'une action pressée avant retour à "action: —".
## Reinitialisé à chaque presse d'action. Valeur en secondes.
const ACTION_LABEL_TIMEOUT_SEC: float = 0.5

## Intervalle de rafraîchissement de LatencyLabel via accumulator.
## get_latency_p99_ms() est coûteux (tri) — appelé 1×/s, pas chaque frame.
const LATENCY_UPDATE_INTERVAL_SEC: float = 1.0

# ---------------------------------------------------------------------------
# @onready — node references
# ---------------------------------------------------------------------------

@onready var _latency_label: Label = $LatencyLabel
@onready var _action_label: Label = $ActionLabel
@onready var _mouse_mode_label: Label = $MouseModeLabel

# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

## Accumulateur pour le gate 1 Hz du rafraîchissement latency.
var _latency_accum: float = 0.0

## Timer décroissant pour l'effacement de ActionLabel après ACTION_LABEL_TIMEOUT_SEC.
## 0.0 = aucune action en attente d'affichage.
var _action_clear_timer: float = 0.0

## Dirty-flag pour MouseModeLabel — évite la réécriture chaque frame (zero-alloc).
## Init -1 pour forcer la 1re écriture (-1 ≠ false ≠ true).
var _last_mouse_captured: int = -1

## Strings pré-allouées pour MouseModeLabel — évite `"mouse_mode: %s" % ...` par frame.
const _MOUSE_TEXT_CAPTURED: String = "mouse_mode: CAPTURED"
const _MOUSE_TEXT_VISIBLE: String = "mouse_mode: VISIBLE"

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Binary gate release : si pas en debug, queue_free() supprime le noeud
	# avant qu'il ne soit rendu. Garantit zéro coût runtime en release —
	# pas juste visible = false (qui ne supprime pas le node du tree).
	# ADR-0004 D-9, AC-DBG-2.
	if not OS.has_feature("debug"):
		queue_free()
		return

	# Overlay OFF par défaut — F3 toggle via _unhandled_input.
	visible = false

	# Connecter les signaux gameplay InputManager → handler unique.
	# .bind(&"name") passe le nom d'action en paramètre supplémentaire.
	# Signal-only pattern (ADR-0004 D-1) — pas de polling ici.
	InputManager.jump_pressed.connect(_on_action_pressed.bind(&"jump"))
	InputManager.dash_pressed.connect(_on_action_pressed.bind(&"dash"))
	InputManager.attack_pressed.connect(_on_action_pressed.bind(&"attack"))
	InputManager.restart_pressed.connect(_on_action_pressed.bind(&"restart"))

## Bascule la visibilité de l'overlay sur presse de debug_toggle (F3).
## Pas de consume/accept_event — cette action n'a aucun consumer gameplay.
## InputEvent.is_action_pressed pattern standard Godot (pas Input.* direct).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		visible = not visible

## Rafraîchit les 3 labels quand l'overlay est visible.
## Zero-alloc en régime permanent :
## - LatencyLabel : mis à jour 1×/s via accumulator (1 String allocation/s, gated).
## - MouseModeLabel : dirty-flag + const strings pré-allouées (0 alloc sauf transition).
## - ActionLabel : reset à "action: —" (string literal interné) quand timer expire.
func _process(delta: float) -> void:
	if not visible:
		return

	# Rafraîchissement latency p99 à 1 Hz via accumulator.
	_latency_accum += delta
	if _latency_accum >= LATENCY_UPDATE_INTERVAL_SEC:
		_latency_accum = 0.0
		var p99: float = InputManager.get_latency_p99_ms()
		_latency_label.text = "latency_p99: %.2f ms" % p99
		_latency_label.modulate = Color.RED if p99 > LATENCY_ANOMALY_THRESHOLD_MS else Color.WHITE

	# MouseModeLabel : dirty-flag sur transition CAPTURED↔VISIBLE uniquement.
	# is_mouse_captured() = 1 getter call ; comparaison int = zero alloc.
	# Écriture du Label.text uniquement à la transition → 0 alloc/frame en régime permanent.
	var captured: int = 1 if InputManager.is_mouse_captured() else 0
	if captured != _last_mouse_captured:
		_last_mouse_captured = captured
		_mouse_mode_label.text = _MOUSE_TEXT_CAPTURED if captured == 1 else _MOUSE_TEXT_VISIBLE

	# ActionLabel : timer décrémentiel, reset à idle quand expire.
	if _action_clear_timer > 0.0:
		_action_clear_timer -= delta
		if _action_clear_timer <= 0.0:
			_action_label.text = "action: —"

# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

## Met à jour ActionLabel avec le nom de l'action pressée et arme le timer d'effacement.
## Appelé via les 4 signaux gameplay InputManager avec .bind(&"action_name").
## [param action_name] : StringName passé via bind() depuis connect().
func _on_action_pressed(action_name: StringName) -> void:
	_action_label.text = "action: %s" % String(action_name)
	_action_clear_timer = ACTION_LABEL_TIMEOUT_SEC
