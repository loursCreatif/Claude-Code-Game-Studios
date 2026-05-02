# Technical Debt Register

> Registre des dettes techniques identifiées en cours de développement.
> Chaque entrée note l'origine (story, code review, ADR), la sévérité (BLOCKING / ADVISORY / TRIVIAL),
> le coût estimé de remboursement, et le déclencheur de re-priorisation.
>
> Mise à jour : alimentée par `/story-done`, `/code-review`, `/architecture-review`, `/tech-debt`.

## Format

| ID | Date | Origine | Sévérité | Coût | Description | Action |
|----|------|---------|----------|------|-------------|--------|

---

## TD-001 — ADR-0007 VC-6 : amender pour 3 writes `get_tree().paused` — RESOLVED 2026-05-02

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 → **Resolved 2026-05-02** |
| **Origine** | `/story-done` story-001 menu-system |
| **Sévérité** | ADVISORY |
| **Coût** | XS (1-2h) — amendement texte ADR + bump VC-6 lint expected count à 3 |
| **Fichier** | `docs/architecture/adr-0007-game-state-manager.md` (VC-6 ligne 436) |

**Description** : VC-6 stipulait "exactement 2 matches attendus pour `get_tree().paused =`" dans `game_state_manager.gd`. Implémentation contient **3 writes légitimes** :
- Ligne 70 : `get_tree().paused = true` (request_pause)
- Ligne 78 : `get_tree().paused = false` (request_resume)
- Ligne 87 : `get_tree().paused = false` (request_scene_transition — libère pause flag avant Pause→MainMenu, anti-flicker)

Le 3e write est une nécessité fonctionnelle non anticipée par la rédaction initiale de l'ADR. Autorité unique D-4 respectée (tous les writes restent dans GSM).

**Action appliquée 2026-05-02** : VC-6 amendée — expected count 2 → 3, 3e write documenté avec contexte `request_scene_transition` anti-flicker, trigger d'authority drift escalation explicité (4e write = escalation).

**Trigger re-prio** : aucun — résolu. Si un 4e write apparaît, escalader BLOCKING (signal d'authority drift).

---

## TD-002 — main_menu_controller.gd : version_label.visible redondant — RESOLVED 2026-05-02

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 → **Resolved 2026-05-02** |
| **Origine** | `/code-review` story-001 menu-system |
| **Sévérité** | TRIVIAL (cosmétique) |
| **Coût** | XS (5 min) |
| **Fichier** | `src/gameplay/menu/main_menu_controller.gd` ligne 63 |

**Description** : `version_label.visible = DEBUG_SHOW_VERSION` au runtime alors que `main_menu.tscn` ligne 59 fige déjà `visible = false`. Comportement identique, ligne supprimable.

**Action appliquée 2026-05-02** : commentaire explicatif ajouté pour audit trail (option B du tech debt). Ligne conservée car DEBUG_SHOW_VERSION constant peut servir de gate runtime si futur debug build.

**Trigger re-prio** : aucun — résolu.

---

## TD-003 — GSM `_ready` : ajouter assert R-3 mitigation autoload order — RESOLVED 2026-05-02

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-04-28 → **Resolved 2026-05-02** |
| **Origine** | `/code-review` story-001 menu-system |
| **Sévérité** | ADVISORY |
| **Coût** | XS (5 min) — 1 ligne |
| **Fichier** | `src/core/game_state_manager.gd` ligne 49 |

**Description** : ADR-0007 R-3 ligne 384 mitigation : `assert InputManager != null` en début de GSM `_ready` pour crash explicite si `project.godot` autoload réordonné par erreur. Story-001 n'imposait pas ce guard, mais c'est une mitigation explicite de l'ADR.

**Action appliquée 2026-05-02** : assert ajouté en première ligne `_ready()` avec message explicite sur l'ordre autoload attendu (InputManager → GSM → SaveLoad → Audio → UpgradeSystem D-1).

**Trigger re-prio** : aucun — résolu.

---

## TD-004 — CameraSystem `_update_tilt_wall_run` : polling `_player.wall_normal` viole ADR-0002 A-1

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-02 |
| **Origine** | `/code-review` story-011 camera-system (godot-gdscript-specialist RC-1) |
| **Sévérité** | ADVISORY (architectural violation, mais pré-existant story-005, fonctionnellement correct) |
| **Coût** | M (4-6h) — refactor handlers + tests update + lint VC-7 unmute |
| **Fichier** | `src/gameplay/camera/camera_system.gd` lignes 349-372 (`_update_tilt_wall_run`) + tests stories 005/010 |

**Description** : ADR-0002 Amendment A-1 (2026-04-23) impose consommation signal-driven exclusive de Movement state. `_update_tilt_wall_run` lit `_player.get("wall_normal")` chaque frame dans `_process` — pattern explicitement interdit par VC-7 (CI grep `player.wall_normal` en `_process` = fail). Code introduit story-005 avant Amendment A-1, n'a pas été migré lors de la mise à jour Amendment.

**Manque** :
- Variables d'état : `var _is_wall_running: bool` + `var _wall_side_cached: int`
- Handlers : `_on_wall_run_entered(wall_normal: Vector3)` + `_on_wall_run_exited()`
- Connexions `_ready()` : `_player.wall_run_entered.connect(_on_wall_run_entered)` + `_player.wall_run_exited.connect(_on_wall_run_exited)`
- Disconnects `_exit_tree()` symétriques
- `_update_tilt_wall_run` : remplacer lecture polling par `var wall_side: int = _wall_side_cached`

**Action** :
1. Implémenter cache signal-driven (pattern parity `_is_dashing`)
2. Mettre à jour tests stories 005/010 pour émettre `wall_run_entered` au lieu d'assigner `_mock_player.wall_normal`
3. Activer lint VC-7 ADR-0002 (grep `player.wall_normal` en `_process`)

**Trigger re-prio** : escalader BLOCKING si nouvelle story camera ajoute autre code dépendant du polling, ou si CI VC-7 lint est activé.

---

## TD-005 — Camera test harness fragility stories 005-007 : %CameraEffects/%Camera3D ne résolvent pas

| Champ | Valeur |
|-------|--------|
| **Date** | 2026-05-02 |
| **Origine** | `/code-review` story-011 camera-system (full suite run) |
| **Sévérité** | ADVISORY (13 failures en suite, 0 quand stories tournées en isolation logique) |
| **Coût** | M (3-5h) — adopter pattern story-008 dans tests stories 005, 006, 007 |
| **Fichier** | `tests/integration/camera/story_005_*.gd`, `story_006_*.gd`, `story_007_*.gd` |

**Description** : Stories 005-007 test setup utilise `set_unique_name_in_owner(true)` mais sans scene owner, le lookup `%CameraEffects` / `%Camera3D` dans `@onready` échoue silencieusement → `_camera_effects` reste null dans CameraSystem. Tests crash en `SCRIPT ERROR: Invalid access to property 'rotation' on null instance` quand `_process` ou `_update_tilt_wall_run` s'exécute. Stories 008-011 ont migré vers injection manuelle (`_camera_system._camera_effects = _camera_effects` après `add_child`) qui contourne le problème. Story-011 `_safeguard_rotation` ajoute du bruit SCRIPT ERROR sans changer le pass/fail outcome (la cause root est l'absence d'injection).

**Manque** : Pattern parity story-008/009/011 dans setup stories 005-007 :
```gdscript
_camera_system._camera_effects = _camera_effects
_camera_system._camera3d = _camera3d
_camera_system._player = _mock_player
if _camera_system._overlay == null:
    _camera_system._setup_overlay()
```

**Action** :
1. Migrer `before_test()` stories 005-007 pour injection manuelle post-`add_child`
2. Vérifier `tests/integration/camera/` 53/53 PASSED en suite complète
3. Optionnel : factoriser le setup dans un helper `CameraTestHarness` partagé

**Trigger re-prio** : escalader BLOCKING avant `/team-qa` épic camera (les 13 failures contaminent le rapport sign-off).

---
