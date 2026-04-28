# Credit Economy System — Design Review r2 fresh

**Date** : 2026-04-28
**Verdict** : **NEEDS REVISION (r3 ciblée — scope S/M)**
**Reviewer** : `/design-review --depth full` (4 spécialistes adversariaux + senior synthèse)
**Document reviewé** : `design/gdd/credit-economy-system.md` r2 (615 lignes)
**Re-review de** : `credit-economy-system-review-r1-2026-04-27.md` (7 ship-blockers résolus)

---

## Specialists consulted

- `game-designer` (Player Fantasy + asymétrie viscérale)
- `economy-designer` (drops, sinks, faucets, courbes progression)
- `systems-designer` (contracts inter-systems, edge cases, formulas)
- `qa-lead` (AC quality, test evidence, regression coverage)

Senior verdict synthèse : adjudication directe par le main reviewer (convergences claires).

---

## Prior r1 Resolution Verification (7 ship-blockers)

| Blocker r1 | Statut r2 | Verdict cross-specialist |
|---|---|---|
| **B-1** Rule 7 multi-kill batching default `BATCH_MULTI_KILL_EMIT = true` | ✅ RESOLVED | Cohérent sur 5 points (Rule 7 l.50, EC-CRD-5 l.280, AC-CRD-08 l.500, AC-CRD-31 l.538, Knob l.379). Adjudication CD r1 honorée. |
| **B-2** Combat-only soft-lock `BASE_UPGRADE_COST` 20 → 8 | ⚠️ PARTIALLY RESOLVED | F-CRD-3/4 recalculées correctement, mais surface du problème déplacée : (a) contradiction Shop r2 non-propagée NB-CRD-1, (b) marge zéro pile-poil cassable par Level NB-CRD-2. |
| **B-3** Contradiction tween SPEND_SHOP HUD r1 R-6 | ⚠️ PARTIALLY RESOLVED | §Visual table l.397-403 délègue correctement, mais §UI Requirements l.436 conserve "tween 200-400 ms" hardcodé → contradiction interne résiduelle NB-CRD-3. |
| **B-4** F-CRD-3 sanity N=8 cumulatif | ⚠️ PARTIALLY RESOLVED | Sanity Σ=624 ≤ 680 mathématiquement correct, mais évalué sur `session_yield_max = 85 cr` (joueur completionist 100%) — pas le joueur typique (~60-65 cr). NR-CRD-1. |
| **B-5** 6 ACs Lints/Static mal classés | ⚠️ PARTIALLY RESOLVED | Test Coverage Matrix reformatée + AC-CRD-32 supprimé OK, mais AC-CRD-41 mal-classé Lints/Static alors que c'est un test runtime singleton autoload. NB-CRD-4. |
| **B-6** Rule 6 `_credited_this_run` purge checkpoint | ✅ RESOLVED | Rule 6 l.48 + EC-CRD-7/16 + AC-CRD-50 cohérents. Caveat NR-CRD-3 sur ordre purge cross-étage. |
| **B-7** Race boot `level_active` vs `state_changed(PLAYING)` | ✅ RESOLVED | Rule 5 + Rule 11 + EC-CRD-11 + AC-CRD-51 découplent connexion/hydration proprement. |

**Conclusion B-1..B-7** : 3 résolus complètement, 4 partiellement (problèmes résiduels documentés ci-dessous).

---

## Dependency Graph

| Dépendance déclarée | Existe ? | Statut |
|---|---|---|
| `enemy-definition-data.md` | À vérifier | (référencé via Enemy GDD) |
| `shop-system.md` | ✅ | **CONTRADICTION valeur BASE_UPGRADE_COST cf NB-CRD-1** |
| `secret-system.md` | ✅ | Cohérent (R-SEC-08 SYNC confirme Rule 9) |
| `save-load-system.md` | ✅ | Cohérent |
| `hud-system.md` | ✅ | Délégation §Visual OK, §UI Requirements stale NB-CRD-3 |
| `state-machine` (GSM) | ✅ | ADR-0007 D-9 pull pattern OK |
| `level-system.md` | ✅ | **CONTRAT BORNE N_KILLS_ETAGE_1 non explicite cf NB-CRD-2** |
| `checkpoint-respawn-system.md` | Not Started | Acceptable — Rule 6 r2 a clarifié sans dépendre du GDD Checkpoint |

---

## Required Before Implementation (NEW BLOCKING)

### NB-CRD-1 — Contradiction cross-GDD `BASE_UPGRADE_COST` Credit r2 vs Shop r2 [SHIP-CRITICAL — 3 specialists agree]

**Sources** : `[game-designer G-2]` + `[economy-designer NB-2]` + `[systems-designer NB-1]`

**Fichiers** :
- `credit-economy-system.md` F-CRD-3 l.163 : `BASE_UPGRADE_COST = 8`
- `shop-system.md` Quick Reference l.7 + R-SHP-3 l.98 : `BASE_UPGRADE_COST(20)` + worked example "double_jump à 20 cr (n=0), dash_horizontal à 40 cr (n=1)"
- `shop-system.md` Player Fantasy l.21 : "La carte du haut dit `Saut Double — 20 ₵`"

**Problème** : la révision Credit r2 B-2 abaisse `BASE_UPGRADE_COST` à 8 cr pour résoudre le soft-lock combat-only. **Shop r2 n'a pas été propagé** — il affiche encore 20 cr / 40 cr. Les deux GDDs sont en production simultanée mais divergent sur la **constante canonique** du cycle économique.

L'implémenteur Shop lira `BASE_UPGRADE_COST(20)` et codera l'upgrade n=0 à 20 cr → revert factuel de B-2 → soft-lock combat-only revient. La promesse Player Fantasy Shop "tu en as 33 et la carte dit 20 ₵" devient narrativement incohérente avec un coût réel 8 ₵ (le joueur peut tout acheter trivialement).

**Fix requis (cosmetic Shop r2 amendement)** :
1. `shop-system.md` Quick Reference l.7 : `BASE_UPGRADE_COST(8) + n_index × TIER_COST_STEP(20)` → 8 cr (n=0), 28 cr (n=1)
2. `shop-system.md` R-SHP-3 l.98 : recalcul worked example complet
3. `shop-system.md` Player Fantasy l.21 : actualiser exemple narratif "Saut Double — 8 ₵"
4. Tous worked examples F-SHP-* à recalculer si présents
5. AC-SHP-* impactés à vérifier

**Pillar impact** : Pillar 2 (LA PROGRESSION SE VOIT — la promesse anti soft-lock B-2 inopérable).

---

### NB-CRD-2 — Anti soft-lock B-2 pile-poil : `N_KILLS_ETAGE_1` borne minimale Level non blindée [BLOCKING — 2 specialists agree]

**Sources** : `[economy-designer NB-1]` + `[systems-designer NN-1]`

**Fichiers** : `credit-economy-system.md` Cross-tuning l.384, F-CRD-4 l.213-220.

**Problème** : l'invariant anti soft-lock B-2 `BASE_UPGRADE_COST(8) ≤ kill_yield_etage_1(8)` suppose implicitement `N_KILLS_ETAGE_1 = 8`. Cette valeur est dérivée du Level GDD R-2.6 (`ARENA ≥ 3 EnemySlot`) **mais non instanciée comme borne concrète** dans le Credit GDD.

Si Level r4 (Designed) ou amendement futur ajuste à 6 grunts (plafond bas conforme R-2.6 = 2 arenas × 3 EnemySlot), `kill_yield_etage_1 = 6 cr < 8 cr` → soft-lock combat-only revient sans warning. Worked example l.219 démontre `session_yield = 8 cr = BASE_UPGRADE_COST` — **égalité stricte, marge zéro**.

**Fix requis** : Cross-tuning l.384 doit spécifier explicitement `N_KILLS_ETAGE_1_MIN = Level.ARENA_MIN × Level.ENEMY_SLOT_MIN = 2 × 3 = 6` comme borne inférieure documentée, et la condition anti soft-lock doit être évaluée sur cette borne :
- Soit abaisser `BASE_UPGRADE_COST` à 6 cr (safe range [5,15] le permet)
- Soit documenter une contrainte Level design `N_KILLS_ETAGE_1 ≥ 8` comme invariant cross-GDD avec balance-check assert
- Soit reformuler la contrainte avec marge : `BASE_UPGRADE_COST ≤ min_kill_yield_etage_1 = 0.8 × N_KILLS_NOMINAL × kill_credit`

**Pillar impact** : Pillar 2.

---

### NB-CRD-3 — §UI Requirements l.436 conserve tween hardcodé après délégation B-3 [BLOCKING — 2 specialists agree]

**Sources** : `[game-designer N-B]` + `[systems-designer NB-2]`

**Fichier** : `credit-economy-system.md` §UI Requirements tableau l.436 : `Animation soustraction | … | Counter tween 200-400 ms ; pulse rouge bref optionnel`

**Problème** : B-3 a correctement nettoyé §Visual (l.402 délègue à HUD r1 R-6) mais §UI Requirements ligne 436 conserve la spec de durée 200-400 ms. **Contradiction interne** : un implémenteur HUD lit §UI Requirements (section directement applicable) et code un tween 200-400 ms — exactement ce que B-3 voulait interdire.

**Fix requis** : ligne 436, remplacer "Counter tween 200-400 ms ; pulse rouge bref optionnel" par "voir HUD GDD §J — durée et style délégués". Pattern identique à la ligne 400 qui a déjà été corrigée pour la pulse KILL.

Note connexe : ligne 435-436 mentionne aussi "KILL = pulse 150 ms cyan" côté Credit. Cohérence à vérifier avec HUD r1 R-6 — si stale, déléguer également.

---

### NB-CRD-4 — AC-CRD-10 + AC-CRD-49 : triggers `_on_level_unloaded()` / `_on_level_loaded()` non spécifiés dans Detailed Rules [BLOCKING — 2 specialists agree]

**Sources** : `[systems-designer NR-4]` + `[qa-lead NB-2]`

**Fichier** : `credit-economy-system.md` AC-CRD-10 l.502, AC-CRD-49 l.575, Rule 6 l.48.

**Problème** : Rule 6 spécifie que `_credited_this_run` est vidé à `request_new_run()` ou au `level_active` **suivant**. Mais AC-CRD-10 teste `_on_level_unloaded()` et AC-CRD-49 teste `_on_level_loaded()` — **deux handlers qui n'apparaissent nulle part dans les Detailed Rules**. Ces ACs créent un contrat d'implémentation invisible.

Conséquences :
- L'implémenteur ne sait pas quand appeler `_on_level_unloaded()` (signal Level qui n'existe pas dans Level GDD §Interactions ?)
- AC-CRD-10 testerait un trigger inexistant → AC inférable mais intestable réel
- AC-CRD-49 idem

**Fix requis** :
- AC-CRD-10 → reformuler : `GIVEN le set d'IDs contient des entrées de l'étage précédent ET request_new_run() est émis par GSM, WHEN _on_request_new_run() est traité, THEN size() == 0 ET total_credits inchangé`
- AC-CRD-49 → reformuler : `GIVEN l'étage se charge première fois, WHEN level_active est reçu (premier signal session), THEN size() == 0 (déjà vide) ET total_credits intact ET tous les ennemis du groupe "enemies" connectés`
- OU ajouter Rule 5-bis explicitant `_on_level_unloaded` / `_on_level_loaded` si Level GDD les expose

---

### NB-CRD-5 — AC-CRD-39 perf gate 0.1 ms intestable en CI (hérité r1 P-5 non-résolu) [BLOCKING — 2 specialists agree]

**Sources** : `[game-designer G-3]` + `[qa-lead NR-3]`

**Fichier** : `credit-economy-system.md` AC-CRD-39 l.555.

**Problème** : seuil `< 0.1 ms` sur benchmark GUT en CI avec variance machine ±2-5 ms → flaps CI permanents. Un AC BLOCKING avec seuil ingérable = test fantôme : ne détecte pas régression (toujours rouge) et ne peut pas être vert stable (bruit > signal).

P-5 du r1 review proposait correction précise : `< 1 ms médiane sur N=100, exclure CI si non-reproductible ou marquer ADVISORY sur CI`. **Non appliqué en r2** — classé pre-impl reporté, mais c'est un AC BLOCKING au CI dès première story Credit.

**Fix requis** : reformuler AC-CRD-39 :
> THEN le temps d'exécution total du bloc Credit Economy dans ce tick est `< 1 ms` médiane sur N=100 appels. *Mécanisme* : benchmark GdUnit4 N=100 iterations, mesure médiane, exclure outliers (P95 acceptable à 3 ms). Sur CI : marquer ADVISORY si plateforme non-reproductible ; garder BLOCKING sur hardware target dev.

---

### NB-CRD-6 — Asymétrie 5:1 viscérale : Player Fantasy non livrée MVP, claim non retiré [BLOCKING — Pillar 4 critical]

**Source** : `[game-designer G-1]` + adjudication CD r1 non-honorée + `[game-designer R-4]`

**Fichiers** :
- `credit-economy-system.md` §Player Fantasy l.28-29 : "un kill c'est un battement, un secret c'est un riff" — promesse viscérale
- `credit-economy-system.md` §Audio l.420-422 : "Credit ne demande aucun son spécifique au MVP — Secret System (futur)"
- `secret-system.md` §Player Fantasy l.23-24 : "un clac riche, signature distincte du clac de combat"
- `credit-economy-system.md` OQ-CRD-8 l.613 : "VFX gain crédit secret distinct" — owner audio-director + ux-designer, deadline `Sprint A /design-system hud-system` **PASSÉE**, HUD r1 Rule 5 l.62-64 ne distingue pas KILL vs SECRET dans le pulse (même `CREDIT_COUNTER_TWEEN_MS = 100 ms`)

**Problème** : adjudication creative-director r1 = "1 SFX/VFX différenciés MVP minimum, sinon retirer claim Player Fantasy + North Star". **Aucune des deux options n'est appliquée en r2** :
- Le claim viscéral reste dans §Player Fantasy
- Le SFX/VFX différencié n'est pas livré (Credit délègue à Secret/Audio, Secret délègue à Audio futur, Audio r2.1 n'a pas le bus dédié — boucle de renvoi)
- HUD r1 ne différencie pas le pulse KILL vs SECRET (même tween 100 ms identique)

**Conséquence** : MVP shipera avec feedback indistinguable kill (+1 cr) vs secret (+5/10/15 cr) → Pillar 4 (asymétrie viscérale) cassé silencieusement, malgré le GDD qui en fait une promesse North Star.

**Fix requis (3 options exclusives)** :
- **Option A (livrer)** : Credit GDD §Audio spécifier requirement minimum implémentable : "Secret System DOIT transmettre payload `is_secret: true` à Audio System pour variation pitch ou bus distinct" + HUD r1 amendement pulse différencié SECRET (tween 150 ms ou couleur shift), ET Audio r2.2 amendement bus `SECRET_COLLECT` (résout aussi OQ-SEC-4)
- **Option B (retirer)** : Player Fantasy Section B retire le claim viscéral du paragraphe 4. North Star reformulée : "asymétrie économique mathématiquement tenue 5:1 sans dimension sensorielle MVP, viscéralité Tier 2+"
- **Option C (gate explicite)** : OQ-CRD-8 transformée en `[GATE r3 NB-CRD-6]` avant `/create-epics credit-economy-system` ET `/create-epics secret-system` — bloque ces 2 epics jusqu'à résolution.

**Décision recommandée** : Option A (cohérent Pillar 4 + résout OQ-SEC-4 secret-system par cascade) si Audio r2.2 amendement <2h ; sinon Option C.

---

## Recommended Revisions (NEW RECOMMENDED)

### NR-CRD-1 — Sanity check F-CRD-4 évalué sur completionist 100%, pas joueur typique
`[economy-designer NB-3]` + `[systems-designer NB-3]`

**Fichier** : l.252-258. Check `624 ≤ 680 = session_yield_max(85) × N_SESSIONS_TARGET(8)` valide pour explorateur 100%. Pour joueur typique 70% secrets : `session_yield ≈ 60-65 cr` → `60 × 8 = 480 < 624` → Full Vision (n=7, 148 cr) inatteignable en 8 sessions. **Sanity tautologique** sur cas idéal.

**Fix** : ajouter second check `Σ cost_n ≤ session_yield_typique × N_SESSIONS_TARGET_REALISTIC` avec `session_yield_typique = 60 cr` (70% exploration) et annoter : "Validation Tier 2+ Full Vision est TODO — recalculer à chaque ajout d'étage". Retirer `✅ PASS` prématuré sur N=8 Tier 2+.

---

### NR-CRD-2 — `BASE_UPGRADE_COST = 8 cr` cross-tuning : invariant balance manquant
`[economy-designer R-2]`

**Fichier** : §Tuning Knobs `BASE_UPGRADE_COST` l.353.

**Fix** : ajouter assertion balance-check : `Invariant : BASE_UPGRADE_COST ≤ min(N_KILLS_ETAGE_N × kill_credit["grunt"]) ∀ N`. Si Level GDD modifie `N_KILLS_ETAGE_1 < 8`, abaisser `BASE_UPGRADE_COST` proportionnellement ou alerte balance-check. Lié à NB-CRD-2 mais distinct (NB-CRD-2 = problème Cross-tuning, NR-CRD-2 = blindage Tuning Knobs).

---

### NR-CRD-3 — `_credited_this_run` purge cross-étage : ordre non documenté
`[systems-designer NR-3]`

**Fichier** : Rule 6 l.48.

**Problème** : Rule 6 dit "vidé au `level_active` suivant" mais ordre d'opérations vs connexion nouveaux ennemis non spécifié. Risque race : `level_active` reçu, dictionnaire pas encore vidé, premier kill étage N+1 a un `instance_id` qui collisionne par hasard avec un ID de l'étage N → kill ignoré silencieusement.

**Fix** : documenter explicitement que `_credited_this_run.clear()` se fait **avant** la connexion des nouveaux `enemy_killed` dans `_on_level_active()`. Ajouter assert debug que set est vide en sortie de `_on_level_active()` post-clear pre-connect.

---

### NR-CRD-4 — `secret_collected` connexion flags non spécifiés Rule 9
`[systems-designer NR-1]`

**Fichier** : Rule 9 + Rule 5.

**Problème** : Rule 5 spécifie `enemy_killed.connect(...)` SYNC (flags=0) explicite l.52. Rule 9 ne spécifie **pas** le flag pour `secret_collected`. Si Credit connecte en CONNECT_DEFERRED, signal arrive idle frame suivante → compteur ne monte pas dans le même physics step que la collecte → viole même exigence Pillar 1 que Rule 5.

**Fix** : Rule 9 explicite : `secret_collected.connect(_on_secret_collected, 0)` SYNC, lifecycle même que Rule 5 (connexion `_on_level_active()`).

---

### NR-CRD-5 — AC-CRD-29 mécanisme SYNC ne prouve pas synchronicité runtime
`[systems-designer]` + `[qa-lead NR-2]`

**Fichier** : AC-CRD-29 + hérité P-4 r1.

**Problème** : "vérifier absence flag CONNECT_DEFERRED" prouve seulement la configuration de connexion, pas que le signal n'est pas re-deferred via `call_deferred` interne dans le handler.

**Fix** : reformuler mécanisme : "appeler directement `_physics_process(0.016)` sur instance Credit avec ennemi mock pré-connecté — capturer via spy si `credits_changed` émis **avant** retour `_physics_process`. Assert `spy.get_call_count() == 1` après retour. Complément statique : AC-CRD-20 grep absence `await`/`call_deferred` dans body `_on_enemy_killed`."

---

### NR-CRD-6 — AC-CRD-06 + AC-CRD-15 : `push_warning` non interceptable GUT (hérité r1 N-5)
`[qa-lead NR-1]`

**Fix** : tester comportement observable (retour false, total inchangé, 0 signal) ; vérifier `push_warning` par grep statique dans body `try_spend` / `_on_secret_collected` (Lints/Static).

---

### NR-CRD-7 — AC-CRD-46 mécanisme "même frame" invérifiable par screencap (hérité r1 P-6)
`[qa-lead NR-4]`

**Fix** : integration test Credit + HUD stub — listener sur `credits_changed`, dans handler vérifier `_credit_label.text` déjà mis à jour (SYNC call). Sign-off lead designer reste ADVISORY séparé pour qualité visuelle.

---

### NR-CRD-8 — AC-CRD-45 [Lints/Static] scope incomplet vs `movement_lint_test.gd`
`[qa-lead NB-1]`

**Fix** : AC-CRD-45 doit pointer explicitement vers `tests/static/credit_economy_lint_test.gd` avec mécanisme parsing function-scoped (pas grep simple), pattern identique à `movement-emit-physics-only.md`. AC-CRD-20 le fait déjà — alignement requis sur AC-CRD-45.

---

### NR-CRD-9 — Anti-grind non enforced documenté ni dans GDD
`[economy-designer NR-3 / R-1]`

**Fix** : ajouter §Edge Cases ou §Dependencies note : "L'anti-grind est promesse Level design (chaque étage jouable une fois par run) — Credit Economy ne l'enforce pas. Si Level System permet replay intra-run, cap par étage requis."

---

### NR-CRD-10 — `kill_credit["grunt"]` safe range [1,3] ouvre faille Pillar 4 (hérité r1 P-8)
`[economy-designer NR-1]`

**Fix** : restreindre safe range à `[1, 1]` ou reformuler AC-CRD-16 invariant : `BASE_SECRET_CREDIT × 1 >= 5 × kill_credit["grunt"]` runtime check, pas hardcodé.

---

### NR-CRD-11 — Rule 7 buffer `_pending_kill_delta` lifecycle entre ticks non spec
`[economy-designer NR-2]`

**Fix** : Rule 7 expliciter "`_pending_kill_delta` reset à 0 en début de chaque `_physics_process` (ou après flush)".

---

### NR-CRD-12 — AC-CRD-52 manquant pour `BATCH_MULTI_KILL_EMIT = false` Tier 2+
`[qa-lead NR-5]`

**Fix** : ajouter AC-CRD-52 BLOCKING : `GIVEN BATCH_MULTI_KILL_EMIT == false, WHEN 3 enemy_killed séquentiels même tick, THEN exactement 3 signaux credits_changed séquentiels (N+1,+1,KILL), (N+2,+1,KILL), (N+3,+1,KILL)`. Test paramétré, même fixture qu'AC-CRD-08.

---

### NR-CRD-13 — Sink unique : guard contre `total_credits` infini cross-session
`[economy-designer NR-3]`

**Fix** : ajouter HUD Requirement : quand `N_UPGRADES_OWNED == N_UPGRADES_MAX`, shop indique "No upgrades available" + compteur HUD état différent (couleur gold saturation max ou similaire). Documenter ressenti joueur post-Full-Vision.

---

## Specialist Disagreements

### DA-1 — `kill_credit["grunt"]` safe range [1,1] vs [1,3]
- `economy-designer` : NR-1 / safe range [1,1] pour protéger Pillar 4 ratio 5:1
- Décision design pillar-level : **maintenue à [1,3] avec invariant runtime AC-CRD-16 reformulé** (plus flexible playtest, pillar protégé par check). Cohérent avec NR-CRD-10.

### DA-2 — AC-CRD-39 perf gate BLOCKING vs ADVISORY
- `economy-designer` (potentiel) : BLOCKING force implémentation zero-overhead
- `qa-lead` + `game-designer` : AC BLOCKING intestable CI = théâtre qualité
- **Adjudication** : reformuler `< 1 ms médiane N=100 + outliers exclus` BLOCKING sur dev hardware, ADVISORY sur CI si non-reproductible. Cohérent avec NB-CRD-5.

---

## Senior Verdict (synthèse)

Le r2 résout **3/7 ship-blockers complètement** et **4/7 partiellement**. Le pattern est constant : les corrections ciblées sont mathématiquement correctes mais leur **propagation cross-document n'a pas été honorée**, et l'adjudication CD r1 sur l'asymétrie viscérale a été oubliée dans la rush vers les blockers chiffrables.

**Ship-critical absolu** : NB-CRD-1 (contradiction Shop r2 vs Credit r2 sur `BASE_UPGRADE_COST`) — un implémenteur lisant les deux GDDs verra deux valeurs différentes pour la même constante canonique. C'est le type de bug cross-GDD qui fait dérailler une sprint à la première story Shop.

**Pillar critical** : NB-CRD-6 (asymétrie viscérale non livrée et non retirée) — l'adjudication CD r1 imposait un choix binaire (livrer SFX/VFX MVP minimum OU retirer claim Player Fantasy). Aucun des deux n'a été fait. Le statu quo r2 est **structurellement le pire des deux options** : la promesse reste textuellement, mais l'implémentation MVP livrera silencieusement un feedback identique kill/secret.

**Architecture-correct** : B-1, B-6, B-7 sont des résolutions exemplaires — Rule 7, Rule 6, Rule 11 sont précis et implémentables, ACs cohérents. Le travail r2 est solide sur les blockers d'autonomie système.

**Path to APPROVED** :
1. Amendement cosmétique Shop r2 (`BASE_UPGRADE_COST = 8` propagation, ~30 min) — résout NB-CRD-1
2. Décision Option A/B/C sur asymétrie viscérale Pillar 4 (1-3h selon option) — résout NB-CRD-6
3. r3 ciblée Credit GDD : NB-CRD-2 (cross-tuning borne Level), NB-CRD-3 (UI Requirements stale), NB-CRD-4 (AC triggers), NB-CRD-5 (AC-CRD-39 reformulation) — ~1h editorial
4. Re-review fresh 5-min lean après r3 → APPROVED → unlock `/create-epics credit-economy-system`

---

## Scope Signal

**Rough scope signal : S/M (producer should verify before sprint planning)**

- 6 NEW BLOCKING dont 5 sont cosmétiques/editorial (1-2h chacun) et 1 (NB-CRD-6) requiert décision design + propagation cross-system
- 13 NEW RECOMMENDED batchables r3
- 3 NEW NICE-TO-HAVE polish
- Aucun re-design de règle ou de formule requis
- Pas de nouveau ADR

**Estimation r3 design session focalisée** : 2-3h editorial + 1h décision NB-CRD-6 + propagation Shop r2 cosmetic 30 min = ~4h max.

---

## Final Verdict

**NEEDS REVISION (r3 ciblée)**

Le r2 a fait le travail substantiel sur les blockers d'autonomie. Reste à propager les conséquences cross-GDD et à honorer l'adjudication CD r1 sur Pillar 4 viscéral — décisions et editorial, pas redesign.
