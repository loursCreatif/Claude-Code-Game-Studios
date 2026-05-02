# Mock Player pour les tests nécessitant player.wall_normal.
# Utilisé par story-005 et toute story future testant des features qui
# consomment wall_normal avant que Movement stories soient Complete.
#
# Design : CharacterBody3D minimal — expose uniquement les propriétés
# nécessaires à CameraSystem. Ne contient aucune logique de mouvement.

class_name MockPlayerWithWallNormal
extends CharacterBody3D

## Normale du mur courant. Vector3.ZERO = pas en wall-run.
## Owned par Movement en production — ici manipulable directement dans les tests.
var wall_normal: Vector3 = Vector3.ZERO
