## AudioLevelHandler — Domaine level audio + GSM pause/resume (story-005/006).
## Possédé et instancié par AudioSystem (composition). Reçoit une référence
## injectée au Node AudioSystem pour play_music, stop_music, et accès aux pools.
## ADR-0009 D-2 (pool pré-instancié) + ADR-0007 D-4 (autorité GSM pause).
## Pool exclusive (AC-AUD-12) : aucun AudioStreamPlayer*.new() ici.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const AudioLevelHandler := preload(...)`
# dans audio_system.gd. Bypass class cache CI gdUnit4-action.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const AMBIENT_CROSSFADE_MS: float = 1000.0
const AMBIENT_UNLOAD_FADE_MS: float = 500.0
const MUSIC_FADE_OUT_MS_DEFAULT: float = 500.0
const SILENCE_DB: float = -80.0
const _CROSSFADE_AMP_FLOOR: float = 1e-4


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

var _audio: Node = null


# ---------------------------------------------------------------------------
# Level audio state
# ---------------------------------------------------------------------------

var _ambience_active_idx: int = 0
var _crossfade_active: bool = false
var _crossfade_start_msec: int = 0
var _crossfade_duration_ms: float = AMBIENT_CROSSFADE_MS
var _crossfade_old_player: AudioStreamPlayer = null
var _crossfade_new_player: AudioStreamPlayer = null
var _music_fade_out_active: bool = false
var _music_fade_out_start_msec: int = 0
var _music_fade_out_duration_ms: float = MUSIC_FADE_OUT_MS_DEFAULT
var _music_fade_out_start_db: float = 0.0

## Injection point pour lookup ETAGE_AUDIO_MAPPING. Default : retourne `{}`.
var _get_etage_audio_streams: Callable = func(_etage_id: int) -> Dictionary: return {}


# ---------------------------------------------------------------------------
# GSM pause/resume state
# ---------------------------------------------------------------------------

var _is_paused: bool = false
var _fade_pause_msec: int = 0


# ---------------------------------------------------------------------------
# Signal connection helpers
# ---------------------------------------------------------------------------

## Connecte les signaux Level → handlers en CONNECT_DEFERRED (R-AUD-5).
func connect_level_signals(level: Node) -> void:
	if level == null:
		push_error("AudioLevelHandler.connect_level_signals: level is null")
		return
	if level.has_signal(&"level_active") and not level.level_active.is_connected(_on_level_active):
		level.level_active.connect(_on_level_active, CONNECT_DEFERRED)
	if level.has_signal(&"level_unloading") and not level.level_unloading.is_connected(_on_level_unloading):
		level.level_unloading.connect(_on_level_unloading, CONNECT_DEFERRED)


## Connect au signal GSM state_changed avec CONNECT_DEFERRED.
## Idempotent. No-op gracieux si GSM autoload absent.
func connect_gsm_signals(root: Node) -> void:
	var gsm: Node = root.get_node_or_null("/root/GameStateManager")
	if gsm == null:
		return
	if not gsm.has_signal(&"state_changed"):
		return
	# Connecte AudioSystem._on_state_changed (proxy qui délègue à _level._on_state_changed)
	# au lieu de notre propre _on_state_changed handler. Préserve l'invariant que la
	# connexion appartient au Node AudioSystem (pas au RefCounted handler) pour les
	# tests d'idempotence existants (test_connect_gsm_signals_idempotent).
	if not gsm.state_changed.is_connected(_audio._on_state_changed):
		gsm.state_changed.connect(_audio._on_state_changed, CONNECT_DEFERRED)


# ---------------------------------------------------------------------------
# Level signal handlers
# ---------------------------------------------------------------------------

func _on_level_active(etage_id: int, _player_start: Vector3) -> void:
	var streams: Dictionary = _get_etage_audio_streams.call(etage_id)
	if streams.is_empty():
		push_warning("AudioLevelHandler: no audio mapping for etage_id=%d, fallback silence" % etage_id)
		return
	if streams.has(&"music") and streams[&"music"] != null:
		_audio.play_music(streams[&"music"])
	if streams.has(&"ambient") and streams[&"ambient"] != null:
		start_ambient_crossfade(streams[&"ambient"], AMBIENT_CROSSFADE_MS)


func _on_level_unloading(_etage_id: int) -> void:
	_audio.stop_music(AMBIENT_UNLOAD_FADE_MS / 1000.0)
	var old_player: AudioStreamPlayer = _audio._ambience_pool[_ambience_active_idx]
	if not old_player.playing:
		return
	_crossfade_active = true
	_crossfade_start_msec = int(_audio._get_time_msec.call())
	_crossfade_duration_ms = AMBIENT_UNLOAD_FADE_MS
	_crossfade_old_player = old_player
	_crossfade_new_player = null


# ---------------------------------------------------------------------------
# Crossfade internal logic
# ---------------------------------------------------------------------------

func start_ambient_crossfade(new_stream: AudioStream, duration_ms: float = AMBIENT_CROSSFADE_MS) -> void:
	var old_player: AudioStreamPlayer = _audio._ambience_pool[_ambience_active_idx]
	var new_idx: int = (_ambience_active_idx + 1) % _audio.POOL_AMBIENCE_SIZE
	var new_player: AudioStreamPlayer = _audio._ambience_pool[new_idx]
	new_player.stream = new_stream
	new_player.volume_db = SILENCE_DB
	new_player.pitch_scale = _audio._get_slow_mo_pitch_factor()
	new_player.play()
	if duration_ms <= 0.0:
		old_player.volume_db = SILENCE_DB
		if old_player.playing:
			old_player.stop()
		new_player.volume_db = 0.0
		push_warning("AudioLevelHandler.ambient_crossfade: duration_ms <= 0 — swap instantané")
		_ambience_active_idx = new_idx
		_crossfade_active = false
		return
	_crossfade_active = true
	_crossfade_start_msec = int(_audio._get_time_msec.call())
	_crossfade_duration_ms = duration_ms
	_crossfade_old_player = old_player
	_crossfade_new_player = new_player
	_ambience_active_idx = new_idx


# ---------------------------------------------------------------------------
# _physics_process tick handlers
# ---------------------------------------------------------------------------

func tick_ambient_crossfade() -> void:
	var elapsed: float = float(int(_audio._get_time_msec.call()) - _crossfade_start_msec)
	var t: float = clampf(elapsed / _crossfade_duration_ms, 0.0, 1.0)
	if _crossfade_old_player != null:
		var amp_old: float = lerpf(1.0, 0.0, t)
		_crossfade_old_player.volume_db = linear_to_db(maxf(amp_old, _CROSSFADE_AMP_FLOOR))
	if _crossfade_new_player != null:
		var amp_new: float = lerpf(0.0, 1.0, t)
		_crossfade_new_player.volume_db = linear_to_db(maxf(amp_new, _CROSSFADE_AMP_FLOOR))
	if t >= 1.0:
		if _crossfade_old_player != null:
			_crossfade_old_player.stop()
			_crossfade_old_player.volume_db = 0.0
		if _crossfade_new_player != null:
			_crossfade_new_player.volume_db = 0.0
		_crossfade_active = false
		_crossfade_old_player = null
		_crossfade_new_player = null


func tick_music_fade_out() -> void:
	var elapsed: float = float(int(_audio._get_time_msec.call()) - _music_fade_out_start_msec)
	var t: float = clampf(elapsed / _music_fade_out_duration_ms, 0.0, 1.0)
	var amp_start: float = db_to_linear(_music_fade_out_start_db)
	var amp_now: float = lerpf(amp_start, 0.0, t)
	_audio._music_player.volume_db = linear_to_db(maxf(amp_now, _CROSSFADE_AMP_FLOOR))
	if t >= 1.0:
		_audio._music_player.stop()
		_audio._music_player.volume_db = 0.0
		_music_fade_out_active = false


# ---------------------------------------------------------------------------
# GSM pause/resume handlers
# ---------------------------------------------------------------------------

func _on_state_changed(new_state: int) -> void:
	if new_state == 2:  # PAUSED
		_enter_pause()
	elif new_state == 1:  # PLAYING
		_exit_pause()


func _enter_pause() -> void:
	if _is_paused:
		return
	_is_paused = true
	_fade_pause_msec = int(_audio._get_time_msec.call())
	AudioServer.set_bus_mute(0, true)


func _exit_pause() -> void:
	if not _is_paused:
		return
	_is_paused = false
	var resume_msec: int = int(_audio._get_time_msec.call())
	var pause_duration_msec: int = resume_msec - _fade_pause_msec
	if _audio._combat._swoosh_fade_active:
		_audio._combat._swoosh_fade_start_msec += pause_duration_msec
	if _audio._combat._ducking_release_active:
		_audio._combat._ducking_release_start_msec += pause_duration_msec
	if _audio._movement._wallrun_fade_active:
		_audio._movement._wallrun_fade_start_msec += pause_duration_msec
	if _crossfade_active:
		_crossfade_start_msec += pause_duration_msec
	if _music_fade_out_active:
		_music_fade_out_start_msec += pause_duration_msec
	AudioServer.set_bus_mute(0, false)
