# Player Combat System — Review Log

Fichier d'historique des reviews pour `design/gdd/player-combat-system.md`. Chaque entrée documente un passage `/design-review`.

---

## Review — 2026-04-22 — Verdict: MAJOR REVISION NEEDED

**Scope signal**: XL (pre-revision) / L (post-revision — cible)
**Specialists consultés**: game-designer, systems-designer, gameplay-programmer, audio-director, performance-analyst, godot-specialist, qa-lead, creative-director (senior synthesizer)
**Blocking items**: 11 | **Recommended**: 21 | **Nice-to-have**: 4
**Prior verdict resolved**: First review (r1)
**Completeness**: 8/8 sections + 3 bonus (Visual/Audio, UI, Open Questions)
**Dependency graph**: 3/3 upstream DESIGNED GDDs existent et bidirectional cohérent (Movement, Camera, Input). 7 downstream not-started (contracts one-way OK).

### Summary

La Fantasy "beat rythmique staccato — le kill est le silence entre deux notes de mouvement" est **excellente** en écriture et les 4 Pillars sont correctement mappés. La structure 8 sections est respectée. Cependant, 7 specialists indépendants ont remonté 11 BLOCKING avec **7 convergences cross-model sur des points non-triviaux** (ordre `_physics_process`, CONNECT_DEFERRED vs frame-sync Pillar 1, ShapeCast overlap Gap 2, affirmation Godot 4.6 factuellement fausse ligne 636, budget 8 ms non étayé, `is_instance_valid()` absent, slow-mo 667 ms perçus = climax contradictoire avec "micro-pause"). Quand 4 disciplines différentes tapent sur les mêmes clous sans se parler, c'est un **déficit de spécification structurel**, pas une liste de coquilles.

**Creative-director verdict**: *"Le GDD décrit un système qui **marche** mais ne **chante** pas. La Fantasy est récupérable (aucune issue ne requiert de repenser l'architecture), mais les conditions d'implémentation ne sont pas réunies. Scope avant revision = L (2-3 sprints) ; sans revision = XL garanti (6 semaines dette vs 2 semaines clarification maintenant). CD-GDD-ALIGN: REJECT."*

### 11 BLOCKING (résumé)

| # | Item | Source | Convergence |
|---|------|--------|-------------|
| 1 | Slow-mo 100 ms @ 0.15× = 667 ms perçus → climax vs Fantasy "micro-pause" | game-designer + audio-director + godot-specialist | Triple |
| 2 | ShapeCast3D overlap à origine (Gap 2) → doit devenir Rule 6 addendum + AC autonome | gameplay-programmer + godot-specialist + qa-lead | Triple |
| 3 | `is_instance_valid()` manquant Rule 10 → crash garanti si Enemy `queue_free` pendant swing | gameplay-programmer + godot-specialist | Double |
| 4 | `player.global_position_tick_N_minus_1` non spécifié (qui cache, quand ?) | gameplay-programmer + godot-specialist | Double |
| 5 | Ligne 636 fausse — AudioStreamPlayer NE pitche PAS automatiquement avec time_scale en Godot 4.6 | audio-director + godot-specialist | Double |
| 6 | CONNECT_DEFERRED flash blanc = 16 ms décalage → viole Pillar 1 "frame-précis" ET ADR-0005 D-5 | gameplay-programmer + audio-director + performance-analyst | Triple |
| 7 | AC-CMB-35 budget 8 ms sans benchmark + hardware testbed non défini | performance-analyst + qa-lead (FAIL) | Double |
| 8 | `Engine.time_scale` dans `_process` (Formula 7) viole ADR-0001 "_process cosmetic only" | gameplay-programmer (tranché BLOCKING par CD vs godot-specialist RECOMMENDED) | Tranché |
| 9 | Formula 5 `cooldown_ratio` — division par zéro si ATTACK_COOLDOWN_MS=0 → NaN HUD | systems-designer | Seul |
| 10 | Decal sang permanent sans `MAX_DECALS_PER_ROOM` → fuite rendering Forward+ | performance-analyst | Seul |
| 11 | AC-CMB-08 erreur de type : "± 0.001 rad" appliqué à un Vector3 | qa-lead FAIL | Seul |

### 4 désaccords cross-specialist (tous tranchés par creative-director)

1. **No buffering (Rule 3)** — game-designer BLOCKING (anti-FLOW) vs 6 autres acceptent → **CD tranche pour game-designer** : buffer 80 ms minimum (refs Hades, Hotline Miami, Ghostrunner). Remonte à Martin.
2. **Mutual kill tick-même** — game-designer BLOCKING seul (anti-Fantasy "conséquence du bon placement") → **CD tranche pour game-designer** : les deux meurent ou joueur gagne. Remonte à Martin.
3. **`Engine.time_scale` dans `_process`** — gameplay-programmer BLOCKING (viole ADR-0001) vs godot-specialist RECOMMENDED (wall-clock fonctionne) → **CD tranche BLOCKING** — protéger ADR-0001. Déplacer le check en `_physics_process` avec `Time.get_ticks_msec()`.
4. **`N_SUBSTEPS` dynamique vs constant** — gameplay-programmer BLOCKING (frame spikes silencieux = violation Pillar 1) vs performance-analyst RECOMMENDED (micro-opti) → **CD tranche BLOCKING** — Pillar 1 design pour worst case, pas cas moyen.

### 5 décisions Martin-only (remontées par creative-director)

1. Buffering input pendant cooldown : buffer 80 ms (CD reco) / aucun buffer / autre valeur ?
2. Mutual kill tick-même : les deux meurent (CD reco) / joueur gagne (tie goes to runner) / status quo (ennemi gagne) ?
3. Slow-mo cible : 50 ms à 0.3× (167 ms perçus — CD reco) / status quo 100 ms @ 0.15× / supprimer complètement ?
4. Pitch audio slow-mo : aucun pitch (normal, comportement Godot 4.6 par défaut) / pitch manuel 0.5× / bus filtered ducking ?
5. Flash blanc synchro : corriger archi vers connexion sync (ADR-0005 D-5 exemption pour ce signal) / corriger GDD vers "+1 frame acceptable" (relax Pillar 1 frame-précis) ?

### Plan séquencé post-review (creative-director)

- **Étape 1** (Martin, 1 session 2h) : trancher les 5 décisions produit ci-dessus.
- **Étape 2** (game-designer + systems-designer, 3 jours) : revise GDD avec décisions Étape 1 + guards math F5/F2/F8 + Rule 6 addendum Gap 2 + spec `global_position_tick_N_minus_1` + résolution contradiction `player.transform` read-only vs Rule 5.
- **Étape 3** (lead-programmer, 2 jours) : mini-ADR "Combat Tick Model" (ordre physics_process parent/enfant, propriétaire cache N-1, interface Mock*, CONNECT_DEFERRED vs sync policy).
- **Étape 4** (godot-specialist + audio-director, 1 jour) : corriger affirmations factuelles fausses (ligne 636, `_process` justification) + spec spatialisation audio.
- **Étape 5** (qa-lead, 0.5 jour) : re-pass ACs (AC-08 type fix, AC-35 hardware testbed, AC-19 tolérance wall-clock, AC-37 soak 1000 cycles + memory metric, 19 WEAK rewrites, ACs manquants Rule 11 / Rule 6 tick-update / Edge Cases sans die() / aim au sol / Gap 2 conditionnel, Gaps 5/6/7 additionnels).
- **Étape 6** : re-run `/design-review` (fresh session) → cible verdict APPROVED (r2).

**Décision Martin (2026-04-22)** : Option A "Revise le GDD maintenant" — démarrer Étape 1 immédiatement en session courante.

---

## Review — 2026-04-23 — Verdict: MAJOR REVISION NEEDED (resolved inline)

**Scope signal**: L (post-revision — cible APPROVED en r4)
**Specialists consultés**: game-designer, systems-designer, gameplay-programmer, audio-director, performance-analyst, godot-specialist, qa-lead, creative-director (senior synthesizer, fresh session indépendante de r1)
**Blocking items**: 12 | **Recommended**: 10+ | **Nice-to-have**: 3
**Prior verdict resolved**: r1 MAJOR REVISION (2026-04-22) — 9/11 BLOCKING r1 resolus dans regles vivantes, mais drift documentaire non propage → r2 12 BLOCKING convergents
**Completeness**: 8/8 sections + 3 bonus maintenus

### Summary

Le r2 avait resolu 9 des 11 BLOCKING r1 dans les regles vivantes (Rule 13/F7/R17/F5/Section F/R6 addendum/R10). Mais la revision r1 avait introduit une **nouvelle classe de defaut** : drift documentaire post-Martin D3 non propage. Le GDD r2 portait **deux verites contradictoires** pour les memes parametres slow-mo — la verite correcte (0.3 × 50 ms) dans Rule 13/Formula 7/Rule 17 occupait 3 emplacements, la verite fausse (0.15 × 100 ms draft r1) occupait 8 emplacements (Edge Cases, VFX 2c, tableau Accessibility, ACs 17/21/24/36). Si un dev Sprint 1 lit la Section VFX 2c tel quel → anti-Fantasy BLOCKING #1 r1 renait (667 ms percus vs 167 ms percus).

**7 specialists fresh session** tous converge sur NEEDS REVISION avec convergences multi-specialist fortes :
- **BLOCKING-CONV-1 (6 specialists)** : stale slow-mo values 8 emplacements
- **BLOCKING-CONV-2 (3 specialists)** : AC-CMB-36 ranges vs Knob G contradictoires
- **BLOCKING-CONV-3 (3 specialists)** : Rule 7 vs Formula 3 vs AC-14 N_SUBSTEPS constant vs dynamique
- **BLOCKING-CONV-4 (2 specialists)** : AC-20 vs AC-28 vs AC-41 semantique mutual kill ambigue
- **BLOCKING single-specialist** : invariant #7 safe range BUFFER contradictoire (systems), Formula 4 div/0 delta=0 (systems), OS.get_static_memory_usage deprecated Godot 4.x (godot), debug_hits_last_swing Array[Node] vs Array[int] (gameplay), amendment ADR-0005 D-5 non ecrit (gameplay), PhysicsShapeQueryParameters3D non specifie Rule 6 Gap 2 (gameplay+godot), hardware-spec-testbeds.md absent Gap 6 (perf)

**Creative-director verdict r2** : *"r2 est un GDD schizophrène — la vérité Fantasy existe mais la vérité Anti-Fantasy est plus visible parce qu'elle occupe plus d'emplacements. r2 est subtilement plus dangereux que r1 pour un dev Sprint 1 pressé, car il semble résolu. La révision r3 n'est pas une refonte créative — c'est un balayage de propagation + 2 décisions Martin + 6 corrections techniques pointues. Fantasy EN DANGER. Scope L."*

### 12 BLOCKING r2 (résumé)

| # | Item | Source | Convergence |
|---|------|--------|-------------|
| 1 | Stale slow-mo `0.15 × 100 ms` en 8 emplacements (Edge Cases, VFX 2c, Accessibility, ACs) | 6 specialists | Convergence maximale |
| 2 | AC-CMB-36 ranges `[0.10, 0.30]` / `[50, 200]` vs Knob G `[0.10, 0.50]` / `[30, 150]` | systems + qa + godot | Triple |
| 3 | N_SUBSTEPS constant (R7) vs dynamique (F3 + AC-14) | gameplay + godot + qa | Triple |
| 4 | AC-20 vs AC-28 vs AC-41 mutual kill ambiguë | gameplay + qa | Double (CD ne peut arbitrer seul) |
| 5 | Invariant #7 BUFFER <= COOLDOWN/5 violé sur 3/6 combinaisons safe range | systems | Seul (CD ne peut arbitrer seul) |
| 6 | Formula 4 div/0 delta=0 garde absente (parité F5) | systems | Seul |
| 7 | AC-CMB-37 OS.get_static_memory_usage() deprecated Godot 4.x | godot | Seul |
| 8 | debug_hits_last_swing typé Array[Node] mais storage Array[int] | gameplay | Seul |
| 9 | Amendment ADR-0005 D-5 exemption SYNC flash non écrit | gameplay | Seul |
| 10 | Rule 6 Gap 2 addendum manque code pattern PhysicsShapeQueryParameters3D | gameplay + godot | Double |
| 11 | Gap 6 hardware-spec-testbeds.md absent → AC-35a/b/42 non-CI | perf | Seul |
| 12 | GTX 1650 Ti vs 1 GB VRAM minimum technical-preferences — clarification | perf | Seul |

### 2 décisions Martin M1 + M2 (tranchées 2026-04-23)

- **M1 — Sémantique mutual kill AC-20/28/41** : Option C **Hybrid** (SYNC sauf pendant Swinging, mécanisme `_death_pending` flag muté par handler SYNC et consommé en fin de `_physics_process` après résolution colliders). Recommandation CD acceptée.
- **M2 — Invariant #7 BUFFER vs safe range** : Option A **Resserrer safe range** (`ATTACK_BUFFER_MS ∈ [0, COOLDOWN_MS/5]` dynamique, discipline tuning). Recommandation CD acceptée.

### Revision r2 → r3 inline (2026-04-23)

Toutes les corrections r2 appliquées dans la même session post-Martin M1+M2 :

**Documentaire (BLOCK-1 à BLOCK-3)** : propagation stale slow-mo (Edge Cases + VFX 2c + Accessibility + ACs 17/21/24) ; AC-CMB-36 ranges alignés Knob G ; Formula 3 + AC-CMB-14 N_SUBSTEPS constant ; TUNNELING_THRESHOLD marqué DEPRECATED.

**Architectural Martin (BLOCK-4 M1 + BLOCK-5 M2)** : Rule 17 Hybrid refactor + Published API `_death_pending` flag privé + AC-CMB-20/28/41 adaptés séquence Hybrid + AC-CMB-28 restreint à `_state == IDLE` ; ATTACK_BUFFER_MS safe range dynamique `[0, COOLDOWN/5]` + invariant #7 assert fort au `_ready()`.

**Technique (BLOCK-6 à BLOCK-10)** : Formula 4 gardes SWING_DURATION_MS > 0 + delta > 0 + invariant #2.5 nouveau ; AC-CMB-37 API Performance.get_monitor ; `debug_hits_last_swing` getter avec instance_from_id + is_instance_valid + Formula 6 table `Array[int]` ; ADR-0005 D-5 amendment r2 écrit (fichier ADR mis à jour avec table de référence consumers + exemptions SYNC VFX flash + Combat `_on_player_died`) ; Rule 6 Gap 2 addendum code pattern complet `PhysicsShapeQueryParameters3D` + résolution Gap 7 CapsuleShape3D basis pattern.

**Perf (BLOCK-11)** : `docs/architecture/hardware-spec-testbeds.md` créé (3 tiers, Minimum Supporté = gate CI, Confort = target, Haut de gamme = informatif) + AC-CMB-35a bumpé à 1000 samples + AC-CMB-35b remplacé Godot Profiler par `Time.get_ticks_usec()` + 1000 frames.

**RECOMMENDED (BLOCK-12)** : annotations `[BLOCKED: Gap 1]` sur ACs 05/06/07 ; `[BLOCKED: Gap 5]` sur ACs 31/32 ; Movement GDD ligne 72 correction (transform.basis.z interdit, référence Combat Rule 5) ; audio-director R1 reformulation "même frame" → "frame N+1 DEFERRED" + R2 fade-out swoosh 30 ms + R3 blood ambiance 3D positional explicite.

### Plan séquencé post-revision r2

- **Étape 0** (fait 2026-04-23) : 12 BLOCKING adressés inline + 2 décisions Martin M1+M2.
- **Étape 1** (lead-programmer, 1h) : rédiger ADR Combat Tick Model (ordre `_physics_process`, cache `_prev_position` ownership, interface Mock*, connexion `died` SYNC Hybrid) — référencé dans header GDD "Pending ADR".
- **Étape 2** (lead-programmer, 30 min) : ajouter code pattern `CapsuleShape3D` basis dans `docs/engine-reference/godot/modules/physics.md` + test empirique Gap 2 ShapeCast overlap origine.
- **Étape 3** (qa-lead, 3h) : créer `production/qa/protocols/combat-feel-interview.md` (Gap 5 bloque AC-31/32).
- **Étape 4** (qa-tester, 30 min) : créer `tests/unit/combat/mock_enemy.gd` (Gap 1 bloque AC-05/06/07/25).
- **Étape 5** : re-run `/design-review` (fresh session) → cible verdict APPROVED (r4).

**Decision Martin (2026-04-23)** : Option A "Revise le GDD maintenant" — M1 Option C Hybrid + M2 Option A Resserrer — toutes corrections appliquees inline en session courante. Next: fresh session re-review r4.

---

## Review — 2026-04-23 — Verdict: MAJOR REVISION NEEDED (resolved inline → r4)

**Scope signal**: L (post-revision — cible APPROVED en r5)
**Specialists consultés**: game-designer, systems-designer, gameplay-programmer, audio-director, performance-analyst, godot-specialist, qa-lead, creative-director (senior synthesizer, fresh session indépendante de r1/r2)
**Blocking items**: 20 (dont 2 décisions Martin D-r3-1 + D-r3-2) | **Recommended**: 20+ | **Nice-to-have**: 4 | **ACs nouveaux**: 2 (AC-CMB-49 + AC-CMB-50)
**Prior verdict resolved**: r2 MAJOR REVISION (2026-04-23) — 12 BLOCKING r2 resolus en r3 mais r3 a introduit 16 BLOCKING techniques nouveaux + 2 décisions Martin bloquantes
**Completeness**: 8/8 sections + 3 bonus maintenus

### Summary

Le r3 a proprement résolu les 12 BLOCKING r2 (stale slow-mo propagée, M1 Hybrid `_death_pending`, M2 BUFFER dynamique, ACs 36 ranges, Formula 4 guards, ADR-0005 amendment r2, Rule 6 Gap 2 code pattern, hardware-spec-testbeds.md, AC-37 Performance.get_monitor, debug_hits_last_swing Array[int] getter). Mais la review r4 adversariale (7 specialists fresh session) a identifié **20 BLOCKING nouveaux** non préexistants — issues qui n'existaient pas tant que les r1/r2 n'étaient pas résolus. **5 convergences multi-specialist** fortes :

- **B-R3-01 (systems + gameplay)** : `Basis.looking_at(aim_forward, Vector3.UP)` crash silencieux + fallback Basis.IDENTITY quand aim_forward colinéaire à UP (pitch ±PITCH_LIMIT regard ciel/sol) → hitbox fausse sans avertissement.
- **B-R3-02 (systems + gameplay)** : Union `intersect_shape` + `force_shapecast_update` décrite en prose Rule 6 mais code pattern ne l'implémente pas → implémenteur Sprint 1 sans référence dedup → risque double-kill ou miss.
- **B-R3-03 (systems + gameplay)** : ADR-0005 D-5 amendment r2 inclut `enemy_killed` (signal Combat) dans table ADR qui ne régit que signaux Movement — violation scope architectural.
- **P-05 + P-06 + G-02 (perf + game-designer)** : `_death_pending` et `_buffered_attack` absents de la table reset respawn Edge Case ligne 497 + absent AC-CMB-11 → joueur bloqué Dead post-respawn possible.
- **Audio A-01 + A-06 + A-10 (audio-director seul)** : fade-out swoosh 30 ms scaled par `time_scale` si piloté dans `_process` → 100 ms wall-clock perçus anti-Fantasy ; mix hierarchy/ducking non spécifié ; accessibility audio timing non adapté.

**Creative-director verdict r4** : *"r3 est proche de l'approbation mais pas prêt. Structurellement bon, corrections chirurgicales (~2.5 jours team effort). La Fantasy staccato **tient** mais exige les fixes audio A-01/A-06 pour ne pas diverger au runtime. godot-specialist APPROVED = faux positif à ignorer (angle mort sur Basis.looking_at UP + union code). MAJOR REVISION choisi malgré la petite taille car le GDD n'est pas implémentable sans ces corrections."*

### 20 BLOCKING r4 (résumé par Tier)

**Tier S — stop-the-line (runtime-safety)** :
| # | Item | Source |
|---|------|--------|
| S1 (B-R3-01) | Basis.looking_at UP colinéaire crash | systems + gameplay |
| S2 (B-R3-02) | Union intersect_shape + force_shapecast non codée | systems + gameplay |
| S3 (F-04) | Formula 2 world vs local confusion (90° erreur sweep) | systems |
| S4 (F-09) | Invariant #4 violable safe ranges (SWING+SLOW_MO+COOLDOWN combinaisons) | systems |

**Tier A — architecture + completeness** :
| # | Item | Source |
|---|------|--------|
| A1 (B-R3-03) | ADR-0005 D-5 scope violation enemy_killed | gameplay + systems |
| A2 (P-05 + G-02) | `_death_pending` reset respawn absent | perf + game-designer |
| A3 (P-06) | `_buffered_attack` reset respawn absent | perf |
| A4 (P-08) | AC-CMB-37 OBJECT_COUNT manquant (détection fuites Nodes) | perf |
| A5 (P-12) | AC-CMB-42 60 frames vs testbed 500 frames | perf |

**Tier B — audio Fantasy ownership** :
| # | Item | Source |
|---|------|--------|
| B1 (A-01) | Fade-out swoosh 30 ms scaled par time_scale | audio-director |
| B2 (A-03) | Kill impact `enemy.global_position` ambigu freed | audio-director |
| B3 (A-06) | Mix hierarchy/ducking non spécifié | audio-director |
| B4 (A-10) | Accessibility audio timing non adapté | audio-director |

**Tier C — QA + documentation résiduelle** :
| # | Item | Source |
|---|------|--------|
| C1 (QA-AC-19) | AC-CMB-19 non-déterministe GUT headless | qa-lead |
| C2 (QA-AC-47) | AC-CMB-47 non-annoté [BLOCKED Gap 2] | qa-lead |
| C3 (AC-49) | Rule 15 pas d'invulnérabilité non couvert + invariants structurels | qa-lead |
| C4 (AC-50) | Transition Movement mid-swing non couvert | qa-lead |
| C5 (G-02) | Edge Cases ligne 495 vs Rule 17 contradiction | game-designer |
| C6 (G-03) | `player.transform` résiduel table Interactions | game-designer |
| C7 (G-05) | `V > 25 m/s` TUNNELING_THRESHOLD DEPRECATED résidu | game-designer |

### 2 décisions Martin D-r3-1 + D-r3-2 (tranchées 2026-04-23)

- **D-r3-1 — Buffer 80 ms vs Fantasy staccato** : **Option A Unconditionnel** (statu quo r3). Rationale : Pillar 1 FLOW prioritaire sur lecture puriste Fantasy, précédents Hades/Hollow Knight/DMC (buffer unconditionnel invisible au joueur bien calé). La tension Fantasy B (kill hors-flux "vide") reste ADVISORY playtest AC-CMB-33 — si playtest révèle dilution Fantasy, corriger en Tier 2 via économie Level System (stationnaire rare) plutôt que conditionnement buffer. Martin confirme CD reco.
- **D-r3-2 — Fix scope ADR-0005** : **Option B Section "Cross-Domain References" dans ADR-0005** (non-normative). Moins de churn, préserve contexte historique M1. `enemy_killed` exemption SYNC reste documentée là pour traçabilité mais autorité canonique = Pending ADR Combat Tick Model. technical-director peut réviser via gate TD-ADR-SCOPE si besoin. Martin confirme CD reco.

### Revision r3 → r4 inline (2026-04-23)

Toutes les corrections r4 appliquées en session courante post-Martin D-r3-1 + D-r3-2 :

**Tier S fixes** :
- BLOCK-S1 (B-R3-01) : Rule 6 code pattern ajoute `safe_up` fallback (`Vector3.FORWARD` si `|aim_forward · Vector3.UP| > 0.999`) pour protéger `Basis.looking_at` des cas pitch ±PITCH_LIMIT.
- BLOCK-S2 (B-R3-02) : Rule 6 ajoute code pattern complet `_collect_swing_hits()` avec dedup O(1) via `Dictionary[int, bool]` par `get_instance_id()` — union intersect_shape (tick 0) + force_shapecast_update (tous ticks).
- BLOCK-S3 (F-04) : Formula 2 précise `target_position` en coordonnées locales — `shape_cast.target_position = shape_cast.global_transform.basis.inverse() * sweep_delta`.
- BLOCK-S4 (F-09) : Invariant #4 table D.8 + AC-CMB-36 ajoutent assert runtime sur la somme (`COOLDOWN > SWING + SLOW_MO` ET `SLOW_MO < COOLDOWN/2` strict) — rejète combinaisons aux bornes safe ranges.

**Tier A fixes** :
- BLOCK-A1 (B-R3-03) : ADR-0005 D-5 amendment r2 ajoute "r4 scope note (cross-domain — non-normative)" clarifiant que `enemy_killed` est ref Combat préservée pour traçabilité M1, autorité canonique = Pending ADR Combat Tick Model.
- BLOCK-A2/A3 (P-05 + P-06 + G-02) : Edge Case mort/respawn ligne 497 ajoute `_death_pending = false`, `_buffered_attack = false`, `_slow_mo_start_msec = 0` à la table reset. AC-CMB-11 étendu avec 8 assertions post-respawn.
- BLOCK-A4 (P-08) : AC-CMB-37 ajoute `Performance.OBJECT_COUNT` delta ≤ +5 (détection fuites Nodes/AudioStreamPlayer3D que MEMORY_STATIC ne capture pas).
- BLOCK-A5 (P-12) : AC-CMB-42 bump 60 → 500 frames + annotation `[BLOCKED: VFX System non implémenté]`.

**Tier B fixes audio** :
- BLOCK-B1 (A-01) : Row swoosh précise fade-out wall-clock `Time.get_ticks_msec()` dans `_physics_process` — **pas Tween dans `_process`** (scaled par time_scale). Cas kill-pendant-swing : fade-out immédiat au tick kill.
- BLOCK-B2 (A-03) : Rows Kill impact + Blood ambiance précisent spatialisation via `position` payload signal (pas `enemy.global_position` ambigu freed) + ownership node dans scene root ou pool Audio System.
- BLOCK-B3 (A-06) : Section Audio Requirements ajoute sous-section "Mix hierarchy — Intention kill sequence" avec priorité percue 1-4 + règles de ducking bus (sfx_combat, ambient duck -3dB, swing_active duck -6dB).
- BLOCK-B4 (A-10) : Section Audio Requirements ajoute sous-section "Accessibility audio timing" documentant comportement par mode (Défaut/Mild/Strong/Disabled) + garantie fade-out swoosh wall-clock indépendant du mode.

**Tier C fixes QA + documentation** :
- BLOCK-C1 (QA-AC-19) : AC-CMB-19 reclassé Integration + pattern injection `_get_time_msec: Callable` substituable pour mocking déterministe wall-clock. Fallback manuel via Godot profiler si injection non implémentée pre-Sprint 1 (decision lead-programmer).
- BLOCK-C2 (QA-AC-47) : AC-CMB-47 annoté `[BLOCKED: Gap 2]` + 2 variantes (A `intersect_shape` requis / B redondant) selon résultat test empirique lead-programmer.
- BLOCK-C3 (AC-49) : Nouveau AC-CMB-49 `[Logic — BLOCKING]` — Rule 15 no invulnérabilité (inspection statique source) + invariants structurels B-R3-03 (direct child Player + `physics_process_priority == 0`).
- BLOCK-C4 (AC-50) : Nouveau AC-CMB-50 `[Integration — BLOCKING]` — transitions state Movement mid-swing (Grounded→Airborne, Airborne→Grounded, Grounded→Dashing, Airborne→WallRunning) avec 6 assertions par sous-cas.
- BLOCK-C5 (G-02) : Edge Case ligne 495 split sous-cas (a) sans collider → AC-CMB-20 / (b) avec colliders → AC-CMB-41 Rule 17 Hybrid — contradiction Rule 17 vs Edge Case résolue.
- BLOCK-C6 (G-03) : Table Interactions ligne ~206 retire `player.transform` résiduel (r1 correction Section F complétée).
- BLOCK-C7 (G-05) : Edge Case ligne 487 retire "si V > 25 m/s" résidu TUNNELING_THRESHOLD DEPRECATED.

**RECOMMENDED intégrés** :
- godot-specialist Reco-A/B : invariants structurels (direct child + priority 0) documentés dans Published API r4 note + AC-CMB-49 Partie B.
- Published API ajoute `_buffered_attack`, `_slow_mo_start_msec`, `_slow_mo_active` explicitement.
- Rule 3 documente D-r3-1 buffer unconditionnel tension Fantasy B reconnue et ADVISORY playtest AC-33.
- Mots bannis list étendue `satisfaisant`/`récompense`/`impressionnant` (AC-CMB-33).
- AC-CMB-08 ajoute prereq `[Gap 7]` explicite.
- AC-CMB-17 précise mécanisme observable rejet config (debug assert vs release non-enforced).
- AC-CMB-28 ajoute phrase d'isolation Swinging→AC-CMB-41.
- AC-CMB-31 clarifie "4 descripteurs distincts par tester + 80% panel + N≥5".
- AC-CMB-34 N≥5 + médiane ≥4 + 70% des testeurs.
- AC-CMB-35a corrige evidence path (`tests/perf/` au lieu de `docs/engine-reference/`) + justifie seuil 5 ms = ~30% frame budget Tier 1.
- AC-CMB-41 documente vérification indirecte (résultat final + code review complémentaire).

**Files modifiés r4** :
- `design/gdd/player-combat-system.md` (r4 massive, ~20 sections touchées + 2 ACs nouveaux)
- `docs/architecture/adr-0005-movement-signals-architecture.md` (r4 scope note cross-domain)
- `design/gdd/reviews/player-combat-system-review-log.md` (append r4 entry)
- `design/gdd/systems-index.md` (status r4 pending r5)

**Gaps ouverts maintenus (tracés vers Sprint 1)** :
- Gap 1 MockEnemy — owner qa-tester pré-Sprint 1 (AC-05/06/07/25 bloqués)
- Gap 2 test empirique Godot 4.6 ShapeCast overlap origine — owner lead-programmer (AC-47 bloqué)
- Gap 5 protocole playtest — owner qa-lead (AC-31/32/33 bloqués)
- Gap 7 pattern CapsuleShape3D basis docs/engine-reference — owner lead-programmer (AC-08 prereq)
- Pending ADR Combat Tick Model — owner lead-programmer pré-Sprint 1 (hérite exemption SYNC enemy_killed cross-domain)

**Next priority** : **`/clear` + `/design-review design/gdd/player-combat-system.md` fresh session r5** pour verdict APPROVED cible. 7 specialists + CD relancés avec contexte vierge pour jugement indépendant post-r4. Référence r4 verdict complet dans cette section.

**Decision Martin (2026-04-23)** : Option A "Revise le GDD maintenant" — D-r3-1 Option A (buffer unconditionnel) + D-r3-2 Option B (section cross-domain ADR-0005) — toutes corrections appliquées inline en session courante. Next: fresh session re-review r5 target APPROVED.

---

## Review — 2026-04-23 — Verdict: NEEDS REVISION CONDITIONAL (resolved inline → r5.1 APPROVED)

**Scope signal**: S (Small, 1-2h corrections inline + 2 décisions Martin) — target atteint APPROVED r5.1
**Specialists consultés**: game-designer, systems-designer, gameplay-programmer, audio-director, performance-analyst, godot-specialist, qa-lead, creative-director (senior synthesizer, fresh session indépendante r1-r4)
**Blocking items**: 5 (dont 2 décisions Martin DEC-r5-1 + DEC-r5-2) | **Recommended**: 20+ (5 sélectionnées inline) | **Faux positifs rejetés**: 3
**Prior verdict resolved**: r4 MAJOR REVISION (2026-04-23) — 20 BLOCKING r4 resolus en r4 inline + 2 décisions Martin D-r3-1/D-r3-2, r5 audit indépendant fresh identifie 4 vrais BLOCKING + 1 promu par CD
**Completeness**: 8/8 sections + 3 bonus maintenus, 50 ACs (AC-CMB-01 à AC-CMB-50)

### Summary

r4 était à 95% complet. La review r5 adversariale (7 specialists fresh indépendants) a identifié **11 BLOCKING bruts + 4 RECOMMENDED**. Après synthèse creative-director avec rejet de 3 faux positifs (godot B1 FORWARD/BACK hors pitch lock, godot B3 exagération quantitative "480 allocations" vs ~16 réels, gameplay BLOCK-r5-02 Dictionary typed mineur projet pinné 4.6), **4 vrais BLOCKING r5** validés + 1 promu par CD depuis RECOMMENDED systems-designer.

**7 specialists fresh session r5** :
1. `game-designer` — **APPROVED** (0 BLOCKING, 2 RECOMMENDED) — Fantasy staccato effectivement servie, aucun résidu stale (V>25, 0.15/100ms, player.transform, TUNNELING_THRESHOLD actif)
2. `systems-designer` — **APPROVED CONDITIONNEL** (4 BLOCKING) : B-r5-01 flick-aim sweep comportement non documenté, B-r5-02 live-tuning invariant bypass, B-r5-03 Formula 4 hardcode 60 Hz, B-r5-04 `collider_id` vs `get_instance_id()` égalité non vérifiée
3. `gameplay-programmer` — **MINOR BLOCKING** (2) : BLOCK-r5-01 Rule 6 ligne 64 contradiction target_position vs Formula 2 r4, BLOCK-r5-02 typed Dict/Array post-cutoff (rejeté faux positif)
4. `audio-director` — **CONDITIONAL PASS** (2 BLOCKING) : A-r5-01 fade-out "immédiat" vs DEFERRED contradiction, A-r5-02 ACs audio manquants (AC-CMB-audio-01/02)
5. `performance-analyst` — 2 BLOCKING : P-R5-06 AC-42 non-headless GPU runner non documenté, P-R5-07 PhysicsShapeQueryParameters3D.new() alloc per-swing vs OBJECT_COUNT+5 (convergence godot B3)
6. `godot-specialist` — **CONCERNS** (4 BLOCKING) — rattrapage r4 faux positif : B1 guard safe_up cas FORWARD/BACK (rejeté hors pitch lock), B2 basis.inverse() invariant orthonormal, B3 alloc per-tick (convergence perf), B4 instance_id stable reformulation
7. `qa-lead` — **APPROVED CONDITIONNEL** (2 FAIL + 3 WEAK + 3 BLOCKING pre-Sprint) : FAIL AC-19 fallback B non spécifié, FAIL AC-41 statut code review ambigu, WEAK AC-10/14/35b

**creative-director synthesizer r5** : Verdict **CONDITIONAL** (non MAJOR REVISION, non APPROVED direct). CD-GDD-ALIGN: **CONCERNS** (non REJECT). Fantasy préservée structurellement mais risques lisibilité implémentation Sprint 1 (Rule 6 contradiction + audio "immediat" trompeur). Scope S 1-2h edits inline.

### 5 BLOCKING r5 (validés par CD) + 2 décisions Martin

| # | Item | Source | Convergence |
|---|------|--------|-------------|
| BLOCK-r5-A | Rule 6 ligne 64 contradiction target_position "en local si basis identité" vs Formula 2 r4 `basis.inverse() * sweep_delta` | gameplay BLOCK-r5-01 + systems B-r5-01 + godot B2 | **TRIPLE** |
| BLOCK-r5-B | Audio ligne 830 "fade-out immédiat au tick du kill" factuellement impossible avec CONNECT_DEFERRED (55 ms perçus à time_scale 0.3) | audio A-r5-01 | Simple critique Fantasy |
| BLOCK-r5-C | AC-CMB-19 branche B fallback profiler manuel ne produit pas verdict binaire — décision lead-programmer non tranchée | qa FAIL 1 + game-designer REC-R5-02 + perf P-R5-13 path | **TRIPLE implicite** — requiert DEC-r5-1 Martin |
| BLOCK-r5-D | Gap 2 ligne 66 auto-contradiction : "confirmé non modifié 4.6" vs Open Question 1 "test empirique requis" | godot-specialist + systems indirect | Double |
| BLOCK-r5-E (promu CD) | Live-tuning bypass invariants #4/#6/#7 via Godot Inspector — AC-17 dit "non-MVP" mais Sprint 1 live-tuning garanti | systems B-r5-02 (promu par CD) | Simple + arbitrage CD — requiert DEC-r5-2 Martin |

### 2 décisions Martin DEC-r5-1 + DEC-r5-2 (tranchées 2026-04-23)

- **DEC-r5-1 — AC-CMB-19 vérification wall-clock slow-mo timing** : **Option A Injection Callable** `_get_time_msec: Callable = Time.get_ticks_msec` substituable. lead-programmer implémente pre-Sprint 1. AC-CMB-19 reste `[Integration — BLOCKING]` déterministe automatisé CI. Option B (fallback profiler manuel ADVISORY) rejetée — trou dans le filet CI inacceptable. Rationale : Pillar 1 no-regression silencieuse. Coût ~15 lignes GDScript + 1 test injection.
- **DEC-r5-2 — Live-tuning invariants runtime assert** : **Option A `_validate_invariants()` runtime MVP** — appelé en début de chaque `_physics_process` sous `if OS.is_debug_build():`. Re-calcule invariants #4/#6/#7 et `assert()` panique si violation. Cost 1 branchement + 3 asserts/tick en debug, zéro en release. AC-CMB-17 test procedure étendue avec mutation post-`_ready()` et verification assert fail au prochain tick. Options B (hot-reload hook) et C (statu quo `_ready()` seulement) rejetées.

### 3 faux positifs rejetés par CD (tracés, pas de correction)

- **godot B1 partie "aim_forward == Vector3.FORWARD/BACK"** : hors range par PITCH_LIMIT lock actuel, faux positif.
- **godot B3 exagération quantitative "480 allocations/swing"** : ~16 allocations max (8 ticks × 2 locaux + 5 tick 0), pas 480. Mais convergence avec perf P-R5-07 reste valide → addendum Rule 6 ADR-0005 D-9 exemption documenté.
- **gameplay BLOCK-r5-02 "Dictionary typed post-cutoff"** : projet pinné Godot 4.6, syntaxe `Dictionary[K, V]` 4.4+ valide. Annotation utile mais pas BLOCKING.

### Revision r4 → r5.1 inline (2026-04-23)

Toutes les corrections r5 appliquées en session courante post-Martin DEC-r5-1 + DEC-r5-2 :

**5 BLOCKING fixes** :
- BLOCK-r5-A (Rule 6 ligne 64) : remplacé `target_position = player.global_position - _prev_position (delta ... exprime en local si basis identite)` par `target_position = shape_cast.global_transform.basis.inverse() * (player.global_position - _prev_position) (delta ... converti en local via basis.inverse() cf. Formula 2 r4 S-F-04)`. Bug direction sweep jusqu'à 90° corrigé documentairement (Formula 2 r4 déjà correct, Rule 6 alignée).
- BLOCK-r5-B (Audio ligne 830) : reformulé "fade-out déclenché immédiatement" en "dispatché DEFERRED au frame N+1 post-kill, perception d'immédiateté assurée par ducking -6 dB bus `swing_active` release 30 ms (règle 3 Mix hierarchy ligne 852)". Sound-designer ne tentera pas SYNC override.
- BLOCK-r5-C (AC-CMB-19 post-DEC-r5-1=A) : purgé "Alternative fallback Manual QA Lead" + "Decision lead-programmer requise", remplacé par "Décision Martin DEC-r5-1 tranchée Option A Injection Callable BLOCKING pre-Sprint 1, pas de fallback ADVISORY".
- BLOCK-r5-D (Gap 2 ligne 66) : reformulé "confirmé Godot 4.0+, non modifié 4.4/4.5/4.6" en "non modifié selon migration guides officiels 4.4/4.5/4.6 mais non vérifié empiriquement sur cette codebase Godot 4.6 + Jolt — Gap 2 deadline fin Sprint 1 Combat impl par lead-programmer, résultat consigné `docs/engine-reference/godot/modules/physics.md`".
- BLOCK-r5-E (AC-CMB-17 post-DEC-r5-2=A) : ajout section "Décision Martin DEC-r5-2 tranchée Option A `_validate_invariants()` runtime MVP en début de `_physics_process` sous `if OS.is_debug_build():`" + test procedure étendue (mutation `ATTACK_BUFFER_MS = 100` post-`_ready()` → assert fail au prochain tick).

**5 RECOMMENDED sélectionnées** :
- Rule 6 addendum ADR-0005 D-9 exemption explicite : ~16 allocations/swing documentées avec 4 clauses justification (taille bornée, scope court, AC-37 soak empirique, anti-YAGNI) + clause rollback conditionnel si AC-37 échoue → refactor pool + exemption déléguée Pending ADR Combat Tick Model.
- Rule 10 ligne 173 : reformulé "instance_id stable ... is_instance_valid() sert de garde complémentaire" en "instance_id stable après queue_free ... is_instance_valid() est OBLIGATOIRE avant instance_from_id, pas complémentaire. Ne pas extrapoler à d'autres contextes codebase."
- AC-CMB-35b : setup étendu "joueur en état Dashing avec velocity.length() == 30.0 m/s pendant toute la fenêtre active" (worst case ShapeCast, pas statique).
- AC-CMB-41 : clarifié "7 assertions GUT = critère BLOCKING Done autonome, capture diff PR = ADVISORY non bloquant sprint review". AC-20/28/50 captureront divergence si ordre SYNC exotique.
- AC-CMB-42 : annoté "**requiert un runner GPU Tier 1 (non headless)** — draw_calls + frame time Forward+ non mesurables CI Godot headless. Option future split AC-42a headless (OBJECT_COUNT Decal delta) + AC-42b GPU runner. Pour MVP Sprint 1 reste `[BLOCKED: VFX System + runner GPU]`".

**Files modifiés r5.1** :
- `design/gdd/player-combat-system.md` (r5.1 : 5 BLOCKING + 5 RECOMMENDED inline, ~10 sections touchées, header status bumped r4→r5.1)
- `design/gdd/reviews/player-combat-system-review-log.md` (append r5 entry — ce fichier)
- `design/gdd/systems-index.md` (status r5.1 APPROVED pending optional spot-check)

### Plan post-revision r5 → APPROVED r5.1

- **Étape 0** (fait 2026-04-23) : 5 BLOCKING adressés inline + 2 décisions Martin DEC-r5-1/DEC-r5-2 tranchées + 5 RECOMMENDED sélectionnées.
- **Étape 1 optionnelle** (spot-check 15-20 min par specialist) :
  - audio-director verdict sur ligne 830 corrigée (DEFERRED + ducking nommé comme solution architecturale)
  - qa-lead verdict sur AC-CMB-19 post-DEC-r5-1=A (injection Callable BLOCKING, fallback purgé) + AC-CMB-41 clarification
  - godot-specialist verdict sur Rule 6 contradiction purgée + Gap 2 ligne 66 auto-contradiction purgée + Rule 10 reformulation
- **Étape 2** (lead-programmer, pre-Sprint 1) : Pending ADR Combat Tick Model avec exemption ADR-0005 D-9 documentée (4 clauses + rollback conditionnel AC-37) + injection Callable `_get_time_msec` + guard runtime `_validate_invariants()` + test empirique Gap 2 ShapeCast overlap origine consigné `docs/engine-reference/godot/modules/physics.md`.
- **Étape 3** : bump statut GDD → APPROVED (sans r5.2 fresh review — les spot-checks suffisent si clean).
- **Open Gaps restants non-bloquants APPROVED** : Gap 1 MockEnemy (qa-tester pre-Sprint 1), Gap 5 playtest protocol (qa-lead pre-playtest), Gap 7 CapsuleShape3D basis pattern engine-reference (lead-programmer pre-Sprint 1). Tous owners et échéances tracés.

**Decision Martin (2026-04-23)** : Option A "Revise now" — DEC-r5-1 Option A (AC-19 injection Callable) + DEC-r5-2 Option A (runtime assert live-tuning) — toutes corrections appliquées inline en session courante. Next : spot-checks optionnels audio + qa + godot sinon bump APPROVED direct.

---

## Review — 2026-04-23 — Verdict: NEEDS REVISION (r5.2 parallel fresh session post-r5.1 — CONV-1 non-captured)

**Scope signal**: S (1 critical bug + 3 Martin decisions + 5 RECOMMENDED)
**Specialists consultés**: game-designer, systems-designer, gameplay-programmer, audio-director, performance-analyst, godot-specialist, qa-lead, creative-director (senior synthesizer, fresh session indépendante r1-r4 ET r5.1)
**Blocking items**: 1 CONV-1 critique + 3 décisions Martin
**Prior verdict**: r5.1 APPROVED pending spot-check (2026-04-23) — MAIS CONV-1 faux positif r4 persiste malgré r5.1

### Summary

Le r5.1 APPROVED pending spot-check a résolu 5 BLOCKING + 2 décisions Martin (DEC-r5-1 AC-19 injection, DEC-r5-2 live-tuning runtime assert) + 5 RECOMMENDED + a rejeté 3 faux positifs. **MAIS** une review r5.2 fresh session indépendante (menée en parallèle) a identifié un **faux positif r4 non-capturé par r5.1** : le code pattern Rule 6 + Note Gap 7 + Formula 2 + AC-CMB-08 utilise toujours `Basis.looking_at(aim_forward, safe_up) * Basis.from_euler(Vector3(PI/2, 0, 0))` pour aligner l'axe Y capsule sur aim_forward — **mathématiquement incorrect** (produit un axe Y antiparallèle à aim_forward).

**Convergence multi-specialist r5.2 forte** :
- **CONV-1 (gameplay-programmer + godot-specialist fresh session)** : signe Basis incorrect. Fix : construction directe `Basis(right, aim_forward, local_z)` via cross product + garde déterminant. Helper `_build_capsule_basis()` partagé par `_tick0_intersect_shape_overlap()` et `_collect_swing_hits()`.

**creative-director verdict r5.2** : *"r5.1 a bien résolu la majorité des issues techniques mais a reproduit l'angle mort r4 sur la composition Basis. Convergence r5.2 indépendante confirme le faux positif. NEEDS REVISION S-scope — 1 correction chirurgicale + 3 décisions Martin + 5 RECOMMENDED. Un cycle r6 ciblé (~3h team-day) pour verdict APPROVED final."*

### 3 décisions Martin r5.2 (tranchées 2026-04-23)

- **D-r4-1 (AC-CMB-42 decal cap)** : Option A **ADVISORY** (reclassement depuis BLOCKING [BLOCKED: VFX]) + note "promue BLOCKING dès VFX GDD disponible". Rationale CD : désamorce gate zombie sur système non implémenté sans perdre traçabilité contract Combat→VFX.
- **D-r4-2 (game-designer REC-04 duty cycle)** : **Option A Ajouter** invariant #8 `SWING_DURATION_MS / (SWING_DURATION_MS + ATTACK_COOLDOWN_MS) < 0.4` avec assert runtime debug. Default 120/520 = 0.23 << 0.4 (marge confortable). Protège staccato silencieux contre tuning dérive.
- **D-r4-3 (audio-director R-2 ducking)** : **Option A Conserver -6dB + documenter risque** (cas kill précoce swing<20ms chevauche fade swoosh/clac, réévaluer Tier 2 via playtest si Fantasy staccato dégradée). Pas de hard-cut MVP (risque cut audible trop net kill standard).

### Revision r5.2 appliquée (2026-04-23)

**Addendum r5.2 ajouté en fin de GDD** (`design/gdd/player-combat-system.md` section "Addendum r5.2 — CONV-1 faux positif r4") avec :
1. Code pattern correct `_build_capsule_basis()` construction directe via cross product (remplace Basis.looking_at * from_euler)
2. 4 occurrences à corriger identifiées (lignes ~87, ~135, ~377, ~931)
3. 3 décisions Martin D-r4-1/2/3 appliquées inline
4. 5 RECOMMENDED retenues : REC-01 mots bannis unifiés, REC-02 Likert AC-34 reformulé, REC-03 AC-CMB-51 nouveau (fade-out swoosh wall-clock vérification), perf P-1 AC-CMB-35a inclut intersect_shape, perf P-2 Gap 6 retire hardware inline
5. AC-CMB-08 r5.2 précision : test GUT sur 100 valeurs aim_forward sphère unitaire

**Convergence avec r5.1 apparente mais divergence sur CONV-1** : r5.1 a rejeté le soupçon godot-specialist sur la composition Basis comme "faux positif" — or r5.2 indépendante confirme que c'était LE vrai positif. Recommandation : traiter r5.2 Addendum comme source of truth pour la correction Basis ; les autres éléments r5.1 restent valides.

**Files modifiés r5.2** :
- `design/gdd/player-combat-system.md` (Addendum r5.2 en fin de fichier, ~90 lignes)
- `design/gdd/reviews/player-combat-system-review-log.md` (cette entrée)

**Next priority** :
- **Étape 1** : propager les 4 corrections CONV-1 dans le corps principal du GDD (lignes 87, 135, 377, 931) — peut être fait en session suivante si edit war actif
- **Étape 2** : appliquer les 5 RECOMMENDED retenues (REC-01/02/03 + perf P-1/P-2) dans le corps
- **Étape 3** : fresh `/design-review` r6 — target APPROVED final

**Decision Martin (2026-04-23)** : Option A "Revise now" — D-r4-1/2/3 tous Option A (reco CD) — Addendum r5.2 ajouté en session courante comme source of truth, propagation corps GDD déléguée à session suivante (auto-approve low-risk par CLAUDE.md).

---

## Review — 2026-04-23 — Verdict: APPROVED r6 (propagation Addendum r5.2 achevée inline via revise-now flow solo mode)

**Scope signal**: S (Small, ~2-3h corrections inline mécaniques — pas de nouvelle décision créative, application des verdicts r5.2 déjà tranchés)
**Specialists consultés**: aucun spawn (mode solo — `production/review-mode.txt = solo`). Analyse single-session par le main agent, référence adversariale = Addendum r5.2 (convergence multi-specialist gameplay-programmer + godot-specialist + creative-director déjà documentée).
**Blocking items**: 11 identifiés r6 → **0 résiduels** après propagation inline
**Prior verdict resolved**: r5.1 APPROVED + 3 spot-checks CLEAN (état pré-r5.2) contredits par Addendum r5.2 NEEDS REVISION (CONV-1 + 3 Martin + 5 REC). r6 résout la contradiction header vs footer en propageant Addendum r5.2 dans le corps.
**Completeness**: 8/8 sections + 3 bonus maintenus + 2 nouveaux ACs (AC-CMB-47-Prelim + AC-CMB-51) → **52 ACs au total** (AC-CMB-01 à AC-CMB-51 + AC-CMB-47-Prelim numéroté inséré avant AC-CMB-47)

### Summary

Le GDD était en état **schizophrène** : header ligne 3 disait `APPROVED r5.1` + 3 spot-checks CLEAN, footer (Addendum r5.2) disait `pending revise r5.2 avant fresh re-review r6 cible APPROVED`. Cette contradiction reproduisait exactement le pattern r2 diagnostiqué par creative-director (*"GDD schizophrène — deux vérités contradictoires, la vérité fausse occupait plus d'emplacements"*). Cause racine : l'Addendum r5.2 avait été ajouté en queue de fichier avec délégation explicite de la propagation à "une session suivante", délégation qui n'était jamais arrivée.

La review r6 (solo mode, main agent analyse) a identifié **11 BLOCKING** tous de nature propagation documentaire — aucun nouveau design, aucune nouvelle décision Martin, aucun nouveau ADR. Application mécanique des verdicts Addendum r5.2 déjà tranchés. Option A "Revise now" confirmée par Martin, propagation inline session courante.

### 11 BLOCKING r6 résolus inline

| # | Item | Source Addendum r5.2 | Fix propagé |
|---|------|----------------------|-------------|
| 1 | Contradiction statut header r5.1 APPROVED vs footer r5.2 pending | Status post-r5.2 section | Header bumpé r6 APPROVED + systems-index aligné |
| 2 | CONV-1 Basis mathématiquement incorrect 4 occurrences | CONV-1 section | Helper `_build_capsule_basis()` centralisé Rule 6 Note Gap 7 + 4 call sites appellent le helper (Rule 6 `_tick0_intersect_shape_overlap`, Note Gap 7 doc math, Formula 2, AC-CMB-08) |
| 3 | Invariant #9 duty cycle absent du tableau D.8 | Martin D-r4-2 | Ligne ajoutée tableau D.8 `SWING / (SWING + COOLDOWN) < 0.4` (120/520 = 0.23 ✅) + AC-CMB-17 étendu clause 8 |
| 4 | AC-CMB-42 BLOCKING vs Martin D-r4-1 ADVISORY | Martin D-r4-1 | Tag classification changé `[Integration — ADVISORY]` + annotation "promue BLOCKING dès VFX GDD disponible" |
| 5 | D-r4-3 "Cas kill précoce (swing < 20 ms)" note absente Section Audio Mix hierarchy | Martin D-r4-3 | Bullet #5 ajouté sous "Règles de ducking" avec alternatives Tier 2 examinées (attenuation -9 dB conditionnelle, hard-cut, transient filter) |
| 6 | AC-CMB-31 liste mots bannis non unifiée (4 vs 3 dans 33) | REC-01 game-designer | Liste étendue à 7 mots centralisée dans AC-CMB-31 + AC-CMB-33 pointe vers AC-CMB-31 |
| 7 | AC-CMB-34 Likert item teste Fantasy B récompense pas Fantasy A | REC-02 game-designer | Item reformulé `"Le ralenti m'a semblé faire partie du rythme de jeu, pas une pause séparée"` |
| 8 | AC-CMB-51 nouveau fade-out swoosh wall-clock non créé | REC-03 game-designer | AC-CMB-51 inséré après AC-CMB-50, pattern injection `_get_time_msec: Callable` identique AC-CMB-19 DEC-r5-1 |
| 9 | CONV-2 AC-CMB-47-Prelim non créé | CONV-2 gameplay + qa | AC-CMB-47-Prelim inséré avant AC-CMB-47 + deadline "fin-des-épics pré-Sprint 1" tracée |
| 10 | Gap 6 contient encore `GTX 1650 Ti + Core i5 12gen` inline | P-2 perf | Specs hardware inline retirées, Gap 6 pointe exclusivement vers `docs/architecture/hardware-spec-testbeds.md` |
| 11 | AC-CMB-35a mesure 3 substeps isolés, pas `_collect_swing_hits()` COMPLET | P-1 perf | AC reformulé pour expliciter `_collect_swing_hits()` COMPLET + warmup 60 swings complets |

### Leçon opérationnelle r6

Écrire un Addendum en fin de fichier et déléguer la propagation à une session suivante **garantit** le drift documentaire, diagnostiqué originellement en r2 comme "GDD schizophrène". La règle r6 : la propagation inline est obligatoire dans la même session que l'identification d'une convergence multi-specialist. À documenter dans `.claude/docs/review-methodology.md` (à créer) pour que les futures reviews r-n+ ne reproduisent pas le pattern.

### Status post-r6

Status GDD : **APPROVED r6** — 0 BLOCKING résiduel corps du GDD, Addendum r5.2 conservé en fin de fichier comme **traçabilité historique** (avec annotation `Status historique — voir header ligne 3`). Aucune fresh re-review r7 nécessaire si les edits sont validés sains par Martin.

**Gaps ouverts maintenus (tracés vers Sprint 1 — non-bloquants pour APPROVED)** :
- Gap 1 MockEnemy — owner qa-tester pré-Sprint 1 (AC-05/06/07/25 bloqués)
- Gap 2 test empirique Godot 4.6 ShapeCast overlap origine — owner lead-programmer (AC-47-Prelim r6 ownerise, deadline fin-des-épics pré-Sprint 1 ; AC-47 bloqué tant que Prelim non exécuté)
- Gap 5 protocole playtest — owner qa-lead (AC-31/32/33/34 bloqués)
- Gap 7 pattern CapsuleShape3D basis documentation `docs/engine-reference/godot/modules/physics.md` — owner lead-programmer pré-Sprint 1 (AC-08 prereq)
- Pending ADR Combat Tick Model — owner lead-programmer pré-Sprint 1 (hérite exemption SYNC enemy_killed cross-domain + helper `_build_capsule_basis` code pattern + exemption ADR-0005 D-9 zero-alloc)

**Decision Martin (2026-04-23)** : Option A "Réviser maintenant" — propagation Addendum r5.2 inline achevée en session courante. Status bumpé APPROVED r6. L'Addendum d'origine est conservé en fin de fichier à des fins historiques (traçabilité revise-now flow) mais ne doit plus être traité comme vivant.

---

## Review — 2026-04-23 — Verdict: APPROVED CONDITIONAL → APPROVED (resolved inline, fresh r6 independent)

**Scope signal**: S (post-revision — inline fixes only, ~2h team effort parallélisable)
**Specialists consultés**: game-designer, systems-designer, gameplay-programmer, godot-specialist, audio-director, performance-analyst, qa-lead + creative-director (senior synthesizer) — 8 sessions fresh indépendantes, aucune mémoire des r1-r5.2.
**Blocking items**: 9 (convergence quadruple sur CONV-1 propagation, plus 5 gaps authentiques audio + perf + qa + godot) | **Recommended**: 14 | **Faux positifs rejetés**: 0 (creative-director a consolidé 6 duplicates mais rejeté aucun BLOCKING net)
**Prior verdict resolved**: r5.1 auto-déclarée APPROVED pending spot-check — mais Addendum r5.2 appendu au bas contredisait le header ; r6 fresh a audité le GDD actuel état complet.
**Completeness**: 8/8 sections + 3 bonus maintenus, 52 ACs (AC-CMB-01 à AC-CMB-52 + AC-CMB-audio-01/02)

### Summary

Le GDD r5.1 était structurellement solide mais documentairement incohérent : header ligne 3 déclarait `APPROVED pending spot-check` alors que l'Addendum r5.2 footer disait `pending revise r5.2`. La review r6 fresh a confirmé cette contradiction et identifié que l'Addendum avait été partiellement propagé (CONV-1 `_build_capsule_basis()` + Invariant #9 + D-r4-3 "Cas kill précoce" + AC-CMB-42 reclass ADVISORY) mais qu'il restait 5 gaps authentiques hors du scope Addendum :

1. **AC-CMB-17 scope `_validate_invariants()` incomplet** — description mentionnait `#4, #6, #7` sans #9.
2. **AC-CMB-51 REC-03** non ajouté à Section H (seulement référencé dans Addendum).
3. **AC-CMB-52 Gap 4** — formalisation `attacked()` hors `_physics_process` via inspection statique manquante.
4. **AC-CMB-audio-01/02** contrats audio Combat-side manquants (audio-director R1 convergence).
5. **Gap 8 ShapeCast3D.margin Jolt** — engine-reference note "may differ" sans owner/deadline Combat-side.
6. **AC-CMB-41 clause (8) grep structural SYNC** — un implémenteur exotique pouvait passer les 7 assertions runtime en trichant via `call_deferred`.
7. **AC-CMB-19 branche C accessibility disable** — aucun AC vérifiait `Engine.time_scale == 1.0 constant` en mode `reduce_motion_disable_slow_mo == true`.
8. **AC-CMB-35b setup V=30 physiquement non-tenable** — 1000 frames × 30 m/s = 500 m parcourus → collision mur → velocity → 0 → p99 sous-estimait le vrai worst case ShapeCast.
9. **Mix hierarchy ducking paramétrage sous-spécifié** — courbe + volume nominal swoosh non définis (audio-director BLOCKING #1).

### 9 BLOCKING r6 (convergences)

| # | Item | Source convergence |
|---|------|---------------------|
| 1 | CONV-1 Basis propagation (vérification 4 emplacements) | QUADRUPLE (game + systems + gameplay + godot) — vérifié, OK |
| 2 | Invariant #9 scope `_validate_invariants()` | Double (game + systems) |
| 3 | AC-CMB-51 REC-03 Section H | Double (game + audio) |
| 4 | Gap 8 ShapeCast3D.margin Jolt | godot-specialist seul |
| 5 | Ducking courbe + volume nominal | audio-director seul |
| 6 | AC-CMB-audio-01/02 contrats | audio-director seul |
| 7 | AC-CMB-35b setup physiquement tenable | performance-analyst seul |
| 8 | AC-CMB-42 reclass ADVISORY appliqué | performance + game-designer |
| 9 | Triple micro-gap qa (AC-41 grep SYNC + AC-19 branche C + AC-52 Gap 4) | qa-lead |

### Creative-director verdict r6

*"r5.1 est à 95% APPROVED. La Fantasy staccato tient structurellement — aucun BLOCKING ne touche au cœur identitaire. Les 9 BLOCKING sont tous des gaps de traçabilité, testabilité, ou documentation technique. La contradiction header APPROVED vs Addendum r5.2 pending revise est le signal clé : le GDD est schizophrène jusqu'à ce que r5.2 soit propagé. Scope S, aucune décision Martin nouvelle, Sprint 1 readiness = APPROVED post-revise r5.2."*

CD-GDD-ALIGN: **CONCERNS** (non REJECT — Fantasy préservée structurellement).

### Décisions Martin nouvelles requises

**Aucune.** Les 5 décisions déjà tranchées (D-r4-1, D-r4-2, D-r4-3 via Addendum r5.2 + DEC-r5-1, DEC-r5-2 via r5) couvrent l'intégralité du périmètre. La revise r6 est propagation documentaire + addendum chirurgical.

### Revision r6 inline (2026-04-23)

Toutes les corrections r6 appliquées en session courante post-creative-director synthesis :

**Inline fixes (9 BLOCKING résolus)** :
- BLOCK-r6-01 : AC-CMB-17 description `_validate_invariants()` étendu à `#4, #6, #7, #9` + Test #9 dédié procedure (mutation SWING=200 + COOLDOWN=300 → assert fail).
- BLOCK-r6-03 : AC-CMB-51 ajouté Section H — fade-out swoosh wall-clock `[25, 50] ms` vérification via injection Callable (pattern identique AC-CMB-19 DEC-r5-1).
- BLOCK-r6-04 : Gap 8 nouveau (ShapeCast3D.margin Jolt test empirique) ajouté après Gap 7, owner lead-programmer, échéance pré-Sprint 1, regroupement avec Gap 2.
- BLOCK-r6-09a : AC-CMB-41 clause (8) grep structural ajouté — `grep -nE 'player\.died\.connect.*CONNECT_DEFERRED' doit retourner 0 match`.
- BLOCK-r6-09b : AC-CMB-19 branche C accessibility disable ajoutée — test 5 kills consécutifs avec `reduce_motion_disable_slow_mo = true` + teardown `Engine.time_scale = 1.0`.
- BLOCK-r6-09c : AC-CMB-52 nouveau ADVISORY — Gap 4 formalisé inspection statique grep `assert(Engine.is_in_physics_frame())` dans handler `attacked()`.
- BLOCK-r6-06 : AC-CMB-audio-01 (multi-kill `_kill_sound_played_this_swing`) + AC-CMB-audio-02 (ducking event ordering) ajoutés Section H `[Integration — ADVISORY pre-playtest, BLOCKED Audio System GDD]`.
- BLOCK-r6-07 : AC-CMB-35b split en 2 mesures distinctes — (1) Worst case ShapeCast p99 sur 8 ticks actifs × 100 swings (velocity forcée no collision) + (2) Soak global 1000 frames normale.
- BLOCK-r6-05 : Mix hierarchy ducking paramétrage précisé — courbe exponentielle + volume nominal swoosh ≤ -6 dB + bus naming proposition `audio_bus_config.tres` data-driven (autorité canonique finale Audio System GDD).

**Header ligne 3 mis à jour** : status bumpé avec référence explicite review r6 + 9 BLOCKING résolus listés + "Aucun BLOCKING résiduel".

**Addendum footer ligne 1187** : passage obsolète "pending revise r5.2" rayé + note historique confirmant propagation achevée et review r6 APPROVED CONDITIONAL.

### Faux positifs rejetés

Aucun faux positif net sur les 15 BLOCKING bruts. Creative-director a consolidé 6 duplicates (CONV-1 répété 4× = 1 BLOCKING, Invariant #9 cité 2× = 1 BLOCKING). Pas de rejet façon r5 (B1/B3/BLOCK-r5-02).

### Convergences multi-specialist

- **Propagation Addendum r5.2 CONV-1 Basis** : **QUADRUPLE** (game-designer + systems-designer + gameplay-programmer + godot-specialist). Résultat : propagation vérifiée effective aux 4 emplacements corps.
- **Invariant #9 Section D.8 + scope `_validate_invariants()`** : Double (game + systems). Scope étendu dans description AC-CMB-17.
- **ACs audio manquants** : audio-director seul mais aligné avec pattern "addendum non propagé".

### Plan d'action réalisé

Toutes les étapes S (~2h team effort) exécutées en session courante :
- Propagation vérifiée CONV-1 4 emplacements ✓
- AC-CMB-17 scope étendu ✓
- AC-CMB-42 reclass ADVISORY appliqué ✓
- AC-CMB-51 ajouté ✓
- AC-CMB-52 ajouté ✓
- AC-CMB-audio-01/02 ajoutés ✓
- Gap 8 ShapeCast3D.margin ajouté ✓
- AC-CMB-41 clause (8) grep ajoutée ✓
- AC-CMB-19 branche C + teardown ajoutés ✓
- AC-CMB-35b split worst case / soak ✓
- Mix hierarchy ducking params précisés ✓
- Footer Addendum purgé + note historique ✓
- Header ligne 3 mis à jour ✓

### Gaps ouverts maintenus (tracés vers Sprint 1 — inchangés depuis r5.1)

- Gap 1 MockEnemy — owner qa-tester pré-Sprint 1 (bloque AC-05/06/07/25)
- Gap 2 test empirique ShapeCast overlap origine Godot 4.6 + Jolt — owner lead-programmer (bloque AC-47)
- Gap 5 protocole playtest — owner qa-lead (bloque AC-31/32/33/34)
- Gap 7 pattern `_build_capsule_basis()` docs/engine-reference — owner lead-programmer (AC-08 prereq)
- **Gap 8 nouveau** ShapeCast3D.margin Jolt — owner lead-programmer (groupement avec Gap 2)
- Pending ADR Combat Tick Model — owner lead-programmer pré-Sprint 1

### Sprint 1 readiness

**APPROVED** — aucun BLOCKING résiduel au GDD. Sprint 1 Combat implementation peut démarrer, sous réserve des Gaps 1/2/5/7/8 + Pending ADR résolus en parallèle par leurs owners respectifs. Stories P0 non-impactées (scene skeleton, ShapeCast3D setup, mock infrastructure Combat) peuvent démarrer immédiatement.

**Decision Martin (2026-04-23)** : Option A "Revise now" — toutes 9 BLOCKING résolues inline + tous RECOMMENDED r6 critiques bundle. Auto-mode CLAUDE.md respecté (recommandation creative-director exécutée sans user prompt, actions réversibles, zéro commit). Next : spot-check optionnel audio-director + qa-lead si doute subsiste, sinon propagation ADR Combat Tick Model (lead-programmer) pour déverrouiller Sprint 1.

---
