## AudioCombatHandler — Domaine combat (story-003/007/008).
## Possédé et instancié par AudioSystem (composition). Reçoit une référence
## injectée au Node AudioSystem pour appeler play_2d / play_3d_at et accéder
## aux pools. PAS un autoload — pas de class_name (référencé via preload binding
## local dans audio_system.gd pour bypass class cache CI gdUnit4-action).
## ADR-0009 D-3 (wall-clock fades) + D-4 (CONNECT_DEFERRED).
## Pool exclusive (AC-AUD-12) : aucun AudioStreamPlayer*.new() ici.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const AudioCombatHandler := preload(...)`
# dans audio_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests
# (gdUnit4-action ne build pas `.godot/global_script_class_cache.cfg`).
# Miroir pattern AutoloadResetTestSuite (commit 2edf64c).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SWING_ACTIVE_NOMINAL_DB: float = -6.0
const DUCKING_DELTA_DB: float = -6.0
const BLOOD_DELAY_MS: float = 50.0
const MAX_PITCH_RANK: int = 3
const MULTI_KILL_PITCH_SHIFT_SEMITONES: float = 2.0
const BLOOD_QUEUE_SIZE: int = 8
const SILENCE_DB: float = -80.0
const SECRET_PITCH_SCALE: float = 1.3348398541700344  # 2.0 ** (5.0/12.0)


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à AudioSystem (Node) — pour play_2d / play_3d_at / pools.
## Injectée dans AudioSystem._ready() après instanciation.
var _audio: Node = null


# ---------------------------------------------------------------------------
# Streams (injectés par le caller post-asset-load)
# ---------------------------------------------------------------------------

var swoosh_stream: AudioStream = null
var clac_stream: AudioStream = null
var blood_stream: AudioStream = null


# ---------------------------------------------------------------------------
# Combat tunables
# ---------------------------------------------------------------------------

var swoosh_fade_duration_ms: float = 30.0
var ducking_release_ms: float = 30.0


# ---------------------------------------------------------------------------
# Combat state
# ---------------------------------------------------------------------------

var _kill_count_this_swing: int = 0
var _active_clac_players: Dictionary[int, bool] = {}
var _swoosh_fade_active: bool = false
var _swoosh_fade_start_msec: int = 0
var _ducking_release_active: bool = false
var _ducking_release_start_msec: int = 0
var _clac_finished_callbacks: Array[Callable] = []
var _blood_pending_msec: PackedFloat32Array = PackedFloat32Array()
var _blood_pending_pos: PackedVector3Array = PackedVector3Array()
var _blood_pending_count: int = 0


# ---------------------------------------------------------------------------
# Slow-mo slot fixed-pitch tracker (story-008)
# ---------------------------------------------------------------------------

var _slot_fixed_pitch: Dictionary[int, float] = {}


# ---------------------------------------------------------------------------
# Init helpers
# ---------------------------------------------------------------------------

func setup_blood_queue() -> void:
	_blood_pending_msec.resize(BLOOD_QUEUE_SIZE)
	_blood_pending_pos.resize(BLOOD_QUEUE_SIZE)
	for i: int in range(BLOOD_QUEUE_SIZE):
		_blood_pending_msec[i] = -1.0


func setup_clac_callbacks(pool_3d_size: int) -> void:
	_clac_finished_callbacks.resize(pool_3d_size)
	for i: int in range(pool_3d_size):
		_clac_finished_callbacks[i] = _on_clac_slot_finished.bind(i)


func emit_boundary_warnings() -> void:
	if swoosh_fade_duration_ms <= 0.0:
		push_warning("AudioCombatHandler: swoosh_fade_duration_ms <= 0 — fade short-circuit SILENCE_DB")
	if ducking_release_ms <= 0.0:
		push_warning("AudioCombatHandler: ducking_release_ms <= 0 — release short-circuit NOMINAL_DB")


# ---------------------------------------------------------------------------
# Signal connection helper
# ---------------------------------------------------------------------------

## Connecte les signaux Combat → handlers en CONNECT_DEFERRED (R-AUD-5).
## Idempotent. Appelé runtime par init game state via AudioSystem.
func connect_combat_signals(combat: Node) -> void:
	if combat == null:
		push_error("AudioCombatHandler.connect_combat_signals: combat is null")
		return
	if combat.has_signal(&"swing_started") and not combat.swing_started.is_connected(_on_swing_started):
		combat.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
	if combat.has_signal(&"swing_ended") and not combat.swing_ended.is_connected(_on_swing_ended):
		combat.swing_ended.connect(_on_swing_ended, CONNECT_DEFERRED)
	if combat.has_signal(&"enemy_killed") and not combat.enemy_killed.is_connected(_on_enemy_killed):
		combat.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)


## Connecte le signal secret_collected → handler en CONNECT_DEFERRED (R-AUD-5).
## Idempotent. No-op gracieux si signal absent.
func connect_secret_signals(secret_system: Node) -> void:
	if secret_system == null:
		push_warning("AudioCombatHandler.connect_secret_signals: secret_system null, skip")
		return
	if not secret_system.has_signal(&"secret_collected"):
		push_warning("AudioCombatHandler.connect_secret_signals: signal 'secret_collected' absent")
		return
	if not secret_system.secret_collected.is_connected(_on_secret_collected):
		secret_system.secret_collected.connect(_on_secret_collected, CONNECT_DEFERRED)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_swing_started() -> void:
	_kill_count_this_swing = 0
	_swoosh_fade_active = false
	_set_swoosh_volume_db(SWING_ACTIVE_NOMINAL_DB)
	if swoosh_stream != null:
		_audio.play_2d(swoosh_stream, &"swing_active")


func _on_swing_ended() -> void:
	_kill_count_this_swing = 0
	_start_swoosh_fade()


func _on_enemy_killed(_enemy: Node, position: Vector3) -> void:
	_kill_count_this_swing += 1
	var rank: int = mini(_kill_count_this_swing - 1, MAX_PITCH_RANK - 1)
	var pitch_scale: float = pow(2.0, (MULTI_KILL_PITCH_SHIFT_SEMITONES * float(rank)) / 12.0)
	if clac_stream != null:
		var slot_idx: int = _audio.play_3d_at(clac_stream, position, &"combat_kill", pitch_scale)
		if slot_idx >= 0:
			_active_clac_players[slot_idx] = true
			var slot: AudioStreamPlayer3D = _audio._3d_pool[slot_idx]
			var cb: Callable = _clac_finished_callbacks[slot_idx]
			if slot.finished.is_connected(cb):
				slot.finished.disconnect(cb)
			slot.finished.connect(cb, CONNECT_ONE_SHOT)
			# lint-audio-deferred-ok: signal interne pool tracker, dispatch immediate one-shot
	_start_ducking_release()
	_schedule_blood_play(position)


func _on_clac_slot_finished(slot_idx: int) -> void:
	_active_clac_players.erase(slot_idx)


func _on_secret_collected(secret_node: Node, _tier: int) -> void:
	if not is_instance_valid(secret_node):
		push_warning("AudioCombatHandler: secret_node invalide (queue_free pré-DEFERRED), fallback play_2d head-locked")
		_audio.play_2d(clac_stream, &"SFX", SECRET_PITCH_SCALE)
		return
	var pos: Vector3 = secret_node.global_position
	if not pos.is_finite():
		push_warning("AudioCombatHandler: secret_node.global_position invalide (NaN/inf), fallback play_2d head-locked")
		_audio.play_2d(clac_stream, &"SFX", SECRET_PITCH_SCALE)
		return
	var slot_idx: int = _audio.play_3d_at(clac_stream, pos, &"SFX", SECRET_PITCH_SCALE)
	if slot_idx >= 0:
		_slot_fixed_pitch[slot_idx] = SECRET_PITCH_SCALE


# ---------------------------------------------------------------------------
# Wall-clock fade / release internal logic
# ---------------------------------------------------------------------------

func _start_swoosh_fade() -> void:
	if swoosh_fade_duration_ms <= 0.0:
		_set_swoosh_volume_db(SILENCE_DB)
		_swoosh_fade_active = false
		return
	_swoosh_fade_active = true
	_swoosh_fade_start_msec = int(_audio._get_time_msec.call())


func _start_ducking_release() -> void:
	var idx: int = AudioServer.get_bus_index(&"swing_active")
	if idx == -1:
		return
	if ducking_release_ms <= 0.0:
		AudioServer.set_bus_volume_db(idx, SWING_ACTIVE_NOMINAL_DB)
		_ducking_release_active = false
		return
	AudioServer.set_bus_volume_db(idx, SWING_ACTIVE_NOMINAL_DB + DUCKING_DELTA_DB)
	_ducking_release_active = true
	_ducking_release_start_msec = int(_audio._get_time_msec.call())


func _set_swoosh_volume_db(db: float) -> void:
	var idx: int = AudioServer.get_bus_index(&"swing_active")
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, db)


func _schedule_blood_play(position: Vector3) -> void:
	var play_at_msec: float = float(_audio._get_time_msec.call()) + BLOOD_DELAY_MS
	for i: int in range(BLOOD_QUEUE_SIZE):
		if _blood_pending_msec[i] < 0.0:
			_blood_pending_msec[i] = play_at_msec
			_blood_pending_pos[i] = position
			_blood_pending_count += 1
			return
	push_warning("AudioCombatHandler: blood queue full (>%d concurrent), drop" % BLOOD_QUEUE_SIZE)


# ---------------------------------------------------------------------------
# _physics_process tick handlers
# ---------------------------------------------------------------------------

func tick_swoosh_fade() -> void:
	var elapsed: float = float(int(_audio._get_time_msec.call()) - _swoosh_fade_start_msec)
	var t: float = clampf(elapsed / swoosh_fade_duration_ms, 0.0, 1.0)
	var volume_db: float = lerpf(SWING_ACTIVE_NOMINAL_DB, SILENCE_DB, t)
	_set_swoosh_volume_db(volume_db)
	if t >= 1.0:
		_swoosh_fade_active = false


func tick_ducking_release() -> void:
	var idx: int = AudioServer.get_bus_index(&"swing_active")
	if idx == -1:
		_ducking_release_active = false
		return
	var elapsed: float = float(int(_audio._get_time_msec.call()) - _ducking_release_start_msec)
	var t: float = clampf(elapsed / ducking_release_ms, 0.0, 1.0)
	var start_amp: float = db_to_linear(SWING_ACTIVE_NOMINAL_DB + DUCKING_DELTA_DB)
	var end_amp: float = db_to_linear(SWING_ACTIVE_NOMINAL_DB)
	var current_amp: float = lerpf(start_amp, end_amp, t)
	AudioServer.set_bus_volume_db(idx, linear_to_db(current_amp))
	if t >= 1.0:
		AudioServer.set_bus_volume_db(idx, SWING_ACTIVE_NOMINAL_DB)
		_ducking_release_active = false


func tick_blood_queue() -> void:
	if blood_stream == null:
		return
	var now: float = float(_audio._get_time_msec.call())
	for i: int in range(BLOOD_QUEUE_SIZE):
		if _blood_pending_msec[i] >= 0.0 and now >= _blood_pending_msec[i]:
			_audio.play_3d_at(blood_stream, _blood_pending_pos[i], &"Ambience", 1.0)
			_blood_pending_msec[i] = -1.0
			_blood_pending_count -= 1


# ---------------------------------------------------------------------------
# Clac tracker cleanup (pool recycle + force-stop)
# ---------------------------------------------------------------------------

func cleanup_clac_slot_tracker(slot_idx: int, pool_3d: Array) -> void:
	if not _active_clac_players.has(slot_idx):
		return
	_active_clac_players.erase(slot_idx)
	if slot_idx >= 0 and slot_idx < _clac_finished_callbacks.size():
		var slot: AudioStreamPlayer3D = pool_3d[slot_idx]
		var cb: Callable = _clac_finished_callbacks[slot_idx]
		if slot.finished.is_connected(cb):
			slot.finished.disconnect(cb)


func cleanup_fixed_pitch_slot(slot_idx: int) -> void:
	if not _slot_fixed_pitch.has(slot_idx):
		return
	_slot_fixed_pitch.erase(slot_idx)
