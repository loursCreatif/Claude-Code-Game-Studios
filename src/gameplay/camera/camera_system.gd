class_name CameraSystem
extends Node3D

## Camera system orchestrator attached to CameraArm (Node3D child of CharacterBody3D).
##
## ADR-0002 ownership model (one axis per node, no cross-writes) :
##   - Yaw   : Player.rotation.y       (written by movement system)
##   - Pitch : CameraArm.rotation.x    (written by this system, story 002+)
##   - Tilt  : CameraEffects.rotation.z (written by this system, story 005+)
##   - FOV   : Camera3D.fov            (written by this system, story 005+)
##   - Shake : Camera3D.rotation       (assignation, story 007+)
##
## TR-cam-001 : ownership séparé par étage scene tree.
## TR-cam-003 : logique caméra en _process (frame rate affichage) — pas de _physics_process.
##
## Story 001 : scene skeleton only. Motion logic arrives in story 002+.
## Story 002 : yaw + pitch raw apply via InputManager.mouse_motion signal.
## Story 005 : tilt wall-run — derive wall_side from player.wall_normal + lerp camera_effects.rotation.z.
## Story 006 : FOV dash pulse — signal-driven flag + lerp camera3d.fov.
## Story 007 : shake additif + wall_jump kick — assignation camera3d.rotation, exp decay, limit_length cap.
## Story 011 : _exit_tree cleanup (symétrie _ready ↔ _exit_tree, Rule 16) + NaN safeguard (GDD Edge Case).
## Story 012 : perf instrumentation ring buffer — p50/p99 _process cost + E2E mouse→rendered latency.
##             ADR-0002 VC-6 : _process cost ≤ 0.2 ms p99 / 1000 frames.
##             GDD AC-CAM-80/81 : p50 ≤ 0.2 ms, p99 ≤ 0.4 ms (240 samples) ;
##             latency mouse_motion → rotation applied ≤ 16 ms p99 (1000 samples).


# ---------------------------------------------------------------------------
# Constants — perf instrumentation ring buffer (story 012, GDD AC-CAM-80/81)
# ADR-0004 D-8 pattern : PackedFloat32Array pré-alloué, zero-alloc runtime.
# ---------------------------------------------------------------------------

## Capacité ring buffer coût _process — ~4 s à 60 fps (GDD AC-CAM-80 : 240 samples).
const PROCESS_COST_CAPACITY: int = 240

## Capacité ring buffer latence mouse_motion — 1000 événements (GDD AC-CAM-81).
const LATENCY_CAPACITY: int = 1000


# ---------------------------------------------------------------------------
# Constants — yaw/pitch bounds (story 002, derived from ADR-0002 + GDD)
# ---------------------------------------------------------------------------

## Limite pitch absolue ≈ 87.1° (PI/2 − 0.05 rad). Évite gimbal lock visuel
## quand le joueur regarde plein haut/bas. Clamp dur, sans accumulation interne
## (AC-CAM-03 : 10 motions « vers le haut » → pitch reste à PITCH_LIMIT).
const PITCH_LIMIT: float = PI / 2.0 - 0.05

## Cap magnitude appliquée par event mouse motion. Protège contre flick
## dégénéré (10 000 px/event) × sensitivity max (0.012) → 120 rad sinon.
## AC-CAM-04 : cap AVANT commit, le delta excédentaire n'est PAS accumulé.
const MAX_ROT_PER_FRAME: float = PI


# ---------------------------------------------------------------------------
# Constants — FOV dash pulse (story 006, TR-cam-001, ADR-0002 + ADR-0005)
# ---------------------------------------------------------------------------

## FOV de base (degrés). Prototype validé 2026-04-21 (Camera GDD).
## Reduce_motion slider et réglage utilisateur hors scope (stories 010, MVP open question).
const BASE_FOV: float = 90.0

## Bonus FOV ajouté lors d'un dash (degrés). Peak cible = BASE_FOV + DASH_FOV_KICK = 100°.
## Reduce_motion multiplier (0.5) PAS dans cette story — ajouté par story 010 (peak → 95°).
const DASH_FOV_KICK: float = 10.0

## Vitesse de lerp FOV (unit/s). Snap-in ~150 ms — fov ≥ 98.5° en 9 frames (AC-CAM-20).
const DASH_FOV_LERP_SPEED: float = 14.0


# ---------------------------------------------------------------------------
# Constants — wall-run tilt (story 005, TR-cam-004, ADR-0002 + ADR-0005)
# ---------------------------------------------------------------------------

## Angle de tilt cible (rad) lors d'un wall-run. Source de vérité Camera.
## Prototype validé 2026-04-21. ~20° en degrés.
## Reduce_motion multiplier PAS encore appliqué ici (story 010).
const WALL_RUN_TILT_ANGLE: float = 0.35

## Vitesse de lerp (unit/s) pour le tilt wall-run.
## t_95 ≈ 250 ms à 60 fps (3 / TILT_LERP_SPEED ≈ 0.25 s).
const TILT_LERP_SPEED: float = 12.0


# ---------------------------------------------------------------------------
# Constants — shake additif + wall_jump kick (story 007, TR-cam-001, ADR-0002 Risk 3 + ADR-0005)
# ---------------------------------------------------------------------------

## Decay rate (1/s) — exp(-SHAKE_DECAY * delta) → retour < 5% en ~250 ms.
## Stable GDScript, pas de post-cutoff API.
const SHAKE_DECAY: float = 12.0

## Magnitude du kick wall-jump (rad ≈ 3°). Direction dérivée par _sign_with_fallback
## sur dot(wall_normal, -camera_arm.basis.x) — GDD Rule 7.
## Reduce_motion multiplier (shake_mult = 0.0) PAS dans cette story — ajouté par story 010.
const WALL_JUMP_KICK_MAGNITUDE: float = 0.05

## Cap absolu sur la magnitude cumulée du shake (rad ≈ 11.5°).
## Empêche cumul nauséeux quand plusieurs sources appellent add_shake() même tick.
const MAX_SHAKE_MAGNITUDE: float = 0.2


# ---------------------------------------------------------------------------
# Constants — respawn lifecycle (story 008, TR-cam-001, ADR-0002 + ADR-0005 D-2/D-6/D-8)
# ---------------------------------------------------------------------------

## Mini-state Camera-side pour gater mouse_motion + idempotence handler died.
## ADR-0005 D-8 : transition 1× par changement, guard `if _state == RESPAWNING: return`.
## ADR-0001 : Movement reste autorité unique sur le state RESPAWN_DELAY=50ms côté gameplay
## — _state ici est COSMETIC ONLY (gate effets visuels + mouse, pas logique gameplay).
enum State { ACTIVE, RESPAWNING }

## Couleur de l'overlay rouge sombre activé pendant Respawning (AC-CAM-40).
## Alpha 0.6 — fade trajectoire 0.6 → 0 + flash blanc 50 ms livrés par story 009.
const RESPAWN_OVERLAY_COLOR: Color = Color(0.4, 0.0, 0.0, 0.6)

## CanvasLayer.layer pour overlay respawn — au-dessus du HUD (50) et du Pause (80).
## Convention M Camera : Respawn overlay = 100 (top, safe au-dessus de tout UI).
const RESPAWN_OVERLAY_LAYER: int = 100


# ---------------------------------------------------------------------------
# Constants — respawn fade + flash visual (story 009, GDD Rule 9 + Visual/Audio)
# ---------------------------------------------------------------------------

## Durée du fade rouge → transparent (s). GDD Visual/Audio Requirements : 100 ms.
## Phase 2 de la séquence respawn (post-flash blanc). Cible Pillar 3 ≤ 400 ms total.
const RESPAWN_OVERLAY_FADE_DURATION: float = 0.100

## Durée du flash blanc intercalé (s). GDD Visual/Audio Requirements : 50 ms.
## Phase 1 de la séquence — snap-in immédiat puis hold pendant cette durée.
const RESPAWN_FLASH_DURATION: float = 0.050

## Couleur du flash blanc Mirror's Edge reference (alpha 0.9, presque opaque).
## GDD Rule 9 + Visual/Audio Requirements.
const RESPAWN_FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)

## Couleur de fin de fade (rouge transparent). Alpha 0 domine, couleur rouge
## maintenue pour cohérence interpolation. Le callback final hide l'overlay.
const RESPAWN_FADE_END_COLOR: Color = Color(0.4, 0.0, 0.0, 0.0)


# ---------------------------------------------------------------------------
# Constants — reduce_motion gate (story 010, GDD Rule 14 accessibility floor)
# ---------------------------------------------------------------------------

## Multiplier appliqué à `WALL_RUN_TILT_ANGLE` quand `_reduce_motion == true`.
## GDD Rule 14 (creative-director r1 2026-04-21) : tilt × 0.25 → 0.0875 rad au lieu de 0.35.
## Atténue le wall-run roll pour le public motion-sensitive (15-25%).
const REDUCE_MOTION_TILT_MULT: float = 0.25

## Multiplier appliqué à `DASH_FOV_KICK` quand `_reduce_motion == true`.
## GDD Rule 14 : fov_kick × 0.5 → peak 95° au lieu de 100°.
const REDUCE_MOTION_FOV_KICK_MULT: float = 0.5

# Shake reduce_motion : pas de constante — gate par early-return dans `add_shake`,
# équivalent à multiplier × 0.0. Plus économique qu'inject + clamp à 0.


# ---------------------------------------------------------------------------
# Node references — resolved via unique-name accessors (%NodeName).
# CameraArm IS self (script is attached to CameraArm node).
# ---------------------------------------------------------------------------

@onready var _camera_arm: Node3D = self
@onready var _camera_effects: Node3D = %CameraEffects
@onready var _camera3d: Camera3D = %Camera3D

## Reference cached vers Player (CharacterBody3D parent direct du CameraArm).
## Cache au _ready pour éviter get_parent() lookup chaque mouse_motion.
@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D


# ---------------------------------------------------------------------------
# Module state — signal-driven flags (story 006+)
# ---------------------------------------------------------------------------

## Cache signal-driven de l'état dash. Mis à jour exclusivement par les
## handlers _on_dash_started / _on_dash_ended. Source de vérité Camera-side.
## Manifest 2026-04-23 ligne 161 : interdit de lire player.is_dashing en _process.
## Ne jamais écrire ce flag depuis _update_fov_dash — lecture seule dans _process.
var _is_dashing: bool = false

## TD-004 — Cache signal-driven de l'état wall-run. Mis à jour exclusivement par
## les handlers _on_wall_run_entered / _on_wall_run_exited. Source de vérité Camera-side.
## ADR-0002 Amendment A-1 (2026-04-23) : interdit de lire player.wall_normal chaque frame
## dans _process — substitué par cache signal-driven (parity pattern _is_dashing).
## Ne jamais écrire ces vars depuis _update_tilt_wall_run — lecture seule dans _process.
##
## _wall_side_cached : -1 (mur gauche), 0 (pas en wall-run), +1 (mur droit).
## Dérivé une fois à _on_wall_run_entered depuis sign((-wall_normal).dot(player.basis.x)).
var _is_wall_running: bool = false
var _wall_side_cached: int = 0

## Offset shake (rad, axes Euler YXZ Camera3D) — appliqué via assignation
## camera3d.rotation = _shake_offset chaque frame (pas +=, ADR-0002 Risk 3).
## L'assignation garantit le reset implicite quand _shake_offset → 0 et évite
## le drift visuel par cumul de transformations.
## Mis à jour par add_shake / add_shake_roll (entrée), exp decay + limit_length (sortie _update_shake).
var _shake_offset: Vector3 = Vector3.ZERO


## Mini-state Camera (story 008) — gère idempotence handler died (AC-CAM-43)
## + gate mouse_motion pendant Respawning (AC-CAM-40 : rotation figée).
## Mute uniquement par _on_died (ACTIVE → RESPAWNING) et _on_respawned (RESPAWNING → ACTIVE).
var _state: State = State.ACTIVE


## CanvasLayer hôte de l'overlay rouge respawn — pré-créé au _ready() (one-shot
## alloc hors hot-path, ADR-0005 D-5 + Manifest 2026-04-23 Forbidden : zero-alloc handler).
var _canvas_layer: CanvasLayer = null


## Overlay rouge sombre — visible pendant Respawning (AC-CAM-40), hidden pendant ACTIVE.
## Story 009 anime fade trajectoire 0.6 → 0 + flash blanc 50 ms via _respawn_tween.
var _overlay: ColorRect = null


## Tween animant la séquence respawn (story 009) : flash blanc 50 ms → fade 100 ms → hide.
## Re-créé à chaque _on_respawned (kill du précédent si encore valide pour edge case
## died/respawned/died/respawned consécutifs en < 200 ms).
var _respawn_tween: Tween = null


## Cache multipliers reduce_motion (GDD Rule 14, story 010 + Polish P4 wiring ADR-0015).
## Lus depuis `AccessibilityService.get_camera_*_mult()` au `_ready()` + reconnect
## `settings_changed` pour live update mid-game (pull-pattern ADR-0015 D-3).
##
## Defaults 1.0/1.0/1.0 → comportement Camera identique au MVP non-accessibility (D-5).
## Service-level clamping garanti (D-7) — Camera n'a pas à re-clamper.
##
## Tests : injectent directement les 3 floats pour valider AC-CAM-70/71/72 sans
## passer par AccessibilityService (pattern parity story-022 Combat).
var _tilt_mult: float = 1.0
var _fov_kick_mult: float = 1.0
var _shake_mult: float = 1.0


# ---------------------------------------------------------------------------
# Module state — perf instrumentation ring buffers (story 012, GDD AC-CAM-80/81)
# Pré-alloués au _ready() via .resize() — zero-alloc runtime garanti après init.
# Écritures uniquement dans hot paths (_process + _on_mouse_motion).
# ---------------------------------------------------------------------------

## Ring buffer coût _process (ms). Pré-alloué PROCESS_COST_CAPACITY floats.
var _process_cost_samples: PackedFloat32Array = PackedFloat32Array()

## Indice d'écriture courant dans _process_cost_samples (wrap modulo CAPACITY).
var _process_cost_write_idx: int = 0

## Ring buffer latence mouse_motion → rotation appliquée (ms).
## t_event capturé au début de _on_mouse_motion (meilleure précision sans modification InputManager).
var _latency_samples: PackedFloat32Array = PackedFloat32Array()

## Indice d'écriture courant dans _latency_samples (wrap modulo CAPACITY).
var _latency_write_idx: int = 0


# ---------------------------------------------------------------------------
# Module state — settings persistence (story 013, ADR-0014)
# ---------------------------------------------------------------------------

## Préférences utilisateur Camera persistées (TR-cam-006). Chargées au `_ready()`
## via `SettingsResource.load_or_default("camera", …)` (ADR-0014 D-5).
## `null` jusqu'au load, ou si `suppress_settings_load == true` (tests qui n'ont
## pas besoin de toucher `user://settings/`).
##
## Sauvegarde via `save_settings()` (trigger explicite — Settings menu apply,
## flush-on-quit, debug command). ADR-0014 D-6 interdit l'auto-save en hot path.
var settings: CameraSettings = null

## Flag de désactivation du chargement settings au boot (parité InputManager.suppress_settings_load
## et `suppress_debug_overlay`). Tests qui veulent isoler le filesystem settent
## `true` AVANT `add_child` (stories 002–012 n'en ont pas besoin — defaults silent
## si fichier absent, mais le flag évite la pollution de `user://settings/`).
var suppress_settings_load: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Story 012 — pré-allocation ring buffers perf : DOIT précéder l'early-return
	# pour que _process() n'écrive jamais hors-bounds, même quand le test harness
	# injecte _camera_effects post-_ready (TD-005 — pattern parity stories 005-008).
	# .resize() sur PackedArray vide alloue CAPACITY éléments initialisés à 0,
	# idempotent si rappelé (no-op si déjà sized). ADR-0004 D-8 zero-alloc runtime.
	if _process_cost_samples.size() == 0:
		_process_cost_samples.resize(PROCESS_COST_CAPACITY)
	if _latency_samples.size() == 0:
		_latency_samples.resize(LATENCY_CAPACITY)

	# Test harness may inject these; only assert if not injected AND not resolved via %
	if _camera_effects == null:
		assert(PITCH_LIMIT < PI / 2.0, "CameraSystem: PITCH_LIMIT must stay strictly under PI/2 to avoid gimbal lock")
		assert(MAX_ROT_PER_FRAME > 0.0, "CameraSystem: MAX_ROT_PER_FRAME must be positive")
		return  # Test harness skips _ready() completion if vars not injected

	assert(_camera_arm != null, "CameraSystem: _camera_arm null — script must be attached to CameraArm")
	assert(_camera_effects != null, "CameraSystem: _camera_effects null — ensure CameraEffects has unique_name_in_owner=true")
	assert(_camera3d != null, "CameraSystem: _camera3d null — ensure Camera3D has unique_name_in_owner=true")
	assert(_player != null, "CameraSystem: _player null — CameraArm must be direct child of CharacterBody3D")
	assert(PITCH_LIMIT < PI / 2.0, "CameraSystem: PITCH_LIMIT must stay strictly under PI/2 to avoid gimbal lock")
	assert(MAX_ROT_PER_FRAME > 0.0, "CameraSystem: MAX_ROT_PER_FRAME must be positive")

	# Story 013 (ADR-0014) — chargement settings AVANT init FOV pour appliquer
	# `fov_user_offset` au snapshot initial. Defaults silent si first launch (D-4).
	# `suppress_settings_load` permet aux tests de bypasser le filesystem.
	if not suppress_settings_load:
		_load_settings()

	# Initialisation explicite FOV avant toute lerp (story 006, AC-CAM-20 initial state).
	# Offset utilisateur (story 013) ajouté au baseline pour cohérence avec _update_fov_dash.
	var fov_offset: float = settings.fov_user_offset if settings != null else 0.0
	_camera3d.fov = BASE_FOV + fov_offset

	# Story 002 : connexion synchrone (CONNECT_0 default) — handler léger,
	# zéro alloc, mutation scalaire uniquement (ADR-0005 D-5 consumer léger).
	# Story 011 ajoutera le _exit_tree disconnect symétrique.
	InputManager.mouse_motion.connect(_on_mouse_motion)

	# Story 006 : connexions canoniques Camera ↔ Movement — Manifest 2026-04-23
	# ligne 149 (6 handlers signal-driven Movement). Mode SYNC (flags=0, pas
	# CONNECT_DEFERRED) — ADR-0005 D-5 consumer léger (toggle bool, zero-alloc).
	# VC-8 ADR-0002 Amendment A-1 : assert connection.flags == 0.
	# Story 011 ajoutera les disconnects symétriques en _exit_tree.
	_player.dash_started.connect(_on_dash_started)
	_player.dash_ended.connect(_on_dash_ended)

	# Story 007 : connexion wall_jumped — payload (wall_normal, launch_velocity).
	# Mode SYNC (D-5 consumer léger : 1 dot product + 1 sign + 1 add scalaire +
	# 1 limit_length < 0.05 ms, zéro alloc, pas d'instanciation Node).
	# Story 011 ajoutera le _exit_tree disconnect symétrique.
	_player.wall_jumped.connect(_on_wall_jumped)

	# TD-004 — connexions wall_run_entered/exited (signal-driven cache).
	# Mode SYNC (D-5 consumer léger : 1 dot + 1 sign + 1 assign scalaire, zéro alloc).
	# Substitue le polling _player.wall_normal dans _update_tilt_wall_run (ADR-0002 A-1).
	_player.wall_run_entered.connect(_on_wall_run_entered)
	_player.wall_run_exited.connect(_on_wall_run_exited)

	# Story 008 : pré-création overlay respawn (one-shot alloc au boot, hors hot-path).
	# DOIT précéder les connexions died/respawned : si une émission synchrone arrivait
	# avant _setup_overlay, _on_died accéderait à _overlay null. En pratique impossible
	# au _ready() (signaux émis depuis _physics_process Movement, donc post-_ready),
	# mais l'ordre défensif vaut zéro coût.
	_setup_overlay()

	# Story 008 : connexions died/respawned — handlers légers après pré-création
	# overlay. Mode SYNC (D-5 consumer léger : toggle bool + visible + 4 scalar resets).
	# Story 011 ajoutera les disconnects symétriques en _exit_tree.
	_player.died.connect(_on_died)
	_player.respawned.connect(_on_respawned)

	# Polish P4 (ADR-0015 D-3) : Camera consumer AccessibilityService — pull-pattern
	# au _ready + reconnect signal_changed pour live update mid-game (GDD Rule 14).
	if not AccessibilityService.settings_changed.is_connected(_on_accessibility_changed):
		AccessibilityService.settings_changed.connect(_on_accessibility_changed)
	_apply_accessibility()

	# Story 012 : pré-allocation ring buffers perf — déjà fait en haut de _ready()
	# (avant l'early-return du test harness). Idempotent — no-op si déjà sized.
	# ADR-0004 D-8 pattern : capacité fixe réservée au boot, jamais realloc ensuite.


# ---------------------------------------------------------------------------
# Lifecycle — cleanup (story 011, GDD Rule 16 symétrie _ready ↔ _exit_tree)
# ---------------------------------------------------------------------------

## Disconnect explicite de tous les signaux connectés dans _ready().
## Garantit l'absence de "Signal target was freed" lors d'un scene reload
## (Player free + reconstruit). AC-CAM-63.
##
## Ordre inversé de _ready() pour symétrie visuelle et lisibilité.
## `is_instance_valid` + `is_connected` guards : idempotence si Camera free
## avant Player (ordre d'arbre imprévisible dans certains edge cases).
## Zero overhead sur le chemin normal — disconnect = metadata op (Manifest Guardrail).
##
## InputManager : autoload, toujours valide → pas besoin de is_instance_valid.
## _player/_camera_effects/_camera3d : enfants/parent qui peuvent déjà être freed
## si l'arbre se démonte dans un ordre non-standard.
func _exit_tree() -> void:
	# Disconnect InputManager.mouse_motion (story 002).
	if InputManager.mouse_motion.is_connected(_on_mouse_motion):
		InputManager.mouse_motion.disconnect(_on_mouse_motion)

	# Disconnect AccessibilityService.settings_changed (Polish P4 ADR-0015).
	if AccessibilityService.settings_changed.is_connected(_on_accessibility_changed):
		AccessibilityService.settings_changed.disconnect(_on_accessibility_changed)

	# Disconnect signaux player (stories 006/007/008) via référence locale au
	# parent plutôt que _player : évite accès à @onready var freed potentiellement.
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


# ---------------------------------------------------------------------------
# Lifecycle — process (cosmetic, story 005+)
# ---------------------------------------------------------------------------

## Frame update — cosmetic-only camera effects (ADR-0001 Rule 12, Control Manifest
## Presentation layer). Tilt wall-run, FOV dash et shake exécutés ici, pas dans _physics_process.
## Ordre : safeguard → tilt → fov → shake. Indépendants (noeuds distincts), ordre cosmétique seulement.
## Story 011 : _safeguard_rotation() exécutée en premier — protège le lerp tilt contre NaN.
## Story 012 : instrumentation ring buffer — 2× Time.get_ticks_usec() + 1 subtract + 1 write.
##             Overhead ≤ 0.01 ms/frame (GDD AC-CAM-80 guardrail instrumentation). Zero-alloc.
func _process(delta: float) -> void:
	# TD-005 defensive guard : _camera_effects/_camera3d peuvent être null pendant
	# le tear-down test (queue_free pending) ou le boot intermédiaire avant injection
	# manuelle dans before_test(). Symétrique de l'early-return _ready() ligne 252.
	# En production runtime, ces refs sont garanties non-null par le scene owner.
	if _camera_effects == null or _camera3d == null:
		return
	var t_start: int = Time.get_ticks_usec()
	_safeguard_rotation()       # Story 011 — doit précéder _update_tilt_wall_run
	_update_tilt_wall_run(delta)
	_update_fov_dash(delta)
	_update_shake(delta)
	# Story 012 — écriture coût _process en µs → ms, ring buffer write index wrap.
	var elapsed_ms: float = float(Time.get_ticks_usec() - t_start) / 1000.0
	_process_cost_samples[_process_cost_write_idx] = elapsed_ms
	_process_cost_write_idx = (_process_cost_write_idx + 1) % PROCESS_COST_CAPACITY


# ---------------------------------------------------------------------------
# Private — NaN safeguard (story 011, GDD Edge Case « camera_effects.rotation.z NaN »)
# ---------------------------------------------------------------------------

## Détecte et corrige un NaN/Inf sur camera_effects.rotation.z avant le lerp tilt.
## Appelé en début de _process chaque frame (coût ≤ 0.005 ms : 1 appel is_finite).
##
## Seul .z est gardé : c'est l'axe tilt écrit par _update_tilt_wall_run.
## .x et .y appartiennent à d'autres systèmes (pitch sur CameraArm, shake sur Camera3D) ;
## leurs NaN relèveraient d'autres guards si nécessaire empiriquement.
##
## Log level push_warning (pas push_error) — debug run continue.
## Préfixe "[camera]" pour filtrage prod logs. AC-CAM-NAN-1.
func _safeguard_rotation() -> void:
	if not is_finite(_camera_effects.rotation.z):
		_camera_effects.rotation.z = 0.0
		push_warning("[camera] camera_effects.rotation.z NaN/Inf detected, reset to 0")


# ---------------------------------------------------------------------------
# Private — tilt wall-run (story 005, TR-cam-004, ADR-0002 + ADR-0005)
# ---------------------------------------------------------------------------

## TD-004 — Lecture cache signal-driven _wall_side_cached (mis à jour par
## _on_wall_run_entered/exited). ADR-0002 Amendment A-1 (2026-04-23) interdit
## le polling player.wall_normal chaque frame — pattern parity _is_dashing.
##
## En production : Movement state machine garantit AIRBORNE intermédiaire entre
## wall-runs (cf. _try_start_wall_run guard `_state != AIRBORNE`), donc chaque
## changement de mur génère wall_run_exited puis wall_run_entered = cache toujours
## à jour pour l'intent gameplay. Tests passent par .emit() direct sur les signaux.
##
## _wall_side_cached == 0 → target == 0 (pas en wall-run, lerp retour à 0).
func _update_tilt_wall_run(delta: float) -> void:
	# TD-004 : cache signal-driven (pas de polling _player.wall_normal).
	var target_roll: float = WALL_RUN_TILT_ANGLE * float(_wall_side_cached)

	# Story 010 reduce_motion gate (GDD Rule 14, AC-CAM-70) : applique multiplier
	# AU TARGET avant lerp — pas après commit. Cache `_tilt_mult` lu depuis
	# AccessibilityService au _ready + signal_changed (Polish P4 ADR-0015 D-3).
	# Toggle mid-game → service emit settings_changed → cache rechargé → lerp
	# adapte vers nouveau target au frame suivant (smooth transition).
	target_roll *= _tilt_mult

	# Lerp cosmétique, clamp du facteur pour protéger contre delta élevé (frame spike).
	_camera_effects.rotation.z = lerp(
		_camera_effects.rotation.z,
		target_roll,
		min(TILT_LERP_SPEED * delta, 1.0),
	)


# ---------------------------------------------------------------------------
# Private — FOV dash pulse (story 006, TR-cam-001, ADR-0002 + ADR-0005)
# ---------------------------------------------------------------------------

## Interpole camera3d.fov vers BASE_FOV + DASH_FOV_KICK quand _is_dashing,
## vers BASE_FOV sinon. Lu depuis _process (cosmétique uniquement).
##
## Pattern : flag _is_dashing mis à jour par handlers signaux (_on_dash_started /
## _on_dash_ended) — jamais par polling player.is_dashing (Manifest 2026-04-23
## ligne 161, forbidden pattern camera_polls_movement_state_transitions).
##
## Double dash avant retour complet : dash_started re-fire, _is_dashing reste true,
## target reste 100°, lerp reprend depuis valeur courante (pas de saut — kick absolu).
##
## Story 010 reduce_motion gate (GDD Rule 14, AC-CAM-71) : multiplier appliqué
## à DASH_FOV_KICK avant calcul target_fov — peak passe de 100° à 95°.
## Respawn reset (_camera3d.fov = BASE_FOV, _is_dashing = false) : story 008.
func _update_fov_dash(delta: float) -> void:
	var dash_kick: float = DASH_FOV_KICK * _fov_kick_mult
	# Story 013 — `fov_user_offset` (settings) ajouté au baseline ; null-safe pour
	# les chemins de test qui suppressent le load (settings reste null).
	var fov_offset: float = settings.fov_user_offset if settings != null else 0.0
	var target_fov: float = BASE_FOV + fov_offset + (dash_kick if _is_dashing else 0.0)
	_camera3d.fov = lerp(
		_camera3d.fov,
		target_fov,
		min(DASH_FOV_LERP_SPEED * delta, 1.0),
	)


# ---------------------------------------------------------------------------
# Signal handlers — Movement dash (story 006, ADR-0005 D-7 / D-8)
# ---------------------------------------------------------------------------

## Sets _is_dashing=true. ADR-0005 D-7 (no Movement mutation) + D-8 (idempotent).
## SYNC connection (D-5 : toggle bool, zero-alloc).
func _on_dash_started(_dash_dir: Vector3, _dash_speed: float) -> void:
	_is_dashing = true


## Sets _is_dashing=false. ADR-0005 D-7 (no Movement mutation) + D-8 (idempotent).
func _on_dash_ended() -> void:
	_is_dashing = false


# ---------------------------------------------------------------------------
# Signal handlers — Movement wall-run (TD-004, ADR-0002 A-1, ADR-0005 D-7/D-8)
# ---------------------------------------------------------------------------

## TD-004 — Cache wall-run state à l'entrée. Dérive _wall_side_cached depuis le
## payload wall_normal et l'axe X local du Player (sign((-wall_normal).dot(basis.x))).
## ADR-0002 Amendment A-1 : substitue le polling player.wall_normal chaque frame.
## SYNC connection (D-5 : 1 dot + 1 sign + 1 assign scalar, zero-alloc).
##
## sign(0) == 0 → cache reste 0 si wall_normal == Vector3.ZERO (defensive).
## En production wall_normal est garantit non-zéro à l'entrée WALL_RUNNING (Movement
## ne pousse l'état que si _wall_normal valide).
func _on_wall_run_entered(wall_normal: Vector3) -> void:
	_is_wall_running = true
	_wall_side_cached = int(sign((-wall_normal).dot(_player.global_transform.basis.x)))


## TD-004 — Reset cache wall-run à la sortie. _wall_side_cached = 0 → lerp retour à 0.
## SYNC connection (D-5 : 2 scalar resets, zero-alloc). Idempotent (D-8).
func _on_wall_run_exited() -> void:
	_is_wall_running = false
	_wall_side_cached = 0


# ---------------------------------------------------------------------------
# Signal handlers — AccessibilityService (Polish P4, ADR-0015 D-3 pull-pattern)
# ---------------------------------------------------------------------------

## Recharge les 3 multipliers depuis AccessibilityService. Service-level clamping
## déjà appliqué (D-7) — Camera ne re-clampe pas. Lecture one-shot zero-alloc.
func _apply_accessibility() -> void:
	_tilt_mult = AccessibilityService.get_camera_tilt_mult()
	_fov_kick_mult = AccessibilityService.get_camera_fov_kick_mult()
	_shake_mult = AccessibilityService.get_camera_shake_mult()


## Handler signal `settings_changed` — déclenche reload cache (live update mid-game).
func _on_accessibility_changed() -> void:
	_apply_accessibility()


# ---------------------------------------------------------------------------
# Public API — shake (story 007, TR-cam-001, ADR-0002 Risk 3)
# Préparée pour consumers VFX hit katana / boss impact (post-MVP, hors scope MVP).
# MVP : seul _on_wall_jumped l'appelle.
# ---------------------------------------------------------------------------

## Ajoute un offset additif au shake courant. Borne via limit_length au cap MAX_SHAKE_MAGNITUDE.
## Zero-alloc : Vector3 value type, += et limit_length() retournent stack.
## AC-CAM-32 : 3× add_shake_roll(0.05) même tick → length() ≤ 0.2 (cap).
##
## Story 010 reduce_motion gate (GDD Rule 14, AC-CAM-72) : early-return si
## `_shake_mult <= 0.0` — équivaut à shake_mult = 0.0 mais plus économique
## (évite inject + clamp à 0 répété). Le shake déjà injecté pré-toggle continue
## son decay naturel via `_update_shake` (gate sur injection seule, pas decay).
## Polish P4 (ADR-0015 D-3) : `_shake_mult` lu depuis AccessibilityService.
func add_shake(offset_radians: Vector3) -> void:
	if _shake_mult <= 0.0:
		return
	_shake_offset += offset_radians * _shake_mult
	_shake_offset = _shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)


## Helper raccourci — applique magnitude sur l'axe Z (roll caméra) uniquement.
func add_shake_roll(magnitude: float) -> void:
	add_shake(Vector3(0.0, 0.0, magnitude))


# ---------------------------------------------------------------------------
# Private — shake update + sign helper (story 007)
# ---------------------------------------------------------------------------

## Alternative à sign() qui retourne 0 pour input 0. GDD Rule 7 :
## wall_normal ⊥ -basis.x (cas dégénéré exact, ex : mur en avant) → fallback +1
## évite kick nul silencieux (kick toujours visible côté joueur).
func _sign_with_fallback(x: float) -> float:
	if x > 0.0:
		return 1.0
	elif x < 0.0:
		return -1.0
	else:
		return 1.0


## Décroissance exponentielle + cap + ASSIGNATION sur camera3d.rotation.
## ADR-0002 Risk 3 : assignation (`=`, pas `+=`) garantit reset implicite quand
## _shake_offset → 0 — évite drift visuel par cumul de transformations.
## Reduce_motion (story 010) gatera shake_mult = 0.0 avant add_shake_roll côté
## handler, désactivant l'entrée — pas besoin de gate ici. Respawn reset (story 008)
## remettra _shake_offset = Vector3.ZERO + _camera3d.rotation = Vector3.ZERO.
## AC-CAM-30 : retour < 5% magnitude initiale en ~250 ms (15 frames @ 60 fps).
func _update_shake(delta: float) -> void:
	_shake_offset *= exp(-SHAKE_DECAY * delta)
	_shake_offset = _shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)
	_camera3d.rotation = _shake_offset


# ---------------------------------------------------------------------------
# Signal handlers — Movement wall_jumped (story 007, ADR-0005 D-2 / D-7 / D-8)
# ---------------------------------------------------------------------------

## Consomme wall_jumped(wall_normal, launch_velocity) — signature canonique ADR-0005 D-2.
## GDD Rule 7 : direction du kick dérivée par dot(wall_normal, -camera_arm.basis.x) :
##   - mur à gauche (normal=+x, caméra forward=-z) → dot=-1 → kick négatif (penche gauche)
##   - mur à droite (normal=-x)                    → dot=+1 → kick positif (penche droite)
##   - mur en avant (normal=+z, dot=0 exact)       → fallback +1 → kick positif
##
## launch_velocity ignorée volontairement (préfixe _) — magnitude shake constante MVP,
## non calibrée à la vélocité d'éjection. Tier 2+ pourrait moduler.
##
## SYNC connection (D-5 consumer léger), no Movement mutation (D-7), idempotent (D-8 :
## emits multiples additionnent via limit_length, pas de side-effect cumulatif non borné).
func _on_wall_jumped(wall_normal: Vector3, _launch_velocity: Vector3) -> void:
	var dir: float = _sign_with_fallback(wall_normal.dot(-_camera_arm.global_transform.basis.x))
	add_shake_roll(WALL_JUMP_KICK_MAGNITUDE * dir)


# ---------------------------------------------------------------------------
# Private — respawn overlay setup (story 008, GDD Rule 9 + Edge Case)
# ---------------------------------------------------------------------------

## Pré-création one-shot overlay rouge sombre — ColorRect fullscreen sur CanvasLayer
## dédié au-dessus du HUD (layer=100). Appelé depuis _ready() pour tenir la
## contrainte zero-alloc handler signal (Manifest 2026-04-23 Forbidden : pas
## d'instanciation Node en _on_died).
##
## Hiérarchie : CameraSystem (CameraArm) → CanvasLayer → ColorRect.
## Le CanvasLayer est attaché au CameraArm pour suivre le Player dans la scène
## (cleanup automatique via _exit_tree story 011 quand Player est libéré).
func _setup_overlay() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "RespawnOverlayLayer"
	_canvas_layer.layer = RESPAWN_OVERLAY_LAYER
	add_child(_canvas_layer)

	_overlay = ColorRect.new()
	_overlay.name = "RespawnOverlay"
	# Anchors fullscreen — preset 15 = full rect (anchors all 0/1 + offsets 0).
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.color = RESPAWN_OVERLAY_COLOR
	_overlay.visible = false
	_canvas_layer.add_child(_overlay)


# ---------------------------------------------------------------------------
# Signal handlers — Movement died/respawned (story 008, ADR-0005 D-2/D-6/D-8)
# ---------------------------------------------------------------------------

## Consomme died() — entre en Respawning, active overlay, gate mouse_motion.
## ADR-0005 D-8 idempotent (AC-CAM-43 miroir AC-MV-41) : early return si déjà
## RESPAWNING — un second emit dans le délai 50 ms est no-op.
## ADR-0005 D-7 (no Movement mutation) : ne touche que Camera-side state.
##
## Handler léger SYNC (CONNECT_0) : toggle bool + visible + color reset = ≤ 0.05 ms.
## Zero-alloc grâce à la pré-création overlay au _ready().
func _on_died() -> void:
	if _state == State.RESPAWNING:
		return  # Idempotence AC-CAM-43 — second died() dans le délai = no-op.
	# Story 009 : kill l'animation respawn en cours (cas died→respawned→died rapide
	# < 200 ms) — sinon le tween écraserait RESPAWN_OVERLAY_COLOR avec interpolation
	# fade en cours. Sans kill, second cycle visuel = conflit.
	if _respawn_tween != null and _respawn_tween.is_valid():
		_respawn_tween.kill()
	_state = State.RESPAWNING
	# Réinitialise color au default (cas dev où un setup futur aurait muté
	# _overlay.color entre deux cycles — défensif sans coût notable).
	_overlay.color = RESPAWN_OVERLAY_COLOR
	_overlay.visible = true


## Consomme respawned(position: Vector3) — reset effets visuels + sortie Respawning.
## Position ignorée (Camera ne déplace pas le Player — Movement le fait, ADR-0001 D-3).
##
## Reset checklist (AC-CAM-41) :
##   - camera_effects.rotation.z = 0  (tilt wall-run, story 005)
##   - camera3d.fov = BASE_FOV         (FOV dash pulse, story 006)
##   - camera3d.rotation = ZERO        (shake, story 007)
##   - _shake_offset = ZERO            (state shake interne, story 007)
##   - _is_dashing = false             (cas edge : died pendant dash actif)
##
## NE TOUCHE PAS (Ghostrunner approach, décision creative-director r1 2026-04-21) :
##   - camera_arm.rotation.x (pitch) — préservé pour éviter désorientation Pillar 3
##   - player.rotation.y (yaw)       — préservé idem ; ADR-0005 D-7 interdit aussi.
##
## Idempotent : second respawned sans died préalable s'exécute quand même
## (pas de guard) — reset des valeurs déjà default = no-op silencieux.
func _on_respawned(_position: Vector3) -> void:
	_camera_effects.rotation.z = 0.0
	# Story 013 — reset FOV au baseline + offset utilisateur (cohérence avec _update_fov_dash).
	var fov_offset: float = settings.fov_user_offset if settings != null else 0.0
	_camera3d.fov = BASE_FOV + fov_offset
	_camera3d.rotation = Vector3.ZERO
	_shake_offset = Vector3.ZERO
	_is_dashing = false
	# Story 009 : séquence animée flash blanc 50 ms → fade rouge 100 ms → hide.
	# L'overlay reste visible pendant l'animation ; le tween final hide via callback.
	_animate_respawn_overlay()
	_state = State.ACTIVE


# ---------------------------------------------------------------------------
# Private — respawn fade + flash animation (story 009, GDD Rule 9 + Visual/Audio)
# ---------------------------------------------------------------------------

## Anime la séquence respawn : snap couleur flash blanc → hold 50 ms → fade vers
## transparent 100 ms → hide overlay via callback final.
##
## Timing total : 50 ms flash + 100 ms fade = 150 ms overlay-side. Avec
## RESPAWN_DELAY=50 ms côté Movement, gross total ≤ 200 ms — bien sous Pillar 3
## cible 400 ms (AC-CAM-FLASH-2).
##
## Edge case died/respawned/died/respawned en < 200 ms : kill du tween précédent
## avant de créer le nouveau, évite conflit d'animation sur même `_overlay.color`.
##
## ADR-0002 ownership : overlay owned par Camera (CanvasLayer enfant Camera —
## VFX System ne duplique pas l'overlay, GDD Cross-References strict).
##
## Tween Godot 4 API stable (≤ 4.3, pas post-cutoff). `create_tween()` retourne
## un Tween auto-attaché à SceneTree, qui process en _process implicitement —
## cohérent avec Presentation layer cosmetic-only (ADR-0001 Rule 12).
func _animate_respawn_overlay() -> void:
	# Edge case : si un précédent tween est encore actif (respawn rapide consécutif),
	# kill avant de créer le nouveau pour éviter conflit sur _overlay.color.
	if _respawn_tween != null and _respawn_tween.is_valid():
		_respawn_tween.kill()

	_respawn_tween = create_tween()

	# Phase 1 — flash blanc snap-in (durée 0 = instantané) puis hold 50 ms.
	_respawn_tween.tween_property(_overlay, "color", RESPAWN_FLASH_COLOR, 0.0)
	_respawn_tween.tween_interval(RESPAWN_FLASH_DURATION)

	# Phase 2 — fade vers rouge transparent sur 100 ms.
	_respawn_tween.tween_property(
		_overlay,
		"color",
		RESPAWN_FADE_END_COLOR,
		RESPAWN_OVERLAY_FADE_DURATION,
	)

	# Callback final — hide l'overlay pour rester propre au-delà du tween.
	_respawn_tween.tween_callback(func() -> void: _overlay.visible = false)


# ---------------------------------------------------------------------------
# Public getters — respawn state (story 008, used by tests + story 009 fade)
# ---------------------------------------------------------------------------

## Returns the respawn overlay ColorRect. Used by integration tests (AC-CAM-40/41)
## and by story 009 to drive fade trajectory + flash white modulate.
func get_respawn_overlay() -> ColorRect:
	return _overlay


## Returns true if Camera is currently in Respawning state (gates mouse_motion).
func is_respawning() -> bool:
	return _state == State.RESPAWNING


# ---------------------------------------------------------------------------
# Input handlers (story 002+)
# ---------------------------------------------------------------------------

## Applique raw yaw + pitch reçus depuis InputManager.mouse_motion.
## Ownership ADR-0002 strict : yaw=Player.rotation.y, pitch=CameraArm.rotation.x.
## Pas de smoothing, pas de buffer (Pillar 1 FLOW raw feel).
## Gates enabled / mouse_captured : story-003 (early return, zero alloc, no log).
## Gates state Respawning : story-008 (rotation figée pendant respawn). reduce_motion : story 010.
## Story 012 : capture t_event en entrée de handler pour mesure latence E2E.
##   t_event = Time.get_ticks_usec() à réception du signal (post-InputManager dispatch).
##   t_applied = après commit des rotations yaw+pitch.
##   Overhead : 2× get_ticks_usec() + 1 subtract + 1 write — ≤ 0.005 ms.
##   Note : InputManager.mouse_motion ne transmet pas le timestamp hardware — on mesure
##   la latence depuis réception signal → rotation committed (sous-ensemble E2E réel).
##   Coordination avec Input epic (ADR-0004 D-8) prévue pour timestamp hardware quand
##   disponible (story-input-latency). Sans ce timestamp, p99 mesuré ici sera
##   conservateur (exclut OS driver latency).
func _on_mouse_motion(delta: Vector2) -> void:
	# Story 012 — timestamp d'entrée handler pour mesure latence.
	# Capture AVANT les gates (mesure le coût complet du handler incluant early-returns).
	var t_event: int = Time.get_ticks_usec()

	# Story-008 Gate #0 (AC-CAM-40) : pendant Respawning la rotation est figée.
	# Skip silencieux, pas de buffer du delta (cohérent avec gates story-003).
	if _state == State.RESPAWNING:
		return

	# Story-003 Gate #1 (GDD Rule 15) : mouse captured requis — état OS/window-level.
	# Couvre MouseFree standalone (ex : main menu pré-capture). Skip silencieux,
	# pas de warning, pas de buffer du delta (AC-CAM-61 : aucun pending_delta).
	if not InputManager.is_mouse_captured():
		return

	# Story-003 Gate #2 (ADR-0004 D-4) : InputManager enabled requis — état logique.
	# Couvre pause / respawn / cutscene via refcount (story-004 ajoutera les blockers).
	# Redondant avec is_mouse_captured pour certains états (Menu = both false) mais
	# orthogonal pour MouseFree standalone. Ordre indifférent pour correctness —
	# mouse_captured testé en premier pour lisibilité de diagnostic.
	if not InputManager.enabled:
		return

	# Lecture sensitivity + invert chaque event = hot-reload automatique au runtime.
	var sensitivity: float = InputManager.mouse_sensitivity
	var invert_factor: float = -1.0 if InputManager.mouse_y_inverted else 1.0

	# Convention écran → 3D : delta.x positif = curseur droite = caméra tourne droite (yaw -)
	# delta.y positif = curseur bas = caméra regarde bas (pitch -, sauf invert)
	var yaw_delta: float = -delta.x * sensitivity
	var pitch_delta: float = -delta.y * sensitivity * invert_factor

	# Clamp magnitude AVANT commit (AC-CAM-04). Pas d'accumulation interne :
	# le surplus est jeté, pas mémorisé pour le frame suivant.
	yaw_delta = clamp(yaw_delta, -MAX_ROT_PER_FRAME, MAX_ROT_PER_FRAME)
	pitch_delta = clamp(pitch_delta, -MAX_ROT_PER_FRAME, MAX_ROT_PER_FRAME)

	# Apply ownership-correct (ADR-0002 Required patterns).
	_player.rotation.y += yaw_delta
	_camera_arm.rotation.x = clamp(
		_camera_arm.rotation.x + pitch_delta,
		-PITCH_LIMIT,
		PITCH_LIMIT,
	)

	# Story 012 — mesure latence E2E depuis réception signal → rotation committed.
	# Écriture ring buffer après commit (t_applied implicite = maintenant).
	var latency_ms: float = float(Time.get_ticks_usec() - t_event) / 1000.0
	_latency_samples[_latency_write_idx] = latency_ms
	_latency_write_idx = (_latency_write_idx + 1) % LATENCY_CAPACITY


# ---------------------------------------------------------------------------
# Public getters — used by integration tests (story 001) and future systems.
# Returning typed refs guarantees static analysis catches contract violations.
# ---------------------------------------------------------------------------

## Returns the CameraArm node (self). Ownership : pitch (story 002+).
func get_camera_arm() -> Node3D:
	return _camera_arm


## Returns the CameraEffects node. Ownership : tilt (story 005+).
func get_camera_effects() -> Node3D:
	return _camera_effects


## Returns the Camera3D node. Ownership : FOV + shake (story 005+).
func get_camera3d() -> Camera3D:
	return _camera3d


# ---------------------------------------------------------------------------
# Public API — settings persistence (story 013, ADR-0014)
# ---------------------------------------------------------------------------

## Sauvegarde les `settings` courants vers `user://settings/camera.tres` via le
## helper SettingsResource. Trigger explicite uniquement (Settings menu apply,
## flush-on-quit, debug command) — ADR-0014 D-6 interdit l'auto-save en hot path.
##
## Retourne l'Error de ResourceSaver (OK si succès). No-op safe si `settings == null`
## (suppress_settings_load actif) — retourne ERR_UNCONFIGURED.
## Usage : var err := camera_system.save_settings()
func save_settings() -> Error:
	if settings == null:
		return ERR_UNCONFIGURED
	var err: Error = SettingsResource.save(settings, "camera")
	if err != OK:
		push_warning("[camera-settings] save failed: %d" % err)
	return err


# ---------------------------------------------------------------------------
# Private — settings load (story 013, ADR-0014 D-3/D-4/D-5)
# ---------------------------------------------------------------------------

## Charge `user://settings/camera.tres` ou applique les defaults silencieusement
## si first launch (ADR-0014 D-4). Migration forward-only via `CameraSettings.migrate_from`.
##
## Propagation Tuning Knobs : `mouse_sensitivity` + `mouse_y_inverted` exposés sur
## InputManager (consumer principal — Camera lit ces props chaque mouse_motion).
## Ainsi Camera est l'autorité settings (GDD camera-system Tuning Knobs) et
## Input est tenant runtime (hot path). `fov_user_offset` reste local — appliqué
## par `_update_fov_dash` et le reset `_on_respawned`.
func _load_settings() -> void:
	settings = SettingsResource.load_or_default(
		"camera",
		Callable(CameraSettings, "create_defaults"),
		Callable(CameraSettings, "migrate_from"),
	) as CameraSettings
	# Propagation aux propriétés runtime InputManager — last-write-wins par rapport
	# à input_settings.tres (cohérent : Camera GDD est autorité Tuning Knobs souris).
	InputManager.mouse_sensitivity = settings.mouse_sensitivity
	InputManager.mouse_y_inverted = settings.mouse_y_inverted


# ---------------------------------------------------------------------------
# Public API — perf instrumentation (story 012, GDD AC-CAM-80/81)
# Consommé par tests GdUnit4 + QA dashboard.
# ---------------------------------------------------------------------------

## Retourne {p50: float, p99: float} du coût _process en ms.
## Calculé depuis _process_cost_samples (ring buffer 240 samples, pré-alloué).
## Retourne {p50: 0.0, p99: 0.0} si le buffer est vide (pas encore d'échantillons).
## GDD AC-CAM-80 : p50 ≤ 0.2 ms, p99 ≤ 0.4 ms.
func get_process_cost_percentiles() -> Dictionary:
	return _compute_percentiles(_process_cost_samples)


## Retourne {p50: float, p99: float} de la latence mouse_motion → rotation applied en ms.
## Calculé depuis _latency_samples (ring buffer 1000 samples, pré-alloué).
## GDD AC-CAM-81 : p99 ≤ 16 ms (= 1 frame à 60 fps).
func get_mouse_latency_percentiles() -> Dictionary:
	return _compute_percentiles(_latency_samples)


## Calcule p50 + p99 depuis un PackedFloat32Array.
## Tri in-place sur un duplicate() pour ne pas altérer le ring buffer source.
## Zero-alloc côté caller (PackedFloat32Array duplicate + sort = one-shot alloc hors hot-path).
## n == 0 → retour immédiat avec zeros (buffer pas encore rempli ou non-initialisé).
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


# ---------------------------------------------------------------------------
# Public API — aim_forward (story 004, TR-cam-002, ADR-0002 Formula 5 + VC-4)
# ---------------------------------------------------------------------------

## Forward vector (convention Godot : -Z forward, +Y up) calculé en forme close
## trigonométrique depuis yaw (Player.rotation.y) + pitch (CameraArm.rotation.x).
##
## Roll-invariant par construction : camera_effects.rotation.z (tilt wall-run)
## n'apparaît pas dans la formule → hitbox katana stable horizontalement en wall-run.
##
## Coût : 2 sin + 2 cos + 1 Vector3 constructor < 0.01 ms (négligeable dans
## budget Camera _process 0.2 ms). Pas de cache — yaw/pitch changent chaque
## mouse_motion, caching introduirait cycle d'invalidation inutile.
##
## Consommé par Future Combat epic pour orienter swept katana (ADR-0002 VC-4
## cross-check : aim_forward == -Basis.from_euler(Vector3(pitch, yaw, 0),
## EULER_ORDER_YXZ).z — équivalence analytique démontrée).
var aim_forward: Vector3:
	get:
		var yaw: float = _player.rotation.y
		var pitch: float = _camera_arm.rotation.x
		var cp: float = cos(pitch)
		return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)
