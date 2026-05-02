# Attribution causale 50 ms — Garde-fou Feel AC

> **Story** : player-movement-system / story-017
> **AC** : Feel AC Attribution causale (garde-fou Martin r3)
> **Constante testée** : `RESPAWN_DELAY_MS = 50.0` (story-001/008 + ADR-0005 VC-7)
> **Date** : DEFERRED — séance non encore réalisée
> **Statut** : **TEMPLATE / PENDING** — à compléter par QA Lead avec 5 joueurs débutants

## Setup

- Build release MVP, scène avec hazards variés (laser rouge, pic, ennemi melee, chute pit)
- 5 playtesters DÉBUTANTS (jamais joué CHROME://ASCENT, idéalement non-FPS hardcore)
- 10 morts scriptées par playtester (4 hazards × ~2-3 occurrences = 10)
- Facilitateur en face-à-face, demande après chaque mort : **"qu'est-ce qui t'a tué ?"**

## Grille (à remplir)

| # mort | Cause réelle | Joueur 1 | Joueur 2 | Joueur 3 | Joueur 4 | Joueur 5 |
|--------|-------------|----------|----------|----------|----------|----------|
| 1 | TBD | TBD | TBD | TBD | TBD | TBD |
| 2 | TBD | TBD | TBD | TBD | TBD | TBD |
| 3 | TBD | TBD | TBD | TBD | TBD | TBD |
| 4 | TBD | TBD | TBD | TBD | TBD | TBD |
| 5 | TBD | TBD | TBD | TBD | TBD | TBD |
| 6 | TBD | TBD | TBD | TBD | TBD | TBD |
| 7 | TBD | TBD | TBD | TBD | TBD | TBD |
| 8 | TBD | TBD | TBD | TBD | TBD | TBD |
| 9 | TBD | TBD | TBD | TBD | TBD | TBD |
| 10 | TBD | TBD | TBD | TBD | TBD | TBD |

**Score correct par joueur** : Joueur 1 __/10 ; Joueur 2 __/10 ; Joueur 3 __/10 ;
Joueur 4 __/10 ; Joueur 5 __/10.

## Pass condition

≥ 4 joueurs / 5 ont identifié correctement sur ≥ 8 morts / 10.

- Joueurs avec score ≥ 8/10 : __ / 5
- **Verdict** : [ ] PASS [ ] FAIL

## Action si FAIL

Flagger `RESPAWN_DELAY_MS = 50.0` insuffisant. Plan :
1. Mesurer si erreurs concentrées sur hazards spécifiques (laser vs pic) → revoir
   la lisibilité visuelle du hazard (responsabilité Level/Art).
2. Si erreurs réparties → trigger spike `RESPAWN_DELAY_MS = 80-120 ms`,
   re-playtest. Documenter dans amendement ADR-0005 VC-7.

## Sign-off

| Rôle | Nom | Signature |
|------|-----|-----------|
| QA Lead | TBD | _______ |
| Game Designer (si re-tune RESPAWN) | TBD | _______ |
