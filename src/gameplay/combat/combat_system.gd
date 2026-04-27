## CombatSystem — Player Combat Node (Story 001 scaffold + Story 002 state machine
## + Story 003 death/respawn lifecycle reset)
##
## Direct child du Player CharacterBody3D (Rule 17 / ADR-0006 D-1).
## Assure l'invariant structurel DFS preorder : Player._physics_process
## s'exécute avant CombatSystem._physics_process car Combat = child direct.
##
## Governing ADR : ADR-0006 (Combat Tick Model) + ADR-0005 (Movement Signals — amendment r2)
## Requirements  : TR-cmb-001, TR-cmb-002, TR-cmb-014 (mutual kill state ownership — reset part)
## GDD            : design/gdd/player-combat-system.md
## Story          : production/epics/combat-system/story-001-scene-skeleton-structural-invariants.md
##                  production/epics/combat-system/story-002-state-machine-cooldown-active-tick.md
##                  production/epics/combat-system/story-003-death-respawn-lifecycle-reset.md
##
## Out-of-scope (story 003) :
##   - ShapeCast3D collision layers config (story 006)
##   - Sweep collision logic (story 007/009/011)
##   - _death_pending end-of-tick consumption mutual kill mid-swing (story 014)
##   - Attack buffer set/clear pendant gameplay normal (story 012/004)
##   - Slow-mo lifecycle complet — set/expire (story 013) ; ici uniquement restore défensif
##
## FORBIDDEN (Rule 15 / AC-CMB-49 Partie A) :
##   - Ne jamais exposer is_invulnerable: bool ou invuln_timer
##   - Ne jamais se connecter au layer EnemyHitbox (layer 3)
##   - Aucune logique "pendant Swinging le Player ne peut pas mourir"
##   - Connexion CONNECT_DEFERRED sur player.died — viole ADR-0005 D-5 amendment r2
##     (vérifié AC-CMB-41 clause 8 grep textuel)

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


# ---------------------------------------------------------------------------
# @onready references
# ---------------------------------------------------------------------------

@onready var _shape_cast: ShapeCast3D = $ShapeCast3D


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
	# Defensive : zéroiser collision_mask/layer (défaut Godot mask=1 = LAYER_PLAYER)
	# pour éviter faux positifs avant story-006 (config complète sweep).
	# ADR-0008 D-3 compliance : helper CollisionLayers.build_mask([]) → 0 (pas de bitmask littéral).
	if _shape_cast != null:
		_shape_cast.margin = 0.0
		_shape_cast.collision_mask = CollisionLayers.build_mask([])
		_shape_cast.collision_layer = CollisionLayers.build_mask([])
		# Story 002 : état initial IDLE → ShapeCast3D désactivé.
		# Story 006 configurera mask/layer ; ici on garantit enabled=false au démarrage.
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


func _physics_process(delta: float) -> void:
	# ADR-0001 / ADR-0006 D-3 : toute logique combat tourne dans _physics_process (60 Hz).

	# Décrémenter le cooldown en premier, quelle que soit l'état.
	_cooldown_timer = maxf(0.0, _cooldown_timer - delta)

	if _state == State.DEAD:
		# AC-CMB-03 : aucune logique en état Dead.
		# story-014 gérera _death_pending (hors scope ici).
		return

	if _state == State.SWINGING:
		_active_tick += 1

		# Sweep delegated to story-007/009/011

		if _active_tick >= ACTIVE_TICKS:
			# Fenêtre active expirée : retour à IDLE.
			_state = State.IDLE
			_active_tick = 0
			_hit_this_swing.clear()
			if _shape_cast != null:
				_shape_cast.enabled = false
			swing_ended.emit()

	# State.IDLE : aucun travail par tick hors décrément cooldown (déjà fait).


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Point d'entrée appelé par le Player pour déclencher une attaque.
##
## Transitions :
##   IDLE + cooldown == 0.0  → SWINGING  (AC-CMB-01)
##   IDLE + cooldown  > 0.0  → no-op     (AC-CMB-02)
##   SWINGING                → no-op     (AC-CMB-02)
##   DEAD                    → no-op     (AC-CMB-03)
##
## Note : buffer d'attaque hors scope — implémenté en story-004.
func attacked() -> void:
	if _state == State.DEAD:
		return

	if _state == State.IDLE and _cooldown_timer == 0.0:
		_state = State.SWINGING
		_active_tick = 0
		_cooldown_timer = ATTACK_COOLDOWN_MS / 1000.0
		if _shape_cast != null:
			_shape_cast.enabled = true


# ---------------------------------------------------------------------------
# Signal handlers — Movement died / respawned (Story 003)
# ---------------------------------------------------------------------------

## Handler signal Player.died — connexion SYNC (ADR-0005 D-5 amendment r2 exemption).
##
## Couvre AC-CMB-11 (a) et AC-CMB-21 :
##   1. Si slow-mo actif : restore Engine.time_scale à 1.0 AVANT toute autre transition,
##      puis clear _slow_mo_active + _slow_mo_start_msec (AC-CMB-21).
##   2. Transition vers DEAD.
##   3. ShapeCast3D désactivé (cohérence avec attacked() en DEAD = no-op).
##
## NOTE : ce handler ne set PAS _death_pending — c'est la story-014 qui gère le
## scénario mid-swing mutual kill (consumer end-of-tick). En story-003, _death_pending
## est uniquement reset au respawn.
##
## FORBIDDEN (AC-CMB-41 clause 8) : ne jamais utiliser await / call_deferred ici —
## handler doit être SYNC pour Rule 17 Hybrid (story-014).
func _on_player_died() -> void:
	if _slow_mo_active:
		Engine.time_scale = 1.0
		_slow_mo_active = false
		_slow_mo_start_msec = 0
	_state = State.DEAD
	if _shape_cast != null:
		_shape_cast.enabled = false


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
