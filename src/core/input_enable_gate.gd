## InputEnableGate — Gestion refcount du enable/disable InputManager.
##
## Extrait de input_manager.gd (TD-008 split). Pas de class_name : bypass class cache
## CI gdUnit4 (pattern preload binding, voir feedback_godot_class_name_autoload_collision).
##
## Encapsule le dictionnaire _enable_blockers et la logique refcount (ADR-0004 D-4,
## TR-inp-005). InputManager délègue request_disable / release_enable_request / auto-cleanup
## à cette classe. Le signal enabled_changed reste sur InputManager (ownership signal clair).
##
## Main-thread only (ADR-0004 D-7) — pas d'accès depuis Thread ou WorkerThreadPool.

extends RefCounted

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Dictionnaire des blockers refcount. Clé : owner_id (int), Valeur : true.
## Modifié uniquement via request_disable() / release() / _on_blocker_tree_exited().
var _enable_blockers: Dictionary = {}

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## Retourne true si aucun bloqueur actif (=> InputManager doit être enabled).
## Usage : if gate.is_enabled(): ...
func is_enabled() -> bool:
	return _enable_blockers.is_empty()

# ---------------------------------------------------------------------------
# Mutations (appelées depuis InputManager, main-thread only)
# ---------------------------------------------------------------------------

## Enregistre [param owner] comme bloqueur. Idempotent.
## Retourne true si le bloqueur a été ajouté (false = déjà présent).
## L'appelant (InputManager) doit connecter tree_exited → _on_blocker_tree_exited
## et appeler _update_enabled_state() après.
## Usage : if gate.add_blocker(owner): owner.tree_exited.connect(...)
func add_blocker(owner: Node) -> bool:
	assert(owner != null, "InputEnableGate.add_blocker: owner must not be null")
	var id: int = owner.get_instance_id()
	if _enable_blockers.has(id):
		return false  # Idempotent — déjà enregistré.
	_enable_blockers[id] = true
	return true

## Retire [param owner] de la liste des bloqueurs.
## Retourne true si le bloqueur existait et a été retiré.
## Usage : if gate.remove_blocker(owner): ...
func remove_blocker(owner: Node) -> bool:
	if owner == null:
		return false
	return _enable_blockers.erase(owner.get_instance_id())

## Retire un bloqueur par id (utilisé par le callback tree_exited — l'owner peut
## être freed à ce moment, donc on ne peut pas appeler get_instance_id() dessus).
## Retourne true si le bloqueur existait et a été retiré.
## Usage : if gate.remove_blocker_by_id(owner_id): ...
func remove_blocker_by_id(owner_id: int) -> bool:
	return _enable_blockers.erase(owner_id)
