# Production logger wrapper pour UpgradeSystem.
# Story-002 : Logger DI pattern (R-UPG-9 + GDD r2 B-11) — substitution
# `push_warning(msg)` direct par `_logger.warn(msg)` injectable pour tests.
# Default production behaviour identique à push_warning() — aucune surcharge.
class_name UpgradeLogger
extends RefCounted


## Émet un warning runtime via push_warning (chemin production par défaut).
## Sous-classes (TestUpgradeLogger) overrident pour capturer les messages.
func warn(msg: String) -> void:
	push_warning(msg)
