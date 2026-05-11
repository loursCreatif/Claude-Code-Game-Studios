## CreditEconomy — Autoload singleton for the Credit Economy system.
##
## Owns the single authoritative credit counter (_total_credits).
## Implements R-CRD-1 (unique non-negative int counter), R-CRD-4 (atomic
## try_spend sink), R-CRD-13 (SourceKind enum), R-CRD-3/5/6/7/8 (KILL source +
## idempotence + multi-kill batching + SYNC emission).
##
## Design document : design/gdd/credit-economy-system.md
## ADR-0001 : _physics_process is the sole authority for state mutation.
## ADR-0006 : MAX_KILLS_PER_SWING=3 enforced upstream Combat ; signal contract
##            enemy_killed propagated via Enemy die().
## ADR-0007 : autoload Node singleton pattern, process_mode ALWAYS.
## Stories  : production/epics/credit-economy-system/story-001-... (skeleton)
##            production/epics/credit-economy-system/story-002-... (KILL)
##
## NO class_name declaration — would collide with the autoload identifier
## (see feedback memory feedback_godot_class_name_autoload_collision).
##
## Out of scope (story 002) : guards _is_hydrated / PAUSED on _on_enemy_killed
## (story 004), Source SECRET (story 003), run-purge via GSM (story 005),
## perf benchmark (story 006), static lints (story 007).

extends Node

# ---------------------------------------------------------------------------
# Enum
# ---------------------------------------------------------------------------

## Source that triggered a credit change.
## Exactly 4 MVP values. BOSS_BONUS / ROOM_CLEAR_BONUS reserved for Tier 2+
## (locked by AC-CRD-43 — do NOT add here).
enum SourceKind {
	KILL        = 0,
	SECRET      = 1,
	SPEND_SHOP  = 2,
	BOOT_HYDRATE = 3,
}

# ---------------------------------------------------------------------------
# Tuning Knobs (story 003 — F-CRD-2 secret formula)
# ---------------------------------------------------------------------------

## Base credit reward for collecting a secret. Final credit = BASE × tier.
## Tier 2+ knob : will move to `data/balance/credit_config.tres` once balance
## file exists. Pillar 4 plancher (AC-CRD-16) : `BASE_SECRET_CREDIT * 1` doit
## être >= `5 * KILL_CREDIT_GRUNT` pour que le secret tier 1 vaille au moins
## 5 grunts (viscéralité reward).
const BASE_SECRET_CREDIT: int = 5

## Kill credit baseline for a "grunt" enemy archetype (Tier 2+ knob — will
## move to `data/balance/credit_config.tres`). Used as the reference unit for
## the Pillar 4 ratio plancher (AC-CRD-16). MVP : every kill grants +1 credit
## (story 002), so KILL_CREDIT_GRUNT == 1.
const KILL_CREDIT_GRUNT: int = 1

## Base cost (credits) for the cheapest upgrade (n=0) in the shop catalogue.
## Curve : cost_n = BASE_UPGRADE_COST + TIER_COST_STEP × n  (F-CRD-3 0-based).
## r2 B-2 : lowered 20 → 8 so a combat-only étage 1 (8 kills × 1 cr) reaches
## the first upgrade without secrets (anti soft-lock Pillar 2).
## Tier 2+ knob : will move to `data/balance/credit_config.tres`.
const BASE_UPGRADE_COST: int = 8

## Linear cost increment between consecutive upgrade tiers (F-CRD-3).
## cost_n=1 = 8 + 20 = 28 cr, cost_n=2 = 48 cr, etc.
## Tier 2+ knob : will move to `data/balance/credit_config.tres`.
const TIER_COST_STEP: int = 20

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted SYNC (non-deferred) immediately after state mutation.
## total  : new balance AFTER the change (>= 0).
## delta  : signed amount (+gain / -spend).
## source : which SourceKind triggered the change.
## R-CRD-4, ADR-0001, ADR-0007 D-4.
signal credits_changed(total: int, delta: int, source: SourceKind)

# ---------------------------------------------------------------------------
# State (private — main thread only, ADR-0001)
# ---------------------------------------------------------------------------

## Current credit balance. Never goes below 0 (enforced by try_spend guard).
var _total_credits: int = 0

## True once SaveLoadSystem has hydrated the counter at boot (story 004).
var _is_hydrated: bool = false

## Tracks enemy instance_ids already rewarded this run to enforce idempotence
## (R-CRD-6). Key: instance_id (int), value: true. Cleared on every level_active
## (R-CRD-5 + AC-CRD-49) and on request_new_run (story 005 — GSM ADR-0007).
var _credited_this_run: Dictionary[int, bool] = {}

## Test-observable counter incremented every time try_spend rejects a negative
## amount and emits a push_warning. AC-CRD-06 evidence seam: GUT cannot capture
## push_warning directly, so tests assert this counter to prove the negative
## branch (and its warning) was actually hit. Reset by tests in before_each.
var _negative_amount_warning_count: int = 0

# ---------------------------------------------------------------------------
# Multi-kill batching state (story 002, R-CRD-7)
# ---------------------------------------------------------------------------

## MVP r2 B-1 — when true, multiple `enemy_killed` emits within the same physics
## tick accumulate into a single `credits_changed(N+M, +M, KILL)` flush at end
## of `_physics_process`. Tier 2+ knob : flip to false to restore one emit per
## kill (analytics granular mode). Locked by AC-CRD-08 / AC-CRD-31.
const BATCH_MULTI_KILL_EMIT: bool = true

## Pending batched delta accumulated by `_on_enemy_killed` between physics ticks.
## Reset to 0 at flush.
var _pending_kill_delta: int = 0

## True when at least one kill was credited since the last flush. Decoupled from
## `_pending_kill_delta > 0` so a future caller could legitimately push a 0-delta
## sentinel without ambiguity.
var _has_pending_kill: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Must run while SceneTree is paused so UI/shop can transact on pause screens.
	# Pattern mirrors SaveLoadSystem (ADR-0007 D-1 / ADR-0010 D-4).
	process_mode = PROCESS_MODE_ALWAYS
	# Pillar 4 plancher invariant (AC-CRD-16) — secret tier 1 doit valoir au
	# moins 5 grunts. Si un futur tuning casse ce ratio, le boot crash hard
	# (intentional — protège la conception game feel).
	assert(BASE_SECRET_CREDIT * 1 >= 5 * KILL_CREDIT_GRUNT,
		"AC-CRD-16 violated : BASE_SECRET_CREDIT (%d) * tier1 < 5 * KILL_CREDIT_GRUNT (%d)" \
			% [BASE_SECRET_CREDIT, KILL_CREDIT_GRUNT])
	# GameStateManager autoload is registered BEFORE CreditEconomy in project.godot
	# (idx 20 vs 22) — direct connection safe (D-3 ordre garanti).
	GameStateManager.state_changed.connect(_on_state_changed)
	# LevelSystem autoload is registered AFTER CreditEconomy in project.godot
	# (idx 24 vs 22) — defer the connection so the global identifier resolves.
	_connect_level_active.call_deferred()
	# story-005 : connexion direct car GSM autoload (project.godot ligne 20) est
	# registered AVANT Credit (ligne 22) — cohérent avec connect state_changed
	# ci-dessus. Pas de call_deferred necessaire (vs LevelSystem ligne 24).
	if not GameStateManager.new_run_requested.is_connected(_on_request_new_run):
		GameStateManager.new_run_requested.connect(_on_request_new_run)


## Establish the level_active subscription. Called via call_deferred from
## _ready() to dodge autoload boot ordering (LevelSystem may not yet be
## available when CreditEconomy._ready runs).
func _connect_level_active() -> void:
	if LevelSystem.level_active.is_connected(_on_level_active):
		return
	LevelSystem.level_active.connect(_on_level_active)


# ---------------------------------------------------------------------------
# Per-tick flush — ADR-0001 authority
# ---------------------------------------------------------------------------

## Flushes any pending batched kill delta to a single credits_changed emit.
## Runs every physics tick at the end of CreditEconomy's frame slice.
## Zero-allocation path : reuses member variables, no heap (Pillar 1 hot-path).
func _physics_process(_delta: float) -> void:
	if not _has_pending_kill:
		return
	var delta_to_emit: int = _pending_kill_delta
	_pending_kill_delta = 0
	_has_pending_kill = false
	credits_changed.emit(_total_credits, delta_to_emit, SourceKind.KILL)


# ---------------------------------------------------------------------------
# Signal handlers — Source KILL (story 002, R-CRD-3 / 5 / 6 / 7)
# ---------------------------------------------------------------------------

## Fires on every Level activation (etage entry, R-Lvl-2). Purges the
## per-run idempotence set (AC-CRD-49 d/e — first call no-op, second purges)
## and (re)connects to every node currently in the "enemies" group so kills
## propagate to credit attribution. Connection establishment is decoupled
## from `_is_hydrated` (B-7 — story 004 guards the *received* signal, not the
## connection itself). Resets the pending batch since the previous tick scope
## is invalid post-transition.
func _on_level_active(_etage_id: int, _player_start: Vector3) -> void:
	_credited_this_run.clear()
	_pending_kill_delta = 0
	_has_pending_kill = false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_signal(&"enemy_killed"):
			push_warning("CreditEconomy: node in 'enemies' group has no enemy_killed signal: %s" % enemy)
			continue
		if not enemy.enemy_killed.is_connected(_on_enemy_killed):
			enemy.enemy_killed.connect(_on_enemy_killed)


## Fires on every Enemy.die() that emits enemy_killed. Idempotent per
## instance_id (AC-CRD-09 — defensive against Enemy double-die contournement).
## Increments `_total_credits` immediately (Rule 7 comptable cohérence) ;
## the user-facing emit is batched until the end of _physics_process when
## `BATCH_MULTI_KILL_EMIT == true` (default MVP r2 B-1).
##
## Guards (story 004) :
##   - `_is_hydrated == false` → reject silent (Rule 11 + B-7 race boot AC-CRD-51)
##   - GSM state != PLAYING → reject silent (Rule 10, AC-CRD-36)
##
## Zero-alloc hot path : reuses member variables, no Dictionary literals,
## no String allocations. May fire 60+ Hz under multi-kill bursts.
func _on_enemy_killed(enemy: Node, _position: Vector3) -> void:
	if not _is_hydrated:
		return  # AC-CRD-51 c : pre-hydration kills rejected silent
	if GameStateManager.get_current_state() != GameStateManager.State.PLAYING:
		return  # AC-CRD-36 : non-PLAYING kills (PAUSED, etc.) rejected silent
	var enemy_id: int = enemy.get_instance_id()
	if _credited_this_run.has(enemy_id):
		return  # AC-CRD-09 : silent idempotence guard, no log, no state change.
	_credited_this_run[enemy_id] = true
	_total_credits += 1
	if BATCH_MULTI_KILL_EMIT:
		_pending_kill_delta += 1
		_has_pending_kill = true
	else:
		# Tier 2+ analytics-granular path — emit each kill separately.
		credits_changed.emit(_total_credits, +1, SourceKind.KILL)


# ---------------------------------------------------------------------------
# Signal handlers — Source SECRET (story 003, R-CRD-9 / F-CRD-2 / EC-CRD-9)
# ---------------------------------------------------------------------------

## Fires on every SecretSystem `secret_collected(secret_node, tier)` emit.
## Tier domain : {1, 2, 3} GDD-locked (Secret r1 R-SEC-08). Out-of-domain
## tiers are ignored silently with a push_warning (EC-CRD-9 defensive).
##
## Formula F-CRD-2 : credits = BASE_SECRET_CREDIT × tier (5/10/15 MVP).
## Émission SYNC immédiate — pas de batching MVP (1 secret = 1 emit ; un
## joueur ne collecte pas physiquement 2 secrets dans le même tick 16.6 ms).
##
## Guards (story 004, symétriques à `_on_enemy_killed`) :
##   - `_is_hydrated == false` → reject silent (Rule 11 + B-7 race boot)
##   - GSM state != PLAYING → reject silent (Rule 10)
##
## Idempotence : pas de guard côté Credit — Secret System (R-SEC-08) garantit
## qu'un secret ne peut être collecté qu'une fois (collected_secrets set
## upstream).
func _on_secret_collected(_secret_node: Node, tier: int) -> void:
	if not _is_hydrated:
		return  # pre-hydration secrets rejected silent (B-7 symmetry)
	if GameStateManager.get_current_state() != GameStateManager.State.PLAYING:
		return  # non-PLAYING secrets rejected silent
	if tier < 1 or tier > 3:
		# EC-CRD-9 : tier hors domaine → ignore silencieux + warn pour traçabilité.
		push_warning("Credit Economy: invalid secret tier: %d" % tier)
		return
	var credits: int = BASE_SECRET_CREDIT * tier
	_total_credits += credits
	credits_changed.emit(_total_credits, credits, SourceKind.SECRET)


# ---------------------------------------------------------------------------
# Signal handlers — Persistence (story 004, R-CRD-10/11/12 + EC-CRD-8/11)
# ---------------------------------------------------------------------------

## Observer du GameStateManager.state_changed.
##
## Rule 11 / AC-CRD-24 : premier `state_changed(PLAYING)` reçu → hydrate UNE
## SEULE FOIS via `SaveLoadSystem.load_int("total_credits", 0)`. Transitions
## PLAYING ultérieures (depuis PAUSED, RESPAWNING, etc.) sont no-op (AC-CRD-37/38).
##
## Rule 12 / AC-CRD-23 : tout `state_changed(MENU)` → persist via
## `SaveLoadSystem.save_int("total_credits", _total_credits)` (R-CRD-12, AC-CRD-23).
##
## Autres états (PAUSED, RESPAWNING, BOSS_DEFEATED) : no-op explicite —
## EC-CRD-13 reset/respawn ne touchent pas le compteur (AC-CRD-22/26).
func _on_state_changed(new_state: int) -> void:
	match new_state:
		GameStateManager.State.PLAYING:
			if not _is_hydrated:
				_hydrate_from_save()
				_is_hydrated = true
			# transitions PLAYING ultérieures = no-op (AC-CRD-37/38)
		GameStateManager.State.MENU:
			_persist_to_save()
		_:
			# PAUSED, RESPAWNING, BOSS_DEFEATED — no-op explicite.
			pass


## Hydrate le compteur depuis le savegame. Appelé UNE SEULE FOIS au premier
## `state_changed(PLAYING)` (guard `_is_hydrated == false` upstream). Émet
## `credits_changed(loaded, 0, BOOT_HYDRATE)` exactement 1 fois (AC-CRD-24/30).
##
## EC-CRD-8 : `SaveLoadSystem.load_int` retourne `default=0` si savegame absent
## ou clé corrompue → comportement gracieux, pas de crash.
func _hydrate_from_save() -> void:
	_total_credits = SaveLoadSystem.load_int("total_credits", 0)
	credits_changed.emit(_total_credits, 0, SourceKind.BOOT_HYDRATE)


## Persiste le compteur courant au savegame. Appelé sur chaque
## `state_changed(MENU)` (R-CRD-12). Pas d'émission de signal — la
## persistance est un side-effect silencieux.
func _persist_to_save() -> void:
	SaveLoadSystem.save_int("total_credits", _total_credits)


## Fires when GameStateManager.request_new_run() completes (BOSS_DEFEATED → MENU).
## Purges the per-run idempotence set so a fresh run starts cleanly (R-CRD-6,
## AC-CRD-10). _total_credits is NEVER touched here — credit progression survives
## runs (Pillar 2, ADR-0007 D-8 spirit). Zero-alloc : Dictionary.clear() is O(1).
##
## NB-CRD-4 : ce handler est UNIQUEMENT connecte au signal new_run_requested.
## NE PAS l'appeler depuis _on_state_changed(RESPAWNING/PLAYING) ou un autre
## trigger non-canonique — voir story-005 Control Manifest forbidden patterns.
func _on_request_new_run() -> void:
	_credited_this_run.clear()
	# AC-CRD-10 b : _total_credits intact. Aucune emission credits_changed
	# (le compteur ne change pas, donc pas de notification UI requise).


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the current credit balance. Always >= 0.
func get_total() -> int:
	return _total_credits


## Atomically attempt to spend [amount] credits.
##
## Returns true  and decrements balance when amount <= _total_credits.
## Returns false and leaves state unchanged when balance is insufficient.
##
## Edge cases (R-CRD-4, EC-CRD-1..4):
##   amount == 0  → no-op, returns true, no signal (AC-CRD-05).
##   amount <  0  → push_warning, returns false, no signal (AC-CRD-06).
##   amount >  _total_credits → returns false, no signal (AC-CRD-02).
##
## NO await. NO call_deferred. Emit is SYNC (ADR-0001, AC-CRD-29).
func try_spend(amount: int) -> bool:
	if amount == 0:
		return true  # silent no-op, AC-CRD-05
	if amount < 0:
		_negative_amount_warning_count += 1
		push_warning("Credit Economy: try_spend with negative amount: %d" % amount)
		return false
	if amount > _total_credits:
		return false  # insufficient balance, AC-CRD-02 / AC-CRD-18
	_total_credits -= amount
	credits_changed.emit(_total_credits, -amount, SourceKind.SPEND_SHOP)
	return true
