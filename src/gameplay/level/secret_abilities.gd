## Constantes canoniques pour les valeurs de required_ability des SecretLureMarker.
##
## Utilisé par SecretLureMarker (@export required_ability) et par LevelLint.validate_secret_lures()
## pour valider que chaque lure a une annotation correcte.
##
## StringName pré-alloués (&"…" literals) : zéro allocation — les StringName literals sont
## internés une fois au chargement du script, aucun alloc à la comparaison (ADR-0004 pattern).
##
## Choix Array[StringName] const plutôt que static func valid_abilities() -> Array[StringName] :
## une static func realloue un nouvel Array à chaque appel ; la const est évaluée une fois
## et partagée par référence. Cohérent avec les VALID_ARCHETYPES / VALID_FINAL_ARCHETYPES
## de level_lint.gd.
##
## Source : story-018 AC-LVL-46 / AC-LVL-53, GDD level-system.md F7.
class_name SecretAbilities
extends RefCounted

## Pas d'abilité requise — secret librement accessible.
const NONE: StringName = &"none"

## Requiert le Dash pour atteindre la zone secrète.
const DASH: StringName = &"dash"

## Requiert le Double Jump pour atteindre la zone secrète.
const DOUBLE_JUMP: StringName = &"double_jump"

## Requiert le Wall Run (court) pour atteindre la zone secrète.
const WALL_RUN: StringName = &"wall_run"

## Requiert le Wall Run long (traversée complète) pour atteindre la zone secrète.
const WALL_RUN_LONG: StringName = &"wall_run_long"

## Ensemble complet des valeurs valides pour required_ability.
## Utilisé par validate_secret_lures (AC-LVL-53) pour le membership check O(1).
## const plutôt que static func → Array partagé par référence, zéro alloc par appel.
const VALID_ABILITIES: Array[StringName] = [NONE, DASH, DOUBLE_JUMP, WALL_RUN, WALL_RUN_LONG]

## Abilités satisfaisant la contrainte économique pillar 4 (AC-LVL-46 F7).
## ≥ 1 secret par étage doit requérir une de ces abilités.
const ECONOMIC_CONSTRAINT_ABILITIES: Array[StringName] = [WALL_RUN, WALL_RUN_LONG]


## Retourne true si l'abilité donnée fait partie des valeurs canoniques valides.
## [param ability] : StringName à tester.
## [return] : true si ability ∈ VALID_ABILITIES.
static func is_valid(ability: StringName) -> bool:
	return VALID_ABILITIES.has(ability)


## Retourne true si l'abilité satisfait la contrainte de gating économique (AC-LVL-46).
## [param ability] : StringName à tester.
## [return] : true si ability ∈ ECONOMIC_CONSTRAINT_ABILITIES.
static func is_economic_gating(ability: StringName) -> bool:
	return ECONOMIC_CONSTRAINT_ABILITIES.has(ability)


## Compatibilité : retourne la liste complète des valeurs valides.
## @deprecated : préférer VALID_ABILITIES (const, zéro alloc). Conservé pour
## la rétrocompatibilité avec les callers éventuels antérieurs à story-018 r2.
## [return] : Array[StringName] de taille 5 — [NONE, DASH, DOUBLE_JUMP, WALL_RUN, WALL_RUN_LONG].
static func valid_abilities() -> Array[StringName]:
	return [NONE, DASH, DOUBLE_JUMP, WALL_RUN, WALL_RUN_LONG]
