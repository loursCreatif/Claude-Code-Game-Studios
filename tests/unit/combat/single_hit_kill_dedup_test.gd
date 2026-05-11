# Tests unitaires Story-011 — Single-hit kill + dedup `_hit_this_swing`.
#
# Couvre AC-CMB-05/06/45 + AC-1 à AC-5 (cf. story-011) :
#   AC-CMB-05 : MockEnemy à portée → die() appelé 1×, instance_id ajouté à _hit_this_swing.
#   AC-CMB-06 : MockEnemy déjà dans _hit_this_swing → die() PAS rappelé.
#   AC-CMB-45 : collider sans méthode die() → no-crash, push_warning debug, no mut.
#   AC-1 : Single hit kill canonical.
#   AC-2 : Dedup intra-swing (idempotence).
#   AC-3 : No die() method skip.
#   AC-4 : `_hit_this_swing` cleared on `_start_swing()`.
#   AC-5 : `is_dead()` filter (skip déjà mort).
#   Bonus : MAX_KILLS_PER_SWING cap (story-011 défensif, story-012 plein scope).
#   Bonus : Slow-mo trigger (story-013 cross-link).
#
# Approche : test isolé sur `_resolve_kills(hit_ids)` qui prend les instance_ids en
# entrée. Pas de physics query — `_collect_swing_hits` testé séparément en
# `anti_tunneling_substeps_test.gd` (story-009) + intégration soak story-018.
#
# MockEnemy fixture : `tests/unit/combat/mock_enemy.gd` — StaticBody3D minimal
# avec contract `die()` idempotent + `is_dead()` + layer=2. Pas de class_name
# (cache headless friendly) — instancié via `MockEnemyScript.new()`.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-011-single-hit-kill-dedup.md
# ADR     : ADR-0006 D-3 (instance_id stocké pas Node refs)

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

func _make_combat() -> CombatSystem:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child(player)
	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)
	return combat


## Renvoie un StaticBody3D MockEnemy avec collision shape attachée et layer=2.
## Type returned : StaticBody3D (parent class — accès `die()`/`is_dead()`/`_die_count`
## via duck typing, le script attaché les fournit).
func _make_mock_enemy() -> StaticBody3D:
	var enemy: StaticBody3D = MockEnemyScript.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	enemy.add_child(shape)
	add_child(enemy)
	return enemy


# ---------------------------------------------------------------------------
# AC-CMB-05 / AC-1 — Single hit kill canonical
# ---------------------------------------------------------------------------

func test_combat_single_hit_calls_die_once_and_appends_instance_id() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat()
	var enemy: StaticBody3D = _make_mock_enemy()
	var enemy_id: int = enemy.get_instance_id()
	assert_array(combat._hit_this_swing).is_empty()

	# Act
	combat._resolve_kills([enemy_id])

	# Assert
	assert_int(enemy.get("_die_count")) \
		.override_failure_message("AC-CMB-05 : die() doit être appelé exactement 1 fois") \
		.is_equal(1)
	assert_bool(enemy.call("is_dead")) \
		.override_failure_message("AC-CMB-05 : enemy.is_dead() doit être true post-die()") \
		.is_true()
	assert_array(combat._hit_this_swing) \
		.override_failure_message("AC-CMB-05 : _hit_this_swing doit contenir l'instance_id") \
		.contains([enemy_id])


# ---------------------------------------------------------------------------
# AC-CMB-06 / AC-2 — Dedup intra-swing : déjà dans _hit_this_swing → die() PAS rappelé
# ---------------------------------------------------------------------------

func test_combat_dedup_intra_swing_skips_already_hit_enemy() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat()
	var enemy: StaticBody3D = _make_mock_enemy()
	var enemy_id: int = enemy.get_instance_id()
	combat._hit_this_swing.append(enemy_id)

	# Act
	combat._resolve_kills([enemy_id])

	# Assert
	assert_int(enemy.get("_die_count")) \
		.override_failure_message("AC-CMB-06 : die() ne doit PAS être rappelé (déjà dans _hit_this_swing)") \
		.is_equal(0)
	assert_int(combat._hit_this_swing.size()) \
		.override_failure_message("AC-CMB-06 : _hit_this_swing doit rester taille 1 (no double-append)") \
		.is_equal(1)


# ---------------------------------------------------------------------------
# AC-CMB-45 / AC-3 — collider sans méthode die() → no-crash, no mut
# ---------------------------------------------------------------------------

func test_combat_collider_without_die_method_skipped_no_crash() -> void:
	# Arrange : Node3D sans `die` method.
	var combat: CombatSystem = _make_combat()
	var bogus: Node3D = Node3D.new()
	add_child(bogus)
	var bogus_id: int = bogus.get_instance_id()

	# Act — ne doit pas crasher.
	combat._resolve_kills([bogus_id])

	# Assert
	assert_array(combat._hit_this_swing) \
		.override_failure_message("AC-CMB-45 : _hit_this_swing non muté pour collider sans die()") \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-4 — `_hit_this_swing` cleared on `_start_swing()`
# ---------------------------------------------------------------------------

func test_combat_start_swing_clears_hit_this_swing() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat()
	combat._hit_this_swing.append(101)
	combat._hit_this_swing.append(102)
	assert_int(combat._hit_this_swing.size()).is_equal(2)

	# Act
	combat._start_swing()

	# Assert
	assert_array(combat._hit_this_swing) \
		.override_failure_message("AC-4 : _start_swing() doit clear _hit_this_swing") \
		.is_empty()


# ---------------------------------------------------------------------------
# AC-5 — `is_dead()` filter : enemy déjà mort → skip
# ---------------------------------------------------------------------------

func test_combat_already_dead_enemy_skipped() -> void:
	# Arrange : enemy déjà mort tick précédent (pas encore freed).
	var combat: CombatSystem = _make_combat()
	var enemy: StaticBody3D = _make_mock_enemy()
	enemy.call("die")  # is_dead = true, _die_count = 1
	assert_bool(enemy.call("is_dead")).is_true()
	var enemy_id: int = enemy.get_instance_id()

	# Act
	combat._resolve_kills([enemy_id])

	# Assert
	assert_int(enemy.get("_die_count")) \
		.override_failure_message("AC-5 : die() ne doit PAS être ré-appelé sur enemy is_dead=true") \
		.is_equal(1)
	assert_array(combat._hit_this_swing) \
		.override_failure_message("AC-5 : _hit_this_swing non muté pour enemy déjà mort") \
		.is_empty()


# ---------------------------------------------------------------------------
# Robustness — instance_id orphan (instance_from_id retourne null)
# ---------------------------------------------------------------------------

func test_combat_invalid_instance_id_skipped_no_crash() -> void:
	# Arrange : id résiduel d'un enemy free entre frames.
	var combat: CombatSystem = _make_combat()
	var enemy: StaticBody3D = _make_mock_enemy()
	var stale_id: int = enemy.get_instance_id()
	enemy.queue_free()
	await get_tree().process_frame  # let queue_free settle

	# Act — ne doit pas crasher.
	combat._resolve_kills([stale_id])

	# Assert
	assert_array(combat._hit_this_swing) \
		.override_failure_message("Robustness : _hit_this_swing non muté pour stale instance_id") \
		.is_empty()


# ---------------------------------------------------------------------------
# Bonus — MAX_KILLS_PER_SWING cap (story-011 défensif, story-012 plein scope)
# ---------------------------------------------------------------------------

func test_combat_max_kills_per_swing_cap_breaks_loop() -> void:
	# Arrange : MAX_KILLS_PER_SWING + 2 enemies → seuls les MAX premiers résolus.
	var combat: CombatSystem = _make_combat()
	var enemies: Array[StaticBody3D] = []
	var ids: Array[int] = []
	for i in CombatSystem.MAX_KILLS_PER_SWING + 2:
		var e: StaticBody3D = _make_mock_enemy()
		enemies.append(e)
		ids.append(e.get_instance_id())

	# Act
	combat._resolve_kills(ids)

	# Assert
	assert_int(combat._hit_this_swing.size()) \
		.override_failure_message("MAX_KILLS cap : _hit_this_swing doit être ≤ MAX_KILLS_PER_SWING") \
		.is_equal(CombatSystem.MAX_KILLS_PER_SWING)
	for i in CombatSystem.MAX_KILLS_PER_SWING:
		assert_int(enemies[i].get("_die_count")) \
			.override_failure_message("Enemy #%d (in cap) doit avoir die() appelé" % i) \
			.is_equal(1)
	for i in range(CombatSystem.MAX_KILLS_PER_SWING, enemies.size()):
		assert_int(enemies[i].get("_die_count")) \
			.override_failure_message("Enemy #%d (over cap) ne doit PAS avoir die() appelé" % i) \
			.is_equal(0)


# ---------------------------------------------------------------------------
# Slow-mo trigger — 1er kill du swing déclenche slow-mo (story 013 cross-link)
# ---------------------------------------------------------------------------

func test_combat_first_kill_triggers_slow_mo() -> void:
	# Arrange
	var combat: CombatSystem = _make_combat()
	combat._reduce_motion_disable_slow_mo = false
	combat._reduce_motion_slow_mo_scale_mult = 1.0
	combat._get_time_msec = func() -> int: return 12345
	var enemy: StaticBody3D = _make_mock_enemy()
	var initial_time_scale: float = Engine.time_scale
	assert_bool(combat._slow_mo_active).is_false()

	# Act
	combat._resolve_kills([enemy.get_instance_id()])

	# Assert
	assert_bool(combat._slow_mo_active) \
		.override_failure_message("Story 013 cross-link : 1er kill doit activer slow-mo") \
		.is_true()
	assert_float(Engine.time_scale) \
		.override_failure_message("Story 013 cross-link : Engine.time_scale doit = SLOW_MO_SCALE post-kill") \
		.is_equal_approx(CombatSystem.SLOW_MO_SCALE, 0.001)

	# Cleanup pour ne pas polluer les tests suivants.
	Engine.time_scale = initial_time_scale
	combat._slow_mo_active = false
