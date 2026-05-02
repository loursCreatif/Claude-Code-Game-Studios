# Integration test Story-001 — Upgrade autoload skeleton + project.godot order + process_mode.
# Couvre AC-UPG-1 (singleton accessible + is UpgradeSystem) / AC-UPG-3 BLOCKING (SaveLoad < Upgrade)
# / AC-UPG-3-bis ADVISORY (ordre canonique complet) / AC-UPG-4 (process_mode == ALWAYS == 3).
# Framework : GdUnit4 (extends GdUnitTestSuite).
# Type : Integration (story type Integration — coding-standards.md §Test Evidence).

extends GdUnitTestSuite

const _PROJECT_GODOT_PATH: String = "res://project.godot"

# =============================================================================
# AC-UPG-1 — singleton autoload accessible et typé UpgradeSystem
# =============================================================================

## GIVEN projet booté avec autoloads canoniques,
## WHEN un script accède au singleton via Engine.get_main_loop().root.get_node("Upgrade"),
## THEN Upgrade != null ET Upgrade is UpgradeSystem == true.
## Source : AC-UPG-1, R-UPG-1.
func test_upgrade_autoload_singleton_is_upgrade_system_type() -> void:
	# Arrange — bootstrap Godot a déjà exécuté tous les autoloads avant le test runner.

	# Act
	var upgrade_singleton: Node = Engine.get_main_loop().root.get_node("Upgrade")

	# Assert
	assert_object(upgrade_singleton) \
		.override_failure_message("AC-UPG-1: Upgrade autoload doit être accessible via /root/Upgrade") \
		.is_not_null()
	assert_bool(upgrade_singleton is UpgradeSystem) \
		.override_failure_message("AC-UPG-1: Upgrade is UpgradeSystem doit retourner true") \
		.is_true()

# =============================================================================
# AC-UPG-3 BLOCKING — index(SaveLoadSystem) < index(Upgrade) dans project.godot
# AC-UPG-3-bis ADVISORY — ordre exact canonique
# =============================================================================

## GIVEN parse project.godot bloc [autoload],
## WHEN extraction de l'ordre des clés autoload,
## THEN index("SaveLoadSystem") < index("Upgrade") (BLOCKING)
## ET ordre exact ["InputManager", "GameStateManager", "SaveLoadSystem", ..., "Upgrade", ...] (ADVISORY).
## Source : AC-UPG-3, AC-UPG-3-bis, R-UPG-11.
func test_upgrade_autoload_order_save_load_before_upgrade() -> void:
	# Arrange — lire project.godot raw
	var file: FileAccess = FileAccess.open(_PROJECT_GODOT_PATH, FileAccess.READ)
	assert_object(file) \
		.override_failure_message("project.godot doit être lisible") \
		.is_not_null()
	var content: String = file.get_as_text()
	file.close()

	# Extraire le bloc [autoload]
	var autoload_block_start: int = content.find("[autoload]")
	assert_int(autoload_block_start) \
		.override_failure_message("Bloc [autoload] doit exister dans project.godot") \
		.is_greater_equal(0)
	var autoload_section: String = content.substr(autoload_block_start)
	var next_section_start: int = autoload_section.find("\n[", 1)
	if next_section_start > 0:
		autoload_section = autoload_section.substr(0, next_section_start)

	# Act — extraire les clés dans l'ordre d'apparition
	var lines: PackedStringArray = autoload_section.split("\n")
	var autoload_keys: Array[String] = []
	for line: String in lines:
		var stripped: String = line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("[") or stripped.begins_with(";"):
			continue
		var eq_idx: int = stripped.find("=")
		if eq_idx <= 0:
			continue
		autoload_keys.append(stripped.substr(0, eq_idx))

	# Assert BLOCKING — SaveLoadSystem before Upgrade
	var save_load_idx: int = autoload_keys.find("SaveLoadSystem")
	var upgrade_idx: int = autoload_keys.find("Upgrade")
	assert_int(save_load_idx) \
		.override_failure_message("AC-UPG-3 BLOCKING: SaveLoadSystem doit exister dans [autoload]") \
		.is_greater_equal(0)
	assert_int(upgrade_idx) \
		.override_failure_message("AC-UPG-3 BLOCKING: Upgrade doit exister dans [autoload]") \
		.is_greater_equal(0)
	assert_int(save_load_idx) \
		.override_failure_message(
			"AC-UPG-3 BLOCKING strict: index(SaveLoadSystem)=%d doit être < index(Upgrade)=%d" \
			% [save_load_idx, upgrade_idx]
		) \
		.is_less(upgrade_idx)

	# Assert ADVISORY — InputManager → GSM → SaveLoad précèdent Upgrade
	# (AudioSystem absent au MVP, ne fait pas partie de la séquence vérifiée).
	var input_idx: int = autoload_keys.find("InputManager")
	var gsm_idx: int = autoload_keys.find("GameStateManager")
	assert_int(input_idx) \
		.override_failure_message("AC-UPG-3-bis ADVISORY: InputManager doit précéder GameStateManager") \
		.is_less(gsm_idx)
	assert_int(gsm_idx) \
		.override_failure_message("AC-UPG-3-bis ADVISORY: GameStateManager doit précéder SaveLoadSystem") \
		.is_less(save_load_idx)

# =============================================================================
# AC-UPG-4 — process_mode == PROCESS_MODE_ALWAYS == 3 (double-assert erratum 4.6)
# =============================================================================

## GIVEN autoload Upgrade initialisé,
## WHEN lecture process_mode post-_ready(),
## THEN == Node.PROCESS_MODE_ALWAYS (constante symbolique) ET == 3 (littéral entier).
## Double-assert erratum 1649049 : PROCESS_MODE_ALWAYS = 3 en Godot 4.6 (PAS 4).
## Source : AC-UPG-4, R-UPG-18, ADR-0007 D-4.
func test_upgrade_process_mode_double_assert_always_equals_three() -> void:
	# Arrange
	var upgrade_singleton: Node = Engine.get_main_loop().root.get_node("Upgrade")

	# Act
	var mode: int = upgrade_singleton.process_mode

	# Assert (double-assert erratum 4.6)
	assert_int(mode) \
		.override_failure_message(
			"AC-UPG-4 (symbolic): process_mode doit être Node.PROCESS_MODE_ALWAYS"
		) \
		.is_equal(Node.PROCESS_MODE_ALWAYS)
	assert_int(mode) \
		.override_failure_message(
			"AC-UPG-4 (literal): process_mode doit être 3 (PROCESS_MODE_ALWAYS Godot 4.6 erratum 1649049, " +
			"PAS 4 qui serait PROCESS_MODE_DISABLED)"
		) \
		.is_equal(3)
