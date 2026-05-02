# Runner headless AC-PF-4 (story-008) — stress zero-alloc 10k action_press + 10k mouse_motion
# sur 60 s. Valide que MEMORY_STATIC delta reste sous le seuil 64 KB (ADR-0004 VC-3).
#
# Cadence : ~167 events/s de chaque type = ~333 events/s cumulés. En-dessous du burst
# gameplay normal (1000 Hz flick souris) et suffisant pour saturer les hot paths
# _unhandled_input + _physics_process sans saturer le budget frame.
#
# RNG seed fixe 54321 pour déterminisme — le pattern d'actions est reproductible
# run-after-run, ce qui permet de comparer deux evidence logs sur le même build.
#
# Lancement : godot --headless res://tests/performance/input_zero_alloc_stress.tscn
# Exit code 0 si delta < 64 KB, 1 sinon (gate CI).
extends Node

const DURATION_SEC: float = 60.0
const WARMUP_SEC: float = 5.0  # Post-boot stabilisation — couvre lazy init Godot (overlay debug, pools InputEvent, scene graph settle)
const TOTAL_ACTION_EVENTS: int = 10_000
const TOTAL_MOUSE_EVENTS: int = 10_000
const MEMORY_DELTA_GATE_BYTES: int = 65_536  # 64 KB — AC-PF-4 seuil dur, mesuré POST-warmup (ADR-0004 VC-3 intent = drift continu, pas boot alloc)
const SAMPLE_INTERVAL_SEC: float = 5.0
const RNG_SEED: int = 54321

# Actions gameplay MVP — alignées avec InputManagerScript.ACTIONS_MVP (hors UI).
# StringName literals pour éviter toute allocation lors de l'indexation.
const GAMEPLAY_ACTIONS: Array[StringName] = [
	&"jump", &"dash", &"attack", &"move_forward",
	&"move_back", &"move_left", &"move_right", &"restart",
]

var _elapsed: float = 0.0
var _warmup_done: bool = false
# Budget recalculé sur la durée post-warmup — garantit 10k/10k events pendant la phase mesurée.
var _action_budget_per_sec: float = TOTAL_ACTION_EVENTS / DURATION_SEC
var _mouse_budget_per_sec: float = TOTAL_MOUSE_EVENTS / DURATION_SEC
var _action_accum: float = 0.0
var _mouse_accum: float = 0.0
var _action_events_emitted: int = 0
var _mouse_events_emitted: int = 0
var _next_mem_sample_sec: float = WARMUP_SEC + SAMPLE_INTERVAL_SEC
var _warmup_baseline_bytes: int = 0
var _boot_baseline_bytes: int = 0
# Pré-allouée à la taille max (16 samples : warmup-baseline + 12×5s + fin) pour éviter push_back runtime.
var _mem_samples: PackedInt64Array = PackedInt64Array()
var _sample_count: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _log_path: String = ""
var _finalized: bool = false


func _ready() -> void:
	_rng.seed = RNG_SEED
	# Pré-allouer le buffer de samples — warmup-baseline + 12×5s + clôture = 14 max.
	# 20 slots donne marge confort, zéro realloc pendant le run.
	_mem_samples.resize(20)
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	_log_path = "res://production/qa/evidence/input-zero-alloc-%s.log" % timestamp
	# Capture boot baseline (avant warmup) pour traçabilité — non utilisé par le gate.
	_boot_baseline_bytes = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	print(
		"Input zero-alloc stress — start | seed=%d | warmup=%.1fs | duration=%.1fs | gate=%d bytes (post-warmup)"
		% [RNG_SEED, WARMUP_SEC, DURATION_SEC, MEMORY_DELTA_GATE_BYTES]
	)


func _physics_process(delta: float) -> void:
	if _finalized:
		return
	_elapsed += delta

	# Phase 1 : warmup (0 → WARMUP_SEC). On émet DÉJÀ des events pour forcer
	# la lazy init de Godot (pools InputEvent, dispatch signal, overlay debug).
	# Les events warmup ne comptent PAS dans les 10k cibles — c'est juste pour
	# chauffer les allocateurs internes. Sinon le premier _unhandled_input après
	# mesure baseline pollue la mesure avec des allocs one-shot.
	if not _warmup_done:
		# Cadence warmup = cadence finale (167/s de chaque) — pas besoin de sur-stress ici.
		_action_accum += _action_budget_per_sec * delta
		_mouse_accum += _mouse_budget_per_sec * delta
		while _action_accum >= 1.0:
			var action: StringName = GAMEPLAY_ACTIONS[_rng.randi() % GAMEPLAY_ACTIONS.size()]
			InputManager.simulate_action_press(action)
			_action_accum -= 1.0
		while _mouse_accum >= 1.0:
			InputManager.simulate_mouse_motion(Vector2(1.0, 0.0))
			_mouse_accum -= 1.0
		if _elapsed >= WARMUP_SEC:
			# Post-warmup : mesurer baseline et redémarrer les compteurs pour la phase mesurée.
			_warmup_done = true
			_warmup_baseline_bytes = int(Performance.get_monitor(Performance.MEMORY_STATIC))
			_action_accum = 0.0
			_mouse_accum = 0.0
			_action_events_emitted = 0
			_mouse_events_emitted = 0
			_mem_samples[_sample_count] = _warmup_baseline_bytes
			_sample_count += 1
			print(
				"  warmup done | boot_baseline=%d bytes | post_warmup=%d bytes | delta_boot=%d bytes"
				% [_boot_baseline_bytes, _warmup_baseline_bytes, _warmup_baseline_bytes - _boot_baseline_bytes]
			)
		return

	# Phase 2 : stress mesuré sur DURATION_SEC.
	_action_accum += _action_budget_per_sec * delta
	_mouse_accum += _mouse_budget_per_sec * delta

	# Boucle drain — emit autant d'events que l'accumulateur permet.
	# Les caps (_action_events_emitted < TOTAL) garantissent qu'on ne dépasse pas
	# la cible 10k même si le frame a pris plus de temps que prévu.
	while _action_accum >= 1.0 and _action_events_emitted < TOTAL_ACTION_EVENTS:
		var action: StringName = GAMEPLAY_ACTIONS[_rng.randi() % GAMEPLAY_ACTIONS.size()]
		InputManager.simulate_action_press(action)
		_action_accum -= 1.0
		_action_events_emitted += 1

	while _mouse_accum >= 1.0 and _mouse_events_emitted < TOTAL_MOUSE_EVENTS:
		InputManager.simulate_mouse_motion(Vector2(1.0, 0.0))
		_mouse_accum -= 1.0
		_mouse_events_emitted += 1

	# Sample toutes les 5 s — permet de détecter un drift linéaire (leak)
	# vs un allocation spike ponctuel (GC/fragmentation ponctuelle acceptable).
	if _elapsed >= _next_mem_sample_sec:
		_record_memory_sample()
		_next_mem_sample_sec += SAMPLE_INTERVAL_SEC

	if _elapsed >= WARMUP_SEC + DURATION_SEC:
		_finalize()


func _record_memory_sample() -> void:
	if _sample_count >= _mem_samples.size():
		return  # safety guard — ne devrait jamais arriver (buffer 20 slots, 14 max)
	_mem_samples[_sample_count] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_sample_count += 1


func _finalize() -> void:
	_finalized = true
	# Dernier sample après stress complet — capture le pic final.
	_record_memory_sample()
	# Baseline = post-warmup (mem_samples[0]) ; gate mesure le drift sous stress mesuré,
	# pas le cost de lazy init boot (ADR-0004 VC-3 intent documenté).
	var baseline: int = _mem_samples[0]
	var final_mem: int = _mem_samples[_sample_count - 1]
	var delta_bytes: int = final_mem - baseline
	var pass_gate: bool = delta_bytes < MEMORY_DELTA_GATE_BYTES

	var f: FileAccess = FileAccess.open(_log_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open log %s" % _log_path)
		get_tree().quit(2)
		return

	var os_name: String = OS.get_name()
	var debug_flag: String = "debug" if OS.has_feature("debug") else "release"
	f.store_line("# Input zero-alloc stress — %s" % Time.get_datetime_string_from_system())
	f.store_line("# Build: %s, OS: %s, seed: %d" % [debug_flag, os_name, RNG_SEED])
	f.store_line(
		"# Warmup: %.1fs | Measured stress: %.1fs | action_events: %d/%d | mouse_events: %d/%d"
		% [WARMUP_SEC, DURATION_SEC, _action_events_emitted, TOTAL_ACTION_EVENTS,
			_mouse_events_emitted, TOTAL_MOUSE_EVENTS]
	)
	f.store_line(
		"# Boot baseline=%d bytes | Post-warmup baseline=%d bytes | Lazy-init delta=%d bytes (not gated)"
		% [_boot_baseline_bytes, _warmup_baseline_bytes, _warmup_baseline_bytes - _boot_baseline_bytes]
	)
	# Samples sous stress mesuré : sample 0 = post-warmup baseline (t=0 du stress).
	# Indexation temporelle relative à la phase mesurée (post-warmup) pour lisibilité.
	for i: int in _sample_count:
		var t_sec: int = i * int(SAMPLE_INTERVAL_SEC)
		if i == _sample_count - 1 and _sample_count > int(DURATION_SEC / SAMPLE_INTERVAL_SEC):
			t_sec = int(_elapsed - WARMUP_SEC)  # last sample = actual end time of measured phase
		f.store_line("t=%ds MEMORY_STATIC=%d bytes" % [t_sec, _mem_samples[i]])
	f.store_line(
		"DELTA_STRESS_%ds=%d bytes (gate < %d)" % [int(DURATION_SEC), delta_bytes, MEMORY_DELTA_GATE_BYTES]
	)
	f.store_line("GATE_AC_PF_4=%s" % ("PASS" if pass_gate else "FAIL"))
	f.close()

	print("Input zero-alloc stress — end")
	print(
		"  post-warmup baseline=%d bytes, final=%d bytes, delta=%d bytes"
		% [baseline, final_mem, delta_bytes]
	)
	print("  action_events=%d mouse_events=%d" % [_action_events_emitted, _mouse_events_emitted])
	print("  AC-PF-4 gate (delta < %d): %s" % [MEMORY_DELTA_GATE_BYTES, "PASS" if pass_gate else "FAIL"])
	print("  evidence log: %s" % _log_path)

	if not pass_gate:
		push_error(
			"AC-PF-4 FAIL: delta=%d bytes exceeds 64 KB gate. Investigation branch requise (cf. story-008 fallback PackedByteArray ADR-0004 Risk 2)."
			% delta_bytes
		)

	# Pas de OS.exit_code dans l'API publique — get_tree().quit(int) est le canal.
	get_tree().quit(0 if pass_gate else 1)
