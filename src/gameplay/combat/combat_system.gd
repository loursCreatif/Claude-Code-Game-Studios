## CombatSystem — Player Combat Node (Story 001 scaffold + Story 002 state machine
## + Story 003 death/respawn lifecycle reset + Story 004 attacked handler + buffer 80 ms)
##
## Direct child du Player CharacterBody3D (Rule 17 / ADR-0006 D-1).
## Architecture : composition via 4 handlers RefCounted injectés (_tick_handler,
## _slow_mo_handler, _hit_handler, _lifecycle_handler). Proxy properties
## transparentes exposent les variables internes pour compatibilité tests (pattern
## miroir audio_system.gd).
##
## Governing ADR : ADR-0006 (Combat Tick Model) + ADR-0005 (Movement Signals — amendment r2)
##                 + ADR-0004 (Input — Combat ne polle JAMAIS InputManager, signal-driven)
## Requirements  : TR-cmb-001, TR-cmb-002, TR-cmb-008, TR-cmb-009, TR-cmb-014
## GDD            : design/gdd/player-combat-system.md
##
## FORBIDDEN :
##   Rule 15 / AC-CMB-49 Partie A : Ne jamais exposer is_invulnerable / invuln_timer,
##   se connecter au layer EnemyHitbox (layer 3), ou gérer "pendant Swinging ≠ die".
##   CONNECT_DEFERRED sur player.died — viole ADR-0005 D-5 amendment r2.
##   Story 004 / Core Rule 1 / AC-CMB-7 : Ne jamais lire InputManager.* — signal-driven.

class_name CombatSystem
extends Node3D

# Preload bindings locaux pour les 4 handlers (TD-008 split).
# Pas via `class_name` pour bypass class cache CI gdUnit4-action.
const CombatTickHandler := preload("res://src/gameplay/combat/combat_tick_handler.gd")
const CombatSlowMoHandler := preload("res://src/gameplay/combat/combat_slow_mo_handler.gd")
const CombatHitHandler := preload("res://src/gameplay/combat/combat_hit_handler.gd")
const CombatLifecycleHandler := preload("res://src/gameplay/combat/combat_lifecycle_handler.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Durée de la fenêtre d'attaque active en millisecondes (GDD §G).
const SWING_DURATION_MS: float = 120.0

## Cooldown entre deux attaques en millisecondes (GDD §G).
const ATTACK_COOLDOWN_MS: float = 400.0

## Nombre de ticks physics (60 Hz) couvrant la fenêtre d'attaque active.
const ACTIVE_TICKS: int = int(ceil(SWING_DURATION_MS / (1000.0 / 60.0)))

## Engine.time_scale appliqué pendant la slow-mo de feedback kill (GDD §J — story 013).
const SLOW_MO_SCALE: float = 0.3

## Durée wall-clock (ms) de la fenêtre slow-mo (story 013 — GDD §J Formula 7).
const SLOW_MO_DURATION_MS: float = 50.0

## Fenêtre de bufferisation single-slot pour `attacked` reçu pendant cooldown (GDD §G).
const ATTACK_BUFFER_MS: float = 80.0

## Rayon (m) de la CapsuleShape3D du katana (story 006 — synced avec combat_system.tscn).
const KATANA_RADIUS: float = 0.45

## Hauteur (m) de la CapsuleShape3D du katana = portée d'attaque (story 006).
const KATANA_REACH: float = 1.8

## Plafond multi-hit par swing (GDD §H Multi-Hit Constraint).
const MAX_KILLS_PER_SWING: int = 6

## Nombre de substeps anti-tunneling par tick actif (story 009 — ADR-0006 D-3).
const N_SUBSTEPS: int = 3

## Rayon (m) du Player CapsuleShape3D.
const PLAYER_CAPSULE_RADIUS: float = 0.35

## Rayon minimal (m) d'un ennemi (Combat §D.3 r_enemy_min).
const ENEMY_RADIUS_MIN: float = 0.35

## Vélocité max gameplay (m/s) — dash speed.
const V_MAX: float = 30.0


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## États de la machine à états du système de combat.
enum State { IDLE, SWINGING, DEAD }


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Émis une fois quand la fenêtre d'attaque active expire (transition SWINGING → IDLE).
signal swing_ended()

## Émis à la fin du tick de résolution kill si count >= 2 (multi-hit simultané).
signal multi_kill(count: int)


# ---------------------------------------------------------------------------
# State machine variables
# ---------------------------------------------------------------------------

var _state: State = State.IDLE
var _active_tick: int = 0
var _cooldown_timer: float = 0.0
var _hit_this_swing: Array[int] = []
var _death_pending: bool = false
var _buffered_attack: bool = false

## Position du Player au tick N-1 (capturée à la FIN de `_physics_process`).
var _prev_position: Vector3 = Vector3.ZERO

## Wall-clock Callable substituable en test (ADR-0006 D-5).
var _get_time_msec: Callable = Time.get_ticks_msec


# ---------------------------------------------------------------------------
# Domain handlers (composition)
# ---------------------------------------------------------------------------

var _tick_handler: CombatTickHandler = null
var _slow_mo_handler: CombatSlowMoHandler = null
var _hit_handler: CombatHitHandler = null
var _lifecycle_handler: CombatLifecycleHandler = null


# ---------------------------------------------------------------------------
# @onready references
# ---------------------------------------------------------------------------

@onready var _shape_cast: ShapeCast3D = $ShapeCast3D

## Référence au CameraSystem (sibling sous Player). Null en test isolé (fallback FORWARD).
var _camera_system: Node = null


# ---------------------------------------------------------------------------
# Proxy properties — slow-mo handler (tests accèdent directement)
# ---------------------------------------------------------------------------

var _slow_mo_active: bool:
	get: return _slow_mo_handler._slow_mo_active
	set(v): _slow_mo_handler._slow_mo_active = v

var _slow_mo_start_msec: int:
	get: return _slow_mo_handler._slow_mo_start_msec
	set(v): _slow_mo_handler._slow_mo_start_msec = v

var _reduce_motion_disable_slow_mo: bool:
	get: return _slow_mo_handler._reduce_motion_disable_slow_mo
	set(v): _slow_mo_handler._reduce_motion_disable_slow_mo = v

var _reduce_motion_slow_mo_scale_mult: float:
	get: return _slow_mo_handler._reduce_motion_slow_mo_scale_mult
	set(v): _slow_mo_handler._reduce_motion_slow_mo_scale_mult = v

var _reduce_motion_flash_mult: float:
	get: return _slow_mo_handler._reduce_motion_flash_mult
	set(v): _slow_mo_handler._reduce_motion_flash_mult = v


# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Instancier les handlers et injecter la référence self.
	_tick_handler = CombatTickHandler.new()
	_tick_handler._combat = self
	_slow_mo_handler = CombatSlowMoHandler.new()
	_slow_mo_handler._combat = self
	_hit_handler = CombatHitHandler.new()
	_hit_handler._combat = self
	_lifecycle_handler = CombatLifecycleHandler.new()
	_lifecycle_handler._combat = self

	# ADR-0006 D-1 : CombatSystem doit être direct child du Player CharacterBody3D.
	assert(
		get_parent() is CharacterBody3D,
		"Combat parent must be CharacterBody3D (Player)"
	)

	# ADR-0006 D-2 : process_physics_priority == 0 est un invariant structurel.
	assert(
		process_physics_priority == 0,
		"Combat process_physics_priority must be default 0 (DFS preorder Rule 17)"
	)

	# ADR-0006 Gap 8 : Jolt ignore ShapeCast3D.margin — forcer 0.0 explicitement.
	# ADR-0008 D-3 : config collision via API 1-indexée stricte.
	if _shape_cast != null:
		_shape_cast.margin = 0.0
		for i: int in range(1, 33):
			_shape_cast.set_collision_mask_value(i, false)
		_shape_cast.set_collision_mask_value(CollisionLayers.LAYER_ENEMY, true)
		_shape_cast.enabled = false

	# Story 003 : connexion SYNC (default flag 0) aux signaux Movement died/respawned.
	# FORBIDDEN : CONNECT_DEFERRED sur ces deux connexions (AC-CMB-41 clause 8).
	var parent: Node = get_parent()
	if parent.has_signal("died"):
		parent.died.connect(_on_player_died)
	if parent.has_signal("respawned"):
		parent.respawned.connect(_on_player_respawned)

	# Story 004 : connexion au signal `attacked` Movement (ADR-0005 D-2 outbound-only).
	if parent.has_signal("attacked"):
		parent.attacked.connect(_on_player_attacked)

	# Story 007 : lookup CameraSystem (sibling sous Player parent).
	_camera_system = parent.get_node_or_null("CameraArm")

	# Story 008 : init `_prev_position`.
	var parent_3d: Node3D = parent as Node3D
	if parent_3d != null:
		_prev_position = parent_3d.global_position

	# Story 022 : connect AccessibilityService (ADR-0015 D-3).
	if not AccessibilityService.settings_changed.is_connected(_on_accessibility_changed):
		AccessibilityService.settings_changed.connect(_on_accessibility_changed)
	_apply_accessibility()


func _physics_process(delta: float) -> void:
	_tick_handler.tick(delta)


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Point d'entrée pour déclencher une attaque.
##
## Appelé soit par `_on_player_attacked` (production), soit directement par les tests
## unitaires comme test seam (state_machine_lifecycle_test.gd).
func attacked() -> void:
	if _state == State.DEAD:
		return

	if _state == State.IDLE and _cooldown_timer == 0.0:
		_start_swing()
		return

	# Story 004 AC-CMB-38 : bufferiser si dans la fenêtre 80 ms.
	if _state == State.SWINGING and _cooldown_timer > 0.0 \
			and _cooldown_timer <= ATTACK_BUFFER_MS / 1000.0:
		_buffered_attack = true


## Story 016 AC-CMB-13 : ratio cooldown 0..1 pour binding HUD/UI (read-only).
func get_cooldown_ratio() -> float:
	return clampf(_cooldown_timer / (ATTACK_COOLDOWN_MS / 1000.0), 0.0, 1.0)


# ---------------------------------------------------------------------------
# Private helpers — delegates to handlers (proxy methods for test seams)
# ---------------------------------------------------------------------------

func _start_swing() -> void: _tick_handler.start_swing()

func _validate_aim(aim: Vector3) -> bool: return _hit_handler.validate_aim(aim)
func _compute_substep_segment(i: int, prev: Vector3, current: Vector3, aim: Vector3) -> Array[Vector3]: return _hit_handler.compute_substep_segment(i, prev, current, aim)
func _dedupe_collider_ids(colliders: Array[Object]) -> Array[int]: return _hit_handler.dedupe_collider_ids(colliders)
func _collect_swing_hits() -> Array[int]: return _hit_handler.collect_swing_hits()
func _resolve_kills(hit_ids: Array[int]) -> void: _hit_handler.resolve_kills(hit_ids)
func _update_sweep_origin() -> void: _hit_handler.update_sweep_origin()
func _build_capsule_basis(forward: Vector3) -> Basis: return _hit_handler.build_capsule_basis(forward)
func _trigger_slow_mo_if_first_kill() -> void: _slow_mo_handler.trigger_slow_mo_if_first_kill()
func _check_slow_mo_restore() -> void: _slow_mo_handler.check_slow_mo_restore()
func _drain_death_pending() -> void: _lifecycle_handler.drain_death_pending()
func _validate_invariants() -> void: _lifecycle_handler.validate_invariants()
func _apply_accessibility() -> void: _slow_mo_handler.apply_accessibility()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

## Handler signal Player.attacked — connexion SYNC (ADR-0005 D-2 outbound-only).
## FORBIDDEN (Core Rule 1 + AC-CMB-7) : Combat NE POLLE JAMAIS InputManager.
func _on_player_attacked() -> void:
	if OS.is_debug_build():
		assert(
			Engine.is_in_physics_frame(),
			"attacked() received outside _physics_process — ADR-0005 D-4 violation"
		)
	attacked()


## Handler signal Player.died — connexion SYNC (ADR-0005 D-5 amendment r2 exemption).
## FORBIDDEN (AC-CMB-41 clause 8) : ne jamais utiliser await / call_deferred ici.
func _on_player_died() -> void:
	_lifecycle_handler.on_player_died()


## Handler signal Player.respawned — reset complet à l'état Idle propre.
func _on_player_respawned(_spawn_position: Vector3) -> void:
	_lifecycle_handler.on_player_respawned(_spawn_position)


## Story 022 : handler signal `AccessibilityService.settings_changed`.
func _on_accessibility_changed() -> void:
	_apply_accessibility()
