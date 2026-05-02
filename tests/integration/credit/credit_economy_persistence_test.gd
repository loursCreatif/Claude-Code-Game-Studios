# Tests integration Story-004 — CreditEconomy ↔ GSM ↔ SaveLoadSystem persistence.
# Couvre AC-CRD-22, 23, 24, 25, 26, 27, 30, 36, 37, 38.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration.
#
# GDD   : design/gdd/credit-economy-system.md (R-CRD-10/11/12, EC-CRD-8/13)
# Story : production/epics/credit-economy-system/story-004-persistence-boot-hydrate-quit-save.md
# ADR   : ADR-0010 (SaveLoad), ADR-0007 (GSM)

extends GdUnitTestSuite

# ---------------------------------------------------------------------------
# Setup / teardown — hermetic save file + reset state
# ---------------------------------------------------------------------------

var _emit_calls: Array[Array] = []


func _on_credits_changed_capture(total: int, delta: int, source: int) -> void:
	_emit_calls.append([total, delta, source])


func before_test() -> void:
	# Wipe the savegame so each test starts from a known absent state.
	# SaveLoadSystem reads `user://savegame.cfg` at boot ; subsequent
	# `save_int(...)` calls overwrite. Wipe via DirAccess.
	if FileAccess.file_exists("user://savegame.cfg"):
		DirAccess.remove_absolute("user://savegame.cfg")

	# Reset CreditEconomy state.
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false  # IMPORTANT : story-004 normal-flow boots fresh.
	CreditEconomy._credited_this_run.clear()
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false

	# Reset GSM to MENU baseline (default).
	GameStateManager._current_state = GameStateManager.State.MENU

	# Force SaveLoadSystem to reload its ConfigFile (fresh post-wipe).
	SaveLoadSystem._config = ConfigFile.new()
	SaveLoadSystem._config_loaded = true

	_emit_calls = []
	CreditEconomy.credits_changed.connect(_on_credits_changed_capture)


func after_test() -> void:
	if CreditEconomy.credits_changed.is_connected(_on_credits_changed_capture):
		CreditEconomy.credits_changed.disconnect(_on_credits_changed_capture)
	# Drain pending state for next suite cleanliness.
	CreditEconomy._pending_kill_delta = 0
	CreditEconomy._has_pending_kill = false
	# Wipe save residue.
	if FileAccess.file_exists("user://savegame.cfg"):
		DirAccess.remove_absolute("user://savegame.cfg")


# ---------------------------------------------------------------------------
# AC-CRD-22 — RESPAWNING transition does NOT reset _total_credits
# ---------------------------------------------------------------------------

func test_credit_economy_respawning_state_does_not_reset_total() -> void:
	CreditEconomy._total_credits = 42
	CreditEconomy._is_hydrated = true
	GameStateManager._current_state = GameStateManager.State.PLAYING

	# Simulate transition PLAYING → RESPAWNING via direct handler invoke.
	CreditEconomy._on_state_changed(GameStateManager.State.RESPAWNING)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-22: RESPAWNING must not reset total") \
		.is_equal(42)


# ---------------------------------------------------------------------------
# AC-CRD-23 — quit-to-menu writes save ; new session boot hydrates value
# ---------------------------------------------------------------------------

func test_credit_economy_quit_to_menu_persists_and_new_session_hydrates() -> void:
	# Session A : earn 42 credits + quit-to-menu.
	CreditEconomy._total_credits = 42
	CreditEconomy._is_hydrated = true
	CreditEconomy._on_state_changed(GameStateManager.State.MENU)  # triggers save

	# Verify save file written.
	assert_bool(FileAccess.file_exists("user://savegame.cfg")) \
		.override_failure_message("AC-CRD-23: save_int(MENU) must write savegame.cfg") \
		.is_true()

	# Session B : reset Credit + reload SaveLoad fresh.
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false
	SaveLoadSystem._config = ConfigFile.new()
	var load_err: int = SaveLoadSystem._config.load("user://savegame.cfg")
	assert_int(load_err).is_equal(OK)

	# Boot hydrate via state_changed(PLAYING).
	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-23: new session must hydrate to 42") \
		.is_equal(42)
	assert_bool(CreditEconomy._is_hydrated).is_true()


# ---------------------------------------------------------------------------
# AC-CRD-24 — first state_changed(PLAYING) → hydrate + emit (loaded, 0, BOOT_HYDRATE) once
# ---------------------------------------------------------------------------

func test_credit_economy_first_playing_emits_boot_hydrate_once() -> void:
	# Pre-seed savegame with total_credits=7.
	SaveLoadSystem.save_int("total_credits", 7)

	# Reset Credit state to fresh (already done in before_test).
	# First state_changed(PLAYING).
	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)

	assert_int(CreditEconomy._total_credits).is_equal(7)
	assert_bool(CreditEconomy._is_hydrated).is_true()
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-24: exactly 1 BOOT_HYDRATE emit") \
		.is_equal(1)
	assert_array(_emit_calls[0]) \
		.is_equal([7, 0, CreditEconomy.SourceKind.BOOT_HYDRATE])

	# Edge — 2nd state_changed(PLAYING) (depuis PAUSED) → no additional emit.
	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-24 edge: 2nd PLAYING must not re-emit BOOT_HYDRATE") \
		.is_equal(1)


# ---------------------------------------------------------------------------
# AC-CRD-25 — savegame absent → hydrate to 0, emit (0, 0, BOOT_HYDRATE), no crash
# ---------------------------------------------------------------------------

func test_credit_economy_absent_savegame_hydrates_to_zero() -> void:
	# Savegame already wiped by before_test. Verify.
	assert_bool(FileAccess.file_exists("user://savegame.cfg")) \
		.override_failure_message("Pre: save must be absent") \
		.is_false()

	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-25: absent save → default 0") \
		.is_equal(0)
	assert_bool(CreditEconomy._is_hydrated).is_true()
	assert_int(_emit_calls.size()).is_equal(1)
	assert_array(_emit_calls[0]) \
		.is_equal([0, 0, CreditEconomy.SourceKind.BOOT_HYDRATE])


# ---------------------------------------------------------------------------
# AC-CRD-26 — kills survive RESPAWNING → PLAYING cycle (progression preserved)
# ---------------------------------------------------------------------------

func test_credit_economy_progression_survives_respawn_cycle() -> void:
	CreditEconomy._total_credits = 30
	CreditEconomy._is_hydrated = true
	GameStateManager._current_state = GameStateManager.State.PLAYING

	# Simulate +5 kills (direct mutation — kill source itself tested in story-002).
	CreditEconomy._total_credits += 5
	assert_int(CreditEconomy._total_credits).is_equal(35)

	# Transition PLAYING → RESPAWNING → PLAYING.
	CreditEconomy._on_state_changed(GameStateManager.State.RESPAWNING)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("RESPAWNING must not reset") \
		.is_equal(35)

	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-26: PLAYING after respawn must not reset") \
		.is_equal(35)


# ---------------------------------------------------------------------------
# AC-CRD-27 — round-trip save/load preserves int value bit-for-bit
# ---------------------------------------------------------------------------

func test_credit_economy_round_trip_preserves_high_value() -> void:
	# Save high value.
	CreditEconomy._total_credits = 9_999_999
	CreditEconomy._is_hydrated = true
	CreditEconomy._on_state_changed(GameStateManager.State.MENU)  # persists

	# Reset + reload.
	CreditEconomy._total_credits = 0
	CreditEconomy._is_hydrated = false
	SaveLoadSystem._config = ConfigFile.new()
	SaveLoadSystem._config.load("user://savegame.cfg")

	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-27: round-trip 9_999_999 must be exact") \
		.is_equal(9_999_999)


# ---------------------------------------------------------------------------
# AC-CRD-30 — BOOT_HYDRATE delta is always 0 (regardless of loaded value)
# ---------------------------------------------------------------------------

func test_credit_economy_boot_hydrate_delta_is_always_zero() -> void:
	SaveLoadSystem.save_int("total_credits", 1234)

	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)

	assert_int(_emit_calls.size()).is_equal(1)
	var loaded: int = _emit_calls[0][0]
	var delta: int = _emit_calls[0][1]
	assert_int(loaded).is_equal(1234)
	assert_int(delta) \
		.override_failure_message("AC-CRD-30: BOOT_HYDRATE delta must be exactly 0, was %d" % delta) \
		.is_equal(0)


# ---------------------------------------------------------------------------
# AC-CRD-36 — PAUSED state ignores enemy_killed defensively
# ---------------------------------------------------------------------------

func test_credit_economy_paused_state_ignores_enemy_killed() -> void:
	CreditEconomy._total_credits = 10
	CreditEconomy._is_hydrated = true
	GameStateManager._current_state = GameStateManager.State.PAUSED

	# Defensive : émettre kill manuellement même si Enemy ne devrait jamais
	# émettre en PAUSED (get_tree().paused = true gèle _physics_process).
	var mock: Node = auto_free(Node.new())
	add_child(mock)
	CreditEconomy._on_enemy_killed(mock, Vector3.ZERO)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-36: PAUSED kill must not credit") \
		.is_equal(10)
	assert_int(_emit_calls.size()) \
		.override_failure_message("AC-CRD-36: 0 emit expected") \
		.is_equal(0)


# ---------------------------------------------------------------------------
# AC-CRD-37 — MENU initial state returns 0, MENU→PLAYING does not reset
# ---------------------------------------------------------------------------

func test_credit_economy_menu_initial_get_total_returns_zero_no_reset_on_playing() -> void:
	# Fresh state — _is_hydrated false, _total_credits 0.
	assert_int(CreditEconomy.get_total()).is_equal(0)

	# Pre-seed savegame value 17.
	SaveLoadSystem.save_int("total_credits", 17)

	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)

	assert_int(CreditEconomy.get_total()) \
		.override_failure_message("AC-CRD-37: PLAYING transition must hydrate to 17, not reset") \
		.is_equal(17)


# ---------------------------------------------------------------------------
# AC-CRD-38 — PLAYING → PAUSED → PLAYING leaves total unchanged
# ---------------------------------------------------------------------------

func test_credit_economy_pause_resume_cycle_preserves_total() -> void:
	CreditEconomy._total_credits = 17
	CreditEconomy._is_hydrated = true

	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)
	# Note : already hydrated → no-op on PLAYING.
	assert_int(CreditEconomy._total_credits).is_equal(17)

	CreditEconomy._on_state_changed(GameStateManager.State.PAUSED)
	assert_int(CreditEconomy._total_credits).is_equal(17)

	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)
	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-38: pause/resume cycle must preserve total") \
		.is_equal(17)


# ---------------------------------------------------------------------------
# AC-CRD-25 (corrupt path) — savegame fichier malformé → fallback default 0
# ---------------------------------------------------------------------------

## Couvre la branche "corrompu" de AC-CRD-25 (absent OR corrompu → 0).
## Le test "absent" couvre le path key-not-present (ConfigFile.get_value
## fallback). Ce test couvre le path **type mismatch** : la clé existe mais
## la valeur stockée n'est pas un int (e.g. String suite à édition manuelle
## du save ou format change). load_int doit retourner default + push_warning,
## et CreditEconomy hydrate à 0 sans crash. EC-CRD-8.
func test_credit_economy_corrupt_savegame_type_mismatch_hydrates_to_zero() -> void:
	# Écrire un savegame valide structurellement mais avec total_credits
	# stocké comme String au lieu d'int (corruption sémantique).
	var corrupt: ConfigFile = ConfigFile.new()
	corrupt.set_value("data", "total_credits", "garbage_not_an_int")
	var save_err: int = corrupt.save("user://savegame.cfg")
	assert_int(save_err).is_equal(OK)

	# Force SaveLoadSystem to reload the type-mismatched config.
	SaveLoadSystem._config = ConfigFile.new()
	var load_err: int = SaveLoadSystem._config.load("user://savegame.cfg")
	assert_int(load_err) \
		.override_failure_message("Pre: structurally valid cfg must load OK") \
		.is_equal(OK)
	SaveLoadSystem._config_loaded = true

	# load_int doit retourner default 0 (path typeof(value) != TYPE_INT).
	CreditEconomy._on_state_changed(GameStateManager.State.PLAYING)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("AC-CRD-25 corrupt: type mismatch must fallback to default 0") \
		.is_equal(0)
	assert_bool(CreditEconomy._is_hydrated).is_true()
	assert_int(_emit_calls.size()).is_equal(1)
	assert_array(_emit_calls[0]) \
		.is_equal([0, 0, CreditEconomy.SourceKind.BOOT_HYDRATE])


# ---------------------------------------------------------------------------
# BOSS_DEFEATED transition — explicit no-op (enum coverage)
# ---------------------------------------------------------------------------

## Verrou défensif : `_on_state_changed(BOSS_DEFEATED)` route via le `_:`
## fallback du match — no-op. Si un futur refactor casse le fallback (e.g.
## triggering save/hydrate on BOSS_DEFEATED), ce test catch la régression.
func test_credit_economy_boss_defeated_transition_is_no_op() -> void:
	CreditEconomy._total_credits = 99
	CreditEconomy._is_hydrated = true
	GameStateManager._current_state = GameStateManager.State.PLAYING

	CreditEconomy._on_state_changed(GameStateManager.State.BOSS_DEFEATED)

	assert_int(CreditEconomy._total_credits) \
		.override_failure_message("BOSS_DEFEATED must not mutate total") \
		.is_equal(99)
	assert_int(_emit_calls.size()) \
		.override_failure_message("BOSS_DEFEATED must not emit credits_changed") \
		.is_equal(0)
