# Grunt — humanoid sentinel enemy MVP (Enemy GDD r2 Rule 3 + Rule 11).
#
# Statique 1-PV : die() externe (Combat sweep) → DYING (LaserCone off + signal SYNC) →
# DEAD (post tween scale wall-clock 150 ms). Pas de queue_free() au MVP (Rule 12 — Pillar 3
# pédagogie : grunt mort persiste invisible pour Checkpoint snapshot).
#
# Story : enemy-system/story-001 (Foundation — script + state machine).
# Scene `Grunt.tscn` + LaserCone Area3D câblé en story-002.

class_name Grunt
extends CharacterBody3D


# ---------------------------------------------------------------------------
# Constants — Tuning Knobs (Enemy GDD §Tuning Knobs)
# ---------------------------------------------------------------------------

const R_ENEMY_MIN: float = 0.35
const HEIGHT_GRUNT_M: float = 1.8
const LASER_WIDTH_M: float = 0.5
const LASER_HEIGHT_M: float = 0.3
const LASER_RANGE_M: float = 6.0
const DEATH_TWEEN_DURATION_MS: int = 150
const EPSILON: float = 0.01


# ---------------------------------------------------------------------------
# Enum
# ---------------------------------------------------------------------------

enum State { ALIVE, DYING, DEAD }


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Émis SYNC (pas de CONNECT_DEFERRED côté émetteur — Combat Rule 11 contract)
## à la transition ALIVE → DYING. Combat consommera SYNC pour trigger slow-mo
## Rule 13 ; Credit/VFX/Audio/HUD se connectent indirectement.
signal enemy_killed(node: Node, position: Vector3)


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

var _state: State = State.ALIVE
var _death_tween: Tween = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Rule 10 : grunt MVP strictement statique. Pas de _physics_process tick.
	set_physics_process(false)
	velocity = Vector3.ZERO

	# Rule 4 : configure collision layers via API 1-idx (ADR-0008 D-6 lint).
	# Body : layer LAYER_ENEMY=2, mask LAYER_ENVIRONMENT=4 uniquement
	# (pas de mask LAYER_ENEMY=2 car ennemis ne se collisionnent pas entre eux).
	_set_layers_safe(self, [CollisionLayers.LAYER_ENEMY], [CollisionLayers.LAYER_ENVIRONMENT])

	# EC-ENM-6 : orthonormalize FacingPivot pour annuler tout scale non-uniforme
	# du Marker3D EnemySlot (auteur de niveau a un Marker3D scaled différemment).
	var pivot: Node3D = get_node_or_null("%FacingPivot") as Node3D
	if pivot != null:
		pivot.global_basis = pivot.global_basis.orthonormalized()

	# Rule 4 + Rule 8 : LaserCone Area3D layer LAYER_ENEMY_HITBOX=3, mask LAYER_PLAYER=1.
	# Connect body_entered handler (state-guarded).
	var cone: Area3D = get_node_or_null("%LaserCone") as Area3D
	if cone != null:
		_set_layers_safe(cone, [CollisionLayers.LAYER_ENEMY_HITBOX], [CollisionLayers.LAYER_PLAYER])
		cone.monitoring = true
		if not cone.body_entered.is_connected(_on_laser_cone_body_entered):
			cone.body_entered.connect(_on_laser_cone_body_entered)


## Force-clear bits 1-32 puis set les layers/masks demandés via API 1-idx
## (ADR-0008 D-6). Évite les rémanences éditeur (.tscn aurait pu set des bits).
func _set_layers_safe(node: CollisionObject3D, layers: Array[int], masks: Array[int]) -> void:
	for i in range(1, 33):
		node.set_collision_layer_value(i, false)
		node.set_collision_mask_value(i, false)
	for layer: int in layers:
		node.set_collision_layer_value(layer, true)
	for mask: int in masks:
		node.set_collision_mask_value(mask, true)


# ---------------------------------------------------------------------------
# Public API (lue par Combat sweep + Checkpoint System futur)
# ---------------------------------------------------------------------------

## API canonique appelée par Combat sweep katana (Rule 7 authority of kill).
## Idempotent (Rule 6) — appels 2+ sont no-op silencieux. Émet `enemy_killed`
## SYNC à la 1ère transition ALIVE → DYING.
func die() -> void:
	if _state != State.ALIVE:
		return
	_state = State.DYING
	# Rule 11.b : LaserCone monitoring=false IMMÉDIATEMENT à DYING — un grunt en
	# tween de mort ne tue plus, même pendant les 150 ms de tween (EC-ENM-4 double-sec).
	var cone: Area3D = get_node_or_null("%LaserCone") as Area3D
	if cone != null:
		cone.monitoring = false
	enemy_killed.emit(self, global_position)
	_start_death_tween()


## Getter Checkpoint System (Rule 13 + AC-ENM-07b semantic). DYING ET DEAD
## comptent comme "dead" — un kill mid-tween est correctement capturé au snapshot.
func is_dead() -> bool:
	return _state == State.DYING or _state == State.DEAD


## API Checkpoint System (Rule 13 + EC-ENM-11/12/13). Force le state cible
## sans signal `enemy_killed` ré-émis (le kill original a déjà été crédité).
func _restore_from_snapshot(was_dead: bool) -> void:
	# EC-ENM-13 : si DYING, abort le tween en cours.
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
		_death_tween = null

	var mesh: MeshInstance3D = _get_mesh()

	if was_dead:
		_state = State.DEAD
		if mesh != null:
			mesh.scale = Vector3(EPSILON, EPSILON, EPSILON)
	else:
		_state = State.ALIVE
		if mesh != null:
			mesh.scale = Vector3.ONE


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Démarre le tween scale Vector3.ONE → Vector3(EPSILON) sur 150 ms wall-clock.
## OBLIGATOIRE `set_ignore_time_scale(true)` (F-ENM-3 : indépendant de slow-mo Combat
## Engine.time_scale=0.3). Default `set_pause_mode(TWEEN_PAUSE_BOUND)` laissé
## intact (EC-ENM-9 : pause GSM gèle le tween, resume reprend).
func _start_death_tween() -> void:
	var mesh: MeshInstance3D = _get_mesh()
	if mesh == null:
		# Story-001 unit tests sans .tscn : pas de mesh → tween skipped, transition
		# DYING → DEAD via timer wall-clock direct.
		_death_tween = create_tween()
		_death_tween.set_ignore_time_scale(true)
		_death_tween.tween_interval(DEATH_TWEEN_DURATION_MS / 1000.0)
		_death_tween.tween_callback(_on_death_tween_finished)
		return

	_death_tween = create_tween()
	_death_tween.set_ignore_time_scale(true)
	_death_tween.tween_property(
		mesh,
		"scale",
		Vector3(EPSILON, EPSILON, EPSILON),
		DEATH_TWEEN_DURATION_MS / 1000.0,
	)
	_death_tween.tween_callback(_on_death_tween_finished)


func _on_death_tween_finished() -> void:
	_state = State.DEAD
	_death_tween = null
	# Rule 12 : PAS de queue_free() — grunt persiste invisible pour Checkpoint snapshot.


## Resolve mesh node défensivement — story-001 unit tests instancient `Grunt.new()`
## sans .tscn enfants ; story-002+ utilisera la scène complète avec MeshInstance3D enfant.
func _get_mesh() -> MeshInstance3D:
	return get_node_or_null("MeshInstance3D") as MeshInstance3D


## Rule 8 : LaserCone body_entered handler. Guarded par `_state != ALIVE` pour
## éviter qu'un grunt en DYING/DEAD tue encore (EC-ENM-4). `is_in_group("player")`
## évite le couplage cross-system MovementController (Player owns die()).
func _on_laser_cone_body_entered(body: Node3D) -> void:
	if _state != State.ALIVE:
		return
	if body.is_in_group("player") and body.has_method("die"):
		body.die()
