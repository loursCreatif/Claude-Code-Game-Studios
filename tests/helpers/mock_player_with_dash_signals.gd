# Mock Player pour les tests nécessitant player.dash_started / player.dash_ended.
# Utilisé par story-006 et toute story future testant des features qui
# consomment les signaux dash avant que Movement stories soient Complete.
#
# Design : CharacterBody3D minimal — expose uniquement les signaux canoniques
# ADR-0005 D-2 nécessaires à CameraSystem. Aucune logique de mouvement.
# Les tests émettent les signaux directement via .emit() sur l'instance.

class_name MockPlayerWithDashSignals
extends CharacterBody3D

## Émis quand le player entre en état DASHING.
## Signature canonique ADR-0005 D-2 + D-3.
signal dash_started(dash_dir: Vector3, dash_speed: float)

## Émis quand le player quitte l'état DASHING.
## Signature canonique ADR-0005 D-2 (no payload).
signal dash_ended()
