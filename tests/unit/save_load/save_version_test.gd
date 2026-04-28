# Tests unitaires Story-004 — SaveLoadSystem _save_version lazy init + forward-only schema versioning.
# Couvre AC-SAV-6 / AC-SAV-15 / AC-SAV-16.
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
# AC-SAV-6 — save_int écrit _save_version=1 dans le fichier (lazy init idempotent)
# =============================================================================

## GIVEN user://savegame.cfg absent,
## WHEN save_int("k", 0) exécuté une seule fois,
## THEN le fichier contient `_save_version=1` ET `k=0` dans la section [data].
## Edge case : 2e appel save_int → _save_version=1 apparaît UNE seule fois (idempotent).
## Source : AC-SAV-6, R-SAV-15, ADR-0010 D-6.
func test_save_load_save_int_writes_save_version_one_in_file() -> void:
	# Arrange — before_test() a supprimé savegame.cfg
	var instance: Node = _instantiate_save_load()

	# Act — premier save
	instance.save_int("k", 0)
	var content: String = FileAccess.get_file_as_string(_SAVE_FILE_PATH)

	# Assert — les deux clés sont présentes
	assert_str(content) \
		.override_failure_message("AC-SAV-6: fichier doit contenir '_save_version=1' après save_int") \
		.contains("_save_version=1")
	assert_str(content) \
		.override_failure_message("AC-SAV-6: fichier doit contenir 'k=0' après save_int('k', 0)") \
		.contains("k=0")

	# Act — deuxième save (edge case idempotence)
	instance.save_int("k2", 1)
	var content2: String = FileAccess.get_file_as_string(_SAVE_FILE_PATH)

	# Assert — _save_version=1 présent exactement une fois (pas de doublon)
	var occurrences: int = content2.split("_save_version=1").size() - 1
	assert_int(occurrences) \
		.override_failure_message(
			"AC-SAV-6 (idempotence): '_save_version=1' doit apparaître exactement 1 fois dans le fichier — trouvé %d" % occurrences
		) \
		.is_equal(1)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-15 — fichier avec _save_version=99 : push_warning + lecture partielle réussie
# =============================================================================

## GIVEN user://savegame.cfg contient _save_version=99 et total_credits=42 (version future),
## WHEN SaveLoadSystem instancié (_ready() appelle _check_save_version_compatibility),
## THEN push_warning émis (contient "save version 99" et "supported 1")
##      ET load_int("total_credits", 0) retourne 42 (lecture partielle réussie).
##
## Note : push_warning non assertable directement en GdUnit4 sans plugin spécialisé.
## L'AC-SAV-15 est couvert partiellement par l'assert sur load_int == 42.
## La capture stderr complète est déférée à un test E2E ou plugin spécialisé.
## Source : AC-SAV-15, R-SAV-15, ADR-0010 D-6.
func test_save_load_load_int_with_future_save_version_emits_warning_and_returns_value() -> void:
	# Arrange — écrire manuellement un fichier avec version future (99)
	var cf: ConfigFile = ConfigFile.new()
	cf.set_value("data", "_save_version", 99)
	cf.set_value("data", "total_credits", 42)
	cf.save(_SAVE_FILE_PATH)

	# Act — instancier déclenche _ready() → _check_save_version_compatibility() → push_warning
	var instance: Node = _instantiate_save_load()

	# Act — lecture partielle malgré version future
	var v: int = instance.load_int("total_credits", 0)

	# Assert — lecture réussie malgré version future (AC-SAV-15 partial)
	assert_int(v) \
		.override_failure_message(
			"AC-SAV-15: load_int('total_credits', 0) avec _save_version=99 doit retourner 42 (lecture partielle réussie)"
		) \
		.is_equal(42)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-16 — fichier sans _save_version : get_save_version() retourne 1 (default MVP)
# =============================================================================

## GIVEN user://savegame.cfg contient [data]\ntotal_credits=42 SANS clé _save_version,
## WHEN SaveLoadSystem instancié puis get_save_version() appelé,
## THEN retour 1 (_CURRENT_SAVE_VERSION par défaut — R-SAV-14).
## Source : AC-SAV-16, R-SAV-14, ADR-0010 D-6.
func test_save_load_get_save_version_default_when_key_absent_returns_one() -> void:
	# Arrange — fichier valide sans clé _save_version
	var cf: ConfigFile = ConfigFile.new()
	cf.set_value("data", "total_credits", 42)
	cf.save(_SAVE_FILE_PATH)

	# Act
	var instance: Node = _instantiate_save_load()
	var v: int = instance.get_save_version()

	# Assert — default MVP retourné quand clé absente
	assert_int(v) \
		.override_failure_message(
			"AC-SAV-16: get_save_version() sans clé _save_version dans fichier doit retourner 1 (_CURRENT_SAVE_VERSION default)"
		) \
		.is_equal(1)

	# Cleanup
	instance.queue_free()
