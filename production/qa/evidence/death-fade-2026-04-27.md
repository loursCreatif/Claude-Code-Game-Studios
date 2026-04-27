# AC-MV-101 — Death fade rouge evidence

> **Story** : player-movement-system / story-017
> **AC** : AC-MV-101
> **Date** : DEFERRED — capture non encore réalisée
> **Statut** : **TEMPLATE / PENDING** — à compléter dès que la VFX/UI epic livre le fade rouge implémenté

## Procédure de capture

1. Build release MVP
2. Player Grounded à `(0, 1, 0)`
3. `player.set_checkpoint(Vector3.ZERO)` (pour respawn déterministe)
4. Appeler `player.die()` (depuis console debug ou trigger fixture)
5. Au tick 2 (≈ RESPAWN_DELAY/2 = 25 ms), capture screenshot

## Évidence attendue

- **Fichier image** : `death-fade-2026-04-27.png` (à créer dans le même dossier)
- **Fondu rouge** : plein écran, durée ≤ 40 ms, alpha visible et lisible
- **Lisibilité cause mort** : suffisamment opaque pour signaler clairement la mort
  sans masquer l'environnement (Pillar 4 readability)

## Variant accessibilité

- **`reduce_flash = true`** : `death-fade-reduce-flash-2026-04-27.png`
  - Fondu remplacé par assombrissement gris neutre, durée 80-120 ms
  - Pas de pic de luminance / pas de rouge saturé

## Verdict

- [ ] PASS — fade rouge < 40 ms + variant reduce_flash conforme
- [ ] CONCERNS — fade correct mais durée hors fenêtre
- [ ] FAIL — pas de fade visible OU dépasse 60 ms
- [ ] BLOCKED — VFX/UI epic n'a pas encore livré le fade rouge implémenté

## Dépendances

- **VFX** ou **UI** epic — ColorRect plein écran avec Tween alpha
- **Accessibility** layer (story-018 BLOCKED ADR-0015) — toggle `reduce_flash`

## Sign-off

| Rôle | Nom | Signature |
|------|-----|-----------|
| QA Lead | TBD | _______ |
| Accessibility Specialist (si reduce_flash) | TBD | _______ |
