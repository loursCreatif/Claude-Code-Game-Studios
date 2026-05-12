# Tests unitaires Story-009 — N=3 substeps anti-tunneling + dedup colliders.
#
# Couvre AC-1 à AC-5 (cf. story-009) + AC-CMB-14 + Gap 8 doc :
#   AC-1 : N_SUBSTEPS == 3 constant + gap_max < 0.7 m à V=30 m/s.
#   AC-2 : grep statique — aucun branching dynamique sur velocity.
#   AC-3 : `_compute_substep_segment` interpolation linéaire prev→current.
#   AC-4 : `_dedupe_collider_ids` instance_id dédup (mock objects).
#   AC-5 : `docs/engine-reference/godot/modules/physics.md` documente Jolt margin.
#
# Hors scope unit (DEFERRED story-018 soak) : `_collect_swing_hits` exécute des
# physics queries réelles via `force_shapecast_update` — testé en intégration.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Story   : production/epics/combat-system/story-009-anti-tunneling-substeps-jolt-margin.md
# ADR     : ADR-0006 D-3 (substeps), ADR-0001 (60 Hz physics)
# GDD     : design/gdd/player-combat-system.md AC-CMB-14

extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SCENE_PATH: String = "res://src/gameplay/combat/combat_system.tscn"
const COMBAT_SOURCE_PATH: String = "res://src/gameplay/combat/combat_system.gd"
const PHYSICS_DOC_PATH: String = "res://docs/engine-reference/godot/modules/physics.md"

const PHYSICS_DELTA: float = 1.0 / 60.0
const V_MAX: float = 30.0  # dash speed (KATANA_REACH-aligned hardware budget)
const ENEMY_RADIUS_MIN: float = 0.35  # r_enemy_min (Combat §D.3)
const GAP_MAX_THRESHOLD: float = 2.0 * ENEMY_RADIUS_MIN  # 0.7 m


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
# AC-1 — N_SUBSTEPS == 3 constant + gap_max < 0.7 m
# ---------------------------------------------------------------------------

## AC-1 : N_SUBSTEPS = 3 constant compile-time.
func test_combat_n_substeps_constant_equals_three() -> void:
	assert_int(CombatSystem.N_SUBSTEPS) \
		.override_failure_message(
			"AC-1: N_SUBSTEPS doit être 3 (formula `gap_max = V × delta / N < 2 × r_enemy_min`)"
		) \
		.is_equal(3)


## AC-1 : `gap_max = V × delta / N < 2 × r_enemy_min` à V_max=30, delta=1/60, N=3 →
## gap = 30 × (1/60) / 3 = 0.166 m << 0.7 m.
func test_combat_gap_max_under_threshold_at_dash_velocity() -> void:
	var velocities: Array[float] = [0.0, 10.0, 30.0]

	for v: float in velocities:
		var gap_max: float = v * PHYSICS_DELTA / float(CombatSystem.N_SUBSTEPS)
		assert_float(gap_max) \
			.override_failure_message(
				"AC-1: gap_max à V=%.1f doit être < %.3f m (= 2 × r_enemy_min) — calculé %.3f"
				% [v, GAP_MAX_THRESHOLD, gap_max]
			) \
			.is_less(GAP_MAX_THRESHOLD)


# ---------------------------------------------------------------------------
# AC-2 — Grep statique : aucun branching dynamique sur velocity
# ---------------------------------------------------------------------------

## AC-2 : aucune ligne ne fait varier N_SUBSTEPS en fonction de velocity.
## Patterns interdits :
##   `TUNNELING_THRESHOLD` utilisée pour gate
##   `if velocity ... N_SUBSTEPS = ...`
##   `N_SUBSTEPS = X if ...` (assignation conditionnelle)
##
## Note : `const N_SUBSTEPS: int = 3` est autorisé (declaration constante compile-time).
func test_combat_source_no_dynamic_n_substeps_branching() -> void:
	var file: FileAccess = FileAccess.open(COMBAT_SOURCE_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	var regex: RegEx = RegEx.new()
	# Match : N_SUBSTEPS = (non-const) ou TUNNELING_THRESHOLD utilisé pour gate
	# La déclaration `const N_SUBSTEPS: int = 3` est autorisée (capturée par "const ").
	regex.compile("\\b(TUNNELING_THRESHOLD|N_SUBSTEPS\\s*=\\s*\\d+\\s+if)")

	var violations: Array[String] = []
	for i: int in range(lines.size()):
		var line: String = lines[i]
		if line.strip_edges().begins_with("#"):
			continue
		if line.strip_edges().begins_with("const N_SUBSTEPS"):
			continue
		if regex.search(line) != null:
			violations.append("L%d: %s" % [i + 1, line])

	assert_int(violations.size()) \
		.override_failure_message(
			"AC-2: aucun branching dynamique sur N_SUBSTEPS autorisé. " +
			"N doit rester constant compile-time. Violations : %s" % str(violations)
		) \
		.is_equal(0)


# ---------------------------------------------------------------------------
# AC-3 — Substep position interpolation (pure function)
# ---------------------------------------------------------------------------

## AC-3 : pour `prev = (0,0,0)`, `current = (0,0,-0.5)`, `aim = (0,0,-1)` :
##   substep 0 from = (0,0,0)+(0,0,-0.9) = (0,0,-0.9)
##              to   = (0,0,-0.166)+(0,0,-0.9) = (0,0,-1.066)
##   substep 2 to   = (0,0,-0.5)+(0,0,-0.9) = (0,0,-1.4) [end of trajectory]
func test_combat_compute_substep_segment_interpolates_linearly() -> void:
	var combat: CombatSystem = _make_combat()
	var prev: Vector3 = Vector3.ZERO
	var current: Vector3 = Vector3(0.0, 0.0, -0.5)
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var offset: Vector3 = aim * (CombatSystem.KATANA_REACH / 2.0)

	# Substep 0
	var seg0: Array[Vector3] = combat._compute_substep_segment(0, prev, current, aim)
	assert_vector(seg0[0]) \
		.override_failure_message("AC-3 substep 0 from doit être prev + offset") \
		.is_equal_approx(prev + offset, Vector3.ONE * 0.001)
	assert_vector(seg0[1]) \
		.override_failure_message("AC-3 substep 0 to doit être lerp(prev, current, 1/3) + offset") \
		.is_equal_approx(prev.lerp(current, 1.0 / 3.0) + offset, Vector3.ONE * 0.001)

	# Substep 2 (dernier)
	var seg2: Array[Vector3] = combat._compute_substep_segment(2, prev, current, aim)
	assert_vector(seg2[1]) \
		.override_failure_message("AC-3 substep 2 to doit être current + offset (fin de trajectoire)") \
		.is_equal_approx(current + offset, Vector3.ONE * 0.001)

	combat.get_parent().queue_free()


## AC-3 edge : `prev == current` (joueur immobile) — 3 substeps balayent la même position.
func test_combat_compute_substep_segment_immobile_player_overlapping_substeps() -> void:
	var combat: CombatSystem = _make_combat()
	var pos: Vector3 = Vector3(1.0, 2.0, 3.0)
	var aim: Vector3 = Vector3(0.0, 0.0, -1.0)
	var offset: Vector3 = aim * (CombatSystem.KATANA_REACH / 2.0)
	var expected: Vector3 = pos + offset

	for i: int in range(CombatSystem.N_SUBSTEPS):
		var seg: Array[Vector3] = combat._compute_substep_segment(i, pos, pos, aim)
		assert_vector(seg[0]) \
			.override_failure_message("AC-3 immobile substep %d from = pos + offset" % i) \
			.is_equal_approx(expected, Vector3.ONE * 0.001)
		assert_vector(seg[1]) \
			.override_failure_message("AC-3 immobile substep %d to = pos + offset" % i) \
			.is_equal_approx(expected, Vector3.ONE * 0.001)

	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-4 — Dedup colliders via instance_id
# ---------------------------------------------------------------------------

## AC-4 : `_dedupe_collider_ids` retourne une liste unique d'instance_ids.
##
## Pattern test : on utilise des Node3D réels (ils ont `get_instance_id()`).
## On les ajoute au tree pour qu'ils ne soient pas freed pendant le test, puis on
## les met dans le tableau d'entrée avec des doublons.
func test_combat_dedupe_collider_ids_removes_duplicates() -> void:
	var combat: CombatSystem = _make_combat()

	var enemy_a: Node3D = Node3D.new()
	var enemy_b: Node3D = Node3D.new()
	var enemy_c: Node3D = Node3D.new()
	add_child(enemy_a)
	add_child(enemy_b)
	add_child(enemy_c)

	# 1 ennemi détecté 2× (substeps successifs) + 2 ennemis distincts.
	var input: Array[Object] = [enemy_a, enemy_a, enemy_b, enemy_c, enemy_a]

	# Act
	var deduped: Array[int] = combat._dedupe_collider_ids(input)

	# Assert — 3 IDs uniques
	assert_int(deduped.size()) \
		.override_failure_message(
			"AC-4: dedup doit retourner 3 IDs uniques sur 5 entries (3 distincts) — reçu %d"
			% deduped.size()
		) \
		.is_equal(3)
	# Vérifier que les bons IDs sont présents
	assert_bool(enemy_a.get_instance_id() in deduped).is_true()
	assert_bool(enemy_b.get_instance_id() in deduped).is_true()
	assert_bool(enemy_c.get_instance_id() in deduped).is_true()
	# Ordre d'insertion préservé pour le 1er occurrence
	assert_int(deduped[0]).is_equal(enemy_a.get_instance_id())
	assert_int(deduped[1]).is_equal(enemy_b.get_instance_id())
	assert_int(deduped[2]).is_equal(enemy_c.get_instance_id())

	enemy_a.queue_free()
	enemy_b.queue_free()
	enemy_c.queue_free()
	combat.get_parent().queue_free()


## AC-4 null-safe : entrées null ignorées sans crash.
func test_combat_dedupe_collider_ids_skips_null_entries() -> void:
	var combat: CombatSystem = _make_combat()
	var enemy: Node3D = Node3D.new()
	add_child(enemy)

	var input: Array[Object] = [null, enemy, null, enemy]
	var deduped: Array[int] = combat._dedupe_collider_ids(input)

	assert_int(deduped.size()).is_equal(1)
	assert_int(deduped[0]).is_equal(enemy.get_instance_id())

	enemy.queue_free()
	combat.get_parent().queue_free()


# ---------------------------------------------------------------------------
# AC-5 — Gap 8 doc : ShapeCast3D.margin Jolt 4.6 documenté
# ---------------------------------------------------------------------------

## AC-5 : `docs/engine-reference/godot/modules/physics.md` contient une section
## documentant le comportement empirique de `ShapeCast3D.margin` sous Jolt 4.6.
func test_engine_reference_documents_shapecast_margin_jolt_behavior() -> void:
	var file: FileAccess = FileAccess.open(PHYSICS_DOC_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("AC-5: physics.md doit exister") \
		.is_not_null()
	var content: String = file.get_as_text()
	file.close()

	# Le doc doit mentionner le gap (Gap 8) et la conclusion (Jolt ignore margin).
	assert_bool("ShapeCast3D.margin" in content) \
		.override_failure_message("AC-5: doc doit mentionner ShapeCast3D.margin") \
		.is_true()
	assert_bool("Jolt" in content) \
		.override_failure_message("AC-5: doc doit mentionner Jolt") \
		.is_true()
