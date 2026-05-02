# Test helper Story-007 — Mock Movement reader 60 Hz pull pattern.
# Capture les flags Upgrade au premier _physics_process tick après spawn.
# Utilisé par tests integration AC-UPG-24/25/31/32.
class_name MockMovementReader
extends Node

var first_tick_can_air_jump: bool = false
var first_tick_can_dash: bool = false
var first_tick_can_wall_run: bool = false
var first_tick_observed: bool = false


func _physics_process(_delta: float) -> void:
	if first_tick_observed:
		return
	first_tick_can_air_jump = Upgrade.can_air_jump
	first_tick_can_dash = Upgrade.can_dash
	first_tick_can_wall_run = Upgrade.can_wall_run
	first_tick_observed = true
