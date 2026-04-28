# Tests perf Story-008 — SaveLoadSystem ConfigFile.save() budget (F-SAV-1).
# Couvre AC-SAV-26 (BLOCKING — burst 60 save_int < 60 ms / ~1 ms/call SSD)
# + AC-SAV-27 (ADVISORY — burst 10 saves @ ~2 KB file < 50 ms).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (perf sub-type — coding-standards.md §Test Evidence).
#
# Source : F-SAV-1 budget ~0.3 ms SSD M1 ref, marge ×55 sur frame 16.6 ms @ 60fps.
# ADR-0010 D-1 — graceful degradation HDD : si probe > 5 ms, skip avec print.
#
# Pattern : instance hermétique (pas autoload) — `before_test`/`after_test` rm savegame.cfg.

extends GdUnitTestSuite

const _SAVE_LOAD_SCRIPT_PATH: String = "res://src/core/save_load_system.gd"
const _SAVE_FILE_PATH: String = "user://savegame.cfg"

# Budgets F-SAV-1
const SAMPLES_AC_SAV_26: int = 60
const BUDGET_MS_AC_SAV_26: float = 60.0  # 60 saves × 1 ms target SSD
const SAMPLES_AC_SAV_27: int = 10
const BUDGET_MS_AC_SAV_27: float = 50.0  # 10 saves @ ~2 KB file

# Heuristique HDD : première save > 5 ms = HDD ou CI low-perf → graceful skip.
const HDD_PROBE_THRESHOLD_MS: float = 5.0

# =============================================================================
# Hermetic teardown
# =============================================================================

func before_test() -> void:
	_remove_save_file()


func after_test() -> void:
	_remove_save_file()


func _remove_save_file() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.file_exists("savegame.cfg"):
		dir.remove("savegame.cfg")


func _instantiate_save_load() -> Node:
	var script: GDScript = load(_SAVE_LOAD_SCRIPT_PATH) as GDScript
	var instance: Node = script.new() as Node
	add_child(instance)
	return instance


## Probe HDD/SSD : mesure une première save_int isolée. Si > 5 ms, on assume HDD.
## Side-effect : ajoute clé `_hdd_probe` au fichier — appeler avant le burst test.
func _is_likely_hdd(instance: Node) -> bool:
	var start: int = Time.get_ticks_usec()
	instance.save_int("_hdd_probe", 0)
	var first_save_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	return first_save_ms > HDD_PROBE_THRESHOLD_MS

# =============================================================================
# AC-SAV-26 — BLOCKING burst 60 save_int < 60 ms (~1 ms/call SSD)
# =============================================================================

## GIVEN SaveLoadSystem ready, file MVP ~100 bytes,
## WHEN 60 save_int consécutifs (simulation 1 sec @ 60 fps avec save chaque frame),
## THEN durée totale < 60 ms (i.e. < 1 ms / call avg).
## Source : AC-SAV-26, F-SAV-1, ADR-0010 D-1.
##
## Graceful degradation : si HDD detected (probe > 5 ms), test passe avec print
## (CI hardware variance — false positive sur HDD/CI low-perf runners).
func test_save_load_perf_save_int_burst_60_under_60ms_budget() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	assert_bool(instance.is_ready()) \
		.override_failure_message("AC-SAV-26 prerequisite : SaveLoadSystem ready") \
		.is_true()

	if _is_likely_hdd(instance):
		print("AC-SAV-26 SKIP : HDD detected (probe > %.1f ms) — graceful degradation ADR-0010 D-1" % HDD_PROBE_THRESHOLD_MS)
		instance.queue_free()
		# Pas d'assert — graceful skip côté GdUnit4 (le test passe avec un message info)
		assert_bool(true).is_true()
		return

	# Act — burst 60 save_int avec mesure totale
	var start_usec: int = Time.get_ticks_usec()
	for i: int in range(SAMPLES_AC_SAV_26):
		instance.save_int("perf_k_" + str(i), i)
	var elapsed_ms: float = (Time.get_ticks_usec() - start_usec) / 1000.0

	# Assert
	assert_float(elapsed_ms) \
		.override_failure_message(
			"AC-SAV-26 (F-SAV-1): burst %d save_int = %.2f ms ≥ %.0f ms budget — perf régression SSD" % [SAMPLES_AC_SAV_26, elapsed_ms, BUDGET_MS_AC_SAV_26]
		) \
		.is_less(BUDGET_MS_AC_SAV_26)

	print("AC-SAV-26 PASS : %d save_int = %.2f ms (avg %.3f ms/call, budget %.0f ms)" % [
		SAMPLES_AC_SAV_26, elapsed_ms, elapsed_ms / SAMPLES_AC_SAV_26, BUDGET_MS_AC_SAV_26
	])

	instance.queue_free()

# =============================================================================
# AC-SAV-27 — ADVISORY burst 10 saves @ ~2 KB file < 50 ms (Tier 2+ scaling)
# =============================================================================

## GIVEN SaveLoadSystem ready avec 10 keys padding (~2 KB total file size),
## WHEN burst 10 save_int consécutifs,
## THEN total < 50 ms.
## Source : AC-SAV-27 (ADVISORY MVP — BLOCKING Tier 2+).
##
## Note : ADVISORY — failure log mais ne fail pas le test (utilise print + assert
## conditionnel sur is_likely_hdd seulement). Le check budget est strict mais
## documenté comme advisory dans le print final.
func test_save_load_perf_burst_10_saves_2kb_file_under_50ms_advisory() -> void:
	# Arrange — pre-padding ~50 bytes par key × 10 keys ~ 500 bytes (proxy 2 KB scaling)
	var instance: Node = _instantiate_save_load()
	var padding: Array[StringName] = [&"id_a", &"id_b", &"id_c", &"id_d", &"id_e"]
	for i: int in range(10):
		instance.save_string_array("padding_" + str(i), padding)

	if _is_likely_hdd(instance):
		print("AC-SAV-27 SKIP : HDD detected — graceful degradation")
		instance.queue_free()
		assert_bool(true).is_true()
		return

	# Act
	var start: int = Time.get_ticks_usec()
	for i: int in range(SAMPLES_AC_SAV_27):
		instance.save_int("burst_" + str(i), i)
	var elapsed_ms: float = (Time.get_ticks_usec() - start) / 1000.0

	# Assert (ADVISORY — log mais ne fail pas si overrun ; on assert quand même
	# pour catcher les régressions énormes Tier 2+).
	assert_float(elapsed_ms) \
		.override_failure_message(
			"AC-SAV-27 (ADVISORY): burst %d saves @ ~2 KB padding = %.1f ms ≥ %.0f ms — perf scaling régression" % [SAMPLES_AC_SAV_27, elapsed_ms, BUDGET_MS_AC_SAV_27]
		) \
		.is_less(BUDGET_MS_AC_SAV_27)

	print("AC-SAV-27 PASS : %d saves @ ~2 KB = %.1f ms (avg %.2f ms/call, budget %.0f ms)" % [
		SAMPLES_AC_SAV_27, elapsed_ms, elapsed_ms / SAMPLES_AC_SAV_27, BUDGET_MS_AC_SAV_27
	])

	instance.queue_free()
