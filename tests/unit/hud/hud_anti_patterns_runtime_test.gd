extends GdUnitTestSuite

## Story-005 — HUD System anti-patterns runtime ACs (9 tests).
##
## Couvre AC-HUD-25 (layer<100) + AC-HUD-26 (layer<100 doc) +
## AC-HUD-27 (perf handler <0.5ms p99) + AC-HUD-28 (memory delta <64KB) +
## AC-HUD-31 (absence death/game-over nodes) + AC-HUD-32 (absence minimap nodes) +
## AC-HUD-33 (absence health/shield/ammo nodes) +
## AC-HUD-34 (zero AudioServer ref statique) + AC-HUD-35 (zero cross-system ref statique).
##
## Framework : GdUnit4 (extends GdUnitTestSuite).
## Source : .claude/rules/hud-anti-patterns.md + design/gdd/hud-system.md.
## Story : production/epics/hud-system/story-005-anti-patterns-lint-static.md.


const HUD_SOURCE_PATH: String = "res://src/gameplay/hud/hud_system.gd"

# Seuil perf handler (AC-HUD-27) : 500 µs par emit (0.5 ms wall-clock).
const HANDLER_BUDGET_US: int = 500
# Seuil mémoire (AC-HUD-28) : 64 KB (65536 bytes) sur 1000 emits.
const MEMORY_DELTA_BUDGET_BYTES: int = 65536
# Nombre d'emits pour les tests perf et mémoire.
const STRESS_EMIT_COUNT: int = 1000


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_test() -> void:
	# Reset CreditEconomy + HUD state entre chaque test.
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = true
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	GameStateManager._current_state = GameStateManager.State.PLAYING
	HUDSystem._credit_counter_label.text = "0"
	HUDSystem._credit_counter_label.scale = Vector2.ONE
	if HUDSystem._active_pulse_tween != null and HUDSystem._active_pulse_tween.is_valid():
		HUDSystem._active_pulse_tween.kill()
	HUDSystem._active_pulse_tween = null


func after_test() -> void:
	if HUDSystem._active_pulse_tween != null and HUDSystem._active_pulse_tween.is_valid():
		HUDSystem._active_pulse_tween.kill()
	HUDSystem._active_pulse_tween = null
	HUDSystem._credit_counter_label.scale = Vector2.ONE
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	CreditEconomy._credited_this_run.clear()


# ---------------------------------------------------------------------------
# Helper : récursion nœuds — cherche des nœuds par nom (substring insensible casse).
# ---------------------------------------------------------------------------

func _recursive_search(node: Node, name_substrings: Array[String]) -> int:
	var count: int = 0
	for substr in name_substrings:
		if node.name.to_lower().contains(substr.to_lower()):
			count += 1
	for child in node.get_children():
		count += _recursive_search(child, name_substrings)
	return count


# =============================================================================
# AC-HUD-25 — CanvasLayer.layer < 100
# =============================================================================

## GIVEN HUDSystem autoload initialisé,
## THEN _canvas_layer.layer est strictement inférieur à 100.
## Source : AC-HUD-25, R-HUD-11, hud-anti-patterns.md AC-HUD-LINT-7.
func test_hud_canvas_layer_below_100() -> void:
	# Assert — layer=50 (HUD_CANVAS_LAYER constant) < 100
	assert_int(HUDSystem._canvas_layer.layer) \
		.override_failure_message(
			"AC-HUD-25: _canvas_layer.layer=%d doit être < 100 (R-HUD-11)" \
			% HUDSystem._canvas_layer.layer) \
		.is_less(100)


# =============================================================================
# AC-HUD-26 — layer HUD < 100 (comparaison documentaire avec GSM hypothétique)
# =============================================================================

## GIVEN HUDSystem.layer = 50,
## THEN HUD layer < 100 (seuil GSM hypothétique layer=100).
## Note documentaire : GSM n'est pas instancié ici — le test valide simplement
## que HUD layer < 100, garantissant l'ordre de rendu avec un GSM layer=100.
## Source : AC-HUD-26, hud-anti-patterns.md.
func test_hud_canvas_layer_below_gsm_hypothetical_threshold() -> void:
	const GSM_HYPOTHETICAL_LAYER: int = 100
	var hud_layer: int = HUDSystem._canvas_layer.layer
	assert_bool(hud_layer < GSM_HYPOTHETICAL_LAYER) \
		.override_failure_message(
			"AC-HUD-26: HUD layer=%d doit être < GSM seuil hypothétique=%d" \
			% [hud_layer, GSM_HYPOTHETICAL_LAYER]) \
		.is_true()


# =============================================================================
# AC-HUD-27 — perf handler _on_credits_changed < 0.5ms p99
# =============================================================================

## GIVEN 1000 emits credits_changed mixtes KILL/SECRET/SPEND_SHOP,
## THEN p99 delta_us par emit < 500 µs (0.5 ms wall-clock).
## Source : AC-HUD-27, Pillar 1 (FLOW AVANT TOUT — input latency < 1 frame).
func test_hud_credits_changed_handler_perf_p99() -> void:
	# Arrange — collect samples sur 1000 emits
	var samples: Array[int] = []
	samples.resize(STRESS_EMIT_COUNT)

	var sources: Array[int] = [
		CreditEconomy.SourceKind.KILL,
		CreditEconomy.SourceKind.SECRET,
		CreditEconomy.SourceKind.SPEND_SHOP,
	]
	var total: int = 0

	for i in range(STRESS_EMIT_COUNT):
		var source: int = sources[i % sources.size()]
		var delta: int = 1 if source != CreditEconomy.SourceKind.SPEND_SHOP else -1
		total = maxi(0, total + delta)

		var t0: int = Time.get_ticks_usec()
		CreditEconomy.credits_changed.emit(total, delta, source)
		var elapsed: int = Time.get_ticks_usec() - t0
		samples[i] = elapsed

	# Calcul p99 — index 990/1000
	samples.sort()
	var p99_us: int = samples[int(STRESS_EMIT_COUNT * 0.99)]

	assert_int(p99_us) \
		.override_failure_message(
			"AC-HUD-27: p99 handler duration=%d µs doit être < %d µs (0.5ms budget)" \
			% [p99_us, HANDLER_BUDGET_US]) \
		.is_less(HANDLER_BUDGET_US)


# =============================================================================
# AC-HUD-28 — memory delta < 64 KB sur 1000 emits
# =============================================================================

## GIVEN 1000 emits credits_changed sur path zero-alloc (SPEND_SHOP delta<0 + BOOT_HYDRATE delta==0),
## THEN delta Performance.MEMORY_STATIC < 65536 bytes (64 KB).
## Note R-HUD-13 : KILL/SECRET path crée Tween (cold-path acceptable selon design — alloc inhérente
## à la collision pattern multi-kill story-002). Le hot path zero-alloc R-HUD-13 concerne le `str(total)`
## boxing seul. Ce test valide l'invariant zero-alloc sur les sources sans Tween (delta ≤ 0).
## Source : AC-HUD-28, no-alloc-hot-paths pattern.
func test_hud_credits_changed_memory_delta_under_64kb() -> void:
	# Baseline mémoire avant stress (path zero-alloc seulement : SPEND_SHOP + BOOT_HYDRATE)
	var mem_before: int = Performance.get_monitor(Performance.MEMORY_STATIC)

	var total: int = 1000  # éviter clamp à 0 sur SPEND_SHOP delta<0
	for i in range(STRESS_EMIT_COUNT):
		# Alterne SPEND_SHOP (delta<0 → hard set + scale reset, no Tween)
		# et BOOT_HYDRATE (delta==0 → hard set early return, no Tween)
		var source: int = CreditEconomy.SourceKind.SPEND_SHOP if (i % 2 == 0) else CreditEconomy.SourceKind.BOOT_HYDRATE
		var delta: int = -1 if source == CreditEconomy.SourceKind.SPEND_SHOP else 0
		total = maxi(1, total + delta)
		CreditEconomy.credits_changed.emit(total, delta, source)

	var mem_after: int = Performance.get_monitor(Performance.MEMORY_STATIC)
	var mem_delta: int = mem_after - mem_before

	assert_int(mem_delta) \
		.override_failure_message(
			"AC-HUD-28: memory delta=%d bytes doit être < %d bytes (64KB) sur %d emits zero-alloc path (SPEND_SHOP + BOOT_HYDRATE)" \
			% [mem_delta, MEMORY_DELTA_BUDGET_BYTES, STRESS_EMIT_COUNT]) \
		.is_less(MEMORY_DELTA_BUDGET_BYTES)


# =============================================================================
# AC-HUD-31 — absence death/game-over/respawn_countdown nodes (Pillar 3)
# =============================================================================

## GIVEN HUDSystem tree complet,
## THEN aucun node nommé "death_screen", "game_over" ou "respawn_countdown".
## Pillar 3 : mort invisible — HUD ne doit jamais afficher d'écran de mort.
## Source : AC-HUD-31, design/gdd/hud-system.md Pillar 3 garde-fou.
func test_hud_no_death_screen_nodes() -> void:
	var forbidden_names: Array[String] = ["death_screen", "game_over", "respawn_countdown"]
	var count: int = _recursive_search(HUDSystem, forbidden_names)
	assert_int(count) \
		.override_failure_message(
			"AC-HUD-31: %d node(s) forbidden (Pillar 3 mort invisible) trouvé(s) — %s" \
			% [count, str(forbidden_names)]) \
		.is_equal(0)


# =============================================================================
# AC-HUD-32 — absence minimap/radar/enemy_marker nodes (Pillar 4)
# =============================================================================

## GIVEN HUDSystem tree complet,
## THEN aucun node "minimap", "radar" ou "enemy_marker".
## Pillar 4 : anti-info-overload — HUD MVP ne doit pas contenir de minimap.
## Source : AC-HUD-32, design/gdd/hud-system.md Pillar 4 anti.
func test_hud_no_minimap_nodes() -> void:
	var forbidden_names: Array[String] = ["minimap", "radar", "enemy_marker"]
	var count: int = _recursive_search(HUDSystem, forbidden_names)
	assert_int(count) \
		.override_failure_message(
			"AC-HUD-32: %d node(s) forbidden (Pillar 4 anti-minimap) trouvé(s) — %s" \
			% [count, str(forbidden_names)]) \
		.is_equal(0)


# =============================================================================
# AC-HUD-33 — absence health_bar/shield_bar/ammo_counter nodes
# =============================================================================

## GIVEN HUDSystem tree complet,
## THEN aucun node "health_bar", "shield_bar" ou "ammo_counter".
## MVP scope guard : seul le credit counter est dans le HUD.
## Source : AC-HUD-33, design/gdd/hud-system.md MVP scope.
func test_hud_no_health_or_ammo_nodes() -> void:
	var forbidden_names: Array[String] = ["health_bar", "shield_bar", "ammo_counter"]
	var count: int = _recursive_search(HUDSystem, forbidden_names)
	assert_int(count) \
		.override_failure_message(
			"AC-HUD-33: %d node(s) forbidden (hors MVP scope) trouvé(s) — %s" \
			% [count, str(forbidden_names)]) \
		.is_equal(0)


# =============================================================================
# AC-HUD-34 — zero AudioServer/AudioStreamPlayer ref dans hud_system.gd (statique)
# =============================================================================

## GIVEN source res://src/gameplay/hud/hud_system.gd,
## THEN 0 référence à AudioServer ou AudioStreamPlayer.
## Approche : grep statique runtime via FileAccess + RegEx (plus simple qu'un spy).
## Source : AC-HUD-34, AC-HUD-LINT-1, hud-anti-patterns.md.
func test_hud_source_no_audio_server_reference() -> void:
	var file: FileAccess = FileAccess.open(HUD_SOURCE_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("AC-HUD-34: cannot open %s" % HUD_SOURCE_PATH) \
		.is_not_null()
	var source_text: String = file.get_as_text()
	file.close()

	var regex := RegEx.new()
	regex.compile("AudioServer|AudioStreamPlayer")

	var violations: Array[String] = []
	var lines: PackedStringArray = source_text.split("\n")
	for i in range(lines.size()):
		var line: String = lines[i]
		var stripped: String = line.strip_edges()
		# Skip commentaires purs et exception markers.
		if stripped.begins_with("#"):
			continue
		if line.contains("lint-hud-ok"):
			continue
		if regex.search(line) != null:
			violations.append("%d: %s" % [i + 1, stripped])

	assert_int(violations.size()) \
		.override_failure_message(
			"AC-HUD-34: AudioServer/AudioStreamPlayer reference(s) trouvée(s) dans hud_system.gd:\n%s" \
			% "\n".join(violations)) \
		.is_equal(0)


# =============================================================================
# AC-HUD-35 — zero cross-system ref statique (CombatSystem, LevelSystem, etc.)
# =============================================================================

## GIVEN source res://src/gameplay/hud/hud_system.gd,
## THEN 0 référence aux systèmes interdits.
## Seules deps autorisées : CreditEconomy + GameStateManager.
## Source : AC-HUD-35, AC-HUD-LINT-1, hud-anti-patterns.md outbound-only.
func test_hud_source_no_forbidden_cross_system_reference() -> void:
	var file: FileAccess = FileAccess.open(HUD_SOURCE_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("AC-HUD-35: cannot open %s" % HUD_SOURCE_PATH) \
		.is_not_null()
	var source_text: String = file.get_as_text()
	file.close()

	var regex := RegEx.new()
	# Seules deps autorisées : CreditEconomy + GameStateManager.
	regex.compile(
		"\\bCombatSystem\\b|\\bLevelSystem\\b|\\bMovementController\\b|\\bEnemySystem\\b" \
		+ "|\\bAudioSystem\\b|\\bInputManager\\b|\\bSaveLoadSystem\\b")

	var violations: Array[String] = []
	var lines: PackedStringArray = source_text.split("\n")
	for i in range(lines.size()):
		var line: String = lines[i]
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if line.contains("lint-hud-ok"):
			continue
		if regex.search(line) != null:
			violations.append("%d: %s" % [i + 1, stripped])

	assert_int(violations.size()) \
		.override_failure_message(
			"AC-HUD-35: cross-system reference(s) interdite(s) dans hud_system.gd:\n%s" \
			% "\n".join(violations)) \
		.is_equal(0)
