## AutoloadResetTestSuite — Base class GdUnit4 avec snapshot/restore des autoloads.
##
## Problème (TD-010) : 4 suites échouent en sweep complet mais passent en isolation.
## Les autoloads partagés (GSM, AudioSystem, VFXSystem, Engine) accumulent l'état
## d'une suite à l'autre. Cette base class corrige la pollution par snapshot/restore
## automatique dans before_test / after_test.
##
## Usage (opt-in) :
##   extends AutoloadResetTestSuite  # au lieu de GdUnitTestSuite
##
## Si la suite a déjà ses propres before_test / after_test, appeler super :
##   func before_test() -> void:
##       super.before_test()
##       # ... code spécifique à la suite
##
##   func after_test() -> void:
##       # ... code spécifique
##       super.after_test()
##
## Autoloads couverts :
##   - GameStateManager._current_state  (GSM state machine)
##   - Engine.time_scale                (GSM pause → slow-mo)
##   - SceneTree.paused                 (GSM pause)
##   - AudioSystem._2d_index            (round-robin pool state)
##   - AudioSystem._is_paused           (music pause state)
##   - VFXSystem._flash_kill_active     (flash overlay kill)
##   - VFXSystem._flash_respawn_active  (flash overlay respawn)
##
## Rationale : seuls les champs réellement pollués par les 4 suites identifiées
## sont snapshotés. Ajouter des champs au besoin si de nouvelles pollutions
## apparaissent (cf. story-w4 AC-W4-2).
##
## Source : docs/tech-debt-register.md TD-010
## Plan   : production/tech-debt/story-w4-test-infra-autoload-reset-between-suites.md

class_name AutoloadResetTestSuite
extends GdUnitTestSuite


# ---------------------------------------------------------------------------
# Snapshot storage
# ---------------------------------------------------------------------------

var _snap_gsm_state: int = 0
var _snap_time_scale: float = 1.0
var _snap_tree_paused: bool = false
var _snap_audio_2d_index: int = 0
var _snap_audio_is_paused: bool = false
var _snap_vfx_flash_kill_active: bool = false
var _snap_vfx_flash_respawn_active: bool = false


# ---------------------------------------------------------------------------
# GdUnit4 lifecycle overrides
# ---------------------------------------------------------------------------

func before_test() -> void:
	_snapshot_autoload_state()


func after_test() -> void:
	_restore_autoload_state()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Capture l'état courant des autoloads dans les variables snapshot.
## Appelé automatiquement par before_test(). Peut être appelé manuellement
## si la suite a besoin d'un point de restauration intermédiaire.
func _snapshot_autoload_state() -> void:
	# GameStateManager
	_snap_gsm_state = GameStateManager.get_current_state()

	# Engine
	_snap_time_scale = Engine.time_scale

	# SceneTree
	_snap_tree_paused = get_tree().paused

	# AudioSystem — accès direct au nœud autoload (pas de class_name exposé)
	var audio: Node = _get_autoload_node(&"AudioSystem")
	if audio != null:
		_snap_audio_2d_index = audio._2d_index
		_snap_audio_is_paused = audio._is_paused

	# VFXSystem
	var vfx: Node = _get_autoload_node(&"VFXSystem")
	if vfx != null:
		_snap_vfx_flash_kill_active = vfx._flash_kill_active
		_snap_vfx_flash_respawn_active = vfx._flash_respawn_active


## Restaure l'état des autoloads depuis les variables snapshot.
## Appelé automatiquement par after_test(). Peut être appelé manuellement.
func _restore_autoload_state() -> void:
	# Engine — restaurer d'abord time_scale et paused (impactent le moteur entier)
	Engine.time_scale = _snap_time_scale
	get_tree().paused = _snap_tree_paused

	# GameStateManager — écriture directe du champ privé pour contourner les
	# assertions de transition légale (le snapshot peut être n'importe quel state).
	GameStateManager._current_state = _snap_gsm_state

	# AudioSystem
	var audio: Node = _get_autoload_node(&"AudioSystem")
	if audio != null:
		audio._2d_index = _snap_audio_2d_index
		audio._is_paused = _snap_audio_is_paused

	# VFXSystem
	var vfx: Node = _get_autoload_node(&"VFXSystem")
	if vfx != null:
		vfx._flash_kill_active = _snap_vfx_flash_kill_active
		vfx._flash_respawn_active = _snap_vfx_flash_respawn_active


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Récupère un autoload par son nom enregistré dans /root/.
## Retourne null si l'autoload n'est pas chargé (ex. test unitaire sans scène complète).
func _get_autoload_node(autoload_name: StringName) -> Node:
	return get_tree().root.get_node_or_null(autoload_name)
