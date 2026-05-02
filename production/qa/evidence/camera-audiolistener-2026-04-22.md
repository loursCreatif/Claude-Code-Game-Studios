# QA Evidence — AC-CAM-TREE-4 : AudioListener3D auto-current

**Story** : Story 001 — Camera System Scene Skeleton + Project Settings
**AC** : AC-CAM-TREE-4
**Date** : 2026-04-22
**Status** : DEFERRED — validation en playtest Sprint 1

## Ce qu'on valide

L'`AudioListener3D` enfant de `Camera3D` dans `Player.tscn` doit être auto-current
sans appel explicite à `make_current()`. Quand le Player est la scène active, le son
3D doit être spatialisé depuis la position de la caméra.

## Procédure de validation manuelle

1. Ouvrir `Player.tscn` dans Godot 4.6.
2. Ajouter un `AudioStreamPlayer3D` dans la scène de test à la position `Vector3(10, 0, 0)` (droite).
3. Assigner un fichier audio au stream player (ex. bip court mono).
4. Lancer la scène avec le Player à `rotation.y = 0` (regardant +Z).
5. Écouter : le son doit provenir de l'oreille droite (panning droit).
6. Vérifier qu'aucun `AudioListener3D.make_current()` n'est appelé dans `camera_system.gd`.

## Critère de succès

- Son spatialisé correctement depuis la position caméra (droite quand source à +X).
- Aucun `make_current()` dans `src/gameplay/camera/camera_system.gd`.
- Le `AudioListener3D` node dans le scene tree est auto-actif (Godot active le premier
  `AudioListener3D` trouvé dans le scene tree quand la scène est chargée).

## Notes

- Godot 4.6 : si une scène contient un seul `AudioListener3D`, il devient current
  automatiquement à l'entrée dans le scene tree. Pas besoin de `make_current()`.
- Si plusieurs listeners existent dans le projet, le comportement peut varier —
  valider en contexte de jeu complet au Sprint 1.
- Ref : ADR-0002, `docs/architecture/control-manifest.md`
