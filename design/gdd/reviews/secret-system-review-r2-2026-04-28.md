# Secret System — Design Review r2 fresh

**Date** : 2026-04-28
**Verdict** : **NEEDS REVISION (r3 ciblée — scope XS/S)**
**Reviewer** : `/design-review --depth full` (4 spécialistes adversariaux + senior synthèse)
**Document reviewé** : `design/gdd/secret-system.md` r2 (845 lignes)
**Re-review de** : `secret-system-review-r1-2026-04-27.md` (3 BLOCKING résolus)

---

## Specialists consulted

- `game-designer` (Player Fantasy ARTISAN, anti-énigme, replay value)
- `systems-designer` (contracts cross-system, edge cases, formulas, idempotence)
- `qa-lead` (AC quality, test evidence, regression coverage)
- `level-designer` (authoring contract, pacing, spatial design, tooling)

Senior verdict synthèse : adjudication directe (convergences claires).

---

## Prior r1 Resolution Verification (3 BLOCKING)

| Blocker r1 | Statut r2 | Verdict cross-specialist |
|---|---|---|
| **B-1** Contrat Checkpoint unilatéral (`restore_collected_secrets` direction) | ⚠️ PARTIALLY RESOLVED | Verbe renommé `inject_collected_secrets` correct ; [GATE r2 B-1] visible 5 endroits ; AC-SEC-12/33 PENDING. **Mais** R-SEC-10 décrit simultanément 2 chemins (PULL `get_collected_secrets()` + PUSH `inject_collected_secrets`) sans précédence définie → ambiguïté implémentation NB-SEC-1. |
| **B-2** `instance_id` invalide cross-étage | ✅ RESOLVED | R-SEC-16 ajoutée, invariant clair, cas légitimes/interdits documentés, propagation Level r5 + VFX GDD futurs. Caveat mineur : pas de mécanisme détection runtime mais accepté MVP. |
| **B-3** Tuning Knobs non data-driven | ✅ RESOLVED | `secret_constants.gd` créé avec snippet GDScript `class_name SecretConstants extends RefCounted`, AC-SEC-NEW lint statique. Caveat NR-SEC-2 sur grep StringName `&"…"` vs `"…"`. |

**Conclusion B-1..B-3** : 2 résolus solidement, 1 partiellement (problème de coexistence pull/push qui réémerge en NB-SEC-1).

---

## Dependency Graph

| Dépendance déclarée | Existe ? | Statut |
|---|---|---|
| `credit-economy-system.md` | ✅ Designed r2 | R-SEC-08 SYNC ↔ Credit Rule 9 cohérent |
| `level-system.md` | ✅ Designed r3/r4 | Cohérent ; LAYER_INTERACTIVE=5 référencé sans citer ADR-0008 (NR-SEC-5 hérité r1) |
| `state-machine` (GSM) | ✅ Designed r1 | Pull pattern OK, GSM r2 amendement Secret consumer recommandé (non-bloquant) |
| `save-load-system.md` | ✅ Designed r1 | Tier 2+ persistence cohérent (R-SAV-3) |
| `checkpoint-respawn-system.md` | Not Started | **[GATE r2 B-1]** correctement posé ; OQ-SEC-1 trace |
| `audio-system` | Designed r2.1 | Bus `SECRET_COLLECT` absent → amendement r2.2 RECOMMENDED (gate Audio non bloquant `/create-epics`) |
| `vfx-system` | Not Started | Glow lure spec attendue VFX GDD futur |
| `hud-system.md` | ✅ Designed r1 | Notification `secret_found_pulse` pull pattern OK |
| ADR-0008 (LAYER_INTERACTIVE = 5) | ✅ | Citée implicitement, non listée §Dependencies (NR-SEC-5) |

---

## Required Before Implementation (NEW BLOCKING)

### NB-SEC-1 — Ambiguïté pull/push hydratation Checkpoint sans AC de coexistence [BLOCKING — 2 specialists agree]

**Sources** : `[systems-designer NB-1+NB-2]` + `[qa-lead NB-1]`

**Fichier** : `secret-system.md` R-SEC-10 l.125-137 ; AC-SEC-12 l.[gate] ; AC-SEC-33 l.[gate].

**Problème** : R-SEC-10 décrit **deux chemins simultanés** d'hydratation du dictionnaire `_collected_secret_ids` :
1. **PULL** : Secret appelle `checkpoint.get_collected_secrets()` à `level_active` (ligne 132)
2. **PUSH** : Checkpoint appelle `Secret.inject_collected_secrets(ids)` au moment du restore (ligne 133)

Aucune des deux formulations ne précise :
- Lequel est canonique MVP, lequel est alternative/fallback
- Si les deux co-existent : quel ordre de précédence ?
- Que se passe-t-il si `inject_collected_secrets` est appelé AVANT `level_active` puis Secret PULL re-peuple → double-écriture (idempotente sur `Dictionary[int, bool]` mais sémantiquement ambiguë)
- Si `inject_collected_secrets` est appelé APRÈS `level_active` (race) → comportement non spec

AC-SEC-12 teste uniquement le PULL. AC-SEC-33 teste uniquement le PUSH. **Aucun AC ne couvre la coexistence** ou la priorité. Risque concret : implémenteur Secret choisit PULL, implémenteur Checkpoint choisit PUSH → intégration cassée.

**Fix requis** :
1. R-SEC-10 expliciter : **PULL = chemin canonique MVP** (cohérent avec "Secret est owner de son état"), **PUSH = chemin réservé Tier 2+ Checkpoint-initiated fast-restore**
2. Ajouter AC-SEC-NB-1 BLOCKING : `GIVEN Checkpoint appelle inject_collected_secrets([id_1, id_2]) ET level_active reçu ensuite, WHEN les deux mécanismes s'exercent, THEN état final _collected_secret_ids = union (pas surécrasement)`
3. Soit retirer `inject_collected_secrets` de la surface API MVP (relegated Tier 2+) et supprimer AC-SEC-33

---

### NB-SEC-2 — `CollisionShape3D.disabled = true` sur volume : silent Pillar 4 failure non couvert [BLOCKING — 4 specialists agree]

**Sources** : `[systems-designer NB-3]` + `[qa-lead NN-1]` + `[game-designer R-r2-3]` + `[level-designer R-LD-R3]`

**Convergence forte 4/4** — héritage r1 EC-SEC-MISSING-1 non adressé.

**Problème** : un `SecretCollectVolume_NN` peut être posé dans la scène en respectant tous les knobs (Area3D, layer 5, lure adjacent, hauteur ≥ 2 m, distance lure-volume ≥ 5 m) MAIS avec son `CollisionShape3D` désactivé (`disabled = true`). Conséquence : Secret System connecte le signal `body_entered` lors de `level_active`, mais le callback ne fire **jamais** — le volume est inerte.

**Pillar 4 cassé silencieusement** : le joueur voit le lure brillant, atteint la zone, ne récupère rien — promesse de retour brisée sans message d'erreur ni warning.

R-SEC-13 (validation lifecycle) valide `slot.collect_volume is Area3D` et `layer 5` mais **pas l'état des shapes internes**.

**Fix requis** :
1. R-SEC-13 ajout validation : `slot.collect_volume.get_children().filter(func(c): return c is CollisionShape3D and not c.disabled).is_empty()` → `push_warning("SecretSystem: volume %s a zéro CollisionShape3D active — body_entered ne firra jamais" % slot.collect_volume.name)` + connexion quand même (volume reconfigurable runtime)
2. AC-SEC-NB-2 ADVISORY STATIC : lint Level vérifie au build qu'aucun `SecretCollectVolume_NN` n'a `CollisionShape3D.disabled = true` non-justifié → push_warning si trouvé
3. (Optionnel) AC-SEC-NB-2 BLOCKING runtime si push_warning grep capture activé

---

### NB-SEC-3 — AC-SEC-25 `is_physics_processing()` invalide en GUT headless [BLOCKING]

**Source** : `[qa-lead NB-3]`

**Fichier** : `secret-system.md` AC-SEC-25.

**Problème** : AC-SEC-25 prétend vérifier émission "depuis callback physique main thread" via `assert(is_physics_processing() == true)`. En GUT headless, `body_entered` est simulé par appel direct au callable — `is_physics_processing()` retournera systématiquement `false` (pas dans un vrai `_physics_process`). **L'AC est non-testable tel quel** → faux pass garanti ou échec systématique.

**Fix requis** : reformuler AC-SEC-25 :
- Supprimer assertion `is_physics_processing()`
- Remplacer par : assert connexion `body_entered` établie avec `flags=0` (déjà partiellement AC-SEC-02)
- Ajouter assertion émission SYNC via spy ordre des appels dans même call stack
- La garantie "main thread physics step" est propriété infrastructure Godot non testable headless ; renvoyer vers test integration scene tree (ADVISORY MANUAL séparé) si nécessaire

---

### NB-SEC-4 — AC-SEC-18 mécanisme de test overlap non viable en GUT headless [BLOCKING]

**Source** : `[qa-lead NB-2]`

**Fichier** : `secret-system.md` AC-SEC-18.

**Problème** : AC-SEC-18 prétend tester EC-SEC-09 (joueur dans volume au moment de `level_active`) en simulant "overlap pendant transition". En GUT headless sans scene tree réel, **impossible de maintenir un `body_entered` callback suspendu** pendant l'exécution de `level_active`. Le test appellera les callbacks séquentiellement, jamais en vrai overlap → faux pass systématique.

**Fix requis** : reformuler AC-SEC-18 BLOCKING AUTO :
> `GIVEN Secret System en phase ACTIVE avec slot_A connecté, WHEN level_active (nouvel étage) reçu, THEN R-SEC-11 déconnecte slot_A AVANT de connecter les slots du nouvel étage (séquence vérifiable par espion d'ordre d'appel).`

EC-SEC-09 overlap réel → AC-SEC-NB-4 ADVISORY MANUAL séparé (test sur scène réelle, sign-off lead).

---

### NB-SEC-5 — Distribution spatiale intra-étage non contrainte [BLOCKING — level-designer perspective]

**Source** : `[level-designer R-SEC-LD-B1]`

**Fichier** : `secret-system.md` §Tuning Knobs §Authoring + Level F7 cross-ref.

**Problème** : Level F7 contraint le **nombre total** de secrets par étage (≥ 3, plafond 5) mais **pas la distribution interne**. Configurations conformes au GDD mais cassant Pillar 4 :
- 3 secrets dans salle 1, zéro dans salles 2-5 (frontload — tue découverte progressive)
- 1 secret par salle pendant 3 salles, 0 dans 2 dernières (creux fin d'étage)
- 3 secrets all T1 accessibles sans capability dans étage qui possède wall_run (sous-utilisation moveset → "promesse de retour" Player Fantasy §29 vide)

**Fix requis** : ajouter §Tuning Knobs §Authoring (ou délégué Level r5 §Authoring Guidelines avec cross-ref dans Secret) :
- `MAX_SECRETS_PER_ROOM = 1` (éviter cluster dans une seule salle)
- Au moins 1 secret avec `required_ability` non-disponible au premier passage (créer "promesse de retour" Pillar 4)
- Distribution recommandée : 1 secret tiers début / 1-2 médian / 1 fin (escalade perçue)
- AC STATIC correspondant dans lint Level (étend AC-SEC-41..45)

**Note** : ce fix peut vivre dans Secret GDD OU dans Level GDD r5 §Authoring Guidelines. Ce qui compte : la règle existe quelque part. Recommandation : Secret GDD §Tuning Knobs §Authoring (proximité avec autres règles authoring secret).

---

### NB-SEC-6 — `MIN_LURE_TO_VOLUME_DISTANCE` ne garantit pas un défi de mouvement [BLOCKING — level-designer perspective]

**Source** : `[level-designer R-SEC-LD-B2]`

**Fichier** : `secret-system.md` §Tuning Knobs l.452-453.

**Problème** : `MIN_LURE_TO_VOLUME_DISTANCE = 5.0 m` mesure distance euclidienne, pas défi de traversée. Configurations conformes mais anti-Pillar 4 :
- Lure 6 m horizontal couloir plat → marche directe
- Lure 8 m derrière mur avec ouverture latérale → contournement piéton
- Volume à exactement 2.0 m hauteur → simple saut sans dash

R-SEC-01 (Overview l.11) promet "chaque cachette est un défi d'exécution" — mais aucun knob ne garantit qu'un **obstacle de mouvement** soit interposé.

**Fix requis** : §Tuning Knobs §Authoring formaliser règle :
- Obligation : élément de géométrie physique (mur, gap, plateforme hauteur) interposé entre chemin nominale et volume
- Knob proposé : `REQUIRED_MOVEMENT_CHALLENGE_TYPE : {height_gap, wall_gap, timed_sequence, multi_element}` (authoring tag sur `SecretLureMarker_NN`, lint-only)
- Lint Level :
  - Si `required_ability == "none"` ET `tier == 1` : delta hauteur ≥ `MIN_VOLUME_HEIGHT_ABOVE_FLOOR` sur trajet (déjà partiel)
  - Si `required_ability != "none"` : capability nécessaire sur segment lure→volume (vérification heuristique : navmesh sans la capability ne connecte pas)

---

## Recommended Revisions (NEW RECOMMENDED)

### NR-SEC-1 — AC-SEC-37 scope intégration trop élevé pour AUTO BLOCKING (hérité r1 N persistant)
`[systems-designer NR-2]` + `[qa-lead NR-1]` + `[game-designer R-r2-1]` — 3 specialists agree

**Fix** : décomposer en :
- AC-SEC-37a BLOCKING AUTO : F-SEC-1 unitaire (`yield = Σ tier×5` pour liste donnée)
- AC-SEC-37b ADVISORY AUTO : intégration Credit stub vérifiant ratio session simulée
- Reclassifier AC-SEC-37 actuel ADVISORY (validation calibration, pas contrat fonctionnel)

---

### NR-SEC-2 — AC-SEC-NEW lint StringName `&"…"` vs `"…"` faille grep
`[qa-lead NR-2]`

**Fix** : grep doit chercher les **deux formes** : `"instance_id"` ET `&"instance_id"` ET les autres valeurs migration (`"scene_path"`, `&"scene_path"`, `"uuid_export"`, `&"uuid_export"`). Sinon implémenteur peut hardcoder `&"instance_id"` directement et passer le lint.

---

### NR-SEC-3 — Audio r2.2 promotion en gate pré-`/create-epics secret-system`
`[game-designer R-r2-4]`

**Fix** : §Gates pré-`/create-epics` ajouter row `Audio r2.2 — bus SECRET_COLLECT` RECOMMENDED (owner audio-director, target avant `/create-epics`). Sinon implémenteur Audio par défaut sur bus SFX générique → refacto Tier 2+. Lié NB-CRD-6 Credit (Option A résout par cascade).

---

### NR-SEC-4 — `_collected_secret_ids` ownership purge `request_new_run` flou
`[systems-designer NR-4]` + `[qa-lead NR-3]`

**Fix** : R-SEC-10 expliciter que la purge du Checkpoint snapshot est faite **par Checkpoint lui-même** sur broadcast `request_new_run()` (pas par Secret). Secret purge uniquement `_collected_secret_ids` (son propre état). Reformuler : "dictionnaire `_collected_secret_ids` vidé. Note : le Checkpoint snapshot est purgé par Checkpoint sur le même signal `request_new_run()`".

---

### NR-SEC-5 — ADR-0008 absent §Dependencies (hérité r1 R-4)
`[systems-designer NR-5]`

**Fix** : §Hard dependencies ou §Cousins ajouter ligne : `ADR-0008 — LAYER_INTERACTIVE = 5 (contrainte layer physique volume Area3D)`. 1 ligne. Si ADR-0008 modifie LAYER_INTERACTIVE, Secret silencieusement cassé sans cross-ref.

---

### NR-SEC-6 — F-SEC-2 cap théorique table ambiguous
`[systems-designer NR-1]` + `[game-designer R-r2-2]` + `[game-designer N-r2-1]`

**Fix** : variable table F-SEC-2 reformuler `0 à 150 (cap absolu : 5×15×2 = 150 ; cap pratique completionist : ≈120)`. Documenter que "5:1" est ratio par transaction (5 cr secret T1 vs 1 cr kill), pas ratio session (3.25:1 typique).

---

### NR-SEC-7 — EC-SEC-02 séquence body_entered au tick PAUSED non documentée
`[systems-designer NR-3]`

**Fix** : EC-SEC-02 ajouter séquence : "body_entered tick T → PAUSED tick T → callback traité sous garde R-SEC-08 → ignoré → après resume, joueur re-entre → collectable normalement (idempotence préservée)". Clarifier que secret n'est PAS perdu — il reste UNCOLLECTED, donc collectable après resume.

---

### NR-SEC-8 — AC-SEC-46 + AC-SEC-51 seuil 5/5 trop strict vs autres ACs J 4/5
`[qa-lead NR-4]`

**Fix** : aligner AC-SEC-46 et AC-SEC-51 sur 4/5 (cohérent AC-SEC-47/48/49 standard QA playtest qualitatif).

---

### NR-SEC-9 — AC manquant `state_changed(MENU)` ne purge pas `_collected_secret_ids`
`[qa-lead NR-5]`

**Fix** : ajouter AC-SEC-NR-9 : `GIVEN _collected_secret_ids contient N entrées WHEN state_changed(MENU) reçu THEN size() == N (inchangé, non purgé) ET connections déconnectées (AC-SEC-04 déjà couvre) ET get_collected_ids() reste accessible lecture (AC-SEC-35)`.

---

### NR-SEC-10 — AC-SEC-NEW renommer en AC-SEC-53 (numérotation canonique)
`[systems-designer NN-4]`

**Fix** : `AC-SEC-NEW` → `AC-SEC-53`. Évite ambiguïté de référencement dans epics et stories.

---

### NR-SEC-11 — AC-SEC-39 API `Time.get_ticks_usec()` (Godot 4.6 correct)
`[qa-lead NN-3]`

**Fix** : préciser API : `Time.get_ticks_usec()` (Godot 4.6 standard) — éviter `OS.get_ticks_usec()` deprecated.

---

### NR-SEC-12 — Escalade difficulté intra-étage non requise (métroidvania promise)
`[level-designer R-SEC-LD-R1]`

**Fix** : §Tuning Knobs §Authoring ajouter règle : un étage doit contenir au moins 1 secret avec `required_ability` non-disponible au premier passage (créer arc "tu verras ce secret quand tu auras cette capability" — Player Fantasy §29 + game-concept l.62-63). Pointeur vers Level GDD §progression map requis.

---

### NR-SEC-13 — Visibilité lure depuis chemin nominale en règle positive
`[level-designer R-SEC-LD-R4]`

**Fix** : promouvoir EC-SEC-AP-5 d'anti-pattern à règle authoring positive : `un SecretLureMarker_NN doit être visible depuis au moins un point du chemin nominale (sightline dégagée, portée ≤ MAX_LURE_TO_VOLUME_DISTANCE = 30 m)`. Pillar 4 affordance primaire.

---

## Specialist Disagreements

### DA-SEC-1 — NB-SEC-2 (CollisionShape disabled) BLOCKING vs RECOMMENDED
- `level-designer` (R-LD-R3) : considère que c'est responsabilité Level lint (OQ-SEC-7) — Secret n'est pas owner
- `systems-designer` (NB-3) + `game-designer` (R-r2-3) + `qa-lead` (NN-1) : silent failure Pillar 4 inacceptable, défensive Secret minimum requis
- **Adjudication** : **BLOCKING** car OQ-SEC-7 Level lint est explicitement Sprint 1 (pas MVP). En MVP sans lint, ce cas peut shipper en production. Push_warning runtime côté Secret = défense minimale 0 coût impact.

### DA-SEC-2 — NB-SEC-5 / NB-SEC-6 (distribution spatiale + obstacle mouvement) Secret GDD vs Level GDD
- `game-designer` (potentiel) : ces règles sont Level concern, devraient vivre dans Level r5 §Authoring Guidelines
- `level-designer` : gaps existent ni dans Secret ni dans Level — doivent exister quelque part
- **Adjudication** : la règle peut vivre dans Level r5 §Authoring Guidelines OU Secret GDD §Tuning Knobs §Authoring. Ce qui compte : elle existe. Recommandation Secret GDD §Tuning Knobs §Authoring (proximité authoring secret, single source of truth pour règles secret-spécifiques).

### DA-SEC-3 — Pull vs Push Checkpoint NB-SEC-1 BLOCKING vs RECOMMENDED
- `game-designer` (potentiel) : sémantique "implicitement évidente" (PULL canonique, PUSH alternative restore)
- `systems-designer` + `qa-lead` : 2 ACs indépendants sans précédence → risque double-peuplement réel
- **Adjudication** : **BLOCKING** — ambiguïté écrite explicitement dans GDD doit être tranchée explicitement, pas implicitement.

---

## Senior Verdict (synthèse)

Le r2 résout **2/3 BLOCKING r1 solidement** (B-2 R-SEC-16, B-3 secret_constants.gd) et **1/3 partiellement** (B-1 contrat Checkpoint avec ambiguïté pull/push résiduelle).

**Pattern principal** : le travail r2 est architecturalement plus mature que r1 — la résolution B-2 (R-SEC-16 invariant cross-system documenté) et B-3 (data-driven cohérent studio) sont exemplaires. Mais la résolution B-1 a introduit une nouvelle ambiguïté en présentant deux mécanismes simultanés sans précédence.

**Convergence forte 4/4 specialists** : NB-SEC-2 (CollisionShape3D disabled silent Pillar 4 failure) reste non adressé après r1 puis r2 — c'est le cas où "EC-MISSING-1 reporté Sprint 1 lint" laisse un trou MVP.

**Convergence forte 3/3 (qa + systems + game)** : NR-SEC-1 (AC-SEC-37 scope) — AC `BLOCKING AUTO` qui requiert intégration multi-system est anti-pattern QA. Reportable en RECOMMENDED, scope correctible XS.

**Level-designer perspective unique** : NB-SEC-5 + NB-SEC-6 révèlent un gap structurel — Secret GDD donne un excellent contrat de **collection** (idempotence, signal SYNC, persistance) mais un contrat d'**authoring** incomplet (distribution, défi, escalade). Pillar 4 délivré côté code, sous-livré côté level-design.

**Player Fantasy ARTISAN** : excellente — la sobriété austère du système (pas d'UI propre, signal SYNC + oubli, glow extinct ≤50 ms, anti-cinematic) est la meilleure expression Pillar 4 dans le corpus GDD. R2 ne l'affaiblit pas.

**Path to APPROVED** :
1. r3 ciblée Secret GDD (~2h editorial) :
   - NB-SEC-1 : R-SEC-10 explicite PULL canonique MVP / PUSH Tier 2+
   - NB-SEC-2 : R-SEC-13 push_warning défensif + AC-SEC-NB-2 lint Level
   - NB-SEC-3 + NB-SEC-4 : reformulation ACs SEC-25 + SEC-18
   - NB-SEC-5 + NB-SEC-6 : §Tuning Knobs §Authoring 2-3 nouvelles règles + AC STATIC
2. Re-review fresh 5-min lean → APPROVED → unlock `/create-epics secret-system`

---

## Scope Signal

**Rough scope signal : XS/S (producer should verify before sprint planning)**

- 6 NEW BLOCKING tous scope **reformulation/ajout** (pas redesign)
- 13 NEW RECOMMENDED batchables r3
- 4 NEW NICE-TO-HAVE polish
- 0 nouveau ADR requis
- 0 redesign de règle ou de formula

**Estimation r3 design session focalisée** : 2h editorial Secret GDD + (optionnel) propagation Audio r2.2 NR-SEC-3 = ~2h max.

---

## Final Verdict

**NEEDS REVISION (r3 ciblée — scope XS/S)**

Le r2 a élevé Secret System à un haut niveau de maturité architecturale (R-SEC-16, secret_constants.gd, signaux SYNC). Reste à trancher l'ambiguïté pull/push Checkpoint, défendre Pillar 4 contre CollisionShape disabled, fixer 2 ACs intestables headless, et combler les 2 gaps authoring (distribution + défi mouvement). Tout est editorial — pas de redesign.
