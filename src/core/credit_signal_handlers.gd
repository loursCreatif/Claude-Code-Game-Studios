## CreditSignalHandlers — Signal handlers extracted from CreditEconomy.
##
## Owns the 7 signal-driven handlers (level_active, enemy_killed,
## secret_collected, state_changed, hydrate_from_save, persist_to_save,
## request_new_run) that were previously inlined in credit_economy.gd.
##
## Pattern : RefCounted with dependency injection — mirrors audio_combat_handler.gd.
## Instanciated in CreditEconomy._ready() and stored as _handlers member.
## Receives a reference to the CreditEconomy Node for state mutation and
## signal emission.
##
## TD-008 SPLIT #2 — extracted 2026-05-12.
## Design document : design/gdd/credit-economy-system.md
## ADR-0001 : state mutations delegated back via _economy reference.
## ADR-0010 : _hydrate_from_save / _persist_to_save call SaveLoadSystem.

# NOTE: pas de class_name — référencé via const preload dans credit_economy.gd
# pour bypass l'absence de class cache en CI (pattern miroir audio_combat_handler.gd).

extends RefCounted


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Reference to the CreditEconomy autoload Node. Injected in CreditEconomy._ready()
## after instantiation. Used to mutate _total_credits, _pending_kill_delta,
## _has_pending_kill, _credited_this_run, _is_hydrated, _negative_amount_warning_count
## and to emit credits_changed.
var _economy: Node = null


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
	_economy._credited_this_run.clear()
	_economy._pending_kill_delta = 0
	_economy._has_pending_kill = false
	for enemy in _economy.get_tree().get_nodes_in_group("enemies"):
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
	if not _economy._is_hydrated:
		return  # AC-CRD-51 c : pre-hydration kills rejected silent
	if GameStateManager.get_current_state() != GameStateManager.State.PLAYING:
		return  # AC-CRD-36 : non-PLAYING kills (PAUSED, etc.) rejected silent
	var enemy_id: int = enemy.get_instance_id()
	if _economy._credited_this_run.has(enemy_id):
		return  # AC-CRD-09 : silent idempotence guard, no log, no state change.
	_economy._credited_this_run[enemy_id] = true
	_economy._total_credits += 1
	if _economy.BATCH_MULTI_KILL_EMIT:
		_economy._pending_kill_delta += 1
		_economy._has_pending_kill = true
	else:
		# Tier 2+ analytics-granular path — emit each kill separately.
		_economy.credits_changed.emit(_economy._total_credits, +1, _economy.SourceKind.KILL)


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
	if not _economy._is_hydrated:
		return  # pre-hydration secrets rejected silent (B-7 symmetry)
	if GameStateManager.get_current_state() != GameStateManager.State.PLAYING:
		return  # non-PLAYING secrets rejected silent
	if tier < 1 or tier > 3:
		# EC-CRD-9 : tier hors domaine → ignore silencieux + warn pour traçabilité.
		push_warning("Credit Economy: invalid secret tier: %d" % tier)
		return
	var credits: int = _economy.BASE_SECRET_CREDIT * tier
	_economy._total_credits += credits
	_economy.credits_changed.emit(_economy._total_credits, credits, _economy.SourceKind.SECRET)


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
			if not _economy._is_hydrated:
				_hydrate_from_save()
				_economy._is_hydrated = true
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
	_economy._total_credits = SaveLoadSystem.load_int("total_credits", 0)
	_economy.credits_changed.emit(_economy._total_credits, 0, _economy.SourceKind.BOOT_HYDRATE)


## Persiste le compteur courant au savegame. Appelé sur chaque
## `state_changed(MENU)` (R-CRD-12). Pas d'émission de signal — la
## persistance est un side-effect silencieux.
func _persist_to_save() -> void:
	SaveLoadSystem.save_int("total_credits", _economy._total_credits)


## Fires when GameStateManager.request_new_run() completes (BOSS_DEFEATED → MENU).
## Purges the per-run idempotence set so a fresh run starts cleanly (R-CRD-6,
## AC-CRD-10). _total_credits is NEVER touched here — credit progression survives
## runs (Pillar 2, ADR-0007 D-8 spirit). Zero-alloc : Dictionary.clear() is O(1).
##
## NB-CRD-4 : ce handler est UNIQUEMENT connecte au signal new_run_requested.
## NE PAS l'appeler depuis _on_state_changed(RESPAWNING/PLAYING) ou un autre
## trigger non-canonique — voir story-005 Control Manifest forbidden patterns.
func _on_request_new_run() -> void:
	_economy._credited_this_run.clear()
	# AC-CRD-10 b : _total_credits intact. Aucune emission credits_changed
	# (le compteur ne change pas, donc pas de notification UI requise).
