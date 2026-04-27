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

## Offset shake (rad, axes Euler YXZ Camera3D) — appliqué via assignation
## camera3d.rotation = _shake_offset chaque frame (pas +=, ADR-0002 Risk 3).
## L'assignation garantit le reset implicite quand _shake_offset → 0 et évite
## le drift visuel par cumul de transformations.
## Mis à jour par add_shake / add_shake_roll (entrée), exp decay + limit_length (sortie _update_shake).
var _shake_offset: Vector3 = Vector3.ZERO


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	assert(_camera_arm != null, "CameraSystem: _camera_arm null — script must be attached to CameraArm")
	assert(_camera_effects != null, "CameraSystem: _camera_effects null — ensure CameraEffects has unique_name_in_owner=true")
	assert(_camera3d != null, "CameraSystem: _camera3d null — ensure Camera3D has unique_name_in_owner=true")
	assert(_player != null, "CameraSystem: _player null — CameraArm must be direct child of CharacterBody3D")
	assert(PITCH_LIMIT < PI / 2.0, "CameraSystem: PITCH_LIMIT must stay strictly under PI/2 to avoid gimbal lock")
	assert(MAX_ROT_PER_FRAME > 0.0, "CameraSystem: MAX_ROT_PER_FRAME must be positive")

	# Initialisation explicite FOV avant toute lerp (story 006, AC-CAM-20 initial state).
	_camera3d.fov = BASE_FOV

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


# ---------------------------------------------------------------------------
# Lifecycle — process (cosmetic, story 005+)
# ---------------------------------------------------------------------------

## Frame update — cosmetic-only camera effects (ADR-0001 Rule 12, Control Manifest
## Presentation layer). Tilt wall-run, FOV dash et shake exécutés ici, pas dans _physics_process.
## Ordre : tilt → fov → shake. Indépendants (noeuds distincts), ordre cosmétique seulement.
func _process(delta: float) -> void:
	_update_tilt_wall_run(delta)
	_update_fov_dash(delta)
	_update_shake(delta)


# ---------------------------------------------------------------------------
# Private — tilt wall-run (story 005, TR-cam-004, ADR-0002 + ADR-0005)
# ---------------------------------------------------------------------------

## Dérive wall_side depuis player.wall_normal (read-only, owned by Movement — ADR-0005).
## Interpole camera_effects.rotation.z vers la cible chaque frame.
##
## Dérivation continue (pas de signal connection) : une approche signals-only
## raterait AC-CAM-12 (oscillation gauche↔droit sans sortie de state).
##
## wall_normal == Vector3.ZERO → wall_side == 0 → target == 0 (pas en wall-run).
##
## Lire wall_normal via get("wall_normal") : évite crash si Movement pas encore
## implémenté (property absente du script = null, sign(0) = 0, pas de tilt).
func _update_tilt_wall_run(delta: float) -> void:
	# Lecture défensive : get() retourne null si wall_normal absent du script Player.
	# Cela arrive pendant le développement quand Movement stories pas encore Complete.
	var raw_normal: Variant = _player.get("wall_normal")
	var wall_normal: Vector3 = raw_normal as Vector3 if raw_normal != null else Vector3.ZERO

	# Dérivation wall_side (Rule 4 ADR-0005) : signe du dot entre la normale inversée
	# et l'axe X local du Player. sign(0)==0 → pas de tilt quand wall_normal==ZERO.
	var wall_side: int = int(sign((-wall_normal).dot(_player.global_transform.basis.x)))
	var target_roll: float = WALL_RUN_TILT_ANGLE * wall_side

	# Lerp cosmétique, clamp du facteur pour protéger contre delta élevé (frame spike).
	# Reduce_motion multiplier PAS dans cette story (story 010).
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
## Reduce_motion multiplier (DASH_FOV_KICK * 0.5 si reduce_motion, peak 95°) :
## PAS dans cette story — ajouté par story 010.
## Respawn reset (_camera3d.fov = BASE_FOV, _is_dashing = false) :
## PAS dans cette story — ajouté par story 008.
func _update_fov_dash(delta: float) -> void:
	var target_fov: float = BASE_FOV + (DASH_FOV_KICK if _is_dashing else 0.0)
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
# Public API — shake (story 007, TR-cam-001, ADR-0002 Risk 3)
# Préparée pour consumers VFX hit katana / boss impact (post-MVP, hors scope MVP).
# MVP : seul _on_wall_jumped l'appelle.
# ---------------------------------------------------------------------------

## Ajoute un offset additif au shake courant. Borne via limit_length au cap MAX_SHAKE_MAGNITUDE.
## Zero-alloc : Vector3 value type, += et limit_length() retournent stack.
## AC-CAM-32 : 3× add_shake_roll(0.05) même tick → length() ≤ 0.2 (cap).
func add_shake(offset_radians: Vector3) -> void:
	_shake_offset += offset_radians
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
# Input handlers (story 002+)
# ---------------------------------------------------------------------------

## Applique raw yaw + pitch reçus depuis InputManager.mouse_motion.
## Ownership ADR-0002 strict : yaw=Player.rotation.y, pitch=CameraArm.rotation.x.
## Pas de smoothing, pas de buffer (Pillar 1 FLOW raw feel).
## Gates enabled / mouse_captured : story-003 (early return, zero alloc, no log).
## Gates state Respawning / reduce_motion : stories 008 / 010.
func _on_mouse_motion(delta: Vector2) -> void:
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
