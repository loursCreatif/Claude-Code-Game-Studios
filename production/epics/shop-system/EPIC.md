# Epic: Shop System

> **Layer**: Feature
> **GDD**: design/gdd/shop-system.md (Designed r2 — 1087 lignes, 16 R-SHP + 55 ACs + 41 EC-SHP + 12 OQ)
> **Architecture Module**: ShopSystem (architecture.md §4.3 Feature Layer — scène transitoire `res://scenes/shop/shop.tscn`, pas autoload, R-SHP-1)
> **Status**: Ready
> **Stories**: 16 stories created 2026-04-27 via `/create-stories shop-system` — voir table §Stories ci-dessous
> **✅ Sprint 1 prereq satisfait** : ADR-0010 promu `Accepted` 2026-04-27 — stories 003/005/010/011/015 débloquées pour `/dev-story`.

## Overview

Le Shop System est la scène transitoire d'achat entre étages : un Control fullscreen
chargé par GameStateManager (`request_scene_transition` ADR-0007 D-5) au signal
`etage_completed` du Level System. Architecturalement c'est un **node-local
ShopControllerScript** dans `shop.tscn` (zéro autoload, R-SHP-1) — l'antithèse
des autres Feature systems (Credit/Upgrade/Save autoloads). Il expose un catalogue
MVP de **2 upgrades binaires permanentes** (`double_jump` 20 cr index `n=0`,
`dash_horizontal` 40 cr index `n=1` via courbe linéaire F-CRD-3 amendée r2 0-based)
et exécute le cycle d'achat en 6 étapes déterministes (R-SHP-6) :
`try_spend(amount: int) → bool` (Credit Economy SYNC atomique R-CRD-4 LOCKED) →
`save_string_array("owned_upgrades", _owned_upgrades)` (Save/Load ConfigFile SYNC
ADR-0010) → `apply_upgrade(id: StringName) → void` (Upgrade System SYNC idempotent
R-UPG-4 LOCKED). Pas d'état SHOPPING dans GSM (R-SHP-5 — shop reste PLAYING-state
agnostic). Pas de grinding (R-SHP-13 — re-stock interdit MVP). Persistance immédiate
post-achat (R-SHP-8 — résistance crash, pas de batch close-shop). Le shop ferme
le segment économique du core loop : sans lui, les crédits accumulés par Credit
Economy n'ont pas de sortie, Pillar 2 (LA PROGRESSION SE VOIT) reste promesse.
Scope MVP : 2 upgrades, 2 étages playable (1 shop par étage = 2 visites possibles
F-CRD-4 yield_max 85 cr cumul cohérent F-SHP-3), persistance binaire owned/not_owned,
zéro SFX (Audio bus shop différé Tier 2+ OQ-SHP-4 RESOLVED), zéro animation/tween
durée significative (Chrome Zen sobre, Anti-fantasy F2P fanfare).

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0007: Game State Manager | `request_scene_transition` orchestre entrée/sortie shop ; PLAYING-state agnostic (pas d'état SHOPPING) ; ordre autoload stable | LOW |
| ADR-0010: Save/Load Serialization Format | ConfigFile + `save_string_array("owned_upgrades", Array[StringName])` + `load_string_array(key, default)` SYNC main-thread-only ; type-safe verbs | MEDIUM (Godot 4.4 store_* breaking change abstrait par ConfigFile) |
| ADR-0004: Input API & Focus Handling | Input.is_action_just_pressed("ui_cancel") via InputManager pour R-SHP-11 ESC = Continuer | LOW |

**Pas d'ADR Shop-spécifique** — le shop est une scène UI Control orchestrée par
contrats ADR upstream/downstream. Aucune décision architecturale propre nécessaire
au MVP (pas de pooling, pas de threading, pas de signal outbound, pas de
persistance custom). Si Tier 2+ ouvre re-stock, autoload `RunContext`, ou
multi-shop par étage → ADR Shop-spécifique requis (cf. OQ-SHP-5/11/12).

**Highest engine risk** : MEDIUM (ADR-0010 ConfigFile cross-version stability —
abstraction maintient store_* breaking change Godot 4.4 transparent côté Shop).

## GDD Requirements

Le shop-system r2 expose **16 règles R-SHP** dans `design/gdd/shop-system.md
§Detailed Rules`. Le tr-registry n'a actuellement aucune entrée TR-SHP-* — les
stories référenceront les R-SHP directement (mode équivalent à Movement/Camera
qui utilisent Rules de leur GDD). La création d'entrées TR-SHP dans le registry
sera traitée à `/architecture-review` post-implémentation Sprint 1.

| R-SHP | Requirement (résumé) | Locked Contract | ADR Coverage |
|-------|---------------------|-----------------|--------------|
| R-SHP-1 | Architecture : scène transitoire `shop.tscn`, pas d'autoload | — | ADR-0007 ✅ (scene transitions) |
| R-SHP-2 | Hiérarchie de nœuds `shop.tscn` (Control fullscreen + VBoxContainer + boutons) | — | GDD-owned (UI Godot stdlib) |
| R-SHP-3 | Catalogue hardcodé `const _CATALOG_MVP` avec constantes externes (StringName ids) | Upgrade.apply_upgrade(StringName) | GDD-owned |
| R-SHP-4 | État interne `_owned_upgrades: Array[StringName]` source de vérité locale | SaveLoad.save_string_array | ADR-0010 ✅ |
| R-SHP-5 | GSM PLAYING + scène shop active (pas d'état SHOPPING dédié) | GSM.state == PLAYING | ADR-0007 ✅ |
| R-SHP-6 | Cycle d'achat 6 étapes déterministes (try_spend → save → apply → owned → render → no flash) | Credit.try_spend SYNC atomique + Save SYNC + Upgrade.apply_upgrade SYNC idempotent | ADR-0010 ✅ |
| R-SHP-7 | Idempotence double-click + re-entry (guard `_owned_upgrades.has(id)`) | — | GDD-owned |
| R-SHP-8 | Persistance immédiate post-apply (pas de batch close-shop) | SaveLoad SYNC main-thread | ADR-0010 ✅ |
| R-SHP-9 | Affordability display via signal `Credit.credits_changed` CONNECT_DEFERRED OBLIGATOIRE + VERROUILLÉ | — | GDD-owned (Credit signal contract) |
| R-SHP-10 | Bouton "Continuer" : transition GSM via `request_scene_transition` vers MENU (MVP) | GSM.request_scene_transition | ADR-0007 ✅ |
| R-SHP-11 | ESC = Continuer direct (Pillar 1 anti-friction, EC-SHP-41 risque assumé) | InputManager.was_pressed_this_tick("ui_cancel") | ADR-0004 ✅ |
| R-SHP-12 | OWNED rendu visuel différencié (label "ACHETÉ" + désaturation, pas grayout total) | — | GDD-owned (UI Chrome Zen palette) |
| R-SHP-13 | No grinding : pas de re-stock, pas d'achat multiple, pas de re-roll MVP | — | GDD-owned |
| R-SHP-14 | `N_UPGRADES_MVP = 2` constante Shop-interne ; coûts `[20, 40]` dérivés F-CRD-3 r2 0-based | F-CRD-3 0-based locked | GDD-owned (cross-GDD invariant) |
| R-SHP-15 | Déclenchement via signal Level `etage_completed` + GSM scene transition | Level.etage_completed → GSM.request_scene_transition | ADR-0007 ✅ (partiel — Level ADR Feature à créer) |
| R-SHP-16 | ProcessMode `PROCESS_MODE_ALWAYS` + tween pause-mode (UI réactive même paused) | — | GDD-owned (Godot stdlib) |

**Coverage** : 8/16 R-SHP couverts par ADR (50% — surface architecturale minimale
attendue pour un système UI orchestré). 8/16 GDD-owned (UI rendering, idempotence
guards, tuning constants — pas de décision architecturale propre).

## Untraced Requirements (warnings)

⚠️ **Aucune entrée TR-SHP-* dans `tr-registry.yaml`** — pas un blocker MVP. Les
R-SHP serviront de stable IDs jusqu'à `/architecture-review` post-Sprint 1 qui
créera les TR-SHP-001..016 et synchronisera la coverage.

⚠️ **R-SHP-15 partiel** : `Level.etage_completed` signal n'a pas d'ADR Level
Feature dédié (architecture.md §3 row Level = "to create"). Mitigation MVP :
contract verbal stable Level r1 (Designed) ; ADR Level Feature à créer post-MVP
si signal API évolue.

✅ **OQ-SHP-2 RESOLVED** par Upgrade r1 R-UPG-4 (`apply_upgrade(id: StringName) → void`
SYNC idempotent confirmé, contrat verrouillé).
✅ **OQ-SHP-3 RESOLVED** par Save/Load r1 + ADR-0010 (`save_string_array`/`load_string_array`
SYNC main-thread atomique-best-effort, contrat verrouillé).
✅ **OQ-SHP-4 RESOLVED** MVP zéro SFX (Tier 2+ open).
✅ **OQ-SHP-5 RESOLVED** autoload `RunContext` Tier 2+ pattern (MVP `request_scene_transition` vers MENU).

⏸️ **OQ-SHP-2 (Upgrade contrat impl)** : seul OQ chain-blocked restant, attend
implémentation Sprint 1 UpgradeSystem autoload. Workflow PENDING-ACTIVATION
documenté AC-SHP-48 (mocks Sprint 1 → re-test impl réelle Sprint 2).

## Definition of Done

L'epic est complet quand :
- Toutes les stories sont implémentées, reviewed, closed via `/story-done`
- Tous les 55 ACs de `design/gdd/shop-system.md` sont vérifiés (33 BLOCKING + 22 ADVISORY)
- Toutes les Logic stories ont tests passants dans `tests/unit/shop/`
- Toutes les Integration stories ont tests passants dans `tests/integration/shop/`
- Toutes les UI stories ont evidence docs avec sign-off dans `production/qa/evidence/shop/`
- Lint statique anti-pattern `tween_duration_significant_in_shop` passe (R-SHP-16)
- Lint statique anti-pattern `audiostreamplayer_in_shop_scene` passe (Visual/Audio §V.4)
- Bidirectional contracts validés : Credit `try_spend` SYNC + SaveLoad `save_string_array` SYNC + Upgrade `apply_upgrade` SYNC idempotent (Groupe J ACs)
- Playtest manuel ≥ 2 sessions internes (AC-SHP-50/51/52) — boucle Pillar 2 jouable end-to-end : étage1 → shop → achat → étage2 → capacité effective

## Stories

| # | Story | Type | Status | ADR | Cluster |
|---|-------|------|--------|-----|---------|
| 001 | [Scene skeleton `shop.tscn`](story-001-scene-skeleton.md) | UI | Ready | ADR-0007 | C1 |
| 002 | [ShopController + Catalogue Constants](story-002-controller-catalogue-boot.md) | Logic | Ready | ADR-0007 | C1 |
| 003 | [Boot Hydrate `_owned_upgrades` from SaveLoad](story-003-boot-hydrate-owned-upgrades.md) | Integration | Ready | ADR-0010 | C1 |
| 004 | [Boot Pull Credit Display](story-004-boot-pull-credit-display.md) | Integration | Ready | ADR-0007 | C1 |
| 005 | [Purchase Cycle 6 Étapes Déterministes](story-005-purchase-cycle-ordered.md) | Logic | Ready ⚠️ AC-48 PROVISIONAL OQ-SHP-2 | ADR-0010 + ADR-0007 | C2 |
| 006 | [Idempotence Guards (Double-Click + Re-Entry)](story-006-idempotence-guards.md) | Logic | Ready | ADR-0007 | C2 |
| 007 | [`credits_changed` CONNECT_DEFERRED + Affordability Recalc](story-007-credits-changed-deferred-affordability.md) | Integration | Ready | ADR-0007 + ADR-0005 | C3 |
| 008 | [Continue Button + Initial Focus + GSM Transition](story-008-continue-button-initial-focus.md) | Logic | Ready | ADR-0007 | C4 |
| 009 | [ESC = Continue (anti-friction Pillar 1)](story-009-esc-equals-continue.md) | Logic | Ready | ADR-0004 | C4 |
| 010 | [SaveLoad Write SYNC + Corruption Handling](story-010-saveload-write-sync-corruption.md) | Logic | Ready | ADR-0010 | C5 |
| 011 | [SaveLoad Failure Buffer Retry (EC-SHP-9 Option C)](story-011-saveload-buffer-retry-option-c.md) | Logic | Ready | ADR-0010 | C5 |
| 012 | [Card Visual States + Chrome Zen Palette](story-012-card-states-chrome-zen-palette.md) | UI | Ready | ADR-0007 | C6 |
| 013 | [Animations Tween (Counter / Pulse / Shake) + Reduce Motion Hook](story-013-animations-tween-pulse-shake.md) | Visual/Feel | Ready | ADR-0007 | C6 |
| 014 | [Anti-Patterns Lint Static](story-014-anti-patterns-lint-static.md) | Logic | Ready | ADR-0004 + control-manifest | C7 |
| 015 | [Bidirectional Integration Tests](story-015-bidirectional-integration-tests.md) | Integration | Ready ⚠️ AC-48 PROVISIONAL | ADR-0007 + ADR-0010 + ADR-0005 | C8 |
| 016 | [Performance Benchmarks](story-016-performance-benchmarks.md) | Logic | Ready | ADR-0003 | C8 |

**Distribution** : 8 Logic + 4 Integration + 2 UI + 1 Visual/Feel + 1 Lint = 16 stories
**Coverage** : 16 R-SHP couverts (100%) ; 55 ACs distribués (33 BLOCKING + 22 ADVISORY) ; 41 EC-SHP couverts.

### Workflow PENDING-ACTIVATION (chain-blocked OQ-SHP-2)

- **AC-SHP-48** (Stories 005, 015) : `UpgradeSystem.apply_upgrade(id) -> void` SYNC idempotent — Sprint 1 mock dans `tests/unit/shop/mocks/mock_upgrade_system.gd` ; Sprint 2 activation = re-test contre impl UpgradeSystem r1 réelle. Stories 005 + 015 marquées `Done-Provisional` jusqu'alors.
- ~~**ADR-0010 Proposed**~~ ✅ **RÉSOLU 2026-04-27** — ADR-0010 promu `Accepted` ; les 5 stories Save/Load-dépendantes (003, 005, 010, 011, 015) sont débloquées formellement pour `/dev-story`.

### Cluster mapping (référence design)

- **C1 — Scene skeleton & boot** : Stories 001/002/003/004
- **C2 — Cycle d'achat** : Stories 005/006
- **C3 — Affordability dynamic** : Story 007
- **C4 — Continuer & ESC** : Stories 008/009
- **C5 — Persistance** : Stories 010/011
- **C6 — Visual/UI Chrome Zen** : Stories 012/013
- **C7 — Anti-patterns lint** : Story 014
- **C8 — Bidirectional integration** : Stories 015/016

## Sprint 0 / Sprint 1 prereqs

- **Sprint 0** : aucun (Shop est Sprint 1+ — dépend Credit + Save/Load + Upgrade Sprint 1)
- **Sprint 1 prereqs** :
  - CreditEconomy autoload impl (R-CRD-4 `try_spend(int) → bool` SYNC)
  - SaveLoadSystem autoload impl (ADR-0010 `save_string_array`/`load_string_array` SYNC)
  - UpgradeSystem autoload impl (R-UPG-4 `apply_upgrade(StringName) → void` SYNC idempotent)
  - GameStateManager autoload impl (ADR-0007 `request_scene_transition`)
  - Level System émet `etage_completed` signal (Level r1 contract)
- **Sprint 2 activation** : remplace mocks par impl réelle ; re-run AC-SHP-48/49 BLOCKING

## Next Step

Run `/create-stories shop-system` pour décomposer l'epic en stories implémentables
(estimation : ~14-18 stories selon clustering C1..C8 ci-dessus + workflow
PENDING-ACTIVATION pour C2/C5).
