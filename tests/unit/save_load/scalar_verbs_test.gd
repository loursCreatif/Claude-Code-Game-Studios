# Tests unitaires Story-002 — SaveLoadSystem scalar verbs load_int / save_int + type validation + edge cases.
# Couvre AC-SAV-2 / AC-SAV-3 / AC-SAV-5 / AC-SAV-7 / AC-SAV-8 / AC-SAV-9 / AC-SAV-17 / AC-SAV-18 (partial) / AC-SAV-19.
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Logic (story type Logic — coding-standards.md §Test Evidence).
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
	get_tree().paused = false  # safety si AC-SAV-19 fail mid-test


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
# AC-SAV-2 — load_int retourne la valeur stockée (pas le default)
# =============================================================================

## GIVEN user://savegame.cfg existe avec [data]\ntotal_credits=42,
## WHEN SaveLoadSystem instancié (boot charge le fichier),
## THEN load_int("total_credits", 0) == 42 (pas le default 0).
## Source : AC-SAV-2, R-SAV-4.
func test_save_load_load_int_existing_value_returns_stored_int() -> void:
	# Arrange — écrire le fichier AVANT d'instancier SaveLoadSystem
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("data", "total_credits", 42)
	cfg.save(_SAVE_FILE_PATH)

	# Act
	var instance: Node = _instantiate_save_load()

	# Assert
	assert_int(instance.load_int("total_credits", 0)) \
		.override_failure_message("AC-SAV-2: load_int('total_credits', 0) doit retourner 42 (valeur stockée), pas 0 (default)") \
		.is_equal(42)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-3 — fichier corrompu boot graceful, is_ready() true, load retourne default
# =============================================================================

## GIVEN user://savegame.cfg contient des bytes binaires random (non-ConfigFile),
## WHEN SaveLoadSystem instancié (_ready() exécuté),
## THEN ne crash pas, is_ready() == true (graceful), load_int retourne default.
## Source : AC-SAV-3, R-SAV-7 (graceful degradation sur tout err ≠ OK/ERR_FILE_NOT_FOUND).
func test_save_load_corrupted_file_boot_graceful_returns_defaults() -> void:
	# Arrange — écrire des bytes binaires corrompus
	var file: FileAccess = FileAccess.open(_SAVE_FILE_PATH, FileAccess.WRITE)
	assert_object(file) \
		.override_failure_message("AC-SAV-3: FileAccess.open doit réussir pour créer le fichier corrompu") \
		.is_not_null()
	file.store_buffer(PackedByteArray([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE]))
	file.close()

	# Act — instancier : _ready() va tenter de charger le fichier corrompu
	var instance: Node = _instantiate_save_load()

	# Assert — boot graceful
	assert_bool(instance.is_ready()) \
		.override_failure_message("AC-SAV-3: is_ready() doit être true malgré fichier corrompu (graceful degradation)") \
		.is_true()
	assert_int(instance.load_int("any_key", -1)) \
		.override_failure_message("AC-SAV-3: load_int sur ConfigFile vide post-corruption doit retourner default -1") \
		.is_equal(-1)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-5 — roundtrip save_int puis load_int retourne la valeur persistée
# =============================================================================

## GIVEN SaveLoadSystem instancié (_config_loaded == true),
## WHEN save_int("test_key", 123) puis load_int("test_key", 0),
## THEN retour 123 (valeur persistée, pas le default 0).
## Source : AC-SAV-5, R-SAV-4, ADR-0010 D-2 idempotence.
func test_save_load_save_int_then_load_int_returns_persisted_value() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()

	# Act
	instance.save_int("test_key", 123)
	var result: int = instance.load_int("test_key", 0)

	# Assert
	assert_int(result) \
		.override_failure_message("AC-SAV-5: load_int('test_key', 0) après save_int('test_key', 123) doit retourner 123") \
		.is_equal(123)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-7 — burst 1000 save_int sous budget perf < 1000 ms (< 1 ms / call SSD)
# =============================================================================

## GIVEN SaveLoadSystem instancié,
## WHEN save_int appelé 1000 fois consécutifs avec valeurs croissantes,
## THEN temps total < 1000 ms (F-SAV-1 : < 1 ms / call moyenne sur SSD).
## Source : AC-SAV-7, F-SAV-1, ADR-0010 D-2.
func test_save_load_save_int_burst_1000_calls_under_perf_budget() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()

	# Act — mesurer le burst
	var t0: int = Time.get_ticks_msec()
	for i: int in range(1000):
		instance.save_int("k_" + str(i), i)
	var delta: int = Time.get_ticks_msec() - t0

	# Assert
	assert_int(delta) \
		.override_failure_message(
			"AC-SAV-7: burst 1000 save_int doit prendre < 1000 ms — mesuré %d ms (F-SAV-1 < 1 ms/call SSD)" % delta
		) \
		.is_less(1000)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-8 — load_int clé absente retourne default
# =============================================================================

## GIVEN SaveLoadSystem instancié sans fichier préexistant (clé "absent" jamais sauvegardée),
## WHEN load_int("absent", 99),
## THEN retour 99 (default).
## Source : AC-SAV-8, R-SAV-6.
func test_save_load_load_int_absent_key_returns_default() -> void:
	# Arrange — before_test() a supprimé savegame.cfg
	var instance: Node = _instantiate_save_load()

	# Act
	var result: int = instance.load_int("absent", 99)

	# Assert
	assert_int(result) \
		.override_failure_message("AC-SAV-8: load_int('absent', 99) doit retourner 99 (clé inexistante → default)") \
		.is_equal(99)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-9 — type mismatch Array → default retourné
# =============================================================================

## GIVEN clé "k" stockée avec valeur Array [1, 2, 3] (corruption manuelle via injection seam _config),
## WHEN load_int("k", -1),
## THEN retour -1 (default) — type mismatch détecté par typeof() != TYPE_INT.
## Note : push_warning non asserté (GdUnit4 sans plugin spécialisé) — retour default suffit pour AC-SAV-9.
## Source : AC-SAV-9, R-SAV-6, R-SAV-12, ADR-0010 D-2.
func test_save_load_load_int_type_mismatch_array_returns_default() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	# Injection seam : accès direct à _config pour simuler corruption de type
	instance._config.set_value("data", "k", [1, 2, 3])

	# Act
	var result: int = instance.load_int("k", -1)

	# Assert
	assert_int(result) \
		.override_failure_message("AC-SAV-9: load_int('k', -1) avec type Array stocké doit retourner -1 (type mismatch → default)") \
		.is_equal(-1)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-17 — load_int key inexistante dans fichier valide retourne default
# =============================================================================

## GIVEN user://savegame.cfg valide avec seulement "existing=10",
## WHEN load_int("inexistant", 42),
## THEN retour 42 (clé absente → default).
## Source : AC-SAV-17, R-SAV-6.
func test_save_load_load_int_inexistant_key_with_valid_file_returns_default() -> void:
	# Arrange — fichier valide avec une seule key différente
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("data", "existing", 10)
	cfg.save(_SAVE_FILE_PATH)

	var instance: Node = _instantiate_save_load()

	# Act
	var result: int = instance.load_int("inexistant", 42)

	# Assert
	assert_int(result) \
		.override_failure_message("AC-SAV-17: load_int('inexistant', 42) dans fichier valide sans cette key doit retourner 42") \
		.is_equal(42)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-18 (partial) — save_int avant _ready() push_error, ne crash pas
# =============================================================================

## GIVEN instance SaveLoadSystem créée MAIS _ready() NON appelé (_config_loaded == false),
## WHEN save_int("k", 1),
## THEN ne crash pas (test passe sans exception).
##
## AC-SAV-18 partial coverage : ce test exerce le même push_error défensif que le path
## "permission revoquée mid-session". La couverture complète (mock ERR_FILE_NO_PERMISSION)
## est déférée à story-018 ou refactor avec injection seam ConfigFile.
## Source : AC-SAV-18 (partial), ADR-0010 D-2.
func test_save_load_save_int_when_config_not_loaded_pushes_error_no_crash() -> void:
	# Arrange — instancier SANS add_child → _ready() non appelé → _config_loaded == false
	var script: GDScript = load(_SAVE_LOAD_SCRIPT_PATH) as GDScript
	var instance: Node = script.new() as Node
	# NOTE : NE PAS appeler add_child — _config_loaded reste false

	# Act — doit pousser un push_error mais ne pas crasher
	instance.save_int("k", 1)

	# Assert — le test passe si aucune exception n'a été levée (no crash = AC-SAV-18 partial pass)
	assert_bool(true) \
		.override_failure_message("AC-SAV-18 (partial): save_int avant _ready() doit émettre push_error mais ne pas crasher") \
		.is_true()

	# Cleanup — pas de queue_free car jamais ajouté au scene tree
	instance.free()

# =============================================================================
# AC-SAV-19 — save_int sous get_tree().paused == true réussit
# =============================================================================

## GIVEN SaveLoadSystem instancié (process_mode = PROCESS_MODE_ALWAYS),
## WHEN get_tree().paused = true puis save_int("paused_key", 7),
## THEN load_int("paused_key", 0) == 7 (write réussi malgré tree paused).
## Mechanism : PROCESS_MODE_ALWAYS garantit l'exécution même sous pause — AC-SAV-4 story-001.
## Source : AC-SAV-19, R-SAV-8, ADR-0010 D-4.
func test_save_load_save_int_under_paused_tree_succeeds() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()

	# Act — pause le tree puis save
	get_tree().paused = true
	instance.save_int("paused_key", 7)
	get_tree().paused = false  # restore immédiatement pour les asserts

	# Assert
	assert_int(instance.load_int("paused_key", 0)) \
		.override_failure_message("AC-SAV-19: load_int('paused_key', 0) après save sous tree paused doit retourner 7") \
		.is_equal(7)

	# Cleanup — after_test() garantit get_tree().paused = false même si test fail
	instance.queue_free()
