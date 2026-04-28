# Autoload nom : SaveLoadSystem (position 3 sur 4 — ADR-0007 D-1 + ADR-0010 D-3)
# Pas de class_name — autoload sans class_name évite la collision Godot 4.6
# (ADR-0010 §Key Interfaces + memory feedback_godot_class_name_autoload_collision).
# Les consumers accèdent au singleton via `SaveLoadSystem.xxx` (nom autoload globalement accessible).
extends Node

# =============================================================================
# Constants
# =============================================================================

const SAVE_FILE_PATH: String = "user://savegame.cfg"
# Réservé story-004 (R-SAV-14/15 _save_version forward-only framework).
const _CURRENT_SAVE_VERSION: int = 1

# =============================================================================
# Private variables
# =============================================================================

var _config: ConfigFile
var _config_loaded: bool = false

# =============================================================================
# Built-in virtual methods
# =============================================================================

func _ready() -> void:
	# ADR-0010 D-4 + ADR-0007 D-4 : PROCESS_MODE_ALWAYS = 3 en Godot 4.6
	# Erratum 1649049 : PROCESS_MODE_ALWAYS == 3, PAS 4 (qui est PROCESS_MODE_DISABLED).
	process_mode = Node.PROCESS_MODE_ALWAYS
	assert(process_mode == 3,
		"SaveLoadSystem: process_mode != 3 (PROCESS_MODE_ALWAYS Godot 4.6 erratum 1649049)")

	_config = ConfigFile.new()
	var err: Error = _config.load(SAVE_FILE_PATH)

	if err == OK or err == ERR_FILE_NOT_FOUND:
		# ERR_FILE_NOT_FOUND est nominal au boot fresh (R-SAV-7).
		_config_loaded = true
	else:
		push_error("SaveLoadSystem: load failed err=%d path=%s" % [err, SAVE_FILE_PATH])
		# Graceful : les verbes load_* retourneront leurs defaults même en cas d'erreur.
		_config_loaded = true

# =============================================================================
# Public methods
# =============================================================================

## Retourne true si _ready() a complété l'hydratation de _config.
## API publique exposée pour les tests d'intégration (AC-SAV-1 / AC-SAV-4).
## Les consumers nominaux n'ont pas besoin de l'appeler — l'ordre autoload (#3) garantit
## que SaveLoadSystem est ready avant tout consumer post-position-3 (Credit/Shop/Upgrade).
func is_ready() -> bool:
	_assert_main_thread()
	return _config_loaded


## Charge un entier depuis la section [data] du fichier de sauvegarde.
## Retourne [param default] si le fichier est absent, corrompu, ou si le type stocké n'est pas int.
## Émet [code]push_warning[/code] sur type mismatch (ADR-0010 D-2).
##
## [b]Exemple usage[/b] :
## [codeblock]
## var credits: int = SaveLoadSystem.load_int("total_credits", 0)
## [/codeblock]
func load_int(key: String, default: int) -> int:
	_assert_main_thread()
	if not _config_loaded:
		return default
	var value: Variant = _config.get_value("data", key, default)
	if typeof(value) != TYPE_INT:
		push_warning("SaveLoadSystem: load_int('%s') expected int, got %s — return default" % [key, type_string(typeof(value))])
		return default
	return value


## Persiste un entier dans la section [data] du fichier de sauvegarde.
## Retourne void — pas de signal, pas de bool, push_error en cas d'échec disque (R-SAV-10, ADR-0010 D-2).
## Idempotent : [code]save_int(k, v)[/code] appelé deux fois consécutifs avec la même valeur produit le même fichier (R-SAV-13).
##
## [b]Exemple usage[/b] :
## [codeblock]
## SaveLoadSystem.save_int("total_credits", 42)
## var credits: int = SaveLoadSystem.load_int("total_credits", 0)  # → 42
## [/codeblock]
func save_int(key: String, value: int) -> void:
	_assert_main_thread()
	if not _config_loaded:
		push_error("SaveLoadSystem: save_int('%s') called before _config_loaded" % key)
		return
	_config.set_value("data", key, value)
	var err: Error = _config.save(SAVE_FILE_PATH)
	if err != OK:
		push_error("SaveLoadSystem: save_int('%s') failed err=%d" % [key, err])

## Charge un tableau de StringName depuis la section [data] du fichier de sauvegarde.
## Retourne [param default] si le fichier est absent, corrompu, ou si le type stocké n'est pas Array.
## Les éléments de type String sont normalisés en StringName (R-SAV-12 — ConfigFile sérialise
## StringName comme String entre quotes). Les éléments d'un autre type sont ignorés avec push_warning.
##
## [b]Exemple usage[/b] :
## [codeblock]
## var upgrades: Array[StringName] = SaveLoadSystem.load_string_array("upgrades", [])
## [/codeblock]
func load_string_array(key: String, default: Array[StringName]) -> Array[StringName]:
	_assert_main_thread()
	if not _config_loaded:
		return default
	# Key absente = nominal (pas une corruption) → retour silencieux du default.
	# On évite ConfigFile.get_value(_, _, default) ici pour ne pas comparer cross-type
	# (raw int vs default Array → invalid operator '!=' Godot 4 strict).
	if not _config.has_section_key("data", key):
		return default
	var raw: Variant = _config.get_value("data", key)
	if typeof(raw) != TYPE_ARRAY:
		push_warning("SaveLoadSystem: load_string_array('%s') expected Array, got %s — return default" % [key, type_string(typeof(raw))])
		return default
	var result: Array[StringName] = []
	for elem: Variant in raw:
		var t: int = typeof(elem)
		if t == TYPE_STRING_NAME:
			result.append(elem)
		elif t == TYPE_STRING:
			result.append(StringName(elem))  # R-SAV-12 normalisation String→StringName
		else:
			push_warning("SaveLoadSystem: load_string_array('%s') skip element type=%s" % [key, type_string(t)])
	return result


## Persiste un tableau de StringName dans la section [data] du fichier de sauvegarde.
## Retourne void — pas de signal, pas de bool, push_error en cas d'échec disque (ADR-0010 D-2).
## Note : ConfigFile peut sérialiser les StringName comme String — load_string_array normalise au chargement.
##
## [b]Exemple usage[/b] :
## [codeblock]
## SaveLoadSystem.save_string_array("upgrades", [&"double_jump", &"dash_horizontal"])
## var upgrades: Array[StringName] = SaveLoadSystem.load_string_array("upgrades", [])  # → [&"double_jump", &"dash_horizontal"]
## [/codeblock]
func save_string_array(key: String, value: Array[StringName]) -> void:
	_assert_main_thread()
	if not _config_loaded:
		push_error("SaveLoadSystem: save_string_array('%s') called before _config_loaded" % key)
		return
	_config.set_value("data", key, value)
	var err: int = _config.save(SAVE_FILE_PATH)
	if err != OK:
		push_error("SaveLoadSystem: save_string_array('%s') failed err=%d" % [key, err])

# =============================================================================
# Private methods
# =============================================================================

## Assertion de thread principal — gated en debug uniquement (ADR-0010 D-7).
## Empêche tout appel SaveLoad depuis Thread / WorkerThreadPool / call_deferred cross-thread.
func _assert_main_thread() -> void:
	if OS.has_feature("debug"):
		assert(
			OS.get_thread_caller_id() == OS.get_main_thread_id(),
			"SaveLoadSystem: called from non-main thread (ADR-0010 D-7)"
		)
