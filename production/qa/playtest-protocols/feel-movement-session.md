# Protocole Playtest — Feel Movement (Pillar 1 FLOW AVANT TOUT)

> **Story** : player-movement-system / story-017
> **ADR** : ADR-0001 (Pillar 1)
> **GDD** : design/gdd/player-movement-system.md (Feel Acceptance Criteria)
> **Préalable** : Stories 001-016 implémentées + tests automatisés passants

## Objectif

Valider qualitativement le feel Ghostrunner-like du moveset Movement (course / saut /
double-saut / dash / wall-run / wall-jump). Évidence requise pour gate
**Pre-Production → Production** (EPIC DoD).

## Setup

| Élément | Valeur |
|---------|--------|
| Build | Release MVP (pas debug) |
| Hardware | Entry-level laptop (cible Steam) |
| Input | Clavier + souris |
| Capabilities | toutes actives (`set_capability` debug fixture) |
| Scène | `tests/scenes/perf_test_movement.tscn` (ou Player.tscn + sol + 2 murs corridor) |
| Durée par session | 10 min jeu libre + 10 morts scriptées (attribution causale) |

## Protocole — Session libre 10 min

1. Briefer : "explore librement le mouvement, essaie tout, signale tout ce qui te
   surprend."
2. Le facilitateur observe SANS donner d'instructions ; note verbatim chaque
   commentaire spontané du joueur.
3. À 10 min, pose la question "sur 1-5, le mouvement répond-il instantanément à
   ton input ?" (ADR-0001 EC-1).

### Grille d'observation — mots-clés

**Positifs attendus** (≥ 1 prononcé spontanément par session = bon signe) :
- `réactif`, `instantané`, `fluide`, `précis`, `je contrôle`, `responsive`,
  `tight`, `snappy`

**Négatifs à traquer** (≥ 1 verbatim = trigger ADR-0001 EC-3, spike 120 Hz à
considérer) :
- `floaty`, `slippery`, `unresponsive`, `flottant`, `mou`, `raté`, `stuck`,
  `j'anticipe mes inputs`, `ça répond pas tout de suite`

**Pass condition Feel Playtest** :
- < 20 % de mots-clés négatifs / session (sur 5 sessions)
- Score moyen latence ≥ 3 / 5

## Protocole — Attribution causale 50 ms (garde-fou)

Configurer 10 morts scriptées (laser rouge, pic, ennemi melee, chute pit). Après
chaque mort :

1. Facilitateur : "qu'est-ce qui t'a tué ?" (4 options : laser / pic / ennemi /
   chute)
2. Note la réponse. Compte les corrects.

**Pass condition** : ≥ 4 joueurs / 5 identifient correctement sur ≥ 8 morts / 10.

Si fail → flagger `RESPAWN_DELAY_MS = 50.0` suspect, considérer 80-120 ms en
playtest MVP (revisite ADR-0005 VC-7).

## Captures dédiées (AC-MV-100/101)

Effectuées en parallèle des sessions libres :

- **AC-MV-100 — Dash FOV pulse** : déclencher dash, screenshot à `t = DASH_DURATION/2`
  (= 50 ms = ~3 ticks). Vérifier `camera3d.fov ∈ [99, 101]` (BASE_FOV 90 + DASH_FOV_KICK 10
  appartenant au Camera epic — la story-017 valide la lisibilité visuelle, pas
  l'implémentation Camera). Avec `reduce_motion=true` → fov ≤ 94°.
- **AC-MV-101 — Death fade rouge** : appeler `player.die()`, screenshot à
  `t = RESPAWN_DELAY/2 ≈ 25 ms`. Fondu rouge plein écran ≤ 40 ms ; avec
  `reduce_flash=true` → assombrissement gris neutre 80-120 ms.

Outputs PNG → `production/qa/evidence/dash-vfx-[date].png` et
`production/qa/evidence/death-fade-[date].png`.

## Anti-références

Si ≥ 1 verbatim parmi `j'anticipe mes inputs`, `ça répond pas tout de suite`,
`c'est mou`, `c'est flottant` est prononcé spontanément, déclencher le
protocole ADR-0001 **EC-3** (spike 120 Hz A/B blind).

## Prototype continuity

`prototypes/movement-katana/` doit avoir reçu ≥ 3 sessions playtest avec feel
positif AVANT que cette validation src/ ne se substitue. Comparer les tuning
values entre `prototypes/movement-katana/player.gd` et
`src/gameplay/player/movement_controller.gd` (post stories 001-013) :

- MOVE_SPEED, GRAVITY, JUMP_VELOCITY, AIR_JUMP_VELOCITY, DASH_SPEED, DASH_DURATION,
  DASH_EXIT_SPEED, DASH_MOMENTUM_WINDOW, DASH_COOLDOWN, WALL_RUN_*, WALL_JUMP_SIDE,
  WALL_JUMP_UP

→ Si tuning identique ET feel subjectif Martin + 2 tiers en session courte
identique au prototype → continuité validée. Sign-off
`production/qa/evidence/prototype-to-src-continuity-[date].md`.
