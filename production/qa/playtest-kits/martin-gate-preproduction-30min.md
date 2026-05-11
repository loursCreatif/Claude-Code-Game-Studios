# Playtest Kit — Gate Pre-Production → Production
> **Qui** : Martin (solo dev, auto-validation)
> **Durée** : 30 minutes chrono
> **Objectif** : valider le vertical slice end-to-end boot → core loop
> **Gate** : Vertical Slice Validation Item 1 (`production/sprints/sprint-pre-production-2026-05-05.md`)
> **Date** : _____________ / **Build commit** : _____________

---

## Pré-requis

**Lancer le jeu**
```
godot --path . scenes/MainMenu.tscn
```
ou via l'éditeur Godot : ouvrir le projet, F5 (scène principale).

**Controls de base**

| Action | Touche |
|--------|--------|
| Se déplacer | WASD |
| Regarder | Souris |
| Sauter / double saut | Espace |
| Dash | Shift |
| Wall-run | Courir vers un mur en sautant |
| Attaque katana | Clic gauche |
| Slow-mo (premier kill) | Automatique au premier kill |
| Pause | Échap |

**Build attendue** : release, pas debug. Console overlay désactivé. 60 fps verrouillé.

---

## Phase 1 — Boot + Main Menu + New Game (0–5 min)

**Actions** : Lancer → attendre main menu → options d'accessibilité → New Game.

| # | Question | OUI | NON |
|---|----------|-----|-----|
| 1.1 | Le jeu boot sans erreur console visible et le menu s'affiche en < 5 s ? | ☐ | ☐ |
| 1.2 | Les options d'accessibilité (contraste, réduction de mouvement) sont accessibles depuis le menu principal ? | ☐ | ☐ |
| 1.3 | Cliquer "New Game" lance l'étage 1 sans freeze ni écran noir > 3 s ? | ☐ | ☐ |
| 1.4 | Le HUD (compteur crédits) est visible dès le spawn et lisible ? | ☐ | ☐ |
| 1.5 | L'esthétique menu est plate / Chrome Zen (pas de gradients, pas de coins arrondis) ? | ☐ | ☐ |

---

## Phase 2 — Traversal étage 1 + movement feel (5–10 min)

**Actions** : Explorer l'étage librement — dash, double saut, wall-run, traversal des rooms.

| # | Question | OUI | NON |
|---|----------|-----|-----|
| 2.1 | Le mouvement répond instantanément à chaque input (pas de lag perceptible) ? | ☐ | ☐ |
| 2.2 | Le dash part dans la bonne direction et le timing est net (pas floaty, pas collant) ? | ☐ | ☐ |
| 2.3 | Le wall-run s'enchaîne naturellement après un saut vers un mur sans manipulation spéciale ? | ☐ | ☐ |
| 2.4 | La caméra suit le mouvement sans nausée ni saccade visible ? | ☐ | ☐ |
| 2.5 | Les rooms de l'étage sont traversables sans bloquer (portes ≥ 3.6 m, murs wall-run ≥ 4 m) ? | ☐ | ☐ |

---

## Phase 3 — Combat + slow-mo + death/respawn (10–15 min)

**Actions** : Tuer ≥ 6 ennemis — mix dash-kill + kill statique. Mourir intentionnellement une fois.

| # | Question | OUI | NON |
|---|----------|-----|-----|
| 3.1 | Le sweep katana déclenche le hit visuellement et phoniquement au bon moment (pas de delay perceptible) ? | ☐ | ☐ |
| 3.2 | Le slow-mo au premier kill se ressent comme un élément du rythme (pas une pause célébration artificielle) ? | ☐ | ☐ |
| 3.3 | Le flash kill VFX est visible et court (< 100 ms) sans interrompre le flow ? | ☐ | ☐ |
| 3.4 | La mort se déclenche logiquement (pas de mort invisible ou aléatoire) et le respawn ramène au bon checkpoint ? | ☐ | ☐ |
| 3.5 | Après respawn, tous les systèmes sont opérationnels (mouvement, HUD, ennemis rerespawnés) ? | ☐ | ☐ |

> **Note** : Combat-019 (panel ≥ 5 testeurs × 3 sessions) reste hors scope solo —
> voir `production/qa/protocols/combat-feel-interview.md`. Cette phase couvre l'auto-validation uniquement.

---

## Phase 4 — Credit collection + HUD pulse (15–20 min)

**Actions** : Tuer 10 ennemis, collecter crédits, observer le HUD.

| # | Question | OUI | NON |
|---|----------|-----|-----|
| 4.1 | Le compteur crédits se met à jour immédiatement après chaque kill (pas de délai > 1 frame) ? | ☐ | ☐ |
| 4.2 | L'animation pulse du compteur est visible et brève (Chrome Zen — pas d'animation persistante) ? | ☐ | ☐ |
| 4.3 | Le son de crédit (clic/clac ou équivalent) joue à chaque collecte sans crachotement ni doublons ? | ☐ | ☐ |
| 4.4 | Le total affiché correspond au nombre de kills × valeur attendue (pas de désync compteur/réalité) ? | ☐ | ☐ |

---

## Phase 5 — Shop + Upgrade + Save persistence (20–25 min)

**Actions** : Accéder au shop, acheter un upgrade, quitter le jeu, relancer, vérifier l'upgrade persiste.

| # | Question | OUI | NON |
|---|----------|-----|-----|
| 5.1 | Le shop s'ouvre et affiche les upgrades disponibles avec leur coût en crédits ? | ☐ | ☐ |
| 5.2 | Acheter un upgrade déduit le bon montant de crédits et confirme l'achat sans freeze ? | ☐ | ☐ |
| 5.3 | Après quit + relaunch, les crédits et l'upgrade acheté sont bien restaurés à l'identique ? | ☐ | ☐ |
| 5.4 | L'upgrade acheté a un effet perceptible en jeu (stat différente ou capacité débloquée) ? | ☐ | ☐ |

---

## Phase 6 — Quit → Reload → Resume checkpoint (25–30 min)

**Actions** : Pause menu → Quit → Relancer → continuer depuis le dernier checkpoint.

| # | Question | OUI | NON |
|---|----------|-----|-----|
| 6.1 | Le Pause Menu s'ouvre avec Échap et le jeu se fige (time_scale = 0) ? | ☐ | ☐ |
| 6.2 | "Quit" depuis le Pause Menu retourne au Main Menu (pas un crash, pas de freeze) ? | ☐ | ☐ |
| 6.3 | "Continue" depuis le Main Menu reprend la partie au bon checkpoint (pas au début de l'étage) ? | ☐ | ☐ |
| 6.4 | Le round-trip save/load est transparent — aucun état perdu (crédits, upgrades, position) ? | ☐ | ☐ |
| 6.5 | Les 30 minutes se sont passées sans crash ni soft-lock (blocage d'état récupérable) ? | ☐ | ☐ |

---

## Critical Fun Blockers

> Si **une seule** réponse NON sur les 5 = **GATE FAIL** immédiat.
> Ces questions évaluent le pilier "FLOW AVANT TOUT" (`design/gdd/game-pillars.md`).

| # | Question | OUI | NON |
|---|----------|-----|-----|
| F.1 | Tu as envie de rejouer une deuxième partie immédiatement après ces 30 min ? | ☐ | ☐ |
| F.2 | Le mouvement + combat ensemble donnent une sensation de flow (pas de friction artificielle) ? | ☐ | ☐ |
| F.3 | L'esthétique Chrome Zen (flat, épuré) te paraît cohérente sur l'ensemble des écrans vus ? | ☐ | ☐ |
| F.4 | Tu n'as à aucun moment été bloqué par quelque chose d'incompréhensible sans possibilité de continuer ? | ☐ | ☐ |
| F.5 | Si tu devais présenter ce jeu à quelqu'un d'autre demain, tu te sentirais à l'aise de le faire tourner ? | ☐ | ☐ |

---

## ADVISORY Playtests absorbés

Ces 3 validations ADVISORY convergent dans ce playtest unique — économise 3 sessions séparées.

| Story | AC | Condition de co-validation |
|-------|----|---------------------------|
| HUD-006 (frame-perfect credit counter) | AC-HUD-28 | Phase 4 Q4.1 = OUI + Q4.4 = OUI |
| VFX-008 (flash kill court + désaturé) | AC-VFX-08 | Phase 3 Q3.3 = OUI |
| Credit-008 (Visual/Feel credit pulse) | AC-CRD-08 | Phase 4 Q4.2 = OUI |

Cocher si co-validé :
- [ ] HUD-006 PASS (co-validé Phase 4)
- [ ] VFX-008 PASS (co-validé Phase 3)
- [ ] Credit-008 PASS (co-validé Phase 4)

---

## Verdict Final

**Calcul du score phases** : compter les OUI sur les 28 questions binaires des Phases 1–6.

| Critère | Seuil | Résultat |
|---------|-------|---------|
| Fun Blockers (F.1–F.5) | 0 NON | ☐ PASS / ☐ FAIL |
| Score phases (Phases 1–6) | ≥ 23/28 (≥ 80 %) | __ / 28 — ☐ PASS / ☐ FAIL |

**Verdict global** :

| Condition | Gate |
|-----------|------|
| 0 fun blocker **ET** ≥ 23/28 OUI | **GATE PASS** — Pre-Production → Production |
| ≥ 1 fun blocker **OU** < 23/28 OUI | **GATE FAIL** — relancer `/gate-check pre-production-to-production` après fix |

---

## Sign-off

| Champ | Valeur |
|-------|--------|
| Date session | |
| Build commit | |
| Score phases | __ / 28 |
| Fun blockers | __ / 5 NON |
| HUD-006 co-validé | ☐ OUI / ☐ NON |
| VFX-008 co-validé | ☐ OUI / ☐ NON |
| Credit-008 co-validé | ☐ OUI / ☐ NON |
| **Verdict** | ☐ GATE PASS / ☐ GATE FAIL |
| Signature QA Lead | |

> **Étape suivante si PASS** : relancer `/gate-check pre-production-to-production` avec ce fichier comme evidence.
> **Référence combat panel** : `production/qa/protocols/combat-feel-interview.md` (≥ 5 testeurs × 3 sessions — hors scope solo, planifier en Production).
