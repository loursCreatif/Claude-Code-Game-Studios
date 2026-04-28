# Story 005: NOTIFICATION_WM_CLOSE_REQUEST handler + _flush_pending no-op MVP

> **Epic**: Save/Load System
> **Status**: Complete
> **Layer**: Foundation / Persistence
> **Type**: Integration
> **Manifest Version**: 2026-04-23
> **Estimate**: ~1h — t-shirt XS
> **Risk**: LOW

## Context

**GDD**: `design/gdd/save-load-system.md` r1
**Requirement**: R-SAV-9 (`_notification(NOTIFICATION_WM_CLOSE_REQUEST)` handler + `_flush_pending()` no-op MVP)

**ADR Governing Implementation**: ADR-0010 — Accepted 2026-04-27
**ADR Decision Summary**: D-8 SaveLoadSystem implémente `_notification(what)` qui intercepte `NOTIFICATION_WM_CLOSE_REQUEST` (alt-F4, fermeture fenêtre, signal OS). Le handler appelle `_flush_pending()` qui est **no-op au MVP** grâce au write-through synchrone exhaustif (R-SAV-5) — aucune save dirty ne peut exister entre deux frames. Le hook existe pour absorber Tier 2+ async batch sans casser l'API.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**:
- `NOTIFICATION_WM_CLOSE_REQUEST` constante stable Godot 4.x. Reçue avant `SceneTree.quit()` lors de alt-F4 / window close / OS signal. Garanti livré dans la frame de quit.
- `_notification(what: int)` méthode héritée Node Godot.
- `process_mode = ALWAYS` (story-001) garantit que `_notification` est délivré même si `get_tree().paused == true`.
- Test integration : appel direct `save_load.notification(NOTIFICATION_WM_CLOSE_REQUEST)` simule sans passer par OS.

**Control Manifest Rules (Foundation Persistence)**:
- **Required**: handler intercept WM_CLOSE_REQUEST + `_flush_pending()` méthode privée (no-op MVP).
- **Forbidden**: appel à `get_tree().quit()` depuis `_flush_pending()` — Save/Load ne contrôle pas le lifecycle de la fenêtre, seulement la persistence pré-quit.
- **Guardrail**: `_flush_pending()` doit être idempotent + safe-to-call-from-quit-frame (aucune nouvelle allocation, aucun signal émis).

---

## Acceptance Criteria

*From GDD `design/gdd/save-load-system.md`, scoped to this story:*

- [x] **AC-SAV-21** [Integration] [BLOCKING] : GIVEN session in-progress (SaveLoadSystem ready, file présent post-saves Credit/Shop), WHEN simulation `NOTIFICATION_WM_CLOSE_REQUEST` envoyée via `save_load.notification(NOTIFICATION_WM_CLOSE_REQUEST)`, THEN handler exécuté sans crash, save state consistent (write-through suffit — `_flush_pending()` no-op MVP confirmé).

---

## Implementation Notes

*Derived from ADR-0010 D-8 + R-SAV-9:*

1. **Override `_notification(what: int)`** :
   ```gdscript
   func _notification(what: int) -> void:
       if what == NOTIFICATION_WM_CLOSE_REQUEST:
           _flush_pending()
   ```

2. **`_flush_pending()` no-op MVP** :
   ```gdscript
   func _flush_pending() -> void:
       _assert_main_thread()
       # MVP : no-op — write-through synchrone (R-SAV-5) garantit aucune save dirty
       # Tier 2+ : si async batch introduit, flush la queue dirty ici via _config.save(SAVE_FILE_PATH)
       pass
   ```

3. **NE PAS** émettre de signal `quit_save_completed` ou similaire (R-SAV-10).

4. **NE PAS** déclencher `get_tree().quit()` — Menu System ou autre orchestrateur fait ça (R-SAV-11 zero orchestration).

5. **Cohérence Menu System** : story-007 menu-system délègue `save-on-quit` AC-MNU-57 — Menu intercepte aussi `NOTIFICATION_WM_CLOSE_REQUEST` et appelle ses propres flushes (Credit, Shop, etc.) AVANT `get_tree().quit()`. SaveLoad story-005 livre juste son propre hook. Pas de coordination cross-system requise au MVP.

---

## Out of Scope

- **Tier 2+ async batch** : si un futur ADR introduit batch + thread pool worker async write, `_flush_pending()` deviendra non-trivial. OQ-SAV-3 déféré.
- **AC-SAV-25** integration test 2-session : couvert par integration test cross-system côté Menu/Credit (pas Save/Load) — Save/Load story-005 livre juste le hook unique.
- **Atomic write** OQ-SAV-4 : déféré Tier 2+, pas de logique additionnelle dans `_flush_pending` MVP.

---

## QA Test Cases

**AC-SAV-21** — handler WM_CLOSE_REQUEST safe :
- Given : SaveLoadSystem ready (`_config_loaded == true`), `save_int("total_credits", 42)` appelé préalablement (file content stable)
- When : `save_load.notification(NOTIFICATION_WM_CLOSE_REQUEST)` appelé directement (simule alt-F4)
- Then : aucun crash, aucun push_error inattendu, `FileAccess.get_file_as_string(SAVE_FILE_PATH)` reste cohérent (contient `total_credits=42`)
- Edge cases :
  - WM_CLOSE_REQUEST envoyé pendant `_config_loaded == false` (cas pathologique boot interrompu) — handler ne doit pas crash, juste no-op.
  - WM_CLOSE_REQUEST envoyé deux fois consécutivement (double signal OS rare) — idempotent, pas d'erreur.
  - WM_CLOSE_REQUEST envoyé sous `get_tree().paused == true` — process_mode ALWAYS garantit livraison du `_notification`.

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/save_load/wm_close_request_test.gd` — must exist and pass (1 test AC-SAV-21 avec edge cases inclus)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: **story-001** (skeleton autoload obligatoire), **story-002** (save_int pour setup test "session in-progress")
- Unlocks: menu-system story-007 (Menu peut compter sur le hook SaveLoad pour dériver `save-on-quit` AC-MNU-57)

---

## Completion Notes

**Completed**: 2026-04-28
**Criteria**: 1/1 passing (AC-SAV-21 + 3 edge cases inclus dans la suite)
**Verdict**: COMPLETE

**Tests run** :
- `tests/integration/save_load/wm_close_request_test.gd` 4/4 PASSED 36 ms (AC-SAV-21 + edge cases boot interrompu / double signal / paused tree)
- Suite save_load globale : 17/17 unit + 7/7 integration = **24/24 vert** 476 ms total. Zéro régression sur stories 001-004.

**Files modified (2)** :
- `src/core/save_load_system.gd` 196 → 219 L (+23 L) :
  - `_notification(what: int)` override intercepte `NOTIFICATION_WM_CLOSE_REQUEST` (R-SAV-9)
  - `_flush_pending()` private no-op MVP (write-through synchrone R-SAV-5 garantit zéro dirty)
  - Hook `_check_save_version_compatibility()` ajouté dans `_ready()` post err == OK (corrige état antérieur — appel manquant dans la version persistée du fichier malgré la closure story-004)
- `tests/integration/save_load/wm_close_request_test.gd` NEW 122 L : 4 tests pattern hermétique GdUnit4 identique autoload_skeleton_test.gd.

**Deviations** :
- Aucune. Implémentation 1:1 spec ADR-0010 D-8.
- Note (informative) : un appel `_check_save_version_compatibility()` dans `_ready()` était spécifié par story-004 mais absent du fichier persisté (probablement perdu lors d'un refactor). Restauré incidemment lors de l'edit story-005 — tests story-004 restent verts (AC-SAV-15 future-version warning capture validée par retour load_int == 42, comportement inchangé).

**Code Review** : Skipped (Solo mode — feedback_no_confirmation_apply_directly + production/review-mode.txt = solo)
**Tech Debt Logged** : 0 items

**Unblocks aval** :
- **menu-system story-007** AC-MNU-57 `save-on-quit` — Menu peut désormais déléguer au hook SaveLoad sans coordination cross-system
- **save-load story-006** Tier 2+ stubs (`save_int_array` + meta `get_save_version`) — base shutdown lifecycle solide
- **save-load story-008** perf gate — `_flush_pending` no-op MVP confirmé, pas de coût additionnel à mesurer
