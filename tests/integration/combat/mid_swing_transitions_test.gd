# Tests integration Story-015 — Mid-swing state transitions + race Idle mitigation.
#
# Couvre AC-1 à AC-4 (cf. story-015) + AC-CMB-28/29/50 + Rule 8 :
#   AC-1 : Combat agnostic des states Movement (Grounded/Airborne/Dashing/WallRun) — vérifié
#          par grep statique (Combat ne branche pas sur player.state hors race mitigation).
#   AC-2 : race mitigation IDLE+player.DEAD → Combat force DEAD.
#   AC-3 : pause spam — Movement responsibility, Combat passive.
#   AC-4 : grep textual — UNE seule lecture player.state autorisée (mitigation).
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-015-mid-swing-transitions-race-idle.md
# ADR     : ADR-0006 (Combat Tick Model), ADR-0004 (Input pause)
# GDD     : design/gdd/player-combat-system.md AC-CMB-28/29/50

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const COMBAT_SOURCE_PATH: String = "res://src/gameplay/combat/combat_system.gd"
const PLAYER_SCENE_PATH: String = "res://src/gameplay/player/Player.tscn"
const DELTA_60HZ: float = 1.0 / 60.0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_player_scene() -> Node:
	"""Instancie Player.tscn complet (Movement + Camera + Combat enfant)."""
	var packed: PackedScene = load(PLAYER_SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var player: Node = packed.instantiate()
	add_child(player)
	return player


# ---------------------------------------------------------------------------
# AC-2 — Race mitigation : Combat IDLE + player.state == DEAD → Combat DEAD
# ---------------------------------------------------------------------------

## AC-CMB-28 : si Player.state == DEAD sans signal `died` reçu (race théorique),
## Combat doit détecter à l'entrée de _physics_process et force _state = DEAD.
func test_combat_race_mitigation_forces_dead_when_player_dead_without_signal() -> void:
	var player: Node = _make_player_scene()
	var combat: CombatSystem = player.get_node_or_null("CombatSystem") as CombatSystem
	assert_object(combat).is_not_null()
	assert_int(combat._state).is_equal(CombatSystem.State.IDLE)

	# Mute Player.state = DEAD sans appeler die() (skip signal — race synthétique)
	var movement: MovementController = player as MovementController
	movement.set("_state", MovementController.State.DEAD)

	# Act
	combat._physics_process(DELTA_60HZ)

	# Assert
	assert_int(combat._state) \
		.override_failure_message(
			"AC-CMB-28: race mitigation doit force Combat.DEAD quand Player.DEAD sans signal"
		) \
		.is_equal(CombatSystem.State.DEAD)
	var sc: ShapeCast3D = combat.get_node_or_null("ShapeCast3D") as ShapeCast3D
	assert_bool(sc.enabled).is_false()

	player.queue_free()


## AC-CMB-28 r2 : restriction — race mitigation NE s'applique PAS si SWINGING.
## Le mécanisme `_death_pending` (story 014) gouverne ce cas.
func test_combat_race_mitigation_does_not_override_swinging() -> void:
	var player: Node = _make_player_scene()
	var combat: CombatSystem = player.get_node_or_null("CombatSystem") as CombatSystem

	# Démarrer un swing
	combat.attacked()
	assert_int(combat._state).is_equal(CombatSystem.State.SWINGING)

	# Player passe à DEAD sans signal
	var movement: MovementController = player as MovementController
	movement.set("_state", MovementController.State.DEAD)

	# Act
	combat._physics_process(DELTA_60HZ)

	# Assert — Combat reste SWINGING (mitigation r2 restriction)
	assert_int(combat._state) \
		.override_failure_message(
			"AC-CMB-28 r2: race mitigation NE doit PAS écraser SWINGING (mécanisme _death_pending gouverne)"
		) \
		.is_equal(CombatSystem.State.SWINGING)

	player.queue_free()


# ---------------------------------------------------------------------------
# AC-4 — Grep textual : aucun branching sur player.state (sauf mitigation)
# ---------------------------------------------------------------------------

## AC-4 : `match player.state` ou `player.state == X` (autres que mitigation IDLE+DEAD).
## La mitigation race produit 1 match autorisé.
func test_combat_source_no_player_state_branching_except_race_mitigation() -> void:
	var file: FileAccess = FileAccess.open(COMBAT_SOURCE_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	# Pattern : `match player.state` ou `player.state == X` ou `.state == MovementController.State`
	var regex: RegEx = RegEx.new()
	regex.compile("\\b(match\\s+(\\w+)\\.state|\\.state\\s*[!=]=\\s*MovementController\\.State)")

	var matches: Array[String] = []
	for i: int in range(lines.size()):
		var line: String = lines[i]
		if line.strip_edges().begins_with("#"):
			continue
		if regex.search(line) != null:
			matches.append("L%d: %s" % [i + 1, line])

	# Au plus 1 match autorisé (la mitigation race ligne unique).
	assert_int(matches.size()) \
		.override_failure_message(
			"AC-4: max 1 match player.state (mitigation race uniquement). Matches : %s"
			% str(matches)
		) \
		.is_less_equal(1)
