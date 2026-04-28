# Upgrade System — Review Log

> Continuous log of all design reviews on `design/gdd/upgrade-system.md`.
> Each review entry summarizes verdict, scope, blocking items resolved/added.
> Detailed reports : `upgrade-system-review-r[N]-[date].md`.

---

## Review — 2026-04-27 — Verdict: NEEDS REVISION

**Scope signal** : M (~3-4h editorial r2 design session focalisée)
**Specialists** : game-designer, systems-designer, qa-lead, godot-specialist (4 adversariaux parallèles) + creative-director (synthèse senior)
**Blocking items** : 15 | **Recommended** : 18 | **Nice-to-have** : 7
**Detailed report** : `upgrade-system-review-r1-2026-04-27.md`

**Summary** :

GDD r1 (719 lignes, 14 R-UPG + 4 F-UPG + 35 EC + 43 ACs + 10 OQ) — **8/8 sections présentes** (+3 bonus Visual/Audio/UI/OQ). Architecture data-pure quasi-stateless saine, pull pattern cohérent avec Movement r3 verrouillé, pillar alignment intact (Pillar 2 PROGRESSION SE VOIT primaire, Pillar 1 FLOW par soustraction). Convergences fortes 3+ specialists sur 3 axes critiques.

**3 convergences cross-specialist (priorité haute)** :
1. **`set(flag_name)` reflection unsafe** [game-designer + godot-specialist] — bypasse static typing GDScript 4.6, `set("can_air_jump", "true")` coerce silencieusement. Adjudication CD : garder `set()` (Pillar 2 catalog data-driven) MAIS via helper `_apply_flag(flag_name)` avec validation runtime (existence + `typeof == TYPE_BOOL` + assert).
2. **EC-UPG-14 contradicts R-UPG-4 step 2** [game-designer + systems-designer] — idempotence guard inconsistent. Adjudication CD : EC-UPG-14 wins, guard devient `not _owned.has(id) OR not get(flag_name)` pour absorber hot-reload + désync + tests, avec `assert` post-set.
3. **AC-UPG-22 coercion silencieuse non-filtre** [systems-designer + qa-lead + godot-specialist] — GDScript coerce `int → StringName("42")` silencieusement, "filtre" inexistant ; rejet via R-UPG-9 path (catalog miss). Reformulé r1.1.

**15 BLOCKING détaillés** : `set()` reflection (3 axes) ; EC-UPG-14 vs R-UPG-4 ; F-UPG-1 bound check `n>=0` (cross-Credit) ; F-UPG-2 save bloat N=1M defense ; AC-UPG-22 coercion ; F-UPG-4 Tier 2+ flags non-déclarés ; AC-UPG-3 mécanisme test indéfini ; AC-UPG-5 GUT instrumentation impossible ; AC-UPG-10/11/19/20 `push_warning` non-capturable ; AC-UPG-15 const injection impossible ; AC-UPG-27/33 doublon ; R-UPG-5 `Array` typage manquant ; `const _CATALOG` mutability ; R-UPG-12 no-revoke reframe (Hollow Knight analogie fausse) ; R-UPG-3 ADR catalogue over-governance.

**8 cosmetic fixes appliqués r1.1** :
1. AC-UPG-30 PROVISIONAL → AUTO BLOCKING (Save/Load r1 R-SAV-4 unblocked)
2. AC-UPG-42 PROVISIONAL → AUTO BLOCKING (idem)
3. AC-UPG-43 PROVISIONAL → AUTO BLOCKING (idem)
4. AC-UPG-33 SUPPRIMÉ doublon avec AC-UPG-27
5. AC-UPG-22 reformulé pour refléter coercion silencieuse R-UPG-9 path
6. AC-UPG-26 downgrade BLOCKING → ADVISORY (torn-read structurellement impossible sur bool)
7. R-UPG-5 fix `var owned: Array → Array[StringName]` (typage strict)
8. OQ-UPG-2 reformulé "VERROUILLÉ sur Movement r3 pull pattern, caveat résiduel post Movement r4 si push introduit" (PARTIALLY RESOLVED)

**7 structural BLOCKING reportés r2 design session distincte** :
- B-3 helper `_apply_flag()` design + R-UPG-4 step 4 amendement
- B-4 EC-UPG-14 reconciliation R-UPG-4 + AC ajouté pour resync test
- B-1 R-UPG-12 reframe (anti-pilier "NOT skill tree" + Ghostrunner ref, retirer Hollow Knight)
- B-2 R-UPG-3 retirer requirement ADR catalogue (F-UPG-3 CI suffit)
- B-6 ajouter `EC-UPG-X : owned_array.size() > MAX_CATALOG_SIZE × 2 → tronquer + warning` (defense save bloat)
- B-8 F-UPG-4 cross-ref EC-UPG-9 + note explicite "vars must be declared before _CATALOG add"
- B-9-10-11-12-15 ACs rewrite session (qa-lead + godot-specialist)

**1 cross-system flag (hors scope Upgrade r2)** :
- B-5 F-UPG-1 bound check `n >= 0` documentation côté Credit r3 amendement ou /consistency-check (Credit Economy + Shop chain ownership). Ne bloque pas Upgrade r2.

**Adjudications creative-director (5 décisions clés)** :
1. `set()` reste avec helper `_apply_flag()` — Pillar 2 data-driven catalog préservé, validation runtime ajoutée.
2. EC-UPG-14 wins sur R-UPG-4 — re-sync nécessaire pour hot-reload + tests désync, avec assert pas silent.
3. No-revoke MVP OK — anti-pilier "NOT skill tree" évite UI complexité respec, retirer analogie Hollow Knight (charm system = REVOCABLE), garder Ghostrunner référence.
4. Reorder autoload Upgrade pos 2 — cosmétique zéro coût structurel, optionnel ADR-0007 amendement r3 (non-bloquant Sprint 1).
5. Pillar 2 feedback design — Shop card OWNED label ownership confirmé MVP, runtime VFX d'unlock = Tier 2+ (déjà aligné GDD actuel).

**OQ-UPG-2 status post-review** : PARTIALLY RESOLVED — Movement r3 pull pattern verrouillé (lignes 38/44/46/52/69/315), contrat Upgrade ↔ Movement OK au 2026-04-27. Caveat résiduel post Movement r4 fresh re-review si push pattern introduit.

**Path to APPROVED** : r2 design session focalisée (~3-4h) addressing 7 structural BLOCKING + 18 RECOMMENDED batchables (3 ACs PROVISIONAL déjà promus en r1.1 ; reste 15 RECOMMENDED divers). Re-review fresh post r2 attendue avant `/create-epics upgrade-system`.

**Prior verdict resolved** : First review.

---

## Review — 2026-04-27 — Verdict: NEEDS REVISION (r1 SUPPLEMENTAL — parallel session)

**Scope signal** : M (10 amendements éditoriaux appliqués r1.2 ; 7 structural BLOCKING r1 inchangés en attente r2 design session distincte)
**Specialists** : game-designer, systems-designer, qa-lead, godot-specialist + **economy-designer (5e adversarial)** + creative-director (synthèse senior r1-supplemental)
**Blocking items** : 12 (dont 7 reportés r2) | **Recommended** : 17 | **Nice-to-have** : 8
**Detailed report** : `upgrade-system-review-r1-supplemental-2026-04-27.md`

**Summary** :

Review **parallèle** au moment où la session antérieure finissait sa propre review r1 (r1.1 cosmetic appliqué). 5 specialists adversariaux dont **economy-designer** absent de la r1 antérieure. 12 BLOCKING identifiés vs 15 r1, avec convergence partielle sur 3 axes (set() reflection ; EC-UPG-14 vs R-UPG-4 ; F-UPG-3 sanity). **Stratégie adoptée** : honorer r1.1 cosmetic + appliquer SEULEMENT findings UNIQUES non-conflictuels (10 amendements r1.2). Conflits explicites (EC-UPG-14, set() helper) restent reportés r2 design session distincte selon plan r1.1.

**10 cosmetic amendements appliqués r1.2 (non-conflictuels avec r1.1)** :
1. EC-UPG-32 — `Engine.set_singleton` → `Engine.register_singleton/unregister_singleton` (Godot 4.6 API correct)
2. F-UPG-3 — Invariant bidirectionnel (Shop ⊆ Upgrade ET Upgrade ⊆ Shop avec TIER_2_STUBS_EXEMPT)
3. F-UPG-4 — Retrait `can_secret_radar` du catalog Tier 2+ (Pillar 4 violation — radar = aide cognitive)
4. EC-UPG-2 — Reformulation : ordre R-UPG-11 préservé (GSM pos 2, Upgrade pos 5), garantie via ADR-0007 D-9 (GSM init MENU sans transition synchrone)
5. AC-UPG-3 — Scindé en contrainte stricte (BLOCKING `index(SaveLoad) < index(Upgrade)`) + AC-UPG-3-bis ordre canonique (ADVISORY)
6. AC-UPG-12 — Refactor : grep statique `await|yield` (BLOCKING) + AC-UPG-12-bis wall-clock (ADVISORY) ; remplace frame-counting inopérant en headless
7. AC-UPG-34/35/36 — Word-boundary `\b...\b` + filtre commentaires `^\s*#`
8. AC-UPG-37 — Reformulation scope concret (`src/gameplay/upgrade/` root + name substring) + AC-UPG-37-bis NEW playtest novice 80% en 30s
9. R-UPG-12 corollaire — No-confirm achat = intentionnel anti-friction Pillar 1 documenté
10. 3 NEW OQ-UPG-11/12/13 (affordability marge 25 cr cross-GDD ; secret_radar Pillar 4 reintegration ; Tier 2+ yield budget hypothesis)

**7 structural BLOCKING r1 inchangés (en attente r2 design session)** :
- B-1 R-UPG-12 reframe (Hollow Knight retrait, Ghostrunner garder)
- B-2 R-UPG-3 retirer ADR catalogue requirement
- B-3 helper `_apply_flag()` design + R-UPG-4 step 4
- B-4 EC-UPG-14 reconciliation R-UPG-4 + AC resync test
- B-6 save bloat defense `MAX_CATALOG_SIZE × 2`
- B-8 F-UPG-4 cross-ref EC-UPG-9 + vars-before-_CATALOG note
- B-9-15 ACs rewrite session (qa-lead + godot-specialist)

**Adjudications creative-director r1-supplemental (8 décisions)** :
1. EC-UPG-14 wins (ALIGNÉ r1.1 — pas d'override)
2. Pas de reorder autoload (EC-UPG-2 reformulé via ADR-0007 D-9)
3. Pas de feedback in-world premier usage post-achat (Pillar 1 prime ; AC-UPG-37-bis playtest novice ajouté)
4. `can_secret_radar` retiré (Pillar 4 violation explicite)
5. No-confirm achat documenté Pillar 1 (corollaire R-UPG-12)
6. Affordability flagged OQ-UPG-11 (pas de modification unilatérale coûts)
7. Helper `_apply_flag()` reporté r2 (ALIGNÉ r1.1)
8. R-UPG-12 reframe Hollow Knight reporté r2 (ALIGNÉ r1.1)

**Path to APPROVED** : r2 design session distincte (3-4h ALIGNÉ plan r1.1) addressing 7 structural BLOCKING + valide 3 nouvelles OQ-UPG-11/12/13. Re-review fresh r3 attendue avant `/create-epics upgrade-system` Sprint 1.

**Prior verdict resolved** : Re-review du même jour (r1 antérieure parallel session). Verdict NEEDS REVISION cohérent ; r1.1 cosmetic préservés ; 10 r1.2 amendements supplemental appliqués sans conflit.

---

## r2 design session — 2026-04-27 — `/design-system upgrade-system` r2 focalisée solo auto-approve

**Type** : design session (pas review). Adresse les 7 structural BLOCKING reportés review r1 + r1.2 supplemental + 13 RECOMMENDED batchables.
**Mode** : solo auto-approve (cf. `production/review-mode.txt`).
**Scope effort** : ~3-4h editorial focalisée comme estimé review r1 §9.
**File touched** : `design/gdd/upgrade-system.md` (r1.2 → r2, status header bump + ~15 sections édit ciblées + 4 ACs NEW + 1 catégorie NEW + 1 EC NEW).

### 7 structural BLOCKING addressed

| # | Item | Mécanique r2 | AC associé |
|---|------|---------------|------------|
| **B-1** | R-UPG-12 reframe + retirer Hollow Knight | Section B.3 anti-fantasy + R-UPG-12 corps réécrit ; retrait analogie Hollow Knight charm REVOCABLE (mécaniquement opposé au modèle binaire permanent) ; conservation Ghostrunner + ajout SuperHot ; reframe : la cause directe est le scope MVP (UI respec + politique refund + mental model build dynamique), l'anti-pilier "skill tree" devient conséquence cascade pas axiome | — (édito uniquement) |
| **B-2** | R-UPG-3 retirer ADR catalogue requirement | R-UPG-3 corps réécrit ; F-UPG-3 catalog sanity test CI suffit ; trigger ADR escalation documentés (N>12 OU breaking save format EC-UPG-19) | — (édito uniquement) |
| **B-3** | helper `_apply_flag()` | Section C.1 Variables membres : ajout `_apply_flag(flag_name: StringName)` complet avec props lookup + `typeof == TYPE_BOOL` + assert post-set + trade-offs documentés (~3 µs/call, asserts strippés release Tier 1, optim Tier 2+ cache) ; R-UPG-4 step 4 réécrit pour invoquer le helper | AC-UPG-15 (B-12 rewrite) valide via test catalog réel |
| **B-4** | R-UPG-4 step 2 reconciliation EC-UPG-14 | Step 2 réécrit : guard `_owned.has(id) AND get(flag_name) == true` (early return seulement si **les deux** sont vrais) ; cas A/B/C/D documentés ; resync forcé sur désync | **AC-UPG-9-bis NEW BLOCKING** test injection désync `_owned[id]=true ∧ flag=false` puis apply_upgrade(id) → flag re-passe à true |
| **B-6** | EC-UPG-36 NEW save bloat defense | Catégorie K nouvelle ; R-UPG-5 step 2 truncate `owned.size() > MAX_CATALOG_SIZE_TIER_2 * 2 (=14)` push_warning + slice ; constante `MAX_CATALOG_SIZE_TIER_2 = 7` ajoutée Variables membres | **AC-UPG-44 NEW BLOCKING** (1000 entrées → trunc) + **AC-UPG-45 NEW ADVISORY** boundary value 14/15 |
| **B-8** | F-UPG-4 cross-ref EC-UPG-9 + note vars Tier 2+ | F-UPG-4 Conditions de promotion étendues : "Chaque nouveau `flag_name` ajouté à `_CATALOG` DOIT être déclaré comme `var public: bool = false` AVANT l'ajout entry catalog" + ordre obligatoire 2-commit (var puis catalog, F-UPG-3 doit passer après chacun) | — (édito + cross-ref existing AC-UPG-9 EC-UPG-9) |
| **B-9 à B-15** | ACs rewrite | AC-UPG-5 (B-10) GUT bare instance + Logger DI ; AC-UPG-6 (B-15) const Dictionary mutation in-place caractéristique runtime + AC-UPG-6-bis NEW grep statique ; AC-UPG-9-bis (B-4) NEW resync ; AC-UPG-10/11/19/20 (B-11) Logger DI injection technique pour push_warning capture (refactor mineur Sprint 1 obligatoire) ; AC-UPG-15 (B-12) F-UPG-3 spec rewrite valider catalog réel pas test injection r1 impossible | 5 ACs réécrits + 4 ACs NEW (AC-UPG-6-bis, 9-bis, 44, 45) |

### 13 RECOMMENDED batchés (sur 15 RECOMMENDED reportés ; R-4/R-5/R-9/R-11/R-12/R-13 déjà appliqués r1.1 ou r1.2 supplemental)

| # | Item | Mécanique r2 |
|---|------|---------------|
| R-1 | `_boot_complete` rename `_is_hydrated` | Variables membres + R-UPG-5 + States table + Tuning Knob + EC-UPG-2 + EC-UPG-33 + AC-UPG-5 + AC-UPG-23 + GSM Interactions tous renommés ; mention historique `_boot_complete` conservée pour audit trail review log |
| R-2 | R-UPG-7 player-perspective scenario doc | R-UPG-7 corps étendu : scénario concret « shop entre étages 40 cr → debit → save → apply_upgrade → click Continuer → GSM transition → Player spawn → premier `_physics_process` lit `Upgrade.can_dash == true` » + raison architecturale autoload |
| R-3 | "Zéro signal outbound" framing MVP-only | R-UPG-6 corps étendu : "zéro signal **au MVP**", pas philosophie absolue ; Tier 2+ peut introduire signal additif (cf. OQ-UPG-3 + OQ-UPG-5) si pull continue de fonctionner |
| R-6 | F-UPG-3 const-vs-var detection | AC-UPG-15 (B-12) point (c) : test set+set+assert pour distinguer const vs var |
| R-7 | EC-UPG-23 reformulation callback paths | Caveat r2 : "torn-read impossible" tient au MVP (zéro callback paths) ; Tier 2+ OQ-UPG-5 push pattern peut nécessiter ré-évaluation |
| R-8 | F-UPG-2 set() coût absolu doc | F-UPG-2 Invariants point 2 étendu : ~3 µs/call helper, worst case 14 calls = 42 µs sous budget Pillar 1 ; mesure exacte Sprint 1 via AC-UPG-40/41 |
| R-10 | AC-UPG-24 mock vs real Movement | option (a) BLOCKING fixture mock_movement_reader.gd, option (b) ADVISORY MVP scène réelle player.tscn — BLOCKING post Movement r4 fresh re-review |
| R-14 | AC-UPG-40/41 headless context spec | Contexte runner GUT headless ubuntu-latest CI référence + médiane robust GC pauses (pas moyenne) |
| R-15 | await autoload chain règle formalisée | F-UPG-2 Invariant 5 NEW : `_ready()` strictement SYNC ; AC-UPG-12 grep statique scope étendu Sprint 1 si besoin |
| R-16 | AC-UPG-27 get_signal_list filter spec | Whitelist explicite Object/Node Godot 4.6 OU `flags & METHOD_FLAG_FROM_BASE` ; whitelist re-validable migration Godot mineure |
| R-17 | EC-UPG-5 hot-reload SaveLoad re-instantiation race | Caveat r2 : Godot 4.6 ne garantit pas ordre reload partiel ; admis Tier 1 editor-only |
| R-18 | PROCESS_MODE_ALWAYS set programmatique | EC-UPG-35 décision r2 : set dans `_ready()` (`process_mode = Node.PROCESS_MODE_ALWAYS`), pas via `.tscn` autoload — single source of truth |

### Cross-system flag B-5 (hors-scope Upgrade r2)

F-UPG-1 Credit `n >= 0` bound check documentation côté Credit r3 amendement OR `/consistency-check` Credit-Shop chain ownership — **non-bloquant Upgrade r2**. Tracé pour résolution parallèle.

### Total amendements appliqués r2

- **Header** : status r1.2 → r2, scope addressed récapitulé.
- **Section B.3 anti-fantasy** : retrait Hollow Knight + ajout SuperHot.
- **Section C.1 Variables membres** : helper `_apply_flag()` complet (~50 lignes), constante `MAX_CATALOG_SIZE_TIER_2`, rename `_boot_complete → _is_hydrated`.
- **Section C.3 Core Rules** : R-UPG-3 (B-2), R-UPG-4 (B-3 + B-4), R-UPG-5 (R-1 + B-6), R-UPG-6 (R-3), R-UPG-7 (R-2), R-UPG-12 (B-1).
- **Section C.4 States table** : rename `_is_hydrated`.
- **Section C.5 Interactions GSM** : rename `_is_hydrated`.
- **Section F-UPG-2** : Invariants 2 + 5 (R-8 + R-15).
- **Section F-UPG-4** : Conditions de promotion étendues (B-8).
- **Section Edge Cases** : EC-UPG-2 (rename), EC-UPG-5 (R-17), EC-UPG-13/14 (B-4), EC-UPG-23 (R-7), EC-UPG-33 (R-1 rename), EC-UPG-35 (R-18), EC-UPG-36 NEW (B-6).
- **Section Tuning Knobs** : `_is_hydrated` rename.
- **Section Acceptance Criteria** : AC-UPG-5 (B-10), AC-UPG-6 (B-15) + AC-UPG-6-bis NEW, AC-UPG-9-bis NEW (B-4), AC-UPG-10 (B-11), AC-UPG-11 (B-11), AC-UPG-15 (B-12), AC-UPG-19 (B-11), AC-UPG-20 (B-11), AC-UPG-23 (R-1), AC-UPG-24 (R-10), AC-UPG-27 (R-16), AC-UPG-40 (R-14), AC-UPG-41 (R-14), AC-UPG-44 NEW (B-6), AC-UPG-45 NEW (B-6).

### Path to APPROVED

**Next step** : fresh `/design-review upgrade-system` lean session (5-10 min) — vérifier les 7 BLOCKING addressés + 13 RECOMMENDED batchés OK + cohérence cross-section (helper `_apply_flag` ↔ R-UPG-4 step 4 ↔ AC-UPG-15) + grep `_boot_complete` confirme transition propre vers `_is_hydrated`. Si APPROVED → unlock `/create-epics upgrade-system`. Si NEEDS REVISION → r3 cycle.

**Parallèle non-bloquant** : `/consistency-check` Credit-Shop-Upgrade chain pour B-5 F-UPG-1 `n >= 0` ownership ; amendement Shop r2 cosmétique OQ-SHP-2 RESOLVED ; amendement ADR-0007 D-1 r3 cosmétique pour ordre autoload final.
