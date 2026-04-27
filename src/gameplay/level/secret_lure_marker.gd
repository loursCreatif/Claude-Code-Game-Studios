## Marker3D de lure pour les zones secrètes d'étage.
##
## Positionné dans SpawnMarkers sous le nom SecretLureMarker_NN. Indique l'endroit
## visible cross-room depuis lequel le VFX de lure sera spawné par le futur Secret System.
## Le champ required_ability annote l'abilité de locomotion requise pour atteindre ce secret.
##
## Convention authoring triplet (story-018 AC-LVL-53) :
##   - SecretLureMarker_NN (ce script) sous SpawnMarkers
##   - SecretCollectVolume_NN Area3D sous InteractiveVolumes
##   - SecretAnchor_NN Marker3D sous SpawnMarkers
##
## Choix @export StringName vs @export_enum :
##   @export var required_ability: StringName est préféré en Godot 4.6 car :
##   (1) l'inspector affiche un champ texte direct compatible StringName literals ;
##   (2) les constantes SecretAbilities.* sont des StringName → pas de conversion ;
##   (3) @export_enum forcerait un String puis un cast, introduisant un indirection
##       et une alloc à chaque lecture inspector.
##   Inconvénient : pas de dropdown inspector natif — l'auteur doit saisir la valeur.
##   Ce trade-off est acceptable au MVP (peu d'auteurs, valeurs documentées ci-dessus).
##   Si le feedback design demande un dropdown, migrer vers @export_enum + getter
##   get_required_ability() -> StringName (amendement story-018 r3).
##
## @tool : expose required_ability dans l'inspector pendant le level authoring.
##
## Source : story-018 AC-LVL-46 / AC-LVL-53, GDD level-system.md F7.
@tool
extends Marker3D
class_name SecretLureMarker

## Abilité de locomotion requise pour atteindre ce secret.
## Doit être l'une des constantes de SecretAbilities : none / dash / double_jump / wall_run / wall_run_long.
## Default SecretAbilities.NONE : secret librement accessible — authoring explicite requis.
## Valeur vide ("") ou valeur hors-canon → lint fail (AC-LVL-53).
@export var required_ability: StringName = SecretAbilities.NONE
