# Protocole Playtest — VFX Feel "Court / Sec / Désaturé / Percussif" (AC-VFX-28 / AC-VFX-29)

> **Story** : vfx-system/story-008
> **Type** : Visual/Feel ADVISORY — gate ADVISORY (non-bloquant merge CI)
> **Owner** : qa-lead → sign-off creative-director + game-designer
> **Préalable** : VFX stories 001-007 Complete + smoke test pass + build MVP playable

## Objectif

Valider que le lexique spontané des testeurs converge vers **"court / sec / désaturé / percussif"**
(Pillar 2 Player Fantasy) et que les mots BANNIS liés à la Fantasy B célébration
(**"spectaculaire / satisfaisant / juteux / gore / flashy / impressionnant"**) sont absents.

Valider également que les traces de combat (decals) permettent de reconnaître visuellement
une salle déjà visitée après respawn (AC-VFX-29 Pillar 2 — mémoire physique du run).

## Setup

| Élément | Valeur |
|---------|--------|
| Build | Release MVP VFX stories 001-007 implémentées |
| Hardware | Entry-level laptop Steam Deck-tier (60 fps — VFX ≤ 50 draw calls budget) |
| Input | Clavier + souris |
| Scène | 1-2 salles combat avec 8-15 enemies (density mid-game) |
| Capture | Screencap + audio think-aloud (consentement obligatoire) |
| Accessibility | `reduce_flash` OFF + `reduce_motion` OFF (test version intensité nominale) |
| Panel | **≥ 5 testeurs** (2 expérimentés FPS + 2 casual + 1 dev pair) |
| Durée par testeur | 10 min playtest + 2-3 min interview |

**Recrutement** : testeurs aware genre FPS/parkour (Mirror's Edge / Ghostrunner / Hotline Miami)
mais **pas informés du design intent Pillar 2 / Chrome Zen avant la session** (biais Hawthorne).

## Protocole — Phase 1 : Playtest libre 7 min

1. Brief testeur AVANT lancement : *"Tu vas jouer 7 minutes dans une salle de combat. Concentre-toi
   sur les sensations visuelles. Tu peux parler à voix haute."*
2. **AUCUNE mention** de "court", "sec", "désaturé", "percussif", ni du design intent Chrome Zen.
3. Le facilitateur observe SANS donner d'instructions, note verbatim spontané (timestamp).
4. À 5 min : provoquer un respawn intentionnel (faire mourir le testeur OU demander reset),
   puis le laisser revenir dans la salle déjà combattue — observer la réaction.
5. Stop net à 7 min.

### Mesure passive (facilitateur — pendant session)

- Compter kills exécutés (cible ≥ 10 pour saturation VFX visible).
- Observer si testeur ralentit/regarde les decals au retour dans la salle après respawn.
- Noter tout verbatim spontané sur les couleurs, durée des effets, traces visuelles.

## Protocole — Phase 2 : Interview ouverte 2-3 min

**Ordre obligatoire — ne pas introduire les mots cibles avant Q4.**

1. **"Décris-moi en quelques mots ce que tu ressens quand tu tues un ennemi — les effets visuels."**
   (verbatim libre — détecte lexique spontané)

2. **"Comment décrirais-tu visuellement les effets ? Couleurs, durée, intensité…"**
   (relance sur dimensions visuelles — chercher "court", "sec", "désaturé", durée, saturation)

3. **"Quand tu es revenu(e) dans la salle après ta mort, qu'est-ce que tu as remarqué ?"**
   (verbatim libre — détecte reconnaissance salle "marquée" vs ignorée — AC-VFX-29)

4. **"Sur une échelle 1-5, à quel point les effets sont spectaculaires ?"**
   (scale inversée par rapport à notre cible — score ≤ 2 = positif pour nous)

5. **"Si tu devais comparer à un autre jeu, lequel vient à l'esprit ?"**
   (analogie — Mirror's Edge / Ghostrunner = positif ; DOOM Eternal / glory kill = red flag)

## Codage verbatim (post-session)

### Listes lexicales

**Lexique ATTENDU** (cible AC-VFX-28 — ≥ 3/4 mots présents dans ≥ 4/5 testeurs) :
- `court`
- `sec`
- `désaturé`
- `percussif`
- bonus : `propre`, `staccato`, `minimaliste`, `net`, `bref`

**Mots BANNIS** (AC-VFX-28 — 0/5 testeurs) :
- `spectaculaire`
- `satisfaisant`
- `juteux`
- `gore`
- `flashy`
- `impressionnant`
- `épique`

**Analogies POSITIVES** (bonus) : Mirror's Edge, Ghostrunner, Hotline Miami

**Analogies NÉGATIVES** (red flag) : DOOM Eternal, Shadow Warrior 3, glory kill

## Critères Pass / Fail

| AC | Seuil | Mesure |
|----|-------|--------|
| AC-VFX-28 lexique attendu | ≥ 3/4 mots dans ≥ 4/5 testeurs | Q1+Q2 verbatim spontané |
| AC-VFX-28 mots BANNIS | 0/5 testeurs sur toute session | Q1 à Q5, y compris think-aloud |
| AC-VFX-29 salle "marquée" reconnue | ≥ 4/5 testeurs décrivent salle comme marquée/parcourue | Q3 verbatim |

### Calibrage si fail

**AC-VFX-28 fail** (lexique absent OU mots bannis présents) :
- `BLOOD_SPURT_PARTICLE_COUNT` : 6 → 4
- `KATANA_TRAIL_OPACITY_MAX` : 0.7 → 0.5
- `PARTICLE_LIFETIME_MS` : 400 → 300
- Re-test 2-3 testeurs (mini-panel)

**AC-VFX-29 fail** (salle non reconnue) :
- `MAX_DECALS_PER_ROOM` : 32 → 48
- OU `DECAL_SIZE` : 0.6 → 0.8 m
- Re-test

## Evidence à produire

Fichier : `production/qa/evidence/vfx-feel-playtest-[YYYY-MM-DD].md`

```markdown
# VFX Feel Playtest — YYYY-MM-DD

## Setup
- Build : <git sha> | Panel : 5 testeurs (T1..T5, profils) | Facilitateur : <nom>

## Verbatim par testeur
### T1 — <profil>
- Q1 : "<verbatim>"  |  Q3 : "<verbatim>"  |  Q4 : score /5  |  Q5 : "<jeu cité>"

## Tableau codage
| Testeur | Mots attendus (liste) | ≥ 3/4 ? | Mots bannis | Salle "marquée" Q3 | Score Q4 |
|---------|----------------------|---------|-------------|-------------------|----------|
| T1 | | | | | |

## Verdicts
- AC-VFX-28 lexique : PASS / FAIL
- AC-VFX-28 mots bannis : PASS / FAIL
- AC-VFX-29 salle marquée : PASS / FAIL

## Sign-off
- creative-director : ___ — YYYY-MM-DD
- game-designer : ___ — YYYY-MM-DD
```

## Mots-clés détecteurs (think-aloud en session)

**Positifs** : "court", "sec", "bref", "net", "minimal", "propre", "staccato", "désaturé"

**Négatifs (red flags)** : "impressionnant", "cool", "wow", "spectaculaire", "satisfaisant",
"juteux", "trop", "flashy", "explosif", "épique"

## Source

- `production/epics/vfx-system/story-008-visual-feel-playtest-court-sec-desature.md` §AC-VFX-28/29
- Template : `production/qa/protocols/combat-feel-interview.md`
- GDD : `design/gdd/vfx-system.md` §Player Fantasy + §Acceptance Criteria r1
