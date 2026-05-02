## Script d'authoring pour un nœud Room_NN dans la hiérarchie StaticEnvironment.
##
## Déclaration des propriétés exportées pour l'éditeur et le lint de scène.
## Aucune logique runtime — ce script sert uniquement à la configuration authoring-time.
##
## Utilisation :
##   Attacher ce script à un Node3D nommé Room_NN sous StaticEnvironment.
##   Définir `archetype` via l'Inspector ou par property override dans .tscn.
##
## Rétrocompat r1 :
##   `room_type_legacy` est un champ deprecated (migration r1 → r2).
##   Les nouveaux Room_NN doivent utiliser `archetype` directement.
##   La valeur -1 est le sentinel "non défini" — distingue l'absence d'un choix
##   explicite du legacy 0 (ARENA).
##
## Source GDD : design/gdd/level-system.md R-2.6 r2 (APPROVED r3).
## TR       : TR-lvl-016 (story-011).
## ADR      : N/A — GDD-owned R-2.6.
class_name Room
extends Node3D

# ---------------------------------------------------------------------------
# Exports authoring
# ---------------------------------------------------------------------------

## Archétype de la salle — valeur r2 obligatoire.
## -1 = non défini (sentinel "UNSET") ; 0..3 = valeur RoomArchetype.Type valide.
## Utiliser l'enum : TRAVERSAL=0, COMBAT=1, SHAFT=2, SECRET_HUB=3.
## Plan privilégié : TRAVERSAL (R-2.A GDD).
@export_enum("UNSET:-1", "TRAVERSAL:0", "COMBAT:1", "SHAFT:2", "SECRET_HUB:3")
var archetype: int = -1

## [DEPRECATED r1] Type de salle hérité de l'enum r1.
## Conservé pour la migration — NE PAS utiliser dans les nouveaux Room_NN.
## Valeurs r1 : 0=ARENA, 1=CORRIDOR, 2=VERTICAL_CHAMBER, 3=JUNCTION.
## -1 = sentinel "non défini" (aucun legacy room_type assigné).
## Le lint détectera ce champ et appliquera l'auto-conversion avec push_warning.
@export var room_type_legacy: int = -1
