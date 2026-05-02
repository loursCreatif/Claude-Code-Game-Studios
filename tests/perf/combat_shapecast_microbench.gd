# Microbench Story-017 — `_collect_swing_hits()` p99 ≤ 5 ms (Tier 1 Minimum Supporté).
#
# Mesure le coût COMPLET d'un sweep katana : positionnement basis + 3 substeps
# `force_shapecast_update` + accumulation + dedup. Les substeps font des physics
# queries Jolt réelles (10 MockEnemies déterministes positionnés autour du Player).
#
# Run :
#   godot --headless --script tests/perf/combat_shapecast_microbench.gd
#
# Threshold : p99 > 5 ms → exit code 1 + push_error.
# Justification : 5 ms = ~30% du frame budget 16.6 ms. ShapeCast doit tenir
# dans sa part — Movement/Camera/VFX/Audio/rendering se partagent les 11.6 ms restants.
#
# Hardware testbed : Tier 1 Minimum Supporté (cf. docs/architecture/hardware-spec-testbeds.md).
# AC : tests/perf/combat-shapecast-microbench-log.md doit avoir une entry par run.

extends SceneTree


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SAMPLE_COUNT: int = 1000
const WARMUP_COUNT: int = 60
const ENEMY_COUNT: int = 10
const ENEMY_SEED: int = 12345
const VOLUME_HALF_EXTENT: float = 2.5  # 5×5×5 m volume autour du Player
const P99_THRESHOLD_MS: float = 5.0
const LOG_PATH: String = "res://tests/perf/combat-shapecast-microbench-log.md"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

func _initialize() -> void:
	print("=== Story-017 ShapeCast microbench p99 ≤ %.1f ms ===" % P99_THRESHOLD_MS)
	print("Setup : %d MockEnemies (seed=%d) dans volume %.1fm³, Tier 1 Minimum Supporté" \
			% [ENEMY_COUNT, ENEMY_SEED, VOLUME_HALF_EXTENT * 2.0])

	# Scene setup : Player parent + Combat + N MockEnemies dans LAYER_ENEMY.
	var player: CharacterBody3D = CharacterBody3D.new()
	root.add_child(player)
	player.global_position = Vector3.ZERO

	var packed: PackedScene = load("res://src/gameplay/combat/combat_system.tscn") as PackedScene
	var combat: CombatSystem = packed.instantiate() as CombatSystem
	player.add_child(combat)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = ENEMY_SEED
	for i: int in range(ENEMY_COUNT):
		var enemy: StaticBody3D = StaticBody3D.new()
		enemy.set_collision_layer_value(CollisionLayers.LAYER_ENEMY, true)
		enemy.set_collision_layer_value(CollisionLayers.LAYER_PLAYER, false)
		enemy.global_position = Vector3(
			rng.randf_range(-VOLUME_HALF_EXTENT, VOLUME_HALF_EXTENT),
			rng.randf_range(0.0, VOLUME_HALF_EXTENT * 2.0),
			rng.randf_range(-VOLUME_HALF_EXTENT, VOLUME_HALF_EXTENT)
		)
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: SphereShape3D = SphereShape3D.new()
		shape.radius = CombatSystem.ENEMY_RADIUS_MIN
		collision.shape = shape
		enemy.add_child(collision)
		root.add_child(enemy)

	# Yield 1 physics frame pour que Jolt indexe les colliders.
	await physics_frame

	print("Warmup : %d swings ignorés…" % WARMUP_COUNT)
	for i: int in range(WARMUP_COUNT):
		combat._collect_swing_hits()

	print("Sampling : %d swings mesurés…" % SAMPLE_COUNT)
	var samples: PackedInt64Array = PackedInt64Array()
	samples.resize(SAMPLE_COUNT)
	for i: int in range(SAMPLE_COUNT):
		var t0: int = Time.get_ticks_usec()
		combat._collect_swing_hits()
		var t1: int = Time.get_ticks_usec()
		samples[i] = t1 - t0

	# Trier pour calcul percentiles
	samples.sort()
	var p50_us: int = samples[int(SAMPLE_COUNT * 0.5)]
	var p99_us: int = samples[int(SAMPLE_COUNT * 0.99)]
	var max_us: int = samples[SAMPLE_COUNT - 1]
	var p50_ms: float = float(p50_us) / 1000.0
	var p99_ms: float = float(p99_us) / 1000.0
	var max_ms: float = float(max_us) / 1000.0

	print("Résultat : p50=%.3f ms, p99=%.3f ms, max=%.3f ms" % [p50_ms, p99_ms, max_ms])

	# Append au log
	var log_entry: String = (
		"\n## Run %s\n\n" % Time.get_datetime_string_from_system() +
		"- **Hardware** : Tier 1 Minimum Supporté\n" +
		"- **Godot version** : 4.6 (project pinned)\n" +
		"- **Physics** : Jolt 4.6 default\n" +
		"- **Samples** : %d (warmup %d ignorés)\n" % [SAMPLE_COUNT, WARMUP_COUNT] +
		"- **Enemies** : %d (seed %d, volume %.1fm³)\n" \
				% [ENEMY_COUNT, ENEMY_SEED, VOLUME_HALF_EXTENT * 2.0] +
		"- **p50** : %.3f ms\n" % p50_ms +
		"- **p99** : %.3f ms (threshold ≤ %.1f ms)\n" % [p99_ms, P99_THRESHOLD_MS] +
		"- **max** : %.3f ms\n" % max_ms +
		"- **Verdict** : %s\n" % ("PASS" if p99_ms <= P99_THRESHOLD_MS else "**FAIL**")
	)
	var log_file: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if log_file == null:
		log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if log_file != null:
		log_file.seek_end()
		log_file.store_string(log_entry)
		log_file.close()
		print("Log : %s mis à jour" % LOG_PATH)

	if p99_ms > P99_THRESHOLD_MS:
		push_error(
			"Story-017 AC-CMB-35a FAIL: p99=%.3f ms > %.1f ms threshold (Tier 1)"
			% [p99_ms, P99_THRESHOLD_MS]
		)
		quit(1)
	else:
		print("Story-017 PASS : p99=%.3f ms <= %.1f ms" % [p99_ms, P99_THRESHOLD_MS])
		quit(0)
