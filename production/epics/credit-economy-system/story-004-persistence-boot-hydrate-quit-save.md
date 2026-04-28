# Story 004: Persistence — boot hydrate + quit save (BLOCKED on SaveLoadSystem)

> **Epic**: Credit Economy System
> **Status**: **Blocked** — autoload `SaveLoadSystem` doit être registered dans `project.godot` AVANT `CreditEconomy` (ADR-0010 D-3 ordre #3). Le save-load epic doit être créé/implémenté préalablement OU au minimum le squelette autoload `SaveLoadSystem` avec API `load_int(key, default) -> int` + `save_int(key, value) -> void` doit exister. Tant que cet autoload n'est pas registered et le squelette API publié, **NE PAS commencer l'implémentation** de cette story (les handlers Save/Load référenceraient un singleton inexistant).
> **Layer**: Feature
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/credit-economy-system.md`
**Requirement**: R-CRD-11 (boot hydration `SaveLoad.load_int("total_credits", 0)` à premier `state_changed(PLAYING)`, guard `_is_hydrated`), R-CRD-12 (persist quit `SaveLoad.save_int("total_credits", value)` à `state_changed(MENU)`), R-CRD-10 (guard PAUSED — ignorer `enemy_killed` hors PLAYING), EC-CRD-8 (save absent/corrompu → 0 default), EC-CRD-11 (B-7 race boot — découplage hydration ↔ connexion ennemis).
*(TR-crd-* IDs non encore présents dans `tr-registry.yaml` — référence directe rules GDD r3.)*

**ADR Governing Implementation**:
- ADR-0010: Save/Load Persistence — API typée `SaveLoadSystem.load_int(key, default) -> int` + `save_int(key, value) -> void` (D-2), ordre autoload #3 (D-3), `process_mode = PROCESS_MODE_ALWAYS` (D-4), main thread only (D-7).
- ADR-0007: Game State Manager — signal `state_changed(new_state: State)` (D-3) consommé pour boot hydrate (PLAYING) + quit save (MENU) + guard PAUSED.

**ADR Decision Summary**: Au boot, Credit Economy hydrate `total_credits` UNE SEULE FOIS au premier `state_changed(PLAYING)` reçu (guard `_is_hydrated == false`) via `SaveLoadSystem.load_int("total_credits", 0)`. À chaque `state_changed(MENU)`, Credit persiste l'état courant via `SaveLoadSystem.save_int("total_credits", _total_credits)`. Les transitions PLAYING ultérieures (depuis PAUSED/MENU/RESPAWNING) sont no-op côté hydration. Save absent ou corrupt → default 0 sans crash. Race boot `level_active` AVANT `state_changed(PLAYING)` : connexions enemy établies, mais signaux `enemy_killed` reçus pré-hydration sont rejetés silencieusement.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: ADR-0010 ratifie ConfigFile (`user://savegame.cfg`). API verrouillée — toute déviation de signature (`load_int(key, default) -> int` strict) cassera l'integration. `state_changed` enum `State { MENU=0, PLAYING=1, PAUSED=2, RESPAWNING=3, BOSS_DEFEATED=4 }` (ADR-0007 D-2). Pas d'API post-cutoff Godot 4.6.

**Control Manifest Rules (Feature layer)**:
- Required: guard `_is_hydrated == false` AVANT `SaveLoad.load_int(...)` à chaque `state_changed(PLAYING)` reçu ; guard `GameStateManager.get_current_state() == State.PLAYING` AVANT crédit dans `_on_enemy_killed` (Rule 10) — implémenté dans cette story comme refactor du handler de la story 002 ; émission `credits_changed(loaded_value, 0, BOOT_HYDRATE)` exactement 1 fois après hydration.
- Forbidden: appeler `SaveLoad.save_int(...)` hors `state_changed(MENU)` (pas de auto-save à chaque kill — EC-CRD-14 décision MVP) ; appeler `SaveLoad.load_int(...)` plusieurs fois (les 2e/3e PLAYING sont no-op, AC-CRD-37/38).
- Guardrail: hydration < 2 ms (AC-CRD-40, gate Performance story 006) — lecture ConfigFile + assign + emit signal doit rester sous frame budget boot.

---

## Acceptance Criteria

*From GDD §Acceptance Criteria, scoped à cette story (persistence I/O + GSM observation + race boot) :*

- [ ] AC-CRD-22 [Logic] — `_total_credits = 42` au moment d'un respawn ; Enemy `_restore_from_snapshot(was_dead=true)` n'émet PAS `enemy_killed` ; `_total_credits` reste `42`.
- [ ] AC-CRD-23 [Integration] — `_total_credits == 42` + quit-to-menu → save écrit ; nouvelle session + boot hydrate → `_total_credits == 42`.
- [ ] AC-CRD-24 [Integration] — boot reçoit `state_changed(PLAYING)` → hydrate depuis savegame + `credits_changed(loaded_value, 0, BOOT_HYDRATE)` émis exactement 1 fois.
- [ ] AC-CRD-25 [Logic] — savegame absent ou corrompu → `_total_credits = 0`, `credits_changed(0, 0, BOOT_HYDRATE)` émis, pas de crash, `_is_hydrated == true`.
- [ ] AC-CRD-26 [Integration] — `_total_credits = 30` + 5 cr gagnés (35) + mort + respawn → `_total_credits == 35` (progression préservée).
- [ ] AC-CRD-27 [Logic] — round-trip save/load : valeur sauvegardée == valeur rechargée bit-pour-bit (int, no float trunc).
- [ ] AC-CRD-30 [Logic] — `credits_changed(_, 0, BOOT_HYDRATE)` → `delta == 0` toujours.
- [ ] AC-CRD-36 [Integration] — état PAUSED, signal `enemy_killed` émis (test défensif) → ignoré, `_total_credits` stable.
- [ ] AC-CRD-37 [Logic] — état MENU initial → `get_total()` retourne `0` ou loaded value, pas de reset intempestif à transition MENU→PLAYING.
- [ ] AC-CRD-38 [Logic] — séquence PLAYING → PAUSED → PLAYING → `_total_credits` identique avant/après pause.
- [ ] AC-CRD-51 [Integration] (r2 B-7 race boot) — séquence : `level_active` à T0, `state_changed(PLAYING)` à T1>T0 ; AVANT T1 : connexions établies + `_is_hydrated == false` + signaux `enemy_killed` rejetés silencieusement ; APRÈS T1 : `_is_hydrated = true`, BOOT_HYDRATE émis 1 fois, signaux ultérieurs traités.

---

## Implementation Notes

*Derived from ADR-0010 + ADR-0007 + GDD Rules 10/11/12 + EC-CRD-8/11 :*

1. **Connexion GSM dans `_ready()`** :
   ```gdscript
   func _ready() -> void:
       var gsm := get_node("/root/GameStateManager")
       gsm.state_changed.connect(_on_state_changed)
       # ... connexions story 002 (level_active) + story 003 (secret_collected)
   ```
2. **Handler `_on_state_changed`** (refactor en step ladder) :
   ```gdscript
   func _on_state_changed(new_state: int) -> void:
       # GSM.State enum values : MENU=0, PLAYING=1, PAUSED=2, RESPAWNING=3, BOSS_DEFEATED=4
       match new_state:
           GameStateManager.State.PLAYING:
               if not _is_hydrated:
                   _hydrate_from_save()
                   _is_hydrated = true
               # transitions PLAYING ultérieures = no-op (AC-CRD-37/38)
           GameStateManager.State.MENU:
               _persist_to_save()
           GameStateManager.State.PAUSED, GameStateManager.State.RESPAWNING, GameStateManager.State.BOSS_DEFEATED:
               pass  # no-op explicite — EC-CRD-13 reset/respawn ne touchent pas le compteur
   ```
3. **`_hydrate_from_save()`** :
   ```gdscript
   func _hydrate_from_save() -> void:
       _total_credits = SaveLoadSystem.load_int("total_credits", 0)  # default 0 si absent/corrupt
       # Pas de validation négative — SaveLoad.load_int garantit int valide ou default
       credits_changed.emit(_total_credits, 0, SourceKind.BOOT_HYDRATE)
   ```
4. **`_persist_to_save()`** :
   ```gdscript
   func _persist_to_save() -> void:
       SaveLoadSystem.save_int("total_credits", _total_credits)
       # Aucun signal émis (la persistance est un side-effect silencieux)
   ```
5. **Refactor handler `_on_enemy_killed` (depuis story 002)** : ajouter les guards en tête de fonction :
   ```gdscript
   func _on_enemy_killed(enemy: Node, position: Vector3) -> void:
       # Guard 1 : pré-hydration (Rule 11 + B-7)
       if not _is_hydrated:
           return  # signal rejeté silent — AC-CRD-51 c
       # Guard 2 : pause / non-PLAYING (Rule 10)
       var gsm := get_node("/root/GameStateManager")
       if gsm.get_current_state() != GameStateManager.State.PLAYING:
           return  # AC-CRD-36
       # ... reste du handler story 002 (idempotence, batching, etc.)
   ```
   Note : le même refactor doit être appliqué à `_on_secret_collected` (story 003) — guards identiques.
6. **AC-CRD-22/26 (respawn)** : aucune action côté Credit. Enemy ne ré-émet pas `enemy_killed` au restore (Enemy EC-ENM-11) — Credit n'a rien à faire. Test simulé : émettre `state_changed(RESPAWNING)`, vérifier `_total_credits` inchangé.
7. **AC-CRD-27 round-trip** : test isolé Save → reset Credit → Load → assertEqual. Mécanisme via SaveLoadSystem instance test (path temporaire `user://test_savegame.cfg`).
8. **AC-CRD-51 race boot** : ce test est l'integration test le plus complexe — il demande de :
   - mocker GSM avec contrôle temporel (push `state_changed(PLAYING)` manuellement à T1) ;
   - mocker LevelSystem qui émet `level_active` à T0 < T1 ;
   - mocker SaveLoadSystem qui retourne une valeur stable à `load_int("total_credits", 0)` (e.g. `7`) ;
   - mocker plusieurs Enemy nodes dans groupe `"enemies"` qui peuvent émettre `enemy_killed` à n'importe quel moment.
   Vérifier les 4 phases (a/b/c/d) du test plan dans QA Test Cases.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 001 (skeleton de l'autoload).
- Story 002 (Source KILL — handler `_on_enemy_killed` dans son state primitif). Cette story 004 **refactor** le handler en ajoutant les guards `_is_hydrated` et `state == PLAYING` — c'est attendu, pas un Out of Scope.
- Story 003 (Source SECRET — refactor symétrique guards à appliquer ici aussi).
- Story 005 (Run-purge `request_new_run`).
- Story 006 (Performance — benchmark hydrate < 2 ms est testé là, pas ici).

---

## QA Test Cases

- **AC-CRD-22** : Given `_total_credits = 42`, `_is_hydrated = true`, When émettre `state_changed(RESPAWNING)`, Then `_total_credits == 42`. Mécanisme : direct.
- **AC-CRD-23** : Given session A `_total_credits = 42`, When `state_changed(MENU)` → save écrit ; reset Credit instance ; new session ; `state_changed(PLAYING)` → hydrate, Then `_total_credits == 42`. Mécanisme : test intégration avec SaveLoadSystem réel + path temporaire.
- **AC-CRD-24** : Given session fresh, When `state_changed(PLAYING)` reçu pour la première fois, Then `_is_hydrated == true` ET spy capture exactement 1 appel `credits_changed(loaded, 0, BOOT_HYDRATE)`. Edge : 2e `state_changed(PLAYING)` (depuis PAUSED) → spy 0 appel additionnel.
- **AC-CRD-25** : Given SaveLoad mock retourne `0` (default sur absent), When `_hydrate_from_save()`, Then `_total_credits == 0`, `_is_hydrated == true`, spy 1 appel `(0, 0, BOOT_HYDRATE)`, no crash. Edge corrupted : SaveLoad retourne `0` (default fallback), même résultat.
- **AC-CRD-26** : Given `_total_credits = 30`, When 5 kills (`+5 → 35`) + `state_changed(RESPAWNING)` + `state_changed(PLAYING)`, Then `_total_credits == 35`. Mécanisme : test intégration séquencé.
- **AC-CRD-27** : Given `_total_credits = 9_999_999`, When `_persist_to_save()` puis `_hydrate_from_save()` (via reset Credit + reload), Then valeur identique bit-pour-bit. Edge : valeurs `0`, `1`, `MAX_INT_safe` (~9 quintillions Godot int 64-bit, pas testé jusqu'à overflow).
- **AC-CRD-30** : Given `_hydrate_from_save()` appelé, When spy capture le payload, Then `delta == 0` exactement (pas `+N` même si `loaded > 0`).
- **AC-CRD-36** : Given `state_changed(PAUSED)`, When manual emit `enemy_killed` (test défensif), Then `_total_credits` stable, spy 0 appel.
- **AC-CRD-37** : Given Credit fresh `_is_hydrated = false`, When `get_total()` interrogé en MENU, Then retourne `0` (initial). When `state_changed(PLAYING)` puis `get_total()`, Then retourne loaded value (pas reset).
- **AC-CRD-38** : Given `_total_credits = 17`, When séquence `state_changed(PLAYING) → PAUSED → PLAYING`, Then `_total_credits == 17` à chaque interrogation.
- **AC-CRD-51** :
  - **Phase a** : Given mock Level émet `level_active(1, ...)` à T0, When Credit traite, Then `enemy.enemy_killed.get_connections()` contient Credit pour chaque enemy du groupe.
  - **Phase b** : Given Phase a, When `_is_hydrated` interrogé, Then `false`.
  - **Phase c** : Given Phase b, When mock Enemy émet `enemy_killed`, Then `_total_credits` stable, spy `credits_changed` 0 appel.
  - **Phase d** : Given Phase c, When mock GSM émet `state_changed(PLAYING)` à T1, Then `_is_hydrated == true`, spy capture 1 appel `(loaded, 0, BOOT_HYDRATE)`.
  - **Phase e** : Given Phase d, When mock Enemy émet `enemy_killed` à T2 > T1, Then `_total_credits += 1`, spy capture 1 appel additionnel `(loaded+1, +1, KILL)`.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/credit/credit_economy_persistence_test.gd` (AC-22, 23, 24, 25, 26, 27, 30, 36, 37, 38) — must exist and pass GUT.
- `tests/integration/credit/credit_economy_race_boot_test.gd` (AC-51 — séquencement temporel strict 4 phases) — must exist and pass.

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **Story 001** (skeleton — `_is_hydrated`, signal, enum), **Story 002** (handler `_on_enemy_killed` à refactorer), **Story 003** (handler `_on_secret_collected` à refactorer pour guards). **HARD UPSTREAM** : autoload `SaveLoadSystem` registered dans `project.godot` (ordre #3, ADR-0010 D-3) AVEC API publiée `load_int(key: String, default: int) -> int` + `save_int(key: String, value: int) -> void` (ADR-0010 D-2).
- Unlocks: Story 005 (run-purge — peut référencer `_total_credits` persistant), Story 006 (perf benchmark hydrate boot).
