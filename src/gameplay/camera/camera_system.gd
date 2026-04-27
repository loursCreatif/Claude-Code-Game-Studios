class_name CameraSystem
extends Node3D

## Camera system orchestrator attached to CameraArm (Node3D child of CharacterBody3D).
##
## ADR-0002 ownership model (one axis per node, no cross-writes) :
##   - Yaw   : Player.rotation.y       (written by movement system)
##   - Pitch : CameraArm.rotation.x    (written by this system, story 002+)
##   - Tilt  : CameraEffects.rotation.z (written by this system, story 005+)
##   - FOV   : Camera3D.fov            (written by this system, story 005+)
##   - Shake : Camera3D.h_offset / v_offset (story 007+)
##
## TR-cam-001 : ownership séparé par étage scene tree.
## TR-cam-003 : logique caméra en _process (frame rate affichage) — pas de _physics_process.
##
## Story 001 : scene skeleton only. Motion logic arrives in story 002+.
## Story 002 : yaw + pitch raw apply via InputManager.mouse_motion signal.
## Story 005 : tilt wall-run — derive wall_side from player.wall_normal + lerp camera_effects.rotation.z.


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
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	assert(_camera_arm != null, "CameraSystem: _camera_arm null — script must be attached to CameraArm")
	assert(_camera_effects != null, "CameraSystem: _camera_effects null — ensure CameraEffects has unique_name_in_owner=true")
	assert(_camera3d != null, "CameraSystem: _camera3d null — ensure Camera3D has unique_name_in_owner=true")
	assert(_player != null, "CameraSystem: _player null — CameraArm must be direct child of CharacterBody3D")
	assert(PITCH_LIMIT < PI / 2.0, "CameraSystem: PITCH_LIMIT must stay strictly under PI/2 to avoid gimbal lock")
	assert(MAX_ROT_PER_FRAME > 0.0, "CameraSystem: MAX_ROT_PER_FRAME must be positive")

	# Story 002 : connexion synchrone (CONNECT_0 default) — handler léger,
	# zéro alloc, mutation scalaire uniquement (ADR-0005 D-5 consumer léger).
	# Story 011 ajoutera le _exit_tree disconnect symétrique.
	InputManager.mouse_motion.connect(_on_mouse_motion)


# ---------------------------------------------------------------------------
# Lifecycle — process (cosmetic, story 005+)
# ---------------------------------------------------------------------------

## Frame update — cosmetic-only camera effects (ADR-0001 Rule 12, Control Manifest
## Presentation layer). Tilt wall-run exécuté ici, pas dans _physics_process.
func _process(delta: float) -> void:
	_update_tilt_wall_run(delta)


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
