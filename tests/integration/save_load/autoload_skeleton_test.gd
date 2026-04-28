# Tests d'intégration Story-001 — SaveLoadSystem autoload skeleton + ConfigFile init.
# Couvre AC-SAV-1 (boot fresh defaults) / AC-SAV-4 (autoload order) / AC-SAV-20 (process_mode double-assert).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration (story type Integration — coding-standards.md §Test Evidence).
#
# Naming : test_save_load_[scenario]_[expected_result] per .claude/rules/test-standards.md.

extends GdUnitTestSuite

const _SAVE_LOAD_SCRIPT_PATH: String = "res://src/core/save_load_system.gd"

# =============================================================================
# Hermetic teardown — garantit qu'aucun fichier savegame.cfg ne pollue le run
# =============================================================================

## Supprime le fichier de sauvegarde avant et après chaque test pour isolation.
## Évite la pollution cross-story (story-002+ écrira via le singleton autoload).
func before_test() -> void:
	_remove_save_file()


func after_test() -> void:
	_remove_save_file()


func _remove_save_file() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.file_exists("savegame.cfg"):
		dir.remove("savegame.cfg")

# =============================================================================
# AC-SAV-1 — boot fresh fichier absent retourne defaults
# =============================================================================

## GIVEN user://savegame.cfg n'existe pas,
## WHEN SaveLoadSystem instancié et _ready() exécuté,
## THEN is_ready() == true ET load_int("total_credits", 0) == 0.
## Source : AC-SAV-1, R-SAV-7 (ERR_FILE_NOT_FOUND nominal).
func test_save_load_boot_fresh_no_save_file_returns_int_default() -> void:
	# Arrange — before_test() a déjà supprimé savegame.cfg

	# Act — instancier un SaveLoadSystem frais (ne pas réutiliser le singleton autoload
	# qui a déjà chargé l'état au boot du test runner)
	var script: GDScript = load(_SAVE_LOAD_SCRIPT_PATH) as GDScript
	var instance: Node = script.new() as Node
	add_child(instance)
	# _ready() est appelé par add_child() lorsque le nœud entre dans le scene tree.

	# Assert
	assert_bool(instance.is_ready()) \
		.override_failure_message("AC-SAV-1: is_ready() doit retourner true après boot sans fichier") \
		.is_true()
	assert_int(instance.load_int("total_credits", 0)) \
		.override_failure_message("AC-SAV-1: load_int('total_credits', 0) doit retourner 0 sur fichier absent") \
		.is_equal(0)

	# Cleanup
	instance.queue_free()

# =============================================================================
# AC-SAV-4 — autoload order garantit hydratation avant consumers post-position-3
# =============================================================================

## GIVEN engine boot avec project.godot order InputManager → GSM → SaveLoadSystem → LevelSystem,
## WHEN un consumer-stub Node ajouté en enfant exécute son propre _ready() après SaveLoadSystem,
## THEN SaveLoadSystem.is_ready() == true depuis le _ready() du consumer (sans race).
##
## Mécanisme : add_child() d'un Node consumer-stub déclenche son _ready() immédiatement.
## Ce stub capture l'état is_ready() vu depuis son propre _ready() — preuve directe que
## la garantie autoload tient pour tout consumer instancié post-bootstrap.
## (Mock CreditEconomy real stub différé story credit-economy-001 ; ici proxy direct via Node générique.)
func test_save_load_autoload_ready_observed_true_from_consumer_ready() -> void:
	# Arrange — préparer un consumer-stub qui capture is_ready() depuis son _ready()
	var stub: _ConsumerStub = _ConsumerStub.new()

	# Act — add_child déclenche stub._ready() qui interroge SaveLoadSystem.is_ready()
	add_child(stub)

	# Assert — depuis le _ready() du stub, le singleton autoload est ready
	assert_bool(stub.observed_save_load_ready) \
		.override_failure_message(
			"AC-SAV-4: SaveLoadSystem.is_ready() doit être true depuis _ready() d'un consumer " +
			"post-position-3 (garantie autoload order project.godot)"
		) \
		.is_true()
	assert_object(stub.observed_singleton) \
		.override_failure_message("AC-SAV-4: SaveLoadSystem doit être accessible comme global GDScript") \
		.is_not_null()

	# Cleanup
	stub.queue_free()

# =============================================================================
# AC-SAV-20 — process_mode double-assert erratum Godot 4.6
# =============================================================================

## GIVEN SaveLoadSystem instancié (singleton autoload),
## WHEN inspection de process_mode,
## THEN == PROCESS_MODE_ALWAYS (constante symbolique) ET == 3 (littéral entier).
## Double-assert requis : erratum 1649049 confirme PROCESS_MODE_ALWAYS = 3 en Godot 4.6
## (PAS 4 qui est PROCESS_MODE_DISABLED — confusion possible si dev écrit = 4 par erreur).
## Source : AC-SAV-20, R-SAV-8, ADR-0007 D-4, ADR-0010 D-4.
func test_save_load_process_mode_double_assert_always_equals_three() -> void:
	# Arrange — accéder au singleton autoload via global GDScript identifier
	var save_load_singleton: Node = SaveLoadSystem

	# Act — lire process_mode
	var mode: int = save_load_singleton.process_mode

	# Assert (double-assert erratum 4.6)
	# Assert 1 : constante symbolique
	assert_int(mode) \
		.override_failure_message(
			"AC-SAV-20 (symbolic): process_mode doit être Node.PROCESS_MODE_ALWAYS"
		) \
		.is_equal(Node.PROCESS_MODE_ALWAYS)
	# Assert 2 : littéral entier 3 (guard contre régression si constante change ou mauvaise assignation)
	assert_int(mode) \
		.override_failure_message(
			"AC-SAV-20 (literal): process_mode doit être 3 (PROCESS_MODE_ALWAYS Godot 4.6 erratum 1649049, " +
			"PAS 4 qui serait PROCESS_MODE_DISABLED)"
		) \
		.is_equal(3)

# =============================================================================
# Helpers — consumer-stub pour AC-SAV-4
# =============================================================================

## Node minimal qui capture l'état SaveLoadSystem.is_ready() depuis son propre _ready().
## Permet de prouver l'invariant cross-autoload : tout consumer instancié post-bootstrap
## voit SaveLoadSystem hydraté depuis son propre _ready() (R-SAV-7 + ADR-0010 D-3).
class _ConsumerStub extends Node:
	var observed_save_load_ready: bool = false
	var observed_singleton: Node = null

	func _ready() -> void:
		observed_singleton = SaveLoadSystem
		if observed_singleton != null:
			observed_save_load_ready = observed_singleton.is_ready()
