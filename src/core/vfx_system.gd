## VFXSystem — Autoload singleton Presentation layer pour les effets visuels Chrome Ascent.
##
## class_name VFXSystemScript (suffix -Script mandatory — cf. mémoire
## feedback_godot_class_name_autoload_collision — autoload enregistré comme "VFXSystem").
##
## Architecture : composition via 3 handlers RefCounted (_combat, _gsm, _pool_setup).
## Proxy properties transparentes exposent les variables internes des handlers
## pour compatibilité tests existants (pattern miroir audio_system.gd).
##
## ADR-0001 (wall-clock timer Callable injection), ADR-0009 D-2 (pool exclusive),
## ADR-0009 D-4 (CONNECT_DEFERRED), R-VFX-2 (zero-alloc hot path), R-VFX-14 (outbound-only).

class_name VFXSystemScript

extends Node

# Preload bindings locaux pour les handlers (TD-008 split).
const VFXCombatHandler := preload("res://src/core/vfx_combat_handler.gd")
const VFXGSMHandler := preload("res://src/core/vfx_gsm_handler.gd")
const VFXPoolSetup := preload("res://src/core/vfx_pool_setup.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const BLOOD_PARTICLE_POOL_SIZE: int = 8
const DECAL_POOL_SIZE: int = 64
const MAX_DECALS_PER_ROOM: int = 32
const FLASH_KILL_DURATION_MS: int = 80
const FLASH_RESPAWN_DURATION_MS: int = 50
const FLASH_MIN_INTERVAL_MS: int = 333
const FLASH_OVERLAY_LAYER: int = 60
const BLOOD_COLOR: Color = Color(0.784, 0.137, 0.173, 1.0)  # #C8232C
const TRAIL_COLOR: Color = Color(0.910, 0.910, 0.878, 1.0)  # #E8E8E0
const BLOOD_CONE_ANGLE_DEG: float = 30.0
const PARTICLE_LIFETIME_MS: int = 400
const STATE_MENU: int = 0; const STATE_PLAYING: int = 1; const STATE_PAUSED: int = 2
const STATE_RESPAWNING: int = 3; const STATE_BOSS_DEFEATED: int = 4
const DECAL_RAYCAST_MAX_DISTANCE: float = 3.0
const DEFAULT_FLASH_BRIGHTNESS: float = 1.0
const REDUCE_FLASH_BRIGHTNESS: float = 0.625  # gris #A0A0A0 — F-VFX-2
const KATANA_TRAIL_OPACITY_MAX: float = 0.7
const KATANA_TRAIL_FADE_MS: int = 100
const REDUCE_MOTION_PARTICLE_ANGLE_MULT: float = 0.5
const REDUCE_MOTION_TRAIL_MULT: float = 0.5
const BLOOD_SPURT_PARTICLE_COUNT: int = 6  # informationnel
const _RAYCAST_FALLBACK_DIRS: Array[Vector3] = [
	Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
]


# ---------------------------------------------------------------------------
# Pool references (alloués ici — pool exclusive AC-VFX-05)
# Tests accèdent directement à ces propriétés.
# ---------------------------------------------------------------------------

var _blood_particle_pool: Array[GPUParticles3D] = []
var _decal_pool: Array[Decal] = []
var _trail_mesh: MeshInstance3D = null
var _trail_material: StandardMaterial3D = null
var _flash_overlay_rect: ColorRect = null
var _blood_shader_material: ShaderMaterial = null


# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------

## True quand le VFXSystem est actif (false = paused/menu, story-006).
## Muté par VFXGSMHandler._apply_visibility_for_state.
var _is_active: bool = true

## Wall-clock injection (ADR-0001). `_get_time_msec.call()` → Time.get_ticks_msec().
var _get_time_msec: Callable = Time.get_ticks_msec


# ---------------------------------------------------------------------------
# Domain handlers (composition)
# ---------------------------------------------------------------------------

var _combat: VFXCombatHandler = null
var _gsm: VFXGSMHandler = null


# ---------------------------------------------------------------------------
# Proxy properties — combat handler (compatibilité tests)
# ---------------------------------------------------------------------------

var _blood_idx: int:
	get: return _combat._blood_idx
	set(v): _combat._blood_idx = v
var _decal_write_head: int:
	get: return _combat._decal_write_head
	set(v): _combat._decal_write_head = v
var _room_decal_count: int:
	get: return _combat._room_decal_count
	set(v): _combat._room_decal_count = v
var _trail_active: bool:
	get: return _combat._trail_active
	set(v): _combat._trail_active = v
var _trail_fade_start_msec: int:
	get: return _combat._trail_fade_start_msec
	set(v): _combat._trail_fade_start_msec = v
var _swing_aim_forward: Vector3:
	get: return _combat._swing_aim_forward
	set(v): _combat._swing_aim_forward = v
var _last_effective_cone_deg: float:
	get: return _combat._last_effective_cone_deg
	set(v): _combat._last_effective_cone_deg = v
var _flash_kill_active: bool:
	get: return _combat._flash_kill_active
	set(v): _combat._flash_kill_active = v
var _flash_kill_use_grey: bool:
	get: return _combat._flash_kill_use_grey
	set(v): _combat._flash_kill_use_grey = v
var _flash_respawn_active: bool:
	get: return _combat._flash_respawn_active
	set(v): _combat._flash_respawn_active = v
var _flash_last_msec: int:
	get: return _combat._flash_last_msec
	set(v): _combat._flash_last_msec = v


# ---------------------------------------------------------------------------
# Proxy properties — gsm handler (compatibilité tests)
# ---------------------------------------------------------------------------

var _reduce_motion: bool:
	get: return _gsm._reduce_motion
	set(v): _gsm._reduce_motion = v
var _reduce_flash: bool:
	get: return _gsm._reduce_flash
	set(v): _gsm._reduce_flash = v
var _flash_mult: float:
	get: return _gsm._flash_mult
	set(v): _gsm._flash_mult = v


# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_combat = VFXCombatHandler.new()
	_combat._vfx = self
	_gsm = VFXGSMHandler.new()
	_gsm._vfx = self

	var pool_setup: VFXPoolSetup = VFXPoolSetup.new()
	pool_setup._vfx = self
	var pools: Dictionary = pool_setup.build_pools()

	_blood_particle_pool = pools["blood_particle_pool"]
	_decal_pool = pools["decal_pool"]
	_trail_mesh = pools["trail_mesh"]
	_trail_material = pools["trail_material"]
	_flash_overlay_rect = pools["flash_overlay_rect"]
	_blood_shader_material = pools["blood_shader_material"]

	# Injecter refs pools dans le combat handler
	_combat._blood_particle_pool = _blood_particle_pool
	_combat._decal_pool = _decal_pool
	_combat._trail_mesh = _trail_mesh
	_combat._trail_material = _trail_material
	_combat._flash_overlay_rect = _flash_overlay_rect
	_combat._blood_shader_material = _blood_shader_material
	_combat.init_sub_handlers()

	_connect_upstream_signals()
	_gsm._pull_accessibility_settings()
	_gsm._pull_initial_gsm_state()

	print("[VFXSystem] boot — pool=%d/%d trail=%d flash_layer=%d" % [
		BLOOD_PARTICLE_POOL_SIZE, DECAL_POOL_SIZE,
		1 if _trail_mesh != null else 0, FLASH_OVERLAY_LAYER,
	])


# ---------------------------------------------------------------------------
# Private — upstream signal connections
# ---------------------------------------------------------------------------

func _connect_upstream_signals() -> void:
	var combat: Node = get_node_or_null("/root/CombatSystem")
	if combat != null:
		if combat.has_signal(&"swing_started") and not combat.swing_started.is_connected(_combat._on_swing_started):
			combat.swing_started.connect(_combat._on_swing_started, CONNECT_DEFERRED)
		if combat.has_signal(&"swing_ended") and not combat.swing_ended.is_connected(_combat._on_swing_ended):
			combat.swing_ended.connect(_combat._on_swing_ended, CONNECT_DEFERRED)
		if combat.has_signal(&"multi_kill") and not combat.multi_kill.is_connected(_combat._on_multi_kill):
			combat.multi_kill.connect(_combat._on_multi_kill, CONNECT_DEFERRED)

	var enemy: Node = get_node_or_null("/root/EnemySystem")
	if enemy != null:
		if enemy.has_signal(&"enemy_killed") and not enemy.enemy_killed.is_connected(_combat._on_enemy_killed):
			enemy.enemy_killed.connect(_combat._on_enemy_killed, CONNECT_DEFERRED)

	var camera: Node = get_node_or_null("/root/CameraSystem")
	if camera != null:
		if camera.has_signal(&"died") and not camera.died.is_connected(_combat._on_died):
			camera.died.connect(_combat._on_died, CONNECT_DEFERRED)
		if camera.has_signal(&"respawned") and not camera.respawned.is_connected(_combat._on_respawned):
			camera.respawned.connect(_combat._on_respawned, CONNECT_DEFERRED)

	var gsm: Node = get_node_or_null("/root/GameStateManager")
	if gsm != null:
		_gsm._gsm_ref = gsm
		if gsm.has_signal(&"state_changed") and not gsm.state_changed.is_connected(_gsm._on_state_changed):
			gsm.state_changed.connect(_gsm._on_state_changed, CONNECT_DEFERRED)

	var accessibility: Node = get_node_or_null("/root/AccessibilityService")
	if accessibility != null:
		_gsm._accessibility_service_ref = accessibility
		if accessibility.has_signal(&"settings_changed") and not accessibility.settings_changed.is_connected(_gsm._on_accessibility_settings_changed):
			accessibility.settings_changed.connect(_gsm._on_accessibility_settings_changed, CONNECT_DEFERRED)


# ---------------------------------------------------------------------------
# Public connection helpers (test injection pattern)
# ---------------------------------------------------------------------------

func connect_combat_signals(combat: Node) -> void:
	if combat == null:
		return
	if combat.has_signal(&"swing_started") and not combat.swing_started.is_connected(_combat._on_swing_started):
		combat.swing_started.connect(_combat._on_swing_started, CONNECT_DEFERRED)
	if combat.has_signal(&"swing_ended") and not combat.swing_ended.is_connected(_combat._on_swing_ended):
		combat.swing_ended.connect(_combat._on_swing_ended, CONNECT_DEFERRED)
	if combat.has_signal(&"multi_kill") and not combat.multi_kill.is_connected(_combat._on_multi_kill):
		combat.multi_kill.connect(_combat._on_multi_kill, CONNECT_DEFERRED)

func connect_enemy_signals(enemy: Node) -> void:
	if enemy == null:
		return
	if enemy.has_signal(&"enemy_killed") and not enemy.enemy_killed.is_connected(_combat._on_enemy_killed):
		enemy.enemy_killed.connect(_combat._on_enemy_killed, CONNECT_DEFERRED)

func connect_camera_signals(camera: Node) -> void:
	if camera == null:
		return
	if camera.has_signal(&"died") and not camera.died.is_connected(_combat._on_died):
		camera.died.connect(_combat._on_died, CONNECT_DEFERRED)
	if camera.has_signal(&"respawned") and not camera.respawned.is_connected(_combat._on_respawned):
		camera.respawned.connect(_combat._on_respawned, CONNECT_DEFERRED)

func connect_gsm_signals(gsm: Node) -> void:
	_gsm.connect_gsm_signals(gsm)

func connect_accessibility_signals(accessibility: Node) -> void:
	_gsm.connect_accessibility_signals(accessibility)


# ---------------------------------------------------------------------------
# _physics_process — dispatch aux handlers
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not _is_active:
		return
	if _combat._trail_active and _combat._trail_fade_start_msec > 0:
		_combat.tick_trail_fade()
	if _combat._flash_kill_active:
		_combat.tick_flash_kill()
	if _combat._flash_respawn_active:
		_combat.tick_flash_respawn()


# ---------------------------------------------------------------------------
# Proxy methods — tests appellent ces méthodes directement sur VFXSystem
# ---------------------------------------------------------------------------

func _on_swing_started(direction: Vector3 = Vector3.ZERO) -> void:
	_combat._on_swing_started(direction)

func _on_swing_ended() -> void:
	_combat._on_swing_ended()

func _on_multi_kill(count: int = 0) -> void:
	_combat._on_multi_kill(count)

func _on_enemy_killed(enemy: Node = null, position: Vector3 = Vector3.ZERO) -> void:
	_combat._on_enemy_killed(enemy, position)

func _on_died() -> void:
	_combat._on_died()

func _on_respawned(position: Vector3 = Vector3.ZERO) -> void:
	_combat._on_respawned(position)

func _on_state_changed(new_state: int = 0) -> void:
	_gsm._on_state_changed(new_state)

func _on_accessibility_settings_changed() -> void:
	_gsm._on_accessibility_settings_changed()

func _trigger_flash_kill() -> void:
	_combat._flash.trigger_flash_kill()

func _trigger_flash_respawn() -> void:
	_combat._flash.trigger_flash_respawn()

func _pull_accessibility_settings() -> void:
	_gsm._pull_accessibility_settings()
