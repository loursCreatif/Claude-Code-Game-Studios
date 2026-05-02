# Tests unitaires Story-003 — CombatSystem death/respawn lifecycle full reset.
# Couvre AC-1 (died from Idle), AC-2 (respawn full reset 8 vars), AC-3 (died restore slow-mo),
# AC-4 (grep textuel : aucune connexion CONNECT_DEFERRED sur player.died — AC-CMB-41 clause 8).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Pattern : instancie combat_system.tscn pour disposer du child ShapeCast3D, attache sous un
# CharacterBody3D parent. Aucun état partagé entre tests. Engine.time_scale est restauré en
# after_test() pour éviter la contamination cross-test.
#
# Story   : production/epics/combat-system/story-003-death-respawn-lifecycle-reset.md
# ADR     : ADR-0005 D-5 amendment r2 (SYNC exemption died), ADR-0006 (Combat Tick Model)
# GDD     : design/gdd/player-combat-system.md AC-CMB-11 / AC-CMB-21

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const COMBAT_SOURCE_PATH: String = "res://src/gameplay/combat/combat_system.gd"
const TIME_SCALE_TOLERANCE: float = 0.0001


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## Reset Engine.time_scale après chaque test.
## AC-3 mute time_scale à 0.3 ; un test qui plante avant restore contaminerait les suivants.
func after_test() -> void:
	Engine.time_scale = 1.0


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
# AC-1 — Died from Idle (AC-CMB-11 a)
# ---------------------------------------------------------------------------

## AC-1 : En état IDLE avec slow-mo inactif, _on_player_died() doit transitionner
## vers DEAD, désactiver ShapeCast3D, et laisser Engine.time_scale à 1.0.
func test_combat_died_from_idle_transitions_to_dead_disables_shapecast() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)
	assert_bool(combat._slow_mo_active).is_false()

	var shape_cast: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_object(shape_cast).is_not_null()

	# Act
	combat._on_player_died()

	# Assert — _state DEAD
	assert_int(combat._state) \
		.override_failure_message("AC-1: _state doit être DEAD après _on_player_died()") \
		.is_equal(CombatSystem.State.DEAD)

	# ShapeCast3D désactivé
	assert_bool(shape_cast.enabled) \
		.override_failure_message("AC-1: ShapeCast3D.enabled doit être false en DEAD") \
		.is_false()

	# Engine.time_scale inchangé à 1.0 (slow-mo n'était pas actif)
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-1: Engine.time_scale doit rester à 1.0 quand slow-mo inactif") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)

	combat.get_parent().queue_free()


## AC-1 edge case : died répété (idempotent — déjà DEAD, pas de side-effect indésirable).
func test_combat_died_repeated_in_dead_state_idempotent() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat_from_scene()
	combat._on_player_died()
	assert_int(combat._state).is_equal(CombatSystem.State.DEAD)

	# Act — deuxième died en DEAD
	combat._on_player_died()

	# Assert — état toujours DEAD, pas de mutation parasite
	assert_int(combat._state).is_equal(CombatSystem.State.DEAD)
	var shape_cast: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_bool(shape_cast.enabled).is_false()
	assert_float(Engine.time_scale) \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-2 — Respawn full reset (AC-CMB-11 b — 8 vars + 2 effets externes)
# ---------------------------------------------------------------------------

## AC-2 : En état Combat Dead avec 8 vars muées, _on_player_respawned(Vector3.ZERO)
## doit reset les 8 vars + restore Engine.time_scale=1.0 + désactiver ShapeCast3D.
func test_combat_respawned_resets_all_eight_vars_and_external_effects() -> void:
	# Arrange — état Dead arbitraire avec 8 vars muées
	var combat: CombatSystem = _make_combat_from_scene()
	combat._state = CombatSystem.State.DEAD
	combat._active_tick = 3
	combat._hit_this_swing = [1, 2, 3]
	combat._cooldown_timer = 0.15
	combat._slow_mo_active = true
	combat._slow_mo_start_msec = 1234
	combat._death_pending = true
	combat._buffered_attack = true
	Engine.time_scale = CombatSystem.SLOW_MO_SCALE  # mute externe pour vérifier le restore

	var shape_cast: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	# Force enabled=true pour vérifier qu'il sera bien désactivé par le respawn.
	shape_cast.enabled = true

	# Act
	combat._on_player_respawned(Vector3.ZERO)

	# Assert — 8 vars reset
	# (1) _state == IDLE
	assert_int(combat._state) \
		.override_failure_message("AC-2 (1): _state doit être IDLE") \
		.is_equal(CombatSystem.State.IDLE)
	# (2) _active_tick == 0
	assert_int(combat._active_tick) \
		.override_failure_message("AC-2 (2): _active_tick doit être 0") \
		.is_equal(0)
	# (3) _hit_this_swing.is_empty()
	assert_bool(combat._hit_this_swing.is_empty()) \
		.override_failure_message("AC-2 (3): _hit_this_swing doit être vide") \
		.is_true()
	# (4) _cooldown_timer == 0.0
	assert_float(combat._cooldown_timer) \
		.override_failure_message("AC-2 (4): _cooldown_timer doit être 0.0") \
		.is_equal(0.0)
	# (5) _slow_mo_active == false
	assert_bool(combat._slow_mo_active) \
		.override_failure_message("AC-2 (5): _slow_mo_active doit être false") \
		.is_false()
	# (6) _slow_mo_start_msec == 0
	assert_int(combat._slow_mo_start_msec) \
		.override_failure_message("AC-2 (6): _slow_mo_start_msec doit être 0") \
		.is_equal(0)
	# (7) _death_pending == false
	assert_bool(combat._death_pending) \
		.override_failure_message("AC-2 (7): _death_pending doit être false") \
		.is_false()
	# (8) _buffered_attack == false
	assert_bool(combat._buffered_attack) \
		.override_failure_message("AC-2 (8): _buffered_attack doit être false") \
		.is_false()

	# AND : Engine.time_scale == 1.0 ± 0.0001
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-2: Engine.time_scale doit être restauré à 1.0") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)
	# AND : ShapeCast3D.enabled == false
	assert_bool(shape_cast.enabled) \
		.override_failure_message("AC-2: ShapeCast3D.enabled doit être false") \
		.is_false()

	combat.get_parent().queue_free()


## AC-2 edge case : respawned reçu en IDLE (pas Dead) — comportement = même reset propre.
func test_combat_respawned_in_idle_still_resets_all_state() -> void:
	# Arrange — IDLE avec quelques vars muées (e.g. cooldown actif après attaque)
	var combat: CombatSystem = _make_combat_from_scene()
	combat._cooldown_timer = 0.2
	combat._buffered_attack = true
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)

	# Act
	combat._on_player_respawned(Vector3(1.0, 2.0, 3.0))

	# Assert — même reset propre
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)
	assert_float(combat._cooldown_timer).is_equal(0.0)
	assert_bool(combat._buffered_attack).is_false()

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-3 — Died restore slow-mo (AC-CMB-21)
# ---------------------------------------------------------------------------

## AC-3 : Avec _slow_mo_active=true et Engine.time_scale=0.3, _on_player_died() doit
## restaurer Engine.time_scale à 1.0 AVANT toute autre transition Dead, et clear
## _slow_mo_active = false.
func test_combat_died_during_slow_mo_restores_time_scale_before_dead_transition() -> void:
	# Arrange — slow-mo actif, time_scale muté, état IDLE
	var combat: CombatSystem = _make_combat_from_scene()
	combat._slow_mo_active = true
	combat._slow_mo_start_msec = 5678
	Engine.time_scale = CombatSystem.SLOW_MO_SCALE
	assert_float(Engine.time_scale) \
		.is_between(0.3 - TIME_SCALE_TOLERANCE, 0.3 + TIME_SCALE_TOLERANCE)

	# Act
	combat._on_player_died()

	# Assert — Engine.time_scale restauré à 1.0
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-3: Engine.time_scale doit être restauré à 1.0") \
		.is_between(1.0 - TIME_SCALE_TOLERANCE, 1.0 + TIME_SCALE_TOLERANCE)

	# _slow_mo_active = false
	assert_bool(combat._slow_mo_active) \
		.override_failure_message("AC-3: _slow_mo_active doit être false après restore") \
		.is_false()

	# _slow_mo_start_msec = 0
	assert_int(combat._slow_mo_start_msec) \
		.override_failure_message("AC-3: _slow_mo_start_msec doit être 0 après restore") \
		.is_equal(0)

	# _state = DEAD (post-restore)
	assert_int(combat._state) \
		.override_failure_message("AC-3: _state doit être DEAD après transition Dead") \
		.is_equal(CombatSystem.State.DEAD)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-4 — Grep textuel : connexion mode SYNC sur player.died (AC-CMB-41 clause 8)
# ---------------------------------------------------------------------------

## AC-4 : Vérifie qu'aucune connexion sur player.died n'utilise CONNECT_DEFERRED
## dans combat_system.gd. Lecture du source via FileAccess + regex line-based.
##
## Pattern recherché : `player\.died\.connect.*CONNECT_DEFERRED` — zéro match attendu.
## Les commentaires (lignes commençant par `#`) sont exclus du match strict via
## scan ligne-par-ligne (le pattern doit être dans une ligne de code).
func test_combat_source_no_connect_deferred_on_player_died() -> void:
	# Arrange — lire le source CombatSystem
	var file: FileAccess = FileAccess.open(COMBAT_SOURCE_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("AC-4: combat_system.gd doit être lisible via FileAccess") \
		.is_not_null()
	var source: String = file.get_as_text()
	file.close()

	# Act — scan ligne-par-ligne, exclure les commentaires (ligne stripée commençant par #).
	var regex: RegEx = RegEx.new()
	var compile_status: int = regex.compile("(died|respawned)\\.connect.*CONNECT_DEFERRED")
	assert_int(compile_status) \
		.override_failure_message("AC-4: regex doit compiler") \
		.is_equal(OK)

	var violations: Array[String] = []
	var lines: PackedStringArray = source.split("\n")
	for i: int in range(lines.size()):
		var line: String = lines[i]
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue  # commentaire — exempté
		if regex.search(line) != null:
			violations.append("L%d: %s" % [i + 1, line])

	# Assert — aucune violation
	assert_int(violations.size()) \
		.override_failure_message(
			"AC-4: connexion CONNECT_DEFERRED interdite sur player.died/respawned (clause 8). " +
			"Violations : %s" % str(violations)
		) \
		.is_equal(0)
