## LevelSceneQueries — API publique de lecture de la scène d'étage active.
##
## Possédé et instancié par LevelSystemScript (composition). Reçoit une
## référence injectée vers le Node LevelSystem pour accéder à _current_scene_root.
## PAS un autoload — PAS de class_name (référencé via preload binding local
## dans level_system.gd pour bypass class cache CI gdUnit4-action).
##
## Responsabilités :
##   - get_checkpoint_slots, get_enemy_slots, get_hazard_slots
##   - get_tutorial_anchor, get_secret_slots, get_onboarding_anchors
##   - get_surface_material_for
##   - validate_checkpoint_anchors (debug authoring check)
##
## Ces méthodes ne sont pas en hot path (appelées 1× par peer au handler
## level_active) — coût find_children O(n) acceptable.
##
## ADR-0005 D-10 (API publique read-only consommée par peers).
## Source : AC-LVL-30/30b/30c/44/46/53/54(c), story-009/018/019/021/022.

extends RefCounted

# NOTE : pas de `class_name` — référencé via `const LevelSceneQueries := preload(...)`
# dans level_system.gd pour bypass l'absence de class cache en CI Run GdUnit4 Tests.


# ---------------------------------------------------------------------------
# Injected reference
# ---------------------------------------------------------------------------

## Référence injectée à LevelSystemScript (Node) — pour accéder à
## _current_scene_root via _get_scene_root().
## Injectée dans LevelSystemScript._ready() après instanciation.
var _level: Node = null


# ---------------------------------------------------------------------------
# Spatial lookup helpers
# ---------------------------------------------------------------------------

## Retourne tuples paired { volume: Area3D, anchor: Vector3 } pour chaque
## CheckpointVolume_NN ↔ CheckpointAnchor_NN dans la scène active.
## Source : AC-LVL-30b, ADR-0005 D-10.
##
## Volume sans anchor paired → push_warning + skip. 0 checkpoints = [].
## Guard scene_root null → return [] + push_warning.
func get_checkpoint_slots() -> Array:
	var root: Node3D = _level._get_scene_root()
	if root == null:
		push_warning("get_checkpoint_slots called before level_active — returning empty array")
		return []
	var slots: Array = []
	var volumes: Array[Node] = root.find_children("CheckpointVolume_*", "Area3D", true, false)
	for v: Node in volumes:
		var area: Area3D = v as Area3D
		var idx: String = area.name.trim_prefix("CheckpointVolume_")
		var anchor_node: Node = root.find_child("CheckpointAnchor_" + idx, true, false)
		if anchor_node == null:
			push_warning("CheckpointVolume_%s missing paired CheckpointAnchor" % idx)
			continue
		var anchor: Marker3D = anchor_node as Marker3D
		if anchor == null:
			push_warning("CheckpointAnchor_%s exists but is not a Marker3D" % idx)
			continue
		slots.append({"volume": area, "anchor": anchor.global_position})
	return slots


## Retourne tous les EnemySlot_* Marker3D de la scène active.
## Source : AC-LVL-30b, ADR-0005 D-10.
## Order = DFS preorder Godot (EC-5 TR-lvl-031 deterministic ordering).
## Guard scene_root null → return [] + push_warning.
func get_enemy_slots() -> Array[Marker3D]:
	var root: Node3D = _level._get_scene_root()
	if root == null:
		push_warning("get_enemy_slots called before level_active — returning empty array")
		return []
	var nodes: Array[Node] = root.find_children("EnemySlot_*", "Marker3D", true, false)
	var result: Array[Marker3D] = []
	for n: Node in nodes:
		result.append(n as Marker3D)
	return result


## Retourne tous les HazardSlot_* Marker3D de la scène active.
## Source : AC-LVL-30b, ADR-0005 D-10.
## Guard scene_root null → return [] + push_warning.
func get_hazard_slots() -> Array[Marker3D]:
	var root: Node3D = _level._get_scene_root()
	if root == null:
		push_warning("get_hazard_slots called before level_active — returning empty array")
		return []
	var nodes: Array[Node] = root.find_children("HazardSlot_*", "Marker3D", true, false)
	var result: Array[Marker3D] = []
	for n: Node in nodes:
		result.append(n as Marker3D)
	return result


## Retourne le Marker3D dont le nom == tag, null si introuvable.
## Source : AC-LVL-30, ADR-0005 D-10.
## Tag introuvable → push_warning + null. Guard scene_root null → null + push_warning.
func get_tutorial_anchor(tag: String) -> Marker3D:
	var root: Node3D = _level._get_scene_root()
	if root == null:
		push_warning("get_tutorial_anchor called before level_active — returning null")
		return null
	var markers: Array[Node] = root.find_children(tag, "Marker3D", true, false)
	if markers.is_empty():
		push_warning("tutorial anchor not found: %s" % tag)
		return null
	return markers[0] as Marker3D


## Retourne tous les triplets secret (lure, collect_volume, content_anchor,
## required_ability) de la scène active.
## Source : AC-LVL-46 / AC-LVL-53 (story-018 r2), ADR-0005 D-10.
##
## Convention : SecretLureMarker_01 ↔ SecretCollectVolume_01 ↔ SecretAnchor_01.
## Triplet incomplet → push_warning + skip. 0 secrets = [].
## Guard scene_root null → [] + push_warning.
##
## Clés du Dictionary :
##   "lure"            : Marker3D
##   "collect_volume"  : Area3D
##   "content_anchor"  : Vector3 (position globale)
##   "required_ability": StringName
func get_secret_slots() -> Array[Dictionary]:
	var root: Node3D = _level._get_scene_root()
	if root == null:
		push_warning("get_secret_slots called before level_active — returning empty array")
		return []
	var slots: Array[Dictionary] = []
	var lures: Array[Node] = root.find_children("SecretLureMarker_*", "Marker3D", true, false)
	for l: Node in lures:
		var lure: Marker3D = l as Marker3D
		if lure == null:
			continue
		var idx: String = String(lure.name).trim_prefix("SecretLureMarker_")
		var collect_node: Node = root.find_child("SecretCollectVolume_" + idx, true, false)
		var anchor_node: Node = root.find_child("SecretAnchor_" + idx, true, false)
		if collect_node == null:
			push_warning("SecretLureMarker_%s missing paired SecretCollectVolume" % idx)
			continue
		if anchor_node == null:
			push_warning("SecretLureMarker_%s missing paired SecretAnchor" % idx)
			continue
		var collect: Area3D = collect_node as Area3D
		var anchor: Marker3D = anchor_node as Marker3D
		if collect == null or anchor == null:
			push_warning(
				"Secret triplet %s : type incorrect (volume=%s, anchor=%s)" % [
					idx, collect_node.get_class(), anchor_node.get_class()
				]
			)
			continue
		# Lookup permissif via Object.get() : `as SecretLureMarker` ne peut pas
		# être utilisé ici car level_system.gd est chargé comme autoload AVANT
		# que la SceneTree complète peuple le registry class_name (cf. pattern
		# `const Script: GDScript = preload(...)` adopté par level_lint.gd pour
		# la même raison). Si la scène contient un Marker3D nommé SecretLureMarker_NN
		# sans le script attaché, .get() retourne null → fallback &"" (lint
		# signalera la violation séparément AC-LVL-53).
		var ability: Variant = lure.get("required_ability")
		var ability_sn: StringName = &"" if ability == null else (ability as StringName)
		slots.append({
			"lure": lure,
			"collect_volume": collect,
			"content_anchor": anchor.global_position,
			"required_ability": ability_sn,
		})
	return slots


## Retourne les anchors d'onboarding Combat (FirstEnemySightline + SafeZoneCenter).
## Source : AC-LVL-54(c), story-019, ADR-0005 D-10.
##
## Convention : sous-arbre OnboardingAnchors enfant direct du Level root.
## Étage ≠ 1 (OnboardingAnchors absent) → {} non-fatal (AC-LVL-54(c)).
## Sous-arbre incomplet → push_warning + {}.
## Guard scene_root null → push_warning + {}.
##
## Clés : "first_enemy_sightline" : Marker3D, "safe_zone_center" : Marker3D.
func get_onboarding_anchors() -> Dictionary:
	var root: Node3D = _level._get_scene_root()
	if root == null:
		push_warning("get_onboarding_anchors called before level_active — returning empty dict")
		return {}
	var anchors: Node = root.find_child("OnboardingAnchors", false, false)
	if anchors == null:
		return {}
	var sightline: Marker3D = anchors.find_child("FirstEnemySightline", false, false) as Marker3D
	var safe: Marker3D = anchors.find_child("SafeZoneCenter", false, false) as Marker3D
	if sightline == null or safe == null:
		push_warning("OnboardingAnchors incomplete")
		return {}
	return {
		"first_enemy_sightline": sightline,
		"safe_zone_center": safe,
	}


## Retourne le matériau de surface d'un StaticBody3D pour le routing Audio System.
## Source : AC-LVL-44, TR-lvl-042, story-022.
##
## Valeurs reconnues : "concrete", "metal", "glass", "none".
## Propriété absente → "concrete" silencieux.
## Valeur invalide → push_warning + "concrete".
##
## [param body] : StaticBody3D sur lequel lire le tag de matériau.
## [return] : StringName du matériau (&"concrete" | &"metal" | &"glass" | &"none").
func get_surface_material_for(body: StaticBody3D) -> StringName:
	const VALID_MATS: Array[StringName] = [&"concrete", &"metal", &"glass", &"none"]
	var prop: Variant = body.get("surface_material")
	if prop == null:
		return &"concrete"
	var mat: StringName = StringName(str(prop))
	if not VALID_MATS.has(mat):
		push_warning(
			"get_surface_material_for: invalid surface_material '%s' on %s — defaulting to 'concrete'" % [
				mat, body.get_path()
			]
		)
		return &"concrete"
	return mat


## Valide à l'exécution que les CheckpointAnchor_NN ne sont pas enfermés dans
## un StaticBody3D de la géométrie statique (LAYER_ENVIRONMENT).
## Source : TR-lvl-038, ADR-0001 (Jolt physics space state), story-021 AC-LVL-40.
##
## Pré-requis : la scène doit être dans le scene tree AVANT l'appel.
## Guard _current_scene_root null → push_warning + retourne [].
##
## Collision mask : CollisionLayers.build_mask([CollisionLayers.LAYER_ENVIRONMENT])
## conforme ADR-0008 D-3 + rule collision-layer-api-1-indexed.
##
## API non hot-path (debug authoring check) — allocation intentionnelle.
##
## [return] : Array[Dictionary] de violations :
##   { "anchor_name": String, "position": Vector3, "reason": "inside_static_body" }
func validate_checkpoint_anchors() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var root: Node3D = _level._get_scene_root()
	if root == null or not is_instance_valid(root):
		push_warning("validate_checkpoint_anchors called before level_active — returning empty array")
		return results

	var anchor_nodes: Array[Node] = root.find_children(
		"CheckpointAnchor_*", "Marker3D", true, false
	)

	var space: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state

	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.3

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = CollisionLayers.build_mask([CollisionLayers.LAYER_ENVIRONMENT])

	for node: Node in anchor_nodes:
		var anchor: Marker3D = node as Marker3D
		var pos: Vector3 = anchor.global_position
		query.transform = Transform3D(Basis(), pos)
		var collisions: Array[Dictionary] = space.intersect_shape(query, 1)
		if not collisions.is_empty():
			results.append({
				"anchor_name": anchor.name,
				"position": pos,
				"reason": "inside_static_body",
			})

	return results
