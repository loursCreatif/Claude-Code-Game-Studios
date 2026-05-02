# Feel Playtest — Session 1

> **Story** : player-movement-system / story-017
> **Protocole** : `production/qa/playtest-protocols/feel-movement-session.md`
> **Date** : DEFERRED — séance non encore réalisée
> **Statut** : **TEMPLATE / PENDING** — à remplir par QA Lead après la première session réelle

## Métadonnées (à remplir)

| Champ | Valeur |
|-------|--------|
| Date session | TBD |
| Playtester (initiales / handle) | TBD |
| Profil (gamer / casual / dev) | TBD |
| Hardware | TBD (entry-level laptop cible) |
| Build | release MVP commit `<sha>` |
| Capabilities actives | dash + air_jump + wall_run (set_capability fixtures) |
| Durée session libre | 10 min |

## Observations spontanées (verbatim)

> *(Coller ici toutes les phrases spontanées du joueur — verbatim, sans paraphrase.)*

- TBD

## Mots-clés détectés

**Positifs** (cible : ≥ 1 par session) :
- [ ] réactif / responsive / tight / snappy
- [ ] instantané / instant
- [ ] fluide
- [ ] précis / précise / contrôle
- [ ] je contrôle

**Négatifs** (cible : 0, max 1 toléré) :
- [ ] floaty / flottant
- [ ] slippery / glissant
- [ ] unresponsive / mou
- [ ] raté / stuck
- [ ] j'anticipe mes inputs
- [ ] ça répond pas tout de suite

## Score latence (post-session)

> "Sur 1-5, le mouvement répond-il instantanément à ton input ?" (ADR-0001 EC-1)

Score : __ / 5

## Verdict session

- [ ] PASS (< 20 % négatifs, score ≥ 3/5)
- [ ] CONCERNS (1 négatif détecté ou score == 3)
- [ ] FAIL (> 20 % négatifs OU verbatim anti-référence ADR-0001 EC-3)

## Trigger ADR-0001 EC-3 ?

- [ ] Aucun verbatim anti-référence détecté
- [ ] Verbatim détecté → escalade spike 120 Hz A/B blind requis

## Sign-off

| Rôle | Nom | Signature |
|------|-----|-----------|
| QA Lead | TBD | _______ |
| Creative Director (si EC-3) | — | — |
