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
## Retourne default si le fichier est absent, corrompu, ou si le type est incorrect.
## Minimum viable pour AC-SAV-1 — sémantique complète livrée en story-002.
func load_int(key: String, default: int) -> int:
	_assert_main_thread()
	if not _config_loaded:
		return default
	var value: Variant = _config.get_value("data", key, default)
	if typeof(value) != TYPE_INT:
		if value != default:
			push_warning("SaveLoadSystem: load_int(%s) type mismatch, return default" % key)
		return default
	return value

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
