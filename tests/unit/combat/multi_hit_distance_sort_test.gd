# Tests unitaires Story-012 — Multi-hit + tri distance + signal multi_kill.
#
# Couvre AC-CMB-07/25 + AC-1 à AC-4 (cf. story-012) :
#   AC-CMB-07 : 4 enemies ≥ MAX → top-MAX par distance ascending tués, 4e skipped, multi_kill émis.
#   AC-CMB-25 : 2 enemies tués même tick → slow-mo idempotent (1× set), multi_kill(2) émis.
#   AC-1 : Distance sort + cap MAX_KILLS_PER_SWING.
#   AC-2 : Multi-kill 2 → slow-mo idempotence.
#   AC-3 : Cap exact à MAX.
#   AC-4 : Sort by distance squared (ordre déterministe).
#   Bonus : 1 kill seul → multi_kill PAS émis (count < 2).
#   Bonus : 0 kill (que des is_dead skip) → multi_kill PAS émis (count == 0).
#
# Approche : test isolé sur `_resolve_kills(hit_ids)` avec MockEnemy positionnés
# à des positions distinctes du Player (combat parent CharacterBody3D = origine).
# Pas de physics query — `_collect_swing_hits` testé en story-009 unit + 018 soak.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-012-multi-hit-distance-sort-max-kills.md
# ADR     : ADR-0006 D-3 + Formula 6 (distance squared zéro-sqrt)

extends GdUnitTestSuite

const AutoloadResetHelper := preload("res://tests/helpers/autoload_reset_helper.gd")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const MockEnemyScript: GDScript = preload("res://tests/unit/combat/mock_enemy.gd")

var _autoload_snap: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func before_test() -> void:
	# Defense-in-depth — reset time_scale AVANT snapshot pour neutraliser pollution
	# cross-suite (pattern miroir commit 4228597 sur death_respawn_lifecycle_test).
	Engine.time_scale = 1.0
	_autoload_snap = AutoloadResetHelper.snapshot(get_tree())


func after_test() -> void:
	AutoloadResetHelper.restore(get_tree(), _autoload_snap)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Renvoie un (combat, player) — combat est child Node3D, player est parent
## CharacterBody3D à l'origine (0,0,0) pour servir de référence distance.
func _make_combat_with_player() -> Array:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	player.global_position = Vector3.ZERO
	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)
	return [combat, player]


## Renvoie un MockEnemy positionné à `pos` global (frame parent direct).
func _make_mock_enemy_at(pos: Vector3) -> StaticBody3D:
	var enemy: StaticBody3D = MockEnemyScript.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	enemy.add_child(shape)
	add_child(enemy)
	enemy.global_position = pos
	return enemy


# ---------------------------------------------------------------------------
# AC-CMB-07 / AC-1 — 4 enemies, top-MAX par distance ascending tués
# ---------------------------------------------------------------------------

func test_combat_multi_hit_sorts_by_distance_caps_at_max_kills() -> void:
	# Arrange : (MAX_KILLS + 1) enemies à distances ascending strict.
	# Mais ordre d'insertion DANS hit_ids = descending pour vérifier le tri.
	var co: Array = _make_combat_with_player()
	var combat: CombatSystem = co[0]
	var max: int = CombatSystem.MAX_KILLS_PER_SWING

	# Distances [0.3, 0.8, 1.2, 1.5, 1.7, 1.9, 2.5] m (axe X) — top-6 = indices 0..5.
	# Construire MAX+1 enemies (= 7 si MAX=6).
	var distances: Array[float] = []
	for i in max + 1:
		distances.append(0.3 + float(i) * 0.4)

	var enemies: Array[StaticBody3D] = []
	var ids_descending: Array[int] = []
	for i in distances.size():
		var e: StaticBody3D = _make_mock_enemy_at(Vector3(distances[i], 0.0, 0.0))
		enemies.append(e)
	# Insérer ids dans l'ordre INVERSE pour vérifier que le tri agit.
	for i in range(distances.size() - 1, -1, -1):
		ids_descending.append(enemies[i].get_instance_id())

	# Connect multi_kill signal pour vérifier émission post-die().
	var multi_count_received: Array[int] = [0]
	combat.multi_kill.connect(func(count: int) -> void: multi_count_received[0] = count)

	# Act
	combat._resolve_kills(ids_descending)

	# Assert : top-MAX (indices 0..MAX-1, distances ascending) tués.
	for i in max:
		assert_int(enemies[i].get("_die_count")) \
			.override_failure_message(
				"AC-CMB-07 : enemy[%d] dist=%.1f doit être tué (top-MAX)" \
				% [i, distances[i]]
			) \
			.is_equal(1)
	# (MAX+1)e enemy NON tué.
	assert_int(enemies[max].get("_die_count")) \
		.override_failure_message(
			"AC-CMB-07 : enemy[%d] dist=%.1f NE doit PAS être tué (au-delà cap)" \
			% [max, distances[max]]
		) \
		.is_equal(0)
	# multi_kill émis avec count = MAX.
	assert_int(multi_count_received[0]) \
		.override_failure_message("AC-CMB-07 : multi_kill(%d) attendu, reçu %d" \
			% [max, multi_count_received[0]]) \
		.is_equal(max)


# ---------------------------------------------------------------------------
# AC-CMB-25 / AC-2 — Multi-kill 2 → slow-mo idempotent
# ---------------------------------------------------------------------------

func test_combat_multi_kill_two_enemies_slow_mo_idempotent() -> void:
	# Arrange
	var co: Array = _make_combat_with_player()
	var combat: CombatSystem = co[0]
	combat._reduce_motion_disable_slow_mo = false
	combat._reduce_motion_slow_mo_scale_mult = 1.0
	combat._get_time_msec = func() -> int: return 12345
	var initial_time_scale: float = Engine.time_scale

	var e1: StaticBody3D = _make_mock_enemy_at(Vector3(0.5, 0.0, 0.0))
	var e2: StaticBody3D = _make_mock_enemy_at(Vector3(1.0, 0.0, 0.0))

	var multi_count_received: Array[int] = [0]
	combat.multi_kill.connect(func(count: int) -> void: multi_count_received[0] = count)

	# Act
	combat._resolve_kills([e1.get_instance_id(), e2.get_instance_id()])

	# Assert
	assert_int(e1.get("_die_count")) \
		.override_failure_message("AC-CMB-25 : e1 (0.5 m) tué") \
		.is_equal(1)
	assert_int(e2.get("_die_count")) \
		.override_failure_message("AC-CMB-25 : e2 (1.0 m) tué") \
		.is_equal(1)
	assert_bool(combat._slow_mo_active) \
		.override_failure_message("AC-CMB-25 : slow-mo activée par 1er kill") \
		.is_true()
	assert_float(Engine.time_scale) \
		.override_failure_message("AC-CMB-25 : time_scale = SLOW_MO_SCALE (idempotent — pas re-set par 2e kill)") \
		.is_equal_approx(CombatSystem.SLOW_MO_SCALE, 0.001)
	assert_int(multi_count_received[0]) \
		.override_failure_message("AC-CMB-25 : multi_kill(2) émis") \
		.is_equal(2)

	Engine.time_scale = initial_time_scale
	combat._slow_mo_active = false


# ---------------------------------------------------------------------------
# AC-4 — Sort by distance squared (ordre déterministe)
# ---------------------------------------------------------------------------

func test_combat_resolve_sorts_by_distance_ascending() -> void:
	# Arrange : enemies à distances [1.5, 0.5, 1.0] insérés dans cet ordre désordonné.
	var co: Array = _make_combat_with_player()
	var combat: CombatSystem = co[0]

	var e_far: StaticBody3D = _make_mock_enemy_at(Vector3(1.5, 0.0, 0.0))
	var e_near: StaticBody3D = _make_mock_enemy_at(Vector3(0.5, 0.0, 0.0))
	var e_mid: StaticBody3D = _make_mock_enemy_at(Vector3(1.0, 0.0, 0.0))

	# Act
	combat._resolve_kills([
		e_far.get_instance_id(),
		e_near.get_instance_id(),
		e_mid.get_instance_id(),
	])

	# Assert : ordre dans _hit_this_swing reflète tri ascending.
	assert_int(combat._hit_this_swing.size()).is_equal(3)
	assert_int(combat._hit_this_swing[0]) \
		.override_failure_message("AC-4 : 1er kill = enemy le plus proche (0.5 m)") \
		.is_equal(e_near.get_instance_id())
	assert_int(combat._hit_this_swing[1]) \
		.override_failure_message("AC-4 : 2e kill = enemy moyen (1.0 m)") \
		.is_equal(e_mid.get_instance_id())
	assert_int(combat._hit_this_swing[2]) \
		.override_failure_message("AC-4 : 3e kill = enemy lointain (1.5 m)") \
		.is_equal(e_far.get_instance_id())


# ---------------------------------------------------------------------------
# Bonus — Single kill : multi_kill PAS émis (count < 2)
# ---------------------------------------------------------------------------

func test_combat_single_kill_does_not_emit_multi_kill() -> void:
	var co: Array = _make_combat_with_player()
	var combat: CombatSystem = co[0]
	var enemy: StaticBody3D = _make_mock_enemy_at(Vector3(0.5, 0.0, 0.0))

	var multi_count_received: Array[int] = [0]
	combat.multi_kill.connect(func(count: int) -> void: multi_count_received[0] = count)

	combat._resolve_kills([enemy.get_instance_id()])

	assert_int(enemy.get("_die_count")).is_equal(1)
	assert_int(multi_count_received[0]) \
		.override_failure_message("Single kill : multi_kill NE doit PAS être émis (count < 2)") \
		.is_equal(0)


# ---------------------------------------------------------------------------
# Bonus — Zero kills (tous skipped) : multi_kill PAS émis
# ---------------------------------------------------------------------------

func test_combat_zero_kills_does_not_emit_multi_kill() -> void:
	var co: Array = _make_combat_with_player()
	var combat: CombatSystem = co[0]
	var dead_enemy: StaticBody3D = _make_mock_enemy_at(Vector3(0.5, 0.0, 0.0))
	dead_enemy.call("die")  # déjà mort tick précédent

	var multi_count_received: Array[int] = [-1]
	combat.multi_kill.connect(func(count: int) -> void: multi_count_received[0] = count)

	combat._resolve_kills([dead_enemy.get_instance_id()])

	assert_int(multi_count_received[0]) \
		.override_failure_message("Zero kills : multi_kill NE doit PAS être émis (resté à -1)") \
		.is_equal(-1)
