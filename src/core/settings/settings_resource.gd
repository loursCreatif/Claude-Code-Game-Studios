## Helper static class pour persistance des préférences utilisateur (settings).
## ADR-0014 D-5 : zero autoload, RefCounted utility — chaque consumer charge
## ses propres settings au _ready() via 1 ligne. ADR-0014 D-1/D-2/D-3/D-4
## (Resource .tres typé, sub-folder user://settings/, versioning par champ
## _settings_version, corruption fallback defaults+warning sans rewrite).
##
## Usage canonique :
##
##     _settings = SettingsResource.load_or_default(
##         "camera",
##         Callable(CameraSettings, "create_defaults"),
##         Callable(CameraSettings, "migrate_from"),
##     ) as CameraSettings
##
##     # plus tard, sur trigger explicite (Settings menu apply, flush-on-quit)
##     SettingsResource.save(_settings, "camera")
class_name SettingsResource
extends RefCounted

## Sub-folder canonique sous user:// pour TOUS les settings.
## ADR-0014 D-2 : isolated, scalable, simplifie wipe-settings.
const SETTINGS_DIR: String = "user://settings/"


## Compose le chemin canonique d'un fichier settings : user://settings/<system>.tres.
## ADR-0014 D-2 path canonique. system = nom court du consumer ("camera", "input", "audio").
static func _resolve_path(system: String) -> String:
	return SETTINGS_DIR + system + ".tres"


## Crée le sub-folder user://settings/ si absent. Idempotent.
## ADR-0014 D-2 + D-5 : appelé avant chaque load/save par le helper. Erreur ignorée
## (permission refusée → load suivant retombera sur defaults runtime, save loggera).
static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SETTINGS_DIR):
		var err: Error = DirAccess.make_dir_recursive_absolute(SETTINGS_DIR)
		if err != OK:
			push_warning("[settings] make_dir_recursive_absolute failed: %d" % err)


## Charge le fichier settings du consumer [param system] ou retourne les defaults.
##
## ADR-0014 D-3 + D-4 :
##   - First launch (file absent) : retourne `default_factory.call()` SILENCIEUX (pas de warning).
##   - File present & loadable : appelle `migrate.call(loaded._settings_version, loaded)`
##     pour ramener au CURRENT_VERSION ; fallback defaults si migration retourne null.
##   - File present mais corrompu (ResourceLoader.load → null) : warning + defaults +
##     PAS de réécriture automatique (D-4 anti-debug : laisse le fichier corrompu visible
##     pour QA jusqu'au prochain save() explicite).
##
## [param system] nom court ("camera", "input"). [param default_factory] Callable () -> Resource.
## [param migrate] Callable (int, Resource) -> Resource (forward-only, peut retourner null).
static func load_or_default(
		system: String,
		default_factory: Callable,
		migrate: Callable,
) -> Resource:
	_ensure_dir()
	var path: String = _resolve_path(system)
	if not FileAccess.file_exists(path):
		return default_factory.call() as Resource
	var loaded: Resource = ResourceLoader.load(path)
	if loaded == null:
		push_warning("[settings] %s corrupted, using defaults" % path)
		return default_factory.call() as Resource
	var current_version: int = 0
	var v: Variant = loaded.get(&"_settings_version")
	if v != null:
		current_version = int(v)
	var migrated: Resource = migrate.call(current_version, loaded) as Resource
	if migrated == null:
		push_warning("[settings] %s migration failed, using defaults" % path)
		return default_factory.call() as Resource
	return migrated


## Sérialise [param resource] dans user://settings/<system>.tres.
## ADR-0014 D-1 + D-7 : utiliser ResourceSaver (jamais FileAccess.store_*, forbidden D-9).
## Retourne l'Error de ResourceSaver (OK, ERR_FILE_CANT_WRITE, etc.) — caller logue si != OK.
static func save(resource: Resource, system: String) -> Error:
	_ensure_dir()
	var path: String = _resolve_path(system)
	return ResourceSaver.save(resource, path)
