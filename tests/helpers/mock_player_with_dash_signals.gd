# Mock Player exposant les signaux canoniques ADR-0005 D-2 consommés par CameraSystem.
# Utilisé par story-006 (dash) et story-007 (wall_jumped) — extensible aux stories
# futures qui ajouteront wall_run_entered/exited, died, respawned.
#
# Design : CharacterBody3D minimal — expose uniquement les signaux nécessaires
# à CameraSystem._ready() pour que la connexion ne crash pas. Aucune logique
# de mouvement. Les tests émettent les signaux directement via .emit() sur l'instance.
#
# Note : le nom historique "WithDashSignals" est conservé pour minimiser la ripple
# sur story-006. Le contrat effectif est "MockPlayerWithCameraSignals".

class_name MockPlayerWithDashSignals
extends CharacterBody3D

## Émis quand le player entre en état DASHING.
## Signature canonique ADR-0005 D-2 + D-3.
signal dash_started(dash_dir: Vector3, dash_speed: float)

## Émis quand le player quitte l'état DASHING.
## Signature canonique ADR-0005 D-2 (no payload).
signal dash_ended()

## Émis lors du saut depuis un mur (wall-run jump).
## Signature canonique ADR-0005 D-2 : (wall_normal: Vector3, launch_velocity: Vector3).
## Consommé par CameraSystem._on_wall_jumped (story 007).
signal wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)

## Émis à l'entrée WALL_RUNNING. Signature canonique ADR-0005 D-2 : (wall_normal: Vector3).
## Consommé par CameraSystem._on_wall_run_entered (TD-004 — substitue polling wall_normal).
signal wall_run_entered(wall_normal: Vector3)

## Émis à la sortie WALL_RUNNING. Signature canonique ADR-0005 D-2 (no payload).
## Consommé par CameraSystem._on_wall_run_exited (TD-004).
signal wall_run_exited()

## Émis quand le player meurt. Signature canonique ADR-0005 D-2 (no payload).
## Consommé par CameraSystem._on_died (story 008).
signal died()

## Émis après respawn. Signature canonique ADR-0005 D-2 : (position: Vector3).
## Consommé par CameraSystem._on_respawned (story 008).
signal respawned(position: Vector3)

## Normale du mur courant (read-only pour Camera, ADR-0005 D-7).
## Consommé par CameraSystem._update_tilt_wall_run via get("wall_normal") défensif.
## ZERO quand pas en wall-run. Ajouté story 011 pour les tests AC-CAM-64 (focus-loss
## tilt continuity) sans dépendance à MockPlayerWithWallNormal.
var wall_normal: Vector3 = Vector3.ZERO
