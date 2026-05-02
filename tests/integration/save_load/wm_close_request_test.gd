# Tests d'intégration Story-005 — NOTIFICATION_WM_CLOSE_REQUEST handler + _flush_pending no-op MVP.
# Couvre AC-SAV-21 (handler safe + write-through cohérent + edge cases double signal / paused / boot interrompu).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration (story type Integration — coding-standards.md §Test Evidence).
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
	# Toujours unpause le tree pour éviter pollution cross-test paused.
	get_tree().paused = false


func after_test() -> void:
	_remove_save_file()
	get_tree().paused = false


func _remove_save_file() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.file_exists("savegame.cfg"):
		dir.remove("savegame.cfg")


## Instancie un SaveLoadSystem frais via add_child (déclenche _ready).
## Ne pas réutiliser le singleton autoload — l'état serait partagé cross-test.
func _instantiate_save_load() -> Node:
	var script: GDScript = load(_SAVE_LOAD_SCRIPT_PATH) as GDScript
	var instance: Node = script.new() as Node
	add_child(instance)
	return instance

# =============================================================================
# AC-SAV-21 — handler WM_CLOSE_REQUEST + write-through cohérent
# =============================================================================

## GIVEN SaveLoadSystem ready + save_int("total_credits", 42) appelé,
## WHEN notification(NOTIFICATION_WM_CLOSE_REQUEST) envoyée (simule alt-F4),
## THEN aucun crash, fichier reste cohérent (contient total_credits=42).
## Source : AC-SAV-21, R-SAV-9, ADR-0010 D-8.
func test_save_load_wm_close_request_after_save_int_file_remains_consistent() -> void:
	# Arrange — instance ready + state persisté
	var instance: Node = _instantiate_save_load()
	assert_bool(instance.is_ready()).is_true()
	instance.save_int("total_credits", 42)

	# Act — simuler alt-F4
	instance.notification(NOTIFICATION_WM_CLOSE_REQUEST)

	# Assert — fichier toujours présent + contient la valeur (write-through pré-quit)
	var content: String = FileAccess.get_file_as_string(_SAVE_FILE_PATH)
	assert_str(content) \
		.override_failure_message("AC-SAV-21: fichier doit contenir total_credits=42 post-WM_CLOSE_REQUEST") \
		.contains("total_credits=42")

	# Reload via une nouvelle instance prouve la cohérence end-to-end
	instance.queue_free()
	await get_tree().process_frame
	var fresh: Node = _instantiate_save_load()
	assert_int(fresh.load_int("total_credits", 0)) \
		.override_failure_message("AC-SAV-21: reload post-WM_CLOSE_REQUEST doit retourner 42") \
		.is_equal(42)
	fresh.queue_free()


## EDGE CASE 1 — WM_CLOSE_REQUEST envoyé pendant _config_loaded == false.
## Cas pathologique : boot interrompu avant fin de _ready(). Handler doit no-op safe.
## Sémantique : _flush_pending() est no-op MVP donc indifférent à l'état _config_loaded.
func test_save_load_wm_close_request_when_config_not_loaded_no_crash() -> void:
	# Arrange — instance NON add_child : _ready() pas appelé, _config_loaded == false
	var script: GDScript = load(_SAVE_LOAD_SCRIPT_PATH) as GDScript
	var instance: Node = script.new() as Node

	# Act — notification envoyée hors scene tree (pre-_ready)
	instance.notification(NOTIFICATION_WM_CLOSE_REQUEST)

	# Assert — pas de crash : si on arrive ici, le test passe.
	assert_bool(true).is_true()

	# Cleanup
	instance.free()


## EDGE CASE 2 — Double signal WM_CLOSE_REQUEST (idempotence).
## Cas rare : OS peut émettre 2 signaux consécutifs. Handler doit rester idempotent.
func test_save_load_wm_close_request_double_signal_idempotent() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	instance.save_int("total_credits", 7)

	# Act — double notification consécutive
	instance.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	instance.notification(NOTIFICATION_WM_CLOSE_REQUEST)

	# Assert — fichier toujours cohérent, aucun side-effect
	var content: String = FileAccess.get_file_as_string(_SAVE_FILE_PATH)
	assert_str(content) \
		.override_failure_message("AC-SAV-21: double WM_CLOSE_REQUEST doit rester idempotent (total_credits=7)") \
		.contains("total_credits=7")

	instance.queue_free()


## EDGE CASE 3 — WM_CLOSE_REQUEST sous get_tree().paused == true.
## process_mode = ALWAYS (story-001) garantit livraison du _notification même en pause.
func test_save_load_wm_close_request_under_paused_tree_no_crash() -> void:
	# Arrange
	var instance: Node = _instantiate_save_load()
	instance.save_int("total_credits", 99)
	get_tree().paused = true

	# Act
	instance.notification(NOTIFICATION_WM_CLOSE_REQUEST)

	# Assert — fichier intact malgré pause
	var content: String = FileAccess.get_file_as_string(_SAVE_FILE_PATH)
	assert_str(content) \
		.override_failure_message("AC-SAV-21: WM_CLOSE_REQUEST sous tree paused doit rester safe") \
		.contains("total_credits=99")

	# Cleanup (after_test unpausera aussi par sécurité)
	get_tree().paused = false
	instance.queue_free()
