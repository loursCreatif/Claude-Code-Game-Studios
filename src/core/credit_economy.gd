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
##
## TD-008 SPLIT #2 : signal handlers extracted to credit_signal_handlers.gd.
## Proxy methods _on_enemy_killed / _on_state_changed etc. delegate to _handlers
## for test seam compatibility (pattern audio_system.gd).

extends Node

# NOTE : pas de class_name — évite collision avec l'identifiant autoload Godot.

const _CreditSignalHandlers := preload("res://src/core/credit_signal_handlers.gd")


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
# Handler module (TD-008 split)
# ---------------------------------------------------------------------------

var _handlers: RefCounted = null


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
	# Instantiate signal handler module and inject self reference.
	_handlers = _CreditSignalHandlers.new()
	_handlers._economy = self
	# GameStateManager autoload is registered BEFORE CreditEconomy in project.godot
	# (idx 20 vs 22) — direct connection safe (D-3 ordre garanti).
	GameStateManager.state_changed.connect(_handlers._on_state_changed)
	# LevelSystem autoload is registered AFTER CreditEconomy in project.godot
	# (idx 24 vs 22) — defer the connection so the global identifier resolves.
	_connect_level_active.call_deferred()
	# story-005 : connexion direct car GSM autoload (project.godot ligne 20) est
	# registered AVANT Credit (ligne 22) — cohérent avec connect state_changed
	# ci-dessus. Pas de call_deferred necessaire (vs LevelSystem ligne 24).
	if not GameStateManager.new_run_requested.is_connected(_handlers._on_request_new_run):
		GameStateManager.new_run_requested.connect(_handlers._on_request_new_run)


## Establish the level_active subscription. Called via call_deferred from
## _ready() to dodge autoload boot ordering (LevelSystem may not yet be
## available when CreditEconomy._ready runs).
func _connect_level_active() -> void:
	if LevelSystem.level_active.is_connected(_handlers._on_level_active):
		return
	LevelSystem.level_active.connect(_handlers._on_level_active)


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
# Proxy methods — test seam compatibility (pattern audio_system.gd)
# ---------------------------------------------------------------------------

## Proxy → CreditSignalHandlers._on_level_active.
## Preserved for direct GdUnit4 test calls (tests/unit/credit_economy/).
func _on_level_active(etage_id: int, player_start: Vector3) -> void:
	_handlers._on_level_active(etage_id, player_start)


## Proxy → CreditSignalHandlers._on_enemy_killed.
## Preserved for direct GdUnit4 test calls (tests/unit/credit_economy/).
func _on_enemy_killed(enemy: Node, position: Vector3) -> void:
	_handlers._on_enemy_killed(enemy, position)


## Proxy → CreditSignalHandlers._on_secret_collected.
## Preserved for direct GdUnit4 test calls (tests/unit/credit_economy/).
func _on_secret_collected(secret_node: Node, tier: int) -> void:
	_handlers._on_secret_collected(secret_node, tier)


## Proxy → CreditSignalHandlers._on_state_changed.
## Preserved for direct GdUnit4 test calls (tests/unit/credit_economy/).
func _on_state_changed(new_state: int) -> void:
	_handlers._on_state_changed(new_state)


## Proxy → CreditSignalHandlers._on_request_new_run.
## Preserved for direct GdUnit4 test calls (tests/unit/credit_economy/).
func _on_request_new_run() -> void:
	_handlers._on_request_new_run()


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
