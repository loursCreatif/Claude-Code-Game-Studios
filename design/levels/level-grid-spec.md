# Level Grid Specification — CHROME://ASCENT

> **Status**: Stub (à compléter avec level-designer)
> **Created**: 2026-04-21
> **Owner**: level-designer
> **Source constraint**: `design/gdd/player-movement-system.md`

---

## Purpose

Ce document déclare la **grille modulaire canonique** que le level design doit respecter pour que les promesses du Player Movement System ("1 dash = 1 gap", "saut simple barely clears body") soient tenables sur toute la plage de tuning. Le Movement GDD engage les valeurs ci-dessous ; ce document les fige pour le level design.

---

## Canonical Grid Constants

| Dimension | Valeur cible | Justification movement |
|---|---|---|
| **Corridor width (standard)** | 2.0 m | `DASH_SPEED * DASH_DURATION` (valeurs nominales) couvre 1 gap |
| **Corridor gap (standard)** | 2.0 m | Dash traverse 1 gap, 2 gaps requièrent wall-run ou combo |
| **Parallel walls (wall-jump zone, MVP standard)** | 3.0 m | Wall-jump seul nominal (3.25 m) suffit avec marge 0.25 m. *Revised r3 Player Movement (2026-04-21) : 3.25 m hard cap — la décision Martin A (wall-jump bloque double-jump) rend impossible le combo wall-jump + double-jump précédemment assumé pour les couloirs 4 m.* |
| ~~**Parallel walls (wall-jump + double-jump zone)**~~ ~~4.0 m~~ | **RETIRÉ MVP r3** | Décision Martin r3 A (Player Movement) : wall-jump set `air_jumps_used = MAX_AIR_JUMPS`, double-jump bloqué post-wall-jump. Les couloirs 4 m ne sont plus franchissables en combo MVP. À réintroduire post-MVP si triple-jump (MAX_AIR_JUMPS=2) est ajouté comme upgrade Tier 2. |
| **Obstacle low (simple jump clearable)** | ≤ 0.85 m | `JUMP_VELOCITY² / (2*GRAVITY)` à valeurs nominales = 0.875 m. Range min r3 garantit 0.810 m (JUMP_VELOCITY_min=7.2 à GRAVITY_max=32) — couvre obstacle ≤ 0.8 m strict, marge 0.01 m. |
| **Obstacle mid (double-jump required)** | 1.0–1.6 m | Hors simple jump, dans combo jump |
| **Obstacle high (wall-run/dash required)** | > 1.6 m | Gate capability `can_wall_run` OU `can_air_jump` |
| **Wall-run max length (single segment)** | ≤ 15 m | `WALL_RUN_MAX_DURATION * MOVE_SPEED` = 15 m avant auto-eject |
| **Checkpoint clearance (sous-surface solide)** | ≥ 0.5 m | Évite respawn-in-void loop |
| **Checkpoint horizontal clear from hazard** | ≥ 2.0 m | Temps de parsing avant que le joueur doive réagir |

---

## Tier-0 Accessibility Rule (pre-upgrade)

**Règle** : Au minimum **1 secret** par zone de Tier 1 (MVP) doit être accessible avec le moveset de base uniquement (run + simple jump, `can_dash=false`, `can_air_jump=false`, `can_wall_run=false`).

**Raison** : éviter la circularité "pour trouver un secret, il faut l'upgrade ; pour vouloir l'upgrade, il faut sentir la valeur des secrets" (level-designer F6).

---

## Retro-fit Warnings

Ce document est écrit en réaction à un gap identifié par `/design-review player-movement-system.md` (2026-04-21). Les contraintes ci-dessus :
- Ne sont pas validées par playtest au moment de cette rédaction
- Sont des valeurs nominales uniquement — le tuning movement peut bouger dans les safe ranges et le level design doit re-valider à chaque changement
- Ne couvrent pas encore : tier-1 level design patterns, patrol paths ennemis, sight-lines, VFX spatialization

---

## Next Steps

- [ ] `/design-system level-system` pour écrire le GDD complet Level System, qui inclura ces constantes
- [ ] Playtest du prototype `movement-katana` pour valider les valeurs nominales vs grille
- [ ] Cross-reference avec art direction (art-bible) pour dimensions visuelles cohérentes avec la grille fonctionnelle

---

## Cross-references

- `design/gdd/player-movement-system.md` — Formulas section (source des valeurs movement)
- `design/gdd/game-concept.md` — Visual Identity Anchor (Chrome Zen, géométrie corporate minimaliste)
- Futur : `design/gdd/level-system.md`, `design/gdd/secret-system.md`
