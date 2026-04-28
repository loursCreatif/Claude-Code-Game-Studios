# Story 005: Run-purge GSM (request_new_run + checkpoint defensive)

> **Epic**: Credit Economy System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/credit-economy-system.md`
**Requirement**: R-CRD-6 (idempotence kill via `_credited_this_run` purgé sur `request_new_run()` ou `level_active` suivant ; **PAS** purgé sur checkpoint intra-étage), EC-CRD-7 (checkpoint restore — Enemy ne re-émet pas `enemy_killed`, set non purgé garde-fou défensif), EC-CRD-16 (runs back-to-back — purge set, conserve `total_credits`).
*(TR-crd-* IDs non encore présents dans `tr-registry.yaml` — référence directe rules/EC GDD r3.)*

**ADR Governing Implementation**:
- ADR-0007: Game State Manager — verbe public `request_new_run()` (D-10) consommé par Credit pour purger `_credited_this_run` ; `total_credits` reste inchangé (la persistance Pillar 2 survit aux runs).

**ADR Decision Summary**: Le verbe `GameStateManager.request_new_run()` est le trigger canonique de purge du set d'idempotence kill — il signale une nouvelle run logique (pas une nouvelle session). Le compteur `_total_credits` est préservé (Pillar 2 — la progression survit aux runs). Comportement explicite r2 B-6 : un checkpoint intra-étage **ne purge PAS** le set ; les `instance_id` morts pré-checkpoint restent enregistrés en garde défensive si Combat re-tuait un ennemi déjà comptabilisé.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: aucun API post-cutoff. ADR-0007 D-10 verbe public `request_new_run()` est une fonction normale (pas de signal — le pattern est : Credit observe le **side-effect** de `request_new_run()` via le second `level_active` qui suit, OU connecte directement si GSM expose un signal `new_run_requested`). Vérifier l'API exacte exposée par GSM autoload : si pas de signal dédié, pattern recommandé est de poll via verbe public OU se connecter à `state_changed` cycle complet.

> **NOTE D'IMPLÉMENTATION** : la GDD r3 mentionne « `_on_request_new_run()` (handler local du verbe public GSM) » — ceci suppose que GSM émet un signal observable. Si ADR-0007 D-10 ne définit qu'un verbe public sans signal associé, cette story doit ajouter un signal `new_run_requested()` côté GSM (à coordonner avec gameplay-programmer GSM owner) OU utiliser le second `level_active` comme proxy de purge (déjà couvert par AC-CRD-49 d/e en story 002). Vérifier `docs/architecture/adr-0007-game-state-manager.md` D-10 pendant `/story-readiness`.

**Control Manifest Rules (Feature layer)**:
- Required: purge `_credited_this_run.clear()` sur trigger canonique uniquement ; `_total_credits` JAMAIS muté par le handler purge.
- Forbidden: appeler `_credited_this_run.clear()` depuis `_on_state_changed(RESPAWNING)` ou `_on_state_changed(PLAYING)` (NB-CRD-4 r3 — triggers non-canoniques) ; purger sur checkpoint Tier 2+ (B-6 — décision explicite NE PAS purger).
- Guardrail: opération O(1) par défaut (Dictionary.clear()) — jamais un loop de O(N) pour purger.

---

## Acceptance Criteria

*From GDD §Acceptance Criteria, scoped à cette story (run-purge GSM + checkpoint defensive Tier 2+) :*

- [x] AC-CRD-10 [Logic] (r3 NB-CRD-4) — set `_credited_this_run` peuplé (N entries), GSM émet `request_new_run()`, Credit traite `_on_request_new_run()` : (a) `_credited_this_run.size() == 0`, (b) `_total_credits` inchangé.
- [x] AC-CRD-50 [Integration] (r2 B-6) — Checkpoint Tier 2+ active `_restore_from_snapshot(was_dead=true)` côté Enemy : (a) `_credited_this_run.size()` reste à N (set non purgé), (b) `_total_credits` inchangé, (c) 0 emit `credits_changed` capturé pendant le restore, (d) si Combat re-émet `enemy_killed` pour un ID déjà présent, signal ignoré silencieusement (chained AC-CRD-09).

---

## Implementation Notes

*Derived from ADR-0007 D-10 + GDD Rule 6 + EC-CRD-7/16 :*

1. **Vérification ADR-0007 D-10 préalable** :
   - **Si GSM expose un signal `new_run_requested()`** :
     ```gdscript
     func _ready() -> void:
         var gsm := get_node("/root/GameStateManager")
         gsm.new_run_requested.connect(_on_request_new_run)
         # ... autres connections
     ```
   - **Si GSM expose seulement le verbe public `request_new_run()` sans signal** : coordonner avec gameplay-programmer GSM owner pour ajouter un signal observable. Pattern proposé :
     ```gdscript
     # Côté GameStateManager :
     signal new_run_requested()
     func request_new_run() -> void:
         # ... logique GSM
         new_run_requested.emit()
     ```
   - **Solution dégradée** (si GSM amendment refusé) : observer le pattern `state_changed(MENU) → state_changed(PLAYING)` avec un flag pour distinguer "boot session" vs "new run request" — mais c'est plus fragile, préférer le signal dédié.

2. **Handler `_on_request_new_run()`** :
   ```gdscript
   func _on_request_new_run() -> void:
       _credited_this_run.clear()  # AC-CRD-10 a — O(1) Godot Dictionary.clear()
       # AC-CRD-10 b — _total_credits NE DOIT PAS être touché.
       # Aucun signal credits_changed émis (purge interne, pas un événement crédit).
   ```

3. **AC-CRD-50 checkpoint defensive (Tier 2+)** : aucun handler Credit explicite pour le checkpoint — Credit ne s'abonne PAS au signal Checkpoint System. Le test simule simplement :
   - Set Credit dans état pre-checkpoint (peuplé `_credited_this_run`, `_total_credits` connu).
   - Enemy mock émet son signal de restore (PAS `enemy_killed`).
   - Vérifier que Credit n'a rien fait (set + compteur stables).
   - Test défensif : émettre `enemy_killed` pour un `instance_id` déjà présent → ignoré (réutilise idempotence story 002 AC-CRD-09).

4. **Pas de signal sortant** : la purge est un événement interne — aucun `credits_changed` émis (le compteur ne change pas, donc pas de notification UI requise).

5. **Coordination cross-epic** : si AC-CRD-10 dépend d'un amendment GSM (signal `new_run_requested`), créer une follow-up sub-task sur l'epic GSM ou ajouter un blocker explicite à `/story-readiness`. **Mode solo** : faire l'amendment GSM dans la même session si nécessaire (autorisé par CLAUDE.md collaboration protocol).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 002 : purge `_credited_this_run` sur `level_active` suivant (AC-CRD-49 d/e — second trigger canonique distinct du `request_new_run()`).
- Story 003/004 : guards `_is_hydrated` et `state == PLAYING`.
- L'implémentation Checkpoint System Tier 2+ — cette story 005 ne fait que tester le **comportement défensif** Credit face à un mock Checkpoint signal restore (pas le système checkpoint lui-même).

---

## QA Test Cases

- **AC-CRD-10** :
  - **Phase a** : Given `_credited_this_run = {1001: true, 1002: true, 1003: true}` (3 entries), `_total_credits = 12`, When mock GSM émet `new_run_requested` (ou Credit appelle `_on_request_new_run()` direct), Then `_credited_this_run.size() == 0`.
  - **Phase b** : Given Phase a, Then `_total_credits == 12` (inchangé). Mécanisme : capturer compteur avant/après, assert égalité.
  - Edge case : `_on_request_new_run()` appelé sur set déjà vide → no-op, pas de crash.

- **AC-CRD-50** :
  - **Phase a** : Given `_credited_this_run = {2001: true, 2002: true}` (2 entries pre-checkpoint), `_total_credits = T`, When Enemy mock émet `restored_from_snapshot` ou équivalent (signal qui ne soit PAS `enemy_killed`), Then `_credited_this_run.size() == 2` (préservé).
  - **Phase b** : Given Phase a, Then `_total_credits == T` (inchangé).
  - **Phase c** : Given Phase a + spy `credits_changed` actif, Then 0 emit capturé pendant la séquence restore.
  - **Phase d** (test défensif chained AC-CRD-09) : Given Phase c, When mock Combat émet `enemy_killed(enemy_2001, ...)` pour un ID déjà présent, Then signal ignoré silencieusement, `_total_credits == T` toujours, spy 0 emit.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/credit/credit_economy_run_purge_test.gd` (AC-10, 50) — must exist and pass GUT.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **Story 001** (state vars `_credited_this_run`), **Story 002** (handler `_on_enemy_killed` avec idempotence — AC-CRD-50 Phase d réutilise le code), **Story 004** (guards `_is_hydrated`, `state == PLAYING` — pour que les tests soient en état "hydrated PLAYING" cohérent). **POSSIBLE BLOCKER** : si GSM ADR-0007 D-10 n'expose pas de signal `new_run_requested`, requérir amendment GSM (coordonner avec gameplay-programmer en `/story-readiness`).
- Unlocks: aucune autre story Credit (cette story finalise la machine d'état run-purge).

---

## Completion Notes

**Completed**: 2026-04-28
**Criteria**: 2/2 passing (AC-CRD-10 + AC-CRD-50)
**Verdict**: COMPLETE

**Tests run** : `tests/integration/credit/credit_economy_run_purge_test.gd` 5/5 PASSED 82 ms (AC-CRD-10 phases a/b + AC-CRD-50 phases a/b/c/d).

**Files modified (2)** — livrés par session voisine durant batch parallèle 2026-04-28 :
- `src/core/credit_economy.gd` : ajout signal `new_run_requested` côté GSM (`game_state_manager.gd:32`) + handler `_on_request_new_run()` côté Credit (`credit_economy.gd:299`) + connexion direct dans `_ready()` (autoload idx 2 GSM avant idx 22 Credit).
- `tests/integration/credit/credit_economy_run_purge_test.gd` NEW — 5 tests pattern hermétique (AC-CRD-10 trigger purge + AC-CRD-50 checkpoint defensive 4 phases).

**Convergence parallèle** : closure faite par cette session après convergence — implementation et tests pré-existants (commits voisins). Re-run validation 5/5 vert + suite credit globale 59/59 vert.

**Deviations** :
- **Possible blocker résolu** : ADR-0007 a été amendé pour exposer signal `new_run_requested()` (vu dans `game_state_manager.gd:32`) — pas de pattern proxy `level_active` nécessaire, signal direct utilisé.

**Code Review** : Skipped (Solo mode)
**Tech Debt Logged** : 0 items

**Unblocks aval** :
- **Credit Economy epic progress** : **7/8 stories Complete** (001 skeleton + 002 KILL + 003 SECRET + 004 Persistence + 005 Run-purge + 006 Perf + 007 Lints). Reste **008 Visual/Feel HUD frame-perfect** (manual evidence type Visual/Feel — pas de tests automatisés).
