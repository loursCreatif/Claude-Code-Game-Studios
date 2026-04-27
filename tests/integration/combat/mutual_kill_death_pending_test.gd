# Tests integration Story-014 — CombatSystem mutual kill Hybrid M1 Option C `_death_pending`.
#
# Couvre AC-1 à AC-3 (cf. story-014) + AC-CMB-20/41 + Rule 17 :
#   AC-1 : died reçu mid-swing → drain DIFFÉRÉ à fin _physics_process (state DEAD post-tick).
#   AC-2 : grep CONNECT_DEFERRED interdite (couvert par story-003 test, re-asserted ici).
#   AC-3 : died reçu en SWINGING sans collider → AC-CMB-20 (state DEAD, swing_ended NON émis,
#          ShapeCast disabled, Engine.time_scale=1.0, _death_pending=false post-drain).
#   AC-4 : died reçu en IDLE → drain IMMÉDIAT (story-003 path préservé).
#
# Pattern hybride :
#   - State IDLE/AIRBORNE → handler `_on_player_died` drain immédiatement (story-003 AC).
#   - State SWINGING → handler set `_death_pending=true` ; drain à end-of-tick (story-014 AC).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-014-mutual-kill-hybrid-death-pending.md
# ADR     : ADR-0006 D-2 (Hybrid M1 Option C), ADR-0005 D-5 amendment r2 (SYNC died)
# GDD     : design/gdd/player-combat-system.md AC-CMB-20/41 + Rule 17

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const DELTA_60HZ: float = 1.0 / 60.0
const TIME_SCALE_TOLERANCE: float = 0.0001


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func after_test() -> void:
	Engine.time_scale = 1.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_combat() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)
	return combat


# ---------------------------------------------------------------------------
# AC-1 — died mid-swing → drain DIFFÉRÉ à fin _physics_process
# ---------------------------------------------------------------------------

## AC-1 : Combat SWINGING + _on_player_died → handler set _death_pending=true,
## state reste SWINGING ; après _physics_process, state == DEAD.
func test_combat_died_during_swinging_defers_drain_to_end_of_tick() -> void:
	var combat: CombatSystem = _make_combat()

	# Démarrer un swing manuellement (test seam)
	combat.attacked()
	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)
	assert_bool(combat._death_pending).is_false()

	# Act — handler died (signal SYNC, exécuté immédiatement)
	combat._on_player_died()

	# Assert APRÈS handler — state encore SWINGING, _death_pending=true
	assert_int(combat._state) \
		.override_failure_message(
			"AC-1: handler ne doit PAS muter _state si SWINGING — Rule 17 Hybrid"
		) \
		.is_equal(CombatSystem.State.SWINGING)
	assert_bool(combat._death_pending) \
		.override_failure_message("AC-1: handler doit set _death_pending=true") \
		.is_true()

	# Act — 1 tick _physics_process : drain end-of-tick
	combat._physics_process(DELTA_60HZ)

	# Assert APRÈS tick — state DEAD, _death_pending consommé
	assert_int(combat._state) \
		.override_failure_message("AC-1: après _physics_process, state doit être DEAD") \
		.is_equal(CombatSystem.State.DEAD)
	assert_bool(combat._death_pending) \
		.override_failure_message("AC-1: _death_pending doit être consommé (false) post-drain") \
		.is_false()
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_bool(sc.enabled) \
		.override_failure_message("AC-1: ShapeCast3D doit être disabled post-drain") \
		.is_false()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-3 — AC-CMB-20 : died sans collider en SWINGING
# ---------------------------------------------------------------------------

## AC-CMB-20 : Combat SWINGING à _active_tick=3, sweep vide, died reçu →
## post-tick : state==DEAD, swing_ended NON émis, ShapeCast disabled, time_scale=1.0,
## _death_pending=false.
func test_combat_died_swinging_without_collider_clean_drain() -> void:
	var combat: CombatSystem = _make_combat()

	# Démarrer swing puis 3 ticks
	combat.attacked()
	for _i: int in range(3):
		combat._physics_process(DELTA_60HZ)
	assert_int(combat._active_tick).is_equal(3)

	# Setup capture swing_ended
	var swing_ended_count: int = 0
	combat.swing_ended.connect(func() -> void: swing_ended_count += 1)

	# Act — died mid-swing
	combat._on_player_died()
	combat._physics_process(DELTA_60HZ)

	# Assert AC-CMB-20
	assert_int(combat._state).is_equal(CombatSystem.State.DEAD)
	assert_int(swing_ended_count) \
		.override_failure_message("AC-CMB-20: swing_ended NE doit PAS être émis sur died") \
		.is_equal(0)
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_bool(sc.enabled).is_false()
	assert_float(Engine.time_scale) \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)
	assert_bool(combat._death_pending).is_false()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-4 — died en IDLE → drain IMMÉDIAT (story-003 path préservé)
# ---------------------------------------------------------------------------

## AC-4 : Combat IDLE + _on_player_died → drain immédiat (state DEAD avant tick).
## Préserve la sémantique story-003 AC-CMB-11 (a).
func test_combat_died_in_idle_drains_immediately() -> void:
	var combat: CombatSystem = _make_combat()
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)

	# Act
	combat._on_player_died()

	# Assert — drain immédiat (state DEAD avant tout tick)
	assert_int(combat._state) \
		.override_failure_message(
			"AC-4: died en IDLE doit drain immédiatement (story-003 path)"
		) \
		.is_equal(CombatSystem.State.DEAD)
	assert_bool(combat._death_pending) \
		.override_failure_message("AC-4: _death_pending doit être consommé immédiatement") \
		.is_false()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC : died restore slow-mo en cas SWINGING (combine story-013 + 014)
# ---------------------------------------------------------------------------

## Slow-mo actif + died en SWINGING → drain end-of-tick restore time_scale=1.0.
func test_combat_died_swinging_with_active_slow_mo_restores_time_scale_at_drain() -> void:
	var combat: CombatSystem = _make_combat()

	# Setup : SWINGING + slow-mo actif (manuel)
	combat.attacked()
	combat._slow_mo_active = true
	combat._slow_mo_start_msec = 999999  # large pour bloquer auto-restore via wall-clock
	Engine.time_scale = CombatSystem.SLOW_MO_SCALE

	# Act — died mid-swing puis tick
	combat._on_player_died()
	# Override _get_time_msec pour empêcher le check_slow_mo_restore de restaurer
	# avant le drain (on veut que le drain fasse le restore).
	combat._get_time_msec = Callable(self, "_time_zero")
	combat._physics_process(DELTA_60HZ)

	# Assert
	assert_int(combat._state).is_equal(CombatSystem.State.DEAD)
	assert_float(Engine.time_scale) \
		.override_failure_message("Drain doit restore time_scale=1.0 si _slow_mo_active") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)
	assert_bool(combat._slow_mo_active).is_false()

	combat.get_parent().queue_free()


## Mock helper retournant 0 — empêche `elapsed >= 50` côté `_check_slow_mo_restore`
## (avec _slow_mo_start_msec = 999999, elapsed = 0 - 999999 = -999999 < 50).
func _time_zero() -> int:
	return 0
