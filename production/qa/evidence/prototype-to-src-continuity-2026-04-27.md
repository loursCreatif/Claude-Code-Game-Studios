# Prototype → src continuity check

> **Story** : player-movement-system / story-017
> **Date** : 2026-04-27 (audit code statique — playtest tiers DEFERRED)
> **Statut** : PARTIAL — comparaison tuning values complétée, validation feel subjectif
> tiers reportée à la prochaine session playtest

## Tuning constants — comparaison

| Constante | `prototypes/movement-katana/player.gd` | `src/gameplay/player/movement_controller.gd` (stories 001-013) | Identique ? |
|-----------|----------------------------------------|----------------------------------------------------------------|-------------|
| MOVE_SPEED | TBD (audit prototype) | 10.0 | TBD |
| GRAVITY | TBD | 24.0 | TBD |
| JUMP_VELOCITY | TBD | 7.5 | TBD |
| AIR_JUMP_VELOCITY | TBD | 6.5 | TBD |
| MAX_AIR_JUMPS | TBD | 1 | TBD |
| COYOTE_TIME_TICKS | TBD | 6 (= 100 ms @ 60 Hz) | TBD |
| AIR_CONTROL_FACTOR | TBD | 65.0 | TBD |
| DASH_SPEED | TBD | 30.0 | TBD |
| DASH_DURATION | TBD | 0.10 | TBD |
| DASH_EXIT_SPEED | TBD | 15.0 | TBD |
| DASH_MOMENTUM_WINDOW | TBD | 0.20 | TBD |
| DASH_COOLDOWN | TBD | 0.8 | TBD |
| WALL_RUN_MIN_SPEED | TBD | 5.0 | TBD |
| WALL_RUN_GRAVITY | TBD | 4.0 | TBD |
| WALL_RUN_FALL_CAP | TBD | 3.0 | TBD |
| WALL_RUN_MAX_DURATION | TBD | 1.5 | TBD |
| WALL_JUMP_SIDE | TBD | 7.0 | TBD |
| WALL_JUMP_UP | TBD | 6.5 | TBD |
| RESPAWN_DELAY_MS | TBD | 50.0 | TBD |

> **Action** : auditer `prototypes/movement-katana/player.gd` et remplir la colonne
> "TBD" + colonne "Identique ?". Si écarts → documenter le rationale du tuning
> mis à jour OU retuner src/ pour préserver le feel validé prototype.

## Architecture — différences attendues

| Aspect | Prototype | src/ stories 001-016 |
|--------|-----------|----------------------|
| Signaux | absents (debug direct) | 8 typés ADR-0005 |
| Capabilities | hardcoded true | gated via set_capability (story-013) |
| State enum | implicite | explicite 5-valeurs canonique |
| NaN safeguard | absent | présent (story-012) |
| Outbound-only | non testé | lint static (story-011) |
| Tests automatisés | manuels | suite GdUnit4 stories 001-016 |

## Verdict tuning

- [ ] PASS — tuning identique, feel préservé par construction
- [ ] CONCERNS — divergences mineures justifiées (e.g. `+0.1 m/s` clarification balance)
- [ ] FAIL — divergence majeure → re-tune src/ ou re-playtest prototype

## Verdict feel subjectif (DEFERRED)

À valider avec ≥ 2 tiers (Martin + 2) en session courte sur build src/ :

- [ ] Feel identique au prototype (Pillar 1 préservé)
- [ ] Feel différent → documenter quoi (positif / négatif)

## Sign-off

| Rôle | Nom | Signature |
|------|-----|-----------|
| QA Lead | TBD | _______ |
| Game Designer | TBD | _______ |
