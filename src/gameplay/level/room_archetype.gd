## Définition de l'enum RoomArchetype et helpers de conversion legacy r1 → r2.
##
## Source GDD : design/gdd/level-system.md R-2.6 r2 (APPROVED r3).
## TR       : TR-lvl-016 (story-011).
## ADR      : N/A — GDD-owned R-2.6.
##
## Utilisé par :
##   - src/gameplay/level/room.gd  (@export archetype)
##   - tools/lint/level_lint.gd    (validate_room_archetypes)
class_name RoomArchetype
extends RefCounted

# ---------------------------------------------------------------------------
# Enum principal (r2)
# ---------------------------------------------------------------------------

## Archétypes de salle définis par GDD R-2.6 r2.
## TRAVERSAL   : salle de traversée / plateforme (plan privilégié R-2.A).
## COMBAT      : salle de combat.
## SHAFT       : puits vertical / connecteur de niveaux.
## SECRET_HUB  : hub secret / salle optionnelle cachée.
enum Type {
	TRAVERSAL,   ## 0
	COMBAT,      ## 1
	SHAFT,       ## 2
	SECRET_HUB,  ## 3
}

# ---------------------------------------------------------------------------
# Constantes de mapping legacy r1 → r2
# ---------------------------------------------------------------------------
## Valeur enum r1 pour ARENA (mappée vers COMBAT r2).
const LEGACY_ARENA: int = 0
## Valeur enum r1 pour CORRIDOR (mappée vers TRAVERSAL r2).
const LEGACY_CORRIDOR: int = 1
## Valeur enum r1 pour VERTICAL_CHAMBER (mappée vers SHAFT r2).
const LEGACY_VERTICAL_CHAMBER: int = 2
## Valeur enum r1 pour JUNCTION (mappée vers SECRET_HUB r2).
const LEGACY_JUNCTION: int = 3

# ---------------------------------------------------------------------------
# API publique
# ---------------------------------------------------------------------------

## Convertit une valeur enum r1 vers la valeur Type r2 correspondante.
##
## Mapping obligatoire GDD R-2.6 r2 :
##   ARENA (0)            → COMBAT (1)
##   CORRIDOR (1)         → TRAVERSAL (0)
##   VERTICAL_CHAMBER (2) → SHAFT (2)
##   JUNCTION (3)         → SECRET_HUB (3)
##
## [param legacy] : valeur entière de l'enum r1.
## [return] : valeur Type r2 correspondante (int 0..3), ou -1 (sentinel hors-enum,
## intentionnel — Type ne contient pas de membre UNSET) si la valeur est inconnue.
static func from_legacy_room_type(legacy: int) -> int:
	match legacy:
		LEGACY_ARENA:
			return Type.COMBAT
		LEGACY_CORRIDOR:
			return Type.TRAVERSAL
		LEGACY_VERTICAL_CHAMBER:
			return Type.SHAFT
		LEGACY_JUNCTION:
			return Type.SECRET_HUB
		_:
			return -1
