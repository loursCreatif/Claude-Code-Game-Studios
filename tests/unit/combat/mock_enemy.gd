# MockEnemy — fixture lightweight pour les tests unitaires Combat (Gap 1).
#
# Contract minimal requis par story-011 / story-012 :
# - `die() -> void` idempotent (multi-calls = no-op silent).
# - `is_dead() -> bool` reflète l'état post-die().
# - StaticBody3D layer=2 (LAYER_ENEMY) pour que ShapeCast3D Combat le détecte.
#
# Note : volontairement minimal vs Grunt réel (`src/gameplay/enemy/grunt.gd`).
# Pas de LaserCone, pas de Tween scale, pas de signal `enemy_killed` (Combat
# story-011 consomme le die() return ; le SYNC signal Grunt est testé en suite
# Enemy). Cela isole les tests Combat unit de la complexité scene Grunt.tscn.
#
# Story-011 valide qu'un fixture qui respecte ce contract suffit pour la
# résolution kill — Grunt réel est testé en intégration cross-system (story-018
# soak + Enemy story-004).

# NB : pas de `class_name` — le cache `.godot/global_script_class_cache.cfg` n'est
# rebuildé qu'à l'ouverture éditeur, ce qui casse les CI headless. Les tests
# utilisent `preload("res://tests/unit/combat/mock_enemy.gd")` directement.
extends StaticBody3D


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _is_dead: bool = false
var _die_count: int = 0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# LAYER_ENEMY=2 (ADR-0008). Force-clear other bits pour parité Grunt._set_layers_safe.
	for i in range(1, 33):
		set_collision_layer_value(i, false)
		set_collision_mask_value(i, false)
	set_collision_layer_value(2, true)


# ---------------------------------------------------------------------------
# Combat contract (parité Grunt)
# ---------------------------------------------------------------------------

## API canonique appelée par Combat sweep (story-011 AC-CMB-05).
## Idempotent (story-011 AC-CMB-06) : appels 2+ sont no-op silencieux.
## `_die_count` exposé pour assertions tests (vérifie no-double-call).
func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_die_count += 1


## Getter Combat skip-filter (story-011 AC-5 + Grunt parity).
func is_dead() -> bool:
	return _is_dead
