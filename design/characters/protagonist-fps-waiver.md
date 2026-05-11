# Waiver — Character Design Doc Protagoniste (Artefact #4 Gate Pre-Production → Production)

**Statut** : ✅ WAIVER ACCEPTED  
**Gate** : Pre-Production → Production  
**Date** : 2026-05-11  
**Réf. gate-check** : `production/gate-checks/2026-05-05-pre-production-to-production.md` — Artefact #4 "Character visual profiles"  
**Scope** : Protagoniste uniquement (les ennemis ont leurs GDD et visual budgets dans `design/gdd/enemy-system.md`)

---

## Décision

Aucun character sheet 3D ni profil visuel externe pour le protagoniste au MVP.

L'identité du personnage est définie par trois vecteurs POV-only :
1. Les mains + la lame visible en vue première personne (combat GDD)
2. Le son : footsteps positionnels, swoosh de swing, clac kill
3. Le mouvement : dash, wall-run, wall-jump (movement GDD) — le corps *est* le verbe

---

## Rationale

### FPS POV = anti-pattern character externe par design

CHROME://ASCENT est un FPS à la première personne strict. La caméra ne quitte jamais
le point de vue du protagoniste (voir `design/gdd/camera-system.md` — "le joueur est
derrière elle [...] il l'oublie"). Dans ce contexte, un character sheet traditionnel
(silhouette, palette couleurs, fiche identité visuelle externe) servirait exclusivement
des cinématiques ou un mode third-person — deux éléments absents du MVP et
explicitement hors-scope (Anti-Pillar : "NOT un jeu à narration interruptive", game-concept.md).

### Cohérence avec Pillar 1 — FLOW AVANT TOUT

Un character sheet imposerait une silhouette, une couleur de tenue, des marqueurs
visuels externes que le joueur ne verra jamais pendant le jeu. Documenter ces éléments
sans implémentation visible violerait l'esprit du Pillar 1 ("zéro animation qui gêne
l'enchaînement") : prioriser une spec cosmétique non-implémentable sur le feel immédiat
est une dette de design, pas un livrable.

### Cohérence narrative — protagoniste comme extension du joueur

La core fantasy ("tu es une lame cybernétique", game-concept.md §Core Fantasy) repose
sur l'effacement volontaire du protagoniste en tant qu'entité externe. Le joueur
n'*observe* pas le protagoniste — il *est* le protagoniste. Définir une identité visuelle
externe forte (couleur capillaire, tenue, cicatrices) contredirait cette intention en
produisant un personnage que le joueur "joue" plutôt qu'un corps qu'il *habite*.

La narration environnementale ("posters, terminaux, aucun dialogue in-flow",
game-concept.md §MDA Narrative priority 7) confirme ce choix : le protagoniste n'existe
pas dans les décors, il les traverse.

---

## Identité POV en MVP

Ce waiver ne signifie pas "zéro identité protagoniste" — cela signifie que l'identité
est définie par les assets directement visibles et audibles en POV.

**Ce qui constitue l'identité visuelle du protagoniste au MVP :**

- **La lame** : le katana visible dans le champ de vue (référence `design/gdd/player-combat-system.md`
  — hitbox ShapeCast3D + animation swing). La lame *est* la signature visuelle. Chrome poli,
  géométrie simple cohérente Chrome Zen (art-bible flat shaders).
- **Les mains** : présence implicite — pas de modèle de bras animé détaillé requis au MVP.
  La lame suffit à l'ancrage POV. Les mains complètes (avec sleeve, cyberware visible)
  sont un livrable Tier 2 (voir §Réversibilité).
- **Le crosshair** : ancré à la caméra (`design/gdd/camera-system.md` — "HUD ancre son
  crosshair à la caméra"). Minimaliste, Chrome Zen — pas un indicateur de personnage,
  mais un outil neutre.

**Ce qui N'EST PAS requis au MVP :**

- Silhouette 3D du protagoniste
- Palette couleurs externe (tenue, coiffure, peau)
- Fiche identité narrative (nom, backstory textuelle, arc)
- Portrait ou concept art de personnage

---

## Identité sonore (Sound Identity)

Le son constitue la couche d'identité la plus dense du protagoniste en FPS.

- **Footsteps** : référencés dans `design/gdd/audio-system.md` (pool `AudioStreamPlayer3D`,
  mention footsteps ennemis Tier 2 + environmental SFX). Les footsteps joueur sont
  implicites au MVP via le système 3D positional. Priorité Tier 2 : footsteps joueur
  distincts par surface (metal, béton, verre).
- **Swoosh de swing** : défini dans `design/gdd/audio-system.md` Rules (swoosh fade
  wall-clock 30 ms, bus `SFX`). C'est la signature cinétique du protagoniste — le son
  du geste avant l'impact.
- **Clac kill** : `design/gdd/audio-system.md` Rule 11 + combat GDD. Son sec, 0-transient,
  suivi d'un silence rythmique post-clac (Couche 1). Ce silence *est* la ponctuation du
  protagoniste.
- **Grunt / vocalisations** : hors-scope MVP. Anti-Pillar "NOT un jeu à narration
  interruptive" — une vocalisation joueur pendant le combat introduit une identité
  narrative non voulue. Reevaluation Tier 3 uniquement si playtests révèlent un manque
  d'ancrage corporel.

---

## Réversibilité

Ce waiver est valable pour le MVP (Tier 1) uniquement.

**Conditions de révocation automatique :**

- Ajout d'un mode third-person (même optionnel) → character sheet 3D requis immédiatement
- Ajout de cinématiques ou de cutscenes (même courtes, < 5 s) → silhouette + palette requis
- Ajout d'un écran de sélection de personnage ou d'une option de customisation visuelle
- Introduction d'un nom propre du protagoniste dans les textes in-game (HUD, terminaux)

**Livrables Tier 2 associés (non-bloquants MVP) :**

- Modèle de bras complet avec sleeve cyberpunk + cyberware visible (main gauche vide,
  main droite hilt katana)
- Palette couleurs bras/sleeve alignée art-bible Chrome Zen (flat, métal brossé, accent
  néon froid)
- Footsteps joueur distincts par surface

**En Tier 3 (Full Vision)** : si un mode New Game+ introduit une identité narrative
renforcée (nom, voix off, arc rétrospectif), un character document complet est requis
en amont de ce sprint.

---

## Acceptance Criteria du Waiver

Trois critères binaires à valider avant la clôture du gate Production :

| # | Critère | Valide si |
|---|---------|-----------|
| AC-WAI-PROT-1 | La lame du katana est visible et identifiable en POV lors d'un swing | Screenshot ou playtest session confirme la présence de la géométrie katana dans le champ caméra |
| AC-WAI-PROT-2 | Le swoosh + clac kill sont audibles et distincts sans vocalisation joueur | Playtest session confirme : aucun grunt/voix, swoosh + silence post-clac perceptibles |
| AC-WAI-PROT-3 | Aucune mention du nom propre du protagoniste dans les assets in-game MVP | Grep sur `src/` + `assets/` + `scenes/` : zéro string hardcodée avec nom propre de personnage |

---

## References

- `design/gdd/game-concept.md` — Pillar 1 FLOW AVANT TOUT, Anti-Pillar narration interruptive, Core Fantasy "tu es une lame cybernétique", MDA Narrative priority 7
- `design/gdd/camera-system.md` — décision FPS strict, "le joueur est derrière elle [...] il l'oublie", zéro mode third-person MVP
- `design/gdd/player-combat-system.md` — "le kill est le silence entre deux notes de mouvement", katana POV, hitbox ShapeCast3D
- `design/gdd/player-movement-system.md` — verbes mouvement (dash, wall-run, wall-jump) comme expression corporelle du protagoniste
- `design/gdd/audio-system.md` — swoosh Rule, clac kill + silence rythmique Couche 1, footsteps (Tier 2), grunt hors-scope MVP
- `production/gate-checks/2026-05-05-pre-production-to-production.md` — Artefact #4 "Character visual profiles — possible waiver"
