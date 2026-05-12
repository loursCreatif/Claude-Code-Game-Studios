## AudioBuses — Constantes UPPER_SNAKE_CASE pour les bus audio du projet.
##
## Classe statique pure, PAS un autoload. Utiliser directement via AudioBuses.MUSIC etc.
## Évite la collision class_name ↔ autoload (cf. mémoire feedback_godot_class_name_autoload_collision).
##
## ADR-0009 D-1 : bus hierarchy 7-bus figée.
## Story-001 : implémentation initiale.

class_name AudioBuses
extends RefCounted

## Identifiants (UPPER_SNAKE_CASE per story authoring convention) →
## valeurs StringName matchant le bus_name réel dans AudioServer.
## Convention noms : ADR-0009 D-1 (PascalCase natifs + snake_case enfants),
## alignée sur contrainte engine Godot 4.6 (bus 0 forcé à "Master" silently).
const MASTER: StringName = &"Master"
const MUSIC: StringName = &"Music"
const SFX: StringName = &"SFX"
const SWING_ACTIVE: StringName = &"swing_active"
const COMBAT_KILL: StringName = &"combat_kill"
const AMBIENCE: StringName = &"Ambience"
const UI: StringName = &"UI"


static func set_volume(bus: StringName, volume_db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), volume_db)


static func get_volume(bus: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
