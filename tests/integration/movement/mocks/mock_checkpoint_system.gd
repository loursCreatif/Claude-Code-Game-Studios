## MockCheckpointSystem — consumer conforme ADR-0005 D-7 (no Movement state mutation).
## Appelle uniquement player.set_checkpoint(pos) — API publique.
## N'écrit jamais l'état interne du Movement (velocity, _state).
## Vit dans tests/, pas dans src/ — purement test fixture.
##
## ADR-0005 D-7 : aucune mutation d'état Movement depuis un consommateur externe.
##
## Story: story-015-cross-system-mocks
class_name MockCheckpointSystem
extends Node

# ---------------------------------------------------------------------------
# Public variables
# ---------------------------------------------------------------------------

## Référence explicite au joueur. Si null dans _ready(), fallback sibling ../Player.
## Injection explicite recommandée dans les tests.
var player: MovementController = null

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	if player == null:
		player = get_node("../Player") as MovementController

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Enregistre un checkpoint à pos en appelant l'API publique set_checkpoint().
## AC-MV-81 : set_checkpoint(pos) puis die() déclenché côté test → respawn à pos.
## D-7 compliant : n'écrit jamais player.velocity ni player._state.
## N'appelle jamais die() — c'est le rôle du test, pas du mock.
func set_checkpoint_at(pos: Vector3) -> void:
	if player != null:
		player.set_checkpoint(pos)
