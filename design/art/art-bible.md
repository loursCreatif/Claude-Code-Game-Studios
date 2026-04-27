# Art Bible — CHROME://ASCENT

*Created: 2026-04-21*
*Status: Complete*
*Visual Direction: **Chrome Zen***
*Anchor rule: **"Le vide rend la lame visible."***

> **Art Director Sign-Off (AD-ART-BIBLE)**: _Skipped — Solo mode (review-mode=solo). Sign-off à reprendre si le projet passe en mode `lean` ou `full`._

---

## Purpose

Ce document est le document de contrainte visuelle pour CHROME://ASCENT. Toute décision artistique — palette, composition, asset, UI, VFX — doit pouvoir être validée ou rejetée en le lisant. Les sections sont hiérarchiques : les sections 1–4 définissent l'identité, les sections 5–8 la traduisent en production, la section 9 en curate les références externes.

---

## 1. Visual Identity Statement

### One-Line Visual Rule

> **"Le vide rend la lame visible."**

Cette règle est adoptée sans modification. Elle est opérationnelle : toute décision visuelle peut s'y confronter directement. Un espace dense rend la lecture du mouvement impossible ; un espace vide transforme chaque geste en événement. La lame n'est pas le sujet de l'image — elle en est la conclusion.

### Les 3 Principes Visuels Structurants

#### 1. Une couleur. Une intention.

Chaque plan ne contient qu'une seule couleur d'accent active simultanément. Rouge = menace imminente, cyan = secret ou surface interactive, blanc pur = trajectoire principale. Ces trois couleurs ne coexistent jamais dans le même champ de vision — si elles y sont toutes, aucune ne dit rien.

- **Design test** : quand un élément interactif et un ennemi apparaissent dans le même cadre, ce principe dit — choisir lequel parle. Si l'ennemi est la priorité immédiate, le cyan disparaît ou sort du champ. Jamais deux signaux concurrents au même instant.
- **Pilier servi** : **FLOW AVANT TOUT** — le cerveau ne trie pas, il lit. Un seul signal couleur par plan élimine la charge cognitive qui crée le délai de décision.

#### 2. Surfaces corporates, géométrie nette.

L'architecture de la tour est construite sur des plans larges, des angles droits, du chrome poli, du verre et du béton blanc. Pas d'ornement. Pas de texture organique. La géométrie Arasaka est la cage — lisible, oppressante, froide.

- **Design test** : quand un asset décoratif est ambigu (détail décoratif vs surface de parkour), ce principe dit — simplifier jusqu'à ce que la fonction soit immédiatement lisible à la silhouette. Si on ne peut pas lire la surface en mouvement rapide, elle est trop complexe.
- **Pilier servi** : **LES SECRETS RÉCOMPENSENT LE MOUVEMENT** — une géométrie lisible signifie que le joueur peut anticiper et lire les routes cachées en courant, pas en s'arrêtant pour analyser.

#### 3. Le sang est la seule chaleur.

Tous les éléments visuels respectent une palette froide et désaturée : gris, blanc cassé, noir, chrome. La seule tache chromatique chaude et non-calibrée dans l'image est le sang. Elle n'est pas esthétisée. Elle est là, brute, contrastante — la conséquence physique dans un monde de métal.

- **Design test** : quand on ajoute un effet visuel (UI, VFX, feedback), ce principe dit — si cet effet utilise du rouge-orange-chaud pour autre chose que le sang ou la mort, il contamine le signal. Recolorer en froid ou trouver une autre lecture.
- **Pilier servi** : **LA PROGRESSION SE VOIT ET SE SENT** — le sang comme seul warm signal renforce la lisibilité des confrontations. Quand un ennemi tombe, l'image change de température. Le joueur *sent* que quelque chose s'est passé sans lire un chiffre.

### Ce que ce Visual Identity Statement exclut explicitement

Exclusions : les palettes multi-couleurs saturées (style neon-rainbow cyberpunk), les interfaces avec surcharge d'informations contextuelles permanentes, les textures organiques ou "sale" sur les surfaces principales, les effets particules décoratifs sans rôle de lisibilité, et toute interruption visuelle non liée au mouvement ou à la menace. En résumé : si c'est là pour être *beau* mais pas pour *dire quelque chose d'actionnable*, ce n'est pas dans CHROME://ASCENT.

---

## 2. Mood & Atmosphere

> **Règle transversale** : le joueur lit l'état du jeu en moins de 0.3 seconde. Chaque état possède un élément visuel signature unique — aucun doublon entre les six.

### État 1 — Ascension / Parkour-Combat Flow

*L'état dominant. Le joueur vit ici 85 % du temps.*

| Dimension | Spec |
|---|---|
| **Cible émotionnelle** | Tension cinétique |
| **Key light** | Venant du haut — spots overhead froids, légèrement en contre-plongée sur les surfaces, simulant l'éclairage industriel d'une tour de bureaux |
| **Température couleur** | 5 500–6 500 K (blanc-froid à blanc-jour) ; ombres tirées vers 4 000 K pour créer le contraste sol/plafond |
| **Contraste** | High-key sur les surfaces corporates (chrome, béton blanc), deep shadow dans les interstices |
| **Volumétrique** | Raies verticales fines — dust columns entre dalles et passerelles. Fréquence basse, ne clutte pas la lecture |
| **Adjectifs atmosphériques** | Stérile, ascendant, précis, brutal, compressé |
| **Niveau d'énergie** | Frenetic |
| **Élément signature** | Colonnes de lumière volumétrique verticales qui guident l'œil vers le haut — renforcent la direction du mouvement et lisent "Tower" immédiatement |

### État 2 — Kill Moment

*0.1 seconde de slow-mo mécanique. Un beat, pas une cinématique.*

| Dimension | Spec |
|---|---|
| **Cible émotionnelle** | Catharsis instantanée |
| **Key light** | Flash directionnel omnidirectionnel depuis le point d'impact — blanc pur 6 500 K+, decay en 0.05 s |
| **Température couleur** | Flash blanc froid → retour immédiat à la palette de l'État 1. Le sang est la seule chaleur : splash rouge saturé ~2 200 K visuel (rouge chaud sur fond froid) |
| **Contraste** | Pic extrême sur le frame du flash — tout overexposé sauf la silhouette ennemie et le spray. Retour à high-key normal à la fin du slow-mo |
| **Volumétrique** | Absent pendant le flash — la lumière doit être plate et totale pour que le sang soit le seul objet |
| **Adjectifs atmosphériques** | Explosive, crue, saturée, fugace, nette |
| **Niveau d'énergie** | Explosive |
| **Élément signature** | Flash blanc total (1 frame) suivi du seul élément chaud de tout le jeu : le spray de sang rouge. Contraste thermique maximal dans l'espace visuel le plus bref possible |

### État 3 — Respawn / Retour au Checkpoint

*Transition entre mort et reprise. Instantanée, mais pas silencieuse.*

| Dimension | Spec |
|---|---|
| **Cible émotionnelle** | Réinitialisation froide |
| **Key light** | Aucune — fondu noir complet sur 0.1 s, retour lumière État 1 sur 0.1 s. Pas de fondu progressif : cut binaire |
| **Température couleur** | Noir absolu dans la transition ; retour à 5 500 K à la réapparition |
| **Contraste** | Zéro (noir) → high-key immédiat. Le saut de contraste porte la signalétique |
| **Volumétrique** | Absent pendant la transition. À la réapparition : les colonnes verticales reviennent à pleine intensité — confirmation visuelle "tu es de retour" |
| **Adjectifs atmosphériques** | Sec, mécanique, neutre, binaire, systémique |
| **Niveau d'énergie** | Suspendu (la micro-seconde noire) → frenetic immédiat |
| **Élément signature** | Cut noir-à-noir en deux frames — pas de fondu, pas d'animation. La brutalité du cut **est** le message : le jeu ne juge pas, il repart |

### État 4 — Segment Secret / Hors Chemin

*Le joueur suit un crédit cyan loin du path nominal. La tension change de nature.*

| Dimension | Spec |
|---|---|
| **Cible émotionnelle** | Curiosité tendue |
| **Key light** | Rétro-éclairage latéral — source lumineuse déportée derrière la géométrie, créant des halos sur les arêtes. Direction : 45° horizontal depuis la source cyan |
| **Température couleur** | 7 500–9 000 K (cyan-froid, lumière d'urgence ou aquatique). Contraste fort avec la neutralité 5 500 K de l'État 1 |
| **Contraste** | Low-key global — les surfaces corporates sont sous-exposées. Seul le chemin cyan est en lumière directe. Le reste recule dans l'obscurité |
| **Volumétrique** | Haze latéral diffus — brume flottante froide qui atténue les arrière-plans et isole le joueur dans une bulle cyan |
| **Adjectifs atmosphériques** | Immersif, isolé, iridescent, discret, enveloppant |
| **Niveau d'énergie** | Measured |
| **Élément signature** | L'environnement entier bascule dans un bain de lumière cyan désaturée — les surfaces chromées réfléchissent bleu-froid. Un seul coup d'œil suffit : "je suis hors du chemin" |

### État 5 — Shop / Inter-Étage

*Seul moment de respiration. Le tempo visuel doit le signaler physiquement.*

| Dimension | Spec |
|---|---|
| **Cible émotionnelle** | Décompression calculée |
| **Key light** | Lumière diffuse large — softbox overhead simulée, aucun spot dur. Pas de direction dominante marquée |
| **Température couleur** | 4 200–4 800 K (blanc neutre légèrement chaud — "salle de réunion corporate") — seul état où la température monte légèrement par rapport au flow |
| **Contraste** | Balanced — pas de deep shadow, pas d'overexposure. Lisibilité maximale de l'UI |
| **Volumétrique** | Absent — pas de particules, pas de brume. Espace propre et lisible |
| **Adjectifs atmosphériques** | Neutre, respirable, fonctionnel, plateau, corporate |
| **Niveau d'énergie** | Suspendu |
| **Élément signature** | Absence de tout effet atmosphérique — pas de volumétriques, pas de halos, pas de particules. Le silence visuel **est** le contraste avec les 5 autres états. La salle "ne fait rien" et c'est lisible en 0.3 s |

### État 6 — Defeat / Échec sur Défi de Secret

*Le joueur tombe ou rate une plateforme. Pas une mort au combat — un échec de maîtrise.*

| Dimension | Spec |
|---|---|
| **Cible émotionnelle** | Frustration froide |
| **Key light** | Key light de l'État 4 (cyan) qui se désature brutalement vers gris-blanc 6 000 K à l'instant de l'échec — le contexte cyan "s'éteint" |
| **Température couleur** | Transition 9 000 K → 6 000 K en 0.15 s — désaturation visible, pas de chaud, pas de rouge (pas de mort combat) |
| **Contraste** | Pic de contraste sur la chute : vignette noire dure sur les bords de l'écran, centre surexposé — l'œil est forcé sur le personnage qui tombe |
| **Volumétrique** | La brume cyan de l'État 4 se dissipe instantanément — le contexte "secret" disparaît visuellement en même temps que l'échec |
| **Adjectifs atmosphériques** | Désaturé, abrupt, démasqué, glacial, vide |
| **Niveau d'énergie** | Measured (chute) → cut vers État 3 (respawn) |
| **Élément signature** | La vignette noire dure + désaturation du cyan en simultané — deux signaux qui lisent "tu as raté le secret" sans texte ni son nécessaire |

> **Note lighting artist** : Les transitions entre états 4→6 et 1→2 sont les plus exigeantes en timing. Prévoir des courbes d'interpolation non-linéaires (ease-in sharp) pour respecter les durées de 0.1–0.15 s spécifiées. Aucune transition ne doit dépasser 0.2 s sauf l'État 5 (entrée shop : 0.4 s acceptable).

---

## 3. Shape Language

> **Règle directrice** : *Tout ce qui coupe est hero. Tout ce qui contient recule.*

Le monde d'Arasaka est une cage d'angles droits. La lame du joueur est la seule diagonale. Cette opposition binaire — verticaux/horizontaux corporates contre la ligne oblique du katana — est la logique géométrique de tout l'univers visuel. Le vocabulaire de formes dérive directement de "Le vide rend la lame visible" : pour que la diagonale se lise, le monde doit être fait de droites stables. Rien d'organique. Rien de courbe. La cage mérite ses barreaux nets.

### Principe directeur

Les formes à arêtes vives et angles aigus (katana, laser ennemi, arête de plateforme) sont foreground actif. Les formes rectangulaires fermées et parallèles (murs, dalles, panneaux) sont background passif. Le joueur lit instantanément : si ça coupe, c'est un agent. Si ça contient, c'est du décor.

### Silhouette des personnages

#### Player — mains + katana (vue FPS)

**Les mains** portent une personnalité cyber-ronin minimaliste : gants tactiques fins, pas de bulk. Pas de méca-armor visible sur le dos de la main — une seule surbrillance chrome sur les jointures (arête fine, pas de relief complexe). La main recule dans la composition. Elle tient, elle ne décore pas.

**Le katana** est la forme hero du joueur :

- Lame droite, pas courbée — une ligne de coupe franche, lisible à grande vitesse
- Section transversale fine (moins de 5 % de la largeur d'écran au repos)
- Surface bicolore : dos de lame mat anthracite, tranchant chromé spéculaire. L'arête de lumière est la silhouette lue en 100 ms. Pas de motif gravé, pas d'effet particule permanent
- Tsuba (garde) : rectangle chromé minimal, 1:4 ratio épaisseur/largeur — juste assez pour briser la ligne de la lame et signaler la limite de la prise
- **Test thumbnail** : à 64×64 px, la lame doit lire comme une diagonale claire sur fond sombre. Si elle disparaît dans le fond, elle est trop fine ou trop peu contrastée

#### Ennemis — lecture en 100 ms à 8 m

**Règle de silhouette ennemie** : tout ennemi doit avoir une forme de tête distincte du rectangle corporate ambiant. La tête est la zone de lecture prioritaire — elle flotte au-dessus du bruit géométrique.

**Grunt (MVP)** :

- Corps : bloc rectangulaire vertical (3:1 H/L), uniforme corporate sombre — forme proche des pylônes pour accentuer le contraste dès qu'il bouge
- Tête : casque hémisphérique avec une fente horizontale unique et lumineuse (le laser). Cette fente est la silhouette signature — aucun autre élément du décor n'a une fente lumineuse horizontale à hauteur de visage
- **Distinction props vs ennemis** : les props sont statiques ET sans fente lumineuse. Si ça a une fente horizontale lumineuse à hauteur d'œil, c'est un agent hostile. Règle absolue

**Archétypes futurs — propositions à revalider au moment de la Section 5 (Character Design Direction). Différenciation par forme de tête uniquement** :

| Type | Forme tête | Signal géométrique |
|---|---|---|
| Grunt laser | Hémisphère + fente H | Rectangle stable, sol |
| Sniper | Cylindre étroit + viseur vertical | Vertical, hauteur |
| Brute | Cube large + deux fentes V | Masse, largeur |
| Drone | Octogone plat | Flottant, symétrique |
| Officier | Trapèze inversé + arête vive | Autorité, pointu haut |

Chaque type de tête est identifiable à 64×64 px en silhouette seule.

### Géométrie de l'environnement — Tour Arasaka

#### Forme dominante

**Rectangles et orthogonaux stricts.** Pas de courbes, pas de diagonales dans les murs ou les sols — uniquement dans les éléments interactifs (arêtes de plateformes, katana, lasers). Cette règle est directement opérationnelle : toute diagonale dans l'environnement est une surface de parkour ou une menace. Le décor ne fait pas de diagonale pour rien.

Matières dominantes : plans larges et plats (chrome, béton blanc, verre sombre). Les subdivisions dans les murs sont orthogonales, régulières, et faibles en relief. Plus le jeu avance (étages supérieurs), plus les modules sont grands — la tour se "vide" à mesure qu'on monte, renforçant le principe directeur.

#### Renforcement de la verticalité

La tour se grimpe. Les formes servent ce vecteur :

- **Colonnes verticales pleines** : éléments environnementaux récurrents, hauts, fins (ratio 1:8 L/H minimum). Ils guident l'œil vers le haut sans bloquer le mouvement horizontal
- **Murs à joints horizontaux** : les lignes de jointures dans les panneaux de béton/chrome sont **horizontales** — elles créent une grille de lecture verticale (les joints deviennent les "marches" de la lecture d'altitude). Le joueur lit "combien j'ai monté" via les joints, pas via un HUD
- **Plateformes décalées en Y** : les surfaces de parkour sont disposées en décalé vertical, jamais alignées à plat. La géométrie elle-même suggère la trajectoire : sauter, pas courir
- **Vides entre niveaux** : les ouvertures verticales (trouées dans les dalles) sont plus larges que les ouvertures horizontales (portes). La tour "respire" plus vers le haut que vers l'avant

#### Lisibilité des surfaces de parkour (sans couleur)

La couleur est réservée aux signaux actifs (rouge/cyan/blanc). La surface elle-même doit dire sa fonction via sa forme :

| Surface | Forme signature | Lecture |
|---|---|---|
| Wall-run | Pan de mur lisse, sans joint sur 3 m min, arête supérieure chanfreinée 45° | "Lisse = courir" |
| Plateforme sûre | Bord supérieur avec rebord fin en saillie (5–10 cm) — une lèvre | "Lèvre = poser les pieds" |
| Sol solide | Plan large continu sans interruption, jointures orthogonales régulières | "Continu = stable" |
| Vide mortel | Absence totale de géométrie — le vide n'a pas de forme, il est la forme absente | "Rien = tomber" |
| Zone laser (sol) | Grille métallique fine visible en dessous + arête biseautée à 30° sur les bords | "Transparence + biseau = ne pas marcher" |

**Règle critique** : la forme dit la fonction AVANT la couleur. La couleur confirme ou signale le danger actif. Un mur wall-runnable sans la couleur cyan doit déjà être identifiable comme tel par son chanfrein et sa lisseté.

### UI Shape Grammar

**L'UI reprend la géométrie du monde — avec une abstraction supplémentaire.**

Les éléments HUD utilisent les mêmes angles droits et rectangles que l'architecture Arasaka, mais avec une épaisseur de ligne réduite à son minimum fonctionnel : le HUD est le monde, vu à travers une vitre. Pas de courbes, pas de bords arrondis, pas d'ombres portées.

Justification au service du FLOW :

- Un HUD qui utilise la même grammaire que l'environnement s'intègre sans détacher l'œil — il coexiste plutôt qu'il n'interrompt
- Les angles durs sont scannables en périphérie de vision. Un rectangle chromé en haut à gauche est la barre de vie. Le joueur n'a pas besoin de le regarder, il le voit
- **Exception unique** : les icônes de compétences débloquées dans le shop ont une forme extérieure **hexagonale** — seul élément du jeu à six côtés. Cela les distingue immédiatement de tout élément environnemental ou combat, et crée une "catégorie visuelle shop" reconnaissable. Cette règle est rappelée en Section 7 (UI)

**Ce que l'UI n'est pas** : pas de cadres globuleux, pas de panneaux translucides à bords arrondis (style RPG moderne), pas d'éléments circulaires pour les ressources (utiliser des barres linéaires horizontales à la place).

### Hero Shapes vs Supporting Shapes

#### Hero — attirent l'œil

| Forme | Raison |
|---|---|
| **Diagonale** | Aucun autre élément du monde n'est diagonal — toute diagonale est un agent actif (lame, laser, trajectoire de chute) |
| **Fente lumineuse horizontale** | Seule forme lumineuse à hauteur d'œil dans un mur sombre — encodée "ennemi" dès la première salle |
| **Arête chanfreinée 45°** | Rupture dans la rigueur orthogonale — signal "surface interactive" avant la couleur |

#### Supporting — reculent dans le fond

| Forme | Raison |
|---|---|
| **Rectangle plein sans saillie** | Forme de base de toute l'architecture — le cerveau la catégorise "décor" en moins de 50 ms |
| **Grille orthogonale régulière** | Répétition périodique = texture de fond — la périodicité signale l'inertie, pas l'action |
| **Colonne verticale lisse** | Trop allongée pour être un agent, pas d'arête active — lue comme "structure", guide le regard sans l'accrocher |

### Contraintes de production (primitives Godot)

Chaque forme ci-dessus se construit avec des primitives Godot standard :

- **Colonnes** : `CSGCylinder` ou `MeshInstance3D` + `BoxMesh` étiré en Y — une primitive
- **Arête chanfreinée wall-run** : `BoxMesh` + un second `BoxMesh` fin orienté 45° en surface — deux primitives
- **Lèvre de plateforme** : `BoxMesh` principal + `BoxMesh` rebord (10 cm x 5 cm) — deux primitives
- **Silhouette ennemi grunt** : `CapsuleMesh` corps + `SphereMesh` tête + `BoxMesh` plat émissif pour la fente laser — trois primitives
- **Katana** : `BoxMesh` très allongé (ratio 1:20) avec matériau bicolore (shader plat dos mat / tranchant spéculaire) — une primitive, un shader à deux zones

Aucun asset de cette section ne nécessite de sculpt ou de modélisation organique. Toutes les formes sont constructibles avec un Boolean CSG ou un assemblage de BoxMesh/SphereMesh. Si une forme requiert plus de 5 primitives pour être lisible, elle est trop complexe pour ce budget.

---

## 4. Color System

> **Règle transversale** : *La couleur n'est pas décoration. Elle est un signal d'état mécanique. Si une couleur peut être retirée sans que le joueur perde une information de jeu, elle n'a pas sa place dans CHROME://ASCENT.*

### Palette primaire

#### Neutres / Environnementaux

| # | Nom | Hex | sRGB | Rôle fonctionnel | Couverture écran | Justification |
|---|---|---|---|---|---|---|
| N1 | **Noir Vide** | `#0A0A0C` | (10, 10, 12) | Surface d'absorption — vides, interstices, ombres profondes | 20–35 % | Quasi-noir avec légère dominante bleue (B > R). Contraste contre Blanc Path : 18,1:1 |
| N2 | **Chrome Froid** | `#C8CDD4` | (200, 205, 212) | Matière principale — béton blanc, panneaux chrome, toute surface corporative passive | 35–50 % | Gris légèrement bleuté, 80 % de luminosité — assez clair pour lire les silhouettes sombres devant, assez désaturé pour ne pas concurrencer les accents |
| N3 | **Verre Sombre** | `#1E2228` | (30, 34, 40) | Panneaux verre, arrière-plans, inner-shadow | 15–25 % | Blue-cast calculé — les reflets spéculaires tirent naturellement vers le cyan, préparant visuellement l'État Secret |

#### Accents Sémantiques

| # | Nom | Hex | sRGB | Rôle fonctionnel | Couverture écran | Justification |
|---|---|---|---|---|---|---|
| A1 | **Rouge Menace** | `#E8192C` | (232, 25, 44) | Ennemi actif, laser sol actif, zone de dommage imminent | 0 % → 3–6 % (combat) | Contraste contre Chrome Froid : 4,8:1. Plus saturé que Sang pour distinguer "alarme" de "conséquence" |
| A2 | **Sang** | `#B50F1F` | (181, 15, 31) | Splash de kill uniquement | 0 % → 2–4 % pendant 0.3–0.8 s | Plus sombre et chaud que A1. Contraste contre Noir Vide : 6,1:1. Exception temporelle (< 1 s) |
| A3 | **Cyan Secret** | `#00D4E8` | (0, 212, 232) | Crédit caché, surface wall-run, interactable | 0 % → 5–10 % (segment secret) | Contraste contre Noir Vide : 9,2:1. Contraste contre Chrome Froid : 2,1:1 — **backup cue requis** (voir colorblind) |
| A4 | **Blanc Path** | `#F0F4FF` | (240, 244, 255) | Trajectoire principale, flèche de direction, repère spawn | 0 % → 1–3 % | Blanc légèrement teinté bleu — jamais pur `#FFFFFF` qui cliperait sur Chrome Froid adjacent. Contraste contre Noir Vide : 19,8:1 |

### Vocabulaire sémantique

| Couleur | Hex | Mécanique — ce que ça dit | Jamais utilisée pour |
|---|---|---|---|
| **Rouge Menace** | `#E8192C` | Ennemi actif, laser en charge, zone d'impact imminent | Décoration, UI info, dégâts déjà reçus |
| **Sang** | `#B50F1F` | Confirmation visuelle de kill — splash, durée < 1 s | Surface statique, état persistant, UI, fond de texture |
| **Cyan Secret** | `#00D4E8` | Crédit caché, surface wall-run, interactable en attente d'input | Ennemi, UI d'erreur, décor ambiant statique |
| **Blanc Path** | `#F0F4FF` | Trajectoire principale recommandée, checkpoint actif | Tout ennemi, tout secret, remplissage de surface |
| **Chrome Froid** | `#C8CDD4` | Surface corporative passive — "ici tu peux passer" | Signal de danger, signal interactif, confirmation de progression |
| **Noir Vide** | `#0A0A0C` | Absence, vide mortel, hors-champ | Arrière-plan d'UI fonctionnel (utiliser N3 à la place) |
| **Verre Sombre** | `#1E2228` | Profondeur architecturale, inner-shadow | Surface interactive, élément UI primaire |

### Règles de température par étage

**La palette de base reste identique sur tous les étages.** Les neutres N1/N2/N3 et les accents A1/A2/A3/A4 ne changent pas. Ce qui change par étage est la **densité lumineuse ambiante** et le **ratio ombre/lumière** — non la teinte.

**Justification** : changer la couleur d'une surface entre l'Étage 1 et l'Étage 5 créerait une ambiguïté sémantique. Si Chrome Froid devient légèrement orangé à mi-tower, le cerveau cherche si cette teinte signifie quelque chose. Elle ne signifie rien — et c'est le bruit cognitif que "Une couleur, une intention" élimine.

| Étage | Ambiance narrative | Température ambiante | Ratio lumière/ombre | Signal distinctif |
|---|---|---|---|---|
| **1 — Lobbies** | Corporate ground floor | 5 500 K | 70 / 30 | Colonnes volumétriques denses, beaucoup de lumière — "entrée surveillée" |
| **2 — Bureaux** | Open space Arasaka | 5 800 K | 65 / 35 | Faux-plafonds, lumière uniforme — sensation de cage propre |
| **3 — Serveurs** | Data center | 6 200 K | 50 / 50 | LED froides, lignes de lumière horizontales — plus machine, moins humain |
| **4 — Direction** | Étage vide, prestige | 6 500 K | 40 / 60 | Spots directionnels rares, grandes ombres — la tour "respire" |
| **5 — Sommet** | Toit / penthouse | 6 800–7 000 K | 30 / 70 | Lumière extérieure froide, ciel gris métallique — presque plus d'architecture |

L'ascension est une descente en luminosité et une montée en température — le sommet est plus froid et plus sombre. L'ascension se lit dans le vide croissant, conformément à "Le vide rend la lame visible".

### Palette UI

L'UI utilise les couleurs du monde mais avec des valeurs d'opacité et des hex dérivés — pas identiques. Le HUD doit se lire sur Chrome Froid ET Noir Vide selon l'environnement traversé.

| Élément UI | Hex | Notes |
|---|---|---|
| **Texte principal** | `#F0F4FF` | = Blanc Path — toujours sur fond sombre ou N3 |
| **Texte secondaire / labels** | `#8A9199` | Gris moyen dérivé de Chrome Froid désaturé |
| **Bordures HUD** | `#C8CDD4` à 60 % opacité | Chrome Froid semi-transparent |
| **Highlight sélection** | `#00D4E8` | = Cyan Secret — confirme "interactable" |
| **Icônes shop hexagonales** | Contour `#00D4E8` + fill `#0A0A0C` | Distingue catégorie "shop" de "monde" |
| **Notifications / alertes** | `#E8192C` | = Rouge Menace — jamais pour info neutre |
| **Barre de vie** | `#F0F4FF` fill → `#E8192C` fill quand < 25 % | Blanc = sain / Rouge = critique |
| **Fond de panneau shop** | `#1E2228` à 85 % opacité | = Verre Sombre semi-opaque |

**Principe UI** : l'UI ne crée pas de nouvelles couleurs. Elle redistribue les couleurs du monde dans une couche de lecture supplémentaire.

### Colorblind Safety

Les trois signaux sémantiques actifs sont Rouge Menace, Cyan Secret et Blanc Path.

#### Deutéranopie (confusion rouge/vert)

| Signal | Perception | Backup cue |
|---|---|---|
| Rouge Menace | Brun-kaki, contraste luminance maintenu ~4,8:1 | Fente lumineuse horizontale encodée "ennemi" + pulsation 1 Hz + alerte sonore directionnelle |
| Sang | Brun-foncé, tache sombre sur fond clair | Particules splash directionnel — forme du spray reconnaissable |
| Cyan Secret | Bleu-gris, distinct de Rouge Menace | Chanfrein 45° sur surface wall-run + pulse lent 0.5 Hz |

#### Protanopie (insensibilité aux rouges)

| Signal | Perception | Backup cue |
|---|---|---|
| Rouge Menace | Gris-brun, contraste tombe à ~2,1:1 sur Chrome Froid | Fente laser distincte par géométrie + bip directionnel + pulsation. **Option settings** "High Contrast Enemies" → A1 remplacé par `#FF6B00` (orange vif, 5,2:1 sur N2) |
| Sang | Quasi-invisible | Tolérable — le sang est rétrospectif, kill signalé par disparition de la fente laser + son |

#### Tritanopie (confusion bleu/jaune)

| Signal | Perception | Backup cue |
|---|---|---|
| Cyan Secret | Rouge-rose → confusion possible avec Rouge Menace | Distinction géométrique : wall-run = chanfrein 45° (aucun ennemi n'a cette géométrie), crédit = forme arrondie/hexagonale (aucun laser n'a cette forme) |

**Recommandation technique** : prévoir un paramètre Settings "Colorblind mode" qui remplace Cyan Secret par `#FFD700` (jaune-or, 7 500 K équivalent) sans altérer la sémantique. Cette substitution résout tritanopie et protanopie simultanément. Déléguer l'implémentation au `ui-programmer`.

### Règles de composition en plan

#### Règle de l'accent unique

**Maximum un accent sémantique (A1/A3/A4) visible simultanément dans le champ de vision.** Règle absolue, une seule exception (Sang, voir plus bas).

- Si un ennemi (A1) est dans le plan, les repères de chemin (A4) disparaissent ou sortent du champ
- Si un segment secret (A3) est actif, les ennemis ne sont plus visibles dans le même plan — la géométrie secrète est physiquement séparée du chemin de combat
- Si A4 (chemin) est actif, c'est un contexte sans ennemi ni secret

**Implication level design** : les zones secrètes doivent être physiquement hors ligne de vue des zones de combat. Un couloir, un angle, une rupture de géométrie suffisent. Ce n'est pas un post-process — c'est une contrainte de layout.

#### Couleurs non-sémantiques — éclairage runtime

L'éclairage ambiant (températures Kelvin par étage) n'est **pas** considéré comme un accent sémantique. Les colonnes volumétriques blanches-froides de l'État Flow, la haze froide de l'État Secret — ambiance d'état, pas accents de plan. La règle "un accent" s'applique aux couleurs d'objet et de surface, pas à la température globale de scène.

#### Statut du Sang (A2) — exception temporelle

Le Sang ne compte pas dans la règle de composition car :

1. Sa durée est < 1 seconde (splash + fade)
2. Il apparaît exclusivement à l'instant du Kill, pendant lequel Rouge Menace (A1) est déjà en train de disparaître avec l'ennemi — les deux rouges ne cohabitent jamais plus d'une frame
3. Sa fonction est rétrospective (confirmation), non prospective (signal d'action)

**Règle précise** : pendant le frame de kill, A1 (sur ennemi) est remplacé par A2 (sang) — jamais les deux en même temps. Timing : flash blanc (0.05 s) → A2 (0.3–0.8 s) → retour A1 absent (ennemi mort).

---

## 5. Character Design Direction

> **Règle directrice** : *Sans visage, le geste est l'identité.*
> Le joueur ne voit jamais la cyber-ronin en entier. Ce qu'il voit — ses mains, sa lame, ses bottes au sol — doit lire "précision froide, économie de moyens" sans une seule ligne de dialogue.

### Player Character — la cyber-ronin (vue FPS)

#### Mains et gants

| Élément | Spec |
|---|---|
| **Type** | Gants tactiques fins, coupe militaire minimaliste — pas d'exosquelette, pas de plaque de knuckle proéminente |
| **Matériau principal** | Néoprène mat anthracite `#2A2E34` — ni brillant ni satiné. Absorbe la lumière |
| **Couture / surpiqûre** | Une seule ligne de couture dorso-latérale visible — géométrie, pas décoration |
| **Surbrillance chrome** | Arête fine spéculaire sur les articulations des doigts (dos de la main, 2e phalange) — Chrome Froid `#C8CDD4`, épaisseur < 2 px à résolution native. Visible uniquement sous lumière directe |
| **Absence de détails** | Pas de circuits gravés, pas de diodes, pas de logo. Le gant dit "mission", pas "univers" |
| **Test 100 ms** | La main doit lire "gant sombre avec reflet d'arête" — pas "mécanique complexe" |

#### Bras — portion visible

- Manche longue ras du poignet, même matériau que le gant (néoprène mat)
- Couleur : `#1E2228` (Verre Sombre) — légèrement plus froide que le gant, crée une micro-séparation gant/manche lisible
- Pas de marque, pas de logo, pas de texture différente. Un cylindre sombre qui dit "bras"
- La manche s'arrête au bord du champ visuel FPS — jamais l'épaule ni le coude en entier

#### Katana

| Élément | Spec |
|---|---|
| **Lame** | Droite, ratio 1:20 (épaisseur/longueur) — une diagonale absolue |
| **Bicolore** | Dos de lame : mat anthracite `#2A2E34`. Tranchant : Chrome Froid `#C8CDD4` hautement spéculaire — l'arête de lumière est la silhouette lue en 100 ms |
| **Tsuba (garde)** | Rectangle chromé `#C8CDD4`, ratio 1:4 épaisseur/largeur — une barre, pas une fleur |
| **Tsuka (poignée)** | Fût mat, tressage géométrique discret — losanges plats, pas de cordage organique. Couleur : `#1A1C20`, quasi-noir |
| **Habaki (encollure)** | Manchon chromé fin entre tsuba et lame — continuité matériau avec la garde |
| **Saya (fourreau)** | Absent en gameplay. La lame est toujours nue. Jamais de rengainement visible — pas de budget animation pour ça en MVP |
| **Dimensions à l'écran** | Au repos (position basse droite) : lame occupe ≈ 30 % de la hauteur d'écran. Section transversale < 5 % de la largeur d'écran |
| **Test thumbnail** | À 64×64 px : diagonale claire sur fond sombre, lisible immédiatement |

#### Pieds et jambes (visibles en saut)

- **Pantalon** : coupe cargo taillée, noir `#0A0A0C` (Noir Vide) — sans poche ni pli décoratif. Silhouette lisse
- **Bottes** : bottines hautes (mi-mollet), semelle plate. Matériau cuir synthétique mat, `#0F1114`. Zip latéral invisible, pas de lacet, pas de semelle compensée
- **Visibilité** : uniquement le bas de jambe et le pied lors des sauts hauts. Pas d'animation de jambe en marche normale
- **Budget** : 2 BoxMesh + 1 CapsuleMesh, aucun rigging de pied requis

#### Expression du personnage sans visage

| Canal | Direction |
|---|---|
| **Position de repos** | Lame basse, légèrement inclinée vers le sol — pas au centre de l'écran. Le repos est oblique, pas neutre |
| **Sway de marche** | Minimal. Oscillation horizontale < 3° — stiff, pas de bounce. Le mouvement est contrôlé |
| **Alerte** | La main de soutien remonte légèrement vers la garde. Micro-animation 0.2 s, pas de commentaire audio |
| **Après un kill** | 0.15 s de gel des mains avant le retour à la position de repos — le beat de catharsis (Section 2) se lit aussi dans la main |
| **Respiration** | Compression verticale de la vue ± 0.4 % à 0.25 Hz au repos. Absente en sprint |
| **Principe** | Stiff par défaut. Micro-animations rares et courtes — chacune a un rôle mécanique. Pas de fidget, pas d'animation "personnalité" |

### Archétypes ennemis — direction par type

**Règle commune** : le corps de tous les ennemis reste dans la palette Verre Sombre `#1E2228` + Noir Vide `#0A0A0C`. La différenciation de type ne passe **jamais** par la couleur du corps — uniquement par la forme de tête et la signature lumineuse.

#### Grunt Laser (MVP — spec complète)

| Dimension | Spec |
|---|---|
| **Ratio corps** | 3:1 H/L — bloc vertical, épaules légèrement plus larges que les hanches |
| **Silhouette** | Rectangulaire stricte, proche des pylônes corporates — le contraste se révèle au mouvement |
| **Tête** | Hémisphère `#1E2228`, diamètre = 0,35× hauteur du corps |
| **Signature lumineuse** | Fente horizontale unique à mi-tête, Rouge Menace `#E8192C` — largeur = 80 % du diamètre de la tête. Pulsation 1 Hz (luminosité ± 30 %) |
| **Uniforme** | Surface unie mat. Aucun reflet spéculaire sur le corps — contraste avec la lame du joueur |
| **Posture repos** | Debout, bras le long du corps. Rotation lente 15°/s sur Y — scan passif |
| **Posture alerte** | Légère flexion avant du tronc, fente laser orientée vers le joueur. Transition : 0.3 s |
| **Animation cycle** | Idle : rotation lente. Alert : orientation + pulsation accélérée 2 Hz. Attack : laser déclenché. Death : chute rigide, fente s'éteint |
| **Comportement lisible à 8 m** | La fente lumineuse oriente vers le joueur = "il me vise". Rotation sans orientation = "il patrouille" |
| **Budget primitives** | CapsuleMesh corps + SphereMesh tête + BoxMesh plat émissif fente = 3 primitives |

#### Sniper (Tier 2 — direction)

| Dimension | Spec |
|---|---|
| **Ratio corps** | 4:1 H/L — plus mince et plus haut que le grunt |
| **Tête** | Cylindre étroit `#1E2228`, hauteur = diamètre. Viseur vertical lumineux centré, ligne fine `#E8192C`, hauteur = 60 % du cylindre |
| **Signature lumineuse** | Ligne verticale fine pulsante 0.5 Hz (lente — il calcule) |
| **Posture distinctive** | Inclinaison arrière légère, bras levés — position tireuse |
| **Animation distinctive** | Scan lent horizontal, pause sur le joueur — 3 s de ciblage visible avant le tir |

#### Brute (Tier 2 — direction)

| Dimension | Spec |
|---|---|
| **Ratio corps** | 2:1 H/L — plus large que haut. Masse horizontale |
| **Tête** | Cube `#1E2228`, arêtes vives. Deux fentes en V sur les côtés, Rouge Menace — signal binoculaire |
| **Signature lumineuse** | Deux points V, pulsation rapide 3 Hz en charge |
| **Posture distinctive** | Bras légèrement écartés, centre de gravité bas |
| **Animation distinctive** | Pas lourds — décalage vertical du corps à chaque foulée |

#### Drone (Tier 3 — direction)

| Dimension | Spec |
|---|---|
| **Ratio corps** | Octogone plat, hauteur = 0,2× diamètre — disque volant |
| **Pas de tête séparée** | Le corps entier **est** la tête — forme octogonale distinctive du reste |
| **Signature lumineuse** | Anneau Rouge Menace sur le bord extérieur, pulsation lente 0.8 Hz |
| **Posture distinctive** | Hover — oscillation verticale sinusoïdale ± 5 cm, 1 Hz. Seul ennemi non-sol |
| **Animation distinctive** | Rotation lente sur axe Z (tilt) quand il s'oriente — inclinaison 15° vers la cible |

#### Officier (Tier 3 — direction)

| Dimension | Spec |
|---|---|
| **Ratio corps** | 3,5:1 H/L — plus élancé que le grunt, posture droite |
| **Tête** | Trapèze inversé (plus large en haut) `#1E2228`, arête vive au sommet. Pas de fente — silhouette "autorité" |
| **Signature lumineuse** | Ligne d'épaulette Rouge Menace `#E8192C` sur l'épaule droite uniquement — signal latéral asymétrique |
| **Posture distinctive** | Statique, peu de déplacement — il commande. Les grunts se déplacent autour de lui |
| **Animation distinctive** | Geste de bras lent 1×/4 s — signal d'activation des grunts proches |

#### Ordre de production recommandé

| Priorité | Type | Justification |
|---|---|---|
| MVP | Grunt | Core loop complet avec 1 ennemi — valide lecture, shaders, lisibilité |
| Tier 2a | Brute | Masse vs vitesse : enseigne la lecture de taille avant complexité |
| Tier 2b | Sniper | Introduit menace à distance — nouveauté mécanique claire |
| Tier 3a | Drone | Ajoute axe vertical — challenge navigation, forme radicalement différente |
| Tier 3b | Officier | Meta-ennemi, change le comportement des autres. En dernier, quand l'IA de groupe est stable |

### Boss final — direction visuelle

> Pas de détail mécanique ici. Direction uniquement.

| Dimension | Spec |
|---|---|
| **Silhouette** | 2,5× la hauteur du grunt — lisible comme "autre catégorie" sans tutoriel |
| **Forme** | Corps en T inversé — large aux épaules, effilé aux pieds. Rappelle le grunt mais déformé par l'autorité |
| **Matériau** | Chrome poli hautement spéculaire sur l'ensemble du corps — aucune surface mat. Il reflète l'environnement entier, il **est** le miroir de la tour |
| **Signature lumineuse** | Rouge Menace en anneau autour de chaque jointure (épaules, coudes, genoux) — 6 points lumineux vs 1 fente pour le grunt. Quantité = puissance |
| **Principe de lecture** | La spécularité chrome + les 6 points rouges + la taille 2,5× = "boss" en 150 ms |
| **Élément différenciateur** | Seul personnage du jeu avec du chrome sur le corps — aucun ennemi standard n'en a |

### Distinguishability Rules

| Situation | Signal primaire | Signal secondaire | Temps de lecture |
|---|---|---|---|
| **Grunt vs mur décoratif** | Fente lumineuse horizontale à hauteur d'œil (aucun prop n'en a) | Mouvement de rotation lente | < 50 ms |
| **Grunt vs Drone** | Drone : forme octogonale plate + position hovering hors-sol | Grunt : vertical, sol, hémisphère | < 80 ms |
| **Grunt vs cadavre (après kill)** | Cadavre : fente éteinte + corps en position non-debout + absence de pulsation | Sang `#B50F1F` persistant 2 s au sol | < 100 ms |
| **Boss vs ennemi standard** | Taille 2,5× + chrome spéculaire total | 6 points rouges vs 1 fente | < 150 ms |

**Règle absolue** : la fente lumineuse allumée = agent actif. Fente éteinte = inerte (cadavre ou prop). Cette règle binaire ne tolère aucune exception.

### LOD Philosophy

| Distance | Niveau de détail | Contenu visible |
|---|---|---|
| **> 15 m** | LOD 2 — silhouette seule | Forme de tête + signature lumineuse colorée. Aucun détail de surface |
| **6–15 m** | LOD 1 — lecture fonctionnelle | Silhouette + fente lumineuse + pulsation + posture générale |
| **< 6 m** | LOD 0 — full detail | Matériau mat/chrome, coutures, micro-animations |

**Budget polygones par type :**

| Type | LOD 0 | LOD 1 | LOD 2 |
|---|---|---|---|
| Grunt | 200 tris | 80 tris | 20 tris |
| Sniper / Brute / Officier | 250 tris | 100 tris | 24 tris |
| Drone | 180 tris | 60 tris | 16 tris |
| Boss | 600 tris | 200 tris | 48 tris |

**Détails à 2 m** : minimalistes. Pas de micro-textures, pas de normalmaps complexes. La richesse visuelle vient du shader (spécularité, émission), pas de la géométrie.

### Expression et pose style

| Personnage | Direction | Justification |
|---|---|---|
| **Cyber-ronin (joueur)** | **Stiff** — gestes secs, économes. Oscillation < 3°. Transitions rapides sans ease-out prolongé | Le contrôle précis est la lecture émotionnelle |
| **Grunt** | **Mécanique** — rotations par paliers discrets (15°/step), pas de ease. Idle : scan. Alert : lock | Lisibilité de l'état AI en silhouette |
| **Brute** | **Lourd et continu** — transitions lentes (0.5 s), impact visible à chaque pas | Le contraste de tempo informe le joueur du danger avant l'attaque |
| **Sniper** | **Figé avec micro-tremblements** — immobilité parfaite sauf léger shake 0.2 Hz | La patience est lisible |
| **Drone** | **Fluide et sinusoïdal** — seul personnage sans mouvement sec | La fluidité du drone le distingue de tous les ennemis sol |
| **Officier** | **Lent et délibéré** — chaque geste est large, visible à distance | Autorité = économie de mouvement |
| **Boss** | **Stiff mais massif** — comme le grunt, mais chaque mouvement déplace de l'air visuellement | L'amplitude compense la raideur |

### Contraintes de production — rappel

| Règle | Détail |
|---|---|
| **Grunt MVP** | 3 primitives Godot max (CapsuleMesh + SphereMesh + BoxMesh émissif) |
| **Pas de face rig** | Aucun personnage n'a de visage expressif |
| **Pas de fingers rig** | Les mains joueur sont animées en bloc — gant = mesh rigide |
| **4 états d'animation** | Idle / Alert / Attack / Death — suffisant pour tous les types |
| **Saya absente** | Pas d'animation de rengainement. Budget économisé |
| **Animations additives** | La pulsation de la fente lumineuse est un shader animé (émission sinusoïdale) — pas une animation de mesh |

---

## 6. Environment Design Language

> **Règle directrice** : *L'architecture Arasaka ne décore pas — elle oppresse par la géométrie. Le joueur grimpe à travers une machine, pas un décor.*

---

### 6a. Style Architectural Global

#### Synthèse retenue : Brutalisme Corporate Zen

La tour Arasaka n'est pas cyberpunk au sens de Blade Runner 2049 (organique, décadent, humide). Elle n'est pas Mirror's Edge (propre mais joueur-friendly). Elle n'est pas Tadao Ando pur (béton humaniste, lumière méditative).

Elle est la convergence d'un seul postulat : **le bâtiment construit par quelqu'un qui ne pense plus aux humains.**

Concrètement, cela signifie :

- **Du Brutalisme** : masse, répétition, échelle qui écrase. Les murs ne sont pas là pour être beaux — ils sont là pour dire "tu n'es pas à ta place ici". Surfaces larges, modules répétés, aucune ornementation. Le béton brut est un message politique.
- **Du Minimalisme japonais** : économie absolue de moyens. Chaque élément architectural présent a une raison fonctionnelle. L'absence de détail n'est pas une limite de budget — c'est le style. Un mur vide est un mur volontairement vide.
- **Du Corporate dystopique** : pas de cyberpunk esthétisé. Pas de néons, pas de tuyaux exposés vintage. La tour est *propre*. Elle est entretenue. Elle fonctionne parfaitement et c'est ça qui est inquiétant — pas la dégradation, l'efficacité froide.

**Ce que ça exclut explicitement** : tuyauterie exposée, câbles pendants, tags de graffiti, rouille, humidité, fissures dans le béton (sauf étage 5 — voir 6e), affiches déchirées, meubles renversés.

#### Story-by-architecture : la machine qui absorbe l'humain

La tour ne raconte pas la violence — elle raconte l'**effacement**. Plus on monte, plus l'espace se vide. Plus on monte, plus l'échelle grandit par rapport au corps humain. L'architecture dit : *tu n'étais pas prévu dans cette équation.*

**Opérationnel pour le level designer** :

| Principe | Traduction spatiale |
|---|---|
| Oppression par l'échelle | Plafonds > 5 m aux étages 1–2, > 8 m aux étages 3–5. Aucun espace "à taille humaine" au-delà de l'étage 2 |
| Répétition comme cage | Les modules architecturaux se répètent exactement (même largeur de colonne, même espacement). L'environnement est une grille |
| Vide croissant | Densité de props et de géométrie secondaire diminue à chaque étage. L'étage 5 approche du monolithique |
| Absence humaine codée | Pas de bureau individuel lisible, pas de poste de travail avec écrans allumés. Les espaces "de bureau" sont des rangées de surfaces identiques sans trace d'occupation |

---

### 6b. Philosophie des Textures

#### Choix global : Stylized Flat avec émission contrôlée

**Pas de PBR full.** Pas de textures haute résolution à gérer.

Justification : budget solo dev + lisibilité gameplay > fidélité matière. Les matériaux doivent être **identifiables en 100 ms à vitesse de sprint**, pas photographiquement corrects. Un shader flat bien conçu avec une variation de gradient contrôlée donne plus d'information utile qu'une normal map complexe qui clutte la lecture.

#### Béton blanc (Surface N2, Chrome Froid `#C8CDD4`)

| Dimension | Spec |
|---|---|
| **Texture** | Flat. Gradient subtil vertical (1–2 % de variation de luminosité) pour suggérer l'échelle sans texture bitmap |
| **Fissures / impacts** | **Proscrits** sur les étages 1–4. Autorisés uniquement à l'étage 5 (voir 6e). Le béton Arasaka est parfait — c'est un choix narratif |
| **Rayures** | Uniquement sur les arêtes vives exposées au passage (sol, coins de colonne). Implémentation : arête plus sombre en shader edge detection, pas de texture bitmap |
| **Joints de modules** | Ligne horizontale fine `#0A0A0C` (Noir Vide), épaisseur 1–2 px à résolution native. Régulière, périodique — jamais aléatoire |

#### Chrome (Surfaces spéculaires, équipements)

| Dimension | Spec |
|---|---|
| **Type** | Bicolore : zones polies (haute spécularité) + zones brossées (semi-mat) |
| **Zones polies** | Surfaces larges horizontales et verticales principales — réflexion simulée par gradient vertical inversé de luminosité |
| **Zones brossées** | Arêtes, transitions, surfaces fonctionnelles (cadres de portes, rails) — variation horizontale fine, 5–8 % de contraste |
| **Réflexions** | **Baked**, non runtime. En MVP : cubemap statique par étage, pas de screen-space reflections. Suffisant pour lire "metal brillant" |
| **Couleur de base** | `#C8CDD4` highlight / `#8A9199` mi-ton / `#3A3E44` ombre — trois valeurs, pas de texture |

#### Verre (Panneaux, cloisons, baies)

| Dimension | Spec |
|---|---|
| **Type** | Opaque semi-transparent — **pas traversable visuellement en profondeur**. Absorption plutôt que transmission |
| **Couleur** | `#1E2228` (Verre Sombre) à 80–90 % opacité |
| **Reflets** | Reflet spéculaire directionnel unique (source key light) — shader simple, pas de cubemap sur le verre |
| **Rôle gameplay** | Le verre indique visuellement "tu ne passes pas là" sans être un mur de béton. Utile pour construire des faux-raccourcis lisibles à distance |
| **Rôle narratif** | Dans le Verre Sombre, le joueur voit sa propre silhouette. Pas d'implémentation complexe requise — la couleur seule suffit |

#### Métal noir — fond d'étage Serveurs (Étage 3)

| Dimension | Spec |
|---|---|
| **Type** | Strié horizontalement — rainures régulières, espacement 4–6 cm monde |
| **Couleur** | `#1E2228` avec gradient `#0A0A0C` dans les creux des stries |
| **Spécularité** | Zéro sur les creux, micro-spéculaire sur les crêtes (ligne fine `#3A3E44`) |
| **Rôle** | Différencie visuellement l'étage 3 sans changer la palette. Les stries créent une direction visuelle horizontale — renforce la lecture "data center, rangées" |

#### Sol

| Dimension | Spec |
|---|---|
| **Étages 1–2** | Dalles larges. Module 2 m × 2 m. Joint `#0A0A0C` 2 px. Surface polie flat `#C8CDD4` |
| **Étage 3** | Grillagé métallique — `MeshInstance3D` grille fine. Transparence partielle (40 %) pour lire la profondeur sous le sol. Signal "infrastructure" |
| **Étages 4–5** | Monolithique. Pas de joint visible — une seule dalle continue `#C8CDD4`. L'absence de joint dit "tu es dans l'espace privé" |
| **Ratio joint/dalle** | Étages 1–2 : joint = 2 px pour 200 px de dalle (~1 %). Étage 3 : grille = ratio 1:4 barre/vide. Étages 4–5 : ratio zéro |

---

### 6c. Règles de Densité — Props

#### Densité maximale

**3 props non-gameplay maximum** dans le champ de vision typique (90° H, 70° V) à n'importe quel moment de flow. Au-delà, la lisibilité du mouvement est compromise.

Définition d'un "prop non-gameplay" : élément 3D présent dans la scène qui ne sert ni de surface de parkour, ni de repère de navigation, ni de cache d'ennemi, ni de déclencheur de secret.

#### Liste positive (props autorisés)

| Catégorie | Exemples | Règle de placement |
|---|---|---|
| **Colonnes verticales** | CSGCylinder ou BoxMesh étiré Y | Max 1 par 6 m linéaires de mur |
| **Pylônes signalétiques** | Poteau `#1E2228` + panneau horizontal chromé | Toujours au-dessus de la ligne de tête (> 2,2 m sol) |
| **Conduits verticaux** | CylinderMesh `#1E2228`, diamètre 20–30 cm | Uniquement le long des murs, jamais en milieu de salle |
| **Panneaux Arasaka** | Plan mince `#1E2228` avec texte émissif `#C8CDD4` | Au sol : interdits. Sur mur : 1 par couloir max |
| **Cadres de porte / seuils** | BoxMesh encadrant un passage | Nécessaires pour signaler les transitions d'espace |
| **Rails de sécurité** | BoxMesh horizontal très fin, hauteur 90 cm | Uniquement si le vide mortel est à < 3 m |

#### Liste négative (props interdits)

Aucun élément organique ou humain :

- Plantes, végétation, pots
- Meubles identifiables (chaises, bureaux, canapés)
- Objets personnels (tasses, verres, sacs, dossiers)
- Poubelles, corbeilles
- Décoration murale (tableaux, photos, diplômes)
- Câbles ou tuyaux exposés non-architecturaux
- Tout prop avec courbure organique

#### Règle "prop = silhouette utile"

Avant d'ajouter un prop, poser les trois questions suivantes :

1. **Verticalité** : ce prop guide-t-il l'œil vers le haut ou crée-t-il un point de repère d'altitude ?
2. **Identité Arasaka** : ce prop renforce-t-il le vocabulaire corporate (rectiligne, froid, systémique) ?
3. **Lisibilité** : sa silhouette à 8 m est-elle immédiatement non-ambiguë (ni surface de parkour, ni ennemi) ?

Si aucune des trois réponses n'est "oui" : le prop n'existe pas.

---

### 6d. Environmental Storytelling

Le jeu n'a pas de dialogue. La tour parle par ce qu'elle est — et par ce qui y manque.

#### Principes directeurs

**La domination corporate passe par l'échelle et la répétition.** Des murs qui montent à 8 m quand un humain en mesure 1,7 m sont une phrase politique. Les modules identiques répétés 40 fois sur un couloir disent "la tour n'a pas été pensée pour toi, elle a été pensée pour fonctionner."

**L'humanité est absente par conception, pas par accident.** Il n'y a pas de corps, pas de vestiges d'occupation humaine. Cette absence n'est pas post-apocalyptique — c'est architectural. La tour n'a jamais eu de place pour l'humain. Ce qui renforce ce message : les rares traces d'humains qui existent (voir détails signature) sont précises, choisies, et choquantes par contraste.

**L'ascension est une transgression croissante.** Les étages supérieurs ne doivent pas simplement être "plus difficiles" mécaniquement — ils doivent *visuellement* communiquer "tu ne devrais pas être là". Cela passe par l'agrandissement de l'échelle, la réduction des props, et l'utilisation de détails signature (voir ci-dessous) de plus en plus rares et précis.

#### 5 Détails Environnementaux Signature

**1. Panneaux directionnels bilingues asymétriques**
Signalétique Arasaka : caractères japonais serrés (colonne verticale, police sans-serif) + numéros d'étage latins en grand corps à droite. Les caractères japonais ne sont jamais traduits en sous-titre ou tooltip — ils existent, illisibles pour le joueur occidental. Tension culturelle : la tour est pensée par et pour quelqu'un d'autre. Les chiffres latins, eux, sont lisibles — pragmatisme de l'entreprise qui sait que ses agents de sécurité sont globaux.
*Implémentation* : `PlaneMesh` + texture procédurale texte émissif `#C8CDD4` sur fond `#1E2228`. Placé à chaque intersection de couloir, hauteur 2,5 m.

**2. Caméras de surveillance — éteintes**
Présentes à chaque couloir et intersection (boîtier `#1E2228`, objectif `#0A0A0C`), DEL de statut éteinte. Pas de rouge clignotant — la DEL est noire. La surveillance ne passe plus par des yeux humains derrière un écran. Elle est automatisée, distribuée, et le voyant éteint est plus inquiétant que le voyant allumé : *le système ne fait pas d'effort pour te voir. Il te voit déjà.*
*Implémentation* : `SphereMesh` 8 cm + `BoxMesh` support — 2 primitives. Placé en hauteur (> 3 m), toujours orienté vers les axes de passage.

**3. Taches de sang séché aux étages supérieurs (4–5 uniquement)**
Pas de cadavres. Pas d'armes abandonnées. Uniquement des taches plates au sol, couleur `#4A0A10` (sang séché, plus sombre et désaturé que A2 Sang actif). Forme : projection radiale irrégulière, 40–80 cm de diamètre. Positionnées précisément : à l'entrée d'une salle de boss, sous une plateforme haute, au pied d'une chute possible. Message : *tu n'es pas la première à tenter l'ascension. Les autres ne sont plus là.*
*Règle de placement* : jamais au milieu d'un couloir de passage — toujours là où la mort a une géographie logique (chute, confrontation, embuscade).
*Implémentation* : `PlaneMesh` décal flat sur le sol — une primitive, un shader de couleur flat sans émission.

**4. Numérotation de modules gravée dans le béton**
Les panneaux de béton sont numérotés en séquence (petits caractères `#8A9199`, corps 8–10 px à résolution native, coin inférieur droit de chaque dalle). Numérotation systématique, ininterrompue. Ces numéros n'ont aucun rôle de gameplay — ils sont là pour dire que chaque surface de cette tour a été cataloguée, inventoriée, documentée. L'édifice est son propre système de classement. Message : *cette tour se connaît parfaitement. Toi, non.*
*Implémentation* : shader de texte procédural sur le matériau béton — aucune texture supplémentaire requise.

**5. Lignes de conduite au sol — progressivement abandonnées**
Étages 1–2 : lignes de circulation au sol (`#8A9199`, 8 cm de largeur) indiquant les flux de déplacement — comme dans un aéroport ou un datacenter réel. Couloirs aller/retour distincts. Étage 3 : les lignes commencent à s'interrompre sans raison apparente. Étage 4 : une seule ligne au sol, allant dans une direction qui ne correspond à aucune porte visible. Étage 5 : aucune ligne. Message progressif : *les humains étaient guidés jusqu'ici. Au-delà, le guidage s'arrête. La tour n'attendait plus personne.*
*Implémentation* : `PlaneMesh` décal flat au sol, épaisseur 8 cm, matériau flat `#8A9199` sans émission.

---

### 6e. Déclinaison par Étage

> Rappel de règle : la palette (N1/N2/N3/A1–A4) est identique sur tous les étages. La différenciation passe uniquement par la proportion ombre/lumière, la densité d'éléments, et les matériaux dominants.

| — | **Étage 1 — Lobbies** | **Étage 2 — Bureaux** | **Étage 3 — Serveurs** | **Étage 4 — Direction** | **Étage 5 — Sommet** |
|---|---|---|---|---|---|
| **Ambiance narrative** | Façade de légitimité. La tour montre son visage public. Propre, fonctionnel, presque accueillant — et c'est le premier mensonge. | Cage ouverte. Des centaines de postes identiques, personne dedans. L'open space vide est plus inquiétant que le open space plein. | Le coeur de la machine. Infrastructures visibles, chaleur absente, silence de serveur. Tu es à l'intérieur de quelque chose qui pense. | Prestige vide. Les grands bureaux étaient prévus pour quelqu'un d'important. Cet important n'est plus là — ou il n'en a pas besoin. | Tu ne devrais pas être ici. La tour se finit, mais elle ne s'ouvre pas. Elle devient plus grande et plus vide simultanément. |
| **Éléments signature** | Colonnes à base élargie (pyramide inversée) ; signalétique Arasaka bilingue dense ; lignes de flux au sol complètes | Rangées de surfaces de travail identiques vides (BoxMesh) ; faux-plafond suspendu avec grille lumineuse ; cloisons verre semi-opaque | Racks de serveurs stylisés (BoxMesh empilés, LED lignes `#C8CDD4`) ; sol grillagé ; conduits verticaux épais | Grande table de conférence monolithique (unique prop de grande taille) ; baies vitrées sol-plafond ; absence totale de props secondaires | Taches de sang séché précises ; béton fissuré uniquement ici ; ouverture vers ciel gris (plafond absent ou partiel) |
| **Textures dominantes** | Béton lisse `#C8CDD4` ; chrome brossé sur cadres ; sol dalles 2m×2m avec joints | Béton lisse ; verre semi-opaque `#1E2228` pour cloisons ; sol dalles plus petites (1m×1m — sensation de cellule) | Métal strié noir `#1E2228` sur tous les murs ; sol grillagé métallique ; chrome poli sur racks | Béton lisse — qualité perçue supérieure : gradient légèrement plus lumineux en haut de panneau | Béton avec micro-fissures (seul étage autorisé) ; sol monolithique sans joint ; surfaces patinées `#A8ADB4` (légèrement plus froid) |
| **Scale / proportions** | Plafond 5–6 m. Couloirs 4 m de large. Proportions quasi-humaines — fausse normalité | Plafond 4,5 m. Open space sans colonne centrale — un seul volume ouvert oppressant | Plafond 6 m. Allées entre racks : 2 m de large (serré). Verticalité marquée des racks (3–4 m) | Plafond 8–10 m. Pièces moins nombreuses, plus grandes. Chaque salle = un seul objet au centre | Plafond absent ou > 12 m. Un seul espace continu. L'étage final est une arène, pas un couloir |
| **Storytelling spécifique** | Lignes de flux au sol intactes. Caméras éteintes nombreuses. Numérotation module visible. | Aucune chaise aux postes. Les surfaces de travail n'ont pas d'empreinte d'usage. Lignes de flux interrompues à mi-open space. | Quelques LEDs de rack clignotent — les serveurs tournent encore. La tour fonctionne sans personne. Lignes de flux absentes. | Une seule tache de sang, petite, sous la grande table. La première. | Taches de sang multiples, précises. Béton fissuré autour des points d'impact. Pas de mobilier — juste l'espace et les marques. |

---

### 6f. Parkour-Friendliness — Règles Environnementales

#### Sightline minimum avant saut critique

**0.5 seconde de lecture visuelle à vitesse de sprint (≈ 8 m/s = 4 m de preview minimum).**

La trajectoire du saut critique (chute mortelle si raté) doit être visible depuis un point où le joueur peut encore modifier sa trajectoire. Aucun virage à 90° immédiatement avant un saut sur vide ne doit être possible. Le level designer doit toujours avoir un "poste d'observation" de 4 m minimum avant chaque plateforme non-triviale.

**Cas d'exception autorisé** : les secrets de Section 4 (État Secret) peuvent délibérément cacher la réception d'un saut. Mais la zone de décollage doit être signalée par le cyan AVANT que le joueur soit en position de non-retour.

#### Lisibilité des routes — principale vs secrète

**La différenciation ne passe pas par la couleur** (la couleur est réservée aux signaux actifs). Elle passe par trois leviers :

| Levier | Route principale | Route secrète |
|---|---|---|
| **Shape** | Plateforme avec lèvre marquée, large (> 1,5 m), à hauteur de saut naturelle | Plateforme étroite (< 0,6 m), positionnée à hauteur non-intuitive (trop haut ou derrière un obstacle) |
| **Lighting** | Colonne volumétrique verticale au-dessus de la plateforme cible (État Flow — lumière froide) | Rétro-éclairage latéral cyan diffus uniquement quand le joueur approche (État Secret — pas visible à distance) |
| **Composition** | La plateforme principale est dans le tiers central de l'écran lors de l'approche | La plateforme secrète est en bord de cadre, derrière un angle, ou sous une saillie — visible seulement si le joueur "cherche" |

**Règle complémentaire** : les routes secrètes ne doivent jamais partager le même couloir de première approche que les routes principales. Un couloir = une lecture. La bifurcation doit être physique (un angle, un saut, une ouverture dans un mur) — pas juste "à droite ou à gauche dans le même espace ouvert."

#### Zones mortes et frustration

**Une zone morte est une zone où l'environnement cache visuellement une information nécessaire à la décision.** Elle est acceptable si et seulement si :

1. L'échec dans cette zone n'est pas mortel (vide mortel interdit derrière une zone morte non-signalée)
2. La zone morte est dans un contexte de secret volontaire (État Secret actif = le joueur accepte l'incertitude)
3. Le respawn est immédiat et visible depuis la zone morte (le checkpoint est dans le sightline)

**Zones mortes interdites** :
- Derrière un virage immédiat avant un vide mortel sur le chemin principal
- Dans une zone de combat (les ennemis ne peuvent pas être hors du champ de vision par architecture — ils doivent avoir assez de sightline pour que le joueur les détecte avant d'entrer dans leur range)
- Dans le premier tiers de chaque étage (zone d'introduction — la lisibilité doit être maximale)

**Éviter la frustration sans compromettre les secrets** : la règle est que les secrets cachent la *récompense*, jamais le *danger*. On peut cacher une plateforme secrète. On ne peut pas cacher un vide mortel. La mort surprise n'est jamais "légitime" dans CHROME://ASCENT — le joueur doit pouvoir reconstruire mentalement pourquoi il est mort.

---

## 7. UI/HUD Visual Direction

> **Règle directrice** : *"L'interface est une lame affûtée, pas une armure portée."* Chaque élément présent à l'écran doit mériter sa place en moins de 300 ms — sinon il n'existe pas.

> Cette section intègre la direction de l'art-director et les corrections UX validées (proximity-pulse crosshair, dash cooldown screen-space, accessibilité complète).

### Philosophie globale — Diegetic Hybrid

**Choix retenu : screen-space minimal + ancrage diégétique symbolique.**

Le HUD n'est pas diégétique au sens strict (pas de panneaux 3D, pas de reflets sur le katana portant de l'information critique). Raison : à 60+ FPS en parkour, un élément 3D peut sortir du FOV, être masqué par la géométrie, ou créer une rotation caméra pour "lire" l'interface — violation directe du Pilier FLOW.

**Synthèse** : le HUD screen-space adopte le *vocabulaire visuel* du monde diégétique (lignes fines, angles droits, typographie technique monospace) pour que l'interface se lise comme un élément de la tour. L'interface ne s'excuse pas d'être là, elle fait partie de l'architecture.

| Dimension | Décision |
|---|---|
| **Position UI** | Coins inférieurs (bottom-left, bottom-right) + centre pour crosshair. Zone centrale haute libre à 100 % pendant le Flow |
| **Ancrage diégétique** | Terminologie (crédits Arasaka, coordonnées d'étage) et police monospace technique — pas d'éléments 3D |
| **Shop** | Exception : écran interface full-screen avec fond Verre Sombre `#1E2228` à 85 % opacité — seul état où le HUD prend de la place |

### Hiérarchie visuelle du HUD — État Flow

**Principe de présence** : trois niveaux — Permanent / Contextuel / Absent.

#### Niveau 1 — Permanent (toujours visible, poids visuel minimal)

| Élément | Position | Spec visuelle | Justification |
|---|---|---|---|
| **Crosshair** | Centre absolu | Croix fine 1 px, 12×12 px, `#F0F4FF` à 60 % opacité. Dot central 2×2 px à 100 % opacité. **Proximity-pulse** : expand +1 px quand ennemi en range katana, retour immédiat | 4 segments séparés, pas de cercle. Lisible sur fond clair ET sombre. Pulse = cue screen-space de kill-zone sans casser le minimalism |
| **Dash cooldown arc** | Sous crosshair (offset vertical +20 px) | Anneau partiel rayon 20 px, thickness 2 px, `#F0F4FF`, visible en recharge (remplissage en sens horaire). **Absence = dash dispo** | Movement GDD exige indicateur permanent. Position périphérique lit sans regarder — respect du Flow |
| **Compteur crédits** | Bottom-left | Prefix `CR-` dim `#8A9199` + nombre H2 `#F0F4FF`. Police IBM Plex Mono | Décision d'achat au checkpoint dépend de ce chiffre — doit être lisible en tout temps |
| **Indicateur d'étage** | Bottom-right | Format `FLOOR_07` en caption monospace, `#F0F4FF` à 80 % opacité | Sens de progression, change uniquement au passage de checkpoint |

> **Correction WCAG** : le prefix `CR-` `#8A9199` ne doit jamais être la seule source d'information (le nombre principal est en `#F0F4FF`). `#8A9199` est limité aux labels secondaires accompagnant une info primaire en `#F0F4FF`. Jamais de texte fonctionnel autonome en `#8A9199` sur fond Chrome Froid.

#### Niveau 2 — Contextuel (apparaît sur event, disparaît après délai)

| Élément | Trigger | Durée visible | Spec visuelle |
|---|---|---|---|
| **Pickup crédits** | Ramassage | 1 200 ms | `+CR_XX` en H2 `#F0F4FF`, apparaît à la position du pickup puis translate vers le compteur (200 ms ease-out) |
| **Notification critique** | Shield < 25 % (si shield actif) | Permanent jusqu'à résolution | Vignette `#E8192C` à 20 % opacité 2 px bord écran + icône triangle alerte bottom-center |
| **Hit feedback** | Toucher ennemi | 80 ms | Crosshair expand +4 px (segments), retour linéaire. Pas de flash plein écran |
| **Dégât reçu** | Impact sur joueur | 150 ms | Flash `#E8192C` à 15 % opacité en vignette directionnelle (flash côté gauche = impact gauche) |
| **Secret découvert** | Proximité secret | 600 ms | Icône hexagone cyan `#00D4E8` bottom-center 32×32 px, fade-in 100 ms / hold 400 ms / fade-out 100 ms |
| **Checkpoint atteint** | Passage checkpoint | 800 ms | Flash `#F0F4FF` sur contour de l'indicateur d'étage + update texte |

#### Niveau 3 — Absent (design explicite d'absence)

| Ce qui n'existe pas | Raison |
|---|---|
| Barre de vie permanente | One-shot mutuel — une barre vide = mort, une barre pleine = info redondante |
| Minimap | Le level design garantit la lisibilité spatiale (parkour sightline 4 m min.) |
| Flèche de direction / waypoint | L'environnement guide (lumière verticale, verticalité architecturale). Une flèche trahit le Principe "une couleur, une intention" |
| Kill counter permanent | Pollution du vide central. Contextuel uniquement (Kill Moment) |
| Timer | Absent du MVP |
| Inventaire / liste d'upgrades | Le joueur sait ce qu'il a acheté — pas de récapitulatif permanent |
| Death screen classique | Respawn < 1s, fondu noir direct (État 3 de Section 2) |

### Typographie — IBM Plex Mono

**Famille retenue : IBM Plex Mono** (open-source, SIL OFL 1.1, Google Fonts, intégrable en Godot 4 comme `.ttf`).

Justification : monospace technique renforce le vocabulaire "interface de tour corporate Arasaka" sans tomber dans le futuriste stylisé (qui vieillit mal). Alignement naturel des chiffres (crédits, étage). Lisibilité excellente à petite taille.

**Alternatives rejetées** : Eurostile / Bank Gothic (trop "futuriste SF années 90"). Futura (trop géométrique doux).

**Support japonais** : les panneaux signalétiques in-world (Section 6) utilisent le japonais en décoration diégétique. L'UI système n'a **pas** besoin de japonais. Si localisation future : Noto Sans JP (Google Fonts, open-source, pairing monospace-compatible).

#### Hiérarchie typographique

| Niveau | Usage | Taille base | Poids | Tracking | Couleur |
|---|---|---|---|---|---|
| **H1** | Titres shop / écrans pause | 28 px | Medium (500) | +50 | `#F0F4FF` |
| **H2** | Labels section shop, notifications | 18 px | Regular (400) | +30 | `#F0F4FF` |
| **Body** | Descriptions upgrades, texte menu | 14 px | Regular (400) | +10 | `#F0F4FF` |
| **Caption** | Compteurs HUD, indicateurs secondaires | 11 px | Regular (400) | +20 | `#F0F4FF` ou `#8A9199` (labels only) |
| **Micro** | Labels d'icônes (shop) | 9 px | Regular (400) | +40 | `#8A9199` (shop only) |

> Règle : jamais plus de 2 niveaux typographiques simultanément dans un même bloc visuel.

### Iconographie — Style outlined stroke

**Style retenu : outlined stroke uniquement** (ligne seule, pas de fill). Cohérence directe avec le Shape Language : les lignes fines définissent la forme, le vide intérieur appartient au fond.

**Exception documentée** : icônes shop hexagonales avec fill `#C8CDD4` à 20 % opacité (volume subtil réservé à l'état Shop).

#### Règles de construction

| Paramètre | Spec |
|---|---|
| **Stroke width** | 1.5 px à 1× (base). Jamais < 1 px. 2 px uniquement pour icônes critique |
| **Corner radius** | 0 px — angles droits stricts |
| **Padding intérieur** | 4 px minimum entre stroke et bounding box |
| **Taille base HUD** | 24×24 px |
| **Taille shop** | 48×48 px |
| **Taille notification** | 32×32 px |

#### Catégories et codes visuels

| Catégorie | Forme | Couleur stroke | Usage |
|---|---|---|---|
| **Upgrades shop** | Hexagone (exception unique) | `#C8CDD4` par défaut / `#F0F4FF` sélectionnée | Dash, double-jump, wall-run, etc. |
| **Secrets** | Carré orienté 45° (losange) | `#00D4E8` Cyan Secret | Indicateur découverte |
| **Menaces / alertes** | Triangle pointant vers le haut | `#E8192C` Rouge Menace | Alerte shield critique |
| **Navigation / checkpoints** | Chevron vertical | `#F0F4FF` à 80 % | Confirmation checkpoint |

> **Règle d'accessibilité** : chaque icône est lisible par sa seule forme, sans dépendance à la couleur.

### Animation feel — snap par défaut, ease en shop uniquement

**Principe** : les animations UI servent la lecture, pas la beauté. En Flow, l'interface est quasi-statique. En Shop, elle peut respirer.

| État | Animations autorisées | Durée max |
|---|---|---|
| **Flow / Combat** | Cut, fade court | 150 ms absolus |
| **Shop** | Slide, fade, scale subtil, ease | 350 ms |
| **Pause / Settings** | Fade in/out | 200 ms |

#### Specs par type de transition

| Transition | Comportement | Durée | Easing |
|---|---|---|---|
| Apparition élément contextuel | Fade in | 100 ms | Linear |
| Disparition élément contextuel | Fade out | 100 ms | Linear |
| Notification critique | Cut (instantané) | 0 ms | — |
| **Flow → Shop (exception documentée)** | Fond Verre Sombre fade in | 200 ms | Ease-out (deceleration marque la pause) |
| Shop → Flow | Fond fade out | 150 ms | Linear (retour au flow = pas de douceur) |
| Selection d'upgrade shop | Scale 1.0 → 1.04 → 1.0 | 200 ms total | Ease-in-out |
| Hover upgrade shop | Stroke `#C8CDD4` → `#F0F4FF` | 80 ms | Linear |
| Pickup crédits → compteur | Translate Y + fade | 200 ms | Ease-out cubic |

#### Input feedback

| Action | Délai | Réponse | Durée |
|---|---|---|---|
| Hover bouton shop | 0 ms | Stroke brightens | 80 ms |
| Click / confirm | 0 ms | Scale pulse 1.0 → 0.96 → 1.0 | 100 ms |
| Cancel / back | 0 ms | Fade out élément sélectionné | 100 ms |

### Shop UX — règles d'affordance

Le shop présente jusqu'à 8 upgrades (full vision) avec compteur de crédits. L'affordance doit distinguer trois états sans utiliser la couleur rouge (conflit sémantique avec menace) :

| État | Affordance visuelle |
|---|---|
| **Achetable** | Icône hexagone `#C8CDD4` pleine opacité. Prix en accent `#00D4E8`. Hover fait passer stroke à `#F0F4FF` |
| **Inaccessible (prix > crédits)** | Icône hexagone à 40 % opacité. Prix en `#8A9199`. Pas de hover-feedback actif |
| **Déjà acheté** | Icône remplie `#F0F4FF` (fill + stroke). Prix absent. Badge "OWNED" en Micro caption |

> **Conflit résolu** : l'opacité porte l'information "inaccessible" — jamais le rouge, qui reste réservé aux menaces.

### Éléments diégétiques au katana

**Décision : aucun élément d'information critique sur le katana.**

Justification : le katana est en mouvement constant. Y ancrer de l'information critique crée un conflit entre "regarder pour lire" et "regarder pour viser".

**Autorisé** : feedback visuel pur, non-informatif. Émission blade légèrement plus intense sur le Kill Moment (VFX, pas UI). Teinte blade variant cosmétiquement selon les crédits accumulés — **délégué à technical-artist pour spec VFX**.

**Interdit** : chiffres sur la lame, compteur de kills, indicateur shield intégré à la poignée.

### Accessibilité — Settings obligatoires

Toutes les options suivantes doivent être présentes dès le MVP Settings (implémentation triviale en Godot 4, couvre les exigences WCAG 2.1 AA et les standards console) :

| Option | Détail | Priorité |
|---|---|---|
| **Reduced Motion** | Désactive/atténue FOV pulse dash, camera tilt wall-run, slow-mo aérien | Obligatoire MVP (vestibular disorder) |
| **Text Scale** | Slider 80 %–150 % sur tous les textes UI (shop, menu, notifications) | Obligatoire MVP (WCAG) |
| **Colorblind Mode** | Remplace Cyan `#00D4E8` par Jaune-Or `#FFD700` — résout tritanopie + protanopie | Obligatoire MVP |
| **High Contrast Enemies** | Remplace Rouge Menace `#E8192C` par Orange vif `#FF6B00` — couvre protanopie sévère | Obligatoire MVP |
| **Input Remapping** | Remap complet clavier-souris + gamepad (si supporté). Binding critiques = attaque, dash, jump, wall-run, interaction shop | Obligatoire MVP |
| **Subtitle System** | Légendes d'accessibilité pour sons narratifs (terminaux, alertes Arasaka). Ex. `[TERMINAL : alerte sécurité — étage 3]` | Stretch Tier 2 — architecture à prévoir MVP |
| **Crosshair Opacity** | Slider 40 %–100 % sur l'opacité du crosshair (défaut 60 %) | Recommandé MVP |

### Récapitulatif — Checklist UI programmer

| Règle | Spec |
|---|---|
| Zone centrale | 0 élément permanent au-dessus du crosshair |
| Animation Flow max | 150 ms. Linear ou cut uniquement |
| Animation Shop max | 350 ms. Ease autorisé. Transition d'entrée : 200 ms ease-out |
| Stroke icônes | 1.5 px / corner radius 0 |
| Couleur info | Forme + couleur obligatoires (jamais couleur seule) |
| Fond panels | `#1E2228` à 85 % opacité. Pas de blur, pas de drop-shadow |
| Police | IBM Plex Mono. 5 niveaux typographiques max. 2 niveaux simultanés max |
| Taille icône HUD | 24×24 px. Shop 48×48 px |
| Feedback input | 0 ms délai. Réponse visible 80–100 ms |
| Japonais UI système | Non. Diégétique (panneaux 3D) uniquement |
| Dash cooldown | Arc screen-space sous crosshair, rayon 20 px, thickness 2 px |
| Crosshair pulse | +1 px expand quand ennemi en range katana, retour immédiat |
| Shop affordance | Opacité 100 % / 40 % / fill — jamais le rouge |
| Settings accessibilité | Reduced Motion, Text Scale, Colorblind, High Contrast, Input Remapping, Crosshair Opacity dès MVP |

---

## 8. Asset Standards

> **Règle directrice** : *Style Stylized Flat = shaders préférés aux bitmaps. Le solo dev gagne en iteration ce qu'il concède en fidélité photographique.*

Cette section synthétise les préférences art-director et les contraintes techniques Godot 4.6 (technical-artist). Toute tension a été résolue sans compromis visuel majeur.

### Formats de fichiers

| Catégorie | Source (DCC) | Livré à Godot | Justification |
|---|---|---|---|
| **Meshes 3D** | Blender 4.x `.blend` | `.glb` (glTF 2.0 binaire) | Format natif Godot 4, hiérarchie + matériaux + armatures préservés |
| **Textures** | `.png` lossless (16 bits si gradient) | `.png` → BC1 (opaque) / BC3 (alpha) à l'import | Style Flat = peu de textures, les aplats nets souffrent de la compression lossy |
| **Cubemaps chrome** | `.hdr` (Blender HDRI bake) | `.hdr` | HDR source permet à Godot de générer les mips corrects |
| **VFX** | Spritesheet `.png` ou shader pur | `.gdshader` / `.png` | Shader priorité absolue — spritesheet uniquement pour formes organiques impossibles en shader |
| **Audio SFX** | `.wav` PCM 24-bit, 48 kHz | `.wav` (RAM décompressée) | Latence zéro critique pour feedback kill/dash |
| **Audio SFX long / ambiances** | `.wav` master | `.ogg` Vorbis streamé | Économie RAM, latence acceptable |
| **Audio musique** | `.flac` / `.wav` master | `.ogg` Vorbis q7 | Transparent à q7 sur synthés cyberpunk, réduit poids build |
| **Polices** | `.ttf` IBM Plex Mono | `.ttf` importé SDF | SDF = scalable sans aliasing pour Text Scale 80-150 % |
| **UI sprites** | `.svg` préféré | `.svg` ou `.png` | SVG garantit angles droits nets à toute résolution |
| **Scenes** | — | `.tscn` natif uniquement | Aucun import de scène externe |
| **Données gameplay** | — | `.tres` (Resource Godot) | Stats ennemis, prix upgrades, tuning — modifiable sans recompile, diffable Git |

### Naming conventions

**snake_case strict**, conforme GDScript + auto-import Godot. Schéma : `[prefix]_[objet]_[descripteur]_[variante].[ext]`.

| Préfixe | Usage | Exemple |
|---|---|---|
| `env_` | Mesh environnement | `env_pillar_brutalist_a.glb`, `env_conduit_vertical_01.glb` |
| `char_` | Mesh personnage | `char_grunt_body.glb`, `char_player_hands_idle.glb` |
| `tex_` | Texture | `tex_chrome_cubemap.hdr`, `tex_floor_grid.png` |
| `vfx_` | VFX spritesheet ou shader | `vfx_slash_impact_01.png` |
| `sfx_` | Audio SFX | `sfx_katana_slash_01.wav`, `sfx_parkour_land_03.wav` |
| `mus_` | Audio musique | `mus_floor_03_ambient.ogg`, `mus_combat_loop.ogg` |
| `ui_` | UI sprite ou scene | `ui_icon_dash_outlined.svg`, `ui_screen_shop.tscn` |
| `level_` | Scene niveau | `level_floor_01.tscn`, `level_floor_boss.tscn` |
| `data_` | Resource données | `data_enemy_grunt.tres`, `data_upgrade_dash.tres` |

**Règles absolues** : pas de majuscules, pas d'espaces, pas de tirets `-`. Variantes alphabétiques (`_a`, `_b`) pour géométries alternatives, numériques (`_01`, `_02`) pour séries audio. Pas de préfixe projet global — le dossier `assets/` fait office de namespace.

### Résolution des textures — 3 tiers

| Tier | Usage | Résolution cible |
|---|---|---|
| **Tier 1 — Critique** | Skybox, UI plein écran | 2048×2048 |
| **Tier 2 — Standard** | Cubemap chrome, icônes HUD actives, panneaux Arasaka | 1024×1024 |
| **Tier 3 — Décoratif** | Props d'arrière-plan, details géométriques | 512×512 ou **shader pur préféré** |

**Règle d'or** : si un asset peut être rendu par un shader gradient plutôt qu'une texture bitmap, c'est le shader qui prime. La texture est l'exception.

### LOD — environnement (complément à Section 5)

Assets nécessitant LOD : colonnes structurelles répétées, pylônes/conduits visibles sur 20 m+, panneaux Arasaka étages 4-5.
Assets sans LOD : props proches ou uniques (terminal shop), surfaces planes (géométrie déjà minimale).

| Niveau | Seuil distance | Détail conservé |
|---|---|---|
| **LOD0** | 0–12 m | Silhouette complète + détails orthogonaux lisibles |
| **LOD1** | 12–30 m | Silhouette principale, détails supprimés |
| **LOD2** | 30 m+ | Proxy box ou quad billboard |

**Priorité** : les seuils doivent garantir qu'aucun switch LOD n'est perceptible à vitesse de sprint.

### Performance budgets (Godot 4.6 — GTX 1060 baseline, 60 FPS min / 120 FPS visé)

#### Polygones

| Catégorie | Max tris/instance | Max tris simultanés à l'écran |
|---|---|---|
| Personnages ennemis | 600 (boss LOD0) | 5 000 (8 grunts LOD0 + 2 LOD1) |
| Joueur (mains + lame) | 400 | 400 |
| Props environnementaux | 50 | 2 000 (40 instances via MultiMesh) |
| Décor de fond | 80/module | 4 000 |
| Particules VFX | N/A (billboard) | 200 quads actifs |
| UI | 0 tris 3D (CanvasItem uniquement) | — |
| **Total scène worst-case (étage 3)** | — | **~12 000 tris** |

#### Draw calls

| Catégorie | Max | Stratégie |
|---|---|---|
| Personnages | 24 (3/ennemi × 8) | Matériaux partagés par type |
| Environnement | 20 | `MultiMeshInstance3D` sur modules répétés ≥ 8 |
| VFX actifs | 8 | 1 draw call/GPUParticles3D |
| UI | 4 | Atlas partagé |
| Éclairage | 4 (OmniLight3D / SpotLight3D max) | Au-delà → bake en `LightmapGI` |
| **Total scène** | **60 draw calls max** | Marge pour systèmes non-art |

> **Règle pratique** : si `RenderingServer.get_rendering_info()` dépasse 60 draw calls, investiguer. Sur GTX 1060 Forward+, dégradation vers 200 draw calls.

### VRAM budget — 512 MB alloués

| Catégorie | Budget | Format |
|---|---|---|
| Textures environnement (1 étage) | 64 MB | BC1/BC3 |
| Textures personnages | 16 MB | BC1 (256×256 max par type) |
| Cubemaps chrome | 24 MB | BC1 256×256 × 6 faces × **1 actif** |
| VFX textures (atlas 512×512) | 8 MB | BC3 |
| UI atlases (atlas 512×512 unique) | 4 MB | RGBA8 non-compressé |
| Polices (subset ASCII + Latin Extended) | 2 MB | Bitmap cache SDF |
| Shader PSO cache (D3D12) | ~32 MB | — |
| **Total worst-case** | **~150 MB** | Marge 362 MB |

**Politique cubemaps** : **1 cubemap actif en VRAM** + 1 en préchargement RAM (transition au shop). Les étages 1-3 partagent un cubemap générique (tour monolithique, reflets similaires) — les étages 4-5 ont chacun leur cubemap dédié.

### Material slot counts et instancing

| Règle | Valeur |
|---|---|
| Matériaux max par mesh | 2 (exceptionnel : 3 pour le boss) |
| Matériaux uniques totaux en scène | 12 max |
| Shaders uniques simultanés | 8 max (éviter PSO cache lourd) |
| GPU instancing | Obligatoire pour toute géométrie répétée ≥ 8 instances |

**GPU instancing non-négociable** : colonnes, dalles sol, caméras surveillance, racks serveurs étage 3, lignes de conduite, corps d'ennemis (fente émissive = mesh séparé non-instancé car pulsation `TIME`-offset par instance).

### Shader complexity budget

| Paramètre | Limite | Notes |
|---|---|---|
| Instructions / fragment shader | 128 | Respecté si pas de boucle non-bornée |
| Samplers / shader | 4 | 0-1 en pratique (style flat) |
| Boucles | Bornées uniquement (count constant) | Les boucles dynamiques cassent l'optimisation GPU |
| Texture lookups dans vertex shader | Éviter | Coût élevé, rarement nécessaire |
| **Tessellation** | **Interdit** | Non supporté Mobile Renderer — bloque portage futur |
| **Geometry shaders** | **Interdit** | Déprécié Vulkan. Utiliser compute shader si nécessaire |
| Overdraw | Max 2× par pixel (4× acceptable sur VFX kill) | Style flat = overdraw naturellement bas |

### Validation des concerns Section 6

| Concern | Overhead estimé | Résolution |
|---|---|---|
| Sol grillagé étage 3 (40 % transparence) | 8-12 % frame time géométrie étage 3 | **Alpha-clip** (`ALPHA_SCISSOR_THRESHOLD`) obligatoire — pas alpha-blend. Si > 10 %, simplifier pattern |
| Caméras surveillance (15-30/étage) | 0 % avec instancing | `MultiMeshInstance3D` **non-négociable** (2 primitives → 2 draw calls quel que soit le count) |
| Numérotation gravée sur chaque dalle | +20 instructions fragment shader | Shader procédural acceptable (< 5 % fragment time). Fallback : atlas 256×256 si > 80 instructions |
| 5 variations lignes sol | 0 overhead | 1 shader + `instance_custom_data` par instance |
| Fissures béton étage 5 | < 1 % | Shader procédural préféré, décal mesh en fallback |
| Cubemap par étage | 120 MB si 5 simultanés — **inacceptable** | 1 actif + 1 préchargement. Étages 1-3 partagent cubemap générique |
| Particules sang slow-mo kill | 200 quads × 8 kills potentiels | Budget **par kill event**, pas simultané. Lifetime 0.8 s → terminées avant next kill en flow normal |

### Import constraints Godot 4.6 — paramètres recommandés

**Meshes glTF** :

| Paramètre | Valeur |
|---|---|
| Meshoptimizer compression | Oui (activé) |
| Skin/bones limits | 0 (primitives assemblées) |
| Morph targets | Exclus |
| LOD generation | Manuel (`lod_bias` / `LODGroup`) — budgets Section 5 précis |
| Shadow mesh | Simplifié (LOD2 comme shadow caster) |
| Lightmap UV | UV2 généré à l'import si `LightmapGI` |

**Textures PNG** :

| Paramètre | Valeur |
|---|---|
| Compression VRAM | BC1 / BC3 automatique |
| Mipmaps | Oui sur monde 3D, Non sur UI |
| Anisotropy | 4× max |
| Taille max | 256×256 personnages, 512×512 décors |
| sRGB | Oui color, Non data |

**Polices TTF** :

| Paramètre | Valeur |
|---|---|
| Subset | ASCII + Latin Extended (Unicode 0000–024F) — exclure japonais UI système |
| Rendu | SDF (Signed Distance Field) — scalable pour Text Scale accessibilité |
| Tailles bakées | 16 px base (caption) à 32 px (H1) |

### Export philosophy

**Meshes** :
- Triangulation forcée à l'export Blender (évite surprises n-gons)
- Animations dans le `.glb` du personnage (pas de fichier séparé au MVP)
- Armatures incluses pour personnages uniquement

**Audio** :
- Normalisation SFX : **-12 LUFS**
- Normalisation musique : **-16 LUFS** (norme streaming)
- SFX : mono par défaut (spatialisation par `AudioStreamPlayer3D` Godot)
- Musique : stéréo (synthés cyberpunk utilisent le champ stéréo)

### Pipeline handoff

```
Blender 4.x → Export .glb/.png/.wav → assets/[catégorie]/ → Import Godot 4.6 → Scène .tscn
```

**Structure dossiers** :

```
assets/
├── meshes/        # .glb — env/, char/, props/
├── textures/      # .png, .hdr — tier1/, tier2/, tier3/
├── audio/
│   ├── sfx/       # .wav
│   └── music/     # .ogg
├── ui/            # .svg, .png
├── fonts/         # .ttf (IBM Plex Mono)
└── resources/     # .tres
```

### Self-review solo dev (avant intégration)

Checklist à passer avant chaque asset intégré :

1. **Palette** : aucune couleur hors palette approuvée (N1/N2/N3 + A1–A4)
2. **Silhouette** : lisible en silhouette noire sur fond blanc (test Photoshop/Krita rapide)
3. **Orthogonalité** : aucune diagonale non intentionnelle (Section 3)
4. **Naming** : respect du schéma snake_case avant import
5. **Shader vs texture** : si un shader suffit, refuser la texture bitmap

### Règle de démarrage MVP

**Commencer avec `StandardMaterial3D`. Migrer vers shaders custom section par section en validant le frame time à chaque étape.** Le risque solo dev n'est pas la performance — c'est la difficulté de debug de shaders procéduraux complexes sans expérience GPU. L'itération rapide prime sur la fidélité visuelle jusqu'au Tier 2.

---

## 9. Reference Direction

> **Cette section n'est pas une liste de préférences culturelles. C'est un outil de discrimination visuelle.**

Chaque référence cible un problème précis de production. Avant de valider un asset, un shader, une composition ou un timing, le concept artist, le level designer et le shader-specialist doivent pouvoir pointer vers la référence qui justifie le choix — ou qui l'interdit.

**Règle d'usage** : si un élément visuel ne peut pas être relié à une référence ci-dessous, il n'appartient pas à CHROME://ASCENT. L'absence de justification est un signal de rejet, pas d'approbation.

### 1. Mirror's Edge (DICE, 2008) — Jeu

**Ce qu'on prend** : la stratégie de contraste primaire/secondaire — un chromatisme chaud (rouge Faith) sur un monde quasi-monochrome blanc. Le joueur *lit* l'espace parce que la gamme d'accents est réduite à un seul ton. Dans CHROME://ASCENT : Sang `#B50F1F` et Rouge Menace `#E8192C` héritent de cette règle de lisibilité par contraste maximal sur fond neutre. Extraire aussi : la géométrie architecturale sans ornement des toits — surface plate, arête nette, pas de détail texturé. Applicable directement aux étages 1-3.

**Ce qu'on rejette** : la lumière naturelle. Mirror's Edge joue l'extérieur, le soleil, la saturation bleue du ciel. CHROME://ASCENT est intérieur, artificiel, vide. Pas de gradient ciel, pas de lumière volumétrique chaude, pas d'open space aérien.

**Rôle dans CHROME://ASCENT** : référence primaire pour Section 4 (Color System) et Section 6 (Environment). Sert de test de lisibilité — si un corridor ne passe pas le test Mirror's Edge (accent lu à distance, espace décodable en 250 ms), la composition est à retravailler.

### 2. Tadao Ando — Architecture béton (1970–présent)

**Ce qu'on prend** : la façon dont Ando traite la lumière artificielle dans le béton — une source unique, linéaire, qui révèle la texture de la surface sans la saturer. Chez lui, l'éclairage *est* la composition, pas un ajout décoratif. Dans CHROME://ASCENT : les strips LED froids (couloirs d'étages 2-5) doivent se comporter comme des incisions lumineuses dans la géométrie, pas comme de l'ambiance diffuse. Extraire aussi : la règle des proportions — Ando utilise des modules de 90 cm répétés pour créer une sensation de vastitude à budget mesuré. Équivalent direct pour notre grid Godot : répétition stricte du module 4×4 u dans toutes les surfaces corporates.

**Ce qu'on rejette** : la chaleur spirituelle de ses chapelles (Church of the Light, etc.). Ando travaille souvent la grâce et le silence méditatif avec une lumière presque divine. CHROME://ASCENT est froid, corporate, indifférent. La lumière ne réconforte pas — elle expose.

**Rôle dans CHROME://ASCENT** : référence non-jeu centrale pour Section 6 (Environment) et Section 2 (Mood & Atmosphere). Utile chaque fois qu'un level designer hésite sur le placement d'une source lumineuse ou la proportion d'un couloir. *"Est-ce qu'Ando signerait cette ligne ?"* est une question de production légitime.

### 3. Ghost in the Shell (Mamoru Oshii, 1995) — Film d'animation

**Ce qu'on prend** : les compositions à point de fuite central dans les espaces verticaux — les couloirs de l'immeuble Puppet Master, les puits de ventilation, les ascenseurs. Oshii aligne systématiquement l'axe de symétrie sur la profondeur de champ pour signifier une architecture *qui engloutit*. Dans CHROME://ASCENT : tout couloir d'ascension (surtout étages 4-5) doit tester cette composition. La machine absorbe le joueur vers le haut — la symétrie en renforce l'inévitabilité. Extraire aussi : le comportement de la caméra lors des transitions état/espace — Oshii coupe *après* l'action, pas pendant. Le cut est propre. Équivalent : animation de respawn (Section 2, État 3) — écran noir court, pas de transition fluide organique.

**Ce qu'on rejette** : la palette humide d'Oshii. Hong Kong chez lui est pluvieux, réfléchissant, saturé de reflets sur asphalte mouillé. CHROME://ASCENT est sec, intérieur, sans pluie ni surface réfléchissante organique. Pas de puddles, pas de wet look, pas d'aberration chromatique VHS-inspirée.

**Rôle dans CHROME://ASCENT** : référence pour les compositions de level design verticaux (Section 6) et le timing d'animation/cut (Section 2). Le shader-specialist peut s'y référer pour la **négation** d'effets — pas d'aberration chromatique, pas de bloom doux, pas de halo chaud.

### 4. Ghostrunner (One More Level, 2020) — Jeu

**Ce qu'on prend** : un élément précis et non visuel en apparence — le **timing de feedback hit**. Dans Ghostrunner, la mort ennemie est confirmée par un flash blanc d'une frame + son impact sec avant que le corps n'amorce la chute. Ce décalage de 1 frame est ce qui rend le katana *crédible* sans gore. Dans CHROME://ASCENT : le flash d'impact `#F0F4FF` sur Section 2 doit respecter ce timing — 1 frame d'émission max, puis le Chrome Froid reprend. Extraire aussi : la position de caméra FPS basse (eye level ~1,55 m virtuel, pas 1,75 m) — cela exagère la verticalité des espaces et rend les ennemis plus menaçants par plongée légère.

**Ce qu'on rejette** : la densité d'effets visuels. Ghostrunner utilise des particules abondantes, des trails de lame saturés, des HUD très présents avec effets glitch. CHROME://ASCENT est plus pauvre en effets — le vide est la règle. Pas de particle trail permanent sur la lame, pas de glitch esthétique sur le HUD, pas de surcharge d'informations écran.

**Rôle dans CHROME://ASCENT** : référence de production pour Section 5 (Character), timing VFX (kill feedback), et position caméra FPS. Le technical-artist doit consulter cette référence pour calibrer la durée des effets d'impact — **Ghostrunner est le plafond en densité, CHROME://ASCENT est en dessous.**

### 5. Neri Oxman — Installations et design de matériaux (2007-2019)

**Ce qu'on prend** : **non l'esthétique organique d'Oxman** (contre-identité directe), mais sa méthode de répartition de la complexité. Dans ses œuvres, la complexité maximale se concentre en un point précis, et tout le reste est plan nu. Dans CHROME://ASCENT : cette règle structure les **points de détail signature** (Section 6 — 5 détails par scène). Le détail d'accroche (logo Arasaka, tache de sang, conduit signalétique) est l'équivalent de son "nœud de complexité" — tout autour est délibérément vide. Extraire : la **proportion 1/7**. Chez Oxman, environ 1/7 de la surface porte la complexité. Dans nos scènes : **surface active ≤ 14 % du champ visible**. Les 86 % restants appartiennent au Noir Vide ou au Verre Sombre.

**Ce qu'on rejette** : l'organique, le biomimétisme, les formes fluides. Rien de courbe dans CHROME://ASCENT qui ne soit un conduit technique (câble, tuyau). Oxman est la **contre-référence morphologique** — on emprunte sa loi de distribution, pas ses formes.

**Rôle dans CHROME://ASCENT** : référence de composition pour concept artists et level designers lors du placement des détails signature. Sert de règle-mètre : **si plus de 14 % de la surface porte un détail actif, la scène échoue le test Oxman.**

### Comment utiliser cette section

Cette liste est **close à 5 références**. Elle ne doit pas grandir sans décision explicite de l'Art Director.

- **Pour les concept artists** : chaque illustration de scène doit annoter en marge quelle(s) référence(s) justifient les choix de composition, lumière et palette. Une composition sans ancrage = révision avant validation.
- **Pour les level designers** : les références 2 (Ando) et 3 (Oshii) gouvernent la proportion et la verticalité des espaces. Tester chaque couloir d'ascension contre ces deux points de fuite avant de soumettre un layout.
- **Pour le shader-specialist** : la référence 1 (Mirror's Edge) définit le comportement des accents. La référence 4 (Ghostrunner) définit le plafond de densité des effets. Tout shader soumis doit passer sous ce plafond.
- **Outil de rejet** : si un asset peut être justifié par une référence **non listée** ici (Blade Runner néon, Cyberpunk HUD glitch, Akira ruelle organique), c'est un signal que l'asset diverge de l'identité établie. Remonter à l'Art Director avant production.
