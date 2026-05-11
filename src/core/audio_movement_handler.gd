## AudioMovementHandler — Domaine movement audio (story-004).
## Possédé et instancié par AudioSystem (composition). Reçoit une référence
## injectée au Node AudioSystem pour appeler play_2d et accéder aux pools.
## ADR-0009 D-4 (wall-clock fades) + D-5 (signaux Movement → handlers).
## Pool exclusive (AC-AUD-12) : aucun AudioStreamPlayer*.new() ici.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const AudioMovementHandler := preload(...)`
# dans audio_system.gd. Bypass class cache CI gdUnit4-action.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DEATH_AUDIO_DURATION_MS_MIN: float = 60.0
const DEATH_AUDIO_DURATION_MS_MAX: float = 80.0
const WALLRUN_FADE_OUT_MS: float = 100.0
const SILENCE_DB: float = -80.0


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

var _audio: Node = null


# ---------------------------------------------------------------------------
# Streams
# ---------------------------------------------------------------------------

var dash_stream: AudioStream = null
var wallrun_loop_stream: AudioStream = null
var walljump_stream: AudioStream = null
var death_stream: AudioStream = null


# ---------------------------------------------------------------------------
# Movement state
# ---------------------------------------------------------------------------

var _wallrun_slot_idx: int = -1
var _wallrun_fade_active: bool = false
var _wallrun_fade_start_msec: int = 0


# ---------------------------------------------------------------------------
# Signal connection helper
# ---------------------------------------------------------------------------

## Connecte les signaux Movement → handlers en CONNECT_DEFERRED (R-AUD-5).
## Idempotent. `respawned` non connecté : silence intentionnel (Pillar 1).
func connect_movement_signals(player: Node) -> void:
	if player == null:
		push_error("AudioMovementHandler.connect_movement_signals: player is null")
		return
	if player.has_signal(&"dash_started") and not player.dash_started.is_connected(_on_dash_started):
		player.dash_started.connect(_on_dash_started, CONNECT_DEFERRED)
	if player.has_signal(&"wall_run_entered") and not player.wall_run_entered.is_connected(_on_wall_run_entered):
		player.wall_run_entered.connect(_on_wall_run_entered, CONNECT_DEFERRED)
	if player.has_signal(&"wall_run_exited") and not player.wall_run_exited.is_connected(_on_wall_run_exited):
		player.wall_run_exited.connect(_on_wall_run_exited, CONNECT_DEFERRED)
	if player.has_signal(&"wall_jumped") and not player.wall_jumped.is_connected(_on_wall_jumped):
		player.wall_jumped.connect(_on_wall_jumped, CONNECT_DEFERRED)
	if player.has_signal(&"died") and not player.died.is_connected(_on_died):
		player.died.connect(_on_died, CONNECT_DEFERRED)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_dash_started(_dir: Vector3 = Vector3.ZERO, _strength: float = 0.0) -> void:
	if dash_stream == null:
		return
	_audio.play_2d(dash_stream, &"SFX")


func _on_wall_run_entered(_normal: Vector3 = Vector3.ZERO) -> void:
	if wallrun_loop_stream == null:
		return
	_wallrun_fade_active = false
	_wallrun_slot_idx = _audio.play_2d(wallrun_loop_stream, &"SFX")


func _on_wall_run_exited() -> void:
	if _wallrun_slot_idx < 0:
		return
	_wallrun_fade_active = true
	_wallrun_fade_start_msec = int(_audio._get_time_msec.call())


func _on_wall_jumped(_dir: Vector3 = Vector3.ZERO, _push: Vector3 = Vector3.ZERO) -> void:
	if walljump_stream == null:
		return
	_audio.play_2d(walljump_stream, &"SFX")


func _on_died() -> void:
	if death_stream == null:
		return
	_audio.play_2d(death_stream, &"SFX")


# ---------------------------------------------------------------------------
# Wall-clock fade tick
# ---------------------------------------------------------------------------

func tick_wallrun_fade() -> void:
	if _wallrun_slot_idx < 0:
		_wallrun_fade_active = false
		return
	var elapsed: float = float(int(_audio._get_time_msec.call()) - _wallrun_fade_start_msec)
	var t: float = clampf(elapsed / WALLRUN_FADE_OUT_MS, 0.0, 1.0)
	var volume_db: float = lerpf(0.0, SILENCE_DB, t)
	_audio._2d_pool[_wallrun_slot_idx].volume_db = volume_db
	if t >= 1.0:
		_audio._2d_pool[_wallrun_slot_idx].stop()
		_audio._2d_pool[_wallrun_slot_idx].volume_db = 0.0
		_wallrun_slot_idx = -1
		_wallrun_fade_active = false


# ---------------------------------------------------------------------------
# Validation helper
# ---------------------------------------------------------------------------

## Valide que death_stream respecte la borne 60-80 ms (AC-AUD-07 c/d/e).
func validate_death_audio_duration() -> bool:
	if death_stream == null:
		push_error("AudioMovementHandler: death_stream null — assignation asset pipeline pending")
		return false
	var len_sec: float = death_stream.get_length()
	var len_ms: float = len_sec * 1000.0
	if len_ms < DEATH_AUDIO_DURATION_MS_MIN:
		push_error("AudioMovementHandler: death.wav %.1f ms < %d ms — perceptuellement insuffisant" % [len_ms, int(DEATH_AUDIO_DURATION_MS_MIN)])
		return false
	if len_ms > DEATH_AUDIO_DURATION_MS_MAX:
		push_error("AudioMovementHandler: death.wav %.1f ms > %d ms — overlap respawn frame trop long" % [len_ms, int(DEATH_AUDIO_DURATION_MS_MAX)])
		return false
	return true
