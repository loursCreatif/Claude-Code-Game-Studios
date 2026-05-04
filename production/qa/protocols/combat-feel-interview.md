# Protocole Playtest — Combat Feel Interview (Pillar 2 / Fantasy A in-flow rythmique)

> **Story** : combat-system / story-019
> **ADR** : aucun (relève du Player Fantasy + design feel)
> **GDD** : design/gdd/player-combat-system.md (AC-CMB-31/32/33/34 + r6 REC-01/REC-02)
> **Owner** : qa-lead
> **Préalable** : Combat stories 001-018 implémentées + suite automatisée verte (tests/unit/combat + tests/integration/combat)
> **Gap résolu** : Gap 5 — protocole entretien playtest reproductible (cf. `production/epics/combat-system/story-019-combat-feel-playtest-protocol.md`)

## Objectif

Valider **qualitativement** que le feel Combat (katana sweep + slow-mo 50 ms premier kill + multi-kill rangs) appartient à la **Fantasy A "in-flow rythmique"** et **pas** à la Fantasy B "récompense isolée". Le slow-mo doit être perçu comme un **élément du rythme de jeu** — pas comme une pause célébration.

Évidence requise pour fermer AC-CMB-31/32/33/34 (Visual/Feel ADVISORY) côté combat-system epic et **avancer le project stage** vers Polish/Pre-Release.

## Setup

| Élément | Valeur |
|---------|--------|
| Build | Release MVP (pas debug, pas console overlay) |
| Hardware | Entry-level laptop (cible Steam — 60 fps locked) |
| Input | Clavier + souris (gamepad hors scope MVP) |
| Capabilities | toutes actives (Movement complet, Combat sweep, slow-mo activé) |
| Scène | étage MVP avec ≥ 6 ennemis (Grunt) répartis pour permettre kills en mouvement ET hors-mouvement |
| Durée par session | 5 minutes jeu (≥ 10 kills attendus, mix dash-kill + plateforme statique-kill) + 10-15 min entretien debrief |
| Panel | **≥ 5 testeurs** (cohérent AC-CMB-31/32 ≥ 80% accord, AC-CMB-34 ≥ 70% testeurs) |
| Sessions | **3 sessions panel ≥ 5** distinctes (AC-CMB-32) — dates différentes ; testeurs naïfs (pas habituas du build, ne lisent pas le GDD) |
| Capture | enregistrement audio entretien (consent obligatoire) + notes verbatim horodatées par facilitateur |

## Protocole — Phase 1 : Session libre 5 min

1. Briefer testeur AVANT lancement : *"Tu vas jouer 5 minutes. Explore librement, tue les ennemis, déplace-toi, essaie tout. Tu pourras me dire ce que tu en as pensé ensuite. Aucune bonne ou mauvaise façon de jouer."*
2. **AUCUNE consigne sur le slow-mo, sur le dash, sur les "mots à dire"**. Le facilitateur observe SANS donner d'instructions, note verbatim chaque commentaire spontané du joueur (timestamp seconde près).
3. À 5 min stop net.

### Mesure passive (facilitateur — pendant session)

- Compter le nombre de kills exécutés (cible ≥ 10 — sinon session invalide, rejouer).
- Noter combien de kills en mouvement (dash / wall-run / sprint) vs hors-mouvement (plateforme statique).
- Capturer ≥ 1 séquence dash-kill ET ≥ 1 séquence kill-statique pour réutilisation Phase 2.

## Protocole — Phase 2 : Entretien debrief 10-15 min

15 questions ouvertes structurées en 5 axes. **Ordre obligatoire** (le débrief s'ouvre sur le générique, se resserre sur le slow-mo en fin) — biaiser l'ordre pose des questions sur slow-mo trop tôt, ce qui pollue le verbatim AC-CMB-31.

### Axe 1 — Description spontanée générale (AC-CMB-31)

1. **"Décris-moi ce que tu viens de jouer en 30 secondes, comme si tu en parlais à un pote."** (verbatim libre)
2. **"Comment tu décrirais le combat ? Le rythme, la sensation… qu'est-ce qui te vient ?"** (relance ouverte sur le feel)
3. **"Si tu devais comparer ce combat à un autre jeu ou à une activité, ce serait quoi ?"** (analogie — détecte mots bannis non-rythmiques)

### Axe 2 — Kill en mouvement vs kill statique (AC-CMB-32 + AC-CMB-33)

4. **"Tu te souviens d'un moment où tu as tué un ennemi en bougeant ? Raconte-le."** (verbatim — chercher contexte mouvement implicite : "j'ai traversé en même temps", "ça s'est enchaîné avec mon dash")
5. **"Et un moment où tu étais arrêté(e) sur une plateforme et tu as tué un ennemi ?"** (verbatim — chercher mots vide-ou-manque)
6. **"Entre ces deux types de kill, lequel te paraît le plus… intéressant ? Pourquoi ?"** (relance comparative — laisse émerger le contraste rythmique vs statique)

### Axe 3 — Slow-mo perception (AC-CMB-34 — r6 REC-02)

7. **"Tu as remarqué quelque chose de particulier sur le timing des kills ? Le rythme ?"** (relance neutre — ne pas dire "slow-motion")
8. **"Si je te dis 'ralenti', ça t'évoque quelque chose dans ce que tu as joué ?"** (introduit le mot — verbatim sur perception)
9. **"Le ralenti, tu l'as ressenti comme quoi ? Une pause, un effet, autre chose ?"** (relance ouverte ; chercher si testeur évoque "rythme" vs "pause")

### Axe 4 — Échelle Likert (AC-CMB-34 BLOCKING)

Présenter l'item r6 REC-02 EXACTEMENT formulé :

10. **Item Likert** : *"Le ralenti m'a semblé faire partie du rythme de jeu, pas une pause séparée."* — Échelle 5 points :
    - 1 = Pas du tout d'accord
    - 2 = Plutôt pas d'accord
    - 3 = Ni d'accord ni pas d'accord
    - 4 = Plutôt d'accord
    - 5 = Tout à fait d'accord

11. **"Pourquoi tu mets [valeur] ? Qu'est-ce qui te fait dire ça ?"** (justification verbatim — informe régression future si score baisse)

### Axe 5 — Open-ended fin (verbatim libre)

12. **"S'il y avait un mot pour résumer le rythme du combat, ce serait quoi ?"** (mot unique — détecte ratio in-flow vs out-of-flow vs banni)
13. **"Quelque chose que tu changerais ? Quelque chose qui t'a manqué ?"** (relance frustrations — détecte mots vide-ou-manque sur kill statique)
14. **"Quelque chose qui t'a surpris (positivement OU négativement) ?"** (verbatim libre)
15. **"Tu remettrais une session ? Pourquoi ?"** (replay intent — corrélation feel ≠ pass condition formelle, info qualitative pour creative-director)

## Codage verbatim (post-session, par facilitateur ou intervieweur 2e passe)

### Listes lexicales canoniques

**Vocabulaire IN-FLOW rythmique** (cible AC-CMB-31 — testeur doit utiliser ≥ 2 distincts spontanément) :

- `beat`
- `tempo`
- `staccato`
- `traverser`
- `enchaîner`
- `cadence`

**Vocabulaire VIDE-OU-MANQUE hors-flow** (cible AC-CMB-33 sur kill statique — testeur doit utiliser ≥ 1 spontanément) :

- `plat`
- `vide`
- `sans intérêt`
- `basique`
- `ça passe`
- `mécanique`
- `bof`
- `ok quoi`

**MOTS BANNIS** (cible AC-CMB-31 BLOCKING — AUCUN verbatim ne doit en contenir, signal Fantasy B intrusion) :

- `combo`
- `finisher`
- `engagement`
- `affrontement`
- `satisfaisant`
- `récompense`
- `impressionnant`

### Procédure codage

1. Relire verbatim de chaque testeur (transcription audio + notes facilitateur).
2. Pour chaque session, compter par testeur :
   - Nombre de **descripteurs IN-FLOW distincts** utilisés spontanément (avant Q7-Q9 sur slow-mo — sinon biais introduit par questions).
   - Présence d'**au moins 1 mot VIDE-OU-MANQUE** dans réponse Q5 (kill statique) ou Q13 (frustrations).
   - Présence d'**au moins 1 MOT BANNI** anywhere dans la session (instant-fail AC-CMB-31).
3. Pour chaque kill décrit Q4 (kill en mouvement) : noter si la description évoque un **contexte mouvement** ("en traversant", "pendant que je dashais", "ça s'est enchaîné") ou un **événement isolé** ("je l'ai tué", "j'ai cliqué dessus").
4. Compiler échelle Likert Q10 par testeur — calculer médiane panel + % testeurs ≥ 4.

## Critères Pass / Fail quantifiés

### AC-CMB-31 — Vocabulaire rythmique spontané (BLOCKING ADVISORY playtest signoff)

| Métrique | Seuil pass | Mesure |
|----------|-----------|--------|
| Descripteurs IN-FLOW distincts par testeur | **≥ 4** sur la session | Compte unique mots IN-FLOW Q1-Q6 + Q12 |
| Testeurs utilisant spontanément **≥ 2** descripteurs distincts | **≥ 80%** du panel (≥ 4/5) | Q1-Q6 + Q12, Q13, Q14 — avant Q7 sur slow-mo |
| Mots bannis dans verbatim | **0** sur l'ensemble du panel | Tout verbatim, toute question — instant-fail |

### AC-CMB-32 — Kill en mouvement décrit en contexte mouvement (BLOCKING ADVISORY)

| Métrique | Seuil pass | Mesure |
|----------|-----------|--------|
| Testeurs décrivant kill-en-mouvement comme **contexte mouvement** (pas événement isolé) | **≥ 80%** du panel (≥ 4/5) | Q4 verbatim — phrasé "en traversant", "pendant que", "ça s'est enchaîné" vs "je l'ai tué" |
| Sessions panel répétées | **3 sessions** distinctes ≥ 80% accord chacune | 3 dates différentes, panel ≥ 5 chacun |

### AC-CMB-33 — Kill hors-mouvement utilise mot vide-ou-manque (BLOCKING ADVISORY)

| Métrique | Seuil pass | Mesure |
|----------|-----------|--------|
| Testeurs utilisant spontanément ≥ 1 mot VIDE-OU-MANQUE en Q5 ou Q13 | **≥ 80%** du panel | Q5 (kill statique) ou Q13 (frustrations) — verbatim spontané, pas relancé |
| Comparaison verbatim in-flow Q4 vs out-of-flow Q5 | **Asymétrie qualitative claire** documentée | Codage croisé Q4/Q5 par intervieweur |

### AC-CMB-34 — Likert slow-mo perçu comme rythme (BLOCKING ADVISORY)

| Métrique | Seuil pass | Mesure |
|----------|-----------|--------|
| Testeurs Likert Q10 **≥ 4/5** | **≥ 70%** du panel (≥ 4/5 sur panel 5) | Q10 — item r6 REC-02 EXACTEMENT formulé |
| Médiane panel Q10 | **≥ 4** | Médiane intra-session, panel ≥ 5 |

## Evidence livrée

Chaque session produit un fichier `production/qa/evidence/combat-feel-playtest-[YYYY-MM-DD]-session-N.md` (N=1, 2, 3) contenant :

```markdown
# Combat Feel Playtest — Session N — YYYY-MM-DD

## Setup
- Build commit SHA : <git rev-parse HEAD>
- Panel : 5 testeurs (T1..T5), profils : <âge / familier FPS oui/non / habitué games rythmiques oui/non>
- Facilitateur : <nom>
- Durée totale : <minutes>

## Verbatim par testeur

### T1 — <profil court>
- Q1 : "<verbatim>"
- Q2 : "<verbatim>"
- ...
- Q10 Likert : <1-5> — justification Q11 : "<verbatim>"

### T2 — ...

## Codage

| Testeur | IN-FLOW distincts | ≥ 2 IN-FLOW spontanés | Mots bannis | Q4 contexte mouvement | Q5 mot vide-ou-manque | Likert Q10 |
|---------|-------------------|----------------------|-------------|-----------------------|-----------------------|------------|
| T1 | 4 | OUI | 0 | OUI | OUI | 5 |
| ... | | | | | | |

## Verdicts par AC (cf. seuils protocole)
- AC-CMB-31 : PASS / FAIL — détail
- AC-CMB-32 : PASS / FAIL — détail
- AC-CMB-33 : PASS / FAIL — détail
- AC-CMB-34 : PASS / FAIL — détail (médiane = X, % ≥ 4 = Y%)

## Sign-off
- qa-lead : <nom> — <date>
- creative-director : <nom> — <date> (audit verbatim Fantasy A vs B)
```

3 sessions PASS sur les 4 ACs = AC-CMB-31/32/33/34 fermés. Cross-référence story-019 fermeture.

## Anti-références (red flags)

Si une session révèle :

- ≥ 2 testeurs utilisant **mots bannis** (`combo`, `finisher`, `engagement`, etc.) → **trigger creative-director audit Fantasy A vs Fantasy B drift**. Possible regression slow-mo durée (50 ms trop visible) ou multi-kill rangs (signaling B trop saillant).
- Médiane Likert Q10 ≤ 3 → **trigger systems-designer review SLOW_MO_DURATION_MS / SLOW_MO_SCALE**. Possible déphasage (50 ms trop court → invisible, ou trop long → pause).
- ≥ 80% testeurs utilisent IN-FLOW dans Q5 (kill statique) AUSSI → contraste in-flow/out-of-flow effacé (Combat trop "satisfaisant" intrinsèquement, casse le pattern Fantasy A "le rythme vient du mouvement"). Trigger systems-designer.

## Caveats / Limites

- **Effort estimé** : 3 sessions × (5 min jeu + 15 min entretien + 30 min codage) × 5 testeurs = ~5h coordination + ~2h codage post. Bloque sur **Martin recrute panel ≥ 5 testeurs naïfs** (panneau pas constitué au 2026-05-04 — coordination Martin requise pour passer ce gate).
- **Ne remplace PAS un test automatisé** : AC-CMB-31/32/33/34 sont **Visual/Feel ADVISORY** par design (Pillar 2 humain qualitatif — cf. `.claude/docs/coding-standards.md` Test Standards Visual/Feel category). Ce protocole produit l'evidence requise par le gate avancement project stage Polish.
- **Re-run nécessaire si Combat slow-mo modifié** : tout changement `SLOW_MO_DURATION_MS`, `SLOW_MO_SCALE`, `MAX_KILLS_PER_SWING`, ou compositional changes au sweep timing invalide les sessions précédentes — re-runner les 3 sessions.
- **Single-language** : les listes lexicales sont **francophones** (testeurs francophones natifs). Pour ship multi-langue, dupliquer ce protocole avec listes traduites + revalider Pillar 2 par marché.

## Source

- Story : `production/epics/combat-system/story-019-combat-feel-playtest-protocol.md` Gap 5
- GDD : `design/gdd/player-combat-system.md` AC-CMB-31/32/33/34 + r6 REC-01 (mots bannis) + REC-02 (item Likert)
- Pattern hérité : `production/qa/playtest-protocols/feel-movement-session.md` (story-017 Pillar 1)
- Pillar 2 défini : `design/game-concept.md` (Fantasy A in-flow rythmique vs Fantasy B récompense isolée)
