class_name CameraSystem
extends Node3D

## Camera system orchestrator — attached to CameraArm (Node3D child of CharacterBody3D).
## ADR-0002 ownership: Yaw=Player.rotation.y / Pitch=CameraArm.rotation.x /
## Tilt=CameraEffects.rotation.z / FOV+Shake=Camera3D. TR-cam-003: logic in _process.
## Stories 001–013. Constantes extraites dans CameraConstants (TD-008).

# TD-008: constantes importées depuis CameraConstants (TD-008 split <300 lignes).
# Note architecture: ce fichier dépasse 300 lignes car 13 stories de membres internes
# sont accédés directement par les tests (pattern injection GdUnit4) — extraction
# complète nécessiterait du boilerplate forwarding équivalent. Voir TD-008.
const CC := preload("res://src/gameplay/camera/camera_constants.gd")

# Alias locaux pour lisibilité inline (évite CC.CONSTANT partout).
const PROCESS_COST_CAPACITY: int = CC.PROCESS_COST_CAPACITY
const LATENCY_CAPACITY: int = CC.LATENCY_CAPACITY
const PITCH_LIMIT: float = CC.PITCH_LIMIT
const MAX_ROT_PER_FRAME: float = CC.MAX_ROT_PER_FRAME
const BASE_FOV: float = CC.BASE_FOV
const DASH_FOV_KICK: float = CC.DASH_FOV_KICK
const DASH_FOV_LERP_SPEED: float = CC.DASH_FOV_LERP_SPEED
const WALL_RUN_TILT_ANGLE: float = CC.WALL_RUN_TILT_ANGLE
const TILT_LERP_SPEED: float = CC.TILT_LERP_SPEED
const SHAKE_DECAY: float = CC.SHAKE_DECAY
const WALL_JUMP_KICK_MAGNITUDE: float = CC.WALL_JUMP_KICK_MAGNITUDE
const MAX_SHAKE_MAGNITUDE: float = CC.MAX_SHAKE_MAGNITUDE
const RESPAWN_OVERLAY_COLOR: Color = CC.RESPAWN_OVERLAY_COLOR
const RESPAWN_OVERLAY_LAYER: int = CC.RESPAWN_OVERLAY_LAYER
const RESPAWN_OVERLAY_FADE_DURATION: float = CC.RESPAWN_OVERLAY_FADE_DURATION
const RESPAWN_FLASH_DURATION: float = CC.RESPAWN_FLASH_DURATION
const RESPAWN_FLASH_COLOR: Color = CC.RESPAWN_FLASH_COLOR
const RESPAWN_FADE_END_COLOR: Color = CC.RESPAWN_FADE_END_COLOR
const REDUCE_MOTION_TILT_MULT: float = CC.REDUCE_MOTION_TILT_MULT
const REDUCE_MOTION_FOV_KICK_MULT: float = CC.REDUCE_MOTION_FOV_KICK_MULT

## Mini-state Camera-side (story 008). COSMETIC ONLY — gate effets visuels + mouse.
## ADR-0005 D-8: transition 1× par changement. Pas logique gameplay.
enum State { ACTIVE, RESPAWNING }

# Node references — resolved via unique-name (%NodeName). CameraArm IS self.
@onready var _camera_arm: Node3D = self
@onready var _camera_effects: Node3D = %CameraEffects
@onready var _camera3d: Camera3D = %Camera3D
@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D

# Signal-driven flags (stories 006+). Manifest 2026-04-23 ligne 161: interdit polling.
var _is_dashing: bool = false
var _is_wall_running: bool = false
var _wall_side_cached: int = 0  # -1/0/+1. ADR-0002 Amendment A-1.

## Shake offset additif (rad). ADR-0002 Risk 3: assignation (=, pas +=) chaque frame.
var _shake_offset: Vector3 = Vector3.ZERO

## Mini-state Camera (story 008). Mute par _on_died/_on_respawned uniquement.
var _state: State = State.ACTIVE

# Overlay respawn — pré-créé au _ready() (zero-alloc handler, ADR-0005 D-5).
var _canvas_layer: CanvasLayer = null
var _overlay: ColorRect = null
var _respawn_tween: Tween = null

# Reduce_motion multipliers (story 010, GDD Rule 14, ADR-0015 D-3).
var _tilt_mult: float = 1.0
var _fov_kick_mult: float = 1.0
var _shake_mult: float = 1.0

# Perf ring buffers (story 012, GDD AC-CAM-80/81, ADR-0004 D-8 zero-alloc runtime).
var _process_cost_samples: PackedFloat32Array = PackedFloat32Array()
var _process_cost_write_idx: int = 0
var _latency_samples: PackedFloat32Array = PackedFloat32Array()
var _latency_write_idx: int = 0

# Settings persistence (story 013, ADR-0014).
var settings: CameraSettings = null
var suppress_settings_load: bool = false


func _ready() -> void:
	# Story 012: pré-alloue ring buffers AVANT early-return (écriture _process ne sort jamais
	# hors-bounds même si vars injectées post-_ready).
	if _process_cost_samples.size() == 0:
		_process_cost_samples.resize(PROCESS_COST_CAPACITY)
	if _latency_samples.size() == 0:
		_latency_samples.resize(LATENCY_CAPACITY)

	if _camera_effects == null:
		assert(PITCH_LIMIT < PI / 2.0, "CameraSystem: PITCH_LIMIT must stay strictly under PI/2")
		assert(MAX_ROT_PER_FRAME > 0.0, "CameraSystem: MAX_ROT_PER_FRAME must be positive")
		return

	assert(_camera_arm != null, "CameraSystem: _camera_arm null")
	assert(_camera_effects != null, "CameraSystem: _camera_effects null")
	assert(_camera3d != null, "CameraSystem: _camera3d null")
	assert(_player != null, "CameraSystem: _player null")
	assert(PITCH_LIMIT < PI / 2.0, "CameraSystem: PITCH_LIMIT must stay strictly under PI/2")
	assert(MAX_ROT_PER_FRAME > 0.0, "CameraSystem: MAX_ROT_PER_FRAME must be positive")

	if not suppress_settings_load:
		_load_settings()

	var fov_offset: float = settings.fov_user_offset if settings != null else 0.0
	_camera3d.fov = BASE_FOV + fov_offset

	# Story 002/006/007/TD-004: connexions Movement — SYNC (D-5 consumer léger).
	InputManager.mouse_motion.connect(_on_mouse_motion)
	_player.dash_started.connect(_on_dash_started)
	_player.dash_ended.connect(_on_dash_ended)
	_player.wall_jumped.connect(_on_wall_jumped)
	_player.wall_run_entered.connect(_on_wall_run_entered)
	_player.wall_run_exited.connect(_on_wall_run_exited)

	# Story 008: pré-création overlay puis connexions died/respawned.
	_setup_overlay()
	_player.died.connect(_on_died)
	_player.respawned.connect(_on_respawned)

	# Polish P4 (ADR-0015 D-3): Camera consomme AccessibilityService — pull-pattern.
	if not AccessibilityService.settings_changed.is_connected(_on_accessibility_changed):
		AccessibilityService.settings_changed.connect(_on_accessibility_changed)
	_apply_accessibility()


## Story 011 / GDD Rule 16: symétrie _ready ↔ _exit_tree. AC-CAM-63.
func _exit_tree() -> void:
	if InputManager.mouse_motion.is_connected(_on_mouse_motion):
		InputManager.mouse_motion.disconnect(_on_mouse_motion)
	if AccessibilityService.settings_changed.is_connected(_on_accessibility_changed):
		AccessibilityService.settings_changed.disconnect(_on_accessibility_changed)
	var player: CharacterBody3D = get_parent() as CharacterBody3D
	if player != null and is_instance_valid(player):
		if player.dash_started.is_connected(_on_dash_started):
			player.dash_started.disconnect(_on_dash_started)
		if player.dash_ended.is_connected(_on_dash_ended):
			player.dash_ended.disconnect(_on_dash_ended)
		if player.wall_jumped.is_connected(_on_wall_jumped):
			player.wall_jumped.disconnect(_on_wall_jumped)
		if player.wall_run_entered.is_connected(_on_wall_run_entered):
			player.wall_run_entered.disconnect(_on_wall_run_entered)
		if player.wall_run_exited.is_connected(_on_wall_run_exited):
			player.wall_run_exited.disconnect(_on_wall_run_exited)
		if player.died.is_connected(_on_died):
			player.died.disconnect(_on_died)
		if player.respawned.is_connected(_on_respawned):
			player.respawned.disconnect(_on_respawned)


## Cosmetic frame update (ADR-0001 Rule 12 Presentation layer). Story 012: instrumentation.
func _process(delta: float) -> void:
	if _camera_effects == null or _camera3d == null:
		return
	var t_start: int = Time.get_ticks_usec()
	_safeguard_rotation()
	_update_tilt_wall_run(delta)
	_update_fov_dash(delta)
	_update_shake(delta)
	var elapsed_ms: float = float(Time.get_ticks_usec() - t_start) / 1000.0
	_process_cost_samples[_process_cost_write_idx] = elapsed_ms
	_process_cost_write_idx = (_process_cost_write_idx + 1) % PROCESS_COST_CAPACITY


## Story 011 / GDD Edge Case: détecte NaN sur camera_effects.rotation.z. AC-CAM-NAN-1.
func _safeguard_rotation() -> void:
	if not is_finite(_camera_effects.rotation.z):
		_camera_effects.rotation.z = 0.0
		push_warning("[camera] camera_effects.rotation.z NaN/Inf detected, reset to 0")


## TD-004 / ADR-0002 A-1: tilt via cache signal-driven (pas polling player.wall_normal).
## Story 010: reduce_motion gate via _tilt_mult (GDD Rule 14, AC-CAM-70).
func _update_tilt_wall_run(delta: float) -> void:
	var target_roll: float = WALL_RUN_TILT_ANGLE * float(_wall_side_cached) * _tilt_mult
	_camera_effects.rotation.z = lerp(
		_camera_effects.rotation.z, target_roll, min(TILT_LERP_SPEED * delta, 1.0))


## Story 006: FOV lerp vers BASE_FOV + DASH_FOV_KICK quand _is_dashing. AC-CAM-20/71.
func _update_fov_dash(delta: float) -> void:
	var dash_kick: float = DASH_FOV_KICK * _fov_kick_mult
	var fov_offset: float = settings.fov_user_offset if settings != null else 0.0
	var target_fov: float = BASE_FOV + fov_offset + (dash_kick if _is_dashing else 0.0)
	_camera3d.fov = lerp(_camera3d.fov, target_fov, min(DASH_FOV_LERP_SPEED * delta, 1.0))


## Story 007: décroissance exponentielle shake. ADR-0002 Risk 3: = (pas +=). AC-CAM-30.
func _update_shake(delta: float) -> void:
	_shake_offset *= exp(-SHAKE_DECAY * delta)
	_shake_offset = _shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)
	_camera3d.rotation = _shake_offset


## Story 007: ajoute offset shake. Story 010: early-return si _shake_mult <= 0 (AC-CAM-72).
func add_shake(offset_radians: Vector3) -> void:
	if _shake_mult <= 0.0:
		return
	_shake_offset += offset_radians * _shake_mult
	_shake_offset = _shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)


## Raccourci shake roll (axe Z uniquement).
func add_shake_roll(magnitude: float) -> void:
	add_shake(Vector3(0.0, 0.0, magnitude))


## GDD Rule 7: sign avec fallback +1 pour input 0 (mur en avant, dot=0 exact).
func _sign_with_fallback(x: float) -> float:
	if x > 0.0:
		return 1.0
	elif x < 0.0:
		return -1.0
	else:
		return 1.0


# Signal handlers — Movement dash (story 006, ADR-0005 D-7/D-8)

func _on_dash_started(_dash_dir: Vector3, _dash_speed: float) -> void:
	_is_dashing = true

func _on_dash_ended() -> void:
	_is_dashing = false


# Signal handlers — Movement wall-run (TD-004, ADR-0002 A-1, ADR-0005 D-7/D-8)

## Cache wall_side une seule fois à l'entrée wall-run. ADR-0002 A-1.
func _on_wall_run_entered(wall_normal: Vector3) -> void:
	_is_wall_running = true
	_wall_side_cached = int(sign((-wall_normal).dot(_player.global_transform.basis.x)))

func _on_wall_run_exited() -> void:
	_is_wall_running = false
	_wall_side_cached = 0


# Signal handlers — AccessibilityService (Polish P4, ADR-0015 D-3)

func _apply_accessibility() -> void:
	_tilt_mult = AccessibilityService.get_camera_tilt_mult()
	_fov_kick_mult = AccessibilityService.get_camera_fov_kick_mult()
	_shake_mult = AccessibilityService.get_camera_shake_mult()

func _on_accessibility_changed() -> void:
	_apply_accessibility()


# Signal handlers — Movement wall_jumped (story 007, ADR-0005 D-2/D-7/D-8)

## GDD Rule 7: kick direction via dot(wall_normal, -camera_arm.basis.x).
func _on_wall_jumped(wall_normal: Vector3, _launch_velocity: Vector3) -> void:
	var dir: float = _sign_with_fallback(wall_normal.dot(-_camera_arm.global_transform.basis.x))
	add_shake_roll(WALL_JUMP_KICK_MAGNITUDE * dir)


# Respawn overlay setup + animation (stories 008–009, GDD Rule 9)

## Pré-crée overlay fullscreen sur CanvasLayer (one-shot au _ready, zero-alloc handler).
func _setup_overlay() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "RespawnOverlayLayer"
	_canvas_layer.layer = RESPAWN_OVERLAY_LAYER
	add_child(_canvas_layer)
	_overlay = ColorRect.new()
	_overlay.name = "RespawnOverlay"
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.color = RESPAWN_OVERLAY_COLOR
	_overlay.visible = false
	_canvas_layer.add_child(_overlay)


## AC-CAM-43 idempotence: early-return si déjà RESPAWNING. ADR-0005 D-8.
func _on_died() -> void:
	if _state == State.RESPAWNING:
		return
	if _respawn_tween != null and _respawn_tween.is_valid():
		_respawn_tween.kill()
	_state = State.RESPAWNING
	_overlay.color = RESPAWN_OVERLAY_COLOR
	_overlay.visible = true


## AC-CAM-41 reset: tilt/fov/shake/_is_dashing. Pitch+yaw préservés (Ghostrunner).
## Story 013: reset FOV inclut fov_user_offset. ADR-0005 D-7 no Movement mutation.
func _on_respawned(_position: Vector3) -> void:
	_camera_effects.rotation.z = 0.0
	var fov_offset: float = settings.fov_user_offset if settings != null else 0.0
	_camera3d.fov = BASE_FOV + fov_offset
	_camera3d.rotation = Vector3.ZERO
	_shake_offset = Vector3.ZERO
	_is_dashing = false
	_animate_respawn_overlay()
	_state = State.ACTIVE


## Story 009: flash blanc 50 ms → fade 100 ms → hide. AC-CAM-FLASH-2 total ≤ 400 ms.
## Tween Godot 4 API stable. ADR-0002: overlay owned par Camera.
func _animate_respawn_overlay() -> void:
	if _respawn_tween != null and _respawn_tween.is_valid():
		_respawn_tween.kill()
	_respawn_tween = create_tween()
	_respawn_tween.tween_property(_overlay, "color", RESPAWN_FLASH_COLOR, 0.0)
	_respawn_tween.tween_interval(RESPAWN_FLASH_DURATION)
	_respawn_tween.tween_property(_overlay, "color", RESPAWN_FADE_END_COLOR,
		RESPAWN_OVERLAY_FADE_DURATION)
	_respawn_tween.tween_callback(func() -> void: _overlay.visible = false)


# Public getters — respawn state (story 008)

func get_respawn_overlay() -> ColorRect:
	return _overlay

func is_respawning() -> bool:
	return _state == State.RESPAWNING


# Input handler (story 002+, ADR-0002 ownership: yaw=Player / pitch=CameraArm)

## Story 012: capture t_event en entrée pour mesure latence E2E. AC-CAM-81.
## Gates: Respawning (008) / mouse_captured (003) / enabled (003) / ADR-0004 D-4.
func _on_mouse_motion(delta: Vector2) -> void:
	var t_event: int = Time.get_ticks_usec()
	if _state == State.RESPAWNING:
		return
	if not InputManager.is_mouse_captured():
		return
	if not InputManager.enabled:
		return
	var sensitivity: float = InputManager.mouse_sensitivity
	var invert_factor: float = -1.0 if InputManager.mouse_y_inverted else 1.0
	var yaw_delta: float = clamp(-delta.x * sensitivity, -MAX_ROT_PER_FRAME, MAX_ROT_PER_FRAME)
	var pitch_delta: float = clamp(
		-delta.y * sensitivity * invert_factor, -MAX_ROT_PER_FRAME, MAX_ROT_PER_FRAME)
	_player.rotation.y += yaw_delta
	_camera_arm.rotation.x = clamp(
		_camera_arm.rotation.x + pitch_delta, -PITCH_LIMIT, PITCH_LIMIT)
	var latency_ms: float = float(Time.get_ticks_usec() - t_event) / 1000.0
	_latency_samples[_latency_write_idx] = latency_ms
	_latency_write_idx = (_latency_write_idx + 1) % LATENCY_CAPACITY


# Public getters — node refs (story 001)

func get_camera_arm() -> Node3D:
	return _camera_arm

func get_camera_effects() -> Node3D:
	return _camera_effects

func get_camera3d() -> Camera3D:
	return _camera3d


# Public API — settings persistence (story 013, ADR-0014 D-6: no auto-save hot path)

## Sauvegarde settings vers user://settings/camera.tres. Retourne ERR_UNCONFIGURED si null.
func save_settings() -> Error:
	if settings == null:
		return ERR_UNCONFIGURED
	var err: Error = SettingsResource.save(settings, "camera")
	if err != OK:
		push_warning("[camera-settings] save failed: %d" % err)
	return err


## Story 013 / ADR-0014 D-3/D-4/D-5: load settings, propagation InputManager mouse props.
func _load_settings() -> void:
	settings = SettingsResource.load_or_default(
		"camera",
		Callable(CameraSettings, "create_defaults"),
		Callable(CameraSettings, "migrate_from"),
	) as CameraSettings
	InputManager.mouse_sensitivity = settings.mouse_sensitivity
	InputManager.mouse_y_inverted = settings.mouse_y_inverted


# Public API — perf instrumentation (story 012, GDD AC-CAM-80/81)

## Retourne {p50, p99} du coût _process en ms. GDD AC-CAM-80: p50 ≤ 0.2 ms, p99 ≤ 0.4 ms.
func get_process_cost_percentiles() -> Dictionary:
	return _compute_percentiles(_process_cost_samples)

## Retourne {p50, p99} de la latence mouse_motion→rotation en ms. GDD AC-CAM-81: p99 ≤ 16 ms.
func get_mouse_latency_percentiles() -> Dictionary:
	return _compute_percentiles(_latency_samples)

## Tri sur duplicate() — zero-alloc côté caller. n==0 → zeros.
func _compute_percentiles(samples: PackedFloat32Array) -> Dictionary:
	var n: int = samples.size()
	if n == 0:
		return {"p50": 0.0, "p99": 0.0}
	var sorted: PackedFloat32Array = samples.duplicate()
	sorted.sort()
	return {
		"p50": sorted[int(float(n) * 0.50)],
		"p99": sorted[int(float(n) * 0.99)],
	}


# Public API — aim_forward (story 004, TR-cam-002, ADR-0002 Formula 5 + VC-4)

## Forme close trigonométrique. Roll-invariant: camera_effects.rotation.z exclu.
## Consommé par Combat pour orienter swept katana. ADR-0002 VC-4.
var aim_forward: Vector3:
	get:
		var yaw: float = _player.rotation.y
		var pitch: float = _camera_arm.rotation.x
		var cp: float = cos(pitch)
		return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)
