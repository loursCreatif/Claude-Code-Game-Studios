## CombatHitHandler — ShapeCast hit detection + substep anti-tunneling + kill resolution
## (Stories 005–012).
##
## Extrait de CombatSystem (TD-008 split). Possédé et instancié par CombatSystem.
## PAS de class_name — référencé via preload binding local dans combat_system.gd
## pour bypass class cache CI gdUnit4-action (même pattern que audio_combat_handler.gd).
##
## ADR-0006 D-3 (N_SUBSTEPS anti-tunneling, Formula 3).
## ADR-0008 D-3 (collision layers via API 1-indexée stricte).

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const CombatHitHandler := preload(...)`
# dans combat_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Injected references
# ---------------------------------------------------------------------------

## Référence injectée au Node CombatSystem parent.
## Accès à : _shape_cast, _camera_system, _prev_position, _hit_this_swing,
##           _slow_mo_handler.trigger_slow_mo_if_first_kill(), multi_kill.emit().
var _combat: Node = null


# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

## Exécute N_SUBSTEPS sweeps anti-tunneling et retourne les instance_ids dédupliqués
## des colliders touchés (story 009 — ADR-0006 D-3 Formula 3).
##
## Skip silencieusement si :
##   - `_shape_cast == null` (test scaffold edge)
##   - parent n'est pas Node3D
##   - aim invalide (story 007 — `validate_aim` retourne false)
func collect_swing_hits() -> Array[int]:
	var shape_cast: ShapeCast3D = _combat._shape_cast
	if shape_cast == null:
		return []
	var parent_3d: Node3D = _combat.get_parent() as Node3D
	if parent_3d == null:
		return []

	var aim: Vector3 = Vector3.FORWARD
	var camera: Node = _combat._camera_system
	if camera != null:
		var raw: Variant = camera.get("aim_forward")
		if raw is Vector3:
			var camera_aim: Vector3 = raw as Vector3
			if not validate_aim(camera_aim):
				return []
			aim = camera_aim

	var basis: Basis = build_capsule_basis(aim)
	var current_pos: Vector3 = parent_3d.global_position
	var collected: Array[Object] = []

	for i: int in _combat.N_SUBSTEPS:
		var segment: Array[Vector3] = compute_substep_segment(
			i, _combat._prev_position, current_pos, aim
		)
		var from_pos: Vector3 = segment[0]
		var to_pos: Vector3 = segment[1]
		shape_cast.global_transform = Transform3D(basis, from_pos)
		shape_cast.target_position = to_pos - from_pos
		shape_cast.force_shapecast_update()
		for j: int in shape_cast.get_collision_count():
			var c: Object = shape_cast.get_collider(j)
			if c != null:
				collected.append(c)

	return dedupe_collider_ids(collected)


## Story 011 + 012 — Résolution kill SYNC sur les hits du tick courant.
##
## Pipeline :
##   1. Filter : skip déjà dans `_hit_this_swing`, collider invalide, pas de `die()`,
##      déjà mort via `is_dead()` (AC-5), pas Node3D.
##   2. Sort ascending par distance squared (Pillar 1 zero-sqrt, story-012 AC-CMB-07).
##   3. Resolve : append id à `_hit_this_swing`, `c.die()`, trigger slow-mo, break au cap.
##   4. Multi-kill emit si kills >= 2 (story-012 AC-CMB-07).
func resolve_kills(hit_ids: Array[int]) -> void:
	# Phase 1 : filter candidates
	var candidates: Array[Node3D] = []
	for id: int in hit_ids:
		if id in _combat._hit_this_swing:
			continue
		var c: Object = instance_from_id(id)
		if not is_instance_valid(c):
			continue
		if not c.has_method("die"):
			if OS.is_debug_build():
				push_warning("Combat: collider layer=2 sans 'die()' — skipped, id=%d" % id)
			continue
		if c.has_method("is_dead") and c.is_dead():
			continue
		var node: Node3D = c as Node3D
		if node == null:
			continue
		candidates.append(node)

	# Phase 2 : sort by distance squared ascending (Pillar 1 zero-sqrt)
	if candidates.size() > 1:
		var parent: Node3D = _combat.get_parent() as Node3D
		if parent != null:
			var pp: Vector3 = parent.global_position
			candidates.sort_custom(
				func(a: Node3D, b: Node3D) -> bool:
					return pp.distance_squared_to(a.global_position) < \
						pp.distance_squared_to(b.global_position)
			)

	# Phase 3 : resolve up to MAX_KILLS_PER_SWING
	var kills_this_tick: int = 0
	for c: Node3D in candidates:
		if _combat._hit_this_swing.size() >= _combat.MAX_KILLS_PER_SWING:
			break
		_combat._hit_this_swing.append(c.get_instance_id())
		c.call("die")
		_combat._slow_mo_handler.trigger_slow_mo_if_first_kill()
		kills_this_tick += 1

	# Phase 4 : multi-kill emit
	if kills_this_tick >= 2:
		_combat.multi_kill.emit(kills_this_tick)


## Repositionne ShapeCast3D au tick courant (story 007 entrée + story 008 per-tick).
##
## Skip silencieusement si aim invalide mid-swing (laisse ShapeCast à sa dernière
## position connue — meilleur que désactiver le sweep entier sur un tick foireux isolé).
func update_sweep_origin() -> void:
	var shape_cast: ShapeCast3D = _combat._shape_cast
	if shape_cast == null:
		return
	var parent_3d: Node3D = _combat.get_parent() as Node3D
	if parent_3d == null:
		return

	var aim: Vector3 = Vector3.FORWARD
	var camera: Node = _combat._camera_system
	if camera != null:
		var raw: Variant = camera.get("aim_forward")
		if raw is Vector3:
			var camera_aim: Vector3 = raw as Vector3
			if not validate_aim(camera_aim):
				return
			aim = camera_aim

	var sweep_origin: Vector3 = parent_3d.global_position + aim * (_combat.KATANA_REACH / 2.0)
	shape_cast.global_transform = Transform3D(build_capsule_basis(aim), sweep_origin)


## Calcule les positions de début/fin d'un substep i ∈ [0, N_SUBSTEPS-1] (story 009).
##
## Interpolation linéaire entre `prev` et `current` avec offset `aim × KATANA_REACH/2`.
## Pure function — testable sans physics.
func compute_substep_segment(
		i: int,
		prev: Vector3,
		current: Vector3,
		aim: Vector3
) -> Array[Vector3]:
	var t0: float = float(i) / float(_combat.N_SUBSTEPS)
	var t1: float = float(i + 1) / float(_combat.N_SUBSTEPS)
	var offset: Vector3 = aim * (_combat.KATANA_REACH / 2.0)
	var result: Array[Vector3] = [
		prev.lerp(current, t0) + offset,
		prev.lerp(current, t1) + offset
	]
	return result


## Déduplique une liste de colliders par `instance_id` (story 009 AC-4).
##
## Skip silencieusement les `null`. Pure function.
func dedupe_collider_ids(colliders: Array[Object]) -> Array[int]:
	var seen: Dictionary = {}
	var result: Array[int] = []
	for obj: Object in colliders:
		if obj == null:
			continue
		var id: int = obj.get_instance_id()
		if not (id in seen):
			seen[id] = true
			result.append(id)
	return result


## Construit une `Basis` orientée pour la CapsuleShape3D du katana telle que
## son axe Y local soit aligné sur `forward` (AC-CMB-08 r6 / story 005).
##
## Pattern cross-product direct (PAS `Basis.looking_at × from_euler(±π/2)` —
## bug CONV-1 r5.2 documenté ADR-0006 D-7).
##
## Pré-condition : `forward.is_normalized()` (Camera Rule 13). Assert en debug.
func build_capsule_basis(forward: Vector3) -> Basis:
	assert(forward.is_normalized(), "aim_forward doit être unit vector (Camera Rule 13)")

	var safe_up: Vector3 = Vector3.UP
	if absf(forward.dot(Vector3.UP)) > 0.999:
		safe_up = Vector3.FORWARD

	var right: Vector3 = safe_up.cross(forward).normalized()
	var local_z: Vector3 = right.cross(forward)
	var b: Basis = Basis(right, forward, local_z)

	if absf(b.determinant()) < 0.01:
		push_error(
			"_build_capsule_basis: basis quasi-singulière, fallback IDENTITY — forward=%v"
			% forward
		)
		return Basis.IDENTITY
	return b


## Validation aim_forward avant utilisation (story 007 AC-CMB-27 / AC-CMB-48).
##
## Refuse NaN/inf et vecteur quasi-zéro. En debug émet push_error. Pure function.
func validate_aim(aim: Vector3) -> bool:
	if not aim.is_finite():
		if OS.is_debug_build():
			push_error("Combat: aim_forward NaN/inf — swing ignoré (forward=%v)" % aim)
		return false
	if aim.is_zero_approx():
		if OS.is_debug_build():
			push_error("Combat: aim_forward zero — swing ignoré")
		return false
	return true
