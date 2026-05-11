## InputSettingsLoader — Chargement et sauvegarde des préférences utilisateur Input.
##
## Extrait de input_manager.gd (TD-008 split). Pas de class_name : bypass class cache
## CI gdUnit4 (pattern preload binding, voir feedback_godot_class_name_autoload_collision).
##
## Encapsule _load_settings() et save_settings() (story-010, ADR-0014 D-3/D-4/D-6).
## InputManager instancie ce loader et lui passe une référence à lui-même pour que
## le loader puisse propager les valeurs aux propriétés runtime.
##
## Main-thread only — _load_settings est appelé depuis InputManager._ready() (autoload,
## main thread garanti). save_settings() est un trigger explicite uniquement (D-6).

extends RefCounted

# ---------------------------------------------------------------------------
# Load
# ---------------------------------------------------------------------------

## Charge `user://settings/input.tres` (ADR-0014 D-3/D-4) et propage les valeurs
## persistées aux propriétés runtime de [param manager]. Appelé une seule fois
## depuis InputManager._ready() quand suppress_settings_load == false.
##
## Migration automatique forward-only via InputSettings.migrate_from.
## Corruption / first launch → defaults silencieux (D-4) — pas de blocage boot.
##
## Retourne l'InputSettings chargé (ou les defaults) pour assignation dans manager.settings.
##
## Usage : manager.settings = InputSettingsLoader.load_and_apply(manager)
static func load_and_apply(manager: Node) -> InputSettings:
	var loaded: InputSettings = SettingsResource.load_or_default(
		"input",
		Callable(InputSettings, "create_defaults"),
		Callable(InputSettings, "migrate_from"),
	) as InputSettings
	# Propagation des Tuning Knobs aux propriétés runtime consommées par les hot paths.
	manager.mouse_sensitivity = loaded.mouse_sensitivity
	manager.mouse_y_inverted = loaded.mouse_y_inverted
	manager._focus_regain_window_usec = loaded.focus_regain_window_ms * 1000
	if loaded.mouse_capture_at_boot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		manager._saved_mouse_mode = Input.MOUSE_MODE_CAPTURED
	return loaded

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

## Sauvegarde [param settings] vers `user://settings/input.tres` via SettingsResource.
## Trigger explicite uniquement (Settings menu apply, flush-on-quit) — ADR-0014 D-6
## interdit l'auto-save en _process.
## Retourne l'Error de ResourceSaver (OK si succès, ERR_UNCONFIGURED si settings == null).
## Usage : var err := InputSettingsLoader.save(manager.settings)
static func save(settings: InputSettings) -> Error:
	if settings == null:
		return ERR_UNCONFIGURED
	var err: Error = SettingsResource.save(settings, "input")
	if err != OK:
		push_warning("[input-settings] save failed: %d" % err)
	return err
