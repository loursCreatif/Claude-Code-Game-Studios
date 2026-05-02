# Epic: Upgrade System

> **Layer**: Feature
> **GDD**: `design/gdd/upgrade-system.md` (APPROVED r2, 2026-04-28)
> **Architecture Module**: `UpgradeSystem` (`docs/architecture/architecture.md` §4.3 ligne 149 — Feature Layer Game Systems)
> **Status**: 10/11 Complete (story-011 Visual/Feel pending Martin playtest)
> **Stories**: 11 stories écrites 2026-04-28 — voir table ci-dessous

## Stories

| # | Story | Type | Status | ADR / Source |
|---|-------|------|--------|--------------|
| 001 | [autoload-skeleton-capability-vars](story-001-autoload-skeleton-capability-vars.md) | Integration | Complete | ADR-0007 D-1/D-4 + R-UPG-1/2/11 |
| 002 | [logger-di-unknown-id-warning](story-002-logger-di-unknown-id-warning.md) | Logic | Complete | R-UPG-9 + GDD r2 B-11 |
| 003 | [apply-upgrade-helper-flag-sync-idempotent](story-003-apply-upgrade-helper-flag-sync-idempotent.md) | Logic | Complete | ADR-0001 + R-UPG-4 (1/3/4) + C.1 helper |
| 004 | [apply-upgrade-resync-guard-step2](story-004-apply-upgrade-resync-guard-step2.md) | Logic | Complete | R-UPG-4 step 2 r2 + EC-UPG-13/14 |
| 005 | [boot-hydration-saveload-readyfn](story-005-boot-hydration-saveload-readyfn.md) | Integration | Complete | ADR-0010 + R-UPG-5 (1/3/4) + F-UPG-2 |
| 006 | [save-bloat-truncation-defense](story-006-save-bloat-truncation-defense.md) | Logic | Complete | R-UPG-5 step 2 r2 + EC-UPG-36 |
| 007 | [pull-pattern-movement-integration](story-007-pull-pattern-movement-integration.md) | Integration | Complete | ADR-0001 + R-UPG-7/8 |
| 008 | [catalog-sanity-test-fupg3](story-008-catalog-sanity-test-fupg3.md) | Logic | Complete | F-UPG-3 + R-UPG-3 |
| 009 | [anti-patterns-lint-static](story-009-anti-patterns-lint-static.md) | Logic | Complete | R-UPG-6/10/12/14 |
| 010 | [performance-headless-ci](story-010-performance-headless-ci.md) | Logic | Complete | F-UPG-2 + ADR-0001 frame budget |
| 011 | [playtest-pillar2-understanding-evidence](story-011-playtest-pillar2-understanding-evidence.md) | Visual/Feel | Ready (Martin playtest) | Pillar 2 — AC-UPG-37/37-bis |

**Décomposition** : 7 Logic + 3 Integration + 1 Visual/Feel. Manifest v2026-04-23. Engine Risk LOW.

**Ordre de pickup recommandé** (dépendances) : 001 → 002 → 003 → 004 → 005 → 006 → 008 → 007 → 009 → 010 → 011.

**Notes scope finalisé** :
- Story 002 introduit le pattern Logger DI pour testabilité `push_warning` (refactor Sprint 1 obligatoire).
- Story 004 résout le Cas C/D resync (B-4 r2 amendement) — sans cette story, regression vers early return strict r1.
- Story 006 livre la truncation `MAX_CATALOG_SIZE_TIER_2 * 2 = 14` (B-6 r2).
- Story 008 décide OQ-UPG-10 RESOLVED : F-UPG-3 path = `tests/integration/upgrade/catalog_sanity_test.gd` (instancie autoload pour `get_property_list()`) ; lint statique grep va dans `tests/static/`.
- Story 009 AC-UPG-29 cross-GDD shop integration : Sprint 1 fallback grep statique seul si Shop story `try_buy` pas mergée — promotion full integration coordonnée Shop epic.
- Story 011 AC-UPG-37 partiellement automatisable (SceneTree inspector) ; AC-UPG-37-bis playtest manuel obligatoire avec sign-off game-designer + creative-director.

## Overview

Upgrade System est l'**autorité canonique** sur l'état des capacités permanentes du joueur. C'est un autoload data-pure quasi-stateless (`src/gameplay/upgrade/upgrade_system.gd`) qui expose trois booléens publics typés (`can_air_jump`, `can_dash`, `can_wall_run`) et trois méthodes API (`apply_upgrade(id: StringName) -> void` SYNC idempotent, `is_owned(id) -> bool` getter pur, `get_owned_count() -> int` debug-only). Il vit entre **Shop System** (qui appelle `apply_upgrade(id)` à chaque achat réussi — R-SHP-6 étape 5c locked) et **Player Movement System** (qui lit les capability flags chaque tick depuis `_physics_process` — Movement Rules 3, 6, 7 locked). Au boot, Upgrade lit `SaveLoad.load_string_array("owned_upgrades", [])` (ADR-0010 R-SAV-4) et applique tous les upgrades chargés en une passe via le helper `_apply_flag()` qui valide existence + `typeof == TYPE_BOOL` + assert post-set. Catalog MVP : `{&"double_jump" → &"can_air_jump", &"dash_horizontal" → &"can_dash"}`. Aucun signal outbound, aucune UI propre, aucune persistance write (Shop owns la clé `"owned_upgrades"`). Sert **Pillar 2 LA PROGRESSION SE VOIT** (le crédit devient capacité physique permanente, vu à la milliseconde où le doigt presse la touche au prochain saut) et **Pillar 1 FLOW** par soustraction (zéro UI, zéro friction runtime, lecture pull O(1)).

## Governing ADRs

Aucun ADR Upgrade-spécifique n'est requis au MVP — décision r2 B-2 du GDD : la friction d'un ADR pour ajouter `&"wall_run_long"` ou renommer `&"double_jump"` serait disproportionnée pour solo team en itération playtest Tier 2+. Le vrai garde-fou est **F-UPG-3 catalog sanity test CI** (build-time invariant). Trigger ADR escalation : si N > 12 capabilities (refactor `var → Dictionary[StringName, bool]`) OR si modification renomme un id déjà utilisé en save (breaking change, EC-UPG-19 migration tool requise).

ADRs hérités gouvernant l'implémentation Upgrade :

| ADR | Decision Summary | Engine Risk |
|-----|------------------|-------------|
| **ADR-0001** Physics Rate 60 Hz | Movement lit `Upgrade.can_*` en `_physics_process` à 60 Hz (R-UPG-8 pull pattern) | LOW |
| **ADR-0007** GameStateManager + Scene Transition | Autoload order D-1 (`InputManager → GSM → SaveLoad → Audio → UpgradeSystem` pos 5) ; process_mode D-4 (`PROCESS_MODE_ALWAYS` pour autoload pause-resilience EC-UPG-35) ; D-9 (GSM init MENU sans transition synchrone garantit `Upgrade._is_hydrated` avant premier `start_etage`) | LOW |
| **ADR-0010** Save/Load Persistence (ConfigFile Ratification) | R-SAV-4 `load_string_array(key: String, default: Array[StringName]) -> Array[StringName]` consommé une fois au `_ready()` Upgrade boot hydration (R-UPG-5) ; Upgrade ne persiste jamais (R-UPG-10, Shop owns write) | MEDIUM |

**Engine Risk global Epic** : LOW (architecture.md ligne 106 confirms ; aucune API Godot post-cutoff utilisée — `set/get` reflection + `get_property_list()` stables depuis Godot 3.x ; `Engine.register_singleton/unregister_singleton` stable Godot 4.1+ pour mock tests EC-UPG-32).

## GDD Requirements

Note registry : aucune entrée `TR-upg-*` n'existe dans `docs/architecture/tr-registry.yaml` (registry contient seulement `cam`/`cmb`/`gc`/`inp`/`lvl`/`mov` — peuplé par `/architecture-review` r1-r5 sur systèmes Foundation/Core déjà traversés). Stories devront référencer directement les sections GDD (`R-UPG-N`, `F-UPG-N`, `EC-UPG-N`, `AC-UPG-N`) plutôt que des TR-IDs registry. **Action follow-up post-Sprint 1** : ajouter `TR-upg-001` à `TR-upg-014` (mapping 1-pour-1 sur R-UPG-1..14) au registry lors d'une prochaine `/architecture-review` rotation.

### Core Rules (14 R-UPG)

| Section GDD | Requirement | Couverture |
|-------------|-------------|------------|
| R-UPG-1 | UpgradeSystem autoload `src/gameplay/upgrade/upgrade_system.gd`, instancié au boot, survit transitions scène, `PROCESS_MODE_ALWAYS` set programmatique (R-18) | ADR-0007 D-1 + D-4 ✅ |
| R-UPG-2 | 3 booléens publics typés statiquement `can_air_jump`/`can_dash`/`can_wall_run`, démarrent `false`, seules propriétés publiques capabilities | GDD seul (data-pure) ✅ |
| R-UPG-3 | Catalog `_CATALOG: const Dictionary` owned exclusivement Upgrade. **Pas d'ADR requis MVP** (B-2 reframe). Trigger ADR : N > 12 OR breaking save format. | GDD r2 B-2 ✅ |
| R-UPG-4 | `apply_upgrade(id) -> void` SYNC idempotent. Step 2 guard `_owned.has(id) AND get(flag_name) == true` (les **deux** vrais → return). Step 4 invoque helper `_apply_flag` (B-3 r2). | GDD r2 B-3 + B-4 ✅ |
| R-UPG-5 | Boot hydration `_ready()` : load_string_array → truncate si `> MAX × 2 = 14` (B-6) → boucle `apply_upgrade(id)` → `_is_hydrated = true` (R-1 rename) | ADR-0010 R-SAV-4 ✅ |
| R-UPG-6 | Zéro signal outbound **au MVP** (R-3 framing). Movement poll. Tier 2+ peut ajouter signal additif (OQ-UPG-3, OQ-UPG-5). | GDD seul ✅ |
| R-UPG-7 | Defer-apply EC-SHP-17 résolu trivialement par pull pattern. Player-perspective scenario doc (R-2). | GDD seul ✅ |
| R-UPG-8 | Movement consumer pull-only ; ne connaît pas `apply_upgrade`. Upgrade ignore Movement (outbound-only). | Movement r3 §Dependencies ligne 69/315/489 ✅ |
| R-UPG-9 | Id inconnu → `push_warning` + early return (forward-compat EC-SHP-8) | GDD seul ✅ |
| R-UPG-10 | Upgrade ne persiste jamais. Shop écrit `"owned_upgrades"` (Shop r1 R-SHP-8). | Shop r1 ✅ |
| R-UPG-11 | Ordre autoload `InputManager → GSM → SaveLoad → Audio → Upgrade` (extension ADR-0007 D-1). Contrainte stricte unique : `index(SaveLoad) < index(Upgrade)`. | ADR-0007 D-1 ✅ |
| R-UPG-12 | Pas de `revoke_upgrade` MVP. Reframe r2 B-1 : cause directe = scope MVP (UI respec + politique refund + mental model build dynamique), anti-pilier "skill tree" devient conséquence cascade. | GDD r2 B-1 ✅ |
| R-UPG-13 | Capabilities indépendantes (pas de prérequis croisés). Shop owns gating UI séquentiel. | GDD seul ✅ |
| R-UPG-14 | Single responsibility : Upgrade ignore coût (Credit F-CRD-3), persistance write (Shop+SaveLoad), UI (Shop+HUD). | Cross-GDD ✅ |

### Formulas (4 F-UPG)

| Formule | Description | Couverture |
|---------|-------------|------------|
| F-UPG-1 | Cost lookup DÉLÉGATION owned Credit Economy F-CRD-3 (Upgrade ne calcule jamais) | Credit r2 ✅ |
| F-UPG-2 | Boot hydration sequence O(N) idempotent + Invariant 5 (`_ready()` strictement SYNC, R-15) | GDD r2 R-15 ✅ |
| F-UPG-3 | Catalog sanity invariant build-time GUT (test bidirectionnel Shop ⊆ Upgrade ET Upgrade ⊆ Shop avec TIER_2_STUBS_EXEMPT) | F-UPG-3 r1.2 supplemental ✅ |
| F-UPG-4 | Tier 2+ catalog growth deferred 7 entrées (post-r1.2 retrait `can_secret_radar` Pillar 4) ; cross-ref EC-UPG-9 vars-before-_CATALOG (B-8) | GDD r2 B-8 ✅ |

### Edge Cases (36 EC, 11 catégories A-K)

Couvertes par GDD §Edge Cases — Catégories A (autoload boot ×5), B (id validation ×5), C (idempotence ×4), D (save corrompue ×5), E (defer pattern ×4), F (multi-call atomicité ×3), G (Tier 2+ forward-compat ×3), H (sécurité anti-cheat ×2), I (test/mock ×2), J (process_mode pause ×2), **K save bloat truncation ×1 NEW r2 B-6**.

### Acceptance Criteria (45 ACs, 11 catégories A-K)

39 BLOCKING + 4 ADVISORY + 1 PLAYTEST + 1 PROVISIONAL Tier 2+. ~41 AUTO + 1 PLAYTEST + 3 PROVISIONAL chain. Couvertes par GDD §Acceptance Criteria — Catégories A architecture×6, B apply_upgrade×9 (incl. AC-UPG-9-bis NEW r2 B-4 + AC-UPG-6-bis NEW grep mutation), C boot hydration×8, D pull pattern Movement×4 (incl. AC-UPG-24 mock vs real R-10), E pas de persistance×3, F process_mode×2, G anti-patterns×5, H forward-compat×2, I performance×2 (headless ubuntu-latest CI R-14), J PROVISIONAL×2 (promus AUTO BLOCKING via Save/Load r1 unblock), **K save bloat×2 NEW r2 B-6** (AC-UPG-44 BLOCKING + AC-UPG-45 ADVISORY boundary).

## Dependencies

### Hard (Upgrade ne peut pas fonctionner sans)

| Système | Direction | Status | Contrat |
|---------|-----------|--------|---------|
| **Shop System** | In (Shop appelle Upgrade) | ✅ Designed r2 | `apply_upgrade(id: StringName) -> void` SYNC idempotent (R-SHP-6 step 5c) |
| **Player Movement System** | Out (Movement lit Upgrade) | ✅ Designed r3 | Pull `can_air_jump`/`can_dash`/`can_wall_run` 60 Hz `_physics_process` (Movement Rules 3, 6, 7) |
| **Save/Load System** | In (Upgrade lit au boot) | ✅ Designed r1 + ADR-0010 Accepted | `load_string_array("owned_upgrades", []) -> Array[StringName]` (R-SAV-4) |

### Soft

| Système | Direction | Status | Lien |
|---------|-----------|--------|------|
| **Game State Manager** | Indirect (ordre autoload) | ✅ APPROVED r1 | ADR-0007 D-1 ordre canonique étendu R-UPG-11 |
| **Audio System** | Out (peer Tier 2+) | ✅ APPROVED r2.1 | Tier 2+ SFX d'unlock latent (OQ-UPG-3) |

### Anti-deps (zéro reference)

Movement, Credit, Shop, HUD, Audio, VFX, Camera, Combat, Input — lint statique cover-all.

## Definition of Done

This epic is complete when :

- [ ] All stories implémentées, reviewed, et closed via `/story-done`
- [ ] All 45 ACs vérifiés (39 BLOCKING + 4 ADVISORY + 1 PLAYTEST + 1 PROVISIONAL Tier 2+)
- [ ] Helper `_apply_flag(flag_name: StringName)` implémenté avec 3 asserts (existence + `typeof == TYPE_BOOL` + post-set) — Section C.1 GDD
- [ ] R-UPG-4 step 2 guard `_owned.has(id) AND get(flag_name) == true` (les **deux** vrais → return) — AC-UPG-9-bis BLOCKING resync test passe
- [ ] R-UPG-5 step 2 truncation `> MAX_CATALOG_SIZE_TIER_2 * 2 (=14)` — AC-UPG-44 BLOCKING + AC-UPG-45 ADVISORY boundary tests passent
- [ ] F-UPG-3 catalog sanity test CI passe (`tests/integration/upgrade/catalog_sanity_test.gd` ou `tests/static/` selon décision OQ-UPG-10)
- [ ] AC-UPG-6-bis grep statique zero `_CATALOG[..] = ` mutation production passe
- [ ] AC-UPG-12 grep statique zero `await/yield` dans `apply_upgrade` body passe
- [ ] AC-UPG-27 zero signal outbound passe (filter Object/Node Godot 4.6 whitelist explicite — R-16)
- [ ] AC-UPG-28 grep zero `SaveLoad.save_*` ou `SaveLoad.write_*` passe
- [ ] AC-UPG-34/35/36 grep zero UI/Audio/revoke_upgrade passe (word-boundary + filter commentaires)
- [ ] Logger DI refactor mineur Sprint 1 effectué (cf. AC-UPG-10/11/19/20 — code production utilise `_logger.warn(msg)` au lieu de `push_warning(msg)` direct pour testabilité)
- [ ] Pull pattern Movement vérifié end-to-end (AC-UPG-24 option (a) BLOCKING fixture mock + option (b) ADVISORY scène réelle player.tscn)
- [ ] Tests perf headless ubuntu-latest CI : AC-UPG-40 `_ready()` < 1 ms ; AC-UPG-41 `apply_upgrade()` médiane < 100 µs (R-14)
- [ ] AC-UPG-37-bis playtest novice 80% en 30s post-shop comprend nouvelle capacité (Pillar 2 validation)

## Open Items / Follow-ups

- **OQ-UPG-2 PARTIALLY RESOLVED** : Movement r3 actuel verrouille pull pattern. Caveat post Movement r4 fresh re-review si push pattern introduit (R-UPG-6 + R-UPG-8 + EC-UPG-22/23 ré-évaluation).
- **OQ-UPG-3 SFX d'unlock Tier 2+** : décision audio-director + creative-director (Pillar 1 vs Pillar 2 trade-off). Latent.
- **OQ-UPG-8 Shop r2 cosmetic amendment** : promote OQ-SHP-2 RESOLVED → VERROUILLÉ. Hors scope Sprint 1.
- **OQ-UPG-9 systems-index ligne 154 phrasing raffinement** : "Movement consume Upgrade as data source via pull". Hors scope Sprint 1.
- **OQ-UPG-10 F-UPG-3 test path** : `tests/integration/upgrade/` vs `tests/static/`. À confirmer lors de `/create-stories`.
- **OQ-UPG-11 affordability marge 25 cr** : cross-GDD Credit r3 / Shop r2. Hors scope Upgrade.
- **3 nice-to-have raffinements éditoriaux** (ne bloquent pas l'epic) : EC-UPG-9 obsolescence post-helper, AC-UPG-15 step (c) instance bare, OQ-UPG-11 economy chain.
- **Action follow-up post-Sprint 1** : ajouter TR-upg-001..014 au tr-registry.yaml lors de prochaine `/architecture-review` rotation pour cohérence cross-system.

## Next Step

Run `/create-stories upgrade-system` to break this epic into implementable stories.
