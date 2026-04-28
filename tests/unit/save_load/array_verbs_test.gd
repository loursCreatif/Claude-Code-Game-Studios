# Tests unitaires Story-003 — SaveLoadSystem array verbs load_string_array / save_string_array
# + String→StringName normalization (R-SAV-12).
# Couvre AC-SAV-10 / AC-SAV-11 / AC-SAV-12 / AC-SAV-13 / AC-SAV-14.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (coding-standards.md §Test Evidence — BLOCKING gate).
#
# Naming : test_save_load_[scenario]_[expected_result] per .claude/rules/test-standards.md.

extends GdUnitTestSuite

const _SAVE_LOAD_SCRIPT_PATH: String = "res://src/core/save_load_system.gd"
const _SAVE_FILE_PATH: String = "user://savegame.cfg"

# =============================================================================
# Hermetic teardown — garantit qu'aucun fichier savegame.cfg ne pollue le run
# =============================================================================

func before_test() -> void:
	_remove_save_file()


func after_test() -> void:
	_remove_save_file()
	get_tree().paused = false  # safety si test fail mid-pause


func _remove_save_file() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.file_exists("savegame.cfg"):
		dir.remove("savegame.cfg")

# =============================================================================
# Helpers
# =============================================================================

## Instancie un SaveLoadSystem frais et l'ajoute au scene tree (déclenche _ready()).
## Utiliser à la place du singleton autoload pour garantir l'isolation hermétique.
func _instantiate_save_load() -> Node:
	var script: GDScript = load(_SAVE_LOAD_SCRIPT_PATH) as GDScript
	var instance: Node = script.new() as Node
	add_child(instance)  # déclenche _ready()
	return instance

# =============================================================================
# AC-SAV-10 — roundtrip save_string_array puis load retourne typed Array[StringName]
# =============================================================================

## GIVEN SaveLoadSystem instancié (_config_loaded == true),
## WHEN save_string_array("upg", [&"double_jump", &"dash_horizontal"])
##      puis load_string_array("upg", []),
## THEN retour Array[StringName] size=2, éléments &"double_jump" et &"dash_horizontal", tous TYPE_STRING_NAME.
## Source : AC-SAV-10, ADR-0010 D-2, R-SAV-12.
func test_save_load_save_string_array_then_load_returns_typed_array() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	var input: Array[StringName] = [&"double_jump", &"dash_horizontal"]
	var empty_default: Array[StringName] = []

	# Act
	instance.save_string_array("upg", input)
	var result: Array[StringName] = instance.load_string_array("upg", empty_default)

	# Assert
	assert_int(result.size()) \
		.override_failure_message("AC-SAV-10: load_string_array doit retourner 2 éléments") \
		.is_equal(2)
	assert_int(typeof(result[0])) \
		.override_failure_message("AC-SAV-10: result[0] doit être TYPE_STRING_NAME") \
		.is_equal(TYPE_STRING_NAME)
	assert_int(typeof(result[1])) \
		.override_failure_message("AC-SAV-10: result[1] doit être TYPE_STRING_NAME") \
		.is_equal(TYPE_STRING_NAME)
	assert_str(String(result[0])) \
		.override_failure_message("AC-SAV-10: result[0] doit valoir &'double_jump'") \
		.is_equal("double_jump")
	assert_str(String(result[1])) \
		.override_failure_message("AC-SAV-10: result[1] doit valoir &'dash_horizontal'") \
		.is_equal("dash_horizontal")

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-11 — array vide saved → load retourne [] (pas null, pas le default)
# =============================================================================

## GIVEN SaveLoadSystem instancié,
## WHEN save_string_array("empty_key", []) puis load_string_array("empty_key", [&"fallback"]),
## THEN retour [] (array vide persisté — pas le default [&"fallback"]).
## Source : AC-SAV-11, ADR-0010 D-2.
func test_save_load_save_empty_array_then_load_returns_empty_not_default() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	var saved: Array[StringName] = []
	var fallback: Array[StringName] = [&"fallback"]

	# Act
	instance.save_string_array("empty_key", saved)
	var result: Array[StringName] = instance.load_string_array("empty_key", fallback)

	# Assert
	assert_int(result.size()) \
		.override_failure_message("AC-SAV-11: load_string_array d'un array vide doit retourner [] (size=0), pas le default") \
		.is_equal(0)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-12 — type mismatch int stocké → default retourné + push_warning
# =============================================================================

## GIVEN clé "k" stockée avec valeur int=42 (corruption simulée via injection seam _config),
## WHEN load_string_array("k", []),
## THEN retour [] (default) — type mismatch int != Array détecté.
## Note : push_warning non asserté (GdUnit4 sans plugin spécialisé) — retour default suffit pour AC-SAV-12.
## Source : AC-SAV-12, R-SAV-6, ADR-0010 D-2.
func test_save_load_load_string_array_type_mismatch_int_returns_default() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	# Injection seam : accès direct à _config pour simuler corruption de type (int au lieu d'Array)
	instance._config.set_value("data", "k", 42)
	var empty_default: Array[StringName] = []

	# Act
	var result: Array[StringName] = instance.load_string_array("k", empty_default)

	# Assert
	assert_int(result.size()) \
		.override_failure_message("AC-SAV-12: load_string_array avec int stocké doit retourner [] (default), pas crasher") \
		.is_equal(0)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-13 — array hétérogène [StringName, int, null, String] → 2 éléments valides
# =============================================================================

## GIVEN clé "mixed" stockée avec Array[&"valid_a", 42, null, "string_b"] (injection seam),
## WHEN load_string_array("mixed", []),
## THEN retour [&"valid_a", &"string_b"] (size=2) — int et null ignorés avec push_warning,
##      String "string_b" normalisé en StringName (R-SAV-12). Couvre Shop EC-SHP-7.
## Source : AC-SAV-13, R-SAV-12, ADR-0010 D-2.
func test_save_load_load_string_array_heterogeneous_skips_invalid_normalizes_string() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	# Injection seam : array hétérogène avec types mixtes
	instance._config.set_value("data", "mixed", [&"valid_a", 42, null, "string_b"])
	var empty_default: Array[StringName] = []

	# Act
	var result: Array[StringName] = instance.load_string_array("mixed", empty_default)

	# Assert — size=2 : &"valid_a" (StringName OK) + &"string_b" (String→StringName normalisé)
	assert_int(result.size()) \
		.override_failure_message("AC-SAV-13: array hétérogène doit retourner 2 éléments valides (int et null ignorés)") \
		.is_equal(2)
	assert_str(String(result[0])) \
		.override_failure_message("AC-SAV-13: result[0] doit valoir &'valid_a' (StringName préservé)") \
		.is_equal("valid_a")
	assert_int(typeof(result[0])) \
		.override_failure_message("AC-SAV-13: result[0] doit être TYPE_STRING_NAME") \
		.is_equal(TYPE_STRING_NAME)
	assert_str(String(result[1])) \
		.override_failure_message("AC-SAV-13: result[1] doit valoir &'string_b' (String normalisé en StringName)") \
		.is_equal("string_b")
	assert_int(typeof(result[1])) \
		.override_failure_message("AC-SAV-13: result[1] doit être TYPE_STRING_NAME après normalisation String→StringName") \
		.is_equal(TYPE_STRING_NAME)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-14 — array de 100 StringName : ordre préservé, tous TYPE_STRING_NAME
# =============================================================================

## GIVEN SaveLoadSystem instancié,
## WHEN save_string_array("ids", [&"id_0", ..., &"id_99"]) puis load_string_array("ids", []),
## THEN size=100, ordre préservé, chaque element[i] == &("id_" + str(i)), tous TYPE_STRING_NAME.
## Source : AC-SAV-14, ADR-0010 D-2.
func test_save_load_save_load_100_string_names_preserves_order_and_types() -> void:
	# Arrange — construire l'array de 100 StringName
	var instance: Node = _instantiate_save_load()
	var input: Array[StringName] = []
	for i: int in range(100):
		input.append(StringName("id_" + str(i)))
	var empty_default: Array[StringName] = []

	# Act
	instance.save_string_array("ids", input)
	var result: Array[StringName] = instance.load_string_array("ids", empty_default)

	# Assert — size
	assert_int(result.size()) \
		.override_failure_message("AC-SAV-14: load après save de 100 StringName doit retourner size=100") \
		.is_equal(100)

	# Assert — ordre et type pour chaque élément
	for i: int in range(100):
		assert_int(typeof(result[i])) \
			.override_failure_message("AC-SAV-14: result[%d] doit être TYPE_STRING_NAME" % i) \
			.is_equal(TYPE_STRING_NAME)
		assert_str(String(result[i])) \
			.override_failure_message("AC-SAV-14: result[%d] doit valoir 'id_%d' (ordre préservé)" % [i, i]) \
			.is_equal("id_" + str(i))

	# Cleanup
	instance.queue_free()
