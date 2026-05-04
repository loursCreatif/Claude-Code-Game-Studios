# Microbench Story-017 — `_collect_swing_hits()` p99 ≤ 5 ms (Tier 1 Minimum Supporté).
#
# Mesure le coût COMPLET d'un sweep katana : positionnement basis + 3 substeps
# `force_shapecast_update` + accumulation + dedup. Les substeps font des physics
# queries Jolt réelles (10 MockEnemies déterministes positionnés autour du Player).
#
# AC : production/epics/combat-system/story-017-shapecast-microbench-p99.md (AC-CMB-35a)
# ADR : ADR-0006 D-1/D-2/D-3 + ADR-0001 (physics_process autorité)
# Framework : GdUnit4 v5
#
# DEVIATION du run command original (`--script`) : converti en GdUnit4 test parce que
# `--script` ne charge pas les autoloads (AccessibilityService référencé par CombatSystem
# fail au compile). GdUnit4 cmdtool charge les autoloads → compile OK.
#
# Run :
#   godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
#     --add tests/perf/combat_shapecast_microbench_test.gd --ignoreHeadlessMode
#
# Threshold : p99 > 5 ms → test FAIL.
# Justification : 5 ms = ~30% du frame budget 16.6 ms. ShapeCast doit tenir
# dans sa part — Movement/Camera/VFX/Audio/rendering se partagent les 11.6 ms restants.
#
# Hardware testbed : Tier 1 Minimum Supporté (cf. docs/architecture/hardware-spec-testbeds.md).
# Run actuel : INFORMATIONAL BASELINE (dev laptop) — official Tier 1 sign-off DEFERRED CI infra.

extends GdUnitTestSuite


const SAMPLE_COUNT: int = 1000
const WARMUP_COUNT: int = 60
const ENEMY_COUNT: int = 10
const ENEMY_SEED: int = 12345
const VOLUME_HALF_EXTENT: float = 2.5
const P99_THRESHOLD_MS: float = 5.0
const LOG_PATH: String = "res://tests/perf/combat-shapecast-microbench-log.md"


var _player: CharacterBody3D
var _combat: Node3D
var _enemies: Array[StaticBody3D] = []


func before_test() -> void:
	# Setup scene : Player + Combat + 10 MockEnemies déterministes.
	_player = CharacterBody3D.new()
	get_tree().root.add_child(_player)
	_player.global_position = Vector3.ZERO

	var packed: PackedScene = load("res://src/gameplay/combat/combat_system.tscn") as PackedScene
	assert_that(packed).is_not_null().override_failure_message(
		"combat_system.tscn failed to load"
	)
	var combat_node: Node = packed.instantiate()
	assert_that(combat_node).is_not_null().override_failure_message(
		"combat_system.tscn instantiate returned null"
	)
	_combat = combat_node as Node3D
	assert_that(_combat).is_not_null().override_failure_message(
		"combat_system root not Node3D — class_name CombatSystem may be duplicated"
	)
	_player.add_child(_combat)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = ENEMY_SEED
	for i: int in range(ENEMY_COUNT):
		var enemy: StaticBody3D = StaticBody3D.new()
		enemy.set_collision_layer_value(CollisionLayers.LAYER_ENEMY, true)
		enemy.set_collision_layer_value(CollisionLayers.LAYER_PLAYER, false)
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: SphereShape3D = SphereShape3D.new()
		shape.radius = CombatSystem.ENEMY_RADIUS_MIN
		collision.shape = shape
		enemy.add_child(collision)
		get_tree().root.add_child(enemy)
		enemy.global_position = Vector3(
			rng.randf_range(-VOLUME_HALF_EXTENT, VOLUME_HALF_EXTENT),
			rng.randf_range(0.0, VOLUME_HALF_EXTENT * 2.0),
			rng.randf_range(-VOLUME_HALF_EXTENT, VOLUME_HALF_EXTENT)
		)
		_enemies.append(enemy)

	# Yield 1 physics frame pour que Jolt indexe les colliders.
	await get_tree().physics_frame


func after_test() -> void:
	for enemy: StaticBody3D in _enemies:
		enemy.queue_free()
	_enemies.clear()
	if _combat != null:
		_combat.queue_free()
	if _player != null:
		_player.queue_free()


func test_combat_shapecast_microbench_p99_under_5ms() -> void:
	# Arrange — warmup ignoré.
	for i: int in range(WARMUP_COUNT):
		_combat._collect_swing_hits()

	# Act — 1000 samples mesurés.
	var samples: PackedInt64Array = PackedInt64Array()
	samples.resize(SAMPLE_COUNT)
	for i: int in range(SAMPLE_COUNT):
		var t0: int = Time.get_ticks_usec()
		_combat._collect_swing_hits()
		var t1: int = Time.get_ticks_usec()
		samples[i] = t1 - t0

	# Assert — p99 sous threshold + log entry.
	samples.sort()
	var p50_us: int = samples[int(SAMPLE_COUNT * 0.5)]
	var p99_us: int = samples[int(SAMPLE_COUNT * 0.99)]
	var max_us: int = samples[SAMPLE_COUNT - 1]
	var p50_ms: float = float(p50_us) / 1000.0
	var p99_ms: float = float(p99_us) / 1000.0
	var max_ms: float = float(max_us) / 1000.0

	_append_log_entry(p50_ms, p99_ms, max_ms)

	assert_that(p99_ms).is_less_equal(P99_THRESHOLD_MS).override_failure_message(
		"AC-CMB-35a FAIL: p99=%.3f ms > %.1f ms threshold (Tier 1 Minimum Supporté). " % [p99_ms, P99_THRESHOLD_MS] +
		"p50=%.3f ms / max=%.3f ms — voir log %s" % [p50_ms, max_ms, LOG_PATH]
	)


func _append_log_entry(p50_ms: float, p99_ms: float, max_ms: float) -> void:
	var os_name: String = OS.get_name()
	var processor_name: String = OS.get_processor_name()
	var processor_count: int = OS.get_processor_count()
	var hardware_label: String = "%s — %s (%d cores) — INFORMATIONAL BASELINE (NOT certified Tier 1 — CI infra DEFERRED — see hardware-spec-testbeds.md)" \
			% [os_name, processor_name, processor_count]
	var verdict: String = "PASS" if p99_ms <= P99_THRESHOLD_MS else "**FAIL**"
	var entry: String = (
		"\n## Run %s\n\n" % Time.get_datetime_string_from_system() +
		"- **Hardware** : %s\n" % hardware_label +
		"- **Godot version** : 4.6 (project pinned)\n" +
		"- **Physics** : Jolt 4.6 default\n" +
		"- **Samples** : %d (warmup %d ignorés)\n" % [SAMPLE_COUNT, WARMUP_COUNT] +
		"- **Enemies** : %d (seed %d, volume %.1fm³)\n" \
				% [ENEMY_COUNT, ENEMY_SEED, VOLUME_HALF_EXTENT * 2.0] +
		"- **p50** : %.3f ms\n" % p50_ms +
		"- **p99** : %.3f ms (threshold ≤ %.1f ms)\n" % [p99_ms, P99_THRESHOLD_MS] +
		"- **max** : %.3f ms\n" % max_ms +
		"- **Verdict** : %s\n" % verdict
	)
	var log_file: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if log_file == null:
		log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if log_file != null:
		log_file.seek_end()
		log_file.store_string(entry)
		log_file.close()
