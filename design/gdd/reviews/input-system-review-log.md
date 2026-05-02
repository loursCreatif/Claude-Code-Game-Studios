# Review Log — Input System GDD

Historique des reviews indépendantes du GDD `design/gdd/input-system.md`.

---

## r6 fresh-session review — 2026-04-21 — verdict 🟡 NEEDS REVISION (mineur)

**Mode** : fresh session post-`/clear` (contexte r5 authoring écarté) — validation indépendante obligatoire pour sortir du statut "r5 revised pending" (cf. session-state prochaine étape #3).

**Trigger** : application r5 des 7 fixes R-1..R-7 post-ADR-0004 Accepted a été exécutée in-context. La GDD doit être re-validée fresh pour vérifier que les 7 BLOCKINGs r4 sont effectivement résolus dans le GDD lui-même (pas juste dans l'ADR).

**Méthodologie** : 4 specialists indépendants en parallèle, chacun avec un angle précis et une obligation de citer ligne N du GDD pour chaque finding. Aucune réécriture — review pure. Synthèse creative-director-style ci-dessous.

### Verdicts specialists

| Specialist | Angle | Verdict | Findings structurants |
|---|---|---|---|
| **godot-gdscript-specialist** | API/patterns/typage, StringName, zero-alloc, signal architecture | 🟢 PASS | 0 BLOCKING — D-1..D-9 correctement appliqués. 4 NOTES non-bloquantes (N-1 commentaire inline `0.0 si 0 samples`, N-2 cohérence signature `Node`, N-3 mock `OS.has_feature` impl challenge, N-4 `_latency_scratch` absent tableau Variables). |
| **game-designer** | Pillar 1, ownership frontiers, feel ACs, Open Questions | 🟢 PASS | 0 BLOCKING — Pillar 1 respecté + ownership propres. 8 Design Questions non-bloquantes dont **4 actionables** (DQ-1 budget 60Hz VSync perceived-latency à surveiller playtest, DQ-5 Accessibility toggle-to-dash à résoudre AVANT Checkpoint GDD propagation Movement, DQ-7 hint "Press Escape" à convertir en story backlog, DQ-8 purge résidu "hypothèse 120 Hz" dans Movement GDD Overview). |
| **qa-lead** | AC testability/classification/coverage | 🟡 NEEDS REVISION | **3 BLOCKINGs ACs** + 5 coverage gaps + 3 classification errors. Voir détails ci-dessous. |
| **systems-designer** | Refcount, cross-system, bidirectional, forbidden patterns | 🟢 PASS | 0 BLOCKING — refcount structurellement safe, découplage D-5 vérifié sans résidu, forbidden patterns alignés registry. 2 NOTES (NOTE-1 désynchro `entities.yaml` `RESPAWN_DELAY=200ms` vs Movement GDD 50ms — **hors scope Input mais signalé**, NOTE-2 sémantique jump buffer POST-MVP "press perdue pendant respawn" à clarifier Edge Case l. 420). |

**Verdict global** : 🟡 **NEEDS REVISION (mineur)** — la structure + patterns + design du GDD r5 sont corrects. Seuls 3 BLOCKINGs d'ACs (formulations ambiguës/non testables tel qu'écrits) + 5 coverage gaps d'ACs manquants bloquent l'APPROVED. Aucune régression architecturale, aucun conflit cross-ADR. Effort estimé ~45-60 min d'éditions ACs + mise à jour registry `RESPAWN_DELAY`.

### BLOCKINGs ACs (qa-lead, 3 items)

- **BLK-1 — AC-MC-4 (l. 616)** : mixe test runtime (signaux + `Input.mouse_mode`) ET assertion architectural (grep lint sur `input_manager.gd` absence de réf `GameStateManager`). Non reproductible dans un runner GUT pur. **Fix** : splitter en AC-MC-4 Integration (comportement runtime only) + AC-MC-4b `(Code Review)` ou lint-rule séparée pour l'assertion d'absence de dépendance.
- **BLK-2 — AC-AG-5 (l. 602)** : scénario "build release via mock `OS.has_feature = false`" non testable — GDScript ne permet pas de mocker un singleton natif. **Fix** : soit (a) spécifier un wrapper `_is_debug_build() -> bool` injectable dans l'API test fixtures, soit (b) reformuler la branche release en `(Code Review)` (grep code pour la présence du guard `if not OS.has_feature("debug"): return` en tête de chaque `simulate_*`).
- **BLK-3 — AC-L-3 (l. 625)** : classé `(Integration BLOCKING)` mais c'est un test de performance sur ring buffer unique, pas une interaction multi-systèmes. **Fix** : reclasser `(Perf BLOCKING)` — même gate level, classification correcte. Cohérent avec AC-PF-1..5.

### Coverage gaps ACs (qa-lead, 5 items)

- **CG-1** : Règle 8 (StringName discipline) sans AC — manque `(Code Review)` "grep `was_pressed_this_tick(` dans `src/` → zéro argument de type `String` (non-literal, non-const)".
- **CG-2** : Règle 12 (`ui_cancel` via `_input` + `set_input_as_handled()`) sans AC Integration — vérifier que `ui_cancel` ne remonte pas aux Control nodes sous-jacents.
- **CG-3** : Règle 15 (contrat `mouse_motion` en MouseFree) sans AC — cas "signal émis + `is_mouse_captured() == false`" → consumer Camera qui ignore correctement.
- **CG-4** : AC-L-4 couvre fenêtre expirée mais **pas** cold-start (`_latency_sample_count == 0`) — `get_latency_p99_ms()` retourne quoi à t0 avant injection ? Spéc absente.
- **CG-5** : Règle 5 (`set_mouse_captured` no-op si même mode, anti-flutter macOS) sans AC Logic d'idempotence.

### Classification errors (qa-lead, 3 items)

- **CE-1** : AC-L-3 `(Integration)` → `(Perf)` — cf. BLK-3.
- **CE-2** : AC-DBG-2 `(Manual — smoke check pre-release)` — catégorie "Manual" absente du coding-standards table (`Visual/Feel`, `UI`, `Config/Data` sont les labels canoniques). Réaligner : `(UI Manual walkthrough)` ou `(Config/Data smoke)`.
- **CE-3** : AC-DS-4 (l. 609) duplicate AC-CS-4 (l. 639) — même scénario "press pendant disabled → release → was_pressed_this_tick false" répété dans 2 sections. **Fix** : fusionner en un seul AC (probablement `(Logic)` car scope single-node) OU différencier explicitement (AC-DS-4 = single-owner, AC-CS-4 = multi-owner refcount release).

### Notes additionnelles (à ajuster dans le même pass)

- **R-3 mention fantôme (l. 591)** : classification block intro mentionne "hook public `_on_application_focus_changed(bool)` pour simuler focus headless" — ce hook **n'existe nulle part** dans l'API publique (règle 7) ni dans l'ADR-0004. AC-MC-4 utilise directement `InputManager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` — c'est la bonne approche. **Supprimer la mention du hook** de la note classification.
- **NOTE-2 (systems-designer)** : ajouter ligne Edge Case 420 clarifiant que `jump_pressed` signal est AUSSI suppressed pendant disabled → futur jump buffer POST-MVP qui voudrait survivre au respawn devra polling `Input.is_action_pressed(&"jump")` directement côté Movement (pas via canaux InputManager).
- **NOTE-1 (systems-designer, hors scope Input mais signalé)** : `design/registry/entities.yaml` enregistre `RESPAWN_DELAY = 0.2 s` mais Movement GDD rule 9 = 50 ms (décision Martin r3). **Fix registry** : `value: 0.05`, `safe_range: [0.016, 0.1]`, mettre à jour la note "les 3 GDDs s'accordent sur 200 ms" (incorrect).
- **DQ-5 action urgente** : résoudre l'Open Question Accessibility "toggle-to-dash vs edge-press" AVANT d'écrire le GDD Checkpoint & Respawn — la décision impacte Movement (`is_action_pressed` maintenu vs `was_pressed_this_tick` edge) et Input Tuning Knobs (ajouter `dash_hold_mode: edge | toggle` ?).

### Ce qui est 🟢 solide (à ne pas retoucher)

- D-1..D-9 ADR-0004 tous correctement reflétés dans le GDD (règles 6, 7, 10, 11, 12, 13, 16 + Formulas Latency + Edge Cases + Open Questions).
- Découplage Input → GameStateManager one-way : aucun appel direct résiduel (vérifié ligne 274 + 416).
- Refcount gating structurellement safe (séquence 3-owner couverte, auto-cleanup `tree_exited`, `push_warning` sur release orphan).
- Forbidden patterns 5/5 alignés registry `architecture.yaml`.
- Tick N parity garanti par swap début-de-corps (AC-CS-1 passable).
- Ownership frontiers propres : `mouse_sensitivity` (Input), `WALL_RUN_TILT_ANGLE` (Camera), `restart_hold_duration` (Checkpoint).

### Compteur findings r6

- **BLOCKINGs** : 3 (tous ACs formulations, zéro structurel)
- **Coverage gaps ACs** : 5 (CG-1..5)
- **Classification errors** : 3 (CE-1..3)
- **Notes fantôme/correctifs mineurs** : 2 (R-3 mention hook, NOTE-2 Edge Case 420)
- **Actions hors scope signalées** : 2 (registry `RESPAWN_DELAY`, Open Question Accessibility à résoudre pre-Checkpoint)
- **Design Questions non-bloquantes à surveiller** : 4 (DQ-1, DQ-5, DQ-7, DQ-8)

### Statut GDD post-r6

`Designed — NEEDS REVISION r6 (mineur ACs)`. Une fois les 3 BLOCKINGs + 5 coverage gaps + 3 classification errors traités (~45-60 min), re-run `/design-review` fresh-session r7 OBLIGATOIRE avant APPROVED (même règle que r5→r6 : la correction elle-même biaise le contexte).

### Prochaines étapes (par priorité)

1. **Appliquer les 11 fixes ACs r6** (3 BLK + 5 CG + 3 CE) + R-3 + NOTE-2 Edge Case l. 420 en session dédiée (non-fresh OK, c'est de l'application directe comme r5 application).
2. **Corriger registry `entities.yaml`** : `RESPAWN_DELAY.value` 0.2 → 0.05, mettre à jour la note (hors scope Input mais signalé par NOTE-1).
3. **Résoudre Open Question Accessibility toggle-to-dash** (`/ux-design settings-input`) AVANT `/design-system checkpoint-respawn-system`.
4. **`/clear` + `/design-review design/gdd/input-system.md`** fresh session r7 pour sortir définitivement du NEEDS REVISION.
5. **Re-review `/design-review design/gdd/player-movement-system.md`** fresh session r4 pending + purger résidu "120 Hz hypothèse" Overview (DQ-8).
6. **`/design-review design/gdd/camera-system.md`** fresh session pending.
7. **`/gate-check pre-production`** éligible après r7 Input APPROVED.

---

## Application fixes — 2026-04-21 — r5 post-ADR-0004 Accepted

**Mode** : application directe post-ADR (non-review). ADR-0004 (Input API & Focus Handling) transitionné Accepted via `/architecture-review single-gdd input` fresh-session (verdict PASS, 1 CONCERN cross-ADR C-1 résolu en séance par edits ADR-0001 l. 100 + l. 222).

**Inputs** :
- ADR-0004 Accepted : 9 décisions canoniques (D-1 was_pressed_this_tick · D-2 API cleanup · D-3 swap _pressed↔_consumed · D-4 refcount request_disable/release_enable_request · D-5 application_focus_lost signal · D-6 fenêtre 50 ms absolute time · D-7 Input main-thread only · D-8 ring buffer PackedFloat32/Int64Array · D-9 OS.has_feature("debug") + parse_input_event)
- Migration Plan ADR-0004 l. 510 : Published API + Core Rules (6, 10, 11, 13, 14) + Edge Cases + Formulas + AC-AG-1/2/3 + AC-CS-1 + AC-PF-2 + ajout AC-PF-4.
- 7 flags R-1..R-7 tracés en session state post-ADR-0004 Accepted.

**Edits appliqués** (15 passes sur `design/gdd/input-system.md`) :

1. **Header** : Status `r5`, Last Updated description 7 fixes R-1..R-7, champ `Governing ADRs`.
2. **Règle 6 (enabled/disabled)** : remplace `set_enabled(bool)` par refcount `request_disable(owner)/release_enable_request(owner)` + auto-cleanup `tree_exited` + liste effet transition true→false (flags vidés).
3. **Règle 7 (Published API)** : bloc code réécrit — `was_pressed_this_tick` canonique, suppression `is_action_just_pressed`/`set_enabled`, ajout signals `application_focus_lost/gained`, test fixtures guardées `OS.has_feature("debug")`, 3 forbidden_patterns listés.
4. **Règle 10 (Settings persistence)** : ajout `focus_regain_window_ms` dans `input_settings.tres`, renforcement ordre autoload « InputManager #1 » + lien vers règle 16.
5. **Règle 11 (Signal vs polling)** : bascule à `was_pressed_this_tick` + signals étendus (focus events), sémantique edge-triggered tick N parity.
6. **Règle 13 (Focus handling)** : réécrite — fenêtre 50 ms absolute time `_focus_regained_until_ticks_usec`, pseudocode complet signals one-way (D-5), rationale cross-OS Wayland burst, fenêtre tunable [20, 150] ms.
7. **Règle 16 (NOUVELLE)** : « Flag consumption pattern — swap `_pressed ↔ _consumed` » — pseudocode complet + justification SYNCHRONE début-de-corps (pas `call_deferred` ni fin-de-corps) + mitigation Risk 2 ADR.
8. **Formulas / Latency measurement** : réécrite zero-alloc — 2× `PackedFloat32Array`+`PackedInt64Array` pré-alloués cap 120, `_record_latency_sample`, `get_latency_p99_ms` avec scratch buffer, taille fixe 1.92 KB, forbidden_pattern documenté.
9. **Edge Cases focus** : 2 bullets réécrits (FOCUS_OUT signal one-way vs GameStateManager consumer, FOCUS_IN fenêtre 50 ms).
10. **Edge Case « pressage transition disabled→enabled »** : flags vidés à la transition disabled, `was_pressed_this_tick` retourne `false` au 1er tick enabled.
11. **Edge Case « touche stuck »** : `was_pressed_this_tick` edge-triggered explicite.
12. **Edge Case « action inconnue »** : `was_pressed_this_tick` retourne `false` silencieux + `push_error` en debug.
13. **Interactions with Other Systems** : 5 lignes mises à jour (Movement/Combat/Checkpoint/Menu/GameStateManager signals one-way).
14. **Dependencies** : 6 lignes mises à jour refcount + signal focus.
15. **Cross-References** : 6 lignes mises à jour (API names) + nouvelle entrée GameStateManager.
16. **AC-AG-1..5** : `Input.parse_input_event(InputEventAction)` au lieu de `Input.action_press`, `was_pressed_this_tick` partout, nouvelle AC-AG-5 pour `simulate_action_press` debug/release gate.
17. **AC-DS-1..4** : refcount sémantique, `was_pressed_this_tick`, flags vidés transition.
18. **AC-MC-4/5/7** : focus loss via signal one-way (assert lint grep sur `input_manager.gd`), focus regain fenêtre 50 ms, Wayland burst simulé.
19. **AC-CS-1..5** : tick N parity via swap, refcount 3-owner, auto-cleanup tree_exited, no-ghost post-release, playtest advisory inchangé.
20. **AC-PF-1..5** : AC-PF-2 étendu (6 patterns forbidden), **AC-PF-4 nouveau** (zero-alloc stress 10k events/60s, MEMORY_STATIC delta < 64 KB), **AC-PF-5 nouveau** (hot path p99 ≤ 0.1 ms release, profilé séparément de AC-L-3).
21. **AC-L-1 / AC-L-4** : nouveaux noms de buffer (`_latency_values_ms`, `_latency_sample_count`, `get_latency_p99_ms`).
22. **Open Questions** : 5 nouvelles entrées résolues par ADR-0004 (API polling, refcount, focus Wayland, ring buffer, test fixtures).

**Couverture R-1..R-7** : ✅ R-1 (règle 7 API) · ✅ R-2 (règle 16 swap) · ✅ R-3 (règle 13 fenêtre 50 ms) · ✅ R-4 (Formulas ring buffer) · ✅ R-5 (Edge Case + règle 13 + Interactions signal focus) · ✅ R-6 (règle 7 + AC-AG-1..5 `parse_input_event`) · ✅ R-7 (AC-CS-1 tick N parity maintenu + AC-PF-4 ajouté).

**Effort réel** : ~1h45 (vs estimation ADR-0004 Migration Plan 1h30 — 15 min supplémentaires pour Open Questions + AC-L update).

**Verdict r5** : **r6 re-review fresh-session recommandée** avant `Status: Approved`. Cette application a été faite par le même contexte qu'ADR-0004 Accepted → biais. Fresh session `/design-review design/gdd/input-system.md` obligatoire (LEAN mode suffisant — scope est application ADR, pas design drift).

**Status GDD post-application** : **Designed — r5 revised, pending r6 fresh re-review**.

---

## Review — 2026-04-21 — r4 re-review fresh session — Verdict: MAJOR REVISION NEEDED (ADR-first path)

**Scope signal** : M-L (doc revision architecture-driven ~3-5h LEAN si ADR-0002 créé d'abord, sinon 6-8h et risque r5)
**Mode** : full (7 specialists + creative-director senior synthesis ; specialists NON briefés sur findings r3 pour préserver l'indépendance du fresh session)
**Specialists** : game-designer, systems-designer, qa-lead, gameplay-programmer, godot-specialist, performance-analyst, creative-director
**Blocking items** : 7 (4 structurels convergents + 3 testing bloquants) | **Recommended revisions** : 13 | **Nice-to-have** : 5
**Prior verdict resolved** : r3 LEAN "NEEDS REVISION" n'a PAS été appliquée — GDD file encore au format r2. Les 5 BLOCKINGs r3 + nouveaux défauts rendent le scope plus large que LEAN.
**Contexte nouveau depuis r3** : création de `docs/architecture/adr-0001-physics-rate-60hz.md` (Proposed) qui introduit le pattern `was_pressed_this_tick` et forbidden_pattern `is_action_just_pressed_direct_in_gameplay_physics_process` dans `docs/registry/architecture.yaml`. Ces décisions **contredisent directement** l'API publique du GDD.

### Résumé (synthèse creative-director)

> "Le GDD spirale modérément : r1→r2 approuvé, r3 a identifié 5 BLOCKINGs non appliqués, r4 en trouve 4 structurels + 17 ACs cassés. Ce n'est pas une dérive créative — c'est de la dette technique sur un système carrefour. Les 4 BLOCKINGs convergents (API split, refcount set_enabled, budget hierarchy, dict alloc) ne sont pas des bugs GDD — ce sont des **décisions d'architecture non prises** qui polluent la GDD. Tant qu'elles ne sont pas actées dans un ADR, chaque révision les re-discute. **Pause sur les fixes GDD. Ouvrir d'abord ADR-0001 (critère escalade) + créer ADR-0002 Input API & Focus Handling.** Sans cela, r5 trouvera 3-4 nouveaux BLOCKINGs. On traite les symptômes depuis trois tours — c'est le moment de traiter la cause."

### Top 7 BLOCKINGs identifiés

1. **Incompatibilité API `is_action_just_pressed` vs ADR-0001** (4 voices : systems-designer F1 + gameplay-programmer BLOCKING-1 + qa-lead + godot-specialist implicit) — ADR-0001 liste exactement cette API comme `forbidden_patterns`. GDD expose la dans API publique (règle 7) + ACs AG-2/AG-3/CS-1. `was_pressed_this_tick` absente du GDD. Fix architectural via ADR-0002.

2. **`set_enabled(bool)` sans reference counting — race multi-owner garantie** (systems-designer F2) — Menu + Checkpoint + Cutscene future courent librement. Séquence concrète produit "input live pendant menu ouvert". Fix : `request_disable(owner)/request_enable(owner)` pattern.

3. **Budget hierarchy confus — CI green-light régression 500×** (systems-designer F3 + performance-analyst F1) — AC-L-3 gate à 16 ms pendant que nominal est 0.01 ms. Fix : AC-PF-4 dédié coût hot path p99 ≤ 0.1 ms release.

4. **Allocation Dictionary littérale dans hot path invisible à AC-PF-2** (gameplay-programmer BLOCKING-4 + performance-analyst F-2) — 60-1000 allocs/s non détectées par grep. Fix : 2× `PackedFloat32Array` pré-alloués + `write_idx % capacity`.

5. **AC-AG-1 teste mauvais chemin** (godot-specialist authoritative + qa-lead) — `Input.action_press()` existe mais ne trigger pas `_unhandled_input` par design Godot. AC valide uniquement couche polling. Fix : `parse_input_event(InputEventKey.new(...))`.

6. **`#if debug_build` préprocesseur n'existe pas en GDScript** (gameplay-programmer BLOCKING-2) — toute la suite de fixtures tests repose sur mécanisme inexistant. Fix : checks `OS.has_feature("debug")` runtime + no-op release.

7. **Reset flag timing non spécifié (sync vs deferred)** (gameplay-programmer BLOCKING-3 + godot-specialist adjudicated) — ordre autoload garantit `_physics_process` order (godot-specialist autoritaire), MAIS GDD ne précise pas reset synchrone vs `call_deferred`. Fix : ligne explicite "reset synchrone en fin de corps".

### Revisions recommandées (13 items)

R1 Critère escalade 60→120 Hz absent (game-designer F1) — à intégrer dans réouverture ADR-0001.
R2 `restart` tap sans hold ni grâce (game-designer F2).
R3 Controls via pause menu contredit "3 salles sans texte" (game-designer F3).
R4 `attack` edge-only : dette charge/combo (game-designer F4).
R5 `action_press_coalesce_window = 0` risque contact bounce laptop (game-designer F5).
R6 Couplage bidirectionnel Input ↔ GameStateManager via appel direct (systems-designer F6) → signal `application_focus_lost`.
R7 SaveLoadManager déclaré Amont+Aval simultanément, contradiction interne (systems-designer F7).
R8 Ring buffer <10 samples = max silencieux (systems-designer F5) → nil + flag.
R9 `_skip_next_mouse_delta` single bool insuffisant Wayland multi-frame (gameplay-programmer REVISION-2).
R10 `ui_cancel` + Controls focusés collision non-documentée (gameplay-programmer REVISION-3).
R11 `Input.mouse_mode` thread safety non documentée (godot-specialist).
R12 `ResourceLoader.load()` cas "wrong Resource type" absent Edge Cases (godot-specialist).
R13 17 ACs cassés / non-testables / violent coding-standards (qa-lead comprehensive) — voir rapport qa-lead détaillé.

### Nice-to-have (5 items)

N1 `is_echo()` justification textuelle erronée (correction trivial).
N2 AC-PF-3 NVIDIA LDAT → `RenderingServer.frame_pre_draw` proxy.
N3 Debounce 500 ms persistance sensitivity slider runtime.
N4 Budget stub `input: 0.2 ms` manquant `architecture.yaml`.
N5 Fragilité signals typés pour actions post-MVP.

### Specialist disagreements surfaced + adjudicated

- **`_physics_process` ordering** : gameplay-programmer dit non-garanti, godot-specialist dit garanti par autoload order. **Tranché godot-specialist** (autoritaire Godot 4.6) — mais GDD doit spécifier reset synchrone (B7).
- **`Time.get_ticks_usec()` Windows résolution** : GDD + gameplay-programmer supposent risque 15 ms ; godot-specialist confirme `QueryPerformanceCounter` 100ns + `timeBeginPeriod(1)` au boot. **Tranché godot-specialist** — AC-L-2 peut être supprimée ou relâchée.
- **`Input.action_press()` existence** : qa-lead dit inexistante, godot-specialist dit existe mais ne trigger pas `_unhandled_input`. **Les deux ont partiellement raison** — reformuler avec `parse_input_event()`.

### Décisions r2 non remises en cause (toujours solides)

- 60 Hz physique (défaut Godot) avec cible intra-engine ≤ 16 ms ✓
- Tap restart edge-triggered, hold délégué à Checkpoint ✓ (mais R2 demande décision explicite post-kill grace window Input-side)
- Typed signals par action ✓ (R4+N5 flagged fragilité extension)
- Overlay Controls dans pause menu ✓ (R3 flagged tension onboarding)
- Sensitivity safe range élargi [0.0005, 0.012] ✓

### Plan d'action ADR-first (retenu par Martin via widget)

1. **(45 min) Réouverture ADR-0001** — ajouter critère mesurable d'escalade 60→120 Hz (R1 game-designer).
2. **(1h) Création ADR-0002 Input API & Focus Handling** — fige `was_pressed_this_tick`, reset synchrone, `request_disable(owner)/request_enable(owner)`, signal `application_focus_lost`, pattern ring buffer PackedFloat32Array (B1+B2+B4+B7+R6).
3. **(1h30) Application fixes GDD** — réécriture sections API publique, Interactions, Cross-Refs, ACs AG-2/AG-3/CS-1. Supprimer/relâcher AC-L-2. Remplacer dict par PackedFloat32Array. Corriger AC-AG-1 avec `parse_input_event`. Retirer `#if debug_build`.
4. **(45 min) Réécriture 5 ACs critiques** avec `parse_input_event` au lieu de `Input.action_press()`. Defer 12 autres ACs vers sprint QA dédié.
5. **Dette Sprint 2 acceptée** : R3 (onboarding), R4 (charge/combo), R5 (debounce), R7 (SaveLoad boot), N3 (debounce slider), AC-FEEL-01 (playtesters N≥3 impossible solo).

### Actions post-review

- [x] r4 fresh session exécutée (2026-04-21, 7 specialists + creative-director synthesis)
- [x] systems-index.md statut Input System : r3 LEAN → r4 MAJOR REVISION (ADR-first path)
- [x] Review log append avec traçabilité complète (ce document)
- [ ] **Réouverture ADR-0001** — ajouter critère mesurable d'escalade (à exécuter cette session ou suivante)
- [ ] **Création ADR-0002 Input API & Focus Handling** (à exécuter cette session ou suivante)
- [ ] Application fixes GDD (après ADR-0002 merged)
- [ ] Re-review r5 : **LEAN limité godot-specialist + qa-lead** sur les 7 BLOCKINGs après application (pas full 7 specialists)
- [ ] Création `tests/performance/input_benchmark.tscn` avant implémentation Sprint 1 (une fois GDD approuvé)

### Escalations techniques

- **Technical-director** : créer ADR-0002 (Input API & Focus Handling) — prioritaire ADR-first path. Création ADR rendering-latency pour cible end-to-end ≤ 50 ms reste ouverte (secondaire).
- **Godot-specialist** : validations confirmées 4.6 en r4 (NOTIFICATION_APPLICATION_FOCUS_OUT/IN existent valeurs 2016/2017, `Time.get_ticks_usec` utilise QPC, API runtime InputMap stable). Deux nouveaux points : `Input.mouse_mode` thread safety main-only, `ResourceLoader.load()` wrong-type Resource fallback.

---

## Review — 2026-04-21 — r3 re-review fresh session — Verdict: NEEDS REVISION (LEAN)

**Scope signal** : M (doc revision ~3-4h session concentrée) / M-L (implementation post-revision selon couverture AC)
**Mode** : full (6 specialists + creative-director senior synthesis)
**Specialists** : game-designer, systems-designer, qa-lead, gameplay-programmer, godot-specialist, performance-analyst, creative-director
**Blocking items** : 5 (convergents cross-specialist) | **Recommended revisions** : 12 | **Nice-to-have** : 8
**Prior verdict resolved** : r2 "Approved" n'a PAS résolu 2 BLOCKINGs de r1 — focus handling IDs Godot 4.6 et `Time.get_ticks_usec()` résolution Windows restaient "À vérifier" sans vérification. r3 les re-classifie BLOCKING + identifie 3 nouveaux BLOCKINGs structurels.

### Résumé (synthèse creative-director)

> "La convergence cross-specialists est trop forte sur 3 axes structurels (focus handling Wayland, reference counting `set_enabled`, budget hiérarchie 16ms/0.1ms/0.5ms) pour laisser passer ce GDD en implémentation Sprint 1. Ces défauts ne sont pas cosmétiques : ils produiraient soit un gate CI mort (faux vert), soit un bug architectural (pause ré-activée prématurément), soit un feature cassé silencieusement sur Linux/Wayland — précisément le canari Pillar 1 FLOW. En revanche, la densité des findings est trompeuse : une r3 LEAN ciblée sur 5 fixes surgicaux débloque Sprint 1 sans re-review complète. Aucun finding ne remet en cause les décisions r2 (60 Hz, tap restart, typed signals, overlay Controls) — ils les solidifient."

### Top 5 BLOCKINGs identifiés (convergents multi-voices)

1. **Focus handling ordering + Wayland multi-frame** (3 voices : godot-specialist #1 + gameplay-programmer #1 + game-designer #1) — `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` IDs non confirmés en Godot 4.6 (prior r1 BLOCKING non résolu, juste marqué "À vérifier"). Le flag `_skip_next_mouse_delta` booléen ne tient pas en séquence multi-frame ni sur Wayland : ordering `_notification` vs `_unhandled_input` n'est pas garanti par Godot. Conséquence : camera snap 68° au retour alt-tab sur Linux/Wayland = violation directe Pillar 1 FLOW invisible aux devs Windows. **Fix** : (a) WebSearch docs Godot 4.6 stables pour confirmer IDs, (b) consuming flag time-based (drop deltas pendant ~50ms post-FOCUS_IN), (c) hook `_on_application_focus_changed(bool)` ajouté à l'API publique.

2. **Budget hiérarchie 16 ms / 0.5 ms / 0.1 ms confus = gate CI mort** (3 voices : qa-lead BLK-06/09 + systems-designer + performance-analyst #1) — AC-L-3 dit `≤ 16 ms p99` mais nominal réel est `~0.005-0.01 ms`. Une régression 100× pire passe vert CI. AC-PF-1 `≤ 0.5 ms debug` = exactement `latency_anomaly_threshold_ms` debug → test passe + spam warnings. **Fix** : hiérarchie explicite **ceiling** (16 ms — feel OK, ne jamais dépasser) / **gate CI** (0.5 ms — régression détectable) / **watchdog** (0.1 ms — alerte dev).

3. **`set_enabled()` / `set_mouse_captured()` reference counting absent** (2 voices : systems-designer #4/#5 + gameplay-programmer implicite) — Menu + Checkpoint appellent `set_enabled(false)` indépendamment. Premier `set_enabled(true)` ré-active input alors que 2e appelant attend encore → jeu contrôlable pendant pause/respawn. **Fix** : refactor API en `push_disable(owner) / pop_disable(owner)` avec refcount interne.

4. **Routing `_input` vs `_unhandled_input` non testé + Dict literal invisible au grep AC-PF-2** (3 voices : qa-lead BLK-10 + gameplay-programmer #5 + performance-analyst #2) — AC manquant pour règle 12 : Control focused (ex: TextEdit) peut swallower Escape → jeu impossible à unpauser. Dict literal `{ts=..., ms=...}` dans hot path alloue mais grep `Dictionary(` ne le matche pas → 60-144 allocs/s invisibles CI. **Fix** : (a) AC-UI-01 interaction test GUT pause unpausable, (b) ring buffer en 2 PackedFloat32Array pre-alloués + write_index circulaire, (c) AC-PF-2 grep multi-ligne étendu.

5. **AC testabilité : APIs inexistantes + hooks non-publiés** (7 sub-findings qa-lead BLK-01/02/03/04/05/07/11) — `Input.action_press()` n'existe pas Godot 4.x (AC-AG-1). "Même frame" non déterministe en GUT headless. Hook `_on_application_focus_changed` utilisé par AC-MC-4/5 mais absent section API. AC-L-2 "5.0 ms calibré" sans mécanisme injection timer (lié `Time.get_ticks_usec()` résolution Windows non vérifiée en 4.6). Aucun AC pour clamp `set_mouse_sensitivity` hors safe range. AC-P-1 I/O filesystem en test unit viole coding-standards. **Fix** : corrections ponctuelles ~30-45 min.

### Revisions recommandées (non-blocking, 12 items résumés)

- R1 Dépendance circulaire Input → GameStateManager (systems-designer #6) — via signal `application_focus_lost`
- R2 Contradiction tableau Dependencies SaveLoadManager "Amont" vs note "pas d'appel croisé au boot" (gameplay-programmer #6)
- R3 Camera GDD clamp `max_delta_radians_per_frame` absent (systems-designer #2) — sens 0.012 + flick 100px = 68°/frame non clampé
- R4 Décision 60 Hz sans critère d'escalade documenté (game-designer #2)
- R5 Budget Pillar 3 non contraint vers Checkpoint GDD (game-designer #3) — RESPAWN_DELAY + hold peut dépasser 2s
- R6 IO synchrone `input_settings.tres` sur remap runtime → frame drop HDD (performance-analyst #8)
- R7 Formule courbe slider sensitivity non spécifiée, puissance vs log-géométrique (systems-designer #7)
- R8 Contract `attack` hold behavior non-spécifié (game-designer #7)
- R9 `percentile_99` implémentation non documentée + pop_front O(N) worst case (performance-analyst #3/#4)
- R10 AC-FEEL-02 référence cassée "AC-LAT-01" + AC-FEEL-01 N≥3 non viable solo + AC-FEEL-03 mesure mauvaise métrique (qa-lead REV-08/09/10)
- R11 Guard de type manquant dans `_input` pseudocode règle 12 (gameplay-programmer #5b)
- R12 AC-PF-3 NVIDIA LDAT non faisable solo → alternative `RenderingServer.frame_pre_draw` (performance-analyst #9)

### Nice-to-have (backlog, 8 items)

Slider expo curve formelle, thread safety note `Input.mouse_mode` main-thread, `debug_toggle` erase_action pattern en release, doc `is_echo()` inexacte sur InputEvent base, `Input.get_vector()` deadzone -1.0 clarification, SDL3 triggers post-MVP deadzone `attack` 0.5, 3 sources de vérité fallback 0.0022, `Time.get_ticks_usec()` double-appel coût marginal.

### Agent disagreements surfaced + tranchés

- **Désaccord 1 — Gravité budget 16 ms** : performance-analyst (REVISION) vs qa-lead (BLOCKING BLK-06/09). **Tranché BLOCKING** par creative-director — gate CI mort est structural, pas cosmétique.
- **Désaccord 2 — Pillar 1 à 60 Hz vs 120 Hz** : game-designer seul (REVISION sans critère escalade). **Tranché REVISION retenue** — pas de remontée pillars, 60 Hz tient pour MVP (Hades/Dead Cells aussi 60 Hz). Ajouter juste trigger conditions pour révision.

### Décisions r2 non remises en cause (confirmées solides)

- 60 Hz physique (défaut Godot) avec cible intra-engine ≤ 16 ms
- Tap restart edge-triggered, hold délégué à Checkpoint
- Typed signals par action (`jump_pressed`, `dash_pressed`, etc.)
- Overlay Controls dans pause menu (MVP obligatoire)
- Sensitivity safe range élargi [0.0005, 0.012]

Les 5 BLOCKINGs **solidifient** ces décisions au lieu de les remettre en cause.

### Priorité fix r3 (ordonnées, ~3h30-4h total solo dev)

1. Budget hiérarchie ceiling/gate/watchdog (~30 min) — Performance + AC-L-3 + AC-PF-1
2. API fix AC-AG-1 + AC-AG-2 (~30 min) — `Input.parse_input_event()` + spec "même frame"
3. Focus handling refactor + NOTIFICATION IDs confirm (~1h) — WebSearch docs 4.6 + consuming flag timeout
4. `set_enabled` refcount API (~45 min) — refactor `push_disable/pop_disable` + AC double-call
5. Dict literal watchdog fix (~45 min) — PackedFloat32Array pre-allocated + grep multi-ligne AC-PF-2
6. (Bonus) Dépendance circulaire Input → GameStateManager via signal (~30 min)

### Actions post-review

- [x] Re-review fresh session exécutée (2026-04-21, 6 specialists + creative-director)
- [x] systems-index.md statut Input System : In Review → **NEEDS REVISION (r3 LEAN)**
- [x] Review log append avec traçabilité complète (ce document)
- [ ] **r3 LEAN en session séparée** — relancer `/design-review design/gdd/input-system.md` après `/clear` pour application des 5 fixes chirurgicaux
- [ ] Re-review post-r3 : **LEAN limité qa-lead + godot-specialist** sur les 5 BLOCKINGs uniquement (pas full 6 specialists, creative-director recommandation explicite)
- [ ] Escalation technical-director : ADR physics-rate 60 Hz (acté mais non documenté)
- [ ] Escalation godot-specialist : vérification `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` IDs en 4.6 + résolution `Time.get_ticks_usec()` Windows
- [ ] Post-r3 APPROVED : création `tests/performance/input_benchmark.tscn` avant implémentation Sprint 1

### Escalations techniques (hors scope GDD revision)

- **Technical-director** : ADR `adr-physics-rate.md` (60 Hz acté post-r2 mais non documenté) + ADR `adr-rendering-latency.md` (cible end-to-end ≤ 50 ms dépend du VSync/refresh config)
- **Godot-specialist** : vérification runtime `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` valeurs numériques en Godot 4.6 (via engine-reference update ou test harness), + vérification `Time.get_ticks_usec()` utilise QPC sur Windows (pas GetSystemTimeAsFileTime) — les deux bloquants maintenus depuis r1

---

## Review — 2026-04-21 — Verdict: NEEDS REVISION → Approved (r2)

**Scope signal** : M (doc revision, 3-4 jours) / S (implementation post-revision)
**Mode** : full (6 specialists + creative-director senior synthesis)
**Specialists** : game-designer, systems-designer, qa-lead, gameplay-programmer, godot-specialist, performance-analyst, creative-director
**Blocking items** : 4 | **Recommended revisions** : 11 | **Nice-to-have** : 5
**Prior verdict resolved** : First review

### Résumé (synthèse creative-director)

> "Fondations solides — APIs Godot 4.6 validées, architecture broadly correct, separation of concerns globalement respectée. Mais 3 BLOCKINGs réels + 4 convergences cross-specialists interdisent d'aller en implémentation en l'état. Menace #1 au FLOW si implémenté tel quel : la désynchro signal/polling d'un tick combinée au saut caméra au retour focus. Ce ne sont pas des problèmes de latence mesurable, ce sont des pertes de confiance motrice. Le joueur ne dit pas 'il y a 1 tick de délai', il dit 'le jeu m'a trahi'. Design test du GDD révisé : un joueur alt-tab en plein combat, revient, swing katana — aucune trahison perçue. Si oui, FLOW tenu."

### Bloquants identifiés

1. **`restart_hold_duration` 0.5 s ownership** (game-designer + systems-designer convergent) — logique métier anti-misclick piégée dans Input, viole règle "no business logic". Edge Cases ne documente pas le mécanisme. Ownership ambigu (Input vs Checkpoint).
2. **Signal `action_pressed` vs polling `is_action_just_pressed` désynchro** (systems-designer + gameplay-programmer + performance-analyst convergent, 3 voix) — `_unhandled_input` vs `_physics_process` peuvent diverger d'un tick physique (8.3 ms @ 120 Hz). Menace directe Pillar 1 : un tick de désynchro sur katana-swing = bug injouable.
3. **Flag `_skip_next_mouse_delta` au retour de focus non implémenté** (gameplay-programmer) — GDD dit "delta du premier frame jeté" comme si Godot le fait automatiquement. Faux sur Windows. Sans mitigation, alt-tab → rotation caméra brutale au retour = rupture FLOW visible.
4. **`NOTIFICATION_APPLICATION_FOCUS_OUT/IN` IDs 4.6** (godot-specialist) — UNCERTAIN. Pas confirmé dans docs engine-reference projet. 4.6 dual-focus system peut avoir déplacé la sémantique vers `Window.focus_entered/exited`.

### Revisions recommandées (non-blocking mais critiques)

- Cible latence 8 ms mal cadrée (intra-engine only, chaîne totale joueur = 15-25 ms) — 2 specialists convergent
- Ring buffer p99 biaisé (120 samples ≠ 1 s réelle) — 2 specialists convergent
- `ui_cancel_pressed` perméabilité non contrôlable (futures cutscenes/tuto)
- `_input` vs `_unhandled_input` pour `ui_cancel` (Controls focusés consomment Escape avant `_unhandled_input`)
- `t_event` timestamp faux : pas fourni par Godot, à capter manuellement
- Deadzone 0.2 documentée comme pertinente pour clavier (faux, binaire)
- `is_action_just_pressed` sur action inexistante : `false` silencieux sans contrat
- 13/22 ACs non-testables en l'état (qa-lead)
- Race Save/Load au boot : ordre autoload non contraint
- Typo API `disabled=false` → `enabled=false`
- Windows Enhanced Pointer Precision Open Question non fermée

### Décisions design prises (Martin, 2026-04-21 — via /design-review widgets)

| Question | Décision |
|---|---|
| `restart_hold_duration` ownership | **Move to Checkpoint** (puis en r2 : supprimé complètement — tap restart instantané, aligné Pillar 3) |
| Signal vs polling canonicalisation | **Polling gameplay, signals UI-only** + Forbidden Pattern (en r2 : upgraded en typed signals par action — compile-time safety) |
| `ui_cancel_passthrough` flag | **Déféré** à Open Questions (ajout quand Cutscene System sera spec'd) |

### Décisions additionnelles actées dans r2 (par Martin directement)

- **Physics rate** : 120 Hz → **60 Hz** (défaut Godot). Latence intra-engine cible passe 8 ms → 16 ms (1 tick @ 60 Hz). ADR à venir pour formaliser. Chaîne totale joueur 25-50 ms.
- **Signals typed par action** (`jump_pressed`, `dash_pressed`, etc.) au lieu de signal générique `action_pressed(StringName)`. Zero dispatch côté consommateur. Compile-time safety. Post-MVP remapping peut ajouter un signal générique en complément sans retirer les typés.
- **Sensitivity range élargi** (détails dans GDD).
- **Overlay debug controls pause menu** — interactions détaillées dans r2.

### Actions post-review

- [x] Décisions design prises par Martin (3 widgets answered + édits directes r2)
- [x] Rewrites du GDD (restart tap, typed signals, 60 Hz, focus handling pseudocode, algo p99 time-based, callback routing `_input` vs `_unhandled_input`, autoload order prescription, AC reformulées, Edge Cases clarifiés)
- [x] `systems-index.md` status Input System : Designed → Approved
- [x] Registry entry `mouse_sensitivity` : owned par Input System, formalisé dans Cross-References
- [ ] `/consistency-check` pour valider que Movement GDD a retiré `MOUSE_SENS` de ses Tuning Knobs et remplacé par référence
- [ ] ADR requis (technical-director) : physics rate 60 vs 120 Hz + latence target
- [ ] ADR requis (godot-specialist) : vérifier IDs `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` en Godot 4.6 (dual-focus system impact)
- [ ] Création `tests/performance/input_benchmark.tscn` avant implémentation (AC-L-3, AC-PERF-1 en dépendent)

### Agent disagreements surfaced

- **Signal `action_pressed` O(N×M)** : performance-analyst classait BLOCKING ; creative-director rétrograde à REVISION sévère (theoretical, pas observé). **Résolu en r2** par Martin : typed signals par action élimine entièrement le pattern O(N×M). Convergence naturelle vers la meilleure solution.
- **"Raw input zéro acceleration"** : game-designer demandait tradeoffs documentés. Closed in r2 : décision Ghostrunner-aligned reconfirmée, Open Question Windows Enhanced Pointer Precision reste ouverte mais avec AC de validation plannifié.

### Escalations techniques (hors scope GDD revision)

- **Technical-director** : ADR requis sur physics rate 60 vs 120 Hz (affecte budget latence, frame budget global, coûts simulation). La décision r2 est 60 Hz mais il faut un ADR pour documenter le raisonnement et les implications aux autres systèmes (Movement physique, Combat hitboxes).
- **Godot-specialist** : vérification `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` IDs en 4.6 dual-focus. Ouvrir la doc officielle ou tester en engine avant la première story qui touche focus handling.
