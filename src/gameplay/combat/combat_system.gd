## CombatSystem — Player Combat Node (Story 001 scaffold + Story 002 state machine
## + Story 003 death/respawn lifecycle reset + Story 004 attacked handler + buffer 80 ms)
##
## Direct child du Player CharacterBody3D (Rule 17 / ADR-0006 D-1).
## Assure l'invariant structurel DFS preorder : Player._physics_process
## s'exécute avant CombatSystem._physics_process car Combat = child direct.
##
## Governing ADR : ADR-0006 (Combat Tick Model) + ADR-0005 (Movement Signals — amendment r2)
##                 + ADR-0004 (Input — Combat ne polle JAMAIS InputManager, signal-driven)
## Requirements  : TR-cmb-001, TR-cmb-002, TR-cmb-008 (signal-driven), TR-cmb-009 (buffer single-slot),
##                 TR-cmb-014 (mutual kill state ownership — reset part)
## GDD            : design/gdd/player-combat-system.md
## Story          : production/epics/combat-system/story-001-scene-skeleton-structural-invariants.md
##                  production/epics/combat-system/story-002-state-machine-cooldown-active-tick.md
##                  production/epics/combat-system/story-003-death-respawn-lifecycle-reset.md
##                  production/epics/combat-system/story-004-attacked-handler-buffer-single-slot.md
##
## Out-of-scope (story 004) :
##   - ShapeCast3D collision layers config (story 006)
##   - Sweep collision logic (story 007/009/011)
##   - _death_pending end-of-tick consumption mutual kill mid-swing (story 014)
##   - Slow-mo lifecycle complet — set/expire (story 013) ; ici uniquement restore défensif
##
## FORBIDDEN :
##   Rule 15 / AC-CMB-49 Partie A :
##   - Ne jamais exposer is_invulnerable: bool ou invuln_timer
##   - Ne jamais se connecter au layer EnemyHitbox (layer 3)
##   - Aucune logique "pendant Swinging le Player ne peut pas mourir"
##   - Connexion CONNECT_DEFERRED sur player.died — viole ADR-0005 D-5 amendment r2
##     (vérifié AC-CMB-41 clause 8 grep textuel)
##   Story 004 / Core Rule 1 / AC-CMB-7 :
##   - Ne jamais lire InputManager.* depuis ce fichier — Combat est signal-driven
##     (vérifié grep CI / test_combat_source_no_input_manager_reference)

class_name CombatSystem
extends Node3D


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Durée de la fenêtre d'attaque active en millisecondes (GDD §G).
const SWING_DURATION_MS: float = 120.0

## Cooldown entre deux attaques en millisecondes (GDD §G).
const ATTACK_COOLDOWN_MS: float = 400.0

## Nombre de ticks physics (60 Hz) couvrant la fenêtre d'attaque active.
## Math : ceil(120 / (1000 / 60)) = ceil(120 / 16.666…) = ceil(7.2) = 8.
const ACTIVE_TICKS: int = int(ceil(SWING_DURATION_MS / (1000.0 / 60.0)))

## Engine.time_scale appliqué pendant la slow-mo de feedback kill (GDD §J — story 013).
## Référencé ici uniquement pour restore défensif au died (story 003 AC-CMB-21).
const SLOW_MO_SCALE: float = 0.3

## Durée wall-clock (ms) de la fenêtre slow-mo (story 013 — GDD §J Formula 7).
## Restore Engine.time_scale à 1.0 dans `_physics_process` après cette durée écoulée.
## NB : 50 ms wall-clock = ~167 ms perçus pendant la slow-mo (50 / 0.3).
const SLOW_MO_DURATION_MS: float = 50.0

## Fenêtre de bufferisation single-slot pour `attacked` reçu pendant cooldown (GDD §G — story 004).
## Un signal reçu avec `_cooldown_timer ∈ (0, ATTACK_BUFFER_MS/1000]` est mémorisé puis consommé
## au tick où `_cooldown_timer == 0` ET `_state == IDLE` (AC-CMB-38).
const ATTACK_BUFFER_MS: float = 80.0

## Rayon (m) de la CapsuleShape3D du katana (story 006 — synced avec combat_system.tscn).
const KATANA_RADIUS: float = 0.45

## Hauteur (m) de la CapsuleShape3D du katana = portée d'attaque (story 006).
const KATANA_REACH: float = 1.8

## Plafond multi-hit par swing (GDD §H Multi-Hit Constraint). +2 pour buffer dedup.
## Synced avec ShapeCast3D.max_results = 8 dans combat_system.tscn.
const MAX_KILLS_PER_SWING: int = 6

## Nombre de substeps anti-tunneling par tick actif (story 009 — ADR-0006 D-3 + Formula 3).
## Constant compile-time : `gap_max = V × delta / N` à V=30 m/s, delta=1/60, N=3 →
## gap = 0.166 m << 2 × r_enemy_min = 0.7 m. FORBIDDEN : branching dynamique sur velocity
## (vérifié AC-CMB-14 grep statique — pas de `TUNNELING_THRESHOLD if`).
const N_SUBSTEPS: int = 3

## Rayon (m) du Player CapsuleShape3D — synced avec Player.tscn (radius=0.35).
## Utilisé par invariant #1 (`KATANA_REACH > PLAYER_CAPSULE_RADIUS + 1.0`).
const PLAYER_CAPSULE_RADIUS: float = 0.35

## Rayon minimal (m) d'un ennemi (Combat §D.3 r_enemy_min).
## Utilisé par invariant #5 anti-tunneling (`gap_max < 2 × ENEMY_RADIUS_MIN`).
const ENEMY_RADIUS_MIN: float = 0.35

## Vélocité max gameplay (m/s) — dash speed (Movement DASH_SPEED).
## Utilisé par invariant #5 (gap_max calculation).
const V_MAX: float = 30.0


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

## États de la machine à états du système de combat.
##   IDLE     — en attente, aucune attaque en cours.
##   SWINGING — fenêtre d'attaque active (ACTIVE_TICKS ticks).
##   DEAD     — joueur mort, toute logique combat suspendue.
enum State { IDLE, SWINGING, DEAD }


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Émis une fois quand la fenêtre d'attaque active expire (transition SWINGING → IDLE).
signal swing_ended()


# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

var _state: State = State.IDLE
var _active_tick: int = 0
var _cooldown_timer: float = 0.0
var _hit_this_swing: Array[int] = []

## Drapeau slow-mo actif (story 013 owner ; story 003 lit pour restore défensif au died).
var _slow_mo_active: bool = false

## Timestamp wall-clock (Time.get_ticks_msec) du début slow-mo (story 013 ; reset au respawn).
var _slow_mo_start_msec: int = 0

## Drapeau "died reçu mid-swing" (story 014 end-of-tick consumer ; story 003 reset au respawn).
var _death_pending: bool = false

## Drapeau attack buffer single-slot (story 004/012 owner ; story 003 reset au respawn).
var _buffered_attack: bool = false

## Position du Player au tick N-1 (capturée à la FIN de `_physics_process` story 008).
## Owned exclusivement par Combat (TR-cmb-003 / ADR-0006 D-3) — sert de base anti-tunneling
## story 009 (sweep entre `_prev_position` et `player.global_position` du tick courant).
## Initialisée à `player.global_position` dans `_ready()`.
var _prev_position: Vector3 = Vector3.ZERO

## Story 013 : Callable wall-clock substituable en test. Default = `Time.get_ticks_msec`.
## Permet aux tests d'injecter un mock retournant des timestamps fixes (déterminisme).
var _get_time_msec: Callable = Time.get_ticks_msec

## Story 013 / accessibility (story 022 — branch C) : si `true`, désactive la slow-mo
## sur 1er enemy_killed (cf. AC-CMB-19 r6). Toggleable runtime via settings handler.
@export var _reduce_motion_disable_slow_mo: bool = false


# ---------------------------------------------------------------------------
# @onready references
# ---------------------------------------------------------------------------

@onready var _shape_cast: ShapeCast3D = $ShapeCast3D

## Référence au CameraSystem (script attaché à CameraArm — sibling sous Player).
## Story 007 : lecture `aim_forward` (read-only, ADR-0002 D-2 close-form trigo roll-corrigé).
## Resolved via sibling lookup en _ready() — null en test isolé (fallback Vector3.FORWARD).
var _camera_system: Node = null


# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	# ADR-0006 D-1 : CombatSystem doit être direct child du Player CharacterBody3D.
	# Le DFS preorder de Godot garantit Player._physics_process → CombatSystem._physics_process
	# uniquement si Combat est child direct (pas sibling, pas grandchild).
	assert(
		get_parent() is CharacterBody3D,
		"Combat parent must be CharacterBody3D (Player)"
	)

	# ADR-0006 D-2 : physics_process_priority == 0 (défaut) est un invariant structurel.
	# Toute valeur non-nulle casse le DFS parent-before-child ordering (Rule 17).
	assert(
		physics_process_priority == 0,
		"Combat physics_process_priority must be default 0 (DFS preorder Rule 17)"
	)

	# ADR-0006 Gap 8 (résolu 2026-04-23) : Jolt ignore ShapeCast3D.margin.
	# Forcer margin = 0.0 explicitement pour éviter toute ambiguïté hitbox.
	#
	# Story 006 ADR-0008 D-3 : config collision via API 1-indexée stricte.
	# Force-clear les 32 bits puis set LAYER_PLAYER (self) + LAYER_ENEMY (mask).
	# Cette réécriture override les valeurs par défaut héritées du .tscn pour garantir
	# AC-CMB-09 même si quelqu'un mute la scène inline (defense in depth).
	if _shape_cast != null:
		_shape_cast.margin = 0.0
		for i: int in range(1, 33):
			_shape_cast.set_collision_layer_value(i, false)
			_shape_cast.set_collision_mask_value(i, false)
		_shape_cast.set_collision_layer_value(CollisionLayers.LAYER_PLAYER, true)
		_shape_cast.set_collision_mask_value(CollisionLayers.LAYER_ENEMY, true)
		# Story 002 : état initial IDLE → ShapeCast3D désactivé.
		_shape_cast.enabled = false

	# Story 003 : connexion SYNC (default flag 0) aux signaux Movement died/respawned.
	# ADR-0005 D-5 amendment r2 exige SYNC pour died (handler set _death_pending avant
	# le _physics_process Combat du même tick — Rule 17 Hybrid mutual kill).
	# Defensive : si le parent n'expose pas encore les signaux (Movement non implémenté
	# au MVP / scaffolds tests), on skip — le test peut appeler les handlers directement
	# OU brancher des signaux user_signal côté mock.
	# FORBIDDEN : ajouter CONNECT_DEFERRED sur ces deux connexions (AC-CMB-41 clause 8).
	var parent: Node = get_parent()
	if parent.has_signal("died"):
		parent.died.connect(_on_player_died)
	if parent.has_signal("respawned"):
		parent.respawned.connect(_on_player_respawned)

	# Story 004 : connexion au signal `attacked` Movement (ADR-0005 D-2 outbound-only).
	# Combat NE POLLE JAMAIS InputManager — la décision d'attaquer vient toujours du Player
	# via signal. Mode SYNC OK : handler léger (assert + delegate vers `attacked()`).
	if parent.has_signal("attacked"):
		parent.attacked.connect(_on_player_attacked)

	# Story 007 : lookup CameraSystem (sibling sous Player parent).
	# ADR-0002 D-2 : Combat lit `aim_forward` (read-only roll-corrigé). Pattern interdit :
	# `camera.basis.z`, `player.transform.basis.z` (lint AC-CMB-grep-aim-direct).
	# Fallback test isolé : `_camera_system = null` → `_start_swing` utilise Vector3.FORWARD.
	_camera_system = parent.get_node_or_null("CameraArm")

	# Story 008 : init `_prev_position` à la position courante du Player.
	# DFS preorder Player→Combat (ADR-0006 D-1) garantit que parent est ready.
	var parent_3d: Node3D = parent as Node3D
	if parent_3d != null:
		_prev_position = parent_3d.global_position


func _physics_process(delta: float) -> void:
	# ADR-0001 / ADR-0006 D-3 : toute logique combat tourne dans _physics_process (60 Hz).

	# Story 016 (DEC-r5-2 Option A) : invariants validation runtime debug-only.
	# Couvre live-tuning Inspector — re-évalue les 8 invariants chaque tick en debug.
	# `assert()` est compilé out en release : 0 overhead production.
	if OS.is_debug_build():
		_validate_invariants()

	# Story 015 AC-CMB-28 (race mitigation) : si Player.state == DEAD sans signal `died`
	# reçu (race théorique 1 tick), force Combat à DEAD. Restriction r2 : UNIQUEMENT si
	# `_state == IDLE` (ne pas écraser `_death_pending` Hybrid en SWINGING — story 014).
	if _state == State.IDLE:
		var p: Node = get_parent()
		if p is MovementController and (p as MovementController).state == MovementController.State.DEAD:
			_state = State.DEAD
			if _shape_cast != null:
				_shape_cast.enabled = false
			return

	# Story 013 : check slow-mo restore en premier pour que les autres systèmes lisent
	# un Engine.time_scale cohérent dans le même tick. ADR-0001 authority obligatoire ici.
	_check_slow_mo_restore()

	# Décrémenter le cooldown en premier, quelle que soit l'état.
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)

	if _state == State.DEAD:
		# AC-CMB-03 : aucune logique en état Dead.
		# story-014 gérera _death_pending (hors scope ici).
		# Note : `_prev_position` PAS mis à jour en DEAD — au respawn le tick suivant
		# capturera la nouvelle position (acceptable, story-008 AC-3 edge case).
		return

	if _state == State.SWINGING:
		_active_tick += 1

		# Story 009 AC-CMB-14 : N=3 substeps anti-tunneling balayent la trajectoire
		# entre `_prev_position` (tick N-1) et `player.global_position` (tick N).
		# Les colliders détectés sont accumulés dans `_hit_this_swing` (dedup via instance_id).
		# Story 011/012 consommera cette liste pour la résolution de kills.
		var swing_hits: Array[int] = _collect_swing_hits()
		for instance_id: int in swing_hits:
			if not (instance_id in _hit_this_swing):
				_hit_this_swing.append(instance_id)

		# Story 008 AC-CMB-44 : laisser le ShapeCast à la position canonique tick courant
		# pour observabilité externe (le dernier substep a laissé le ShapeCast à un état
		# intermédiaire de la trajectoire).
		_update_sweep_origin()

		if _active_tick >= ACTIVE_TICKS:
			# Fenêtre active expirée : retour à IDLE.
			_state = State.IDLE
			_active_tick = 0
			_hit_this_swing.clear()
			if _shape_cast != null:
				_shape_cast.enabled = false
			swing_ended.emit()

	# Story 004 — AC-CMB-38 : consommation buffer single-slot.
	# Si on est en IDLE avec cooldown libéré ce tick et un attack bufferisé, on déclenche
	# un nouveau swing immédiatement (même tick que la libération du cooldown).
	# Vérifié APRÈS la transition SWINGING→IDLE ci-dessus pour permettre la consommation
	# au tick exact où le cooldown atteint 0 (cas où ATTACK_COOLDOWN_MS - SWING_DURATION_MS
	# tomberait sur la même frame — AC-5 edge "consommé même tick").
	if _state == State.IDLE and _cooldown_timer == 0.0 and _buffered_attack:
		_buffered_attack = false
		_start_swing()

	# Story 014 — drain `_death_pending` reçu mid-swing (Rule 17 Hybrid M1 Option C).
	# Le sweep a été résolu juste au-dessus → maintenant on peut transitionner Dead.
	# Garantit symétrie mutual kill : Player + Enemy meurent sur le MÊME tick.
	if _death_pending:
		_drain_death_pending()

	# Story 008 — capture `_prev_position` à la FIN du tick (last statement).
	# Sert de base anti-tunneling story-009 (sweep entre prev tick N et current tick N+1).
	# Skip si parent n'est pas Node3D (test scaffold edge case).
	var parent_3d: Node3D = get_parent() as Node3D
	if parent_3d != null:
		_prev_position = parent_3d.global_position


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Point d'entrée pour déclencher une attaque.
##
## Appelé soit par le signal handler `_on_player_attacked` (chemin production), soit
## directement par les tests unitaires comme test seam (state_machine_lifecycle_test.gd).
##
## Transitions (story 002 + 004) :
##   DEAD                                    → no-op       (AC-CMB-03)
##   IDLE + cooldown == 0.0                  → SWINGING    (AC-CMB-01 / AC-CMB-23)
##   SWINGING + cooldown ∈ (0, BUFFER_S]     → buffer set  (AC-CMB-38)
##   SWINGING + cooldown > BUFFER_S          → no-op       (AC-CMB-39 hors fenêtre)
##   IDLE + cooldown > 0.0                   → no-op       (AC-CMB-02)
##
## Buffer single-slot : 2e/3e signal dans la fenêtre laisse `_buffered_attack`
## inchangé (idempotent, 1er retenu).
func attacked() -> void:
	if _state == State.DEAD:
		return

	if _state == State.IDLE and _cooldown_timer == 0.0:
		_start_swing()
		return

	# Story 004 AC-CMB-38 : bufferiser si dans la fenêtre 80 ms (cooldown ∈ (0, BUFFER_S]).
	# La condition `_cooldown_timer > 0.0` exclut l'edge où cooldown vient d'atteindre 0
	# (déjà consommé en _physics_process via le bloc buffer-consumption).
	if _state == State.SWINGING and _cooldown_timer > 0.0 \
			and _cooldown_timer <= ATTACK_BUFFER_MS / 1000.0:
		_buffered_attack = true


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Transition IDLE → SWINGING avec setup uniforme (durée fenêtre, cooldown,
## activation ShapeCast3D). Extrait pour DRY entre `attacked()` (entrée directe)
## et la consommation buffer dans `_physics_process` (story 004 AC-CMB-38).
##
## Pré-conditions : appelant garantit `_state == State.IDLE` et `_cooldown_timer == 0.0`.
##
## Story 007 (aim consumption + position + guards) :
##   - Lit `_camera_system.aim_forward` si disponible (production path).
##   - Si aim invalide (ZERO / NaN / inf) → swing ignoré, `_state` reste IDLE,
##     cooldown PAS armé (le joueur peut ré-essayer immédiatement).
##   - Si `_camera_system == null` (test isolé) → fallback `Vector3.FORWARD`.
##   - Position ShapeCast3D : `player.global_position + aim × KATANA_REACH/2`.
##   - Orientation ShapeCast3D : `_build_capsule_basis(aim)` (axe Y aligné sur aim).
func _start_swing() -> void:
	# Story 007 : valider aim AVANT mutation d'état pour AC-CMB-27 / AC-CMB-48
	# (swing ignoré sur aim invalide, _state reste IDLE, cooldown PAS armé).
	if _camera_system != null:
		var raw: Variant = _camera_system.get("aim_forward")
		if raw is Vector3 and not _validate_aim(raw as Vector3):
			return

	_state = State.SWINGING
	_active_tick = 0
	_cooldown_timer = ATTACK_COOLDOWN_MS / 1000.0
	_hit_this_swing.clear()

	# Position tick 0 (story 007 AC-CMB-16). Le tick suivant et au-delà passe par
	# `_update_sweep_origin` dans `_physics_process` (story 008 AC-CMB-44).
	_update_sweep_origin()
	if _shape_cast != null:
		_shape_cast.enabled = true


## Validation aim_forward avant utilisation (story 007 AC-CMB-27 / AC-CMB-48).
##
## Refuse :
##   - NaN ou inf dans n'importe quelle composante (`is_finite()` false).
##   - Vecteur quasi-zéro (`is_zero_approx()` true) — direction non définie.
##
## En debug build, émet `push_error` pour faciliter le diagnostic. En release,
## le swing est juste ignoré silencieusement (FLOW : pas de pop-up d'erreur).
func _validate_aim(aim: Vector3) -> bool:
	if not aim.is_finite():
		if OS.is_debug_build():
			push_error("Combat: aim_forward NaN/inf — swing ignoré (forward=%v)" % aim)
		return false
	if aim.is_zero_approx():
		if OS.is_debug_build():
			push_error("Combat: aim_forward zero — swing ignoré")
		return false
	return true


## Calcule les positions de début/fin d'un substep i ∈ [0, N_SUBSTEPS-1] (story 009).
##
## Interpolation linéaire entre `prev` (position tick N-1) et `current` (position tick N),
## avec offset constant `aim × KATANA_REACH/2` pour positionner le centre de la capsule
## à mi-portée du katana.
##
## Retourne `[from_pos, to_pos]` : 2 Vector3 stack-allocated (Array temporaire).
##
## Pure function — testable sans physics, ADR-0006 D-3 Formula 3 vérifiable.
func _compute_substep_segment(
		i: int,
		prev: Vector3,
		current: Vector3,
		aim: Vector3
) -> Array[Vector3]:
	var t0: float = float(i) / float(N_SUBSTEPS)
	var t1: float = float(i + 1) / float(N_SUBSTEPS)
	var offset: Vector3 = aim * (KATANA_REACH / 2.0)
	var result: Array[Vector3] = [
		prev.lerp(current, t0) + offset,
		prev.lerp(current, t1) + offset
	]
	return result


## Déduplique une liste de colliders par `instance_id` (story 009 AC-4).
##
## Skip silencieusement les `null` (substep peut renvoyer null si l'enemy a été freed
## entre-temps). Dictionary keyed par instance_id pour O(1) lookup.
##
## Pure function — testable avec mocks Object qui implémentent `get_instance_id()`.
func _dedupe_collider_ids(colliders: Array[Object]) -> Array[int]:
	var seen: Dictionary = {}
	var result: Array[int] = []
	for obj: Object in colliders:
		if obj == null:
			continue
		var id: int = obj.get_instance_id()
		if not (id in seen):
			seen[id] = true
			result.append(id)
	return result


## Exécute N_SUBSTEPS sweeps anti-tunneling et retourne les instance_ids dédupliqués
## des colliders touchés (story 009 — ADR-0006 D-3 Formula 3).
##
## Pour chaque substep i :
##   from = lerp(prev, current, i/N) + aim × REACH/2
##   to   = lerp(prev, current, (i+1)/N) + aim × REACH/2
##   ShapeCast3D positionné `from`, target_position = `to - from`, force_shapecast_update().
##
## Skip silencieusement si :
##   - `_shape_cast == null` (test scaffold edge)
##   - `get_parent()` n'est pas Node3D
##   - aim invalide (story 007 — `_validate_aim` retourne false)
##
## Note : ce helper exécute des physics queries réelles via `force_shapecast_update`.
## Il n'est pas unit-testable en isolation — la résolution de hits est testée en intégration
## (story 018 soak test). Ici on couvre les sub-helpers `_compute_substep_segment` et
## `_dedupe_collider_ids` qui contiennent la logique vérifiable.
func _collect_swing_hits() -> Array[int]:
	if _shape_cast == null:
		return []
	var parent_3d: Node3D = get_parent() as Node3D
	if parent_3d == null:
		return []

	var aim: Vector3 = Vector3.FORWARD
	if _camera_system != null:
		var raw: Variant = _camera_system.get("aim_forward")
		if raw is Vector3:
			var camera_aim: Vector3 = raw as Vector3
			if not _validate_aim(camera_aim):
				return []
			aim = camera_aim

	var basis: Basis = _build_capsule_basis(aim)
	var current_pos: Vector3 = parent_3d.global_position
	var collected: Array[Object] = []

	for i: int in N_SUBSTEPS:
		var segment: Array[Vector3] = _compute_substep_segment(i, _prev_position, current_pos, aim)
		var from_pos: Vector3 = segment[0]
		var to_pos: Vector3 = segment[1]
		_shape_cast.global_transform = Transform3D(basis, from_pos)
		_shape_cast.target_position = to_pos - from_pos
		_shape_cast.force_shapecast_update()
		for j: int in _shape_cast.get_collision_count():
			var c: Object = _shape_cast.get_collider(j)
			if c != null:
				collected.append(c)

	return _dedupe_collider_ids(collected)


## Repositionne ShapeCast3D au tick courant (story 007 entrée + story 008 per-tick).
##
## Lit aim depuis `_camera_system.aim_forward` (production), ou Vector3.FORWARD si
## aucun camera_system (test isolé). Skip silencieusement si aim invalide mid-swing
## (laisse le ShapeCast à sa dernière position connue — meilleur que de désactiver
## le sweep entier sur un tick foireux isolé).
##
## Skip également si `get_parent()` n'est pas un Node3D (test scaffold edge case).
func _update_sweep_origin() -> void:
	if _shape_cast == null:
		return
	var parent_3d: Node3D = get_parent() as Node3D
	if parent_3d == null:
		return

	var aim: Vector3 = Vector3.FORWARD
	if _camera_system != null:
		var raw: Variant = _camera_system.get("aim_forward")
		if raw is Vector3:
			var camera_aim: Vector3 = raw as Vector3
			if not _validate_aim(camera_aim):
				return  # garde dernière position valide
			aim = camera_aim

	var sweep_origin: Vector3 = parent_3d.global_position + aim * (KATANA_REACH / 2.0)
	_shape_cast.global_transform = Transform3D(_build_capsule_basis(aim), sweep_origin)


## Construit une `Basis` orientée pour la CapsuleShape3D du katana telle que
## son axe Y local soit aligné sur `forward` (AC-CMB-08 r6 / story 005).
##
## Pattern cross-product direct (PAS `Basis.looking_at × from_euler(±π/2)` qui
## inverse Y de 180° — bug CONV-1 r5.2 documenté ADR-0006 D-7).
##
## Gardes :
##   1. Colinéarité UP/DOWN : si `|forward · UP| > 0.999` (regard zenith/nadir),
##      bascule sur `safe_up = Vector3.FORWARD` pour éviter `cross()` colinéaire.
##   2. Déterminant quasi-singulier : si `|det| < 0.01`, fallback `Basis.IDENTITY`
##      avec `push_error` pour signaler la pathologie (forward NaN, etc.).
##
## Pré-condition : `forward.is_normalized()` (Camera Rule 13). Assert en debug.
func _build_capsule_basis(forward: Vector3) -> Basis:
	assert(forward.is_normalized(), "aim_forward doit être unit vector (Camera Rule 13)")

	var safe_up: Vector3 = Vector3.UP
	if absf(forward.dot(Vector3.UP)) > 0.999:
		safe_up = Vector3.FORWARD  # fallback pitch ±PITCH_LIMIT (regard zenith/nadir)

	var right: Vector3 = safe_up.cross(forward).normalized()
	var local_z: Vector3 = right.cross(forward)
	var b: Basis = Basis(right, forward, local_z)  # colonne Y = forward par construction

	if absf(b.determinant()) < 0.01:
		push_error(
			"_build_capsule_basis: basis quasi-singulière, fallback IDENTITY — forward=%v"
			% forward
		)
		return Basis.IDENTITY
	return b


# ---------------------------------------------------------------------------
# Signal handlers — Movement attacked / died / respawned (Stories 003 + 004)
# ---------------------------------------------------------------------------

## Handler signal Player.attacked — connexion SYNC (ADR-0005 D-2 outbound-only).
##
## Couvre AC-CMB-22/23/30/38/39/40 (story 004) :
##   - Délègue à `attacked()` qui contient la logique state-machine + buffer.
##   - L'assert `Engine.is_in_physics_frame()` (debug build only) protège contre
##     toute future émission depuis `_process` ou `_input` (violation ADR-0005 D-4).
##
## FORBIDDEN (Core Rule 1 + AC-CMB-7) : Combat NE POLLE JAMAIS InputManager —
## la décision d'attaquer vient toujours d'ici (signal-driven).
func _on_player_attacked() -> void:
	if OS.is_debug_build():
		assert(
			Engine.is_in_physics_frame(),
			"attacked() received outside _physics_process — ADR-0005 D-4 violation"
		)
	attacked()


# ---------------------------------------------------------------------------
# Signal handlers — Movement died / respawned (Story 003)
# ---------------------------------------------------------------------------

## Handler signal Player.died — connexion SYNC (ADR-0005 D-5 amendment r2 exemption).
##
## Pattern hybride story-003 + story-014 (Rule 17 M1 Option C) :
##   - Toujours set `_death_pending = true` (signal observable du death).
##   - Si `_state != SWINGING` → drain immédiat (transition Dead, restore slow-mo, disable
##     ShapeCast). Préserve la sémantique story-003 (AC-CMB-11/21) pour died en IDLE/AIRBORNE.
##   - Si `_state == SWINGING` → drain DIFFÉRÉ à fin de `_physics_process` (story-014
##     AC-CMB-41). Permet la résolution symétrique mutual kill au END du tick.
##
## FORBIDDEN (AC-CMB-41 clause 8) : ne jamais utiliser await / call_deferred ici —
## handler doit être SYNC pour Rule 17 Hybrid (story-014).
func _on_player_died() -> void:
	_death_pending = true
	if _state != State.SWINGING:
		_drain_death_pending()


## Drain du flag `_death_pending` : restore slow-mo, transition Dead, disable ShapeCast.
##
## Idempotent : safe d'appeler avec `_death_pending == false` (no-op). Appelé soit
## immédiatement par `_on_player_died` (state non-SWINGING), soit à la fin de
## `_physics_process` après résolution sweep (state SWINGING — story-014 mutual kill).
func _drain_death_pending() -> void:
	if not _death_pending:
		return
	_death_pending = false
	if _slow_mo_active:
		Engine.time_scale = 1.0
		_slow_mo_active = false
		_slow_mo_start_msec = 0
	_state = State.DEAD
	if _shape_cast != null:
		_shape_cast.enabled = false


## Story 013 : déclenche slow-mo sur 1er enemy_killed du swing.
##
## Idempotent (multi-kill n'étend pas la fenêtre — `_slow_mo_active` flag).
## Branch accessibility (story 022) : si `_reduce_motion_disable_slow_mo == true`,
## ne mute PAS Engine.time_scale (5 kills consécutifs restent à 1.0).
##
## Appelé depuis le hit resolution loop (story 011/012) — exposé public-private pour
## permettre tests directs (story 013 AC-CMB-19/24/25).
func _trigger_slow_mo_if_first_kill() -> void:
	if _slow_mo_active:
		return  # idempotence multi-kill (AC-CMB-25)
	if _reduce_motion_disable_slow_mo:
		return  # accessibility branch C (AC-CMB-19 r6)
	_slow_mo_active = true
	_slow_mo_start_msec = _get_time_msec.call() as int
	Engine.time_scale = SLOW_MO_SCALE


## Story 016 : valide les 8 invariants Combat sur valeurs courantes (live-tuning safe).
##
## Appelé chaque `_physics_process` sous `OS.is_debug_build()` guard — `assert()` est
## compilé out en release. Couvre la mutation Inspector des `@export` (DEC-r5-2 Option A).
##
## Invariants vérifiés (cf. GDD Section D.8) :
##   #1 KATANA_REACH > PLAYER_CAPSULE_RADIUS + 1.0
##   #2 KATANA_REACH > 0.0
##   #3 ATTACK_COOLDOWN_MS >= SWING_DURATION_MS + 1 frame physics (1000/60)
##   #4 ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS
##   #5 V_MAX × delta / N_SUBSTEPS < 2 × ENEMY_RADIUS_MIN (anti-tunneling)
##   #6 SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS / 2
##   #7 ATTACK_BUFFER_MS <= ATTACK_COOLDOWN_MS / 5
##   #8 SWING_DURATION_MS / (SWING_DURATION_MS + ATTACK_COOLDOWN_MS) < 0.4 (duty cycle staccato)
func _validate_invariants() -> void:
	assert(
		KATANA_REACH > PLAYER_CAPSULE_RADIUS + 1.0,
		"Invariant #1: KATANA_REACH (%.3f) doit être > PLAYER_CAPSULE_RADIUS + 1.0 (%.3f)"
		% [KATANA_REACH, PLAYER_CAPSULE_RADIUS + 1.0]
	)
	assert(KATANA_REACH > 0.0, "Invariant #2: KATANA_REACH doit être > 0")
	var min_cooldown_ms: float = SWING_DURATION_MS + (1000.0 / 60.0)
	assert(
		ATTACK_COOLDOWN_MS >= min_cooldown_ms,
		"Invariant #3: ATTACK_COOLDOWN_MS (%.2f) doit être >= SWING + 1 frame (%.2f)"
		% [ATTACK_COOLDOWN_MS, min_cooldown_ms]
	)
	assert(
		ATTACK_COOLDOWN_MS > SWING_DURATION_MS + SLOW_MO_DURATION_MS,
		"Invariant #4: ATTACK_COOLDOWN_MS (%.2f) doit être > SWING + SLOW_MO (%.2f)"
		% [ATTACK_COOLDOWN_MS, SWING_DURATION_MS + SLOW_MO_DURATION_MS]
	)
	var gap_max: float = V_MAX * (1.0 / 60.0) / float(N_SUBSTEPS)
	var enemy_diam: float = 2.0 * ENEMY_RADIUS_MIN
	assert(
		gap_max < enemy_diam,
		"Invariant #5 anti-tunneling: gap_max (%.4f) doit être < 2 × ENEMY_RADIUS_MIN (%.4f)"
		% [gap_max, enemy_diam]
	)
	assert(
		SLOW_MO_DURATION_MS < ATTACK_COOLDOWN_MS / 2.0,
		"Invariant #6: SLOW_MO_DURATION_MS (%.2f) doit être < ATTACK_COOLDOWN_MS / 2 (%.2f)"
		% [SLOW_MO_DURATION_MS, ATTACK_COOLDOWN_MS / 2.0]
	)
	assert(
		ATTACK_BUFFER_MS <= ATTACK_COOLDOWN_MS / 5.0,
		"Invariant #7: ATTACK_BUFFER_MS (%.2f) doit être <= ATTACK_COOLDOWN_MS / 5 (%.2f)"
		% [ATTACK_BUFFER_MS, ATTACK_COOLDOWN_MS / 5.0]
	)
	var duty: float = SWING_DURATION_MS / (SWING_DURATION_MS + ATTACK_COOLDOWN_MS)
	assert(
		duty < 0.4,
		"Invariant #8 duty cycle staccato: duty (%.3f) doit être < 0.4 (sinon pas staccato)"
		% duty
	)


## Story 016 AC-CMB-13 : ratio cooldown 0..1 pour binding HUD/UI (read-only).
##
## Retourne `_cooldown_timer / (ATTACK_COOLDOWN_MS / 1000)`, clampé à [0, 1].
##   - Au déclenchement swing : ratio = 1.0 (cooldown plein).
##   - Au tick où cooldown atteint 0 : ratio = 0.0.
func get_cooldown_ratio() -> float:
	return clampf(_cooldown_timer / (ATTACK_COOLDOWN_MS / 1000.0), 0.0, 1.0)


## Story 013 : restore Engine.time_scale à 1.0 quand SLOW_MO_DURATION_MS écoulé.
##
## Appelé au début de `_physics_process` pour que les autres systèmes lisent un
## time_scale cohérent dans le même tick. ADR-0001 authority : restore depuis
## `_physics_process` UNIQUEMENT (jamais `_process`).
func _check_slow_mo_restore() -> void:
	if not _slow_mo_active:
		return
	var now: int = _get_time_msec.call() as int
	var elapsed: int = now - _slow_mo_start_msec
	if elapsed >= int(SLOW_MO_DURATION_MS):
		Engine.time_scale = 1.0
		_slow_mo_active = false
		_slow_mo_start_msec = 0


## Handler signal Player.respawned — reset complet à l'état Idle propre.
##
## Couvre AC-CMB-11 (b) — 8 vars + 2 effets externes :
##   (1) _state = IDLE
##   (2) _active_tick = 0
##   (3) _hit_this_swing.clear()
##   (4) _cooldown_timer = 0.0
##   (5) _slow_mo_active = false
##   (6) _slow_mo_start_msec = 0
##   (7) _death_pending = false
##   (8) _buffered_attack = false
##   AND : Engine.time_scale = 1.0, ShapeCast3D.enabled = false.
##
## Le paramètre spawn_position n'est pas utilisé par Combat (Movement gère le placement) ;
## il est requis par le contrat ADR-0005 D-2 du signal respawned(spawn_position: Vector3).
func _on_player_respawned(_spawn_position: Vector3) -> void:
	_state = State.IDLE
	_active_tick = 0
	_hit_this_swing.clear()
	_cooldown_timer = 0.0
	_slow_mo_active = false
	_slow_mo_start_msec = 0
	_death_pending = false
	_buffered_attack = false
	Engine.time_scale = 1.0
	if _shape_cast != null:
		_shape_cast.enabled = false
