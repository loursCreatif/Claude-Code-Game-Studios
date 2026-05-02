# Game Concept: CHROME://ASCENT

*Created: 2026-04-21*
*Status: Draft*

---

## Elevator Pitch

> Un action/platformer cyberpunk à la première personne où tu grimpes une tour Arasaka-like, katana à la main, en tranchant des ennemis d'un coup et en traquant des crédits cachés derrière des défis de mouvement, pour acheter des améliorations qui ouvrent littéralement de nouvelles routes dans la tour.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | Action-platformer FPS / parkour / skill-based avec progression permanente |
| **Platform** | PC (Steam / itch.io) — clavier-souris primaire, support manette en stretch |
| **Target Audience** | Fans de Ghostrunner, Hollow Knight, Hades, Dead Cells — joueurs mastery-seekers 18-35 ans |
| **Player Count** | Solo uniquement |
| **Session Length** | 20-45 minutes (1-2 étages + visite shop) |
| **Monetization** | Premium one-time (itch.io pay-what-you-want envisageable pour MVP) |
| **Estimated Scope** | Medium (Tier 1 MVP = 4-6 semaines solo ; Tier 3 Full Vision = 5-6 mois solo) |
| **Comparable Titles** | Ghostrunner (feel), Hollow Knight (shop + secrets), Cyberpunk 2077 (univers, cyberware) |

---

## Core Fantasy

Tu es une lame cybernétique. Tu incarnes une cyber-ronin qui grimpe la tour Arasaka — symbole corporate de la ville — et chaque palier te rapproche du sommet. Le katana est une extension de toi : un coup = un kill. Mais le pouvoir vrai, c'est le **mouvement** — tu voles littéralement entre les salles, tu escalades des parois lisses, tu danses à 4 mètres au-dessus d'un laser mortel. À chaque retour dans la tour, tu te sens objectivement plus fort qu'hier : ton moveset a grandi, des recoins qui t'étaient refusés s'ouvrent maintenant, et ton corps cybernétique est littéralement augmenté.

C'est la promesse de devenir, étape par étape, la lame fluide parfaite.

---

## Unique Hook

**C'est comme Ghostrunner, AND ALSO** chaque crédit du shop est planqué derrière un défi de mouvement (plateforme impossible, timing de dash, chaîne de wall-runs) — donc ton *skill de mouvement actuel* détermine directement *quelles améliorations tu peux t'offrir*. Les upgrades ne sont pas juste des récompenses pour tuer — ce sont des promesses visibles : "atteins ce crédit et ton moveset change pour toujours."

Cette boucle transforme la tour en espace métroidvania vertical : les upgrades débloquent des routes, les routes cachent des crédits, les crédits achètent les upgrades. Tu *vois* ta progression dans l'architecture du niveau.

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Sensation** | 2 | Feedback hit net (son sec + 0.1s slow-mo au kill), trails de mouvement, impact camera subtil |
| **Fantasy** | 4 | Cyber-ronin ascension, Arasaka Tower, chrome + katana |
| **Narrative** | 7 | Minimaliste, environnementale uniquement (posters, terminaux, aucun dialogue in-flow) |
| **Challenge** | 1 | Cœur du jeu : one-shot mutuel, skill ceiling élevé, flow state |
| **Fellowship** | N/A | Solo only |
| **Discovery** | 3 | Secrets = défis de mouvement, récompense exploration verticale |
| **Expression** | 5 | Ordre d'achat des upgrades = style personnel ; speedruns |
| **Submission** | N/A | Jeu intense de bout en bout |

### Key Dynamics (Emergent behaviors)

- Les joueurs vont **re-parcourir les étages** avec un nouveau moveset pour atteindre les secrets inaccessibles au premier passage.
- Les joueurs vont **se spécialiser** (mouvement offensif vs défensif vs aérien) via leurs choix d'achats.
- La communauté va **partager des routes** et des speedruns sur itch.io / réseaux sociaux.
- Les joueurs vont **mourir en riant** — la mort instantanée + respawn 1s crée un flow "blâme-moi, pas le jeu" (cf. Super Meat Boy, Ghostrunner).

### Core Mechanics (systèmes implémentés)

1. **Katana one-shot en mouvement** — hitbox courte, obligatoire d'être proche + en action.
2. **Moveset parkour extensible** — double jump, dash, wall-run, slow-mo aérien débloqués via shop.
3. **Tower ascension par étages** — niveaux linéaires avec embranchements cachés, checkpoints fréquents.
4. **Économie de crédits + shop** — crédits via kills et secrets, achats permanents.
5. **One-hit-death + respawn 1s au checkpoint** — pas de barre de vie, bouclier, ou système de soin.

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** | Ordre d'achat des upgrades, choix des secrets à poursuivre, style d'approche de chaque salle | Supporting |
| **Competence** | Cœur du jeu : skill de mouvement + combat, progression visible via upgrades et secrets atteints | Core |
| **Relatedness** | Non visé (solo, narration minimale) ; compensé par community-sharing de speedruns post-launch | Minimal |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Achievers** — 100% des secrets, speedrun leaderboards, maîtrise du moveset complet
- [x] **Explorers** — route optimale, secrets cachés, architecture verticale à comprendre
- [ ] **Socializers** — pas de co-op ni narrative
- [x] **Killers/Competitors** — leaderboards de speedrun (stretch goal Tier 3)

### Flow State Design

- **Onboarding** : Les 3 premières salles enseignent l'essentiel sans texte — ennemi immobile, dash obligatoire, premier kill, premier mur à courir. L'UI est invisible.
- **Difficulty scaling** : Les upgrades achetées déverrouillent des configurations d'ennemis plus complexes dans les étages suivants (verticalité, timing, densité).
- **Feedback clarity** : Chaque kill flash blanc + son sec 50ms. Chaque hit reçu = fondu rouge 200ms + respawn. Secrets atteints = chime distinctif.
- **Recovery from failure** : Respawn < 1s depuis checkpoint courant. La mort est *pédagogique* (l'ennemi qui t'a tué reste visible au même endroit pour la prochaine tentative).

---

## Core Loop

### Moment-to-Moment (30 secondes)

Entrer dans une salle → lire la config (ennemis, plateformes, lasers) → dasher/wall-runner pour se positionner → trancher l'ennemi d'un coup → enchaîner au suivant. Si on est touché : respawn checkpoint 1s, l'ennemi est toujours là. Le hit feedback est instantané, le rythme est staccato.

### Short-Term (5-15 minutes)

Compléter un segment entre deux checkpoints (2-4 salles), incluant 1-2 crédits cachés optionnels qui sortent du chemin nominal. Le joueur choisit : "je tente le secret maintenant ou je reviens plus tard ?" → tension "one more try" sur la plateforme qui nargue.

### Session-Level (20-45 minutes)

Compléter 1-2 étages complets, récolter ~30-80 crédits, rentrer au shop entre les deux étages, acheter l'upgrade la plus adaptée à son style → pousser dans l'étage suivant qui révèle de nouveaux secrets accessibles grâce à l'upgrade fraîchement achetée. Session naturelle = finition d'étage + shop.

### Long-Term Progression

Débloquer les 8 upgrades clés (cible — 5 minimum si playtest le dicte, cf. Open Questions) à travers les 5 étages ; atteindre le sommet ; battre le boss final. **Boss final** : seul ennemi du jeu avec une barre de vie (plusieurs coups pour le tuer) ; le joueur reste one-shot. L'asymétrie force à maintenir la pression de mouvement pendant plusieurs passes sans jamais offrir de filet de sécurité au joueur. Post-game : speedrun mode, 100% secrets, mode permadeath optionnel (stretch).

### Retention Hooks

- **Curiosity** : Secrets visibles mais inaccessibles ("je reviendrai avec le double jump")
- **Investment** : Crédits + upgrades permanents = progress qu'on ne perd jamais
- **Mastery** : Skill-based, le joueur sent sa propre main s'améliorer
- **Social** : Community leaderboards + partage de routes (post-launch)

---

## Visual Identity Anchor

**Direction : Chrome Zen**

*Règle visuelle centrale* : **"Le vide rend la lame visible."**

*Principes visuels* :

1. **Une seule couleur d'accent par plan.** La couleur signale toujours quelque chose de mécanique (rouge = ennemi/hostile, cyan = secret/interactif, blanc = path principal). *Design test* : si un élément décoratif porte une couleur qui n'a pas de signification mécanique, on le désature.

2. **Géométrie corporate minimaliste.** Surfaces larges, chrome poli, verre, béton blanc. Très peu de détails. Lignes pures. *Design test* : si un élément demande du détail artistique qu'un solo dev ne peut pas livrer en 6 semaines, on le remplace par une primitive + shader flat.

3. **Le sang est la seule tache warm dans l'image.** Les kills créent les seuls splashes de couleur non-calibrés du jeu. *Design test* : si une scène de kill passe inaperçue visuellement, elle échoue — on amplifie.

*Philosophie couleur* : Base achromatique (blanc, gris, chrome) + un accent néon par scène + rouge de sang uniquement aux kills. Palette principale inspirée des intérieurs Arasaka de Cyberpunk 2077 et des architectures de *Mirror's Edge*.

Cette direction sera développée dans le futur `docs/art-bible.md` (via `/art-bible` après `/setup-engine`).

---

## Game Pillars

### Pillar 1: FLOW AVANT TOUT
Le jeu doit répondre instantanément : zéro input delay, zéro animation qui gêne l'enchaînement.

*Design test* : Si on hésite entre une belle animation de 0.4s et un snap fonctionnel de 0.1s → **snap**.

### Pillar 2: LA PROGRESSION SE VOIT ET SE SENT
Chaque upgrade achetée change mesurablement ce que le joueur peut faire. Pas de "+5% dégâts" — que des upgrades qui ouvrent de nouvelles options.

*Design test* : Si une upgrade n'est pas visible en action ni ne débloque une nouvelle route → **poubelle**.

### Pillar 3: UNE SECONDE CHANCE N'EST JAMAIS LOIN
Die-retry doit être sous 2 secondes. Zéro temps perdu entre la mort et la tentative suivante.

*Design test* : Si un système ajoute du temps avant le retry (anim de mort longue, écran de stats) → **coupé ou raccourci**.

### Pillar 4: LES SECRETS RÉCOMPENSENT LE MOUVEMENT, PAS LE CERVEAU
Chaque cachette est un défi d'exécution (timing, route, skill), jamais une énigme logique ou une devinette.

*Design test* : Si pour trouver un secret il faut *réfléchir*, on refait le secret en exigeant de *bouger*.

### Anti-Pillars (What This Game Is NOT)

- **NOT un jeu d'armes multiples** : katana unique. Chaque arme alternative compromettrait FLOW et l'économie d'input.
- **NOT un jeu à énigmes environnementales** (interrupteurs, codes, ordres à trouver) : viole SECRETS = MOUVEMENT.
- **NOT un jeu avec barre de vie ou ennemis tanks** : one-shot mutuel strict pour **tous** les ennemis standards. **Exception unique : le boss final** dispose d'une barre de vie multi-hits (le joueur, lui, reste one-shot — l'asymétrie est intentionnelle et marque la nature exceptionnelle du combat final). Aucun autre ennemi ne prend plus d'un coup.
- **NOT un jeu à narration interruptive** (cutscenes mid-level, dialogues joueur) : viole SECONDE CHANCE.

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| Ghostrunner (2020) | Feel katana one-shot, wall-run, dash, mort instantanée, respawn 1s | Shop de progression permanente + secrets de mouvement (Ghostrunner est linéaire sans progression persistante) | Valide la viabilité commerciale de la formule action+mouvement+one-shot |
| Hollow Knight | Shop/charms permanents, secrets cachés, architecture qui récompense le skill de mouvement | Action FPS 3D à la place de 2D metroidvania ; tempo beaucoup plus rapide | Valide la formule "upgrades permanents qui ouvrent la carte" |
| Cyberpunk 2077 | Univers visuel, concept de cyberware, immersion corporate-tower | Minimalisme Chrome Zen au lieu de densité Night City ; gameplay focalisé | Inspiration émotionnelle clé du créateur |
| Dead Cells | Run pacing, feel de chaque action, feedback moment-to-moment | Progression permanente (pas roguelike) ; one-shot (pas barre de vie) | Valide le "flow de la run courte" |
| Polytopia | Décision tactique entre phases d'action (choix au shop) | N/A — seulement inspirationnel | Confirme l'appétit du créateur pour la décision courte et réflexive |

**Non-game inspirations** :
- *Ghost in the Shell* (film 1995) — silhouette de la cyber-ronin, esthétique urbaine
- *Akira* (film 1988) — ruelles néon, sensation de vitesse
- *Blade Runner 2049* — architectures verticales imposantes, minimalisme corporate
- *Mirror's Edge* (DICE) — référence art direction pour Chrome Zen

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 18-35 |
| **Gaming experience** | Mid-core à hardcore |
| **Time availability** | Sessions 30-60min en semaine, plus longues le weekend |
| **Platform preference** | PC (Steam, itch.io) |
| **Current games they play** | Ghostrunner, Hollow Knight, Hades, Dead Cells, Sekiro |
| **What they're looking for** | Un jeu où leur skill compte vraiment, qui leur offre une progression palpable, avec un feel de mouvement supérieur |
| **What would turn them away** | Barre de vie + ennemis spongieux, cutscenes obligatoires, tutoriels intrusifs, armes multiples qui diluent le focus, progression purement numérique |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Recommended Engine** | À décider via `/setup-engine`. Probable : Godot 4.6 (solo dev, open-source, PC/web easy, pipeline léger). Alternatives : Unity (rich tooling, but heavier) |
| **Key Technical Challenges** | Feel du mouvement FPS (itérations lourdes sur physique + input), hitbox katana en mouvement, niveau vertical avec checkpoints, performances constantes (vsync locked) |
| **Art Style** | 3D stylisé — primitives géométriques + shaders flats, palette minimaliste Chrome Zen |
| **Art Pipeline Complexity** | Low — placeholder possible avec primitives Godot/Unity + shader minimal ; aucun modèle 3D complexe requis pour MVP |
| **Audio Needs** | Moderate — SFX précis critiques (katana, kill, respawn, pickup, wall-run), musique synthwave/cyberpunk légère |
| **Networking** | None (solo only) |
| **Content Volume** | Tier 1 : 1 étage, 3 upgrades, 1 ennemi, 3-5 secrets. Tier 3 : 5 étages, 8 upgrades, 5 ennemis, 1 boss, 30+ secrets |
| **Procedural Systems** | Aucun — tous les niveaux sont hand-crafted |

---

## Risks and Open Questions

### Design Risks

- **Le feel du mouvement katana doit être parfait** ou le jeu est mort à 10 minutes de play. C'est le seul différenciateur de FLOW.
- **Économie de crédits** : trop rares = frustration, trop denses = progression trop rapide et jeu s'éteint. Itération playtest obligatoire.
- **Courbe de difficulté en jeu one-shot** : sans tuto subtil et progression claire, on décourage 70% des joueurs casuals au premier étage.
- **Boss final avec barre de vie** : asymétrie assumée (boss multi-hits, joueur one-shot) mais risque de casser le rythme staccato du reste du jeu. Le combat doit rester une chaîne d'exécutions courtes (ex : 3-5 fenêtres d'attaque enchaînées, chacune risquant la mort immédiate du joueur), pas un DPS check ou un combat d'attrition. À prototyper tôt pour valider le feel.

### Technical Risks

- **Timing des inputs + réponse physique du perso** : 0.1s de délai = jeu cassé. Premier risque technique à résoudre en prototype.
- **Hitbox katana en mouvement rapide** : tunneling possible, détection à haute vitesse angulaire non triviale.
- **Premier jeu solo** = peu d'expérience pour calibrer. Ce sera appris par la pratique.

### Market Risks

- **Niche encombrée** : Ghostrunner 1+2, Neon White, Severed Steel — plusieurs jeux "katana-FPS-flow" récents. Différenciation = shop permanent + secrets métroidvania.
- **Visibilité sur itch.io/Steam** solo premier jeu sans marketing = très limité. Acceptable car projet d'apprentissage.

### Scope Risks

- **Tentation de featuritis** (narrateur, multiples armes, boss intermédiaires). Anti-piliers stricts doivent rester gardiens.
- **Art drift** — perdre le minimalisme Chrome Zen pour essayer de faire "plus joli" = scope explose.

### Open Questions

- **Taille du moveset final** : 8 upgrades cible, 5 minimum si playtest le dicte. À valider par prototype.
- **Tempo des checkpoints** : toutes les 2-4 salles ? À déterminer par playtest.
- **Shop : un seul PNJ ou plusieurs ?** Un seul pour le MVP ; à envisager en Tier 3.

---

## MVP Definition

**Core hypothesis** : *"Le couple katana-instant-kill + mouvement + secret-as-movement-challenge + shop-de-progression-permanente produit un flow state addictif sur 1 étage complet (20-45 min avec exploration des secrets)."*

**Required for MVP** (Tier 1, 4-6 semaines) :

1. Perso FPS avec moveset de base (course, saut — aucune upgrade active au départ)
2. Katana one-shot avec hitbox et feedback propre (SFX + flash)
3. 1 étage de 8-10 salles linéaires avec checkpoints toutes les 2-3 salles
4. 1 type d'ennemi (grunt statique avec laser frontal) — one-shot dans les deux sens
5. Shop fonctionnel avec 2 upgrades achetables (double jump, dash horizontal) — slow-mo aérien sorti du MVP, reporté en système séparé post-MVP (design/gdd/aerial-slowmo-system.md, à écrire en Tier 2+)
6. 3-5 secrets cachés derrière des défis de mouvement
7. Respawn < 1s au checkpoint en cas de mort
8. Art placeholder Chrome Zen (primitives + 1 shader flat)

**Explicitly NOT in MVP** :
- Plusieurs étages, plusieurs types d'ennemis, boss
- Narration environnementale (terminaux, posters)
- Menu principal stylisé (text-only suffit)
- Tutoriel formel (le niveau doit enseigner par design)
- Audio musique (SFX uniquement)
- Speedrun mode, leaderboards
- Cinématiques, dialogues

### Scope Tiers

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP (Tier 1)** | 1 étage, 1 ennemi, 3 upgrades, 3-5 secrets | Core loop complet (tranche + bouge + achète) | 4-6 semaines |
| **Vertical Slice (Tier 2)** | 3 étages, 3 ennemis, 6 upgrades, 10+ secrets, 1 mini-boss | Core + audio polish + tuto intégré | 3 mois total |
| **Alpha (Tier 2.5)** | 4-5 étages placeholder, 5 ennemis, 6-7 upgrades | Tout le core, art rough, pas de boss ni de leaderboard | 4 mois total |
| **Full Vision (Tier 3)** | 5 étages polish, 5 ennemis, 8 upgrades, boss final, speedrun mode, leaderboard itch.io | Full polish + metagame | 5-6 mois total |

---

## Next Steps

- [ ] Configurer le moteur et populer la référence version-aware (`/setup-engine`)
- [ ] Créer l'art bible à partir du Visual Identity Anchor (`/art-bible`)
- [ ] Valider le concept doc (`/design-review design/gdd/game-concept.md`)
- [ ] Décomposer en systèmes avec priorités (`/map-systems`)
- [ ] Écrire les GDDs par système (`/design-system [system-name]` × N)
- [ ] Cross-system consistency (`/review-all-gdds`)
- [ ] Gate check avant architecture (`/gate-check`)
- [ ] Architecture master (`/create-architecture`)
- [ ] ADR × N (`/architecture-decision`)
- [ ] Control manifest (`/create-control-manifest`)
- [ ] Architecture review (`/architecture-review`)
- [ ] UX spec pour HUD + menus (`/ux-design`)
- [ ] Prototype du core mechanic en priorité (`/prototype movement-katana`)
- [ ] Playtest report du prototype (`/playtest-report`)
- [ ] Epics + stories + sprint (`/create-epics` → `/create-stories` → `/sprint-plan`)
- [ ] Développer stories (`/dev-story`)
