# Helper canonique pour la taxonomie 5-layer du MVP (ADR-0008 D-1/D-3).
#
# Source unique de vérité côté code GDScript pour les noms de layers 1-indexés.
# Les valeurs entières sont synchronisées avec project.godot [layer_names]/3d_physics/layer_N
# (ADR-0008 D-4) — toute modification ici doit être reflétée dans project.godot.
#
# Utilisation type :
#   body.set_collision_layer_value(CollisionLayers.LAYER_PLAYER, true)
#   query.collision_mask = CollisionLayers.build_mask([CollisionLayers.LAYER_ENEMY])
#
# Forbidden (lint D-6) :
#   body.collision_layer = 0b00001          # bitmask littéral
#   body.collision_layer |= (1 << 0)        # bit manipulation
#   query.collision_mask = 2                # décimal direct

class_name CollisionLayers
extends Object

const LAYER_PLAYER: int = 1
const LAYER_ENEMY: int = 2
const LAYER_ENEMY_HITBOX: int = 3
const LAYER_ENVIRONMENT: int = 4
const LAYER_INTERACTIVE: int = 5

## Construit un bitmask à partir d'une liste de layers 1-indexées.
## Usage : PhysicsRayQueryParameters3D / PhysicsShapeQueryParameters3D
## qui exposent uniquement `collision_mask: int` sans API per-bit.
##
## Exemple : build_mask([LAYER_ENEMY, LAYER_ENVIRONMENT]) == (1<<1) | (1<<3) == 10
##
## Tous les éléments doivent être dans [1, 32]. Layers 6-32 réservées (ADR-0008 D-5).
static func build_mask(layers_1idx: Array[int]) -> int:
	var m: int = 0
	for layer: int in layers_1idx:
		assert(layer >= 1 and layer <= 32,
			"Layer doit être 1-indexée et ≤ 32 (reçu: %d)" % layer)
		m |= 1 << (layer - 1)
	return m
