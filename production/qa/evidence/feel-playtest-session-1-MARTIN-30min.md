# Feel Playtest Session 1 — Martin Gate Pre-Production → Production

> **Story Type** : Visual/Feel — gate Pre-Production → Production
> **Output Location** : `production/qa/evidence/`
> **Gate Level** : ADVISORY (qualitatif) — BLOCKING si 0 fun blocker ET ≥ 23/28 OUI non atteint
> **Kit source** : `production/qa/playtest-kits/martin-gate-preproduction-30min.md`

| Champ | Valeur |
|-------|--------|
| Date session | `<À REMPLIR — YYYY-MM-DD HH:MM>` |
| Tester | Martin (solo dev, FPS expert ~10 ans) |
| Build branch | `<À REMPLIR — ex. main / chore/story-014-tech-debt-cleanup>` |
| Build commit hash | `<À REMPLIR — ex. fc97353>` |
| Hardware | Apple M4 Mac mini — NOT Tier 1 (informational baseline) |
| Résolution / FPS cible | 1080p, 60 fps verrouillé, vsync ON |
| Durée réelle session | `<À REMPLIR>` (target 30 min — hard floor 25 min) |
| **Verdict global** | `<PASS / FAIL À REMPLIR>` (PASS = 0 fun blocker ET ≥ 23/28 OUI) |

---

## Pré-requis — checklist lancement

Cocher avant de démarrer la session :

- [ ] Build release (pas debug) — console overlay désactivé
- [ ] 60 fps verrouillé confirmé (Godot Project Settings → Display → FPS)
- [ ] `.godot/global_script_class_cache.cfg` présent (éditeur ouvert au moins une fois)
- [ ] Chronomètre prêt — noter heure début et fin de chaque phase

**Commande lancement** :
```
godot --path . scenes/MainMenu.tscn
```
ou via éditeur Godot : F5 (scène principale).

---

## Phase 1 — Boot + Main Menu + New Game (0–5 min)

**Actions** : Lancer → attendre main menu → options d'accessibilité → New Game.

**Durée réelle phase** : `<À REMPLIR — HH:MM:SS → HH:MM:SS>`

- [ ] **Q1.1** : Le jeu boot sans erreur console visible et le menu s'affiche en < 5 s ? — `<OUI / NON>`
- [ ] **Q1.2** : Les options d'accessibilité (contraste, réduction de mouvement) sont accessibles depuis le menu principal ? — `<OUI / NON>`
- [ ] **Q1.3** : Cliquer "New Game" lance l'étage 1 sans freeze ni écran noir > 3 s ? — `<OUI / NON>`
- [ ] **Q1.4** : Le HUD (compteur crédits) est visible dès le spawn et lisible ? — `<OUI / NON>`
- [ ] **Q1.5** : L'esthétique menu est plate / Chrome Zen (pas de gradients, pas de coins arrondis) ? — `<OUI / NON>`

> **Observations Phase 1** :
>
>
>

> **Fun blocker détecté Phase 1 ?** : `<oui + description / non À REMPLIR>`

---

## Phase 2 — Traversal étage 1 + movement feel (5–10 min)

**Actions** : Explorer l'étage librement — dash, double saut, wall-run, traversal des rooms.

**Durée réelle phase** : `<À REMPLIR — HH:MM:SS → HH:MM:SS>`

- [ ] **Q2.1** : Le mouvement répond instantanément à chaque input (pas de lag perceptible) ? — `<OUI / NON>`
- [ ] **Q2.2** : Le dash part dans la bonne direction et le timing est net (pas floaty, pas collant) ? — `<OUI / NON>`
- [ ] **Q2.3** : Le wall-run s'enchaîne naturellement après un saut vers un mur sans manipulation spéciale ? — `<OUI / NON>`
- [ ] **Q2.4** : La caméra suit le mouvement sans nausée ni saccade visible ? — `<OUI / NON>`
- [ ] **Q2.5** : Les rooms de l'étage sont traversables sans bloquer (portes ≥ 3.6 m, murs wall-run ≥ 4 m) ? — `<OUI / NON>`

> **Observations Phase 2** :
>
>
>

> **Fun blocker détecté Phase 2 ?** : `<oui + description / non À REMPLIR>`

---

## Phase 3 — Combat + slow-mo + death/respawn (10–15 min)

**Actions** : Tuer ≥ 6 ennemis — mix dash-kill + kill statique. Mourir intentionnellement une fois.

> **Note** : Combat-019 (panel ≥ 5 testeurs × 3 sessions) reste hors scope solo —
> voir `production/qa/protocols/combat-feel-interview.md`. Cette phase couvre l'auto-validation uniquement.

**Durée réelle phase** : `<À REMPLIR — HH:MM:SS → HH:MM:SS>`

- [ ] **Q3.1** : Le sweep katana déclenche le hit visuellement et phoniquement au bon moment (pas de delay perceptible) ? — `<OUI / NON>`
- [ ] **Q3.2** : Le slow-mo au premier kill se ressent comme un élément du rythme (pas une pause célébration artificielle) ? — `<OUI / NON>`
- [ ] **Q3.3** : Le flash kill VFX est visible et court (< 100 ms) sans interrompre le flow ? — `<OUI / NON>`
- [ ] **Q3.4** : La mort se déclenche logiquement (pas de mort invisible ou aléatoire) et le respawn ramène au bon checkpoint ? — `<OUI / NON>`
- [ ] **Q3.5** : Après respawn, tous les systèmes sont opérationnels (mouvement, HUD, ennemis rerespawnés) ? — `<OUI / NON>`

> **Observations Phase 3** :
>
>
>

> **Fun blocker détecté Phase 3 ?** : `<oui + description / non À REMPLIR>`

---

## Phase 4 — Credit collection + HUD pulse (15–20 min)

**Actions** : Tuer 10 ennemis, collecter crédits, observer le HUD.

**Durée réelle phase** : `<À REMPLIR — HH:MM:SS → HH:MM:SS>`

- [ ] **Q4.1** : Le compteur crédits se met à jour immédiatement après chaque kill (pas de délai > 1 frame) ? — `<OUI / NON>`
- [ ] **Q4.2** : L'animation pulse du compteur est visible et brève (Chrome Zen — pas d'animation persistante) ? — `<OUI / NON>`
- [ ] **Q4.3** : Le son de crédit (clic/clac ou équivalent) joue à chaque collecte sans crachotement ni doublons ? — `<OUI / NON>`
- [ ] **Q4.4** : Le total affiché correspond au nombre de kills × valeur attendue (pas de désync compteur/réalité) ? — `<OUI / NON>`

> **Observations Phase 4** :
>
>
>

> **Fun blocker détecté Phase 4 ?** : `<oui + description / non À REMPLIR>`

---

## Phase 5 — Shop + Upgrade + Save persistence (20–25 min)

**Actions** : Accéder au shop, acheter un upgrade, quitter le jeu, relancer, vérifier l'upgrade persiste.

**Durée réelle phase** : `<À REMPLIR — HH:MM:SS → HH:MM:SS>`

- [ ] **Q5.1** : Le shop s'ouvre et affiche les upgrades disponibles avec leur coût en crédits ? — `<OUI / NON>`
- [ ] **Q5.2** : Acheter un upgrade déduit le bon montant de crédits et confirme l'achat sans freeze ? — `<OUI / NON>`
- [ ] **Q5.3** : Après quit + relaunch, les crédits et l'upgrade acheté sont bien restaurés à l'identique ? — `<OUI / NON>`
- [ ] **Q5.4** : L'upgrade acheté a un effet perceptible en jeu (stat différente ou capacité débloquée) ? — `<OUI / NON>`

> **Observations Phase 5** :
>
>
>

> **Fun blocker détecté Phase 5 ?** : `<oui + description / non À REMPLIR>`

---

## Phase 6 — Quit + Reload + Resume checkpoint (25–30 min)

**Actions** : Pause menu → Quit → Relancer → continuer depuis le dernier checkpoint.

**Durée réelle phase** : `<À REMPLIR — HH:MM:SS → HH:MM:SS>`

- [ ] **Q6.1** : Le Pause Menu s'ouvre avec Échap et le jeu se fige (time_scale = 0) ? — `<OUI / NON>`
- [ ] **Q6.2** : "Quit" depuis le Pause Menu retourne au Main Menu (pas un crash, pas de freeze) ? — `<OUI / NON>`
- [ ] **Q6.3** : "Continue" depuis le Main Menu reprend la partie au bon checkpoint (pas au début de l'étage) ? — `<OUI / NON>`
- [ ] **Q6.4** : Le round-trip save/load est transparent — aucun état perdu (crédits, upgrades, position) ? — `<OUI / NON>`
- [ ] **Q6.5** : Les 30 minutes se sont passées sans crash ni soft-lock (blocage d'état récupérable) ? — `<OUI / NON>`

> **Observations Phase 6** :
>
>
>

> **Fun blocker détecté Phase 6 ?** : `<oui + description / non À REMPLIR>`

---

## Fun Blockers — Récapitulatif post-session

> Si **une seule** réponse NON = **GATE FAIL** immédiat.
> Ces questions évaluent le pilier "FLOW AVANT TOUT" (`design/gdd/game-pillars.md`).

- [ ] **F.1** : Tu as envie de rejouer une deuxième partie immédiatement après ces 30 min ? — `<OUI / NON>`
  > Trigger précis : `<À REMPLIR>`
  >
  >

- [ ] **F.2** : Le mouvement + combat ensemble donnent une sensation de flow (pas de friction artificielle) ? — `<OUI / NON>`
  > Trigger précis : `<À REMPLIR>`
  >
  >

- [ ] **F.3** : L'esthétique Chrome Zen (flat, épuré) te paraît cohérente sur l'ensemble des écrans vus ? — `<OUI / NON>`
  > Trigger précis : `<À REMPLIR>`
  >
  >

- [ ] **F.4** : Tu n'as à aucun moment été bloqué par quelque chose d'incompréhensible sans possibilité de continuer ? — `<OUI / NON>`
  > Trigger précis : `<À REMPLIR>`
  >
  >

- [ ] **F.5** : Si tu devais présenter ce jeu à quelqu'un d'autre demain, tu te sentirais à l'aise de le faire tourner ? — `<OUI / NON>`
  > Trigger précis : `<À REMPLIR>`
  >
  >

---

## ADVISORY Playtests absorbés

Ces 3 validations ADVISORY convergent dans ce playtest — économise 3 sessions séparées.

| Story | AC | Condition de co-validation |
|-------|----|---------------------------|
| HUD-006 (frame-perfect credit counter) | AC-HUD-28 | Q4.1 = OUI + Q4.4 = OUI |
| VFX-008 (flash kill court + désaturé) | AC-VFX-08 | Q3.3 = OUI |
| Credit-008 (Visual/Feel credit pulse) | AC-CRD-08 | Q4.2 = OUI |

- [ ] **HUD-006 PASS** (co-validé Phase 4 — Q4.1 + Q4.4) — `<OUI / NON>`
  > `<1 ligne verbatim : ex. "Compteur frame-perfect confirmé, aucun désync observé sur 10 kills">` 

- [ ] **VFX-008 PASS** (co-validé Phase 3 — Q3.3) — `<OUI / NON>`
  > `<1 ligne verbatim : ex. "Flash kill < 100 ms, non-intrusif, flow non interrompu">`

- [ ] **Credit-008 PASS** (co-validé Phase 4 — Q4.2) — `<OUI / NON>`
  > `<1 ligne verbatim : ex. "Pulse visible et bref, pas d'animation persistante">`

---

## Décision Gate

### Décompte score phases (Q1.1–Q6.5)

| Phase | Questions | OUI | NON |
|-------|-----------|-----|-----|
| Phase 1 — Boot + Menu | Q1.1–Q1.5 (5) | `__` | `__` |
| Phase 2 — Traversal | Q2.1–Q2.5 (5) | `__` | `__` |
| Phase 3 — Combat | Q3.1–Q3.5 (5) | `__` | `__` |
| Phase 4 — Credits + HUD | Q4.1–Q4.4 (4) | `__` | `__` |
| Phase 5 — Shop + Save | Q5.1–Q5.4 (4) | `__` | `__` |
| Phase 6 — Quit + Resume | Q6.1–Q6.5 (5) | `__` | `__` |
| **TOTAL** | **28** | **`__ / 28`** | **`__`** |

### Décompte fun blockers (F.1–F.5)

| Critère | NON détectés |
|---------|-------------|
| Fun Blockers (F.1–F.5) | `__ / 5` |

### Verdict mécanique

| Critère | Seuil | Résultat |
|---------|-------|---------|
| Fun Blockers | 0 NON | ☐ PASS / ☐ FAIL |
| Score phases | ≥ 23/28 (≥ 80 %) | `__ / 28` — ☐ PASS / ☐ FAIL |

**Verdict global** : ☐ **GATE PASS** — Pre-Production → Production / ☐ **GATE FAIL**

> GATE PASS = 0 fun blocker ET ≥ 23/28 OUI — les deux conditions sont obligatoires.

**Action post-session** : `<À REMPLIR — ex. "Re-run /gate-check pre-production-to-production avec ce fichier comme evidence" ou "Fix [bug identifié] puis re-playtest">`

---

## Sign-off

| Champ | Valeur |
|-------|--------|
| Date session | `<À REMPLIR>` |
| Build commit | `<À REMPLIR>` |
| Score phases | `__ / 28` |
| Fun blockers NON | `__ / 5` |
| HUD-006 co-validé | ☐ OUI / ☐ NON |
| VFX-008 co-validé | ☐ OUI / ☐ NON |
| Credit-008 co-validé | ☐ OUI / ☐ NON |
| **Verdict** | ☐ GATE PASS / ☐ GATE FAIL |
| Signature QA Lead | `<À REMPLIR>` |

---

## References

- Kit source : `production/qa/playtest-kits/martin-gate-preproduction-30min.md`
- Ce fichier evidence : `production/qa/evidence/feel-playtest-session-1-MARTIN-30min.md`
- Gate-check précédent : `production/qa/evidence/feel-playtest-session-1-2026-04-27.md` (TEMPLATE vide — TD-014 P0)
- Gate-check cible : `/gate-check pre-production-to-production`
- Protocole combat panel (hors scope solo) : `production/qa/protocols/combat-feel-interview.md`
