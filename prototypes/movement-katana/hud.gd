# PROTOTYPE - NOT FOR PRODUCTION
# Question: Input-to-display latency measurement + feel metrics
# Date: 2026-04-21

extends CanvasLayer

@onready var label: Label = $Label
@onready var crosshair: ColorRect = $Crosshair
@onready var damage_flash: ColorRect = $DamageFlash

var kill_count: int = 0
var death_count: int = 0
var attack_count: int = 0
var last_input_time_ms: int = 0
var last_action_time_ms: int = 0
var input_to_action_ms: float = 0.0
var player_ref: Node = null

func _ready() -> void:
	damage_flash.modulate.a = 0.0
	crosshair.color = Color(1, 1, 1, 0.9)

func set_player(p: Node) -> void:
	player_ref = p

func _process(_delta: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / max(fps, 1.0)
	var state_str: String = ""
	if player_ref and player_ref.has_method("get_state_string"):
		state_str = player_ref.get_state_string()
	label.text = "FPS: %d  (%.2f ms/frame)\n%s\nKills: %d   Deaths: %d   Attacks: %d\nLast input→action: %.1f ms\n\n[WASD] move  [Space] jump (x2)  [Shift gauche] dash  [LMB] katana  [R] respawn  [Esc] release mouse" % [
		fps, frame_ms, state_str, kill_count, death_count, attack_count, input_to_action_ms
	]

func register_attack() -> void:
	attack_count += 1
	last_action_time_ms = Time.get_ticks_msec()
	if last_input_time_ms > 0:
		input_to_action_ms = float(last_action_time_ms - last_input_time_ms)

func register_kill() -> void:
	kill_count += 1
	flash_crosshair()

func register_death() -> void:
	death_count += 1
	flash_damage()

func flash_crosshair() -> void:
	crosshair.color = Color(1, 1, 1, 1)
	var tween: Tween = create_tween()
	tween.tween_property(crosshair, "color", Color(1, 1, 1, 0.9), 0.08)

func flash_damage() -> void:
	damage_flash.modulate.a = 0.6
	var tween: Tween = create_tween()
	tween.tween_property(damage_flash, "modulate:a", 0.0, 0.2)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		last_input_time_ms = Time.get_ticks_msec()
