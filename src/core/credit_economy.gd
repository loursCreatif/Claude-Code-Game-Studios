## CreditEconomy — Autoload singleton for the Credit Economy system.
##
## Owns the single authoritative credit counter (_total_credits).
## Implements R-CRD-1 (unique non-negative int counter), R-CRD-4 (atomic
## try_spend sink), and R-CRD-13 (SourceKind enum).
##
## Design document : design/gdd/credit-economy-system.md
## ADR-0001 : _physics_process is the sole authority for state mutation.
## ADR-0007 : autoload Node singleton pattern, process_mode ALWAYS.
## Story    : production/epics/credit-economy-system/story-001-autoload-skeleton-try-spend.md
##
## NO class_name declaration — would collide with the autoload identifier
## (see feedback memory feedback_godot_class_name_autoload_collision).
##
## Out of scope (story 001) : enemy_killed / secret_collected / state_changed
## handlers, persistence, run-purge, performance benchmark, static lint tests.

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
## (story 002). Key: instance_id (int), value: true.
var _credited_this_run: Dictionary[int, bool] = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Must run while SceneTree is paused so UI/shop can transact on pause screens.
	# Pattern mirrors SaveLoadSystem (ADR-0007 D-1 / ADR-0010 D-4).
	process_mode = PROCESS_MODE_ALWAYS

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
		push_warning("Credit Economy: try_spend with negative amount: %d" % amount)
		return false
	if amount > _total_credits:
		return false  # insufficient balance, AC-CRD-02 / AC-CRD-18
	_total_credits -= amount
	credits_changed.emit(_total_credits, -amount, SourceKind.SPEND_SHOP)
	return true
