## AudioSystem — Autoload singleton pour la gestion audio du projet Chrome Ascent.
##
## PAS de class_name (collision potentielle class_name ↔ autoload identifiant,
## cf. mémoire feedback_godot_class_name_autoload_collision).
##
## Responsabilités story-001 :
## - Boot bus layout 7 buses UPPER_SNAKE_CASE + sidechain MUSIC ← COMBAT_KILL
## - Pool pré-alloué 20 nodes (5×2D + 12×3D + 1×Music + 2×Ambience)
## - Round-robin play_2d stub pour AC-AUD-03
##
## ADR-0009 D-1 (bus hierarchy) + D-2 (pool pré-instancié jamais étendu runtime).
## Story-001 : implémentation initiale.

extends Node


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const POOL_2D_SIZE: int = 5
const POOL_3D_SIZE: int = 12
const POOL_AMBIENCE_SIZE: int = 2

## Noms des buses dans l'ordre attendu (index 0..6).
## Convention ADR-0009 D-1 : PascalCase pour buses natifs (Master/Music/SFX/Ambience/UI)
## et snake_case pour buses enfants SFX (swing_active/combat_kill).
## Contrainte engine Godot 4.6 : bus 0 est forcé à "Master" silently par AudioServer.
const _BUS_NAMES: Array[StringName] = [
	&"Master",
	&"Music",
	&"SFX",
	&"swing_active",
	&"combat_kill",
	&"Ambience",
	&"UI",
]

## Parents attendus par index (index 0 = Master, send vers lui-même).
const _BUS_SENDS: Array[StringName] = [
	&"Master",      # Master → send vers lui-même (convention AudioServer)
	&"Master",      # Music → Master
	&"Master",      # SFX → Master
	&"SFX",         # swing_active → SFX
	&"SFX",         # combat_kill → SFX
	&"Master",      # Ambience → Master
	&"Master",      # UI → Master
]


# ---------------------------------------------------------------------------
# Pool variables
# ---------------------------------------------------------------------------

var _2d_pool: Array[AudioStreamPlayer] = []
var _3d_pool: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer = null
var _ambience_pool: Array[AudioStreamPlayer] = []

## Index round-robin courant pour play_2d / play_3d_at.
var _2d_index: int = 0
var _3d_index: int = 0

## Volume_db nominal par défaut pour duck_bus restore (set au boot).
const SILENCE_DB: float = -80.0


# ---------------------------------------------------------------------------
# Combat audio constants (story-003 — ADR-0009 D-3 + Phase D.3)
# ---------------------------------------------------------------------------

const SWING_ACTIVE_NOMINAL_DB: float = -6.0
const DUCKING_DELTA_DB: float = -6.0  # -6 dB ducking sur swing_active à enemy_killed
const BLOOD_DELAY_MS: float = 50.0
const MAX_PITCH_RANK: int = 3  # rangs 0/1/2 → +0/+2/+4 semitones cap
const MULTI_KILL_PITCH_SHIFT_SEMITONES: float = 2.0  # par rang
const BLOOD_QUEUE_SIZE: int = 8  # max kills concurrents pre-allocated, zero-alloc hot path

## Tunables Combat audio — exposés en var (pas const) pour permettre
## boundary tests D≤0/R≤0 + future migration tuning_knobs.yaml.
## Defaults figés ADR-0009 Phase D.3 / GDD r2.3 Formulas 1+2.
var swoosh_fade_duration_ms: float = 30.0
var ducking_release_ms: float = 30.0


# ---------------------------------------------------------------------------
# Combat audio state (story-003)
# ---------------------------------------------------------------------------

## Streams injectés (null-safe — handlers no-op si stream absent).
## Future stories : assignés via Resource preload depuis assets/audio/.
var swoosh_stream: AudioStream = null
var clac_stream: AudioStream = null
var blood_stream: AudioStream = null

## Counter multi-kill owned Audio (R-AUD-13). Reset à swing_started/swing_ended.
var _kill_count_this_swing: int = 0

## Tracker slots clac actifs (Phase D.3 r2.3) — utilisé par story-007 (slow-mo bus
## allowlist) pour exclure les clacs du pitch shift. Typed Dictionary : guard
## key=int slot index → value=true (présence). Cleanup pré-stop round-robin
## saturation + cleanup pré-connect si slot recyclé (orphan tracker fix).
var _active_clac_players: Dictionary[int, bool] = {}

## Wall-clock fade swoosh state (Formula 1 hardened — _physics_process tick).
var _swoosh_fade_active: bool = false
var _swoosh_fade_start_msec: int = 0

## Wall-clock release ducking state (Formula 2 perceptuel linear-amplitude lerp).
var _ducking_release_active: bool = false
var _ducking_release_start_msec: int = 0

## Pre-built Callable per slot pour zero-alloc clac finished cleanup.
var _clac_finished_callbacks: Array[Callable] = []

## Blood pending queue — pre-allocated PackedArrays zero-alloc hot path.
## Sentinel `-1.0` = slot vide. Counter `_blood_pending_count` skip loop si 0.
var _blood_pending_msec: PackedFloat32Array = PackedFloat32Array()
var _blood_pending_pos: PackedVector3Array = PackedVector3Array()
var _blood_pending_count: int = 0

## Wall-clock injection point (ADR-0006 D-5 — substituable en test).
var _get_time_msec: Callable = Time.get_ticks_msec


# ---------------------------------------------------------------------------
# Movement audio constants (story-004 — ADR-0009 D-4 + R-AUD-14)
# ---------------------------------------------------------------------------

## Bornes duration death.wav (60-80 ms — perceptuellement reconnaissable +
## overlap respawn frame autorisé sans extension RESPAWN_DELAY Pillar 3).
const DEATH_AUDIO_DURATION_MS_MIN: float = 60.0
const DEATH_AUDIO_DURATION_MS_MAX: float = 80.0

## Fade-out wall-run loop sur exit (Formula 1 hardened linear dB lerp).
const WALLRUN_FADE_OUT_MS: float = 100.0


# ---------------------------------------------------------------------------
# Movement audio state (story-004)
# ---------------------------------------------------------------------------

## Streams Movement injectés (null-safe — handlers no-op si absent).
## Future stories : assignés via Resource preload depuis assets/audio/sfx/.
var dash_stream: AudioStream = null
var wallrun_loop_stream: AudioStream = null
var walljump_stream: AudioStream = null
var death_stream: AudioStream = null

## Wall-run loop slot tracker (-1 = pas de loop actif).
var _wallrun_slot_idx: int = -1
var _wallrun_fade_active: bool = false
var _wallrun_fade_start_msec: int = 0


# ---------------------------------------------------------------------------
# Level audio constants (story-005 — ADR-0009 D-2 + ADR-0011)
# ---------------------------------------------------------------------------

## Crossfade ambient defaults — Formula 4 hardened Phase C linear-amplitude lerp.
const AMBIENT_CROSSFADE_MS: float = 1000.0
const AMBIENT_UNLOAD_FADE_MS: float = 500.0
const MUSIC_FADE_OUT_MS_DEFAULT: float = 500.0

## Log-guard pour linear_to_db (évite -inf à amp=0).
const _CROSSFADE_AMP_FLOOR: float = 1e-4


# ---------------------------------------------------------------------------
# Level audio state (story-005)
# ---------------------------------------------------------------------------

## Ambient pool toggle — 0 → Ambience[0] actif, 1 → Ambience[1] actif.
var _ambience_active_idx: int = 0

## Crossfade ambient state (Formula 4 Phase C). `_crossfade_new_player == null`
## signifie fade-out only (level_unloading path).
var _crossfade_active: bool = false
var _crossfade_start_msec: int = 0
var _crossfade_duration_ms: float = AMBIENT_CROSSFADE_MS
var _crossfade_old_player: AudioStreamPlayer = null
var _crossfade_new_player: AudioStreamPlayer = null

## Music fade-out wall-clock state (extension story-002 stub stop_music).
var _music_fade_out_active: bool = false
var _music_fade_out_start_msec: int = 0
var _music_fade_out_duration_ms: float = MUSIC_FADE_OUT_MS_DEFAULT
var _music_fade_out_start_db: float = 0.0

## Injection point pour lookup mapping ETAGE_AUDIO_MAPPING (Level epic 22 Ready
## mais API `get_etage_audio_streams` non shippée). Default : retourne `{}` →
## fallback path testé. Une fois Level shippé, AudioSystem peut wire
## `_get_etage_audio_streams = LevelSystem.get_etage_audio_streams` au boot.
var _get_etage_audio_streams: Callable = func(_etage_id: int) -> Dictionary: return {}


# ---------------------------------------------------------------------------
# GSM pause/resume state (story-006 — ADR-0009 D-1 + ADR-0007 D-4)
# ---------------------------------------------------------------------------

## True entre `_enter_pause` et `_exit_pause` — guard idempotence.
var _is_paused: bool = false

## Snapshot wall-clock msec à la frame de réception `state_changed(PAUSED)`.
## Utilisé au resume pour calculer `pause_duration = resume_msec - _fade_pause_msec`
## et offsetter tous les `*_start_msec` de fades actifs (préserve position pré-pause
## sans accélérer ni étirer le fade — wall-clock indépendant de la durée pause).
var _fade_pause_msec: int = 0


# ---------------------------------------------------------------------------
# _ready
# ---------------------------------------------------------------------------

func _ready() -> void:
	# ADR-0007 D-4 : process_mode = ALWAYS (Godot 4.6 enum value 3) pour recevoir
	# state_changed(PLAYING) DEFERRED même quand SceneTree est paused.
	# Cf. memory feedback_godot_4_6_physics_interpolation_enum.md (pattern enum
	# renumérotation 4.6 vs 4.3 — toujours utiliser symbolique, jamais hardcoder).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_bus_names()
	_setup_pool()
	_setup_sidechain_compressor()
	_setup_blood_queue()
	_setup_clac_callbacks()
	_emit_boundary_warnings()
	_connect_gsm_signals()


# ---------------------------------------------------------------------------
# Private — bus setup
# ---------------------------------------------------------------------------

## Renomme les buses 0..6 en UPPER_SNAKE_CASE (idempotent si déjà corrects).
## Godot impose "Master" comme nom par défaut pour bus 0. On le renomme en MASTER
## pour satisfaire AC-AUD-01. Aucun warning attendu sur Godot 4.6.
func _setup_bus_names() -> void:
	if AudioServer.bus_count != 7:
		push_error("AudioSystem: bus_count != 7 — default_bus_layout.tres mal configuré")
		return

	for i: int in range(7):
		var expected_name: StringName = _BUS_NAMES[i]
		if AudioServer.get_bus_name(i) != expected_name:
			AudioServer.set_bus_name(i, expected_name)
		var expected_send: StringName = _BUS_SENDS[i]
		if AudioServer.get_bus_send(i) != expected_send:
			AudioServer.set_bus_send(i, expected_send)


## Instancie le pool 20 nodes au boot. Jamais étendu runtime (ADR-0009 D-2).
func _setup_pool() -> void:
	# Pool 2D — 5 nodes → bus SFX par défaut
	for _i: int in range(POOL_2D_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"SFX"  # ok pour pool 2D et ambiance partage SFX path
		add_child(p)
		_2d_pool.append(p)

	# Pool 3D — 12 nodes → bus COMBAT_KILL par défaut
	for _i: int in range(POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.bus = &"combat_kill"
		add_child(p)
		_3d_pool.append(p)

	# Music single instance
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	add_child(_music_player)

	# Ambience — 2 nodes
	for _i: int in range(POOL_AMBIENCE_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = &"Ambience"
		add_child(p)
		_ambience_pool.append(p)


## Configure le sidechain compressor Music ← combat_kill (Phase D.2 idempotent).
## Guard : si un AudioEffectCompressor est déjà présent sur le bus Music, skip
## l'ajout et logue un warning (AC-AUD-20).
func _setup_sidechain_compressor() -> void:
	var music_idx: int = AudioServer.get_bus_index(&"Music")
	if music_idx == -1:
		push_error("AudioSystem: bus Music introuvable — default_bus_layout.tres corrompu")
		return

	# Guard idempotent — vérifie si un compressor est déjà présent
	var effect_count: int = AudioServer.get_bus_effect_count(music_idx)
	for i: int in range(effect_count):
		if AudioServer.get_bus_effect(music_idx, i) is AudioEffectCompressor:
			push_warning("AudioSystem: AudioEffectCompressor déjà présent sur Music bus, skip add (idempotent)")
			return

	var compressor: AudioEffectCompressor = AudioEffectCompressor.new()
	compressor.threshold = -24.0
	compressor.ratio = 4.0
	# attack_us = microsecondes (gotcha nommage asymétrique Godot — 5 ms = 5000 µs)
	compressor.attack_us = 5000.0
	compressor.release_ms = 200.0
	# sidechain attend un String (pas StringName) — cast explicite
	compressor.sidechain = "combat_kill"
	AudioServer.add_bus_effect(music_idx, compressor)


# ---------------------------------------------------------------------------
# Public API — verbes haut niveau (R-AUD-1)
# ---------------------------------------------------------------------------

## Joue un stream 2D depuis le pool via round-robin.
## Si le slot est occupé, le son est interrompu (saturation R-1 ADR-0009 D-2).
## Retourne l'index slot utilisé (-1 si stream null).
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
	# story-008 — pitch_scale optionnel pour secret head-locked fallback (Formula 7
	# +5 semitones invariant). Default 1.0 préserve l'historique callers (dash,
	# walljump, death, swoosh, fallback play_3d_at sans pitch).
	player.pitch_scale = pitch_scale
	player.play()
	var used_idx: int = _2d_index
	_2d_index = (_2d_index + 1) % POOL_2D_SIZE
	return used_idx


## Joue un stream 3D positionné en world space (Phase D.1 contract).
## `world_pos` DOIT être global_position de l'émetteur (pas position locale —
## sinon panning relatif parent ou (0,0,0) head-locked silencieux).
## Si `world_pos` non-finite (NaN/inf), fallback `play_2d` head-locked + push_warning.
## Retourne l'index slot pool 3D utilisé (-1 si stream null ou fallback 2D).
func play_3d_at(stream: AudioStream, world_pos: Vector3, bus: StringName, pitch_scale: float = 1.0) -> int:
	if stream == null:
		push_error("AudioSystem.play_3d_at: stream is null")
		return -1
	if not world_pos.is_finite():
		push_warning("AudioSystem.play_3d_at: world_pos invalid (non-finite), fallback play_2d head-locked")
		play_2d(stream, bus, pitch_scale)
		return -1
	var player: AudioStreamPlayer3D = _3d_pool[_3d_index]
	# story-007 Phase D.3 r2.3 — orphan tracker fix : si le slot recyclé contient
	# un clac actif, erase tracker AVANT stop() (sinon `finished` ne fire pas
	# sur force-stop, tracker resterait orphan). Idempotent disconnect aussi.
	_cleanup_clac_slot_tracker(_3d_index)
	# story-008 — cleanup parallèle tracker fixed-pitch (secret slot recyclé).
	_cleanup_fixed_pitch_slot(_3d_index)
	if player.playing:
		player.stop()
	player.bus = bus
	player.global_position = world_pos
	# story-007 AC-AUD-15-a (e) — sons démarrés pendant slow-mo : si pitch_scale
	# default (1.0) ET bus dans allowlist ET slot pas un clac (Combat handler
	# register après play_3d_at retour), pré-set pitch_factor pour zéro latence
	# 1 tick. Si caller passe pitch non-1.0 (Rule 13 multi-kill clac), préserve.
	var effective_pitch: float = pitch_scale
	if is_equal_approx(pitch_scale, 1.0) and PITCH_ALLOWLIST.get(bus, false):
		effective_pitch = _get_slow_mo_pitch_factor()
	player.pitch_scale = effective_pitch
	player.stream = stream
	player.play()
	var used_idx: int = _3d_index
	_3d_index = (_3d_index + 1) % POOL_3D_SIZE
	return used_idx


## Joue un stream music sur `_music_player` single instance.
## fade_seconds : crossfade interne (stub minimal MVP — implementation détaillée story-005).
func play_music(stream: AudioStream, _fade_seconds: float = 1.0) -> void:
	if stream == null:
		push_error("AudioSystem.play_music: stream is null")
		return
	_music_player.stream = stream
	_music_player.play()


## Stop music avec fade-out wall-clock (Formula 4 Phase C linear-amplitude lerp,
## indep `Engine.time_scale`). `fade_seconds <= 0.0` → stop instantané.
## Cumul-safe : si fade en cours, restart depuis volume_db courant.
func stop_music(fade_seconds: float = 0.5) -> void:
	if not _music_player.playing:
		return
	if fade_seconds <= 0.0:
		_music_player.stop()
		_music_player.volume_db = 0.0
		_music_fade_out_active = false
		return
	_music_fade_out_duration_ms = fade_seconds * 1000.0
	_music_fade_out_start_msec = int(_get_time_msec.call())
	_music_fade_out_start_db = _music_player.volume_db
	_music_fade_out_active = true


## Applique ducking instantané sur un bus (delta_db négatif = atténuation).
## Release wall-clock délégué story-003 Combat handlers (Formula 2 perceptuel).
func duck_bus(bus: StringName, delta_db: float, _release_ms: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx == -1:
		push_warning("AudioSystem.duck_bus: bus inconnu '%s'" % bus)
		return
	var current_db: float = AudioServer.get_bus_volume_db(idx)
	AudioServer.set_bus_volume_db(idx, current_db + delta_db)


## Mute/unmute Master bus (préserve queue audio, pas de stream_paused individuel).
## State preservation `_fade_pause_msec` offset → story-006 GSM handler.
func set_paused(paused: bool) -> void:
	AudioServer.set_bus_mute(0, paused)


## Set volume_db user pour bus (sliders settings UI Tier 2).
## MVP : accepte tous les buses ; allowlist UI optionnelle future.
func set_bus_volume_db_user(bus: StringName, db: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx == -1:
		push_warning("AudioSystem.set_bus_volume_db_user: bus inconnu '%s'" % bus)
		return
	AudioServer.set_bus_volume_db(idx, db)


# ---------------------------------------------------------------------------
# Combat audio — boot setup helpers (story-003)
# ---------------------------------------------------------------------------

## Pre-alloc blood pending queue (zero-alloc hot path — slots réutilisés).
func _setup_blood_queue() -> void:
	_blood_pending_msec.resize(BLOOD_QUEUE_SIZE)
	_blood_pending_pos.resize(BLOOD_QUEUE_SIZE)
	for i: int in range(BLOOD_QUEUE_SIZE):
		_blood_pending_msec[i] = -1.0  # sentinel = slot vide


## Pre-build Callable per slot pour Phase D.3 finished cleanup zero-alloc.
## Sans pré-build, chaque `bind(slot_idx)` allouerait un Callable temporaire
## qui empêcherait `is_connected` de matcher (chaque bind = nouvelle Callable).
func _setup_clac_callbacks() -> void:
	_clac_finished_callbacks.resize(POOL_3D_SIZE)
	for i: int in range(POOL_3D_SIZE):
		_clac_finished_callbacks[i] = _on_clac_slot_finished.bind(i)


## Boot guards — D≤0/R≤0 boundaries logged 1× pour diagnostic prod misconfig.
func _emit_boundary_warnings() -> void:
	if swoosh_fade_duration_ms <= 0.0:
		push_warning("AudioSystem: swoosh_fade_duration_ms <= 0 — fade short-circuit SILENCE_DB")
	if ducking_release_ms <= 0.0:
		push_warning("AudioSystem: ducking_release_ms <= 0 — release short-circuit NOMINAL_DB")


# ---------------------------------------------------------------------------
# Combat audio — public connection helper (story-003)
# ---------------------------------------------------------------------------

## Connecte les signaux Combat → handlers Audio en CONNECT_DEFERRED (R-AUD-5).
## Idempotent : skip si déjà connecté. Appelé runtime par init game state.
func connect_combat_signals(combat: Node) -> void:
	if combat == null:
		push_error("AudioSystem.connect_combat_signals: combat is null")
		return
	if combat.has_signal(&"swing_started") and not combat.swing_started.is_connected(_on_swing_started):
		combat.swing_started.connect(_on_swing_started, CONNECT_DEFERRED)
	if combat.has_signal(&"swing_ended") and not combat.swing_ended.is_connected(_on_swing_ended):
		combat.swing_ended.connect(_on_swing_ended, CONNECT_DEFERRED)
	if combat.has_signal(&"enemy_killed") and not combat.enemy_killed.is_connected(_on_enemy_killed):
		combat.enemy_killed.connect(_on_enemy_killed, CONNECT_DEFERRED)


# ---------------------------------------------------------------------------
# Combat audio — signal handlers (story-003)
# ---------------------------------------------------------------------------

## Handler swing_started (CONNECT_DEFERRED) :
##   - Reset multi-kill counter (R-AUD-13 + AC-AUD-17)
##   - Cancel any pending swoosh fade + restore swing_active bus à NOMINAL
##   - Joue swoosh sur bus swing_active (null-safe)
func _on_swing_started() -> void:
	_kill_count_this_swing = 0
	_swoosh_fade_active = false
	_set_swoosh_volume_db(SWING_ACTIVE_NOMINAL_DB)
	if swoosh_stream != null:
		play_2d(swoosh_stream, &"swing_active")


## Handler swing_ended (CONNECT_DEFERRED) :
##   - Reset multi-kill counter (AC-AUD-17 — pas carry-over rang +6 bug)
##   - Démarre fade swoosh wall-clock 30 ms (Formula 1)
func _on_swing_ended() -> void:
	_kill_count_this_swing = 0
	_start_swoosh_fade()


## Handler enemy_killed (CONNECT_DEFERRED) — capture position au tick d'émission
## côté Combat (R-AUD-7 + ADR-0006 D-3) ; ici on consomme le payload.
##   - Increment counter, calcule rang +0/+2/+4 cap (AC-AUD-05)
##   - Joue clac 3D positioned avec pitch_scale (asset reuse R-AUD-13)
##   - Track slot dans _active_clac_players (Phase D.3 → story-007 allowlist)
##   - Démarre ducking swing_active -6 dB instantané + release wall-clock (AC-AUD-06)
##   - Schedule blood ambiance 50 ms post-clac (R-AUD-12 ordering)
func _on_enemy_killed(_enemy: Node, position: Vector3) -> void:
	_kill_count_this_swing += 1
	var rank: int = mini(_kill_count_this_swing - 1, MAX_PITCH_RANK - 1)
	var pitch_scale: float = pow(2.0, (MULTI_KILL_PITCH_SHIFT_SEMITONES * float(rank)) / 12.0)
	if clac_stream != null:
		var slot_idx: int = play_3d_at(clac_stream, position, &"combat_kill", pitch_scale)
		if slot_idx >= 0:
			_active_clac_players[slot_idx] = true
			# Phase D.3 — auto-cleanup tracker quand slot finit naturellement
			var slot: AudioStreamPlayer3D = _3d_pool[slot_idx]
			var cb: Callable = _clac_finished_callbacks[slot_idx]
			if slot.finished.is_connected(cb):
				slot.finished.disconnect(cb)
			slot.finished.connect(cb, CONNECT_ONE_SHOT)
	_start_ducking_release()
	_schedule_blood_play(position)


## Cleanup tracker quand un slot clac finit (CONNECT_ONE_SHOT auto-disconnect).
func _on_clac_slot_finished(slot_idx: int) -> void:
	_active_clac_players.erase(slot_idx)


# ---------------------------------------------------------------------------
# Combat audio — wall-clock fade/release internal logic (story-003)
# ---------------------------------------------------------------------------

## Démarre fade swoosh — boundary D≤0 short-circuit SILENCE_DB immédiat.
func _start_swoosh_fade() -> void:
	if swoosh_fade_duration_ms <= 0.0:
		_set_swoosh_volume_db(SILENCE_DB)
		_swoosh_fade_active = false
		return
	_swoosh_fade_active = true
	_swoosh_fade_start_msec = int(_get_time_msec.call())


## Démarre ducking release — boundary R≤0 short-circuit NOMINAL immédiat.
## Set bus directement à (NOMINAL + DELTA) = -12 dB instantané (1 frame),
## puis release wall-clock vers NOMINAL via Formula 2 perceptuel.
## Si ducking déjà actif (rapid kills), restart from -12 (no accumulation).
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
	_ducking_release_start_msec = int(_get_time_msec.call())


## Set volume_db sur bus swing_active (helper interne).
func _set_swoosh_volume_db(db: float) -> void:
	var idx: int = AudioServer.get_bus_index(&"swing_active")
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, db)


## Schedule un blood play à `now + BLOOD_DELAY_MS` wall-clock dans pool pré-alloué.
## Si queue saturée (>8 concurrent kills), drop + push_warning (limite Combat = 3/swing).
func _schedule_blood_play(position: Vector3) -> void:
	var play_at_msec: float = float(_get_time_msec.call()) + BLOOD_DELAY_MS
	for i: int in range(BLOOD_QUEUE_SIZE):
		if _blood_pending_msec[i] < 0.0:
			_blood_pending_msec[i] = play_at_msec
			_blood_pending_pos[i] = position
			_blood_pending_count += 1
			return
	push_warning("AudioSystem: blood queue full (>%d concurrent), drop" % BLOOD_QUEUE_SIZE)


# ---------------------------------------------------------------------------
# Combat audio — _physics_process tick (story-003)
# ---------------------------------------------------------------------------

## Wall-clock tick (60 Hz garanti main thread) pour fades + release + blood queue.
## Skip rapide si rien d'actif (zero-cost when idle).
func _physics_process(_delta: float) -> void:
	if _swoosh_fade_active:
		_tick_swoosh_fade()
	if _ducking_release_active:
		_tick_ducking_release()
	if _blood_pending_count > 0:
		_tick_blood_queue()
	if _wallrun_fade_active:
		_tick_wallrun_fade()
	if _crossfade_active:
		_tick_ambient_crossfade()
	if _music_fade_out_active:
		_tick_music_fade_out()
	# story-007 — slow-mo pitch shift bus allowlist (Formula 5 + Phase D.3 tracker
	# clac exclusion). Tick chaque physics frame : detect Engine.time_scale
	# change → apply pitch_factor sur slots allowlist non-clac, restore invariants
	# (1.0) sur slots hors allowlist ou clacs.
	_tick_slow_mo_pitch_shift()


## Formula 1 hardened — fade swoosh linear dB lerp NOMINAL → SILENCE sur D ms.
func _tick_swoosh_fade() -> void:
	var elapsed: float = float(int(_get_time_msec.call()) - _swoosh_fade_start_msec)
	var t: float = clampf(elapsed / swoosh_fade_duration_ms, 0.0, 1.0)
	var volume_db: float = lerpf(SWING_ACTIVE_NOMINAL_DB, SILENCE_DB, t)
	_set_swoosh_volume_db(volume_db)
	if t >= 1.0:
		_swoosh_fade_active = false


## Formula 2 perceptuel hardened — release ducking via linear-amplitude lerp
## puis convert back to dB. À t=0.5, db ≈ -8.5 (vs -9.0 si dB-linear lerp).
func _tick_ducking_release() -> void:
	var idx: int = AudioServer.get_bus_index(&"swing_active")
	if idx == -1:
		_ducking_release_active = false
		return
	var elapsed: float = float(int(_get_time_msec.call()) - _ducking_release_start_msec)
	var t: float = clampf(elapsed / ducking_release_ms, 0.0, 1.0)
	var start_amp: float = db_to_linear(SWING_ACTIVE_NOMINAL_DB + DUCKING_DELTA_DB)
	var end_amp: float = db_to_linear(SWING_ACTIVE_NOMINAL_DB)
	var current_amp: float = lerpf(start_amp, end_amp, t)
	AudioServer.set_bus_volume_db(idx, linear_to_db(current_amp))
	if t >= 1.0:
		AudioServer.set_bus_volume_db(idx, SWING_ACTIVE_NOMINAL_DB)
		_ducking_release_active = false


## Joue les blood ambiances dont le wall-clock delay est écoulé.
## Note : pitch_scale=1.0 passé ici car bus &"Ambience" est dans PITCH_ALLOWLIST
## → play_3d_at applique automatiquement _get_slow_mo_pitch_factor() (story-007
## AC-AUD-15-a (e) zéro latence 1 tick).
func _tick_blood_queue() -> void:
	if blood_stream == null:
		return
	var now: float = float(_get_time_msec.call())
	for i: int in range(BLOOD_QUEUE_SIZE):
		if _blood_pending_msec[i] >= 0.0 and now >= _blood_pending_msec[i]:
			play_3d_at(blood_stream, _blood_pending_pos[i], &"Ambience", 1.0)
			_blood_pending_msec[i] = -1.0
			_blood_pending_count -= 1


# ---------------------------------------------------------------------------
# Movement audio — public connection helper (story-004)
# ---------------------------------------------------------------------------

## Connecte les signaux Movement → handlers Audio en CONNECT_DEFERRED (R-AUD-5).
## Idempotent : skip si déjà connecté. Appelé runtime par init game state.
## `respawned` non connecté : silence intentionnel post-respawn (clarté Pillar 1).
func connect_movement_signals(player: Node) -> void:
	if player == null:
		push_error("AudioSystem.connect_movement_signals: player is null")
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
# Movement audio — signal handlers (story-004)
# ---------------------------------------------------------------------------

## Handler dash_started (CONNECT_DEFERRED) — joue dash 2D head-locked SFX.
## Args ignorés (signature flexible : Godot tolère handler avec moins d'args).
func _on_dash_started(_dir: Vector3 = Vector3.ZERO, _strength: float = 0.0) -> void:
	if dash_stream == null:
		return
	play_2d(dash_stream, &"SFX")


## Handler wall_run_entered (CONNECT_DEFERRED) — démarre loop infinie 2D.
## Track slot pour fade-out déclenché par wall_run_exited.
func _on_wall_run_entered(_normal: Vector3 = Vector3.ZERO) -> void:
	if wallrun_loop_stream == null:
		return
	# Cancel fade en cours si re-entry pendant fade (rare mais safe)
	_wallrun_fade_active = false
	_wallrun_slot_idx = play_2d(wallrun_loop_stream, &"SFX")


## Handler wall_run_exited (CONNECT_DEFERRED) — démarre fade-out 100 ms wall-clock.
## Si pas de slot actif (corner case), no-op.
func _on_wall_run_exited() -> void:
	if _wallrun_slot_idx < 0:
		return
	_wallrun_fade_active = true
	_wallrun_fade_start_msec = int(_get_time_msec.call())


## Handler wall_jumped (CONNECT_DEFERRED) — joue walljump 2D head-locked.
func _on_wall_jumped(_dir: Vector3 = Vector3.ZERO, _push: Vector3 = Vector3.ZERO) -> void:
	if walljump_stream == null:
		return
	play_2d(walljump_stream, &"SFX")


## Handler died (CONNECT_DEFERRED) — joue death 2D head-locked SFX.
## Pillar 3 : overlap première frame respawn autorisé (queue audio Godot survit
## scene reload — ne PAS étendre RESPAWN_DELAY pour accommoder son).
func _on_died() -> void:
	if death_stream == null:
		return
	play_2d(death_stream, &"SFX")


# ---------------------------------------------------------------------------
# Movement audio — wall-clock fade tick (story-004)
# ---------------------------------------------------------------------------

## Formula 1 hardened — fade wall-run loop linear dB lerp NOMINAL → SILENCE
## sur WALLRUN_FADE_OUT_MS (100 ms wall-clock, indep Engine.time_scale).
## À t=1.0 : stop slot + reset tracker.
func _tick_wallrun_fade() -> void:
	if _wallrun_slot_idx < 0:
		_wallrun_fade_active = false
		return
	var elapsed: float = float(int(_get_time_msec.call()) - _wallrun_fade_start_msec)
	var t: float = clampf(elapsed / WALLRUN_FADE_OUT_MS, 0.0, 1.0)
	var volume_db: float = lerpf(0.0, SILENCE_DB, t)
	_2d_pool[_wallrun_slot_idx].volume_db = volume_db
	if t >= 1.0:
		_2d_pool[_wallrun_slot_idx].stop()
		_2d_pool[_wallrun_slot_idx].volume_db = 0.0  # restore default pour reuse round-robin
		_wallrun_slot_idx = -1
		_wallrun_fade_active = false


# ---------------------------------------------------------------------------
# Movement audio — duration validation helper (story-004)
# ---------------------------------------------------------------------------

## Valide que `death_stream` respecte la borne 60-80 ms (AC-AUD-07 c/d/e).
## Retourne true si OK ; false + push_error si stream null/duration hors bornes.
## Appelable au boot game state (post-asset-load) ou en test.
func validate_death_audio_duration() -> bool:
	if death_stream == null:
		push_error("AudioSystem: death_stream null — assignation asset pipeline pending")
		return false
	var len_sec: float = death_stream.get_length()
	var len_ms: float = len_sec * 1000.0
	if len_ms < DEATH_AUDIO_DURATION_MS_MIN:
		push_error("AudioSystem: death.wav %.1f ms < %d ms — perceptuellement insuffisant" % [len_ms, int(DEATH_AUDIO_DURATION_MS_MIN)])
		return false
	if len_ms > DEATH_AUDIO_DURATION_MS_MAX:
		push_error("AudioSystem: death.wav %.1f ms > %d ms — overlap respawn frame trop long" % [len_ms, int(DEATH_AUDIO_DURATION_MS_MAX)])
		return false
	return true


# ---------------------------------------------------------------------------
# Level audio — public connection helper (story-005)
# ---------------------------------------------------------------------------

## Connecte les signaux Level → handlers Audio en CONNECT_DEFERRED (R-AUD-5).
## Idempotent : skip si déjà connecté. Appelé runtime par init game state.
func connect_level_signals(level: Node) -> void:
	if level == null:
		push_error("AudioSystem.connect_level_signals: level is null")
		return
	if level.has_signal(&"level_active") and not level.level_active.is_connected(_on_level_active):
		level.level_active.connect(_on_level_active, CONNECT_DEFERRED)
	if level.has_signal(&"level_unloading") and not level.level_unloading.is_connected(_on_level_unloading):
		level.level_unloading.connect(_on_level_unloading, CONNECT_DEFERRED)


# ---------------------------------------------------------------------------
# Level audio — signal handlers (story-005)
# ---------------------------------------------------------------------------

## Handler level_active (CONNECT_DEFERRED) — lookup mapping ETAGE_AUDIO_MAPPING
## via injection `_get_etage_audio_streams`, puis `play_music` + crossfade ambient.
## Fallback : mapping vide → push_warning + return early (music précédente continue).
func _on_level_active(etage_id: int, _player_start: Vector3) -> void:
	var streams: Dictionary = _get_etage_audio_streams.call(etage_id)
	if streams.is_empty():
		push_warning("AudioSystem: no audio mapping for etage_id=%d, fallback silence" % etage_id)
		return
	if streams.has(&"music") and streams[&"music"] != null:
		play_music(streams[&"music"])
	if streams.has(&"ambient") and streams[&"ambient"] != null:
		_start_ambient_crossfade(streams[&"ambient"], AMBIENT_CROSSFADE_MS)


## Handler level_unloading (CONNECT_DEFERRED) — fade-out music + ambient 0.5 s.
## Music : `stop_music(0.5)` → fade-out wall-clock Formula 4 Phase C.
## Ambient : reuse crossfade pipeline avec `_crossfade_new_player = null` →
## fade-out only (pas de swap idx, pas de nouvelle source).
func _on_level_unloading(_etage_id: int) -> void:
	stop_music(AMBIENT_UNLOAD_FADE_MS / 1000.0)
	var old_player: AudioStreamPlayer = _ambience_pool[_ambience_active_idx]
	if not old_player.playing:
		return
	_crossfade_active = true
	_crossfade_start_msec = int(_get_time_msec.call())
	_crossfade_duration_ms = AMBIENT_UNLOAD_FADE_MS
	_crossfade_old_player = old_player
	_crossfade_new_player = null


# ---------------------------------------------------------------------------
# Level audio — crossfade internal logic (story-005)
# ---------------------------------------------------------------------------

## Démarre crossfade ambient — boundary D≤0 short-circuit swap instantané.
## Toggle `_ambience_active_idx` 0↔1 pour round-robin double buffer.
func _start_ambient_crossfade(new_stream: AudioStream, duration_ms: float = AMBIENT_CROSSFADE_MS) -> void:
	var old_player: AudioStreamPlayer = _ambience_pool[_ambience_active_idx]
	var new_idx: int = (_ambience_active_idx + 1) % POOL_AMBIENCE_SIZE
	var new_player: AudioStreamPlayer = _ambience_pool[new_idx]
	new_player.stream = new_stream
	new_player.volume_db = SILENCE_DB
	# story-007 AC-AUD-15-a (b) — ambient bus dans allowlist : pré-set
	# pitch_scale au play (zéro latence 1 tick) si slow-mo actif.
	new_player.pitch_scale = _get_slow_mo_pitch_factor()
	new_player.play()
	if duration_ms <= 0.0:
		old_player.volume_db = SILENCE_DB
		if old_player.playing:
			old_player.stop()
		new_player.volume_db = 0.0
		push_warning("AudioSystem.ambient_crossfade: duration_ms <= 0 — swap instantané")
		_ambience_active_idx = new_idx
		_crossfade_active = false
		return
	_crossfade_active = true
	_crossfade_start_msec = int(_get_time_msec.call())
	_crossfade_duration_ms = duration_ms
	_crossfade_old_player = old_player
	_crossfade_new_player = new_player
	_ambience_active_idx = new_idx


# ---------------------------------------------------------------------------
# Level audio — _physics_process tick handlers (story-005)
# ---------------------------------------------------------------------------

## Formula 4 hardened Phase C — linear-amplitude lerp (PAS dB-domain lerp r2 stale).
## À t=0.5, amp_old=0.5 → linear_to_db(0.5) ≈ -6 dB (perceptuellement uniforme,
## pas le dip ~3 dB du dB-domain bug).
## `_crossfade_new_player == null` → fade-out only (level_unloading path).
func _tick_ambient_crossfade() -> void:
	var elapsed: float = float(int(_get_time_msec.call()) - _crossfade_start_msec)
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
			_crossfade_old_player.volume_db = 0.0  # restore default pour reuse round-robin
		if _crossfade_new_player != null:
			_crossfade_new_player.volume_db = 0.0  # snap exact 0 dB (post-log-guard)
		_crossfade_active = false
		_crossfade_old_player = null
		_crossfade_new_player = null


## Music fade-out wall-clock — Formula 4 Phase C linear-amplitude lerp depuis
## `_music_fade_out_start_db` vers SILENCE. À t=1.0 : stop + restore volume_db 0.
func _tick_music_fade_out() -> void:
	var elapsed: float = float(int(_get_time_msec.call()) - _music_fade_out_start_msec)
	var t: float = clampf(elapsed / _music_fade_out_duration_ms, 0.0, 1.0)
	var amp_start: float = db_to_linear(_music_fade_out_start_db)
	var amp_now: float = lerpf(amp_start, 0.0, t)
	_music_player.volume_db = linear_to_db(maxf(amp_now, _CROSSFADE_AMP_FLOOR))
	if t >= 1.0:
		_music_player.stop()
		_music_player.volume_db = 0.0  # restore pour reuse
		_music_fade_out_active = false


# ---------------------------------------------------------------------------
# GSM pause/resume handlers (story-006 — AC-AUD-08/09)
# ---------------------------------------------------------------------------

## Connect au signal GSM `state_changed` avec CONNECT_DEFERRED (R-AUD-5 + ADR-0007 D-10).
## Idempotent (no-op si déjà connecté). No-op gracieux si GSM autoload absent
## (test fixtures peuvent invoquer `_on_state_changed` directement).
func _connect_gsm_signals() -> void:
	var gsm: Node = get_node_or_null("/root/GameStateManager")
	if gsm == null:
		return
	if not gsm.has_signal(&"state_changed"):
		return
	if not gsm.state_changed.is_connected(_on_state_changed):
		gsm.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)


## Handler GSM state_changed — dispatch PAUSED/PLAYING vers enter/exit pause.
## Autres états (MENU, RESPAWNING, BOSS_DEFEATED) : no-op ici (Audio outbound-only,
## pas d'autorité game flow — autorité GSM seul ADR-0007 D-4).
func _on_state_changed(new_state: int) -> void:
	# Lookup enum via get_node — évite hard dependency compile-time sur GameStateManager.
	# Valeurs canoniques GSM : MENU=0, PLAYING=1, PAUSED=2, RESPAWNING=3, BOSS_DEFEATED=4.
	if new_state == 2:  # PAUSED
		_enter_pause()
	elif new_state == 1:  # PLAYING
		_exit_pause()


## Mute Master bus + snapshot wall-clock pour offset post-resume.
## Idempotent (no-op si déjà paused — guard contre double emit GSM).
func _enter_pause() -> void:
	if _is_paused:
		return
	_is_paused = true
	_fade_pause_msec = int(_get_time_msec.call())
	# AC-AUD-08 (a) : mute MASTER bus 0 — préserve queue audio (R-AUD-10).
	# Pas de stream_paused individuel : queue Godot survit, sample continue
	# d'avancer en interne (non audible), reprend là où il était sur unmute.
	AudioServer.set_bus_mute(0, true)


## Unmute Master + offset wall-clock sur tous les `*_start_msec` de fades actifs.
## Préserve position pré-pause exacte (fade pré-pause à t=15ms reprend à t=15ms,
## PAS à t=15ms+pause_duration qui aurait fini depuis longtemps).
func _exit_pause() -> void:
	if not _is_paused:
		return
	_is_paused = false
	var resume_msec: int = int(_get_time_msec.call())
	var pause_duration_msec: int = resume_msec - _fade_pause_msec
	# AC-AUD-09 (b) : décaler les timestamps de départ des fades actifs.
	# Fade actif post-resume : elapsed = resume_msec + dt - (start_msec + pause_duration)
	#                                  = (resume_msec - start_msec - pause_duration) + dt
	#                                  = elapsed_pre_pause + dt    ← reprend exactement où il était
	if _swoosh_fade_active:
		_swoosh_fade_start_msec += pause_duration_msec
	if _ducking_release_active:
		_ducking_release_start_msec += pause_duration_msec
	if _wallrun_fade_active:
		_wallrun_fade_start_msec += pause_duration_msec
	if _crossfade_active:
		_crossfade_start_msec += pause_duration_msec
	if _music_fade_out_active:
		_music_fade_out_start_msec += pause_duration_msec
	AudioServer.set_bus_mute(0, false)


# ---------------------------------------------------------------------------
# Slow-mo pitch shift bus allowlist + clac exclusion (story-007 — ADR-0009 D-3 r2)
# ---------------------------------------------------------------------------

## Allowlist per-bus pour pitch shift slow-mo (Rule 11 r2 — bus invariants vs
## bus pitch-shifted). True = bus subit Formula 5 sous slow-mo ; False = invariant.
## - COMBAT_KILL : queue blood ambiance (slot clac exclu via _active_clac_players)
## - AMBIENCE : room tone HLM drone (perceptuellement uniforme avec game time)
## - Autres (MASTER/MUSIC/SFX/SWING_ACTIVE/UI) : invariant 1.0 (Pillar Player Fantasy)
const PITCH_ALLOWLIST: Dictionary[StringName, bool] = {
	&"Master": false,
	&"Music": false,
	&"SFX": false,
	&"swing_active": false,
	&"combat_kill": true,
	&"Ambience": true,
	&"UI": false,
}

## Cache du dernier pitch_factor calculé — évite recompute log() chaque tick si
## time_scale stable. Reset à 0.0 force recompute initial.
var _last_pitch_factor: float = 1.0
var _last_time_scale: float = 1.0


## Compute Formula 5 — semitones offset pour un time_scale donné.
## `compute_semitones(0.3) ≈ -2.1` → pitch_factor = 2^(-2.1/12) ≈ 0.8821.
## `compute_semitones(1.0) == 0.0` → pitch_factor = 1.0 (no shift).
func compute_semitones(ts: float) -> float:
	if ts <= 0.0:
		return 0.0  # guard log domain
	return log(ts) / log(2.0) * 12.0


## Retourne pitch_factor courant pour bus dans allowlist. 1.0 si pas de slow-mo.
## Utilisé par handlers dispatch (_tick_blood_queue, _start_ambient_crossfade,
## play_3d_at default-pitch path) pour pré-set pitch AU MOMENT DU play() — zéro
## latence 1 tick (AC-AUD-15-a (e)).
func _get_slow_mo_pitch_factor() -> float:
	var ts: float = Engine.time_scale
	if is_equal_approx(ts, 1.0):
		return 1.0
	# Cache hit : recompute évité (zero-alloc hot path).
	if is_equal_approx(ts, _last_time_scale):
		return _last_pitch_factor
	_last_time_scale = ts
	_last_pitch_factor = pow(2.0, compute_semitones(ts) / 12.0)
	return _last_pitch_factor


## Per-tick : detect Engine.time_scale → apply pitch_factor sur slots allowlist
## non-clac, restore invariants 1.0 sur slots hors allowlist OU clacs.
## Couvre cas runtime : slow-mo activé pendant qu'un son joue déjà → re-pitch
## au prochain tick (e.g. ambient bouclant pendant slow-mo step).
## Skip rapide si time_scale==1.0 ET aucun slot n'a pitch != 1.0.
func _tick_slow_mo_pitch_shift() -> void:
	var ts: float = Engine.time_scale
	var slow_mo_active: bool = not is_equal_approx(ts, 1.0)
	var pitch_factor: float = _get_slow_mo_pitch_factor()
	# Iterate _3d_pool — applique pitch ou invariant selon allowlist + tracker clac.
	for i: int in range(POOL_3D_SIZE):
		var p: AudioStreamPlayer3D = _3d_pool[i]
		if not p.playing:
			continue
		# story-008 — slot avec fixed pitch user (secret SECRET_PITCH_SCALE) :
		# préserve quel que soit le bus, AVANT check allowlist (sinon SFX
		# secret serait reseté à 1.0). Couvre AC-AUD-19 (a-c) invariant slow-mo.
		if _slot_fixed_pitch.has(i):
			continue
		# Hors allowlist (SWING_ACTIVE, MUSIC, SFX, UI) : invariant 1.0.
		if not PITCH_ALLOWLIST.get(p.bus, false):
			if not is_equal_approx(p.pitch_scale, 1.0):
				p.pitch_scale = 1.0
			continue
		# Slot clac (Phase D.3 tracker) : préserve Rule 13 multi-kill pitch.
		if _active_clac_players.has(i):
			continue
		# Bus dans allowlist + slot non-clac : applique pitch_factor (1.0 ou Formula 5).
		if not is_equal_approx(p.pitch_scale, pitch_factor):
			p.pitch_scale = pitch_factor
	# Iterate _ambience_pool — bus AMBIENCE en allowlist, jamais clac.
	for i: int in range(POOL_AMBIENCE_SIZE):
		var a: AudioStreamPlayer = _ambience_pool[i]
		if not a.playing:
			continue
		if not is_equal_approx(a.pitch_scale, pitch_factor):
			a.pitch_scale = pitch_factor
	# _music_player : bus MUSIC hors allowlist → invariant 1.0 toujours.
	if _music_player != null and _music_player.playing:
		if not is_equal_approx(_music_player.pitch_scale, 1.0):
			_music_player.pitch_scale = 1.0
	# Suppress unused var warning (slow_mo_active gardé pour clarté logique).
	var _suppressed: bool = slow_mo_active


## Phase D.3 r2.3 fix — cleanup tracker clac AVANT stop()/recyclage round-robin.
## Si slot N est dans _active_clac_players, erase tracker + disconnect callback
## one-shot (sinon `finished` ne fire pas sur force-stop, tracker resterait orphan).
## Idempotent : no-op si slot pas dans tracker. Zero-alloc (pas de set/array temp).
func _cleanup_clac_slot_tracker(slot_idx: int) -> void:
	if not _active_clac_players.has(slot_idx):
		return
	_active_clac_players.erase(slot_idx)
	if slot_idx >= 0 and slot_idx < _clac_finished_callbacks.size():
		var slot: AudioStreamPlayer3D = _3d_pool[slot_idx]
		var cb: Callable = _clac_finished_callbacks[slot_idx]
		if slot.finished.is_connected(cb):
			slot.finished.disconnect(cb)


## Force-stop slot 3D (round-robin saturation guard, Phase D.3 r2.3).
## Wrapper public pour tests : appelle cleanup_clac_slot_tracker AVANT stop()
## puis push_warning. play_3d_at fait déjà cleanup inline ; cette fonction
## existe pour scénarios externes (e.g. boss death force-stop tous les pool).
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
# Secret audio handler — Rule 17 r2.2 + Formula 7 (story-008)
# ADR-0009 D-3 (allowlist) + D-5 (spatialisation 3D positional)
# ---------------------------------------------------------------------------

## Secret pitch shift +5 semitones — Formula 7 absolu (PAS composite Formula 5
## slow-mo). `2.0 ** (5/12) ≈ 1.3348`. Bus `SFX` exclusif (PAS `COMBAT_KILL` —
## sidechain n'arme pas, Couche 1 silence rythmique combat invariant).
const SECRET_PITCH_SCALE: float = 1.3348398541700344  # 2.0 ** (5.0/12.0) précomputé


## Tracker slots avec pitch fixé par caller (story-008 secret SECRET_PITCH_SCALE).
## key=int slot index → value=float pitch_scale demandé. `_tick_slow_mo_pitch_shift`
## skip ces slots (préserve pitch même hors allowlist). Cleanup au recyclage
## round-robin (play_3d_at + _round_robin_3d_stop_if_saturated).
var _slot_fixed_pitch: Dictionary[int, float] = {}


## Connecte le signal `secret_collected(secret_node, tier)` du Secret System
## avec `CONNECT_DEFERRED` (R-AUD-5). No-op gracieux si signal absent (boot
## ordering : Secret System pas encore prêt, ou tests sans dépendance).
## Pattern symétrique connect_movement_signals / connect_combat_signals.
func connect_secret_signals(secret_system: Node) -> void:
	if secret_system == null:
		push_warning("AudioSystem.connect_secret_signals: secret_system null, skip")
		return
	if not secret_system.has_signal(&"secret_collected"):
		push_warning("AudioSystem.connect_secret_signals: signal 'secret_collected' absent")
		return
	if not secret_system.secret_collected.is_connected(_on_secret_collected):
		secret_system.secret_collected.connect(_on_secret_collected, CONNECT_DEFERRED)


## Handler secret collect — pitch +5 semitones bus SFX, pas de ducking, pas de
## blood ambiance, pas d'incrément `_kill_count_this_swing`. R-AUD-7 capture
## position au tick de réception (DEFERRED N+1) — défense queue_free post-collect.
## Phase D.1 fallback `play_2d` head-locked si position non-finite OU node libéré.
func _on_secret_collected(secret_node: Node, _tier: int) -> void:
	# R-AUD-7 — défense queue_free post-collect : node peut être invalide DEFERRED N+1.
	if not is_instance_valid(secret_node):
		push_warning("AudioSystem: secret_node invalide (queue_free pré-DEFERRED), fallback play_2d head-locked")
		play_2d(clac_stream, &"SFX", SECRET_PITCH_SCALE)
		return
	# Capture position au tick reception (pas une ref live au node).
	var pos: Vector3 = secret_node.global_position
	# Phase D.1 — is_finite precheck → fallback head-locked si NaN/inf.
	if not pos.is_finite():
		push_warning("AudioSystem: secret_node.global_position invalide (NaN/inf), fallback play_2d head-locked")
		play_2d(clac_stream, &"SFX", SECRET_PITCH_SCALE)
		return
	# Bus SFX exclusif — sidechain MUSIC ← COMBAT_KILL n'arme pas.
	# Pitch invariant slow-mo (SFX hors PITCH_ALLOWLIST + tracker fixed_pitch).
	var slot_idx: int = play_3d_at(clac_stream, pos, &"SFX", SECRET_PITCH_SCALE)
	if slot_idx >= 0:
		# AC-AUD-19 — register dans tracker pour que `_tick_slow_mo_pitch_shift`
		# préserve le pitch même hors allowlist (sinon SFX serait reseté à 1.0).
		_slot_fixed_pitch[slot_idx] = SECRET_PITCH_SCALE
	# Pas de duck_bus, pas d'incrément _kill_count_this_swing, pas de blood — Rule 17.


## Cleanup tracker fixed-pitch quand un slot est recyclé/force-stopped.
## Idempotent : no-op si slot pas dans tracker. Appelé depuis `play_3d_at`
## (round-robin recycle) et `_round_robin_3d_stop_if_saturated` (force-stop).
func _cleanup_fixed_pitch_slot(slot_idx: int) -> void:
	if not _slot_fixed_pitch.has(slot_idx):
		return
	_slot_fixed_pitch.erase(slot_idx)
