# Benchmark runner — EC-8 Jolt CCD gameplay scenarios gate (story-023 AC-LVL-43).
#
# Valide que 4 scénarios gameplay (dash seul, dash mur épais, wallrun+jump combo,
# dash+wallrun worst-case) ne provoquent pas de tunneling (clip-through) via Jolt
# CCD à des vitesses worst-case issues du Movement GDD.
#
# fixture etage_ccd_gameplay.tscn intentionnellement omise — geometry programmatique
# pour déterminisme + zero scene I/O (pattern établi par level_ccd_sweep_runner.gd).
#
# --- PATTERN HEADLESS ---
# Ce runner s'exécute via :
#   godot --headless --path . tests/performance/level_ccd_gameplay_runner.tscn
# Il extends Node3D (pas SceneTree) pour disposer d'un SceneTree actif et
# donc d'une boucle physique Jolt fonctionnelle (await get_tree().physics_frame).
# Pattern CLAUDE.md Godot CLI Safety rule #1 exception documentée : extends Node3D
# requiert SceneTree actif pour move_and_slide(). CI ubuntu-only (même pattern
# que perf-level-ccd / perf-level-draw-calls — incident CLAUDE.md 2026-04-27).
#
# --- DEVIATIONS PAR RAPPORT AU SPEC MOVEMENT ---
# DEV-1 : PlayerController state machine n'existe pas au MVP. On instancie Player.tscn
#   (real Jolt CharacterBody3D root + production scene tree) MAIS on ajoute
#   CollisionShape3D programmatiquement (Movement story-001 ne l'a pas encore créée)
#   ET on drive `velocity` directement (pas via state machine). C'est l'approximation
#   la plus proche de "réel" disponible au MVP.
# DEV-2 : wall_jump impulse value = 12 m/s horizontal est une approximation issue
#   de la lecture Movement GDD constants — pas de calibration finale (Movement system
#   pas implémenté).
# DEV-3 : Combo "wall_run + wall_jump" simulé comme vélocité linéaire cumulative
#   (-18 m/s sur Z), pas comme transition state-machine. La gate teste la robustesse
#   Jolt CCD à la magnitude de vélocité, pas la fidélité du state machine.
#
# Source : ADR-0001 EC-8 CLAIM-UNVERIFIED, TR-lvl-039, story-023 AC-LVL-43.
# ADR-0001 D-1 : Jolt 4.6 default, physics 60 Hz.
# Lancement CI : godot --headless --path . tests/performance/level_ccd_gameplay_runner.tscn

extends Node3D

# ---------------------------------------------------------------------------
# Constantes de configuration
# ---------------------------------------------------------------------------

## Scène Player de production — CharacterBody3D root + CameraArm + CombatSystem.
## CollisionShape3D absente dans Player.tscn (Movement story-001 à venir) —
## ajoutée programmatiquement dans _setup_arenas() (DEV-1).
const PLAYER_SCENE: PackedScene = preload("res://src/gameplay/player/Player.tscn")

## Scénarios gameplay (4 configs) — chacun correspond à une combinaison
## de mouvements worst-case issue du Movement GDD.
## Format : {name: String, thickness_m: float, velocity_z: float}
## velocity_z : magnitude sur l'axe Z (négatif = vers le mur).
const SCENARIOS: Array[Dictionary] = [
	{
		"name": "dash_into_wall_03m",
		"thickness_m": 0.3,
		# DASH_SPEED = 21.0 m/s — spec Movement GDD.
		"velocity_z": -21.0,
	},
	{
		"name": "dash_into_wall_05m",
		"thickness_m": 0.5,
		# DASH_SPEED = 21.0 m/s — même vitesse, mur plus épais.
		"velocity_z": -21.0,
	},
	{
		"name": "wallrun_into_corner_03m",
		"thickness_m": 0.3,
		# Combo wall_run (6.0 m/s) + wall_jump horizontal (12.0 m/s) = 18.0 m/s.
		# DEV-2 : wall_jump = 12 m/s approximation Movement GDD (pas de calibration finale).
		# DEV-3 : cumulé linéairement, pas via state machine.
		"velocity_z": -18.0,
	},
	{
		"name": "dash_wallrun_combo_03m",
		"thickness_m": 0.3,
		# Combo dash (21.0 m/s) + wall_run (6.0 m/s) = 27.0 m/s worst-case.
		# DEV-3 : magnitude cumulative linéaire (pas de transition state machine).
		"velocity_z": -27.0,
	},
]

## Nombre de passes par scénario.
const PASSES_PER_SCENARIO: int = 50

## Nombre de ticks physiques par passe (≈ 0.5 s @ 60 Hz).
const PHYSICS_TICKS_PER_PASS: int = 30

## Espacement entre arenas sur l'axe X (évite les interférences Jolt cross-talk).
const ARENA_SPACING_X: float = 25.0

## Position de départ du joueur avant le mur (mur centré à z=0, joueur part de z=+5).
const BODY_START_Z: float = 5.0

## Marge de détection tunneling (m) — évite les faux positifs dus à la safe_margin Jolt.
const TUNNEL_MARGIN_M: float = 0.05

## Offset du plan Area3D derrière le mur (m) — détection clip primaire via signal.
const AREA_BEHIND_WALL_OFFSET_M: float = 0.3

## Layer PLAYER (1-indexé, ADR-0008 / CollisionLayers.LAYER_PLAYER = 1).
## Note : tests/** est hors scope de collision-layer-api-1-indexed.md (rule src/** only).
## On utilise set_collision_layer_value / set_collision_mask_value conforme ADR-0008.
const LAYER_PLAYER: int = 1

## Layer ENVIRONMENT (1-indexé, ADR-0008 / CollisionLayers.LAYER_ENVIRONMENT = 4).
const LAYER_ENVIRONMENT: int = 4

## Rayon capsule joueur (approximation production, conforme Player.tscn scaffold).
const CAPSULE_RADIUS: float = 0.3

## Hauteur capsule joueur (1.8 m = corps standard FPS).
const CAPSULE_HEIGHT: float = 1.8

## Demi-extents du mur sur axes X et Y (non testés — seule l'épaisseur Z varie).
const WALL_HALF_EXTENT_X: float = 5.0
const WALL_HALF_EXTENT_Y: float = 5.0

# ---------------------------------------------------------------------------
# Private variables
# ---------------------------------------------------------------------------

## Corps CharacterBody3D par arena (index = index scénario).
var _player_bodies: Array[CharacterBody3D] = []

## Positions de départ par arena.
var _body_start_positions: Array[Vector3] = []

## Plan arrière des murs (z négatif) par arena.
var _wall_back_z_values: Array[float] = []

## Flags de clip par Area3D (index = index scénario).
## Mis à true par signal body_entered quand le joueur traverse le mur.
var _area_clip_flags: Array[bool] = []

## Collisions totales détectées par move_and_slide() par scénario.
## Utilisé pour le sanity check global (Jolt actif ?).
## Initialisé à 0 pour chaque scénario ; mis à jour par _run_scenario().
var _scenario_total_collisions: Array[int] = []

# ---------------------------------------------------------------------------
# Built-in virtual methods
# ---------------------------------------------------------------------------

func _ready() -> void:
	_setup_arenas()
	_run_benchmark.call_deferred()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Spawne 4 arenas programmatiquement (1 par scénario).
## Chaque arena = StaticBody3D mur + Area3D détecteur + Player.tscn instancié.
## Pattern : add_child() AVANT global_position (Node3D requiert is_inside_tree — Godot warning sinon).
func _setup_arenas() -> void:
	for i: int in range(SCENARIOS.size()):
		var scenario: Dictionary = SCENARIOS[i]
		var thickness: float = float(scenario["thickness_m"])
		var offset_x: float = float(i) * ARENA_SPACING_X

		# --- Mur StaticBody3D ---
		# Mur : layer ENVIRONMENT (4), mask 0 (le mur ne détecte rien).
		var wall: StaticBody3D = StaticBody3D.new()
		wall.name = "Wall_%02d" % i
		wall.set_collision_layer_value(LAYER_ENVIRONMENT, true)

		var wall_shape_node: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(WALL_HALF_EXTENT_X * 2.0, WALL_HALF_EXTENT_Y * 2.0, thickness)
		wall_shape_node.shape = box
		wall.add_child(wall_shape_node)
		add_child(wall)
		wall.global_position = Vector3(offset_x, 0.0, 0.0)

		# Plan arrière du mur centré à z=0 : z = -(thickness / 2).
		var wall_back_z: float = -(thickness * 0.5)
		_wall_back_z_values.append(wall_back_z)

		# --- Area3D détecteur derrière le mur (détection clip primaire) ---
		# Placée à AREA_BEHIND_WALL_OFFSET_M derrière le plan arrière du mur.
		# Si body_entered se déclenche → le joueur a traversé le mur (clip confirmé).
		var area: Area3D = Area3D.new()
		area.name = "ClipDetector_%02d" % i
		area.monitoring = true
		area.monitorable = false
		# Area3D : mask PLAYER (1) pour détecter le CharacterBody3D.
		area.set_collision_mask_value(LAYER_PLAYER, true)

		var area_shape_node: CollisionShape3D = CollisionShape3D.new()
		var area_box: BoxShape3D = BoxShape3D.new()
		# Plan fin (0.1 m) derrière le mur pour capturer tout corps ayant traversé.
		area_box.size = Vector3(WALL_HALF_EXTENT_X * 2.0, WALL_HALF_EXTENT_Y * 2.0, 0.1)
		area_shape_node.shape = area_box
		area.add_child(area_shape_node)
		add_child(area)
		area.global_position = Vector3(offset_x, 0.0, wall_back_z - AREA_BEHIND_WALL_OFFSET_M)

		# Connexion signal : closure capturant l'index pour mettre à jour _area_clip_flags.
		# arena_index capturé explicitement (lambda capture-by-value en GDScript 4).
		var arena_index: int = i
		area.body_entered.connect(func(_body: Node3D) -> void:
			_area_clip_flags[arena_index] = true
		)

		# --- Player instancié depuis Player.tscn (DEV-1) ---
		# Player.tscn = CharacterBody3D root + CameraArm + CombatSystem.
		# CollisionShape3D absente → ajoutée programmatiquement (Movement story-001 à venir).
		var player_instance: Node = PLAYER_SCENE.instantiate()
		var player_body: CharacterBody3D = player_instance as CharacterBody3D
		player_body.name = "Player_%02d" % i
		# MOTION_MODE_FLOATING : pas de gravité appliquée (joueur FPS).
		player_body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		player_body.safe_margin = 0.001  # Jolt default, conforme story-014.
		# Joueur : layer PLAYER (1), mask ENVIRONMENT (4) pour collider avec le mur.
		player_body.set_collision_layer_value(LAYER_PLAYER, true)
		player_body.set_collision_mask_value(LAYER_ENVIRONMENT, true)

		# CollisionShape3D capsule ajoutée programmatiquement (DEV-1).
		# add_child(player_body) AVANT player_body.add_child(capsule_shape_node)
		# → player_body doit être dans l'arbre pour que global_position fonctionne.
		add_child(player_body)
		var capsule_shape_node: CollisionShape3D = CollisionShape3D.new()
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = CAPSULE_RADIUS
		capsule.height = CAPSULE_HEIGHT
		capsule_shape_node.shape = capsule
		player_body.add_child(capsule_shape_node)

		var start_pos: Vector3 = Vector3(offset_x, 0.0, BODY_START_Z)
		player_body.global_position = start_pos

		_player_bodies.append(player_body)
		_body_start_positions.append(start_pos)
		_area_clip_flags.append(false)
		_scenario_total_collisions.append(0)


# ---------------------------------------------------------------------------
# Benchmark coroutine
# ---------------------------------------------------------------------------

## Lance les 4 scénarios séquentiellement et quitte avec exit code 0 ou 1.
## Exit 0 = tous scénarios → clips == 0 + sanity check OK.
## Exit 1 = au moins un scénario → clips > 0 OU sanity check fail.
func _run_benchmark() -> void:
	# Garantir qu'au moins un tick physique Jolt s'est écoulé avant les passes.
	await get_tree().physics_frame

	print("=== EC-8 Jolt CCD Gameplay Gate — Story-023 AC-LVL-43 ===")
	print("scenarios=%d, passes_per_scenario=%d, ticks_per_pass=%d" % [
		SCENARIOS.size(), PASSES_PER_SCENARIO, PHYSICS_TICKS_PER_PASS
	])
	print("")

	var scenario_results: Array[Dictionary] = []
	var gate_pass: bool = true
	var total_collisions_all_scenarios: int = 0

	for i: int in range(SCENARIOS.size()):
		var scenario: Dictionary = SCENARIOS[i]
		var scenario_name: String = str(scenario["name"])
		var thickness: float = float(scenario["thickness_m"])
		var velocity_z: float = float(scenario["velocity_z"])

		var clips: int = await _run_scenario(i, velocity_z)
		var clips_rate: float = (float(clips) / float(PASSES_PER_SCENARIO)) * 100.0

		total_collisions_all_scenarios += _scenario_total_collisions[i]

		var result: Dictionary = {
			"name": scenario_name,
			"thickness_m": thickness,
			"clips": clips,
			"passes": PASSES_PER_SCENARIO,
			"clips_rate_pct": snappedf(clips_rate, 0.01),
		}
		scenario_results.append(result)

		var status_str: String = "PASS" if clips == 0 else "FAIL"
		print("  %s (%.1fm @ %.1fm/s) → clips=%d rate=%.2f%% [%s]" % [
			scenario_name, thickness, absf(velocity_z), clips, clips_rate, status_str
		])

		if clips > 0:
			gate_pass = false

	print("")

	# Sanity check — si AUCUNE collision n'a été détectée sur l'ensemble des scénarios
	# ET tous les clips = 0, Jolt est probablement inactif (simulation non démarrée).
	# Source : garde-fou copié de story-014 level_ccd_sweep_runner.gd.
	if total_collisions_all_scenarios == 0:
		var sanity_msg: String = (
			"EC-8 gameplay sanity FAIL — 0 collision détectée sur tous les scénarios. "
			+ "Jolt probablement inactif ou CollisionShape3D non initialisée. Résultats invalides."
		)
		push_error(sanity_msg)
		gate_pass = false

	# Output JSON_RESULT structuré (format spec story-023).
	var json_out: Dictionary = {"scenarios": scenario_results}
	print("JSON_RESULT:")
	print(JSON.stringify(json_out))
	print("")

	if gate_pass:
		print("EC-8 gameplay gate PASS — 0 clips sur tous les scénarios (AC-LVL-43)")
	else:
		push_error("EC-8 gameplay gate FAIL — voir messages ci-dessus (TR-lvl-039 / sanity)")

	get_tree().quit(0 if gate_pass else 1)


# ---------------------------------------------------------------------------
# Simulation d'un scénario
# ---------------------------------------------------------------------------

## Exécute PASSES_PER_SCENARIO passes pour le scénario à l'index [scenario_idx].
## Retourne le nombre de passes où un tunneling est détecté.
## Met à jour _scenario_total_collisions[scenario_idx] (sanity check).
##
## [param scenario_idx] : index dans SCENARIOS / _player_bodies.
## [param velocity_z] : vitesse sur Z (négatif = vers le mur, m/s).
## [return] : nombre de clips détectés sur les PASSES_PER_SCENARIO passes.
func _run_scenario(scenario_idx: int, velocity_z: float) -> int:
	var clips: int = 0
	var body: CharacterBody3D = _player_bodies[scenario_idx]
	var start_pos: Vector3 = _body_start_positions[scenario_idx]
	var wall_back_z: float = _wall_back_z_values[scenario_idx]
	var total_collisions: int = 0

	for _pass: int in range(PASSES_PER_SCENARIO):
		# Réinitialiser le flag Area3D avant chaque passe.
		_area_clip_flags[scenario_idx] = false

		var pass_result: Dictionary = await _simulate_pass(
			body, start_pos, wall_back_z, velocity_z
		)

		var clipped_by_area: bool = _area_clip_flags[scenario_idx]
		var clipped_by_position: bool = bool(pass_result["clipped_by_position"])
		var pass_collisions: int = int(pass_result["collisions"])

		total_collisions += pass_collisions

		# Clip confirmé si l'une ou l'autre des deux méthodes de détection se déclenche.
		if clipped_by_area or clipped_by_position:
			clips += 1

	_scenario_total_collisions[scenario_idx] = total_collisions
	return clips


## Simule une passe unique : corps partant de start_pos, se déplaçant à velocity_z
## vers un mur centré à z=0.
##
## Détection double critère :
##   Primaire  — Area3D.body_entered (signal _area_clip_flags[i]) :
##               déclenché si le joueur traverse physiquement le mur.
##   Fallback  — position finale : z < wall_back_z - TUNNEL_MARGIN_M
##               ET collisions == 0 (conforme story-014).
##
## [param body] : CharacterBody3D instancié du Player.
## [param start_pos] : position de départ pour réinitialisation.
## [param wall_back_z] : plan arrière du mur (z négatif).
## [param velocity_z] : vitesse sur Z en m/s (négatif = vers le mur).
## [return] : Dictionary {clipped_by_position: bool, collisions: int}.
func _simulate_pass(
	body: CharacterBody3D,
	start_pos: Vector3,
	wall_back_z: float,
	velocity_z: float
) -> Dictionary:
	# Réinitialiser position et vitesse.
	body.global_position = start_pos
	body.velocity = Vector3(0.0, 0.0, velocity_z)

	var accumulated_collisions: int = 0

	for _tick: int in range(PHYSICS_TICKS_PER_PASS):
		await get_tree().physics_frame

		body.move_and_slide()
		accumulated_collisions += body.get_slide_collision_count()

		# Arrêt anticipé si collision détectée (pas de tunneling, corps stoppé).
		if accumulated_collisions > 0:
			break

		# Arrêt anticipé si le corps a largement dépassé le mur (hors scène).
		if body.global_position.z < wall_back_z - 2.0:
			break

	# Fallback : détection via position finale (conforme story-014 pattern).
	var final_z: float = body.global_position.z
	var clipped_by_position: bool = (
		final_z < wall_back_z - TUNNEL_MARGIN_M
		and accumulated_collisions == 0
	)

	return {
		"clipped_by_position": clipped_by_position,
		"collisions": accumulated_collisions,
	}
