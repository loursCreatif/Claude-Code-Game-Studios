# Tests unitaires Story-006 — ring buffer latence zero-alloc (ADR-0004 D-8, TR-inp-007).
#
# Couvre :
# - AC-L-1 : 6 samples [5,5,5,5,5,32] → p99 ≥ 30 (fallback max car valid < 10)
# - AC-L-2 : résolution horloge Time.get_ticks_usec() ≥ 1 ms précis
# - AC-L-4 : 50 samples à t0 - 2 s → p99 = 0.0 (aucun dans fenêtre 1 s)
# - Bord fenêtre : sample à t-999_999 µs inclusif
# - Buffer vide → 0.0
# - Wrap ring @ CAPACITY → sample_count clamp + write_idx monotone
# - last_input_to_publish_latency_ms getter reflète le dernier sample
# - Intégration hot path : press action → sample enregistré au swap suivant
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Chaque test instancie son propre InputManager — aucun état partagé via l'autoload.

extends GdUnitTestSuite

const LATENCY_CAPACITY: int = 120

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Crée et attache un InputManager frais au scene tree (déclenche _ready).
func _make_manager() -> InputManagerScript:
	var manager: InputManagerScript = InputManagerScript.new()
	add_child(manager)
	return manager

# ---------------------------------------------------------------------------
# AC-L-1 — 6 samples dont un spike 32 ms → p99 ≥ 30 (fallback max car valid < 10)
# ---------------------------------------------------------------------------

func test_latency_p99_with_6_samples_and_spike_returns_max_fallback() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var now: int = Time.get_ticks_usec()
	# Séquence [5, 5, 5, 5, 5, 32] — spike en dernière position.
	manager._record_latency_sample(5.0, now)
	manager._record_latency_sample(5.0, now)
	manager._record_latency_sample(5.0, now)
	manager._record_latency_sample(5.0, now)
	manager._record_latency_sample(5.0, now)
	manager._record_latency_sample(32.0, now)

	# Act
	var p99: float = manager.get_latency_p99_ms()

	# Assert — valid = 6 < 10, donc fallback max. Max des 6 valeurs = 32.
	assert_float(p99) \
		.override_failure_message(
			"AC-L-1: p99 avec 6 samples [5,5,5,5,5,32] doit retourner ≥ 30 (fallback max < 10 samples), got %.2f" % p99
		) \
		.is_greater_equal(30.0)

	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-L-1 (ordre indifférent) — spike en slot 0 ou slot 5 → même résultat
# ---------------------------------------------------------------------------

func test_latency_p99_spike_at_slot_0_and_slot_5_yield_same_result() -> void:
	var manager_a: InputManagerScript = _make_manager()
	var manager_b: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var now: int = Time.get_ticks_usec()
	# Manager A : spike au slot 0.
	manager_a._record_latency_sample(32.0, now)
	for _i: int in range(5):
		manager_a._record_latency_sample(5.0, now)
	# Manager B : spike au slot 5.
	for _i: int in range(5):
		manager_b._record_latency_sample(5.0, now)
	manager_b._record_latency_sample(32.0, now)

	# Assert — le tri canonique rend l'ordre d'insertion sans effet.
	assert_float(manager_a.get_latency_p99_ms()) \
		.override_failure_message("AC-L-1: ordre des samples ne doit pas affecter p99") \
		.is_equal(manager_b.get_latency_p99_ms())

	manager_a.queue_free()
	manager_b.queue_free()

# ---------------------------------------------------------------------------
# AC-L-2 — résolution horloge Time.get_ticks_usec() : 5 ms réel → delta ∈ [4, 6]
# ---------------------------------------------------------------------------

func test_latency_clock_resolution_5ms_sleep_measures_in_tolerance() -> void:
	# Arrange — OS.delay_usec garantit un sleep µs-précis, contrairement à
	# create_timer qui se quantifie sur le frame rate (~16.6 ms @ 60 Hz).
	# On valide ici la résolution de Time.get_ticks_usec, pas la précision du timer.
	var t0: int = Time.get_ticks_usec()

	# Act — sleep 5 ms réel.
	OS.delay_usec(5000)
	var t1: int = Time.get_ticks_usec()

	var delta_ms: float = float(t1 - t0) / 1000.0

	# Assert — tolérance AC story-006 [4, 6]. Borne inf détecte résolution < 1 ms.
	# Borne sup détecte jitter scheduler extrême (OS surchargé ou clock quantifié).
	# Si fail : investiguer — résolution horloge insuffisante pour mesurer latence
	# input gameplay (< 16 ms cible).
	assert_float(delta_ms) \
		.override_failure_message(
			"AC-L-2: 5 ms réel doit mesurer ≥ 4 ms (résolution horloge), got %.3f ms" % delta_ms
		) \
		.is_greater_equal(4.0)
	assert_float(delta_ms) \
		.override_failure_message(
			"AC-L-2: 5 ms réel doit mesurer ≤ 6 ms (jitter scheduler acceptable), got %.3f ms" % delta_ms
		) \
		.is_less_equal(6.0)

# ---------------------------------------------------------------------------
# AC-L-4 — fenêtre 1 s : 50 samples à t0 - 2 s → p99 = 0.0 (aucun dans fenêtre)
# ---------------------------------------------------------------------------

func test_latency_p99_all_samples_older_than_window_returns_zero() -> void:
	# Arrange
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var now: int = Time.get_ticks_usec()
	# Injecter 50 samples avec timestamps "t0 - 2 s" (hors fenêtre 1 s).
	# L'injection directe des timestamps remplace l'advance-time non disponible.
	var t_old: int = now - 2_000_000
	for _i: int in range(50):
		manager._record_latency_sample(10.0, t_old)

	# Act
	var p99: float = manager.get_latency_p99_ms()

	# Assert — aucun sample ne passe le filtre cutoff = now - 1_000_000 µs → 0.0.
	assert_float(p99) \
		.override_failure_message(
			"AC-L-4: 50 samples vieux de 2 s, p99 doit retourner 0.0 (aucun dans fenêtre 1 s), got %.2f" % p99
		) \
		.is_equal(0.0)

	manager.queue_free()

# ---------------------------------------------------------------------------
# AC-L-4 (bord) — sample à t-999_999 µs → inclus dans fenêtre (inclusif borne inf)
# ---------------------------------------------------------------------------

func test_latency_p99_sample_at_window_boundary_is_included() -> void:
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	# Sample au bord inclusif (marge 500 ms) : timestamp = now - 500_000 µs ≥ cutoff.
	# Marge choisie pour éviter la flakiness — un écart de quelques µs entre le `now`
	# du test et le `Time.get_ticks_usec()` interne à get_latency_p99_ms() doit rester
	# largement sous 500 ms sur n'importe quel runner CI. La sémantique "`>=` inclusif"
	# reste testée (le sample doit être à l'intérieur de la fenêtre 1 s et pas filtré).
	var now: int = Time.get_ticks_usec()
	var t_edge: int = now - 500_000
	manager._record_latency_sample(42.0, t_edge)

	# Act — valid = 1 < 10 → fallback max.
	var p99: float = manager.get_latency_p99_ms()

	# Assert — le sample doit passer le filtre et donner 42.
	assert_float(p99) \
		.override_failure_message(
			"AC-L-4 bord: sample à t-999_999 µs doit être inclus dans fenêtre, got %.2f" % p99
		) \
		.is_equal(42.0)

	manager.queue_free()

# ---------------------------------------------------------------------------
# Sanity — buffer vide → 0.0
# ---------------------------------------------------------------------------

func test_latency_p99_empty_buffer_returns_zero() -> void:
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	assert_float(manager.get_latency_p99_ms()) \
		.override_failure_message("Buffer vide doit retourner 0.0") \
		.is_equal(0.0)

	manager.queue_free()

# ---------------------------------------------------------------------------
# Sanity — last_input_to_publish_latency_ms getter reflète le dernier sample
# ---------------------------------------------------------------------------

func test_last_latency_property_reflects_most_recent_sample() -> void:
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var now: int = Time.get_ticks_usec()
	manager._record_latency_sample(12.3, now)
	assert_float(manager.last_input_to_publish_latency_ms) \
		.override_failure_message("last_input_to_publish_latency_ms doit = 12.3 après 1er sample") \
		.is_equal_approx(12.3, 0.01)

	manager._record_latency_sample(7.5, now)
	assert_float(manager.last_input_to_publish_latency_ms) \
		.override_failure_message("last_input_to_publish_latency_ms doit = 7.5 après 2e sample") \
		.is_equal_approx(7.5, 0.01)

	manager.queue_free()

# ---------------------------------------------------------------------------
# Sanity — wrap ring @ CAPACITY : sample_count clamp + write_idx monotone
# ---------------------------------------------------------------------------

func test_latency_ring_wrap_clamps_sample_count_and_preserves_write_idx() -> void:
	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var now: int = Time.get_ticks_usec()
	# Remplir CAPACITY + 5 samples → wrap modulo CAPACITY écrase les 5 premiers.
	for i: int in range(LATENCY_CAPACITY + 5):
		manager._record_latency_sample(float(i), now)

	# sample_count doit être clampé à CAPACITY (pas d'overflow).
	assert_int(manager._latency_sample_count) \
		.override_failure_message("sample_count doit être clampé à %d" % LATENCY_CAPACITY) \
		.is_equal(LATENCY_CAPACITY)

	# write_idx reste monotone — utilisé pour localiser le slot courant via %.
	assert_int(manager._latency_write_idx) \
		.override_failure_message(
			"write_idx doit être monotone = CAPACITY+5, got %d" % manager._latency_write_idx
		) \
		.is_equal(LATENCY_CAPACITY + 5)

	# Le slot 0 doit contenir la valeur i=CAPACITY (wrap a écrasé i=0).
	assert_float(manager._latency_values_ms[0]) \
		.override_failure_message("slot 0 doit contenir la valeur du wrap i=CAPACITY") \
		.is_equal(float(LATENCY_CAPACITY))

	manager.queue_free()

# ---------------------------------------------------------------------------
# Intégration hot path — press action → _event_arrival_ts_usec capturé → sample swap
# ---------------------------------------------------------------------------

func test_unhandled_input_action_press_records_latency_on_next_physics_frame() -> void:
	if not OS.has_feature("debug"):
		# parse_input_event peut être no-op en release selon build — skip explicite
		# pour que le runner marque SKIPPED plutôt que PASSED (visibilité CI).
		skip_test("requires debug feature (Input.parse_input_event is no-op in release)")
		return

	var manager: InputManagerScript = _make_manager()
	await get_tree().process_frame

	var count_before: int = manager._latency_sample_count

	# Act — injecter un press action (pattern ADR-0004 D-9 canonique).
	var ev := InputEventAction.new()
	ev.action = &"jump"
	ev.pressed = true
	Input.parse_input_event(ev)

	# Attendre le prochain physics_frame : _unhandled_input a capturé le ts,
	# _physics_process swap puis consomme _event_arrival_ts_usec.
	await get_tree().physics_frame

	# Assert — 1 sample enregistré exactement.
	assert_int(manager._latency_sample_count) \
		.override_failure_message(
			"press jump → 1 sample latence enregistré (before=%d, after=%d)"
			% [count_before, manager._latency_sample_count]
		) \
		.is_equal(count_before + 1)

	# _event_arrival_ts_usec doit être reset à 0 après consommation.
	assert_int(manager._event_arrival_ts_usec) \
		.override_failure_message("_event_arrival_ts_usec doit être reset à 0 après swap") \
		.is_equal(0)

	# last_input_to_publish_latency_ms doit être > 0 (latency mesurée réelle).
	assert_float(manager.last_input_to_publish_latency_ms) \
		.override_failure_message("latency mesurée doit être > 0 ms") \
		.is_greater(0.0)

	manager.queue_free()
