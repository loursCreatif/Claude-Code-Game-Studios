@tool
class_name StaticSurface
extends StaticBody3D

## Composant de tagging de surface physique pour le routing Audio System.
##
## Attaché sur un StaticBody3D, expose @export var surface_material pour
## que l'Audio System (épic futur) puisse router les footstep SFX selon
## le matériau sous le joueur (béton → gravel, métal → metal_clang, etc.).
##
## Convention de nommage : "concrete" | "metal" | "glass" | "none"
## Valeur par défaut "concrete" si propriété absente sur le StaticBody3D
## (rétrocompatibilité : les corps non-tagués reçoivent le matériau béton).
##
## Source : TR-lvl-042, story-022 AC-LVL-44, ADR-0005 D-10.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Valeurs valides de surface_material.
## Utilisé par is_valid_surface_material() et LevelSystemScript.get_surface_material_for().
const VALID_SURFACE_MATERIALS: Array[String] = ["concrete", "metal", "glass", "none"]

# ---------------------------------------------------------------------------
# Export variables
# ---------------------------------------------------------------------------

## Identifiant du matériau physique de cette surface.
## Consommé par l'Audio System au footstep event pour router vers le bon bus SFX.
## Valeurs valides : "concrete" | "metal" | "glass" | "none"
## Défaut "concrete" = matériau le plus courant dans l'environnement MVP Chrome Zen.
@export var surface_material: String = "concrete"

# ---------------------------------------------------------------------------
# Public static helpers
# ---------------------------------------------------------------------------

## Retourne true si [s] est une valeur de surface_material valide.
## Utilisé par le lint et par LevelSystemScript.get_surface_material_for()
## pour la validation de la valeur exportée.
##
## [param s] : chaîne à valider.
## [return] : true si s ∈ VALID_SURFACE_MATERIALS.
static func is_valid_surface_material(s: String) -> bool:
	return VALID_SURFACE_MATERIALS.has(s)
