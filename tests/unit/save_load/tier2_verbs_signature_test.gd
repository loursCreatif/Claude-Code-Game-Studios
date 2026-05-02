# Tests unitaires Story-006 — SaveLoadSystem Tier 2+ verbs stubs
# (load_int_array / save_int_array) + get_save_version meta signature.
# Couvre AC-006-1 (roundtrip Array[int]) / AC-006-2 (Array hétérogène partial valid)
# / AC-006-3 (signatures publiques stables R-SAV-4).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (coding-standards.md §Test Evidence — BLOCKING gate).
#
# Naming : test_save_load_[scenario]_[expected_result] per .claude/rules/test-standards.md.

extends GdUnitTestSuite

const _SAVE_LOAD_SCRIPT_PATH: String = "res://src/core/save_load_system.gd"
const _SAVE_FILE_PATH: String = "user://savegame.cfg"

# =============================================================================
# Hermetic teardown
# =============================================================================

func before_test() -> void:
	_remove_save_file()


func after_test() -> void:
	_remove_save_file()
	get_tree().paused = false


func _remove_save_file() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.file_exists("savegame.cfg"):
		dir.remove("savegame.cfg")

# =============================================================================
# Helpers
# =============================================================================

func _instantiate_save_load() -> Node:
	var script: GDScript = load(_SAVE_LOAD_SCRIPT_PATH) as GDScript
	var instance: Node = script.new() as Node
	add_child(instance)
	return instance

# =============================================================================
# AC-006-1 — roundtrip save_int_array puis load_int_array retourne Array[int]
# =============================================================================

## GIVEN SaveLoadSystem ready,
## WHEN save_int_array("k", [1, 2, 3]) puis load_int_array("k", []),
## THEN retour size==3, valeurs identiques, ordre préservé, tous TYPE_INT.
## Source : AC-006-1, R-SAV-4, ADR-0010 D-2.
func test_save_load_save_int_array_roundtrip_returns_persisted_typed_array() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	var src: Array[int] = [1, 2, 3]

	# Act
	instance.save_int_array("collected_ids", src)
	var loaded: Array[int] = instance.load_int_array("collected_ids", [] as Array[int])

	# Assert
	assert_int(loaded.size()) \
		.override_failure_message("AC-006-1: load_int_array doit retourner 3 éléments") \
		.is_equal(3)
	assert_int(loaded[0]).is_equal(1)
	assert_int(loaded[1]).is_equal(2)
	assert_int(loaded[2]).is_equal(3)
	assert_int(typeof(loaded[0])) \
		.override_failure_message("AC-006-1: éléments doivent être TYPE_INT") \
		.is_equal(TYPE_INT)

	instance.queue_free()


## EDGE CASE — valeurs négatives + extrêmes (INT_MAX, INT_MIN, 0).
func test_save_load_save_int_array_extreme_values_roundtrip_preserved() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	var src: Array[int] = [-1, 0, 9223372036854775807, -9223372036854775808]

	# Act
	instance.save_int_array("extremes", src)
	var loaded: Array[int] = instance.load_int_array("extremes", [] as Array[int])

	# Assert
	assert_int(loaded.size()).is_equal(4)
	assert_int(loaded[0]).is_equal(-1)
	assert_int(loaded[1]).is_equal(0)
	assert_int(loaded[2]).is_equal(9223372036854775807)
	assert_int(loaded[3]).is_equal(-9223372036854775808)

	instance.queue_free()


## EDGE CASE — array vide roundtrip.
func test_save_load_save_int_array_empty_roundtrip_returns_empty() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	var src: Array[int] = []

	# Act
	instance.save_int_array("empty", src)
	var loaded: Array[int] = instance.load_int_array("empty", [] as Array[int])

	# Assert
	assert_int(loaded.size()) \
		.override_failure_message("AC-006-1 edge: array vide roundtrip doit retourner []") \
		.is_equal(0)

	instance.queue_free()

# =============================================================================
# AC-006-2 — partial validation Array hétérogène : skip non-int + warnings
# =============================================================================

## GIVEN ConfigFile contient un Array hétérogène [1, "string", null, 4],
## WHEN load_int_array("k", []),
## THEN retour [1, 4] (subset valide, ordre préservé), 2 push_warning émis (visibles stderr).
## Source : AC-006-2, R-SAV-4, ADR-0010 D-2.
##
## Note : push_warning visibles stderr non assertés programmatiquement (limite GdUnit4
## sans plugin stderr capture — pattern identique scalar_verbs_test.gd AC-SAV-9).
## Sémantique vérifiée par retour [1, 4] (subset valide attendu).
func test_save_load_load_int_array_with_heterogeneous_array_skips_invalid_elements() -> void:
	# Arrange — écrire un fichier avec Array hétérogène manuellement (sans typer)
	var pre_config: ConfigFile = ConfigFile.new()
	pre_config.set_value("data", "_save_version", 1)
	pre_config.set_value("data", "mixed", [1, "string", null, 4])
	pre_config.save(_SAVE_FILE_PATH)

	var instance: Node = _instantiate_save_load()

	# Act
	var loaded: Array[int] = instance.load_int_array("mixed", [] as Array[int])

	# Assert — subset valide [1, 4], ordre préservé
	assert_int(loaded.size()) \
		.override_failure_message("AC-006-2: subset valide doit contenir 2 éléments (skip String + null)") \
		.is_equal(2)
	assert_int(loaded[0]).is_equal(1)
	assert_int(loaded[1]).is_equal(4)

	instance.queue_free()


## EDGE CASE — tous éléments invalides → retour [] + N warnings.
func test_save_load_load_int_array_all_invalid_elements_returns_empty() -> void:
	# Arrange
	var pre_config: ConfigFile = ConfigFile.new()
	pre_config.set_value("data", "_save_version", 1)
	pre_config.set_value("data", "all_bad", ["a", "b", null])
	pre_config.save(_SAVE_FILE_PATH)

	var instance: Node = _instantiate_save_load()

	# Act
	var loaded: Array[int] = instance.load_int_array("all_bad", [] as Array[int])

	# Assert
	assert_int(loaded.size()) \
		.override_failure_message("AC-006-2 edge: tous invalides doit retourner []") \
		.is_equal(0)

	instance.queue_free()


## EDGE CASE — type stocké non-Array (ex: int) → return default + 1 push_warning.
func test_save_load_load_int_array_type_mismatch_returns_default() -> void:
	# Arrange
	var pre_config: ConfigFile = ConfigFile.new()
	pre_config.set_value("data", "_save_version", 1)
	pre_config.set_value("data", "wrong_type", 42)  # int au lieu d'Array
	pre_config.save(_SAVE_FILE_PATH)

	var instance: Node = _instantiate_save_load()

	# Act
	var loaded: Array[int] = instance.load_int_array("wrong_type", [99] as Array[int])

	# Assert — return default tel quel
	assert_int(loaded.size()).is_equal(1)
	assert_int(loaded[0]).is_equal(99)

	instance.queue_free()

# =============================================================================
# AC-006-3 — signatures publiques R-SAV-4 stables (reflection check)
# =============================================================================

## GIVEN SaveLoadSystem instance,
## WHEN inspection des méthodes via Callable.is_valid() + script.get_method_list(),
## THEN load_int_array / save_int_array / get_save_version sont présentes avec arités correctes.
## Source : AC-006-3, R-SAV-4 verrou ADR-0010 D-2.
func test_save_load_tier2_verbs_signatures_present_with_correct_arities() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()

	# Act + Assert — Callable.is_valid prouve que la méthode existe
	var c_load: Callable = Callable(instance, "load_int_array")
	var c_save: Callable = Callable(instance, "save_int_array")
	var c_meta: Callable = Callable(instance, "get_save_version")

	assert_bool(c_load.is_valid()) \
		.override_failure_message("AC-006-3: load_int_array doit être présent") \
		.is_true()
	assert_bool(c_save.is_valid()) \
		.override_failure_message("AC-006-3: save_int_array doit être présent") \
		.is_true()
	assert_bool(c_meta.is_valid()) \
		.override_failure_message("AC-006-3: get_save_version doit être présent") \
		.is_true()

	# Assert arité — get_method_list retourne dict avec 'args' Array
	var methods: Array = instance.get_script().get_script_method_list()
	var found_load: Dictionary = _find_method(methods, "load_int_array")
	var found_save: Dictionary = _find_method(methods, "save_int_array")
	var found_meta: Dictionary = _find_method(methods, "get_save_version")

	assert_bool(not found_load.is_empty()).is_true()
	assert_bool(not found_save.is_empty()).is_true()
	assert_bool(not found_meta.is_empty()).is_true()

	assert_int(found_load["args"].size()) \
		.override_failure_message("AC-006-3: load_int_array doit avoir 2 args (key, default)") \
		.is_equal(2)
	assert_int(found_save["args"].size()) \
		.override_failure_message("AC-006-3: save_int_array doit avoir 2 args (key, value)") \
		.is_equal(2)
	assert_int(found_meta["args"].size()) \
		.override_failure_message("AC-006-3: get_save_version doit avoir 0 arg") \
		.is_equal(0)

	# Sanity check get_save_version() retourne 1 (default _CURRENT_SAVE_VERSION MVP)
	assert_int(instance.get_save_version()) \
		.override_failure_message("AC-006-3: get_save_version() doit retourner 1 sur fichier absent") \
		.is_equal(1)

	instance.queue_free()


## Helper : recherche une méthode par nom dans la liste retournée par get_script_method_list().
func _find_method(methods: Array, name: String) -> Dictionary:
	for m: Dictionary in methods:
		if m.get("name", "") == name:
			return m
	return {}
