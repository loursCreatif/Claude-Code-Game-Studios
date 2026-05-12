## AudioSystem — Autoload singleton pour la gestion audio du projet Chrome Ascent.
##
## PAS de class_name (collision potentielle class_name ↔ autoload identifiant,
## cf. mémoire feedback_godot_class_name_autoload_collision).
##
## Architecture : composition via 3 handlers RefCounted injectés (_combat,
## _movement, _level). Proxy properties transparentes exposent les variables
## internes des handlers pour compatibilité tests existants.
##
## ADR-0009 D-1 (bus hierarchy) + D-2 (pool pré-instancié jamais étendu runtime).
## Pool exclusive (AC-AUD-12) : seul ce fichier instancie AudioStreamPlayer*.

extends Node

# Preload bindings locaux pour les 3 handlers (TD-008 split).
# Pas via `class_name` pour bypass class cache CI gdUnit4-action (pattern miroir
# AutoloadResetTestSuite commit 2edf64c).
const AudioCombatHandler := preload("res://src/core/audio_combat_handler.gd")
const AudioMovementHandler := preload("res://src/core/audio_movement_handler.gd")
const AudioLevelHandler := preload("res://src/core/audio_level_handler.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const POOL_2D_SIZE: int = 5
const POOL_3D_SIZE: int = 12
const POOL_AMBIENCE_SIZE: int = 2

const _BUS_NAMES: Array[StringName] = [
	&"Master", &"Music", &"SFX", &"swing_active", &"combat_kill", &"Ambience", &"UI",
]
const _BUS_SENDS: Array[StringName] = [
	&"Master", &"Master", &"Master", &"SFX", &"SFX", &"Master", &"Master",
]

const SILENCE_DB: float = -80.0

## Slow-mo allowlist (story-007 Rule 11 r2). True = pitch-shifted sous slow-mo.
const PITCH_ALLOWLIST: Dictionary[StringName, bool] = {
	&"Master": false, &"Music": false, &"SFX": false,
	&"swing_active": false, &"combat_kill": true, &"Ambience": true, &"UI": false,
}

## Secret pitch +5 semitones (Formula 7). Proxy depuis AudioCombatHandler.
const SECRET_PITCH_SCALE: float = 1.3348398541700344


# ---------------------------------------------------------------------------
# Pool variables (restent sur AudioSystem — tests accèdent directement)
# ---------------------------------------------------------------------------

var _2d_pool: Array[AudioStreamPlayer] = []
var _3d_pool: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer = null
var _ambience_pool: Array[AudioStreamPlayer] = []
var _2d_index: int = 0
var _3d_index: int = 0

## Wall-clock injection (ADR-0006 D-5 — substituable en test).
var _get_time_msec: Callable = Time.get_ticks_msec


# ---------------------------------------------------------------------------
# Domain handlers (composition)
# ---------------------------------------------------------------------------

var _combat: AudioCombatHandler = null
var _movement: AudioMovementHandler = null
var _level: AudioLevelHandler = null


# ---------------------------------------------------------------------------
# Slow-mo pitch shift cache (story-007)
# ---------------------------------------------------------------------------

var _last_pitch_factor: float = 1.0
var _last_time_scale: float = 1.0


# ---------------------------------------------------------------------------
# Proxy properties — combat (compatibility layer for tests)
# ---------------------------------------------------------------------------

var swoosh_stream: AudioStream:
	get: return _combat.swoosh_stream
	set(v): _combat.swoosh_stream = v
var clac_stream: AudioStream:
	get: return _combat.clac_stream
	set(v): _combat.clac_stream = v
var blood_stream: AudioStream:
	get: return _combat.blood_stream
	set(v): _combat.blood_stream = v
var swoosh_fade_duration_ms: float:
	get: return _combat.swoosh_fade_duration_ms
	set(v): _combat.swoosh_fade_duration_ms = v
var ducking_release_ms: float:
	get: return _combat.ducking_release_ms
	set(v): _combat.ducking_release_ms = v
var _kill_count_this_swing: int:
	get: return _combat._kill_count_this_swing
	set(v): _combat._kill_count_this_swing = v
var _active_clac_players: Dictionary:
	get: return _combat._active_clac_players
var _swoosh_fade_active: bool:
	get: return _combat._swoosh_fade_active
	set(v): _combat._swoosh_fade_active = v
var _swoosh_fade_start_msec: int:
	get: return _combat._swoosh_fade_start_msec
	set(v): _combat._swoosh_fade_start_msec = v
var _ducking_release_active: bool:
	get: return _combat._ducking_release_active
	set(v): _combat._ducking_release_active = v
var _ducking_release_start_msec: int:
	get: return _combat._ducking_release_start_msec
	set(v): _combat._ducking_release_start_msec = v
var _clac_finished_callbacks: Array:
	get: return _combat._clac_finished_callbacks
var _blood_pending_msec: PackedFloat32Array:
	get: return _combat._blood_pending_msec
var _blood_pending_count: int:
	get: return _combat._blood_pending_count
	set(v): _combat._blood_pending_count = v
var _slot_fixed_pitch: Dictionary:
	get: return _combat._slot_fixed_pitch
var BLOOD_QUEUE_SIZE: int:
	get: return AudioCombatHandler.BLOOD_QUEUE_SIZE


# ---------------------------------------------------------------------------
# Proxy properties — movement
# ---------------------------------------------------------------------------

var dash_stream: AudioStream:
	get: return _movement.dash_stream
	set(v): _movement.dash_stream = v
var wallrun_loop_stream: AudioStream:
	get: return _movement.wallrun_loop_stream
	set(v): _movement.wallrun_loop_stream = v
var walljump_stream: AudioStream:
	get: return _movement.walljump_stream
	set(v): _movement.walljump_stream = v
var death_stream: AudioStream:
	get: return _movement.death_stream
	set(v): _movement.death_stream = v
var _wallrun_slot_idx: int:
	get: return _movement._wallrun_slot_idx
	set(v): _movement._wallrun_slot_idx = v
var _wallrun_fade_active: bool:
	get: return _movement._wallrun_fade_active
	set(v): _movement._wallrun_fade_active = v
var _wallrun_fade_start_msec: int:
	get: return _movement._wallrun_fade_start_msec
	set(v): _movement._wallrun_fade_start_msec = v


# ---------------------------------------------------------------------------
# Proxy properties — level / GSM
# ---------------------------------------------------------------------------

var _ambience_active_idx: int:
	get: return _level._ambience_active_idx
	set(v): _level._ambience_active_idx = v
var _crossfade_active: bool:
	get: return _level._crossfade_active
	set(v): _level._crossfade_active = v
var _crossfade_start_msec: int:
	get: return _level._crossfade_start_msec
	set(v): _level._crossfade_start_msec = v
var _crossfade_duration_ms: float:
	get: return _level._crossfade_duration_ms
	set(v): _level._crossfade_duration_ms = v
var _crossfade_old_player: AudioStreamPlayer:
	get: return _level._crossfade_old_player
	set(v): _level._crossfade_old_player = v
var _crossfade_new_player: AudioStreamPlayer:
	get: return _level._crossfade_new_player
	set(v): _level._crossfade_new_player = v
var _music_fade_out_active: bool:
	get: return _level._music_fade_out_active
	set(v): _level._music_fade_out_active = v
var _music_fade_out_start_msec: int:
	get: return _level._music_fade_out_start_msec
	set(v): _level._music_fade_out_start_msec = v
var _music_fade_out_duration_ms: float:
	get: return _level._music_fade_out_duration_ms
	set(v): _level._music_fade_out_duration_ms = v
var _get_etage_audio_streams: Callable:
	get: return _level._get_etage_audio_streams
	set(v): _level._get_etage_audio_streams = v
var _is_paused: bool:
	get: return _level._is_paused
	set(v): _level._is_paused = v
var _fade_pause_msec: int:
	get: return _level._fade_pause_msec
	set(v): _level._fade_pause_msec = v


# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_combat = AudioCombatHandler.new()
	_combat._audio = self
	_movement = AudioMovementHandler.new()
	_movement._audio = self
	_level = AudioLevelHandler.new()
	_level._audio = self
	_setup_bus_names()
	_setup_pool()
	_setup_sidechain_compressor()
	_combat.setup_blood_queue()
	_combat.setup_clac_callbacks(POOL_3D_SIZE)
	_combat.emit_boundary_warnings()
	_level.connect_gsm_signals(get_tree().root)


# ---------------------------------------------------------------------------
# Private — bus + pool setup
# ---------------------------------------------------------------------------

func _setup_bus_names() -> void:
	if AudioServer.bus_count != 7:
		push_error("AudioSystem: bus_count != 7 — default_bus_layout.tres mal configuré")
		return
	for i: int in range(7):
		if AudioServer.get_bus_name(i) != _BUS_NAMES[i]:
			AudioServer.set_bus_name(i, _BUS_NAMES[i])
		if AudioServer.get_bus_send(i) != _BUS_SENDS[i]:
			AudioServer.set_bus_send(i, _BUS_SENDS[i])


func _setup_pool() -> void:
	for _i: int in range(POOL_2D_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_2d_pool.append(p)
	for _i: int in range(POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.bus = &"combat_kill"
		add_child(p)
		_3d_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)
	for _i: int in range(POOL_AMBIENCE_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"Ambience"
		add_child(p)
		_ambience_pool.append(p)


func _setup_sidechain_compressor() -> void:
	var music_idx: int = AudioServer.get_bus_index(&"Music")
	if music_idx == -1:
		push_error("AudioSystem: bus Music introuvable — default_bus_layout.tres corrompu")
		return
	var effect_count: int = AudioServer.get_bus_effect_count(music_idx)
	for i: int in range(effect_count):
		if AudioServer.get_bus_effect(music_idx, i) is AudioEffectCompressor:
			push_warning("AudioSystem: AudioEffectCompressor déjà présent sur Music bus, skip add (idempotent)")
			return
	var compressor: AudioEffectCompressor = AudioEffectCompressor.new()
	compressor.threshold = -24.0
	compressor.ratio = 4.0
	compressor.attack_us = 5000.0
	compressor.release_ms = 200.0
	compressor.sidechain = "combat_kill"
	AudioServer.add_bus_effect(music_idx, compressor)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func play_2d(stream: AudioStream, bus: StringName, pitch_scale: float = 1.0) -> int:
	if stream == null:
		push_error("AudioSystem.play_2d: stream is null")
		return -1
	var player: AudioStreamPlayer = _2d_pool[_2d_index]
	if player.playing:
		push_warning("AudioSystem: pool 2D saturé sur slot %d — interruption forcée" % _2d_index)
		player.stop()
	player.stream = stream
	player.bus = bus
	player.pitch_scale = pitch_scale
	player.play()
	var used_idx: int = _2d_index
	_2d_index = (_2d_index + 1) % POOL_2D_SIZE
	return used_idx


func play_3d_at(stream: AudioStream, world_pos: Vector3, bus: StringName, pitch_scale: float = 1.0) -> int:
	if stream == null:
		push_error("AudioSystem.play_3d_at: stream is null")
		return -1
	if not world_pos.is_finite():
		push_warning("AudioSystem.play_3d_at: world_pos invalid (non-finite), fallback play_2d head-locked")
		play_2d(stream, bus, pitch_scale)
		return -1
	var player: AudioStreamPlayer3D = _3d_pool[_3d_index]
	_cleanup_clac_slot_tracker(_3d_index)
	_cleanup_fixed_pitch_slot(_3d_index)
	if player.playing:
		player.stop()
	player.bus = bus
	player.global_position = world_pos
	var effective_pitch: float = pitch_scale
	if is_equal_approx(pitch_scale, 1.0) and PITCH_ALLOWLIST.get(bus, false):
		effective_pitch = _get_slow_mo_pitch_factor()
	player.pitch_scale = effective_pitch
	player.stream = stream
	player.play()
	var used_idx: int = _3d_index
	_3d_index = (_3d_index + 1) % POOL_3D_SIZE
	return used_idx


func play_music(stream: AudioStream, _fade_seconds: float = 1.0) -> void:
	if stream == null:
		push_error("AudioSystem.play_music: stream is null")
		return
	_music_player.stream = stream
	_music_player.play()


func stop_music(fade_seconds: float = 0.5) -> void:
	if not _music_player.playing:
		return
	if fade_seconds <= 0.0:
		_music_player.stop()
		_music_player.volume_db = 0.0
		_level._music_fade_out_active = false
		return
	_level._music_fade_out_duration_ms = fade_seconds * 1000.0
	_level._music_fade_out_start_msec = int(_get_time_msec.call())
	_level._music_fade_out_start_db = _music_player.volume_db
	_level._music_fade_out_active = true


func duck_bus(bus: StringName, delta_db: float, _release_ms: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx == -1:
		push_warning("AudioSystem.duck_bus: bus inconnu '%s'" % bus)
		return
	AudioServer.set_bus_volume_db(idx, AudioServer.get_bus_volume_db(idx) + delta_db)


func set_paused(paused: bool) -> void:
	AudioServer.set_bus_mute(0, paused)


func set_bus_volume_db_user(bus: StringName, db: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx == -1:
		push_warning("AudioSystem.set_bus_volume_db_user: bus inconnu '%s'" % bus)
		return
	AudioServer.set_bus_volume_db(idx, db)


# ---------------------------------------------------------------------------
# Public connection helpers (delegates to handlers)
# ---------------------------------------------------------------------------

func connect_combat_signals(combat: Node) -> void:
	_combat.connect_combat_signals(combat)

func connect_movement_signals(player: Node) -> void:
	_movement.connect_movement_signals(player)

func connect_level_signals(level: Node) -> void:
	_level.connect_level_signals(level)

func connect_secret_signals(secret_system: Node) -> void:
	_combat.connect_secret_signals(secret_system)

func validate_death_audio_duration() -> bool:
	return _movement.validate_death_audio_duration()


# ---------------------------------------------------------------------------
# _physics_process
# ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _combat._swoosh_fade_active:
		_combat.tick_swoosh_fade()
	if _combat._ducking_release_active:
		_combat.tick_ducking_release()
	if _combat._blood_pending_count > 0:
		_combat.tick_blood_queue()
	if _movement._wallrun_fade_active:
		_movement.tick_wallrun_fade()
	if _level._crossfade_active:
		_level.tick_ambient_crossfade()
	if _level._music_fade_out_active:
		_level.tick_music_fade_out()
	_tick_slow_mo_pitch_shift()


# ---------------------------------------------------------------------------
# Proxy methods — tests call these directly on AudioSystem
# ---------------------------------------------------------------------------

func _on_swing_started() -> void:
	_combat._on_swing_started()

func _on_swing_ended() -> void:
	_combat._on_swing_ended()

func _on_enemy_killed(enemy: Node, position: Vector3) -> void:
	_combat._on_enemy_killed(enemy, position)

func _on_clac_slot_finished(slot_idx: int) -> void:
	_combat._on_clac_slot_finished(slot_idx)

func _on_secret_collected(secret_node: Node, tier: int) -> void:
	_combat._on_secret_collected(secret_node, tier)

func _on_dash_started(dir: Vector3 = Vector3.ZERO, strength: float = 0.0) -> void:
	_movement._on_dash_started(dir, strength)

func _on_wall_run_entered(normal: Vector3 = Vector3.ZERO) -> void:
	_movement._on_wall_run_entered(normal)

func _on_wall_run_exited() -> void:
	_movement._on_wall_run_exited()

func _on_wall_jumped(dir: Vector3 = Vector3.ZERO, push: Vector3 = Vector3.ZERO) -> void:
	_movement._on_wall_jumped(dir, push)

func _on_died() -> void:
	_movement._on_died()

func _on_level_active(etage_id: int, player_start: Vector3) -> void:
	_level._on_level_active(etage_id, player_start)

func _on_level_unloading(etage_id: int) -> void:
	_level._on_level_unloading(etage_id)

func _on_state_changed(new_state: int) -> void:
	_level._on_state_changed(new_state)

func _tick_swoosh_fade() -> void:
	_combat.tick_swoosh_fade()

func _tick_ducking_release() -> void:
	_combat.tick_ducking_release()

func _tick_blood_queue() -> void:
	_combat.tick_blood_queue()

func _tick_wallrun_fade() -> void:
	_movement.tick_wallrun_fade()

func _tick_ambient_crossfade() -> void:
	_level.tick_ambient_crossfade()

func _tick_music_fade_out() -> void:
	_level.tick_music_fade_out()

func _start_ambient_crossfade(new_stream: AudioStream, duration_ms: float = AudioLevelHandler.AMBIENT_CROSSFADE_MS) -> void:
	_level.start_ambient_crossfade(new_stream, duration_ms)

func _connect_gsm_signals() -> void:
	_level.connect_gsm_signals(get_tree().root)

func _enter_pause() -> void:
	_level._enter_pause()

func _exit_pause() -> void:
	_level._exit_pause()

func _cleanup_clac_slot_tracker(slot_idx: int) -> void:
	_combat.cleanup_clac_slot_tracker(slot_idx, _3d_pool)

func _cleanup_fixed_pitch_slot(slot_idx: int) -> void:
	_combat.cleanup_fixed_pitch_slot(slot_idx)

func _round_robin_3d_stop_if_saturated(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= POOL_3D_SIZE:
		push_warning("AudioSystem._round_robin_3d_stop_if_saturated: slot_idx %d out of range" % slot_idx)
		return
	var player: AudioStreamPlayer3D = _3d_pool[slot_idx]
	if not player.playing:
		return
	_cleanup_clac_slot_tracker(slot_idx)
	_cleanup_fixed_pitch_slot(slot_idx)
	player.stop()
	push_warning("AudioSystem: pool 3D saturation, force-stop slot %d" % slot_idx)


# ---------------------------------------------------------------------------
# Slow-mo pitch shift (story-007)
# ---------------------------------------------------------------------------

func compute_semitones(ts: float) -> float:
	if ts <= 0.0:
		return 0.0
	return log(ts) / log(2.0) * 12.0


func _get_slow_mo_pitch_factor() -> float:
	var ts: float = Engine.time_scale
	if is_equal_approx(ts, 1.0):
		return 1.0
	if is_equal_approx(ts, _last_time_scale):
		return _last_pitch_factor
	_last_time_scale = ts
	_last_pitch_factor = pow(2.0, compute_semitones(ts) / 12.0)
	return _last_pitch_factor


func _tick_slow_mo_pitch_shift() -> void:
	var ts: float = Engine.time_scale
	var pitch_factor: float = _get_slow_mo_pitch_factor()
	for i: int in range(POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = _3d_pool[i]
		if not p.playing:
			continue
		if _combat._slot_fixed_pitch.has(i):
			continue
		if not PITCH_ALLOWLIST.get(p.bus, false):
			if not is_equal_approx(p.pitch_scale, 1.0):
				p.pitch_scale = 1.0
			continue
		if _combat._active_clac_players.has(i):
			continue
		if not is_equal_approx(p.pitch_scale, pitch_factor):
			p.pitch_scale = pitch_factor
	for i: int in range(POOL_AMBIENCE_SIZE):
		var a: AudioStreamPlayer = _ambience_pool[i]
		if not a.playing:
			continue
		if not is_equal_approx(a.pitch_scale, pitch_factor):
			a.pitch_scale = pitch_factor
	if _music_player != null and _music_player.playing:
		if not is_equal_approx(_music_player.pitch_scale, 1.0):
			_music_player.pitch_scale = 1.0
	var _suppressed: bool = not is_equal_approx(ts, 1.0)
