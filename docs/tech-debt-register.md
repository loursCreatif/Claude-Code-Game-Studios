# Technical Debt Register

> Registre des dettes techniques identifiées en cours de développement.
> Chaque entrée note l'origine (story, code review, ADR), la sévérité (BLOCKING / ADVISORY / TRIVIAL),
> le coût estimé de remboursement, et le déclencheur de re-priorisation.
>
> Mise à jour : alimentée par `/story-done`, `/code-review`, `/architecture-review`, `/tech-debt`.
>
> **Dernière mise à jour** : 2026-05-11 — refresh post story-014 cleanup + scan complet src/ + cross-ref sprint Pre-Production.

## Format

| ID | Date | Origine | Sévérité | Coût | Description | Action |
|----|------|---------|----------|------|-------------|--------|

---

## Entrées actives

---

### TD-006 — vfx_system.gd : 5 TODOs story-002 (blood shader + cone + flash_mult) — OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-11 |
| **Origine** | scan src/ (grep TODO) |
| **Sévérité** | ADVISORY |
| **Priorité** | P2 polish |
| **Coût** | S (2-4h par item, 3 items) |
| **Fichiers** | `src/core/vfx_system.gd` lignes 298, 303, 304, 666, 747 |
| **Sprint suggéré** | Sprint 1 Production (VFX story-002 scope) |

**Description** :
- L298-304 : `_setup_blood_pool()` — shader `blood_particle.gdshader` non chargé, couleur flat fallback, `BLOOD_COLOR` + `opacity` shader parameters absents.
- L666 : `_spawn_blood_spurt()` — `effective_cone_deg` calculé mais non appliqué sur `ParticleProcessMaterial.spread`.
- L747 : `_flash_mult` continu (pullé story-005) non consommé dans `_physics_process` flash loop.

Comportement visible : pas de shader blood flat unshaded Chrome Zen, cone de particules fixe ignoring la formule, flash mult continu inutilisé.

**Trigger re-prio** : story-008 VFX playtest panel Martin — si les testeurs notent l'absence de shader blood, passer P1 avant playtest.

---

### TD-007 — shop_controller.gd : TODO Sprint 2 — constantes CreditEconomy hardcodées — OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-11 |
| **Origine** | scan src/ (grep TODO) |
| **Sévérité** | ADVISORY |
| **Priorité** | P2 polish |
| **Coût** | XS (30 min) |
| **Fichier** | `src/ui/shop/shop_controller.gd` ligne 23 |
| **Sprint suggéré** | Sprint 2 (avant shop launch playtest) |

**Description** : Fallback hardcodé `BASE_UPGRADE_COST` au lieu de référencer `CreditEconomy.BASE_UPGRADE_COST`. Risque de divergence si la constante est tuned en production sans que le shop reflète la valeur.

**Trigger re-prio** : tout ajustement de `BASE_UPGRADE_COST` dans `credit_economy.gd` rend ce TODO P1 (valeur désynchronisée visible en playtest).

---

### TD-008 — audio_system.gd + camera_system.gd + movement_controller.gd : fichiers > 300 lignes — OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-11 |
| **Origine** | scan wc -l src/ (CLAUDE.md : files under 300 lines) |
| **Sévérité** | ADVISORY |
| **Priorité** | P3 nice-to-have |
| **Coût** | M–L (4-12h par fichier) |
| **Fichiers** | `audio_system.gd` (1149 l.) · `camera_system.gd` (990 l.) · `movement_controller.gd` (917 l.) · `level_system.gd` (893 l.) · `combat_system.gd` (864 l.) · `vfx_system.gd` (777 l.) · `input_manager.gd` (658 l.) · `shop_controller.gd` (401 l.) · `credit_economy.gd` (349 l.) |
| **Sprint suggéré** | Production (opportuniste, à ne pas bloquer livraison) |

**Description** : 9 fichiers dépassent le seuil 300 lignes (standard CLAUDE.md). Les systèmes Core/Foundation sont par nature denses (autoloads monolithiques par conception ADR). Le split n'est pas nécessairement applicable sans un ADR de refactoring (ex. AudioSystem : ADR-0009 impose un autoload unique). Évaluer au cas par cas.

**Note** : Les 4 plus gros (`audio_system`, `camera_system`, `movement_controller`, `level_system`) ont tous des ADRs ratifiés justifiant leur structure. Le split n'est envisageable qu'en extrayant des helper modules stateless (ex. formules, sous-états).

**Trigger re-prio** : si la complexité cyclomatique dépasse 10 dans une méthode identifiée en code review, passer P2 et créer une story dédiée.

---

### TD-009 — level_frame_time_runner.gd : accès membres privés LevelSystem — OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-11 |
| **Origine** | scan tests/ (grep TECH-DEBT) |
| **Sévérité** | ADVISORY |
| **Priorité** | P3 nice-to-have |
| **Coût** | S (2-4h) |
| **Fichier** | `tests/performance/level_frame_time_runner.gd` ligne 331 |
| **Sprint suggéré** | Sprint 1 Production (si AC-LVL-42 story-023 scope le permet) |

**Description** : Le runner de performance accède à `_state` et `_connect_room_triggers` (membres privés de `LevelSystem`) directement — encapsulation breach documentée. Corriger en exposant une API test-only (`inject_state_for_test` à la manière de `inject_pressed_for_test` InputManager) ou en passant par le signal `room_entered`.

**Trigger re-prio** : si `LevelSystem` est refactorisé et que les membres privés sont renommés/supprimés, ce test casse silencieusement (pas de type checking GDScript sur accès dynamique).

---

### TD-010 — Tests cross-suite pollution (4 suites) — DEFER OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-09 → DEFER |
| **Origine** | Story W-4 diagnostic (`production/tech-debt/story-w4-test-infra-autoload-reset-between-suites.md`) |
| **Sévérité** | ADVISORY |
| **Priorité** | P2 important |
| **Coût** | S (3-5h) — base class + 4 opt-in suites |
| **Fichiers** | `tests/helpers/` (à créer) + 4 suites : `main_menu_boot_test.gd` · `no_alloc_play_2d_test.gd` · `story_009_respawn_fade_flash_test.gd` · `test_movement_signals_typed_contract.gd` |
| **Sprint suggéré** | Sprint 1 Production (post-régressions per-epic résolues) |

**Description** : 4 / 1117 tests échouent en sweep complet mais passent en isolation — vraies pollutions cross-suite (0.36 % volume). Cause : `GSM._current_state`, `AudioSystem` pool, `VFX._flash_active`, signal refcount non restaurés entre suites. Plan : `AutoloadResetTestSuite` base class avec snapshot/restore dans `before_test/after_test`.

**ACs** : voir `production/tech-debt/story-w4-test-infra-autoload-reset-between-suites.md`.

**Trigger re-prio** : si les régressions per-epic sont toutes résolues et que les 4 pollutions persistent, passer P1 bloquant smoke run complet.

---

### TD-011 — Combat story-019 panel Martin : playtest humain ≥5 testeurs × 3 sessions — OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-05 |
| **Origine** | Sprint Pre-Production — `production/epics/combat-system/EPIC.md` |
| **Sévérité** | ADVISORY |
| **Priorité** | P1 important |
| **Coût** | XS effort code (0) — livraison dépend recrutement testeurs |
| **Fichier** | `production/qa/protocols/combat-feel-interview.md` |
| **Sprint suggéré** | Sprint 1 Production immédiat — bloque story-019 Close |

**Description** : Story-019 est `Ready` — le protocole playtest est publié. Aucune implementation requise. Blocker = recrutement panel ≥5 testeurs × 3 sessions Martin. Close story-019 après 3 sessions avec ≥5 testeurs.

**Trigger re-prio** : déjà P1 — à compléter avant Production gate final.

---

### TD-012 — HUD story-006 + VFX story-008 : playtest manuel Visual/Feel ADVISORY — OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-09 |
| **Origine** | Sprint Pre-Production — HUD EPIC.md + VFX EPIC.md |
| **Sévérité** | ADVISORY |
| **Priorité** | P1 important |
| **Coût** | XS effort code — livraison dépend playtest humain Martin |
| **Fichiers** | `production/epics/hud-system/story-006-*.md` · `production/epics/vfx-system/story-008-*.md` |
| **Sprint suggéré** | Sprint 1 Production — dé-bloque VFX epic close + HUD epic close |

**Description** : 2 stories BLOCKED sur validation playtest manuel Visual/Feel (ADVISORY gate). HUD story-006 : feel pulse/counter HUD sign-off. VFX story-008 : screen-flash + court-sec désaturé sign-off ≥5 testeurs. Ces stories sont épiques close-out — leur résolution marque `7/8 → 8/8` VFX et `5/6 → 6/6` HUD.

**Trigger re-prio** : déjà P1 — dé-bloque audit Pre-Production → Production gate.

---

### TD-013 — Tier 1 hardware sign-off DEFERRED (draw_calls + 60 fps baseline) — OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-04 |
| **Origine** | W-1+W-2 smoke-2026-05-04 warnings |
| **Sévérité** | ADVISORY |
| **Priorité** | P2 important |
| **Coût** | XS (1-2h sur hardware réel) |
| **Fichier** | `production/qa/smoke-2026-05-04.md` |
| **Sprint suggéré** | Sprint 1 Production dès qu'un Tier 1 disponible (i3-10100F + GTX 1050) |

**Description** : Draw calls < 500 / frame et target 60 fps non validés sur hardware Tier 1 minimum (Apple M4 ≠ Tier 1 cible). Gates W-1+W-2 auto-SKIP en headless CI.

**Trigger re-prio** : passe P0 si playtest Vertical Slice révèle < 60 fps sur hardware Tier 1 avant release.

---

### TD-014 — Vertical Slice playtest humain — OPEN (bloque gate Pre-Production → Production)

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-05 |
| **Origine** | Sprint Pre-Production `sprint-pre-production-2026-05-05.md` ligne 102-107 |
| **Sévérité** | BLOCKING |
| **Priorité** | P0 blocker |
| **Coût** | XS effort code (0) — 30 min Martin |
| **Fichier** | `production/qa/playtests/feel-playtest-session-1-2026-04-27.md` (TEMPLATE) |
| **Sprint suggéré** | Immédiat — bloque gate |

**Description** : `feel-playtest-session-1-2026-04-27.md` reste TEMPLATE — zéro session humaine documentée. C'est le bloquer principal Pre-Production → Production. Martin doit lancer le jeu 30 min (boot → core loop end-to-end), remplir le template, et signaler les critical fun blockers avant de relancer `/gate-check pre-production-to-production`.

**Trigger re-prio** : déjà P0 — gate bloqué.

---

### TD-015 — Credit story-008 BLOCKED upstream HUD — OPEN

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-05 |
| **Origine** | Sprint Pre-Production — credit-economy EPIC.md |
| **Sévérité** | ADVISORY |
| **Priorité** | P2 important |
| **Coût** | XS — HUD epic livré (unblocked 2026-05-04), à vérifier |
| **Fichier** | `production/epics/credit-economy-system/EPIC.md` |
| **Sprint suggéré** | Sprint 1 Production immédiat — HUD epic livré = débloqué |

**Description** : story-008 crédit était bloquée upstream HUD epic. Index.md indique HUD epic livré (`unblocked 2026-05-04`). Vérifier si story-008 peut passer `Ready → In Progress` maintenant.

**Trigger re-prio** : si story-008 n'est pas encore démarrée Sprint 1, P1.

---

## Résolu récemment

---

### TD-001 — ADR-0007 VC-6 : amender pour 3 writes `get_tree().paused` — RESOLVED 2026-05-02

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 → **Resolved 2026-05-02** |
| **Origine** | `/story-done` story-001 menu-system |
| **Sévérité** | ADVISORY |
| **Coût** | XS (1-2h) |
| **Fichier** | `docs/architecture/adr-0007-game-state-manager.md` (VC-6 ligne 436) |

**Action appliquée 2026-05-02** : VC-6 amendée — expected count 2 → 3, 3e write documenté avec contexte `request_scene_transition` anti-flicker, trigger d'authority drift escalation explicité (4e write = escalation).

---

### TD-002 — main_menu_controller.gd : version_label.visible redondant — RESOLVED 2026-05-02

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 → **Resolved 2026-05-02** |
| **Origine** | `/code-review` story-001 menu-system |
| **Sévérité** | TRIVIAL |
| **Coût** | XS (5 min) |
| **Fichier** | `src/gameplay/menu/main_menu_controller.gd` ligne 63 |

**Action appliquée 2026-05-02** : commentaire explicatif ajouté — ligne conservée car `DEBUG_SHOW_VERSION` peut servir de gate runtime future build debug.

---

### TD-003 — GSM `_ready` : assert R-3 mitigation autoload order — RESOLVED 2026-05-02

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 → **Resolved 2026-05-02** |
| **Origine** | `/code-review` story-001 menu-system |
| **Sévérité** | ADVISORY |
| **Coût** | XS (5 min) |
| **Fichier** | `src/core/game_state_manager.gd` ligne 49 |

**Action appliquée 2026-05-02** : assert `InputManager != null` ajouté en première ligne `_ready()` avec message explicite sur l'ordre autoload attendu.

---

### TD-004 — CameraSystem `_update_tilt_wall_run` : polling `_player.wall_normal` viole ADR-0002 A-1 — RESOLVED 2026-05-02

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-02 → **Resolved 2026-05-02** |
| **Origine** | `/code-review` story-011 camera-system |
| **Sévérité** | ADVISORY (architectural violation pré-existante) |
| **Coût** | M (4-6h) |
| **Fichier** | `src/gameplay/camera/camera_system.gd` + tests stories 005/010/011 |

**Action appliquée 2026-05-02** : signal-driven cache `_is_wall_running/_wall_side_cached` implémenté, polling remplacé, tests migrés. ADR-0002 A-1 respecté. Lint VC-7 activable en CI.

---

### TD-005 — Camera test harness fragility stories 005-007 — RESOLVED 2026-05-02

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-02 → **Resolved 2026-05-02** |
| **Origine** | `/code-review` story-011 camera-system (suite run) |
| **Sévérité** | ADVISORY |
| **Coût** | M (3-5h) |
| **Fichiers** | `tests/integration/camera/story_005_*.gd` · `story_006_*.gd` · `story_007_*.gd` |

**Action appliquée 2026-05-02** : injection manuelle `_camera_effects/_camera3d/_player` dans `before_test()` des stories 005/006/007 — pattern parity story-008/009/011. Résultat : 66/67 tests PASSED (1 pré-existant hors scope).

---

### TD-016 — Story-014 cleanup : doc-comment TR-lvl-010 + story-023 CCD validation — RESOLVED 2026-04-27 (story-014 branche courante)

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-27 → **Resolved 2026-04-27** |
| **Origine** | Story-014 completion notes + `production/tech-debt/story-014-cleanup-plan.md` |
| **Sévérité** | ADVISORY |
| **Coût** | XS |
| **Fichiers** | `tools/lint/level_lint.gd:609` · `production/epics/level-system/story-023-*.md` |

**Action appliquée 2026-04-27** : doc-comment "TR-lvl-011" → "TR-lvl-010" corrigé. Story-023 `tr-lvl-039-automated-gate` créée (Status: Ready, 4 ACs CCD première run empirique). Wall-run global_transform + CCD runner Node3D/.tscn déjà résolus en r2 fix-pass.

---

## Résolu 2026-05-09 (sprint test cleanup)

| Item | Description | Fichiers clés | Résolution |
|------|-------------|---------------|------------|
| Movement canonical fails (4→0) | Jolt headless `is_on_floor()` flaky, physics_interpolation_mode=2 renumérotée 4.6 | `movement_controller.gd` · tests unit/integration/movement | commits `5c10ad8` + pending → **50/50 PASS** |
| Camera 10 fails (story_001-003) | Godot 4.6 élide keys project.godot + `MOUSE_MODE_CAPTURED` no-op headless | `camera_system.gd` · tests camera | commit `a5349c5` → **106/106 PASS** |
| Input cluster fails (7→0) | `parse_input_event` no-op headless + `physics_frame` ne pump pas `_physics_process` | `input_manager.gd` · tests unit/input | commits `47ca6e2` + pending → **24/24 PASS** |
| Lint drift 5 fails (extends GutTest) | `extends GutTest` → Parse Error GdUnit4, regex trop large | `tests/static/menu_main_menu_lint_test.gd` | commit `7d0f4e4` → **94/94 PASS** |
| Level 30 fails | 8 patterns : signaux obsolètes / is_push_error / find_children owned / lambda capture / Area3D flaky | `level_system.gd` · tests integration/level | commits `299052c` + pending → **88/88 PASS** |
| Lint authoring 5 fails | Marker3D base / substrings obsolètes / float32 boundary / find_children owned / API `validate_checkpoint_pairs` manquante | `tests/static/` | commit pending → **174/174 PASS** |

---

## Top 5 — Prochains remboursements recommandés

| Rang | ID | Description | Priorité | Effort | Raison |
|------|----|-------------|----------|--------|--------|
| 1 | TD-014 | Vertical Slice playtest 30 min Martin | P0 | 30 min | **Gate bloqué** Pre-Production → Production |
| 2 | TD-011 | Combat story-019 panel ≥5 testeurs | P1 | 0 code | Bloque story-019 Close, épique combat à 21/22 Complete |
| 3 | TD-012 | HUD-006 + VFX-008 playtest Visual/Feel | P1 | 0 code | Débloque 2 épiques close-out (HUD 5/6 → 6/6, VFX 7/8 → 8/8) |
| 4 | TD-010 | Cross-suite pollution 4 suites (AutoloadReset) | P2 | S (3-5h) | Smoke run global encore instable ; débloque CI sweep complet fiable |
| 5 | TD-006 | VFX blood shader + cone + flash_mult (5 TODOs) | P2 | S–M | Visible en playtest VFX story-008 ; à résoudre avant panel Martin |
