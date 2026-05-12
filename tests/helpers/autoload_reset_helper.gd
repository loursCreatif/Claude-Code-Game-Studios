## AutoloadResetHelper — Snapshot/restore autoloads via composition (pas héritage).
##
## Pattern : référencé via `const AutoloadResetHelper := preload("res://tests/helpers/autoload_reset_helper.gd")`
## et appelé en static. Bypass total class cache CI gdUnit4-action (la base class via héritage
## ne marche pas car gdUnit4 addon est gitignored — `GdUnitTestSuite` non résolu à l'init parser).
##
## Usage :
##   extends GdUnitTestSuite
##   const AutoloadResetHelper := preload("res://tests/helpers/autoload_reset_helper.gd")
##   var _snap: Dictionary = {}
##
##   func before_test() -> void:
##       _snap = AutoloadResetHelper.snapshot(get_tree())
##       # ... code spécifique à la suite
##
##   func after_test() -> void:
##       # ... code spécifique
##       AutoloadResetHelper.restore(get_tree(), _snap)
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
## Source : docs/tech-debt-register.md TD-010
## Plan   : production/tech-debt/story-w4-test-infra-autoload-reset-between-suites.md

extends RefCounted


## Capture l'état courant des autoloads dans un Dictionary snapshot.
static func snapshot(tree: SceneTree) -> Dictionary:
	var snap: Dictionary = {
		gsm_state = GameStateManager.get_current_state(),
		time_scale = Engine.time_scale,
		tree_paused = tree.paused,
	}

	# AudioSystem — accès direct au nœud autoload (pas de class_name exposé)
	var audio: Node = tree.root.get_node_or_null(^"AudioSystem")
	if audio != null:
		snap[&"audio_2d_index"] = audio._2d_index
		snap[&"audio_is_paused"] = audio._is_paused

	# VFXSystem
	var vfx: Node = tree.root.get_node_or_null(^"VFXSystem")
	if vfx != null:
		snap[&"vfx_flash_kill_active"] = vfx._flash_kill_active
		snap[&"vfx_flash_respawn_active"] = vfx._flash_respawn_active

	return snap


## Restaure l'état des autoloads depuis un Dictionary snapshot.
static func restore(tree: SceneTree, snap: Dictionary) -> void:
	if snap.is_empty():
		return

	# Engine — restaurer d'abord time_scale et paused (impactent le moteur entier)
	Engine.time_scale = snap.time_scale
	tree.paused = snap.tree_paused

	# GameStateManager — écriture directe du champ privé pour contourner les
	# assertions de transition légale (le snapshot peut être n'importe quel state).
	GameStateManager._current_state = snap.gsm_state

	# AudioSystem
	var audio: Node = tree.root.get_node_or_null(^"AudioSystem")
	if audio != null and snap.has(&"audio_2d_index"):
		audio._2d_index = snap[&"audio_2d_index"]
		audio._is_paused = snap[&"audio_is_paused"]

	# VFXSystem
	var vfx: Node = tree.root.get_node_or_null(^"VFXSystem")
	if vfx != null and snap.has(&"vfx_flash_kill_active"):
		vfx._flash_kill_active = snap[&"vfx_flash_kill_active"]
		vfx._flash_respawn_active = snap[&"vfx_flash_respawn_active"]
