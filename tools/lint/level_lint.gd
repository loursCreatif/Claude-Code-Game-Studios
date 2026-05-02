## Lint helper pour la hiérarchie canonique des scènes d'étage.
##
## Source : TR-lvl-006, ADR-0011 D-2, story-010 AC-LVL-11.
##          TR-lvl-016, GDD R-2.6 r2, story-011 AC-LVL-50/AC-LVL-52/AC-LVL-52b.
##          TR-lvl-004, ADR-0011 D-13, story-012 AC-LVL-55 (R-4 r2 budgets, F2).
##          TR-lvl-007, TR-lvl-008, TR-lvl-019, ADR-0008 D-1/D-2/D-3,
##          story-013 AC-LVL-12/AC-LVL-13/AC-LVL-17.
##          TR-lvl-010, TR-lvl-011, TR-lvl-013, TR-lvl-039, story-014 AC-LVL-14/AC-LVL-15.
##          TR-lvl-020, ADR-0011, story-021 AC-LVL-19.
##          TR-018, story-018 AC-LVL-46/AC-LVL-53 (secret triplet + required_ability).
##          TR-019, story-019 AC-LVL-54 (onboarding anchors étage 1).
##          TR-lvl-040/041/042/043, ADR-0003 Shader Baker, story-022 AC-LVL-44.
##
## Usage :
##   var errors := LevelLint.validate_scene_hierarchy(root)
##   if errors.is_empty():
##       print("PASS")
##   else:
##       for err in errors: push_error(err)
##
##   var arch_errors := LevelLint.validate_room_archetypes(root)
##   var budget_errors := LevelLint.validate_room_archetype_invariants(root)
##   var col_errors := LevelLint.validate_collision_layers(root)
##   var wall_errors := LevelLint.validate_wall_thickness(root)
##   var shape_errors := LevelLint.validate_level_shapes(root)
##   var door_errors := LevelLint.validate_door_widths(root)
##   var wall_run_errors := LevelLint.validate_wall_run_surfaces(root)
##   var sb_count_errors := LevelLint.validate_static_body_count_per_room(root)
##
## Appelé par run_level_lint.gd en CI (exit 1 si violations)
## et par les tests GdUnit4 dans tests/unit/lint/.
class_name LevelLint
extends RefCounted

# ---------------------------------------------------------------------------
# Constants — hiérarchie canonique (story-010)
# ---------------------------------------------------------------------------

## Noms des enfants directs obligatoires de type Node3D.
const REQUIRED_NODE3D_CHILDREN: Array[String] = [
	"StaticEnvironment",
	"InteractiveVolumes",
	"SpawnMarkers",
]

## Nom de l'enfant direct obligatoire de type Area3D.
const REQUIRED_AREA3D_EXIT_TRIGGER: String = "EtageExitTrigger"

# ---------------------------------------------------------------------------
# Constants — archetypes (story-011, GDD R-2.6 r2)
# ---------------------------------------------------------------------------

## Valeur sentinel "non défini" pour archetype et room_type_legacy.
const ARCHETYPE_UNSET: int = -1

## Valeurs valides de RoomArchetype.Type (r2).
const ARCHETYPE_TRAVERSAL: int = 0
const ARCHETYPE_COMBAT: int = 1
const ARCHETYPE_SHAFT: int = 2
const ARCHETYPE_SECRET_HUB: int = 3

## Ensemble des valeurs r2 valides (pour membership test O(1)).
const VALID_ARCHETYPES: Array[int] = [
	ARCHETYPE_TRAVERSAL,
	ARCHETYPE_COMBAT,
	ARCHETYPE_SHAFT,
	ARCHETYPE_SECRET_HUB,
]

## Nombre minimum d'archétypes distincts requis par étage (S-1 / AC-LVL-50a).
const MIN_DISTINCT_ARCHETYPES: int = 3

## Archétypes autorisés pour la salle finale (S-4 / AC-LVL-50e).
const VALID_FINAL_ARCHETYPES: Array[int] = [
	ARCHETYPE_SECRET_HUB,
	ARCHETYPE_TRAVERSAL,
]

## preload du helper RoomArchetype pour from_legacy_room_type().
## Nécessaire en CI headless où class_name n'est pas résolu sans SceneTree complet.
const RoomArchetypeScript: GDScript = preload("res://src/gameplay/level/room_archetype.gd")

## preload de CollisionLayers pour les constantes LAYER_* (ADR-0008 D-1/D-3).
## Nécessaire en CI headless où class_name n'est pas résolu sans SceneTree complet.
const CollisionLayersScript: GDScript = preload("res://src/core/collision_layers.gd")

## preload de SecretAbilities pour les constantes d'abilité (story-018 AC-LVL-53).
## Nécessaire en CI headless où class_name n'est pas résolu sans SceneTree complet.
const SecretAbilitiesScript: GDScript = preload("res://src/gameplay/level/secret_abilities.gd")

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Valide la hiérarchie canonique d'une scène d'étage.
##
## Vérifie la présence et le type corrects des 4 enfants directs requis :
## - StaticEnvironment (Node3D)
## - InteractiveVolumes (Node3D)
## - SpawnMarkers (Node3D)
## - EtageExitTrigger (Area3D)
##
## [param root] : la Node3D racine de la scène d'étage instanciée.
## [return] : tableau de messages de violation (vide = PASS).
static func validate_scene_hierarchy(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	# Vérification des 3 enfants Node3D directs obligatoires.
	for required: String in REQUIRED_NODE3D_CHILDREN:
		var n: Node = root.find_child(required, false, false)
		if n == null or not (n is Node3D):
			errors.append("missing required Node3D child: %s" % required)

	# Vérification de l'EtageExitTrigger (Area3D direct).
	var exit: Node = root.find_child(REQUIRED_AREA3D_EXIT_TRIGGER, false, false)
	if exit == null or not (exit is Area3D):
		errors.append("missing EtageExitTrigger as Area3D child of root")

	return errors


# ---------------------------------------------------------------------------
# Public API — archetypes (story-011, AC-LVL-50 / AC-LVL-52 / AC-LVL-52b)
# ---------------------------------------------------------------------------

## Valide les archetypes de chaque Room_NN sous StaticEnvironment.
##
## Vérifie deux catégories de règles :
##
## **Présence (AC-LVL-52 / AC-LVL-52b)** :
##   - Chaque Room_NN doit avoir un `archetype` valide ∈ [0, 3].
##   - Si `archetype` est absent (UNSET = -1) mais `room_type_legacy` ∈ [0, 3],
##     l'auto-conversion est appliquée via RoomArchetype.from_legacy_room_type()
##     avec push_warning (compat r1, 0 violation lint — AC-LVL-52b).
##   - Si les deux sont -1 ou la conversion legacy échoue → violation lint.
##
## **Diversité séquençage (AC-LVL-50 S-1..S-5)** :
##   - S-1 : ≥ 3 archétypes distincts sur l'étage.
##   - S-2 : pas de salles COMBAT consécutives.
##   - S-3 : au moins 1 SHAFT présent.
##   - S-4 : la salle finale ∈ {SECRET_HUB, TRAVERSAL}.
##   - S-5 : au moins 1 SECRET_HUB présent.
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
static func validate_room_archetypes(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	# Localiser StaticEnvironment (enfant direct).
	# Si absent, validate_scene_hierarchy l'a déjà flaggé — pas de doublon.
	var static_env: Node = root.find_child("StaticEnvironment", false, false)
	if static_env == null or not (static_env is Node3D):
		return errors

	# Récupérer les Room_NN — utilise l'ordre tree natif (= ordre déclaré dans .tscn,
	# qui suit le zero-pad 01..N par convention authoring R-5.2).
	# get_children() est déterministe ; sort_custom sur Array[Node] avec comparaison
	# StringName (Node.name) produit un ordre non-lexicographique.
	var rooms: Array[Node] = []
	for child: Node in static_env.get_children():
		if String(child.name).begins_with("Room_"):
			rooms.append(child)

	# Résolution des archetypes (collecte + violations présence).
	var archetypes_in_order: Array[int] = []

	for room: Node in rooms:
		var room_name: String = room.name
		var resolved: int = _resolve_archetype(room, room_name, errors)
		if resolved != ARCHETYPE_UNSET:
			archetypes_in_order.append(resolved)

	# Aucune salle résolue → pas de check diversity (déjà flaggé en présence).
	if archetypes_in_order.is_empty():
		return errors

	# S-1 (AC-LVL-50a) — ≥ MIN_DISTINCT_ARCHETYPES distincts.
	var distinct: Array[int] = []
	for a: int in archetypes_in_order:
		if not distinct.has(a):
			distinct.append(a)
	if distinct.size() < MIN_DISTINCT_ARCHETYPES:
		errors.append(
			"insufficient archetype diversity: %d distinct, required >= 3" % distinct.size()
		)

	# S-3 (AC-LVL-50b) — ≥ 1 SHAFT.
	if not archetypes_in_order.has(ARCHETYPE_SHAFT):
		errors.append("missing required archetype: SHAFT")

	# S-5 (AC-LVL-50c) — ≥ 1 SECRET_HUB.
	if not archetypes_in_order.has(ARCHETYPE_SECRET_HUB):
		errors.append("missing required archetype: SECRET_HUB")

	# S-2 (AC-LVL-50d) — pas de COMBAT consécutifs.
	for i: int in range(archetypes_in_order.size() - 1):
		if archetypes_in_order[i] == ARCHETYPE_COMBAT and archetypes_in_order[i + 1] == ARCHETYPE_COMBAT:
			errors.append(
				"consecutive COMBAT rooms at index %d and %d" % [i, i + 1]
			)

	# S-4 (AC-LVL-50e) — salle finale ∈ {SECRET_HUB, TRAVERSAL}.
	var final_archetype: int = archetypes_in_order.back()
	if not VALID_FINAL_ARCHETYPES.has(final_archetype):
		errors.append(
			"final room archetype must be SECRET_HUB or TRAVERSAL, got %s" % _archetype_name(final_archetype)
		)

	return errors


# ---------------------------------------------------------------------------
# Private helpers — archetypes
# ---------------------------------------------------------------------------

## Résout l'archetype d'un Room_NN, en gérant la compat legacy r1.
##
## Lit `archetype` et `room_type_legacy` via Node.get() avec sentinel -1.
## Ajoute les violations dans [errors] si besoin.
## Retourne la valeur r2 résolue, ou ARCHETYPE_UNSET (-1) si non résoluble.
static func _resolve_archetype(room: Node, room_name: String, errors: Array[String]) -> int:
	# Lecture avec sentinel -1 si la propriété est absente du script.
	var arch: Variant = room.get("archetype")
	var legacy: Variant = room.get("room_type_legacy")

	var arch_int: int = ARCHETYPE_UNSET if arch == null else int(arch)
	var legacy_int: int = ARCHETYPE_UNSET if legacy == null else int(legacy)

	# Cas 1 : archetype valide r2.
	if VALID_ARCHETYPES.has(arch_int):
		return arch_int

	# Cas 2 : archetype UNSET + room_type_legacy valide → compat r1 avec warning.
	if arch_int == ARCHETYPE_UNSET and legacy_int != ARCHETYPE_UNSET:
		var converted: int = RoomArchetypeScript.from_legacy_room_type(legacy_int)
		if converted != ARCHETYPE_UNSET:
			push_warning(
				"%s legacy room_type, migrate to archetype @export" % room_name
			)
			return converted
		# legacy présent mais valeur inconnue.
		errors.append("%s invalid room_type_legacy=%d" % [room_name, legacy_int])
		return ARCHETYPE_UNSET

	# Cas 3 : aucune propriété valide.
	errors.append("%s missing @export archetype" % room_name)
	return ARCHETYPE_UNSET


## Retourne le nom lisible d'un archetype r2 pour les messages d'erreur.
static func _archetype_name(archetype: int) -> String:
	match archetype:
		ARCHETYPE_TRAVERSAL:
			return "TRAVERSAL"
		ARCHETYPE_COMBAT:
			return "COMBAT"
		ARCHETYPE_SHAFT:
			return "SHAFT"
		ARCHETYPE_SECRET_HUB:
			return "SECRET_HUB"
		_:
			return "UNKNOWN(%d)" % archetype


# ---------------------------------------------------------------------------
# Constants — budgets per-archetype (story-012, ADR-0011 D-13, AC-LVL-55)
# ---------------------------------------------------------------------------

## Budgets de nœuds par archetype (R-4 r2).
## Clés : "dc" (MeshInstance3D draw calls), "sb3d" (StaticBody3D),
##         "area3d" (Area3D), "marker3d" (Marker3D).
## Source : ADR-0011 D-13, GDD R-4 r2.
const R4_BUDGETS: Dictionary = {
	ARCHETYPE_TRAVERSAL: {"dc": 22, "sb3d": 18, "area3d": 4, "marker3d": 10},
	ARCHETYPE_COMBAT:    {"dc": 38, "sb3d": 32, "area3d": 10, "marker3d": 30},
	ARCHETYPE_SHAFT:     {"dc": 32, "sb3d": 28, "area3d": 6, "marker3d": 18},
	ARCHETYPE_SECRET_HUB:{"dc": 34, "sb3d": 25, "area3d": 12, "marker3d": 24},
}

## Overhead de draw calls fixes au niveau (UI, manager nodes, etc.).
## Additionné aux DC per-salle pour le calcul de la limite agrégée F2.
## Source : ADR-0011 D-13, GDD F2.
const LEVEL_OVERHEAD: int = 20

## Plafond agrégé de DC incluant overhead (GDD F2 : Σ DC_salle + LEVEL_OVERHEAD ≤ 350).
const AGGREGATE_DC_CAP: int = 350

# ---------------------------------------------------------------------------
# Constants — story-014 (AC-LVL-14 F1, AC-LVL-15 F8, TR-lvl-013)
# ---------------------------------------------------------------------------

## Largeur minimale d'un doorway (F1) : max(size.x, size.z) ≥ 3.6 m.
## Source : GDD Formula 1 — min_opening_width = 2 × KATANA_REACH (1.8 m).
const MIN_DOOR_WIDTH_M: float = 3.6

## Hauteur minimale d'une surface wall-run (F8) : size.y ≥ 4.0 m.
## Source : GDD Formula 8 — jump_apex (1.68) + wall_run_vertical_reach (2.3) = 3.98 → 4.0 m.
const MIN_WALL_RUN_HEIGHT_M: float = 4.0

## Longueur minimale d'une surface wall-run (F8) : max(size.x, size.z) ≥ 3.0 m.
## Source : GDD F8, TR-lvl-039.
const MIN_WALL_RUN_LENGTH_M: float = 3.0

## Déviation d'orientation maximale autorisée pour une surface wall-run (degrés).
## Source : GDD F8 — face verticale, normal UP ≤ 5° écart.
const MAX_WALL_ORIENTATION_DEVIATION_DEG: float = 5.0

## Nombre maximum de StaticBody3D par Room_NN (plafond global, TR-lvl-013).
## Distinct des budgets per-archetype de story-012.
const MAX_STATIC_BODIES_PER_ROOM: int = 25


# ---------------------------------------------------------------------------
# Public API — budget invariants (story-012, AC-LVL-55)
# ---------------------------------------------------------------------------

## Valide les invariants de budget per-archetype (R-4 r2) pour chaque Room_NN.
##
## Pour chaque salle résolue sous StaticEnvironment :
##   - Compte MeshInstance3D (DC), StaticBody3D, Area3D, Marker3D (owned=false pour
##     traverser les instances PackedScene enfants).
##   - Compare aux budgets R4_BUDGETS[archetype] ; signale chaque dépassement.
##   - Pour archetype SHAFT : vérifie ≥1 enfant nommé "VerticalShaftRoom*".
## En fin de validation :
##   - Vérifie que Σ DC_salle + LEVEL_OVERHEAD ≤ AGGREGATE_DC_CAP (GDD F2).
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
static func validate_room_archetype_invariants(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	# Localiser StaticEnvironment (enfant direct).
	var static_env: Node = root.find_child("StaticEnvironment", false, false)
	if static_env == null or not (static_env is Node3D):
		errors.append("validate_room_archetype_invariants: StaticEnvironment absent — impossible de valider les budgets")
		return errors

	# Récupérer les Room_NN sous StaticEnvironment.
	var rooms: Array[Node] = []
	for child: Node in static_env.get_children():
		if String(child.name).begins_with("Room_"):
			rooms.append(child)

	var total_dc: int = 0

	for room: Node in rooms:
		var room_name: String = room.name

		# Résolution silencieuse de l'archetype (sans muter errors).
		var archetype: int = _resolve_archetype_silent(room)
		# Salles UNSET déjà flaggées par validate_room_archetypes — on skip.
		if archetype == ARCHETYPE_UNSET:
			continue

		# Compter les métriques via find_children owned=false.
		var metrics: Dictionary = _count_room_metrics(room)
		var dc: int = metrics["dc"]
		var sb3d: int = metrics["sb3d"]
		var area3d: int = metrics["area3d"]
		var marker3d: int = metrics["marker3d"]

		total_dc += dc

		var budget: Dictionary = R4_BUDGETS[archetype]
		var arch_name: String = _archetype_name(archetype)

		# Check DC.
		if dc > budget["dc"]:
			errors.append(
				"%s %s DC=%d exceeds budget %d (+%d)" % [
					room_name, arch_name, dc, budget["dc"], dc - budget["dc"]
				]
			)
		# Check StaticBody3D.
		if sb3d > budget["sb3d"]:
			errors.append(
				"%s %s StaticBody3D=%d exceeds budget %d (+%d)" % [
					room_name, arch_name, sb3d, budget["sb3d"], sb3d - budget["sb3d"]
				]
			)
		# Check Area3D.
		if area3d > budget["area3d"]:
			errors.append(
				"%s %s Area3D=%d exceeds budget %d (+%d)" % [
					room_name, arch_name, area3d, budget["area3d"], area3d - budget["area3d"]
				]
			)
		# Check Marker3D.
		if marker3d > budget["marker3d"]:
			errors.append(
				"%s %s Marker3D=%d exceeds budget %d (+%d)" % [
					room_name, arch_name, marker3d, budget["marker3d"], marker3d - budget["marker3d"]
				]
			)

		# Check primitive obligatoire pour SHAFT.
		if archetype == ARCHETYPE_SHAFT and not _has_vertical_shaft_room_child(room):
			errors.append(
				"%s SHAFT archetype requires >=1 VerticalShaftRoom primitive instance" % room_name
			)

	# Check agrégat DC (GDD F2).
	if total_dc + LEVEL_OVERHEAD > AGGREGATE_DC_CAP:
		errors.append(
			"aggregate DC %d + LEVEL_OVERHEAD %d = %d exceeds cap %d" % [
				total_dc, LEVEL_OVERHEAD, total_dc + LEVEL_OVERHEAD, AGGREGATE_DC_CAP
			]
		)

	return errors


# ---------------------------------------------------------------------------
# Private helpers — budget invariants (story-012)
# ---------------------------------------------------------------------------

## Résout l'archetype d'une salle sans muter un tableau d'erreurs externe.
## Retourne la valeur r2 résolue, ou ARCHETYPE_UNSET si non résolvable.
static func _resolve_archetype_silent(room: Node) -> int:
	var arch: Variant = room.get("archetype")
	var legacy: Variant = room.get("room_type_legacy")

	var arch_int: int = ARCHETYPE_UNSET if arch == null else int(arch)
	var legacy_int: int = ARCHETYPE_UNSET if legacy == null else int(legacy)

	if VALID_ARCHETYPES.has(arch_int):
		return arch_int

	if arch_int == ARCHETYPE_UNSET and legacy_int != ARCHETYPE_UNSET:
		var converted: int = RoomArchetypeScript.from_legacy_room_type(legacy_int)
		if converted != ARCHETYPE_UNSET:
			return converted

	return ARCHETYPE_UNSET


## Compte les MeshInstance3D, StaticBody3D, Area3D et Marker3D sous une salle.
## Utilise owned=false pour traverser les instances PackedScene enfants (ADR-0011 D-13).
##
## [param room] : Node3D racine de la salle (Room_NN).
## [return] : Dictionary {"dc": int, "sb3d": int, "area3d": int, "marker3d": int}.
static func _count_room_metrics(room: Node3D) -> Dictionary:
	var dc: int = room.find_children("*", "MeshInstance3D", true, false).size()
	var sb3d: int = room.find_children("*", "StaticBody3D", true, false).size()
	var area3d: int = room.find_children("*", "Area3D", true, false).size()
	var marker3d: int = room.find_children("*", "Marker3D", true, false).size()
	return {"dc": dc, "sb3d": sb3d, "area3d": area3d, "marker3d": marker3d}


## Vérifie qu'au moins un enfant direct de la salle est nommé "VerticalShaftRoom*".
## Convention authoring : l'instance PackedScene vertical_shaft_room.tscn doit être
## nommée "VerticalShaftRoom" ou "VerticalShaftRoom_NN" dans le .tscn parent.
##
## [param room] : Node3D racine de la salle (Room_NN).
## [return] : true si au moins un enfant commence par "VerticalShaftRoom".
static func _has_vertical_shaft_room_child(room: Node3D) -> bool:
	for child: Node in room.get_children():
		if String(child.name).begins_with("VerticalShaftRoom"):
			return true
	return false


# ---------------------------------------------------------------------------
# Public API — collision layers discipline (story-013, ADR-0008 D-2, AC-LVL-12/13)
# ---------------------------------------------------------------------------

## Valide la discipline des layers de collision pour StaticEnvironment et InteractiveVolumes.
##
## **AC-LVL-12** — Tous les StaticBody3D sous StaticEnvironment doivent :
##   - Avoir le layer LAYER_ENVIRONMENT (4) actif.
##   - Avoir collision_mask == 0 (géométrie statique ne détecte rien).
##
## **AC-LVL-13** — Tous les Area3D sous InteractiveVolumes doivent :
##   - Avoir le layer LAYER_INTERACTIVE (5) actif.
##   - Avoir monitorable == false (signal-only, pas de détection inverse).
##   - Avoir monitoring == true (détecte les corps entrants).
##   - Avoir collision_mask incluant LAYER_PLAYER (1).
##
## Si StaticEnvironment ou InteractiveVolumes sont absents : violation silencieuse
## (déjà couverte par validate_scene_hierarchy).
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-007, TR-lvl-008, ADR-0008 D-1/D-2/D-3, story-013 AC-LVL-12/AC-LVL-13.
static func validate_collision_layers(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	# --- AC-LVL-12 : StaticBody3D sous StaticEnvironment ---
	var static_env: Node = root.find_child("StaticEnvironment", false, false)
	if static_env != null:
		for sb: StaticBody3D in static_env.find_children("*", "StaticBody3D", true, false):
			if not sb.get_collision_layer_value(CollisionLayersScript.LAYER_ENVIRONMENT):
				errors.append(
					"%s missing layer %d (LAYER_ENVIRONMENT)" % [
						sb.get_path(), CollisionLayersScript.LAYER_ENVIRONMENT
					]
				)
			if sb.collision_mask != 0:
				errors.append(
					"%s collision_mask must be 0, got %d" % [sb.get_path(), sb.collision_mask]
				)

	# --- AC-LVL-13 : Area3D sous InteractiveVolumes ---
	var vol: Node = root.find_child("InteractiveVolumes", false, false)
	if vol != null:
		for a: Area3D in vol.find_children("*", "Area3D", true, false):
			if not a.get_collision_layer_value(CollisionLayersScript.LAYER_INTERACTIVE):
				errors.append(
					"%s missing layer %d (LAYER_INTERACTIVE)" % [
						a.get_path(), CollisionLayersScript.LAYER_INTERACTIVE
					]
				)
			if a.monitorable:
				errors.append("%s monitorable must be false" % a.get_path())
			if not a.monitoring:
				errors.append("%s monitoring must be true" % a.get_path())
			if not a.get_collision_mask_value(CollisionLayersScript.LAYER_PLAYER):
				errors.append(
					"%s collision_mask must include LAYER_PLAYER (%d)" % [
						a.get_path(), CollisionLayersScript.LAYER_PLAYER
					]
				)

	return errors


# ---------------------------------------------------------------------------
# Public API — wall thickness (story-013, TR-lvl-019, AC-LVL-17)
# ---------------------------------------------------------------------------

## Valide l'épaisseur minimale des murs (EC-8 Jolt CCD fiabilité).
##
## Pour chaque StaticBody3D de la scène, inspecte ses CollisionShape3D enfants.
## Pour chaque BoxShape3D trouvé, vérifie que l'axe horizontal le plus mince
## (min de size.x et size.z) est ≥ 0.3 m. L'axe Y n'est pas considéré car
## les murs sont verticaux.
##
## Violation : "%s BoxShape3D thickness %.2fm < 0.3m (EC-8)"
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-019, ADR-0001 (Jolt CCD), story-013 AC-LVL-17.
static func validate_wall_thickness(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	for sb: StaticBody3D in root.find_children("*", "StaticBody3D", true, false):
		for cs: CollisionShape3D in sb.find_children("*", "CollisionShape3D", true, false):
			var shape: Shape3D = cs.shape
			if shape is BoxShape3D:
				var box: BoxShape3D = shape as BoxShape3D
				var thickness: float = minf(box.size.x, box.size.z)
				if thickness < 0.3:
					errors.append(
						"%s BoxShape3D thickness %.2fm < 0.3m (EC-8)" % [
							cs.get_path(), thickness
						]
					)

	return errors


# ---------------------------------------------------------------------------
# Public API — level shapes discipline (story-013, story-008 AC-LVL-WBV)
# ---------------------------------------------------------------------------

## Valide que les WorldBoundsVolume utilisent exclusivement BoxShape3D.
##
## ConcavePolygonShape3D et les trimesh sont interdits sur les volumes de
## WorldBoundsVolume car ils ne supportent pas la détection Area3D correctement
## avec Jolt Physics (ADR-0001, ADR-0008).
##
## Parcourt tous les Area3D nommés "WorldBoundsVolume" (récursif) et vérifie
## que leurs CollisionShape3D enfants ont une BoxShape3D.
##
## Violation : "%s WorldBoundsVolume must use BoxShape3D, got <class>"
##
## Si aucun WorldBoundsVolume trouvé : silencieux (couvert par d'autres lint).
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-019, ADR-0001 (Jolt), story-013 / story-008.
static func validate_level_shapes(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	for wbv: Area3D in root.find_children("WorldBoundsVolume", "Area3D", true, false):
		for cs: CollisionShape3D in wbv.find_children("*", "CollisionShape3D", true, false):
			var shape: Shape3D = cs.shape
			if shape != null and not (shape is BoxShape3D):
				errors.append(
					"%s WorldBoundsVolume must use BoxShape3D, got %s" % [
						cs.get_path(), shape.get_class()
					]
				)

	return errors


# ---------------------------------------------------------------------------
# Public API — door width lint (story-014, AC-LVL-14, F1)
# ---------------------------------------------------------------------------

## Valide la largeur minimale des doorways (F1) dans InteractiveVolumes.
##
## Pour chaque Area3D nommé RoomTrigger_* sous InteractiveVolumes portant
## la meta `is_doorway == true`, inspecte ses CollisionShape3D/BoxShape3D
## enfants et vérifie que max(size.x, size.z) >= MIN_DOOR_WIDTH_M (3.6 m).
##
## L'opt-in via meta `is_doorway=true` évite les faux positifs sur les
## grandes open areas non-corridor.
##
## Violation : "RoomTrigger_NN door width X.XXm < 3.6m (F1)"
## Violation : "RoomTrigger_NN is_doorway=true but no BoxShape3D — width unverifiable (F1)"
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-010, GDD Formula 1, story-014 AC-LVL-14.
static func validate_door_widths(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	var vol: Node = root.find_child("InteractiveVolumes", false, false)
	if vol == null:
		return errors

	for area: Area3D in vol.find_children("*", "Area3D", true, false):
		var area_name: String = area.name
		if not area_name.begins_with("RoomTrigger_"):
			continue
		# Opt-in : méta is_doorway doit être présente et vraie.
		if not area.get_meta("is_doorway", false):
			continue

		# Sans BoxShape3D, la largeur n'est pas vérifiable → faux négatif silencieux.
		var found_box: bool = false
		for cs: CollisionShape3D in area.find_children("*", "CollisionShape3D", true, false):
			var shape: Shape3D = cs.shape
			if not (shape is BoxShape3D):
				continue
			found_box = true
			var box: BoxShape3D = shape as BoxShape3D
			var width: float = maxf(box.size.x, box.size.z)
			if width < MIN_DOOR_WIDTH_M:
				errors.append(
					"%s door width %.2fm < 3.6m (F1)" % [area_name, width]
				)

		if not found_box:
			errors.append(
				"%s is_doorway=true but no BoxShape3D — width unverifiable (F1)" % area_name
			)

	return errors


# ---------------------------------------------------------------------------
# Public API — wall-run surface lint (story-014, AC-LVL-15, F8)
# ---------------------------------------------------------------------------

## Valide les surfaces wall-runnable (F8) dans StaticEnvironment.
##
## Pour chaque StaticBody3D portant la meta `wall_run_enabled == true`,
## inspecte ses CollisionShape3D/BoxShape3D et vérifie 3 invariants :
##   1. Hauteur : size.y >= MIN_WALL_RUN_HEIGHT_M (4.0 m).
##   2. Longueur : max(size.x, size.z) >= MIN_WALL_RUN_LENGTH_M (3.0 m).
##   3. Orientation : global_transform.basis.y.angle_to(Vector3.UP) <= deg_to_rad(5).
##      (global_transform pour capter rotations parentes ; en lint hors-arbre,
##       global_transform == transform local — safe fallback.)
##
## L'opt-in via meta `wall_run_enabled=true` évite les faux positifs sur
## les surfaces statiques non-designées pour le wall-run.
##
## Violations distinctes :
##   "Wall %s height %.2fm < 4.0m (F8)"
##   "Wall %s length %.2fm < 3.0m (F8)"
##   "Wall %s orientation deviation > 5° (F8)"
##   "Wall %s wall_run_enabled=true but no BoxShape3D — geometry unverifiable (F8)"
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-011, GDD Formula 8, story-014 AC-LVL-15.
static func validate_wall_run_surfaces(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	var static_env: Node = root.find_child("StaticEnvironment", false, false)
	if static_env == null:
		return errors

	var max_dev_rad: float = deg_to_rad(MAX_WALL_ORIENTATION_DEVIATION_DEG)

	for sb: StaticBody3D in static_env.find_children("*", "StaticBody3D", true, false):
		if not sb.get_meta("wall_run_enabled", false):
			continue

		var sb_name: String = sb.name

		# Check orientation (une vérification par StaticBody3D, indépendante du shape).
		# global_transform capte les rotations parentes (Room_NN incliné). En
		# contexte lint hors-arbre, global_transform == transform local — safe fallback.
		var deviation: float = sb.global_transform.basis.y.angle_to(Vector3.UP)
		if deviation > max_dev_rad:
			errors.append("Wall %s orientation deviation > 5° (F8)" % sb_name)

		# Sans BoxShape3D, height/length non vérifiables → faux négatif silencieux.
		var found_box: bool = false
		for cs: CollisionShape3D in sb.find_children("*", "CollisionShape3D", true, false):
			var shape: Shape3D = cs.shape
			if not (shape is BoxShape3D):
				continue
			found_box = true
			var box: BoxShape3D = shape as BoxShape3D

			if box.size.y < MIN_WALL_RUN_HEIGHT_M:
				errors.append(
					"Wall %s height %.2fm < 4.0m (F8)" % [sb_name, box.size.y]
				)

			var length: float = maxf(box.size.x, box.size.z)
			if length < MIN_WALL_RUN_LENGTH_M:
				errors.append(
					"Wall %s length %.2fm < 3.0m (F8)" % [sb_name, length]
				)

		if not found_box:
			errors.append(
				"Wall %s wall_run_enabled=true but no BoxShape3D — geometry unverifiable (F8)" % sb_name
			)

	return errors


# ---------------------------------------------------------------------------
# Public API — StaticBody3D count gate per room (story-014, TR-lvl-013)
# ---------------------------------------------------------------------------

## Valide que chaque Room_NN ne dépasse pas MAX_STATIC_BODIES_PER_ROOM (25).
##
## Plafond global distinct des budgets per-archetype de story-012.
## Parcourt les Room_NN directs sous StaticEnvironment (même convention
## d'énumération que validate_room_archetypes).
##
## Violation : "Room_NN StaticBody3D count N > 25 (TR-lvl-013)"
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-013, story-014.
static func validate_static_body_count_per_room(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	var static_env: Node = root.find_child("StaticEnvironment", false, false)
	if static_env == null or not (static_env is Node3D):
		return errors

	for child: Node in static_env.get_children():
		if not child.name.begins_with("Room_"):
			continue
		var room: Node3D = child as Node3D
		if room == null:
			continue
		var count: int = room.find_children("*", "StaticBody3D", true, false).size()
		if count > MAX_STATIC_BODIES_PER_ROOM:
			errors.append(
				"%s StaticBody3D count %d > 25 (TR-lvl-013)" % [room.name, count]
			)

	return errors


# ---------------------------------------------------------------------------
# Public API — secret triplet lint (story-018, AC-LVL-46, AC-LVL-53)
# ---------------------------------------------------------------------------

## Valide la cohérence des triplets secrets (SecretLureMarker_NN ↔ SecretCollectVolume_NN
## ↔ SecretAnchor_NN) et les contraintes économiques du GDD F7.
##
## **AC-LVL-53 — Cohérence triplet** :
##   - Pour chaque SecretLureMarker_NN sous SpawnMarkers : vérifie que
##     SecretCollectVolume_NN Area3D existe sous InteractiveVolumes ET que
##     SecretAnchor_NN Marker3D existe sous SpawnMarkers.
##   - Orphelins côté Volume (SecretCollectVolume_NN sans Lure) flaggués.
##   - Orphelins côté Anchor (SecretAnchor_NN sans Lure) flaggués.
##   - Chaque SecretLureMarker_NN doit avoir required_ability ∈ {none, dash,
##     double_jump, wall_run, wall_run_long} ; valeur absente ou vide = violation.
##
## **AC-LVL-46 — Contraintes de count (GDD F7)** :
##   - Nombre de tuples NN distincts ∈ [3, 5].
##   - Au moins 1 secret avec required_ability ∈ {wall_run, wall_run_long}
##     (contrainte économique pillar 4).
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-018, story-018 AC-LVL-46/AC-LVL-53, GDD level-system.md F7.
static func validate_secret_lures(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	# Localiser les sous-arbres canoniques.
	var spawn_markers: Node = root.find_child("SpawnMarkers", false, false)
	var interactive_volumes: Node = root.find_child("InteractiveVolumes", false, false)

	# Si les sous-arbres manquent, validate_scene_hierarchy l'a déjà flaggé.
	# On sort sans doublon.
	if spawn_markers == null or interactive_volumes == null:
		return errors

	# Collecter les index NN présents dans chaque sous-arbre.
	var lure_indices: Array[String] = _collect_secret_indices(spawn_markers, "SecretLureMarker_")
	var volume_indices: Array[String] = _collect_secret_indices(interactive_volumes, "SecretCollectVolume_")
	var anchor_indices: Array[String] = _collect_secret_indices(spawn_markers, "SecretAnchor_")

	# --- AC-LVL-53 : vérification triplet depuis le côté Lure ---
	# Utilise la const VALID_ABILITIES (zéro alloc vs static func valid_abilities()).
	var valid_abilities: Array[StringName] = SecretAbilitiesScript.VALID_ABILITIES

	# --- Skip si 0 secrets : étage encore en authoring (cohérent validate_checkpoint_pairs). ---
	if lure_indices.is_empty() and volume_indices.is_empty() and anchor_indices.is_empty():
		return errors

	for idx: String in lure_indices:
		# Volume manquant ?
		if not volume_indices.has(idx):
			errors.append(
				"AC-LVL-53: Secret tuple incomplete at index %s — missing SecretCollectVolume" % idx
			)
		# Anchor manquant ?
		if not anchor_indices.has(idx):
			errors.append(
				"AC-LVL-53: Secret tuple incomplete at index %s — missing SecretAnchor" % idx
			)
		# required_ability valide ?
		var lure_node: Node = spawn_markers.find_child("SecretLureMarker_" + idx, true, false)
		if lure_node != null:
			var ability: Variant = lure_node.get("required_ability")
			var ability_sn: StringName = &"" if ability == null else (ability as StringName)
			if not valid_abilities.has(ability_sn):
				errors.append(
					"AC-LVL-53: SecretLureMarker_%s required_ability not in {none, dash, double_jump, wall_run, wall_run_long}" % idx
				)

	# --- AC-LVL-53 : orphelins côté Volume ---
	for idx: String in volume_indices:
		if not lure_indices.has(idx):
			errors.append(
				"AC-LVL-53: SecretCollectVolume_%s orphan — missing SecretLureMarker_%s" % [idx, idx]
			)

	# --- AC-LVL-53 : orphelins côté Anchor ---
	for idx: String in anchor_indices:
		if not lure_indices.has(idx):
			errors.append(
				"AC-LVL-53: SecretAnchor_%s orphan — missing SecretLureMarker_%s" % [idx, idx]
			)

	# Nombre de tuples distincts = taille des index Lure (référence canonique).
	var secret_count: int = lure_indices.size()

	# --- AC-LVL-46 : count ∈ [3, 5] ---
	if secret_count < 3:
		errors.append("AC-LVL-46: secret count %d < 3" % secret_count)
	elif secret_count > 5:
		errors.append("AC-LVL-46: secret count %d > 5" % secret_count)

	# --- AC-LVL-46 : contrainte économique ≥ 1 wall_run ou wall_run_long ---
	# Évaluée uniquement si le count est valide (≥ 3) pour éviter faux positif
	# quand l'étage a des secrets mais en nombre insuffisant.
	if secret_count >= 3:
		var has_wall_run: bool = false
		for idx: String in lure_indices:
			var lure_node: Node = spawn_markers.find_child("SecretLureMarker_" + idx, true, false)
			if lure_node == null:
				continue
			var ability: Variant = lure_node.get("required_ability")
			var ability_sn: StringName = &"" if ability == null else (ability as StringName)
			if SecretAbilitiesScript.is_economic_gating(ability_sn):
				has_wall_run = true
				break
		if not has_wall_run:
			errors.append(
				"AC-LVL-46: economic constraint: ≥ 1 secret must require wall_run or wall_run_long"
			)

	return errors


# ---------------------------------------------------------------------------
# Constants — story-020 (AC-LVL-18/20/46/47/48/49/51, F3/F5/F6/F7)
# ---------------------------------------------------------------------------

## Nombre minimum de RoomTrigger_* Area3D par étage (AC-LVL-20).
const MIN_ROOM_COUNT: int = 8

## Nombre maximum de RoomTrigger_* Area3D par étage (AC-LVL-20).
const MAX_ROOM_COUNT: int = 10

## Nombre minimum de SecretCollectVolume_* Area3D par étage (AC-LVL-46, F7).
const MIN_SECRET_COUNT: int = 3

## Nombre maximum de SecretCollectVolume_* Area3D par étage (AC-LVL-46, F7).
const MAX_SECRET_COUNT: int = 5

## Hauteur minimale d'un étage (|PlayerStart.y - EtageExitTrigger.y|) en mètres (AC-LVL-48, F5).
const MIN_ETAGE_HEIGHT_M: float = 15.0

## Hauteur maximale d'un étage (|PlayerStart.y - EtageExitTrigger.y|) en mètres (AC-LVL-48, F5).
const MAX_ETAGE_HEIGHT_M: float = 60.0

## Marge minimale (tous axes) du WorldBoundsVolume BoxShape3D autour de l'union des StaticBody3D (AC-LVL-49, F6).
const WORLD_BOUNDS_MARGIN_M: float = 3.0

## Espacement minimal autorisé entre checkpoints floor(N/K) (AC-LVL-51, F3).
const MIN_CHECKPOINT_SPACING: int = 2

## Espacement maximal autorisé entre checkpoints floor(N/K) (AC-LVL-51, F3).
const MAX_CHECKPOINT_SPACING: int = 3


# ---------------------------------------------------------------------------
# Public API — formula lints aggregate (story-020, ADR-0011 D-7)
# ---------------------------------------------------------------------------

## Agrège 7 checks gate authoring-time pour les formules F3/F5/F6/F7 et les
## invariants de count PlayerStart / Room / Secret / Checkpoint.
##
## **AC-LVL-18** — PlayerStart unique : find_children("PlayerStart", "Marker3D", true)
##   doit retourner length == 1. Violation : "PlayerStart count %d != 1".
##
## **AC-LVL-20** — Room count [8, 10] : count RoomTrigger_* Area3D.
##   Violation : "Room count %d outside [8, 10]".
##
## **AC-LVL-46** — Secret count [3, 5] : count SecretCollectVolume_* Area3D.
##   Violation : "Secret count %d outside [3, 5] (F7)".
##
## **AC-LVL-47 + AC-LVL-51** — Checkpoint count & spacing F3.
##   Violations : "checkpoint spacing: K=0 fail",
##                "checkpoint spacing: K=1 on N>=4 fail (spacing >= 4 violates Pillar 3)",
##                "checkpoint spacing: K==N fail (spacing=1 violates Pillar 1 FLOW)",
##                "checkpoint spacing=%d (N_rooms=%d, K=%d) outside [2, 3] — see Formula 3".
##
## **AC-LVL-48** — Etage height F5 : |PlayerStart.y - EtageExitTrigger.y| ∈ [15, 60] m.
##   Violation : "etage height %.2fm outside [15, 60]m (F5)".
##   Si PlayerStart ou EtageExitTrigger absent : skip silencieux.
##
## **AC-LVL-49** — WorldBoundsVolume F6 : BoxShape3D doit contenir l'union AABB
##   de tous les StaticBody3D BoxShape3D + 3 m de marge sur tous axes.
##   Violation : "WorldBoundsVolume does not enclose union + 3m margin (F6)".
##   Si WorldBoundsVolume absent : skip silencieux.
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-009, TR-lvl-012, TR-lvl-014, TR-lvl-015, GDD F3/F5/F6/F7,
##          ADR-0011 D-7, story-020 AC-LVL-18/AC-LVL-20/AC-LVL-46/AC-LVL-47/
##          AC-LVL-48/AC-LVL-49/AC-LVL-51.
static func validate_level_formulas(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	# --- AC-LVL-18 : PlayerStart unique ---
	var starts: Array[Node] = root.find_children("PlayerStart", "Marker3D", true)
	if starts.size() != 1:
		errors.append("PlayerStart count %d != 1" % starts.size())

	# --- AC-LVL-20 : Room count [8, 10] ---
	var rooms: Array[Node] = root.find_children("RoomTrigger_*", "Area3D", true)
	var n: int = rooms.size()
	if n < MIN_ROOM_COUNT or n > MAX_ROOM_COUNT:
		errors.append("Room count %d outside [8, 10]" % n)

	# --- AC-LVL-47 + AC-LVL-51 : Checkpoint count & spacing F3 ---
	var checkpoints: Array[Node] = root.find_children("CheckpointVolume_*", "Area3D", true)
	var k: int = checkpoints.size()
	if k == 0:
		errors.append("checkpoint spacing: K=0 fail")
	elif k == 1 and n >= 4:
		errors.append("checkpoint spacing: K=1 on N>=4 fail (spacing >= 4 violates Pillar 3)")
	elif k == n:
		errors.append("checkpoint spacing: K==N fail (spacing=1 violates Pillar 1 FLOW)")
	else:
		var spacing: int = n / k  # GDScript 4.x : int / int = division entière (floor pour positifs)
		if spacing < MIN_CHECKPOINT_SPACING or spacing > MAX_CHECKPOINT_SPACING:
			errors.append(
				"checkpoint spacing=%d (N_rooms=%d, K=%d) outside [2, 3] — see Formula 3" % [spacing, n, k]
			)

	# --- AC-LVL-46 : Secret count [3, 5] ---
	var secrets: Array[Node] = root.find_children("SecretCollectVolume_*", "Area3D", true)
	var s: int = secrets.size()
	if s < MIN_SECRET_COUNT or s > MAX_SECRET_COUNT:
		errors.append("Secret count %d outside [3, 5] (F7)" % s)

	# --- AC-LVL-48 : Etage height F5 ---
	# Skip silencieux si PlayerStart ou EtageExitTrigger absent (autres lints couvrent déjà).
	var start_node: Node = root.find_child("PlayerStart", true, false)
	var exit_node: Node = root.find_child("EtageExitTrigger", true, false)
	var start_marker: Marker3D = start_node as Marker3D if start_node != null else null
	var exit_area: Area3D = exit_node as Area3D if exit_node != null else null
	if start_marker != null and exit_area != null:
		var h: float = abs(start_marker.global_position.y - exit_area.global_position.y)
		if h < MIN_ETAGE_HEIGHT_M or h > MAX_ETAGE_HEIGHT_M:
			errors.append("etage height %.2fm outside [15, 60]m (F5)" % h)

	# --- AC-LVL-49 : WorldBoundsVolume F6 ---
	# Skip silencieux si WorldBoundsVolume absent.
	var bounds_node: Node = root.find_child("WorldBoundsVolume", true, false)
	var bounds_area: Area3D = bounds_node as Area3D if bounds_node != null else null
	if bounds_area != null and bounds_area.has_node("CollisionShape3D"):
		var cs_node: Node = bounds_area.get_node("CollisionShape3D")
		var cs: CollisionShape3D = cs_node as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			var box: BoxShape3D = cs.shape as BoxShape3D
			var bounds_aabb: AABB = AABB(
				bounds_area.global_position - box.size / 2.0,
				box.size
			)
			var union: AABB = AABB()
			var first: bool = true
			for sb: StaticBody3D in root.find_children("*", "StaticBody3D", true):
				for sc_node: Node in sb.find_children("*", "CollisionShape3D", false):
					var sc: CollisionShape3D = sc_node as CollisionShape3D
					if sc == null:
						continue
					if sc.shape is BoxShape3D:
						var sbox: BoxShape3D = sc.shape as BoxShape3D
						var aabb: AABB = AABB(
							sc.global_position - sbox.size / 2.0,
							sbox.size
						)
						if first:
							union = aabb
							first = false
						else:
							union = union.merge(aabb)
			if not first:
				var required: AABB = union.grow(WORLD_BOUNDS_MARGIN_M)
				if not bounds_aabb.encloses(required):
					errors.append(
						"WorldBoundsVolume does not enclose union + 3m margin (F6)"
					)

	return errors


## Collecte les suffixes NN des nœuds dont le nom commence par [prefix] sous [parent].
## Scan les enfants directs uniquement (convention authoring : Lures/Volumes/Anchors
## sont des enfants directs de leurs sous-arbres respectifs).
## [param parent] : Node parent à scanner.
## [param prefix] : préfixe de nom (ex. "SecretLureMarker_").
## [return] : Array[String] des suffixes NN (ex. ["01", "02", "03"]).
static func _collect_secret_indices(parent: Node, prefix: String) -> Array[String]:
	var indices: Array[String] = []
	for child: Node in parent.get_children():
		var child_name: String = child.name
		if child_name.begins_with(prefix):
			var idx: String = child_name.trim_prefix(prefix)
			if not indices.has(idx):
				indices.append(idx)
	return indices


# ---------------------------------------------------------------------------
# Public API — onboarding anchors lint (story-019, AC-LVL-54)
# ---------------------------------------------------------------------------

## Valide les anchors d'onboarding Combat (étage 1 uniquement).
##
## **AC-LVL-54** — OnboardingAnchors (stage 1 r2 fix #5) :
##   (a) Pour étage_id == 1 :
##       - Sous-arbre OnboardingAnchors (enfant direct du root) obligatoire.
##       - FirstEnemySightline Marker3D doit être présent sous OnboardingAnchors.
##       - SafeZoneCenter Marker3D doit être présent sous OnboardingAnchors.
##       - Distance PlayerStart → FirstEnemySightline ≤ 15 m.
##   (b) SafeZoneCenter ≥ 6 m de tout EnemySlot_* Marker3D de l'étage.
##       SafeZoneCenter ≥ 4 m de tout HazardSlot_* Marker3D de l'étage.
##   (c) Pour étage_id ≠ 1 : absence de OnboardingAnchors non-fatale (retourne []).
##
## Note : le check raycast ligne-de-vue (obstruction FirstEnemySightline) requiert
## PhysicsDirectSpaceState3D — délégué au test d'intégration
## tests/integration/level/level_onboarding_raycast_test.gd.
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [param etage_id] : identifiant de l'étage (1 = tutorial obligatoire).
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-019, story-019 AC-LVL-54, GDD level-system.md.
static func validate_onboarding_anchors(root: Node3D, etage_id: int) -> Array[String]:
	var errors: Array[String] = []

	var anchors: Node = root.find_child("OnboardingAnchors", false, false)
	if anchors == null:
		if etage_id == 1:
			errors.append("etage 1 requires OnboardingAnchors sub-tree")
		return errors  # étage != 1 → non-fatal

	var sightline: Marker3D = anchors.find_child("FirstEnemySightline", false, false) as Marker3D
	var safe: Marker3D = anchors.find_child("SafeZoneCenter", false, false) as Marker3D

	if sightline == null:
		errors.append("OnboardingAnchors missing FirstEnemySightline")
	if safe == null:
		errors.append("OnboardingAnchors missing SafeZoneCenter")

	# --- AC-LVL-54(a) : distance PlayerStart → FirstEnemySightline ≤ 15 m ---
	if sightline != null:
		var player_start: Marker3D = root.find_child("PlayerStart", true, false) as Marker3D
		if player_start != null:
			var dist: float = player_start.global_position.distance_to(sightline.global_position)
			if dist > 15.0:
				errors.append("FirstEnemySightline distance %.2fm > 15m" % dist)

	# --- AC-LVL-54(b) : SafeZoneCenter distances ---
	if safe != null:
		var enemy_slots: Array[Node] = root.find_children("EnemySlot_*", "Marker3D", true)
		for e: Node in enemy_slots:
			var em: Marker3D = e as Marker3D
			if em == null:
				continue
			var d: float = safe.global_position.distance_to(em.global_position)
			if d < 6.0:
				errors.append(
					"SafeZoneCenter distance %.2fm < 6m from %s" % [d, em.name]
				)
		var hazards: Array[Node] = root.find_children("HazardSlot_*", "Marker3D", true)
		for h: Node in hazards:
			var hm: Marker3D = h as Marker3D
			if hm == null:
				continue
			var d: float = safe.global_position.distance_to(hm.global_position)
			if d < 4.0:
				errors.append(
					"SafeZoneCenter distance %.2fm < 4m from %s" % [d, hm.name]
				)

	return errors


# ---------------------------------------------------------------------------
# Public API — visual authoring invariants (story-022, TR-lvl-040/041, AC-LVL-44)
# ---------------------------------------------------------------------------

## Chemin de l'atlas Chrome Zen — textures à ce chemin exemptées du plafond 1024².
## (L'atlas lui-même peut être exactement 1024×1024.)
const CHROME_ZEN_ATLAS_PATH: String = "res://assets/textures/chrome_zen_atlas.png"

## Chemin du shader Chrome Zen flat — référence attendue sur les ShaderMaterial.
const CHROME_ZEN_SHADER_PATH: String = "res://assets/shaders/chrome_zen_flat.gdshader"

## Chemin du ShaderMaterial partagé Chrome Zen flat.
const CHROME_ZEN_MATERIAL_PATH: String = "res://assets/materials/chrome_zen_flat.tres"

## Valide les invariants visuels Chrome Zen : primitives only + shader obligatoire
## + contraintes de taille de texture atlas.
##
## **TR-lvl-040** — Primitives only :
##   - Pour chaque MeshInstance3D sous [root], vérifie `mesh is PrimitiveMesh`.
##   - Si `mesh is ArrayMesh` → violation "imported mesh found at <path>".
##     (Best-effort : tout ArrayMesh est flaggé ; ArrayMesh procédural légitime
##     doit être refactorisé en PrimitiveMesh au MVP.)
##
## **TR-lvl-040 shader** — Material override Chrome Zen :
##   - Si material_override est un ShaderMaterial référençant chrome_zen_flat.gdshader
##     OU le .tres partagé → PASS.
##   - Si StandardMaterial3D, ORMMaterial3D, ou ShaderMaterial pointant vers un autre
##     shader → violation "material at <path> must reference chrome_zen_flat.gdshader".
##   - material_override == null → PASS (inherit parent material).
##
## **TR-lvl-041** — Contraintes de taille texture :
##   - Paramètre shader `atlas` (Texture2D) : max(w,h) > 1024 → violation "1024".
##   - Paramètre shader `atlas` dans la tranche (512, 1024] → violation "512" (individuelle).
##   - L'atlas maître `chrome_zen_atlas.png` peut être exactement 1024 — exempté du
##     check sub-texture.
##
## [param root] : Node3D racine de la scène d'étage instanciée.
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-040, TR-lvl-041, ADR-0003 Shader Baker, story-022 AC-LVL-44.
static func validate_visual_authoring(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	for node: Node in meshes:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi == null:
			continue

		var node_path: String = str(mi.get_path())

		# --- TR-lvl-040 : primitive only ---
		var mesh: Mesh = mi.mesh
		if mesh != null and mesh is ArrayMesh:
			errors.append(
				"imported mesh found at %s: MVP Chrome Zen primitives only (TR-lvl-040)" % node_path
			)

		# --- TR-lvl-040 shader : material_override check ---
		var mat: Material = mi.material_override
		if mat != null:
			var is_valid_chrome_zen: bool = false
			if mat is ShaderMaterial:
				var sm: ShaderMaterial = mat as ShaderMaterial
				# Accepté si le resource_path du ShaderMaterial correspond au .tres partagé
				# OU si le shader attaché correspond au .gdshader canonique.
				if sm.resource_path == CHROME_ZEN_MATERIAL_PATH:
					is_valid_chrome_zen = true
				elif sm.shader != null and sm.shader.resource_path == CHROME_ZEN_SHADER_PATH:
					is_valid_chrome_zen = true
			if not is_valid_chrome_zen:
				errors.append(
					"material at %s must reference chrome_zen_flat.gdshader (TR-lvl-040)" % node_path
				)
		# mat == null → autorisé (inherit parent material) — pas de violation

		# --- TR-lvl-041 : texture size checks (uniquement sur ShaderMaterial avec shader Chrome Zen) ---
		if mat is ShaderMaterial:
			var sm: ShaderMaterial = mat as ShaderMaterial
			var shader_valid: bool = (
				sm.resource_path == CHROME_ZEN_MATERIAL_PATH
				or (sm.shader != null and sm.shader.resource_path == CHROME_ZEN_SHADER_PATH)
			)
			if shader_valid:
				errors.append_array(_check_texture_sizes(sm, node_path))

	return errors


## Vérifie les tailles des Texture2D dans les uniforms d'un ShaderMaterial.
## Retourne les violations de taille (atlas cap 1024², sub-texture cap 512²).
## L'atlas `chrome_zen_atlas.png` est exempté du check sub-texture (peut être 1024).
##
## [param sm] : ShaderMaterial à inspecter.
## [param node_path] : chemin du node pour les messages d'erreur.
## [return] : Array[String] de violations (vide = PASS).
static func _check_texture_sizes(sm: ShaderMaterial, node_path: String) -> Array[String]:
	var errors: Array[String] = []
	if sm.shader == null:
		return errors

	var param_list: Array[Dictionary] = sm.shader.get_shader_uniform_list()
	for param: Dictionary in param_list:
		var tex: Variant = sm.get_shader_parameter(param["name"])
		if not (tex is Texture2D):
			continue
		var texture: Texture2D = tex as Texture2D
		var w: int = texture.get_width()
		var h: int = texture.get_height()
		var max_dim: int = maxi(w, h)

		# Exempter l'atlas lui-même du check sub-texture (peut être 1024×1024 exact).
		var is_atlas: bool = texture.resource_path == CHROME_ZEN_ATLAS_PATH

		# Atlas cap : toute texture (y compris atlas) ≤ 1024.
		if max_dim > 1024:
			errors.append(
				"%s texture size %d > 1024 atlas cap (TR-lvl-041)" % [node_path, max_dim]
			)
		# Sub-texture cap : textures non-atlas ≤ 512.
		elif not is_atlas and max_dim > 512:
			errors.append(
				"%s individual texture %d > 512 cap (TR-lvl-041)" % [node_path, max_dim]
			)

	return errors


# ---------------------------------------------------------------------------
# Public API — tuning knobs YAML presence check (story-022, TR-lvl-043, AC-LVL-44)
# ---------------------------------------------------------------------------

## Valide la présence du fichier design/registry/level.yaml et la présence minimale
## de toutes les clés de tuning knobs requises (lecture substring — pas de parser YAML complet).
##
## **AC-LVL-44** — level.yaml présent et contient les clés MVP obligatoires :
##   KATANA_REACH, CHECKPOINT_SPACING, ETAGE_HEIGHT_MIN, ETAGE_HEIGHT_MAX,
##   ROOM_COUNT_MIN, ROOM_COUNT_MAX, SECRET_COUNT_MIN, SECRET_COUNT_MAX,
##   DRAW_CALL_BUDGET, VRAM_BUDGET_MB, RAM_BUDGET_MB, LOAD_TIME_BUDGET_MS,
##   LAYER_PLAYER, LAYER_ENVIRONMENT, MIN_HEIGHT_M.
##
## Pas de paramètre root — check fichier uniquement (indépendant de la scène).
##
## [return] : Array[String] de violations (vide = PASS).
## Source : TR-lvl-043, story-022 AC-LVL-44.
static func validate_tuning_knobs_present() -> Array[String]:
	var errors: Array[String] = []

	const YAML_PATH: String = "res://design/registry/level.yaml"
	const REQUIRED_KEYS: Array[String] = [
		"KATANA_REACH",
		"CHECKPOINT_SPACING",
		"ETAGE_HEIGHT_MIN",
		"ETAGE_HEIGHT_MAX",
		"ROOM_COUNT_MIN",
		"ROOM_COUNT_MAX",
		"SECRET_COUNT_MIN",
		"SECRET_COUNT_MAX",
		"DRAW_CALL_BUDGET",
		"VRAM_BUDGET_MB",
		"RAM_BUDGET_MB",
		"LOAD_TIME_BUDGET_MS",
		"LAYER_PLAYER",
		"LAYER_ENVIRONMENT",
		"MIN_HEIGHT_M",
	]

	var file: FileAccess = FileAccess.open(YAML_PATH, FileAccess.READ)
	if file == null:
		errors.append("design/registry/level.yaml missing")
		return errors

	var content: String = file.get_as_text()
	file.close()

	for key: String in REQUIRED_KEYS:
		if not (key in content):
			errors.append("design/registry/level.yaml missing key '%s'" % key)

	return errors


# ---------------------------------------------------------------------------
# Public API — enemy slot triplet (story-006 enemy-system, AC-ENM-23/24/25)
# ---------------------------------------------------------------------------

## Tolérance pour scale uniforme (autorise IDENTITY + tolérance flottante).
const ENEMY_SLOT_SCALE_TOLERANCE: float = 0.001

## Distance minimale entre 2 EnemySlot_* (Enemy GDD F-ENM-1 + EC-ENM-8).
## Calc : 2 × R_ENEMY_MIN (0.35) + buffer ≈ 1.0 m.
const ENEMY_SLOT_MIN_DISTANCE_M: float = 1.0


## Itère sous root et collecte tous les Marker3D EnemySlot_*. Helper privé
## pour les 3 validators enemy slot. find_children DFS — même contrat que
## EnemySpawner runtime (story-003).
static func _collect_enemy_slots(root: Node3D) -> Array[Marker3D]:
	var slots: Array[Marker3D] = []
	for n: Node in root.find_children("EnemySlot_*", "Marker3D", true, false):
		var marker: Marker3D = n as Marker3D
		if marker != null:
			slots.append(marker)
	return slots


## Valide que chaque EnemySlot_* Marker3D a un scale uniforme = Vector3.ONE.
##
## **AC-ENM-23 / EC-ENM-6** : un Marker3D scaled non-uniformément produit un
## cône laser visuellement déformé. Le runtime force orthonormalized() sur
## %FacingPivot.global_basis (story-002), mais ce lint authoring-time catch les
## EnemySlot avec scale non-uniform avant que le bug arrive en playtest.
##
## Tolérance : Vector3.ONE ± 0.001 par axe (autorise précision flottante).
## Violation : "EnemySlot_NN scale not uniform: <Vector3>"
##
## Source : Enemy GDD r2 EC-ENM-6, AC-ENM-23, story-006.
static func validate_enemy_slot_marker3d(root: Node3D) -> Array[String]:
	var errors: Array[String] = []

	for slot: Marker3D in _collect_enemy_slots(root):
		var s: Vector3 = slot.transform.basis.get_scale()
		var dx: float = absf(s.x - 1.0)
		var dy: float = absf(s.y - 1.0)
		var dz: float = absf(s.z - 1.0)
		if dx > ENEMY_SLOT_SCALE_TOLERANCE or dy > ENEMY_SLOT_SCALE_TOLERANCE or dz > ENEMY_SLOT_SCALE_TOLERANCE:
			errors.append(
				"%s EnemySlot scale not uniform: %s (EC-ENM-6 / AC-ENM-23)" % [slot.name, str(s)]
			)

	return errors


## Valide que toute paire d'EnemySlot_* est séparée d'au moins 1.0 m.
##
## **AC-ENM-24 / EC-ENM-8** : 2 grunts trop proches voient leurs capsules
## (R_ENEMY_MIN = 0.35 m chacune) collisionner → Jolt push automatique → grunts
## qui « glissent » visuellement. Distance minimale = 2 × 0.35 + buffer = 1.0 m.
##
## Comparaison O(N²) — acceptable car typiquement < 30 EnemySlot par étage.
## Violation : "EnemySlot_AA & EnemySlot_BB distance N.NNm < 1.0m"
##
## Source : Enemy GDD r2 EC-ENM-8, AC-ENM-24, story-006.
static func validate_enemy_slot_min_distance(root: Node3D) -> Array[String]:
	var errors: Array[String] = []
	var slots: Array[Marker3D] = _collect_enemy_slots(root)

	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			var a: Marker3D = slots[i]
			var b: Marker3D = slots[j]
			var distance: float = a.global_position.distance_to(b.global_position)
			if distance < ENEMY_SLOT_MIN_DISTANCE_M:
				errors.append(
					"%s & %s distance %.3fm < 1.0m (EC-ENM-8 / AC-ENM-24)" % [a.name, b.name, distance]
				)

	return errors


## Valide qu'aucun EnemySlot_* n'est placé À L'INTÉRIEUR d'un StaticBody3D
## sous StaticEnvironment (mur / plafond / collidable).
##
## **AC-ENM-25 / EC-ENM-7** : un grunt instancié dans un mur est invisible et
## non-tuable — pas de crash mais asset gaspillé. Le GDD décrit un raycast
## vertical ; le lint static fait un check AABB équivalent (no physics dependency,
## hermetic-compatible). Si le slot tombe DANS la AABB d'un BoxShape3D, FAIL.
##
## Limite : couvre uniquement BoxShape3D (cas dominant level MVP). Les autres
## shapes (Convex, Mesh) ne sont pas utilisées sur l'étage MVP.
## Violation : "EnemySlot_NN placed inside StaticBody3D <name>"
##
## Source : Enemy GDD r2 EC-ENM-7, AC-ENM-25, story-006.
static func validate_enemy_slot_clearance(root: Node3D) -> Array[String]:
	var errors: Array[String] = []
	var slots: Array[Marker3D] = _collect_enemy_slots(root)
	if slots.is_empty():
		return errors

	var static_env: Node = root.find_child("StaticEnvironment", false, false)
	if static_env == null:
		return errors

	for slot: Marker3D in slots:
		var slot_pos: Vector3 = slot.global_position
		var flagged: bool = false
		for sb: StaticBody3D in static_env.find_children("*", "StaticBody3D", true, false):
			if flagged:
				break
			for cs: CollisionShape3D in sb.find_children("*", "CollisionShape3D", true, false):
				var shape: Shape3D = cs.shape
				if not (shape is BoxShape3D):
					continue
				var box: BoxShape3D = shape as BoxShape3D
				var local_pos: Vector3 = cs.global_transform.affine_inverse() * slot_pos
				var half: Vector3 = box.size * 0.5
				if (
					absf(local_pos.x) <= half.x
					and absf(local_pos.y) <= half.y
					and absf(local_pos.z) <= half.z
				):
					errors.append(
						"%s placed inside StaticBody3D %s (EC-ENM-7 / AC-ENM-25)" % [slot.name, sb.name]
					)
					flagged = true
					break

	return errors
