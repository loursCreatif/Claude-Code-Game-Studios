# Tests unitaires Story-002 — CombatSystem state machine Idle/Swinging/Dead + cooldown + active_tick.
# Couvre AC-CMB-01, AC-CMB-02, AC-CMB-03, AC-CMB-04 + vérification constante ACTIVE_TICKS.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Chaque test instancie la scène combat_system.tscn pour disposer du child ShapeCast3D.
# Aucun état partagé entre tests.
#
# Story   : production/epics/combat-system/story-002-state-machine-cooldown-active-tick.md
# ADR     : ADR-0001 (60 Hz physics), ADR-0006 D-3 (physics_process only)
# GDD     : design/gdd/player-combat-system.md §G

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const DELTA_60HZ: float = 1.0 / 60.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Instancie combat_system.tscn, l'attache sous un CharacterBody3D dans le tree.
## Retourne le CombatSystem prêt (_ready() déclenché).
func _make_combat_from_scene() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()

	var combat: CombatSystem = packed.instantiate() as CombatSystem
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	player.add_child(combat)
	return combat


# ---------------------------------------------------------------------------
# AC-CMB-01 — IDLE + cooldown=0 + attacked() → SWINGING
# ---------------------------------------------------------------------------

## AC-CMB-01 : En état IDLE avec cooldown à zéro, appeler attacked() doit
## transitionner immédiatement vers SWINGING, armer le cooldown, et activer ShapeCast3D.
func test_combat_attacked_in_idle_with_cooldown_zero_transitions_to_swinging() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	# Vérifier préconditions
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)
	assert_float(combat._cooldown_timer).is_equal(0.0)

	# Act
	combat.attacked()

	# Assert — après attacked(), avant tout tick physics :
	# _state == SWINGING
	assert_int(combat._state) \
		.override_failure_message("AC-CMB-01: _state doit être SWINGING après attacked()") \
		.is_equal(CombatSystem.State.SWINGING)

	# _active_tick == 0 (incrémenté seulement au premier tick physics)
	assert_int(combat._active_tick) \
		.override_failure_message("AC-CMB-01: _active_tick doit être 0 immédiatement après attacked()") \
		.is_equal(0)

	# _cooldown_timer armé à ATTACK_COOLDOWN_MS / 1000
	var expected_cooldown: float = CombatSystem.ATTACK_COOLDOWN_MS / 1000.0
	assert_float(combat._cooldown_timer) \
		.override_failure_message("AC-CMB-01: _cooldown_timer doit être ~0.4 après attacked()") \
		.is_between(expected_cooldown - 0.001, expected_cooldown + 0.001)

	# ShapeCast3D activé
	var shape_cast: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_bool(shape_cast.enabled) \
		.override_failure_message("AC-CMB-01: ShapeCast3D.enabled doit être true après attacked()") \
		.is_true()

	# Simuler un tick physics pour vérifier l'incrément de _active_tick
	combat._physics_process(DELTA_60HZ)
	assert_int(combat._active_tick) \
		.override_failure_message("AC-CMB-01: _active_tick doit être 1 après le premier tick physics") \
		.is_equal(1)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-CMB-02 — IDLE + cooldown > 0 + attacked() → no-op
# ---------------------------------------------------------------------------

## AC-CMB-02 : En état IDLE avec cooldown actif, appeler attacked() ne doit
## pas modifier l'état ni le cooldown.
func test_combat_attacked_in_idle_with_cooldown_active_no_transition() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	combat._cooldown_timer = 0.1
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)

	# Act
	combat.attacked()

	# Assert — état IDLE inchangé
	assert_int(combat._state) \
		.override_failure_message("AC-CMB-02: _state doit rester IDLE avec cooldown actif") \
		.is_equal(CombatSystem.State.IDLE)

	# cooldown inchangé par attacked() (non décrémenté — aucun tick physics appelé)
	assert_float(combat._cooldown_timer) \
		.override_failure_message("AC-CMB-02: _cooldown_timer ne doit pas changer lors d'un attacked() bloqué") \
		.is_greater(0.0)

	combat.get_parent().queue_free()


## AC-CMB-02 variante : En état SWINGING, appeler attacked() ne doit pas
## réinitialiser la swing en cours.
func test_combat_attacked_while_swinging_is_ignored() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	combat.attacked()
	# Un tick pour incrémenter _active_tick à 1
	combat._physics_process(DELTA_60HZ)
	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)
	var tick_before: int = combat._active_tick

	# Act — deuxième attaque pendant la swing
	combat.attacked()

	# Assert — _active_tick non remis à zéro, état toujours SWINGING
	assert_int(combat._state) \
		.override_failure_message("AC-CMB-02b: _state doit rester SWINGING") \
		.is_equal(CombatSystem.State.SWINGING)
	assert_int(combat._active_tick) \
		.override_failure_message("AC-CMB-02b: _active_tick ne doit pas être remis à zéro") \
		.is_equal(tick_before)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-CMB-03 — DEAD + attacked() → no-op
# ---------------------------------------------------------------------------

## AC-CMB-03 : En état DEAD, appeler attacked() ne doit rien faire.
func test_combat_attacked_in_dead_state_ignored() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	combat._state = CombatSystem.State.DEAD

	var shape_cast: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	# S'assurer que ShapeCast3D est bien désactivé en DEAD
	assert_bool(shape_cast.enabled) \
		.override_failure_message("AC-CMB-03 précondition: ShapeCast3D.enabled doit être false en DEAD") \
		.is_false()

	# Act
	combat.attacked()

	# Assert — état DEAD inchangé
	assert_int(combat._state) \
		.override_failure_message("AC-CMB-03: _state doit rester DEAD après attacked()") \
		.is_equal(CombatSystem.State.DEAD)

	# ShapeCast3D toujours désactivé
	assert_bool(shape_cast.enabled) \
		.override_failure_message("AC-CMB-03: ShapeCast3D.enabled doit rester false en DEAD") \
		.is_false()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-CMB-04 — SWINGING tick 7 → tick suivant IDLE + swing_ended émis
# ---------------------------------------------------------------------------

## AC-CMB-04 : À _active_tick == 7, le prochain tick physics doit transitionner
## vers IDLE, remettre _active_tick à zéro, vider _hit_this_swing,
## désactiver ShapeCast3D, et émettre swing_ended exactement une fois.
func test_combat_swinging_tick_seven_transitions_to_idle_emits_swing_ended() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	combat.attacked()
	# Simuler 7 ticks — _active_tick sera à 7 après ces ticks
	for _i: int in range(7):
		combat._physics_process(DELTA_60HZ)

	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)
	assert_int(combat._active_tick) \
		.override_failure_message("AC-CMB-04 précondition: _active_tick doit être 7 avant le tick final") \
		.is_equal(7)

	# Capturer le signal swing_ended via un compteur — GDScript lambda capture-by-value
	# requiert un Array container (Array est passé par référence), pas un int local.
	var swing_ended_count: Array[int] = [0]
	combat.swing_ended.connect(func() -> void: swing_ended_count[0] += 1)

	var shape_cast: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D

	# Act — 8e tick : _active_tick passe de 7 à 8, >= ACTIVE_TICKS (8) → IDLE
	combat._physics_process(DELTA_60HZ)

	# Assert — transition vers IDLE
	assert_int(combat._state) \
		.override_failure_message("AC-CMB-04: _state doit être IDLE après le 8e tick") \
		.is_equal(CombatSystem.State.IDLE)

	# _active_tick remis à zéro
	assert_int(combat._active_tick) \
		.override_failure_message("AC-CMB-04: _active_tick doit être 0 après transition IDLE") \
		.is_equal(0)

	# _hit_this_swing vidé
	assert_bool(combat._hit_this_swing.is_empty()) \
		.override_failure_message("AC-CMB-04: _hit_this_swing doit être vide après transition IDLE") \
		.is_true()

	# ShapeCast3D désactivé
	assert_bool(shape_cast.enabled) \
		.override_failure_message("AC-CMB-04: ShapeCast3D.enabled doit être false après transition IDLE") \
		.is_false()

	# swing_ended émis exactement une fois
	assert_int(swing_ended_count[0]) \
		.override_failure_message("AC-CMB-04: swing_ended doit être émis exactement 1 fois") \
		.is_equal(1)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# Constante ACTIVE_TICKS == 8
# ---------------------------------------------------------------------------

## Vérifie que ACTIVE_TICKS vaut bien 8 (ceil(120 / 16.666…) = ceil(7.2) = 8).
## Régression : toute modification de SWING_DURATION_MS doit être répercutée ici.
func test_combat_active_ticks_constant_equals_eight() -> void:
	assert_int(CombatSystem.ACTIVE_TICKS) \
		.override_failure_message(
			"ACTIVE_TICKS doit être 8 (ceil(120ms / 16.666ms) = ceil(7.2) = 8)"
		) \
		.is_equal(8)
