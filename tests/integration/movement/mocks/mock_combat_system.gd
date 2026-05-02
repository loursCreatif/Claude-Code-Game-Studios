## MockCombatSystem — consumer conforme ADR-0005 D-10 (outbound-only).
## Lit l'API publique Movement (is_dashing, velocity) et connecte le signal attacked.
## NE MUTE JAMAIS l'état Movement (D-7 respect).
## Vit dans tests/, pas dans src/ — purement test fixture.
##
## ADR-0005 D-10 : Movement n'a aucune connaissance de ce mock.
## Les consommateurs se connectent eux-mêmes depuis leur _ready().
##
## Story: story-015-cross-system-mocks
class_name MockCombatSystem
extends Node

# ---------------------------------------------------------------------------
# Public variables
# ---------------------------------------------------------------------------

## Dernière velocity capturée pendant is_dashing == true.
## Initialisée à ZERO ; mise à jour chaque physics tick où le joueur dashe.
## AC-MV-80 : last_sweep_velocity.length() ≈ DASH_SPEED pendant is_dashing.
var last_sweep_velocity: Vector3 = Vector3.ZERO

## Nombre d'émissions du signal attacked reçues depuis la connexion.
## AC : attacked signal propagation — incrémenté dans _on_attacked().
var attack_count: int = 0

## Référence explicite au joueur. Si null dans _ready(), fallback sibling ../Player.
## Injection explicite recommandée dans les tests (pas de dépendance au scène-tree).
var player: MovementController = null

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	if player == null:
		player = get_node("../Player") as MovementController
	if player != null:
		player.attacked.connect(_on_attacked)


func _physics_process(_delta: float) -> void:
	if player != null and player.is_dashing:
		last_sweep_velocity = player.velocity

# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_attacked() -> void:
	attack_count += 1
