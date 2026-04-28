# Test helper Story-005 — sous-classe observable d'UpgradeSystem.
# Override apply_upgrade pour capturer la valeur de _is_hydrated mid-boucle
# (AC-UPG-23) sans toucher la production code path. Le helper est instance-bare
# only — usage : new() → set_logger_for_test() → seed save → _ready() → assert.
class_name ObservableUpgradeSystem
extends UpgradeSystem

## Snapshot de _is_hydrated capturé à chaque entrée de apply_upgrade pendant
## la boucle d'hydratation. AC-UPG-23 attend `[false, false, ...]` mid-loop
## puis `_is_hydrated == true` post-_ready().
var observed_hydration_during_loop: Array[bool] = []


func apply_upgrade(id: StringName) -> void:
	observed_hydration_during_loop.append(_is_hydrated)
	super.apply_upgrade(id)
