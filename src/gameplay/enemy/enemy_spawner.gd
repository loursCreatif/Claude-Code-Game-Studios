# EnemySpawner — helper static factory pour Grunts au boot d'étage.
#
# OQ-ENM-2 RESOLVED : pas d'autoload séparé. LevelSystem est l'orchestrateur direct,
# appelant `EnemySpawner.spawn_for_scene(scene_root)` juste avant `level_active.emit()`.
# Le helper est un Object pur — pas d'instance, pas de state, juste deux méthodes statiques.
#
# Story : enemy-system/story-003 (Core — LevelSystem spawn integration).
#
# Source GDD : Enemy GDD r2 Rule 9 (spawn iterate `EnemySlot_*` Marker3D), Rule 4
# (collision contract figé), EC-ENM-16 (archetype unknown fallback).

class_name EnemySpawner
extends Object


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GRUNT_SCENE_PATH: String = "res://src/gameplay/enemy/Grunt.tscn"
const ARCHETYPE_GRUNT: StringName = &"grunt"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Itère tous les `EnemySlot_*` Marker3D enfants de `scene_root`, instancie
## un `Grunt.tscn` par slot, copie position + orientation orthonormalisée
## (EC-ENM-6), et ajoute le grunt à `scene_root` directement.
##
## Archetype meta `&"grunt"` (default) → grunt direct. Archetype inconnu (ex.
## `&"drone"` Tier 2+ pas livré au MVP) → fallback grunt + push_warning
## (EC-ENM-16 : robustesse > strictness au runtime).
##
## Retourne la liste des Grunts spawnés (utile pour tests + debug logging).
## Retourne `[]` si `scene_root` null ou si Grunt.tscn introuvable (fail-loud).
static func spawn_for_scene(scene_root: Node3D) -> Array[Grunt]:
	var spawned: Array[Grunt] = []

	if scene_root == null:
		push_warning("EnemySpawner.spawn_for_scene: scene_root null — returning []")
		return spawned

	var grunt_packed: PackedScene = load(GRUNT_SCENE_PATH) as PackedScene
	if grunt_packed == null:
		push_error("EnemySpawner: %s introuvable ou non parsable" % GRUNT_SCENE_PATH)
		return spawned

	var slot_nodes: Array[Node] = scene_root.find_children(
		"EnemySlot_*", "Marker3D", true, false
	)

	for slot_node: Node in slot_nodes:
		var slot: Marker3D = slot_node as Marker3D
		if slot == null:
			continue

		# EC-ENM-16 : archetype meta avec fallback grunt + warning si inconnu.
		var archetype_value: Variant = slot.get_meta("archetype", ARCHETYPE_GRUNT)
		var archetype: StringName = StringName(str(archetype_value))
		if archetype != ARCHETYPE_GRUNT:
			push_warning(
				"Enemy archetype '%s' unknown — fallback to 'grunt'" % archetype
			)

		var grunt: Grunt = grunt_packed.instantiate() as Grunt
		if grunt == null:
			push_error("EnemySpawner: Grunt.tscn instantiate cast failed")
			continue

		scene_root.add_child(grunt)
		grunt.global_position = slot.global_position

		# EC-ENM-6 : orthonormalize l'orientation pour annuler tout scale non-uniforme
		# du Marker3D EnemySlot. Le grunt._ready() a déjà orthonormalisé sur basis
		# default IDENTITY ; cet override applique l'orientation du slot proprement.
		var pivot: Node3D = grunt.get_node_or_null("%FacingPivot") as Node3D
		if pivot != null:
			pivot.global_basis = slot.global_basis.orthonormalized()

		spawned.append(grunt)

	return spawned
