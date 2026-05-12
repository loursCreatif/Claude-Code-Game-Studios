# UX Spec — HUD

> **Statut** : WAIVER REDIRECT · Gate Pre-Production → Production · 2026-05-11
> **Artefact** : #13 (gate-check 2026-05-05) + Quality Check #2
> **Scope** : Gameplay HUD MVP uniquement (hors menus, hors screens de résultat)

---

## Décision

`design/gdd/hud-system.md` est la source canonique UX et gameplay du HUD. Ce document est un
pointeur de cohérence pour le gate-check : il synthétise les décisions UX structurelles sans les
dupliquer. Toute modification comportementale doit passer par le GDD, pas par ce fichier.

---

## Scope UX MVP — 5 éléments

Le HUD CHROME://ASCENT ne contient **exactement** que ces éléments au MVP :

- **Credits counter** — label monospace, ancré top-right (24 px bord droit, 20 px bord haut, post-SafeArea). Toujours visible en `PLAYING` et `RESPAWNING`.
- **Pulse scale KILL** — tween `Label.scale` → 1.05 → 1.0, 100 ms, easing `EASE_IN_OUT TRANS_SINE`. Déclenché sur `credits_changed(delta > 0, SourceKind.KILL)`.
- **Pulse scale SECRET** — identique, durée 150 ms (+50 %). Signal visuel que "c'était un riff, pas un battement" (GDD r1.1 NB-CRD-6 Option A).
- **Low-credits warning** — comportement défini dans GDD §Tuning Knobs (`LOW_CREDITS_THRESHOLD`). Pas de couleur seule comme unique signal (voir §Accessibility).
- **Game over fade** — propriété du GSM / Camera / VFX ; HUD caché instantanément dès `PAUSED` ou `BOSS_DEFEATED` (table de visibilité GDD Rule 8).

**Exclusions explicites MVP** : health bar, ammo, minimap, compass, damage numbers, floating "+N", combo counter, objective marker, death screen. Chacun viole un anti-pillar game-concept.

---

## Hiérarchie visuelle

Pillar 1 (FLOW AVANT TOUT) impose qu'un seul élément reçoive l'attention du joueur à la fois.
Ordre de priorité descendant :

1. Centre écran — action gameplay (katana, dash, ennemi)
2. Périphérie — credits counter (rôle "odomètre silencieux")
3. Jamais — tout élément qui force un saccade vers l'UI pendant un combat

Le counter est ancré **top-right** précisément parce que le regard du FPS reste centré-bas
(suivi de la cible). Le coin supérieur droit entre dans le champ périphérique sans compétition.

---

## Information density

Chrome Zen K.2 (game-pillars.md) : ≤ 3 éléments UI visibles simultanément.

| État GSM | Éléments HUD visibles | Respect K.2 |
|---|---|---|
| `PLAYING` combat actif | credits counter (1) | ✅ |
| `PLAYING` low-credits | counter + warning signal (2) | ✅ |
| `PLAYING` pulse actif | counter en animation (1 — pas un second élément) | ✅ |
| `RESPAWNING` | counter visible, freeze si pulse en cours (1) | ✅ |
| `PAUSED` / `MENU` | HUD masqué (0) | ✅ |

Un pulse en cours ne compte pas comme élément additionnel — il anime l'existant.

---

## Accessibility

Conformité WCAG 2.1 AA obligatoire sur tous les éléments HUD MVP :

- **Taille texte** : credits counter ≥ 24 px rendu à 1080p, scalable via `UI_SCALE_FACTOR` (GDD Tuning Knob). À 720p, floor à 20 px minimum.
- **Contraste** : blanc froid sur fond jeu sombre — ratio cible ≥ 4.5:1 (AA). Art-director valide la palette Chrome Zen ; la teinte retenue ne peut pas tomber sous 3.0:1 (AA large text) sur aucun fond de niveau.
- **Couleur non exclusive** : le low-credits warning ne peut pas reposer sur la couleur seule. Signal combiné requis : changement de typographie (bold / italic) OU clignotement OU icône — au choix de l'art-director, mais le signal doit rester lisible en mode deutéranopie (green-blind) et protanopie (red-blind). Colorblind mode non implémenté MVP mais la palette de base doit y survivre sans patch.
- **Sous-titres** : HUD gameplay ne produit aucune voix-off. Sans objet.
- **Input** : HUD est read-only, aucune interaction directe. Pas de focus keyboard/gamepad requis.

---

## Reduce-motion

ADR-0015 D-1 Option A définit le comportement VFX global. Extension au HUD :

- En mode reduce-motion activé (`AccessibilitySystem.reduce_motion == true`) : les tweens `Label.scale` (KILL et SECRET) sont remplacés par un **hard set** immédiat (`Label.text = str(total)` sans animation de scale). Le signal de mise à jour reste frame-perfect (Pillar 1 FLOW inchangé).
- Le time_scale GSM (slow-mo combat) n'affecte pas les durées de tween HUD : le tween respecte `time_scale` via le Tween standard Godot, ce qui signifie qu'en slow-mo (Combat GDD `time_scale = 0.3`), le pulse HUD dure visuellement plus longtemps en wall-clock — comportement intentionnel (le joueur perçoit l'effet dans la même temporalité dilatée que le combat).
- La low-credits warning ne produit pas de flash répétitif (< 3 Hz, pas de risque photosensibilité). Si le design évolue vers un clignotement, fréquence ≤ 3 Hz obligatoire + warning écran.

---

## Contraintes d'implémentation (pour ui-programmer)

Ces contraintes découlent des rules UX et du lint statique — elles ne sont pas négociables au MVP :

- `CanvasLayer.layer` : valeur cible `50` (layer < 100 strict — GSM owns 100). Voir `.claude/rules/hud-anti-patterns.md` AC-HUD-LINT-7.
- Zéro référence à `AudioSystem`, `CombatSystem`, `LevelSystem`, `InputManager`, `SaveLoad` depuis `src/gameplay/hud/`. Voir lint AC-HUD-LINT-1/2/3.
- Zéro gradient, corner_radius > 0, AnimationPlayer, ShaderMaterial. Chrome Zen hard-edge (AC-HUD-LINT-4/5/6).
- Pattern outbound-only partagé avec Audio System (ADR-0009 D-2) : HUD consomme `CreditEconomy` et `GameStateManager` uniquement, n'émet aucun signal aval.

---

## Playtest en attente (story hud-006 — ADVISORY)

La story `hud-system/story-006` est BLOCKED ADVISORY (Visual/Feel gate non-bloquant CI).
Elle requiert une session playtest manuelle avant clôture :

- Protocole : `production/qa/protocols/hud-006-credit-008-frame-perfect-playtest.md`
- Evidence cible : `production/qa/evidence/hud-frame-perfect-evidence-[DATE].md`
- AC à valider : AC-HUD-23 (frame-perfect ≤ 1 frame), AC-HUD-30 (resize stable), AC-CRD-46 (convergence credit-008)

Cette story ne bloque pas le gate Pre-Production → Production (ADVISORY). Elle doit être résolue avant la fin du Sprint Production 1.

---

## Références

| Source | Rôle |
|---|---|
| [`design/gdd/hud-system.md`](../gdd/hud-system.md) | Source canonique — 8 sections GDD, Detailed Rules, Formulas, AC-HUD-* |
| [`design/gdd/game-concept.md`](../gdd/game-concept.md) | Pillar 1 FLOW (latency < 1 frame), Pillar 2 (la progression se voit) |
| [`design/gdd/game-pillars.md`](../gdd/game-pillars.md) | Chrome Zen K.2 (density ≤ 3), K.5 (hard-edge), K.7 (no animation) |
| [`docs/architecture/adr-0009-audio-system.md`](../../docs/architecture/adr-0009-audio-system.md) | D-2 pattern pool exclusive partagé (HUD = consumer outbound-only) |
| [`.claude/rules/hud-anti-patterns.md`](../../.claude/rules/hud-anti-patterns.md) | Lint statique enforced CI — AC-HUD-LINT-1 à 7 |
| [`production/qa/protocols/hud-006-credit-008-frame-perfect-playtest.md`](../../production/qa/protocols/hud-006-credit-008-frame-perfect-playtest.md) | Protocole playtest manuel (5 scénarios, AC-HUD-23/30/AC-CRD-46) |
