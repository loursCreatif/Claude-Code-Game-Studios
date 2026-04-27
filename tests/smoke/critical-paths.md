# Smoke Test: Critical Paths

**Purpose** : exécuter ces 10-15 checks en moins de 15 minutes avant toute hand-off QA.
**Run via** : `/smoke-check` (lit ce fichier)
**Update** : ajouter une entrée quand un nouveau système core est implémenté.

## Core Stability (always run)

1. Le jeu démarre jusqu'au main menu sans crash
2. Une nouvelle session peut être lancée depuis le main menu
3. Le main menu répond à tous les inputs sans freeze

## Core Mechanic (update per sprint)

<!-- Ajouter ici le mécanisme primaire de chaque sprint à mesure qu'il est implémenté -->

4. **[Sprint 1 — Movement]** Le joueur peut marcher, sauter, dash, wall-run — la caméra suit correctement (60 fps locked, pas de décalage input > 1 frame)
5. **[Sprint 1 — Input]** `was_pressed_this_tick()` est consommé dans le tick courant (AC-CS-1 tick N parity)

## Data Integrity

6. Save game complete sans erreur (une fois save system implémenté)
7. Load game restaure l'état correct (une fois load system implémenté)

## Performance

8. Pas de frame rate drops visibles sur target hardware (60 fps vsync locked)
9. Pas de croissance mémoire > 64 KB sur 60 s de gameplay (zero-alloc hot path AC-PF-2)
10. Input-to-display latency p99 ≤ 16 ms intra-engine (budget Pillar 1 FLOW)
