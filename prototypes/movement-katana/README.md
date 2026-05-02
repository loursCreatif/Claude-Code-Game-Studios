# Prototype movement-katana

**PROTOTYPE — NOT FOR PRODUCTION. Code à jeter, à ne pas importer depuis `src/`.**

## Question

Le feel du mouvement katana + parkour (input <1 frame, dash, wall-run, double jump, katana one-shot en mouvement rapide) est-il atteignable en Godot 4.6 avec GDScript ?

## Lancer le prototype

```
godot --path prototypes/movement-katana
```

Ou depuis l'éditeur Godot : `Importer → prototypes/movement-katana/project.godot → F5`.

## Contrôles

| Touche | Action |
|---|---|
| `W A S D` | Déplacement |
| `Souris` | Regarder |
| `Espace` | Saut (x2 dispo en l'air) |
| `Shift` | Dash horizontal (cooldown 0.8s) |
| `Clic gauche` | Coup de katana |
| `R` | Respawn manuel |
| `Échap` | Relâcher la souris |

## Ce qu'il faut tester (check-list feel)

1. **Réponse input** : le HUD affiche `Last input→action`. Viser <16ms.
2. **Mouvement au sol** : démarre/s'arrête net ? Pas de glisse longue ?
3. **Saut simple + double saut** : la courbe de chute semble rapide ? Pas flottante ?
4. **Dash** : immédiat au Shift ? 0.15s de burst puis rend le contrôle ?
5. **Wall-run** : en sprintant parallèle à un des deux murs latéraux, la chute ralentit ? Un saut lance latéralement depuis le mur ?
6. **Hitbox katana en mouvement** : dasher à travers un ennemi et swinguer simultanément — le kill s'enregistre-t-il même à vitesse élevée ? (Test anti-tunneling.)
7. **One-shot mutuel** : entrer dans le laser rouge devant un ennemi tue-t-il le joueur instantanément ? Respawn <1s ?
8. **120 Hz physique** : le compteur FPS monte-t-il librement au-dessus de 60 ? (vsync locked à la fréquence du moniteur.)

## Arène de test

- Zone de départ (z=+6) face à un enemy proche
- Couloir mur-à-mur pour wall-run (deux murs parallèles 4m d'écart)
- Plateforme haute à l'arrière pour tester le double jump
- Saut de dash sur plateforme isolée à z=+12 (pit mortel en dessous)
- 4 ennemis placés à différentes distances/hauteurs

## Fichiers

- `project.godot` — config (Jolt, Forward+, 120Hz physique, inputs)
- `main.tscn` + `main.gd` — arène procédurale
- `player.gd` — character controller (120 lignes)
- `katana.gd` — swing + ShapeCast3D hitbox (~60 lignes)
- `enemy.gd` + `enemy.tscn` — cible one-shot + laser
- `hud.gd` — métriques à l'écran

## Tuning à iterer si quelque chose sent faux

Tous dans `player.gd` en haut :

| Const | Valeur actuelle | Axe |
|---|---|---|
| `MOVE_SPEED` | 10.0 | Vitesse au sol |
| `JUMP_VELOCITY` | 7.0 | Hauteur saut |
| `AIR_JUMP_VELOCITY` | 6.5 | Hauteur double saut |
| `GRAVITY` | 28.0 | Agressivité chute |
| `DASH_SPEED` | 28.0 | Burst dash |
| `DASH_DURATION` | 0.15 | Fenêtre dash |
| `DASH_COOLDOWN` | 0.8 | Cadence dash |
| `WALL_RUN_GRAVITY` | 4.0 | Stickiness wall-run |
| `MOUSE_SENS` | 0.0022 | Sensibilité souris |
