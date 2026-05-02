# Test unitaire story-022 — design/registry/level.yaml schema invariants.
#
# Couvre :
#   AC-LVL-44 (story-022) : `design/registry/level.yaml` doit exister sur disk
#   et exposer les 13 knobs minimaux (constants + layers + wall_run) avec leurs
#   defaults MVP. Schéma versionné via la clé `schema_version`.
#
# Approche : lecture simple FileAccess.get_as_text + assertions sur substrings
# des paires `KEY: value`. Pas de parser YAML complet (Godot stdlib n'en fournit
# pas) — un test de présence + valeurs critique suffit pour empêcher la dérive
# silencieuse des defaults.
#
# Framework : GdUnit4 (extends GdUnitTestSuite).
#
# Story : production/epics/level-system/story-022-chrome-zen-shader-atlas-tuning.md
# Req   : AC-LVL-44, TR-lvl-043
# Source: design/gdd/level-system.md §Tuning Knobs

extends GdUnitTestSuite


const YAML_PATH: String = "res://design/registry/level.yaml"


## AC-LVL-44 — fichier présent sur disk + schema_version + 13 knobs critiques.
##
## Si l'un des knobs disparaît (ex. cleanup imprudent), ce test échoue avec un
## message indiquant la clé manquante — empêche la dérive silencieuse.
func test_tuning_knobs_yaml_exists_and_parses() -> void:
	# --- Arrange ---
	# (rien — lecture filesystem direct)

	# --- Act ---
	assert_bool(FileAccess.file_exists(YAML_PATH)).is_true() \
		.override_failure_message("design/registry/level.yaml manquant — TR-lvl-043 / AC-LVL-44 fail")
	var file: FileAccess = FileAccess.open(YAML_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var content: String = file.get_as_text()
	file.close()

	# --- Assert : schema versioning + 13 knobs critiques avec defaults MVP ---
	# Schéma
	assert_str(content).contains("schema_version: 1")

	# Constants — 12 knobs
	assert_str(content).contains("KATANA_REACH: 1.8")
	assert_str(content).contains("CHECKPOINT_SPACING: 3")
	assert_str(content).contains("ETAGE_HEIGHT_MIN: 15.0")
	assert_str(content).contains("ETAGE_HEIGHT_MAX: 60.0")
	assert_str(content).contains("ROOM_COUNT_MIN: 8")
	assert_str(content).contains("ROOM_COUNT_MAX: 10")
	assert_str(content).contains("SECRET_COUNT_MIN: 3")
	assert_str(content).contains("SECRET_COUNT_MAX: 5")
	assert_str(content).contains("DRAW_CALL_BUDGET: 350")
	assert_str(content).contains("VRAM_BUDGET_MB: 50")
	assert_str(content).contains("RAM_BUDGET_MB: 20")
	assert_str(content).contains("LOAD_TIME_BUDGET_MS: 1000")

	# Layers — 5 collision layers ADR-0008 D-1
	assert_str(content).contains("LAYER_PLAYER: 1")
	assert_str(content).contains("LAYER_ENEMY: 2")
	assert_str(content).contains("LAYER_ENEMY_HITBOX: 3")
	assert_str(content).contains("LAYER_ENVIRONMENT: 4")
	assert_str(content).contains("LAYER_INTERACTIVE: 5")

	# Wall run — F8
	assert_str(content).contains("MIN_HEIGHT_M: 4.0")
	assert_str(content).contains("MIN_LENGTH_M: 3.0")
	assert_str(content).contains("MAX_TILT_DEG: 5.0")
