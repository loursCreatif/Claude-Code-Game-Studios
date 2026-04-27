# Input System

> **Status**: Designed — r5 revised — **NEEDS REVISION r6 (mineur, ACs)**
> **Author**: Martin + design-system skill (auto mode) + design-review r2 (7 specialists + creative-director synthesis) + application fixes post-ADR-0004 Accepted (2026-04-21) + fresh-session r6 independent review (2026-04-21, 4 specialists : gdscript / game-designer / qa-lead / systems-designer)
> **Last Updated**: 2026-04-21 (r5 application + r6 review verdict 🟡 NEEDS REVISION mineur — 3 BLOCKINGs ACs + 5 coverage gaps + 3 classification errors à appliquer ; structure/patterns/ADR-0004 D-1..D-9 🟢 PASS)
> **Last Verified**: 2026-04-21 (r6 fresh-session — structure PASS, ACs à affiner — log : `design/gdd/reviews/input-system-review-log.md`)
> **Implements Pillar**: Pillar 1 (FLOW AVANT TOUT) — primaire, critique. Toute autre pilière dépend implicitement d'un input sans latence.
> **Governing ADRs**: ADR-0001 (Physics Rate 60 Hz + Jolt) · ADR-0003 (Rendering & Display Latency) · **ADR-0004 (Input API & Focus Handling — canonique)**

## Summary

Le Input System est la couche d'entrée unique du jeu : il capture clavier, souris, (plus tard) manette, les traduit en **actions abstraites** nommées (`jump`, `dash`, `attack`...) et une **mouse motion** continue, puis expose cette couche aux consommateurs (Player Movement, Camera, Combat, Menu, HUD). Il est la *seule* source d'input du projet — aucun autre système ne lit directement `Input.*` de Godot. Cette indirection garantit la remappabilité future, le test headless, le pause/freeze global, et la mesure de latence. Cible : **latency intra-engine** (event reçu par le callback `_input` / `_unhandled_input` → signal émis) ≤ 16 ms p99 (1 tick physique @ 60 Hz, défaut Godot — cf. ADR à venir). La latence totale perçue par le joueur (OS polling + event loop + display) sera de l'ordre de 25–50 ms sur hardware standard — voir section Game Feel pour les trois budgets distincts.

> **Quick reference** — Layer: `Foundation` · Priority: `MVP` · Key deps: `Aucune (ce système est la base)` — consommé par: `Player Movement, Camera System, Player Combat, Menu, HUD`

## Overview

Le Input System est un service autoload (singleton Godot) qui orchestre trois responsabilités : (1) mapper les touches physiques en actions abstraites via `InputMap` de Godot, (2) publier des événements typés (signals Godot) à chaque press/release d'action et à chaque mouvement de souris, (3) gérer l'état global de capture de souris (gameplay = captured, menu = free) et l'état enabled/disabled (freeze pendant respawn ou pause). Il ne contient aucune logique de gameplay : aucune décision sur *quoi* faire d'un dash, juste sur *quand* le dash a été demandé. Le système est construit pour tourner à la cadence du moteur (`_input` + `_unhandled_input` pour les events côté callback, `_physics_process` 60 Hz pour le polling des consommateurs), et il expose une API de mesure de latence utilisée par le HUD debug. Toute la binding list vit dans un Godot `project.godot` (InputMap) + une `Resource` de settings (`input_settings.tres`) contenant sensibilité souris, inversion Y, et (post-MVP) overrides de remapping.

## Player Fantasy

Le joueur ne *pense* pas à l'input. Il appuie et le jeu est déjà là. Toute la promesse de Pillar 1 (FLOW) passe par ce système : si un seul tick est perdu ou ajouté, le jeu *glisse*, et tous les systèmes aval (Movement, Combat) héritent du défaut sans pouvoir le compenser.

Cible émotionnelle : **transparence absolue**. Le joueur ne doit jamais dire "j'ai cliqué mais ça n'a pas pris". Chaque input est une note staccato qui part immédiatement vers l'engine. L'Input System est infrastructure pure — sa fantaisie est celle d'un bus invisible.

Anti-référence : tout jeu où le menu lag, où la souris "saute" après la pause, où un bouton doit être tenu 50 ms pour être enregistré. Jamais ici.

> Cette section existe par complétude du template (système foundation, fantaisie indirecte). Le joueur ne *sent* pas l'Input System — il sent son absence quand il est cassé.

## Detailed Design

### Core Rules

1. **Singleton autoload**. Le Input System est un autoload Godot nommé `InputManager`, instancié une seule fois au lancement, accessible globalement via `InputManager.get_movement_vector()`, `InputManager.enabled`, etc. Tous les autres systèmes consomment via cet autoload — *jamais* via `Input.*` directement.

2. **Actions abstraites déclarées dans `InputMap`**. Toute touche physique est déclarée dans le projet Godot via l'onglet Project > Input Map. Les consommateurs ne réfèrent qu'aux noms d'actions abstraites. Si une touche change, aucun code aval ne bouge. Tous les noms d'action sont des `StringName` (`&"jump"`, `&"dash"`) — pas des `String`, pour éviter les allocations dans les hot paths.

3. **Actions MVP** :

   | Action (abstraite) | Default binding KB/M | Catégorie | Edge vs Hold |
   |---|---|---|---|
   | `move_left` | `A` | Gameplay | Hold (axis) |
   | `move_right` | `D` | Gameplay | Hold (axis) |
   | `move_forward` | `W` | Gameplay | Hold (axis) |
   | `move_back` | `S` | Gameplay | Hold (axis) |
   | `jump` | `Space` | Gameplay | Edge (just_pressed) |
   | `dash` | `Left Shift` | Gameplay | Edge (just_pressed) |
   | `attack` | `Mouse Left` | Gameplay | Edge (just_pressed) |
   | `restart` | `R` | Meta | Edge (just_pressed) — anti-misclick hold owned par Checkpoint, pas Input |
   | `ui_cancel` | `Escape` | UI | Edge (just_pressed) — ouvre/ferme pause menu |
   | `ui_confirm` | `Enter` / `Mouse Left` (menu state only) | UI | Edge |
   | `debug_toggle` | `F3` | Dev | Edge (build non-release uniquement) |

4. **Mouse look = événement, pas action**. La rotation caméra (mouvement de la souris sans clic) n'est pas une action — c'est un flux continu. Le Input System capte les `InputEventMouseMotion` dans `_unhandled_input` et les republie via un signal `mouse_motion(delta: Vector2)`. Les consommateurs (Camera System principal) connectent ce signal. Le delta est toujours en pixels (non multiplié par la sensibilité — la sensibilité est appliquée par le consommateur qui lit `InputManager.mouse_sensitivity`).

5. **Mouse capture state**. Le Input System possède le `Input.mouse_mode` global. Deux valeurs :
   - `MOUSE_MODE_CAPTURED` pendant le gameplay (souris cachée, deltas purs)
   - `MOUSE_MODE_VISIBLE` pendant menus / pause
   L'API `InputManager.set_mouse_captured(bool)` permet aux systèmes UI / Menu de basculer. Au démarrage : `MOUSE_MODE_VISIBLE` jusqu'à ce que le Game State Manager entre en état Playing.

6. **Input enabled / disabled — refcount multi-owner** (ADR-0004 D-4). Le Input System expose une propriété **READ-ONLY** `enabled: bool` dérivée d'un dictionnaire de blockers `_enable_blockers: Dictionary` (key = `owner.get_instance_id()`). `enabled == _enable_blockers.is_empty()`. Quand `enabled == false` :
   - `was_pressed_this_tick(action)` renvoie toujours `false` (cf. règle 7).
   - `get_movement_vector()` renvoie `Vector2.ZERO`.
   - Les signals typés par action (`jump_pressed`, `dash_pressed`, `attack_pressed`, `restart_pressed`) ne sont pas émis.
   - `mouse_motion` signal **n'est pas émis** (évite la rotation caméra pendant pause/respawn).
   - `ui_cancel_pressed` et `ui_confirm_pressed` restent émis (sinon impossible de unpause).
   - Les flags internes `_pressed_this_tick` et `_consumed_this_tick` sont vidés à la transition `enabled: true → false` (évite press mémorisée).

   **API refcount** (remplace `set_enabled(bool)`) :
   - `request_disable(owner: Node) -> void` — ajoute un blocker. Idempotent pour même owner. Auto-cleanup via `owner.tree_exited` (CONNECT_ONE_SHOT).
   - `release_enable_request(owner: Node) -> void` — retire le blocker. `push_warning` si owner n'avait pas de blocker actif.
   - `enabled` redevient `true` **seulement** quand tous les blockers sont relâchés.

   Utilisé par : Checkpoint & Respawn pendant RESPAWN_DELAY, Menu System pendant pause, futur Cutscene System (Tier 2). La séquence multi-owner (Menu+Checkpoint+Cutscene simultanés) est structurellement safe : un release isolé ne réactive pas l'input si d'autres owners sont encore disabled.

7. **API publique (canonique — ADR-0004)** :

   ```gdscript
   # ─── Polling gameplay — canal GAMEPLAY (appelées depuis _physics_process des consumers) ───
   # ADR-0004 D-1 : was_pressed_this_tick REMPLACE is_action_just_pressed (forbidden_pattern ADR-0001).
   # Renvoie false / ZERO si !enabled. Si `action` n'existe pas dans l'InputMap :
   # push_error en debug (OS.has_feature("debug")), retourne false silencieusement en release.
   InputManager.get_movement_vector() -> Vector2                        # WASD normalized, ZERO si !enabled
   InputManager.was_pressed_this_tick(action: StringName) -> bool       # edge-triggered, tick N parity (ADR-0004 D-3 swap pattern)
   InputManager.is_action_pressed(action: StringName) -> bool           # hold/level-triggered (reste legitime)

   # ─── Signals typés par action — canal UI / event-driven (règle 11, jamais utilisés par le gameplay) ───
   # Choix : signals typés par action (pas de signal générique) — compile-time safety, zero dispatch
   # côté consommateur, meilleur pour 9 actions figées au MVP. Si remapping dynamique post-MVP
   # nécessite un signal générique, ajouter en complément SANS retirer les typés.
   signal jump_pressed                                  # (sauf si !enabled)
   signal dash_pressed                                  # (sauf si !enabled)
   signal attack_pressed                                # (sauf si !enabled)
   signal restart_pressed                               # (sauf si !enabled)
   signal jump_released                                 # idem pour release — ajouter au besoin
   signal dash_released
   signal attack_released
   signal mouse_motion(delta: Vector2)                  # émis à chaque InputEventMouseMotion (si enabled, hors fenêtre 50 ms post-FOCUS_IN)
   signal ui_cancel_pressed                             # émis même quand enabled == false (sinon impossible de unpause)
   signal ui_confirm_pressed                            # émis même quand enabled == false (menu active)
   signal enabled_changed(is_enabled: bool)             # émis sur transition — pour HUD debug, pas gameplay
   signal mouse_captured_changed(is_captured: bool)     # émis sur transition — pour HUD debug

   # ─── Focus events — signals one-way consommés par GameStateManager (ADR-0004 D-5) ───
   # Input reste Foundation (aucune dépendance aval). Découplage Input ↔ GameStateManager.
   signal application_focus_lost()                      # émis dans _notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
   signal application_focus_gained()                    # émis dans _notification(NOTIFICATION_APPLICATION_FOCUS_IN)

   # ─── Enable gating refcount (ADR-0004 D-4, remplace set_enabled(bool)) ───
   InputManager.request_disable(owner: Node) -> void            # ajoute blocker ; idempotent pour même owner ;
                                                                 # auto-cleanup via owner.tree_exited (CONNECT_ONE_SHOT)
   InputManager.release_enable_request(owner: Node) -> void     # retire blocker ; push_warning si pas actif
   InputManager.enabled: bool                                   # READ-ONLY (getter dérivé : _enable_blockers.is_empty())

   # ─── Mouse state — setters encapsulés, vars publiques read-only ───
   InputManager.set_mouse_captured(captured: bool) -> void  # no-op si déjà au même mode (évite flutter macOS)
   InputManager.is_mouse_captured() -> bool             # read-through de Input.mouse_mode — pas de cache
   InputManager.set_mouse_sensitivity(value: float) -> void # clamp dans safe_range, persiste dans input_settings.tres
   InputManager.mouse_sensitivity: float                # READ-ONLY getter (safe range [0.0005, 0.012] rad/px)
   InputManager.set_mouse_y_inverted(value: bool) -> void
   InputManager.mouse_y_inverted: bool                  # READ-ONLY getter

   # ─── Debug / telemetry — READ-ONLY depuis l'extérieur ───
   InputManager.last_input_to_publish_latency_ms: float # READ-ONLY getter (rolling window p99, ring buffer PackedFloat32Array)
   InputManager.debug_overlay_enabled: bool             # toggled par F3 — le HUD ne doit pas écraser
   InputManager.set_debug_overlay_enabled(value: bool) -> void  # pour F3 handler uniquement

   # ─── Test fixtures — présentes en toute build, no-op en release (ADR-0004 D-9) ───
   # GDScript n'a PAS de préprocesseur #if — guard runtime via OS.has_feature("debug") + no-op release + assert.
   # Injection via Input.parse_input_event(InputEventAction.new(...)) — le seul qui trigger _unhandled_input
   # (Input.action_press ne le trigger PAS ; godot-specialist authoritative r4).
   InputManager.simulate_action_press(action: StringName) -> void    # no-op si !OS.has_feature("debug")
   InputManager.simulate_action_release(action: StringName) -> void
   InputManager.simulate_mouse_motion(delta: Vector2) -> void

   # ─── API SUPPRIMÉE (forbidden_patterns — ADR-0004) ───
   # InputManager.is_action_just_pressed(action) -> bool       # SUPPRIMÉE — utiliser was_pressed_this_tick
   # InputManager.is_action_just_released(action) -> bool      # SUPPRIMÉE — utiliser signaux *_released si besoin
   # InputManager.set_enabled(value: bool) -> void             # SUPPRIMÉE — utiliser request_disable / release_enable_request
   ```

   **Encapsulation stricte** : toutes les `var` exposées publiquement sont read-only (getter uniquement).
   Les mutations passent par setters. Backing vars (`_enabled`, `_mouse_sensitivity`, etc.) sont `private`
   (convention Godot : préfixe `_`). Un consommateur qui écrit `InputManager.enabled = false` directement
   ne compile pas (lint) ou ne fait rien à runtime. Cf. godot-gdscript-specialist standard.

   **Forbidden patterns (registry)** :
   - `is_action_just_pressed_direct_in_gameplay_physics_process` (ADR-0001) — étendu par ADR-0004 D-2 : `InputManager.is_action_just_pressed` n'existe plus.
   - `set_enabled_bool_global_without_refcount` (ADR-0004 D-4) — race multi-owner.
   - `preprocessor_if_debug_build_in_gdscript` (ADR-0004 D-9) — n'existe pas en GDScript.

8. **StringName discipline**. Toutes les actions sont référencées via `StringName` pré-alloués en constantes au sommet du script (`const ACTION_JUMP := &"jump"`, etc.). Raison d'être : les literals `&"..."` sont internés par le runtime GDScript (pas d'allocation heap répétée pour un literal donné), mais une conversion dynamique `String → StringName` (via variable `String`) alloue à chaque appel. Les constantes préviennent cette conversion dynamique et facilitent le refactoring. **Règle étendue aux consommateurs** : jamais de `was_pressed_this_tick(some_string_var)` — toujours literal `&"..."` ou constante.

9. **Pas de logique métier**. Le Input System ne sait pas ce qu'est un jump ou un dash ; il ne sait pas si le joueur peut dasher (c'est le rôle du Movement + Upgrade). Il publie *que l'action a été demandée*. Toute suppression/filtrage de input est faite côté consommateur. **Corollaire** : anti-misclick et hold-to-confirm (ex : le hold 0.5s sur `restart`) sont la responsabilité du consommateur qui interprète l'action, pas d'Input. Cf. Checkpoint & Respawn GDD pour le hold de `restart`.

10. **Settings persistence + ordre autoload**. `input_settings.tres` contient :
    - `mouse_sensitivity: float` (default 0.0022 rad/px)
    - `mouse_y_inverted: bool` (default false)
    - `focus_regain_window_ms: int` (default 50, clamp [20, 150] — cf. règle 13)
    - `remap_overrides: Dictionary` (post-MVP — vide au MVP)

    Le Save/Load System charge/sauvegarde cette ressource via son propre canal (settings vs gameplay save séparés). Le chargement au boot DOIT être synchrone (`ResourceLoader.load()`, pas `load_threaded_request`) dans `_ready()` de `InputManager`, et `InputManager` DOIT être déclaré **en premier** (`#1`) dans `[autoload]` de `project.godot` — règle intangible ADR-0001 + ADR-0004. Cet ordre garantit que `InputManager._physics_process` tourne avant tous les consumers (Movement, Combat, Camera, etc.), permettant au **swap `_pressed ↔ _consumed`** (règle 16) de publier l'edge tick N aux consumers du même tick. Un autoload ajouté avant InputManager casse le contrat et fait échouer AC-CS-1. Lint rule `.claude/rules/inputmanager-autoload-first.md` (à créer) + AC GUT `test_autoload_order_inputmanager_first` enforcent.

11. **Signal vs polling — contrat canonique** (anti-désynchro, ADR-0004 D-1). Les deux chemins peuvent diverger d'un tick physique (16.6 ms @ 60 Hz) si utilisés ensemble. Règle projet :
    - **Polling `was_pressed_this_tick(action)` + `is_action_pressed(action)` + `get_movement_vector()` depuis `_physics_process`** → gameplay uniquement : Player Movement, Player Combat, Checkpoint (pour `restart`), Camera (pour toggle éventuel).
    - **Signals `*_pressed` / `*_released` / `mouse_motion` / `ui_cancel_pressed` / `application_focus_lost/gained`** → UI / event-driven / state transitions uniquement : Menu, HUD, VFX, Audio, GameStateManager.
    - **Forbidden Pattern** : un même consommateur ne doit JAMAIS mixer signal + polling pour la même action. Si un système a besoin des deux sémantiques, choisir le polling. Ajouter cette règle au Control Manifest lors de sa création.
    - Les signals typés par action (`jump_pressed`, etc.) sont émis depuis `_unhandled_input` (cadence render, pas physics) — un consommateur de signal qui lit de la physique du frame courant peut lire un état du frame précédent. C'est une raison de plus pour ne pas utiliser les signals côté gameplay.
    - **Sémantique `was_pressed_this_tick`** : retourne `true` **une fois exactement** sur le tick physique qui suit la press, y compris si la press a eu lieu entre deux `_physics_process` (cadence render > physics). Zero perte d'edge.

12. **Callback routing** (pour que `ui_cancel` traverse les Controls focusés).
    - `ui_cancel` est traité dans **`_input(event)`** (priorité maximale, avant les Control nodes). Après émission de `ui_cancel_pressed`, appeler `get_viewport().set_input_as_handled()` pour empêcher la propagation aux widgets.
    - Toutes les autres actions + `mouse_motion` sont traitées dans **`_unhandled_input(event)`** (propagation normale, après Controls). Pas de `set_input_as_handled()` — les widgets UI gardent accès aux events qui ne sont pas `ui_cancel`.
    - Filtre `event.is_echo()` (auto-repeat clavier) avec type guard : `if event is InputEventKey and event.is_echo(): return` — `is_echo()` n'existe que sur `InputEventWithModifiers`.

13. **Focus loss / regain handling** (ADR-0004 D-5 + D-6). Au retour de focus (alt-tab Windows, switch macOS, Wayland Linux), le delta souris accumulé hors-fenêtre peut être massif et faire pivoter la caméra brutalement. **Sur Wayland** spécifiquement, le compositeur livre un **burst de 3–6 `InputEventMouseMotion` sur 2–3 frames** — un latch single-shot (`_skip_next_mouse_delta: bool`) laisse passer 5/6 events. Solution : fenêtre temporelle **absolute time** (pas frame count) qui absorbe tout event jusqu'à 50 ms post-FOCUS_IN. Aucun système aval appelé depuis `_notification` — découplage via signals (D-5).

    ```gdscript
    var _saved_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
    var _focus_regained_until_ticks_usec: int = 0
    const FOCUS_REGAIN_WINDOW_USEC: int = 50_000  # 50 ms, tunable [20_000, 150_000]

    signal application_focus_lost()
    signal application_focus_gained()

    func _notification(what: int) -> void:
        if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
            _saved_mouse_mode = Input.mouse_mode
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            _focus_regained_until_ticks_usec = 0
            application_focus_lost.emit()       # GameStateManager décide du pause (D-5)
        elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
            Input.mouse_mode = _saved_mouse_mode
            _focus_regained_until_ticks_usec = Time.get_ticks_usec() + FOCUS_REGAIN_WINDOW_USEC
            application_focus_gained.emit()

    func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventMouseMotion:
            if Time.get_ticks_usec() < _focus_regained_until_ticks_usec:
                return  # absorbe TOUT event jusqu'à 50 ms post-FOCUS_IN (Wayland burst-safe)
            # traitement normal : emit mouse_motion(event.relative)
    ```

    **Pourquoi absolute time et pas frame count** : à 60 Hz physics + 144 Hz render, un count de « N prochaines frames render » est ambigu (30 ms @ 144 Hz = 4.3 frames, 30 ms @ 60 physics = 1.8 tick). Absolute time est non-ambigu et indépendant du rafraîchissement.

    **Durée 50 ms** : compromis (Wayland burst observé 15–35 ms, macOS rare 2–5 ms, Windows ~0 ms ou 1 frame). Tunable dans `input_settings.tres` via clé `focus_regain_window_ms` (clamp 20–150 ms).

    **Validation requise pre-impl (ADR-0004 VC-1/2)** : 3 OS cibles (Windows 11, macOS Sonoma, Linux Ubuntu 24 Wayland+X11). Confirmer que `NOTIFICATION_APPLICATION_FOCUS_OUT/IN` se déclenchent bien sur alt-tab OS-level — la sémantique dual-focus 4.6 (mouse/touch ≠ keyboard/gamepad) ne doit PAS émettre ces notifications pour focus UI intra-fenêtre. Si warning log « NOTIFICATION obsolete », migrer vers `Window.focus_entered/exited`.

14. **Mouse motion delta : pas de clamp auto**. À flick extrême (p.ex. 20 000 px/s sur souris 1000 Hz), un seul `mouse_motion` peut livrer 300+ px, produisant une rotation caméra de ~95°/frame. Input publie le delta brut — le clamp éventuel (par exemple `max_delta_radians_per_frame = 0.5 rad`) est la responsabilité du Camera System quand il applique la sensibilité. Documenté ici pour éviter la surprise.

15. **Contract `mouse_motion` en MouseFree**. Le signal est émis normalement quand mouse est libre (utile pour hover tracking côté widgets). **Les consommateurs gameplay (Camera, Movement) DOIVENT vérifier `is_mouse_captured() == true` avant d'appliquer les deltas**, ou se déconnecter du signal quand gameplay inactif. Défaut à éviter : rotation caméra silencieuse pendant menu open.

16. **Flag consumption pattern — swap `_pressed ↔ _consumed` en début `_physics_process`** (ADR-0004 D-3). `was_pressed_this_tick(action)` lit un dictionnaire `_consumed_this_tick` distinct de `_pressed_this_tick` écrit par `_unhandled_input`. En **ligne 1** de `InputManager._physics_process`, les références Dictionary sont échangées (zero alloc — Dictionary = reference type en GDScript), puis le dict recyclé (l'ex-`_consumed`) est vidé à `false` pour le prochain tick. Les consumers (Movement, Combat, Checkpoint) tournent après InputManager dans le même tick N (règle 10 autoload #1) et lisent `_consumed_this_tick` via `was_pressed_this_tick`. **AC-CS-1 garantie** : press au frame N → consumer lit `true` au `_physics_process` du tick N (pas N+1).

    ```gdscript
    var _pressed_this_tick: Dictionary = {}    # écrit par _unhandled_input (cadence render)
    var _consumed_this_tick: Dictionary = {}   # lu par was_pressed_this_tick() (cadence physics)

    func _ready() -> void:
        for action in ACTIONS_MVP:
            _pressed_this_tick[action] = false
            _consumed_this_tick[action] = false

    func _physics_process(_delta: float) -> void:
        # Ligne 1 : snapshot avant que le tick ne consomme (zero alloc — refs)
        var temp: Dictionary = _consumed_this_tick
        _consumed_this_tick = _pressed_this_tick
        _pressed_this_tick = temp
        # Vider le dict recyclé pour le prochain tick
        for action in ACTIONS_MVP:
            _pressed_this_tick[action] = false
        # (reste du corps : mesure latency, etc.)

    func was_pressed_this_tick(action: StringName) -> bool:
        if not _enable_blockers.is_empty():
            return false
        return _consumed_this_tick.get(action, false)
    ```

    **Pourquoi SYNCHRONE début-de-corps et pas `call_deferred`/fin-de-corps** : `call_deferred` repousse à la fin du frame — si un consumer poll en son `_physics_process`, il lit après reset et obtient toujours `false` → AC-CS-1 échoue. Fin-de-corps d'InputManager pose le même problème (consumers tournent après InputManager, liraient `false` si reset était en fin). Le swap en début-de-corps est la seule position correcte.

    **Risque documenté (ADR-0004 Risk 2)** : si GDScript applique une copy-on-write subtile sur Dictionary swap (non documenté explicitement), le comportement diverge. Mitigation : test GUT `test_was_pressed_this_tick_swap_is_zero_alloc` avec `Performance.get_monitor(MEMORY_STATIC)` stable — si alloc détectée, replier sur 2× `PackedByteArray` parallèles indexés par hash(action).

### States and Transitions

Le Input System a peu d'états — c'est une couche réactive. Deux axes orthogonaux :

| State (enabled axis) | Entry Condition | Exit Condition | Behavior |
|---|---|---|---|
| **Enabled** | `enabled = true` (default) | Code externe set `enabled = false` | Tous signals émis, toutes queries renvoient vrai input |
| **Disabled** | Code externe set `enabled = false` (respawn, pause, cutscene future) | Code externe set `enabled = true` | Signals coupés (sauf `ui_cancel_pressed`), `get_movement_vector` renvoie ZERO, `is_action_*` renvoient false, `mouse_motion` non émis |

| State (mouse axis) | Entry Condition | Exit Condition | Behavior |
|---|---|---|---|
| **MouseCaptured** | `set_mouse_captured(true)` appelé (Game State Manager entre en Playing) | `set_mouse_captured(false)` (pause, menu) | `Input.mouse_mode = CAPTURED`, souris cachée, deltas purs pour `mouse_motion` |
| **MouseFree** | `set_mouse_captured(false)` (boot, menu, pause) | `set_mouse_captured(true)` | Souris visible, peut cliquer dans le UI, `mouse_motion` signal continue d'émettre (utile pour widgets qui veulent du hover tracking) |

**Combinaisons valides** :
- `Enabled + MouseCaptured` = gameplay actif (état dominant)
- `Disabled + MouseCaptured` = respawn delay (le joueur ne peut rien faire, mais on garde la souris cachée pour éviter le saut de curseur au reprise)
- `Disabled + MouseFree` = pause menu (le joueur interagit avec le menu, le gameplay est gelé)
- `Enabled + MouseFree` = boot screen / main menu (jamais pendant gameplay)

### Interactions with Other Systems

| Système | Rôle | Interface |
|---|---|---|
| **Player Movement System** (aval) | Consomme les inputs gameplay | Appelle `get_movement_vector()`, `was_pressed_this_tick(&"jump" / &"dash")` chaque `_physics_process`. Connecte `mouse_motion` pour la rotation caméra horizontale (Y-axis du joueur). |
| **Camera System** (aval) | Rotation pitch vertical + FOV effects | Connecte `mouse_motion` signal, applique `mouse_sensitivity` et `mouse_y_inverted` à la composante Y. |
| **Player Combat System** (aval) | Déclenche swing katana | Appelle `was_pressed_this_tick(&"attack")` dans `_physics_process`. |
| **Checkpoint & Respawn System** (aval) | Appelle restart manuel, gère le freeze pendant respawn delay | Appelle `was_pressed_this_tick(&"restart")` pour respawn volontaire. Appelle `InputManager.request_disable(self)` à l'entrée RESPAWN_DELAY, `release_enable_request(self)` en sortie. |
| **Menu System** (aval + contrôleur du mode souris) | Bascule captured/free | Connecte `ui_cancel_pressed` signal pour ouvrir/fermer menu. Appelle `set_mouse_captured(bool)`. Appelle `request_disable(self)` à l'ouverture du menu, `release_enable_request(self)` à la fermeture. |
| **Game State Manager** (aval, consumer one-way de focus events) | Pause global sur focus loss | Connecte `application_focus_lost` signal dans `_ready()` (ADR-0004 D-5). Décide seul du pause selon `current_state` (pause uniquement si `PLAYING`). **InputManager n'appelle jamais `GameStateManager.*`** — découplage one-way. |
| **HUD System** (aval, dev overlay) | Affiche latency mesurée | Lit `last_input_to_publish_latency_ms`. Connecte `debug_toggle` action pour afficher/cacher. |
| **Save/Load System** (aval, settings only) | Persiste `input_settings.tres` | Lit/écrit `input_settings.tres` au boot et à chaque changement de sensitivity/remap. |
| **Accessibility System** (post-MVP) | Publie remap overrides, assistance (hold-to-repeat, sticky keys) | Remplit `remap_overrides` dans `input_settings.tres`. Ajoute éventuellement des `action_pressed` simulés pour les features d'assistance. |

## Formulas

Le Input System est quasi sans formule — il passe des booléens et des deltas. Deux formules significatives :

### Movement vector normalization

```
raw_vector = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
# raw_vector est déjà normalisé par Godot : longueur ≤ 1.0, deadzone par défaut appliquée
output = raw_vector if enabled else Vector2.ZERO
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `raw_vector` | `v` | Vector2 | length ∈ [0, 1] | Input brut après normalisation Godot |
| `enabled` | — | bool | true / false | Flag d'activation du système |

**Output range** : `|output|` ∈ [0, 1]. Godot applique déjà la deadzone des axes (default 0.2) et normalise la diagonale pour éviter la "speed bonus en diagonale" classique.
**Exemple** : `W+D` pressés simultanément → `raw_vector = (0.707, -0.707)` → norme exactement 1.0.

### Mouse delta application (côté consommateur, référence)

Ce calcul n'est pas fait *dans* le Input System — il est fait par le Camera System. Il est documenté ici parce que le Input System possède `mouse_sensitivity` :

```
yaw_delta_radians   = mouse_motion.x * mouse_sensitivity
pitch_delta_radians = mouse_motion.y * mouse_sensitivity * (-1 if mouse_y_inverted else 1)
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `mouse_motion` | — | Vector2 | pixels/frame | Delta brut du déplacement souris |
| `mouse_sensitivity` | `s_m` | float | 0.0005 – 0.012 rad/px | Setting utilisateur (range élargi post-r2 pour couvrir high-sens CS:GO-style à low-sens sniper) |
| `mouse_y_inverted` | — | bool | true / false | Setting utilisateur |

**Output range** : à 60 fps avec mouvement rapide (~3000 px/s), `yaw_delta ≈ 50 * 0.0022 ≈ 0.11 rad/frame` = 6.3°/frame. Pas d'accélération souris (choix design : raw input seulement).
**Exemple** : un flick de 1000 px à sensitivity 0.0022 → rotation totale = 2.2 rad ≈ 126°.

### Latency measurement (rolling p99) — algorithme zero-alloc (ADR-0004 D-8)

Périmètre de la mesure : **intra-engine uniquement** — du moment où le callback `_unhandled_input` / `_input` reçoit l'event, au moment où le signal (ou la mise à jour du flag polling) est publié. Ne couvre PAS la latence OS → engine (USB polling 8 ms @ 125 Hz, OS dispatch 1–3 ms, event loop batching 0–8 ms) ni display (VSync + scanout 8–48 ms selon rafraîchissement). Voir Game Feel pour la chaîne complète.

**Structure (zero-alloc, ADR-0004 D-8)** : 2× arrays pré-alloués au `_ready()` de capacité fixe 120 (2 s @ 60 samples/s). **Interdit** : `Array[Dictionary]` / `push_back` / literal `{ts = ..., ms = ...}` — tous allouent dans le hot path. Le ring buffer s'écrase naturellement par `write_idx % CAPACITY`.

```gdscript
const LATENCY_SAMPLES_CAPACITY: int = 120
const LATENCY_WINDOW_USEC: int = 1_000_000  # fenêtre glissante 1 s réelle (filtrée à la lecture)

var _latency_values_ms: PackedFloat32Array = PackedFloat32Array()
var _latency_timestamps_usec: PackedInt64Array = PackedInt64Array()
var _latency_write_idx: int = 0
var _latency_sample_count: int = 0  # clamp à CAPACITY

func _ready() -> void:
    _latency_values_ms.resize(LATENCY_SAMPLES_CAPACITY)
    _latency_timestamps_usec.resize(LATENCY_SAMPLES_CAPACITY)
    # resize() pré-alloue le backing buffer — zero alloc en write ultérieur

# Hot path : capture event arrival, post-publish measure, record
func _record_latency_sample(value_ms: float, ts_usec: int) -> void:
    var slot: int = _latency_write_idx % LATENCY_SAMPLES_CAPACITY
    _latency_values_ms[slot] = value_ms
    _latency_timestamps_usec[slot] = ts_usec
    _latency_write_idx += 1
    if _latency_sample_count < LATENCY_SAMPLES_CAPACITY:
        _latency_sample_count += 1

# Usage dans _unhandled_input (exemple jump key press)
func _unhandled_input(event: InputEvent) -> void:
    var t_event: int = Time.get_ticks_usec()
    if event is InputEventKey and event.is_echo():
        return
    for action in ACTIONS_MVP:
        if event.is_action_pressed(action):
            _pressed_this_tick[action] = true
            _emit_typed_signal_for_action(action)  # jump_pressed, etc.
            var t_publish: int = Time.get_ticks_usec()
            _record_latency_sample((t_publish - t_event) / 1000.0, t_publish)
            break
```

**Calcul p99 à la demande** (lectures rares ~1 Hz depuis HUD F3, PAS dans le hot path) :

```gdscript
# Buffer scratch pré-alloué même capacité — sort, filter fenêtre 1s
var _latency_scratch: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
    # ... (suite du _ready) ...
    _latency_scratch.resize(LATENCY_SAMPLES_CAPACITY)

func get_latency_p99_ms() -> float:
    var now: int = Time.get_ticks_usec()
    var valid_count: int = 0
    for i in range(_latency_sample_count):
        if _latency_timestamps_usec[i] >= now - LATENCY_WINDOW_USEC:
            _latency_scratch[valid_count] = _latency_values_ms[i]
            valid_count += 1
    if valid_count < 10:
        # Fallback : renvoie max au lieu du p99 (règle r2 conservée)
        var max_v: float = 0.0
        for i in range(valid_count):
            if _latency_scratch[i] > max_v:
                max_v = _latency_scratch[i]
        return max_v
    # Sort slice [0, valid_count) — in-place sur le scratch
    _sort_packed_float_slice(_latency_scratch, valid_count)
    var idx_p99: int = int(floor(valid_count * 0.99))
    return _latency_scratch[idx_p99]
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `t_event` | — | int (μs) | — | `Time.get_ticks_usec()` au début du callback. Godot ne fournit pas de timestamp natif sur `InputEvent`. |
| `t_publish` | — | int (μs) | — | `Time.get_ticks_usec()` juste après `.emit()` / flag update. |
| `_latency_values_ms` | — | `PackedFloat32Array` cap 120 | [0, +∞) ms | Pré-alloué au `_ready()`. Zero alloc runtime. |
| `_latency_timestamps_usec` | — | `PackedInt64Array` cap 120 | absolute μs | Pré-alloué. Utilisé pour filtrer fenêtre 1 s à la lecture. |
| `_latency_write_idx` | — | int | [0, +∞) | Monotone. Slot = `% CAPACITY`. |
| `_latency_sample_count` | — | int | [0, 120] | Clamp à CAPACITY ; indique combien de slots valides pour le p99. |

**Taille mémoire fixe** : 120 × 4 bytes (float) + 120 × 8 bytes (int64) + 120 × 4 (scratch) = **1.92 KB** stable (voir ADR-0004 Performance Implications). Zero growth après `_ready()`.

**Forbidden pattern** (registry ADR-0004) : `alloc_in_hot_path_via_literal_dict_or_pushback` — l'ancien `_latency_samples.push_back({ts=..., ms=...})` est interdit par ce forbidden_pattern. Détection via lint `.claude/rules/no-alloc-hot-paths.md`.

**Output range** :
- Cible ≤ 16 ms p99 **intra-engine** (= 1 tick physique à 60 Hz, défaut Godot).
- > 33 ms intra-engine = bloquant Pillar 1 (2 ticks de retard = feel cassé).
- La valeur est mesurée en build release (debug Godot interpreter tourne 3–5× plus lentement ; en debug, accepter jusqu'à ~50 ms p99 comme proxy du budget release).
- **Note** : cette cible couvre uniquement la portion intra-engine. Latence totale perçue (OS polling + event loop + Godot dispatch + display) est budgétée séparément : cible end-to-end ≤ 50 ms p99 (sub-perception humaine ~25-30 ms pour inputs critiques ; au-delà de 50 ms le joueur commence à ressentir). Un test end-to-end (key press hardware → pixel change écran) est nécessaire en phase de polish — pas un AC de l'Input System seul.

**Exemple** : si un `jump` est reçu par `_unhandled_input` à t=100 000 μs et que le signal `action_pressed` est émis à t=105 000 μs, sample = 5.0 ms.

**Pré-requis horloge** : `Time.get_ticks_usec()` nécessite une résolution ≥ 1 ms côté OS. Godot appelle `timeBeginPeriod(1)` sur Windows au boot (à vérifier en 4.6). Si la résolution est 15 ms (Windows par défaut), tous les samples tombent sur 0 ou 15 ms — métrique cassée. AC de validation : sample reference de 5 ms contrôlé → doit valoir 4.0–6.0 ms, pas 0 ou 15.

## Edge Cases

- **Input reçu pendant que `enabled == false`** : l'event est consommé et silencieusement ignoré. Aucun signal typé émis (`jump_pressed`, etc.), aucun log (sauf mode debug). Exception : `ui_cancel_pressed` et `ui_confirm_pressed` traversent quand même — sinon impossible de unpause. `mouse_motion` signal également suppressed (évite la rotation caméra pendant pause/respawn). Les flags `_pressed_this_tick` et `_consumed_this_tick` sont vidés à la transition `enabled: true → false` pour éviter une press mémorisée traversant la désactivation (ADR-0004 D-4).
- **Mouse capture perdue par OS** (alt-tab Windows, OS dialog) : Godot émet `NOTIFICATION_APPLICATION_FOCUS_OUT`. Le Input System sauvegarde `_saved_mouse_mode = Input.mouse_mode`, set `MOUSE_MODE_VISIBLE`, reset `_focus_regained_until_ticks_usec = 0`, puis émet `application_focus_lost()` signal. **InputManager n'appelle AUCUN système aval** (ADR-0004 D-5 — découplage Foundation). Le `GameStateManager` (autoload aval) connecte ce signal dans son `_ready()` et décide seul du pause selon son `current_state` (pause uniquement si `PLAYING`, pas si déjà en menu). Cette inversion préserve le principe « Input = Foundation, aucune dépendance amont » (Quick Reference).
- **Retour de focus (`NOTIFICATION_APPLICATION_FOCUS_IN`)** : restaure `Input.mouse_mode = _saved_mouse_mode`, arme la fenêtre `_focus_regained_until_ticks_usec = Time.get_ticks_usec() + 50_000`, émet `application_focus_gained()` signal. **Tout `InputEventMouseMotion`** reçu dans les 50 ms qui suivent est **absorbé** par `_unhandled_input` (règle 13). Couvre le burst Wayland 3–6 events sur 2–3 frames. Validation 3 OS : Windows 11, macOS Sonoma, Ubuntu Wayland+X11 (ADR-0004 VC-1/2).
- **Touche physiquement bloquée / stuck** (debug hardware) : aucun mitigation code — c'est au joueur de régler son clavier. Le système reportera l'action comme pressée indéfiniment, le consommateur doit pouvoir gérer (ex : hold de `jump` ne spam pas car `was_pressed_this_tick` est edge-triggered — elle ne retourne `true` qu'au tick qui suit la press, pas aux ticks de maintien).
- **Input simultané conflictuel** (ex: deux bindings sur la même touche) : Godot's InputMap gère nativement — plusieurs actions peuvent répondre à la même touche. Le système ne dédoublonne pas ; à la discrétion du design de ne pas mapper deux actions gameplay sur la même touche.
- **Pressage exactement pendant la transition `enabled: false → true`** : si un press tombait pendant le tick disabled, le flag `_pressed_this_tick[action]` a été vidé à la transition disabled (règle 6 + ADR-0004 D-4 `_update_enabled_state`) — `was_pressed_this_tick` retourne `false` au premier tick enabled. Pas de buffer restored. Raison : préserver le contrat « disabled = je ne vois rien ». Si un système veut un jump buffer qui traverse le respawn, c'est au Movement de buffer lui-même (cf. Movement GDD jump_buffer — géré à ce niveau-là).
- **Sensitivity réglée à 0** : `mouse_motion` signal continue d'émettre, mais le Camera System multiplie par 0 → caméra figée. Pas d'erreur. Safe range `[0.0005, 0.012]` rad/px enforce via clamp au moment du set dans le settings menu (bornes r2 — cf. Published API + registry).
- **Deadzone 0.2 et clavier** : l'option `deadzone` dans l'action InputMap s'applique à la magnitude du vecteur résultant d'`Input.get_vector`. Pour le clavier (binaire 0/1), W seul = longueur 1.0 → aucun effet de deadzone. W+D = (0.707, 0.707) après normalisation Godot → toujours aucun effet. **La deadzone n'a d'effet que pour les sticks gamepad** (post-MVP). Documenté ici pour éviter la confusion.
- **`restart` pressé pendant pause menu** : Input publie `action_pressed(&"restart")` ? Non — pause → `enabled == false` → signal supprimé ET polling renvoie false. Le joueur doit d'abord unpause (Escape) puis presser R.
- **`restart` press court vs hold** : hors-scope Input. Input publie un edge simple. Le hold 0.5s (anti-misclick pour respawn volontaire) est géré par Checkpoint & Respawn System, qui mesure la durée via polling de `is_action_pressed(&"restart")` dans son propre `_physics_process`. Si Checkpoint décide finalement de ne pas avoir de hold (instant-restart aligné Pillar 3), aucun changement côté Input.
- **`F3` (debug) pressé en build release** : l'action n'est pas mappée en release (exclue via `OS.has_feature("debug")` check à l'enregistrement dans `_ready()`). Aucun effet.
- **InputEvent avec `event.is_echo() == true`** (auto-repeat clavier quand touche tenue) : filtré dans `_unhandled_input` avec type guard — `if event is InputEventKey and event.is_echo(): return`. Raison : seules les transitions initiales doivent déclencher `action_pressed`. `is_echo()` n'existe pas sur `InputEventMouseMotion` ni sur `InputEvent` générique — d'où le guard de type.
- **Action pressée avec nom inexistant dans InputMap** (typo `&"jum"`) : `was_pressed_this_tick(&"jum")` retourne `false` silencieusement (via `_consumed_this_tick.get(action, false)` — valeur par défaut `false`). En build debug (`OS.has_feature("debug") == true`), un check séparé `InputMap.has_action(action)` émet `push_error("Unknown input action: %s" % action)` une fois par action inconnue rencontrée. Consommateurs doivent utiliser les constantes `ACTION_JUMP` etc. pour prévenir les typos.
- **Remapping qui aboutit à une binding vide** (post-MVP — action plus mappée à aucune touche) : le système autorise, mais émet un warning au boot. L'action ne pourra jamais être pressée. Le Menu Remap UI doit empêcher cette configuration via validation UX.
- **Deux InputEventMouseMotion dans le même frame** : Godot fusionne automatiquement les deltas — un seul événement reçu par frame dans `_unhandled_input`. Aucune logique spéciale à ajouter.
- **Flick extrême** (flick 20 000 px/s sur souris 1000 Hz) : un `InputEventMouseMotion` unique peut livrer 300+ px → rotation caméra ~95°/frame à sensitivity 0.0050. Input publie le delta brut ; le clamp éventuel (`max_delta_radians_per_frame`) est la responsabilité de Camera System. Documenté ici pour éviter la surprise.
- **Game lose focus pendant un dash** : déclenche la pause (règle ci-dessus), Movement System est gelé par `enabled=false`, le dash en cours est gelé avec le reste. Traitement exact de la reprise post-focus = ownership Game State Manager GDD.
- **Mouse sensitivity changée pendant gameplay** (via un settings menu ouvrable en pause) : le nouveau setting est appliqué *au prochain event* (pas d'interpolation), et la valeur est persistée dans `input_settings.tres` via le Save/Load System. Aucun glitch attendu.
- **Valeur invalide lue depuis `input_settings.tres`** (corrupted save, sensitivity NaN ou hors safe range) : fallback hardcodé (0.0022) + log warning. Le fichier est réécrit au prochain save.
- **`Input.mouse_mode` modifié par du code externe** (plugin debug, script tiers) : `is_mouse_captured()` lit `Input.mouse_mode` directement (read-through), donc la réponse est toujours cohérente même si l'état interne d'`InputManager` n'est pas au courant du changement. Les signaux `mouse_captured_changed` (si ajoutés post-MVP) devraient passer par un polling de `Input.mouse_mode` plutôt que par un cache.

## Dependencies

| Système | Direction | Nature de la dépendance |
|---|---|---|
| **Godot Engine (Input singleton)** | Amont direct | Encapsule `Input.*`, `Input.get_vector`, `Input.mouse_mode`, `InputMap`. Si Godot 4.x change l'API (cf. 4.5 SDL3 gamepad, 4.6 dual-focus), adapter ici. |
| **Save/Load System** | Amont (consomme settings) + Aval (publie remap changes) | Lit `input_settings.tres` au boot ; sauvegarde sur changement. Le Save/Load System est le *custodian* du fichier ; Input System fournit le contenu. |
| **Player Movement System** | Aval | Consomme `get_movement_vector()`, `was_pressed_this_tick(&"jump"/&"dash"/&"restart")`, `mouse_motion`. Toute renommage d'action casse Movement. |
| **Camera System** | Aval | Consomme `mouse_motion`, lit `mouse_sensitivity`, `mouse_y_inverted`. |
| **Player Combat System** | Aval | Consomme `was_pressed_this_tick(&"attack")`. |
| **Checkpoint & Respawn System** | Aval | Appelle `request_disable(self)` à l'entrée RESPAWN_DELAY, `release_enable_request(self)` en sortie ; consomme `&"restart"` action via polling (`was_pressed_this_tick(&"restart")` + `is_action_pressed(&"restart")`) et **détient le hold anti-misclick 0.5s** si conservé — Input ne filtre pas. |
| **Game State Manager** | Aval (consumer one-way) | Connecte `application_focus_lost` signal (ADR-0004 D-5). Contrôle `set_mouse_captured()` selon l'état du run (Playing vs Menu). Appelle `request_disable/release_enable_request` pendant pause. |
| **Menu System** | Aval (contrôleur + consommateur) | Connecte `ui_cancel_pressed`, `ui_confirm_pressed`. Appelle `set_mouse_captured(false)` + `request_disable(self)` à l'ouverture du menu ; `release_enable_request(self)` + `set_mouse_captured(true)` à la fermeture. |
| **HUD System** | Aval | Lit `last_input_to_publish_latency_ms` pour overlay debug. Consomme `debug_toggle` action. |
| **Accessibility System** (Full Vision) | Aval | Override `remap_overrides`, potentiellement injecte des actions simulées pour hold-to-repeat ou sticky keys. |

**Note de cohérence bidirectionnelle** : chaque système aval ci-dessus DOIT lister Input System en dépendance amont. Le Player Movement GDD le fait déjà (section Dependencies + Cross-References). Les autres GDDs à rédiger devront l'inclure.

**Contrainte d'ordre d'initialisation** (`project.godot` section `[autoload]`) :

```
[autoload]
InputManager="*res://src/core/input_manager.gd"       # 1er — aucune dépendance amont
SaveLoadManager="*res://src/core/save_load_manager.gd"  # 2ème — utilisé par InputManager pour settings load mais InputManager tolère l'absence (fallback defaults)
GameStateManager="*res://src/core/game_state_manager.gd"  # 3ème — contrôle enabled/mouse_mode
```

Raison : `InputManager._ready()` doit avoir fini de charger `input_settings.tres` (via `ResourceLoader.load()` synchrone) avant le premier `_unhandled_input`. Godot garantit que tous les `_ready()` des autoloads finissent avant le premier event delivery si le load est synchrone. Si `SaveLoadManager` est déclaré AVANT `InputManager` et qu'il tente de lire des settings via InputManager, l'ordre inverse serait requis — mais le pattern choisi est : InputManager charge lui-même ses settings (fallback hardcodé si fichier absent), SaveLoadManager écrit quand le settings menu modifie une valeur. Pas d'appel croisé au boot.

## Tuning Knobs

| Paramètre | Valeur courante | Safe Range | Effet si augmenté | Effet si diminué |
|---|---|---|---|---|
| `mouse_sensitivity` | 0.0022 rad/px | 0.0005 – 0.012 | Caméra rapide (les joueurs FPS high-sens à 0.008-0.012 flick tour complet en un geste) | Caméra très lente (low-sens sniper 0.0005-0.0010, précision micro-ajustements). Slider exposé non-linéaire (exponentiel) pour garder précision dans les basses valeurs. |
| `mouse_y_inverted` | false | true / false | Inverse la pitch verticale | — |
| `mouse_axis_deadzone_stick` (InputMap action deadzone) | 0.20 (Godot default, gamepad uniquement) | 0.10 – 0.35 | Stick gamepad plus tolérant aux tremblements (post-MVP) | Stick trop sensible, dérive involontaire. **Sans effet sur clavier** (binaire 0/1) — configuré dans l'éditeur Project > Input Map par action, pas en code. |
| `mouse_capture_at_boot` | false | true / false | Souris capturée dès le boot (skip main menu) | Souris libre jusqu'au premier Play click |
| `debug_overlay_default` | false (release) / true (editor & dev build) | true / false | HUD latency visible d'office | HUD latency caché, toggle F3 requis |
| `latency_anomaly_threshold_ms` | 0.1 ms (release) / 0.5 ms (debug interpreter) | 0.05 – 1.0 | Plus tolérant — détecte seulement les vrais bugs structurels | Plus sensible — log warning plus vite, peut spam |
| `action_press_coalesce_window` | 0 s (désactivé au MVP) | 0 – 0.05 | Fusionne deux press rapprochés en un (anti-double-fire pour hardware douteux) | Chaque press est distinct (default) |

**À PROPOS de `latency_anomaly_threshold_ms`** : pas une cible de tuning, mais un seuil d'alerte. Le coût nominal attendu du hot path est ~0.005–0.01 ms release (quelques signals + ring buffer push). Tout dépassement de 0.1 ms release = bug structurel à investiguer (allocation heap dans le hot path, boucle imprévue, signal dispatch O(N²) latent). Le HUD overlay F3 affiche la valeur mesurée et flag rouge si > seuil.

**Ring buffer fenêtre** : hard-coded à 1 seconde réelle (time-based), pas paramétrable. Voir Formulas → Latency measurement pour l'algo.

**`restart_hold_duration` — déplacé** : ce paramètre appartient désormais au Checkpoint & Respawn System GDD (ownership architectural : Input ne filtre pas les actions métier). Si Checkpoint décide de garder le hold 0.5s, il lira son propre knob ; sinon (restart instantané à la Ghostrunner, aligné Pillar 3), aucun knob requis.

**Interactions notables** :
- `mouse_sensitivity` et `mouse_y_inverted` sont persistés dans `input_settings.tres` (survivent aux runs). Les autres sont des constantes compile-time ou debug-only.
- Tout changement de `mouse_sensitivity` invalide instantanément le feel du gameplay — à exposer dans un settings menu (cf. Menu System GDD futur).

## Visual/Audio Requirements

Système infrastructure : pas de VFX/audio propre. Les feedbacks associés aux inputs (whoosh de dash, clic de menu, etc.) sont la responsabilité des systèmes aval qui *réagissent* aux actions.

Deux exceptions infrastructurelles :

| Événement | Feedback visuel | Feedback audio | Priorité |
|---|---|---|---|
| Menu click (mouse press sur widget) | Highlight du widget (géré par Theme Godot) | `ui_click.wav` court | Low — natif Godot |
| Mouse capture change (boot, menu ↔ gameplay) | Souris apparaît/disparaît — transition hard, pas d'animation | Aucun | Low |

## Game Feel

### Feel Reference

**Aucun jeu spécifique** — la référence est *l'absence* de jeux mal faits. Ghostrunner, Counter-Strike, DOOM (2016), Quake : tous ont un input qui disparaît. Anti-référence : les jeux console porté PC sans retravailler le input (mouse accelerated, input queue, hold-to-confirm partout).

### Input Responsiveness — trois budgets distincts

La latence totale perçue par le joueur est la somme de trois étapes. Le Input System en contrôle UNE (intra-engine). Les deux autres sont dictées par le hardware du joueur et les choix config de rendering.

| Segment | Budget cible p99 | Responsable | Notes |
|---|---|---|---|
| **OS → engine** (USB polling + OS dispatch + event loop batching) | 2–15 ms variable | Hardware + OS | Non-contrôlable. Mitigation joueur : clavier 1000 Hz, souris gaming. Non-mesurable depuis GDScript. |
| **Intra-engine** (callback reçu → signal émis / flag polling updated) | **≤ 16 ms** (= 1 tick physique @ 60 Hz, défaut Godot) | Input System (CE GDD) | **Mesuré par le ring buffer p99** ci-dessus. Cible sacrée — dérive = alerte HUD F3. Budget debug interpreter : ≤ 50 ms (3–5× release). |
| **Engine → display** (rendering + VSync + scanout) | 8 ms @ 144 Hz VSync off ; 16 ms @ 144 Hz VSync on ; 32 ms @ 60 Hz VSync | Rendering config (Technical Director decision) | Recommandation Pillar 1 : 144 Hz VSync off ou G-Sync. VSync 60 Hz = Pillar 1 compromis assumé. |
| **Total perçu joueur p99** | **~25–50 ms** (hardware standard) / ~20–30 ms (gaming 1000 Hz + 144 Hz) | — | Ce que le playtest mesure en phase Polish. Sub-perception humaine ~25-30 ms pour clics critiques. |

| Action | Intra-engine budget (p99) | Critique Pillar 1 ? |
|---|---|---|
| Key press → signal typé (`jump_pressed`, `dash_pressed`, `attack_pressed`) / polling flag update | ≤ 16 ms | OUI — jump, dash, attack |
| Mouse motion → `mouse_motion` signal | ≤ 16 ms (émis depuis `_unhandled_input`) | OUI — aim feel |
| Mouse click → `attack_pressed` / polling flag | ≤ 16 ms | OUI — katana swing |
| State change (`enabled`, mouse capture) | ≤ 33 ms | Non — asynchrone |

**La cible publique du GDD est `publish latency p99 ≤ 16 ms intra-engine`** (1 tick physique à 60 Hz, cadence par défaut de Godot confirmée pour ce projet). Toute dérive déclenche une alerte HUD F3 pendant le dev. Il est **essentiel** que cette mesure ne soit pas confondue avec la latence totale perçue : la doc de playtest et les ACs de feel doivent clairement distinguer les deux.

> **Décision acté post-r2** : physique Godot à 60 Hz (défaut). Raison : le coût d'un doublement à 120 Hz sur Movement + Camera + Combat n'est pas justifié pour les 8 ms théoriquement gagnés, alors que le tick-to-tick déjà ≤ 16 ms est sous le seuil de perception pour clics simples. Si une future phase Polish démontre un besoin, un ADR dédié pourra acter la transition à 120 Hz avec rebudgétisation complète des systèmes physiques.

### Animation Feel Targets

N/A — système sans animation.

### Impact Moments

N/A — infrastructure.

### Weight and Responsiveness Profile

- **Weight** : néant — aucun concept de poids, c'est un relai pur.
- **Contrôle joueur** : total, toujours. Aucune action "absorbée" sauf quand `enabled=false` (explicitement désactivé par un autre système).
- **Snap quality** : binaire — chaque press est un edge, chaque release est un edge.
- **Modèle d'accélération** : aucune — raw input, zéro lissage, zéro mouse acceleration.
- **Texture d'échec** : si un input paraît perdu, c'est soit (a) `enabled=false` non signalé — à corriger côté système qui désactive ; (b) latence hardware (OS, clavier) — pas de mitigation. Le HUD debug doit pouvoir identifier lequel des deux.

### Feel Acceptance Criteria

Ces ACs sont du **Game Feel** — évalués par playtest structuré, pas par test automatisé. Les ACs automatisables figurent dans la section Acceptance Criteria plus bas.

Protocole de playtest structuré (à documenter séparément dans `tests/playtest-protocols/input-system-feel.md` avant la phase QA) :

- [ ] **AC-FEEL-01 (Playtest structuré input perdu)** : **GIVEN** N≥3 playtesters en session structurée (protocole pense-à-voix-haute + questionnaire sortie), 10 min de gameplay actif (combat + mouvement, pas menu), **WHEN** le debrief pose la question fermée "Avez-vous eu le sentiment qu'une action (jump, dash, attack, restart) n'a pas été enregistrée ? Oui/Non", **THEN** 0 Oui sur les N sessions. Si 1+ Oui, évenement documenté (timestamp + action) → bug S2 vers lead-programmer. Evidence : `production/qa/evidence/input-playtest-feel-{date}.md`.
- [ ] **AC-FEEL-02 (Dev overlay latency)** : **GIVEN** build dev avec overlay F3 actif, **WHEN** QA exécute le protocole d'input standardisé de 5 min (cf. AC-LAT-01), **THEN** 3 captures d'écran (t=1/3/5 min) montrent `last_input_to_publish_latency_ms ≤ 16 ms p99` chacune. Une violation isolée < 3 fenêtres consécutives tolérée. Evidence : `production/qa/evidence/input-latency-{date}/`.
- [ ] **AC-FEEL-03 (Mouse mode transitions)** : **GIVEN** état Playing (curseur caché), **WHEN** le joueur presse Escape pour ouvrir le pause menu, **THEN** la position du curseur au frame T+1 est à ≤ 2 px de sa position au frame T (mesuré via log de position cursor en build dev). Réciproquement au retour gameplay. Evidence : log + screenshot cursor position dans `production/qa/evidence/`.
- [ ] **AC-FEEL-04 (Alt-tab cycle)** : **GIVEN** état Playing avec W+A tenus, **WHEN** alt-tab (Windows : Alt+Tab, Mac : Cmd+Tab), attente 3s, retour focus, unpause via Escape, **THEN** (a) le jeu est en pause automatiquement au alt-tab (menu pause visible), (b) aucun mouvement joueur au retour tant que W/A ne sont pas relâchés-repressés, (c) pas de rotation caméra brutale au retour (premier `InputEventMouseMotion` post-focus drop). Exécuter 5× par OS (Windows + macOS + Linux). Evidence : vidéo courte ou log d'états.
- [ ] **AC-FEEL-05 (Boot settings loaded)** : **GIVEN** `input_settings.tres` contient `mouse_sensitivity = 0.0055` (valeur non-default), **WHEN** le joueur lance le jeu et bouge la souris de +200 px au premier frame jouable, **THEN** la rotation caméra observée correspond à `sensitivity = 0.0055` (pas 0.0022). Alternativement : log dev "InputSettings loaded at t=Xms" + "First InputEvent at t=Yms", PASS si X < Y.

## UI Requirements

| Information | Emplacement HUD | Fréquence update | Condition |
|---|---|---|---|
| Latency p99 (ms) | Overlay debug F3, coin supérieur droit | Chaque tick physique (60 Hz) | Toggle F3, build non-release uniquement |
| Current action pressed (list) | Overlay debug F3, sous latency | À chaque signal `*_pressed / *_released` | Toggle F3, dev |
| Mouse mode indicator | Overlay debug F3 | À chaque changement | Toggle F3, dev |
| **Controls reference (MVP)** | **Pause Menu → écran "Controls"** | **Statique** | **Accessible en tout temps via pause menu — liste lisible des bindings par défaut (WASD, Space, Shift, Mouse Left, R, Escape). MVP obligatoire pour que le joueur découvre l'existence de restart et debug.** |
| Sensitivity slider | Menu Settings (écran dédié) | Preview live sur `value_changed` | Accessible depuis pause menu |
| Invert Y checkbox | Menu Settings | Au click | Idem |
| Remap table | Menu Settings (post-MVP) | Au remap | Idem |

> **📌 UX Flag — Input System** : Deux écrans de Menu Settings nécessitent un spec UX avant les stories Menu System :
> 1. **Settings** (sensitivity slider exponentiel non-linéaire, invert Y checkbox, remap post-MVP) → lancer `/ux-design settings-input`
> 2. **Controls** (MVP obligatoire — liste statique lisible des bindings par défaut, pas de modification au MVP) → lancer `/ux-design controls-overlay`
>
> Noter les deux dans systems-index. Décision acté post-r2 : pas de splash au premier spawn ; le joueur accède à Controls via pause menu quand il en a besoin. Risque résiduel : un joueur novice ne presse peut-être jamais Escape — à mitiger par un hint discret "Press Escape for menu" au premier spawn (spec Menu System).

## Cross-References

| Ce document référence | GDD cible | Élément référencé | Nature |
|---|---|---|---|
| `mouse_sensitivity` exposé ici, consommé par Camera | `design/gdd/camera-system.md` *(à écrire)* | Application du delta rotation | Data dependency |
| `get_movement_vector()`, `was_pressed_this_tick(&"jump"/&"dash"/&"restart")` | `design/gdd/player-movement-system.md` *(existant)* | API consommée par Movement | Data dependency |
| `was_pressed_this_tick(&"attack")` | `design/gdd/player-combat-system.md` *(à écrire)* | Trigger katana swing | State trigger |
| `request_disable(owner) / release_enable_request(owner)` appelé pendant respawn delay | `design/gdd/checkpoint-respawn-system.md` *(à écrire)* | Freeze d'input coordonné refcount | Ownership handoff |
| `set_mouse_captured()`, `request_disable/release_enable_request` appelés par Menu | `design/gdd/menu-system.md` *(à écrire)* | Contrôle du mode d'input | Ownership handoff |
| `ui_cancel_pressed` signal consommé par Menu | `design/gdd/menu-system.md` *(à écrire)* | Pause toggle | State trigger |
| `application_focus_lost` signal consommé par GameStateManager (ADR-0004 D-5) | `design/gdd/game-state-manager.md` *(à écrire)* | Découplage focus-loss → pause | State trigger one-way |
| `input_settings.tres` persisté par Save/Load | `design/gdd/save-load-system.md` *(à écrire)* | Settings file lifecycle | Ownership handoff |

> **Registry entry (résolu 2026-04-21, range élargi post-r2)** : `mouse_sensitivity` = 0.0022 rad/px (safe range **0.0005 – 0.012** — élargi post-design-review r2 pour couvrir high-sens FPS et low-sens sniper) est **owned par Input System** (cette GDD). Enregistré dans `design/registry/entities.yaml` → constants. Le Movement GDD a retiré l'entrée `MOUSE_SENS` de ses Tuning Knobs et ajouté une note "Settings owned by Input System". Le Camera GDD à venir le consommera pour le pitch vertical. Le registry `entities.yaml` doit être mis à jour pour refléter le nouveau safe_range.

## Acceptance Criteria

> **Classification par type** (cf. `.claude/docs/coding-standards.md` → Test Evidence by Story Type) :
> - **Logic** : automatisés GUT, BLOCKING.
> - **Integration** : ≥ 2 systèmes OU hook public `_on_application_focus_changed(bool)` pour simuler focus headless, BLOCKING.
> - **Visual/Feel** : playtest + screenshot + lead sign-off, ADVISORY.
> - **Config/Data** : smoke check, ADVISORY.

### Actions gameplay — Logic (BLOCKING)

> **Note API test fixture (ADR-0004 D-9)** : tous les AC d'injection d'action utilisent `Input.parse_input_event(InputEventAction)` — c'est le seul pattern qui déclenche `_unhandled_input` (godot-specialist authoritative r4). `Input.action_press(...)` met à jour l'état interne d'`Input.*` mais **ne trigger PAS** les callbacks `_unhandled_input` → teste le mauvais chemin.

- **AC-AG-1 (Logic)** — **GIVEN** `enabled == true`, **WHEN** un `InputEventAction.new()` avec `action = &"move_forward"` et `pressed = true` est injecté via `Input.parse_input_event(ev)` dans GUT, **THEN** au `_physics_process` suivant (tick N) `get_movement_vector()` renvoie `Vector2(0, -1)` ± 0.01 et `was_pressed_this_tick(&"move_forward")` renvoie `true`.
- **AC-AG-2 (Logic)** — **GIVEN** `enabled == true`, **WHEN** `&"jump"` est pressée via `Input.parse_input_event(InputEventAction)` au frame render N, **THEN** `was_pressed_this_tick(&"jump")` renvoie `true` au `_physics_process` du tick N (1 fois), `false` au tick N+1 (edge-triggered strict via swap `_pressed ↔ _consumed` règle 16).
- **AC-AG-3 (Logic)** — **GIVEN** `&"dash"` pressée via `Input.parse_input_event(InputEventAction{pressed=true})` et maintenue (pas de release) pendant 60 ticks consécutifs, **THEN** `was_pressed_this_tick(&"dash")` renvoie `true` **uniquement** au tick N ; `is_action_pressed(&"dash")` renvoie `true` aux ticks N..N+59.
- **AC-AG-4 (Logic)** — **GIVEN** `enabled == true` ET `Time.get_ticks_usec() >= _focus_regained_until_ticks_usec`, **WHEN** `InputEventMouseMotion` avec `relative = Vector2(10, 0)` injecté via `Input.parse_input_event(ev)`, **THEN** signal `mouse_motion(Vector2(10, 0))` émis exactement une fois.
- **AC-AG-5 (Logic — simulate_action_press)** — **GIVEN** build debug (`OS.has_feature("debug") == true`), **WHEN** `InputManager.simulate_action_press(&"jump")` appelé, **THEN** `was_pressed_this_tick(&"jump")` retourne `true` au tick suivant ET signal `jump_pressed` émis. **GIVEN** build release (via mock `OS.has_feature` = false), **WHEN** même appel, **THEN** no-op silencieux + `assert` déclenche en debug de test.

### Disabled state — Logic (BLOCKING)

- **AC-DS-1 (Logic)** — **GIVEN** au moins un blocker actif (`enabled == false`), **WHEN** toute action gameplay pressée via `Input.parse_input_event(InputEventAction)`, **THEN** aucun signal typé (`jump_pressed`, etc.) émis, `get_movement_vector() == Vector2.ZERO`, `was_pressed_this_tick(<any>)` renvoie `false`.
- **AC-DS-2 (Logic)** — **GIVEN** `enabled == false`, **WHEN** `&"ui_cancel"` pressée via `Input.parse_input_event(InputEventAction)`, **THEN** signal `ui_cancel_pressed` émis exactement une fois.
- **AC-DS-3 (Logic)** — **GIVEN** `enabled == false`, **WHEN** `InputEventMouseMotion` injecté via `Input.parse_input_event`, **THEN** aucun `mouse_motion` émis.
- **AC-DS-4 (Logic — no ghost post-transition)** — **GIVEN** `request_disable(Node_A)` actif (enabled=false) pendant qu'un `InputEventAction{action=&"jump", pressed=true}` est injecté, puis `release_enable_request(Node_A)` (enabled=true), **WHEN** aucun input tenu, **THEN** `was_pressed_this_tick(&"jump")` renvoie `false` au premier tick enabled (flags vidés à la transition disabled).

### Mouse capture — Logic + Integration

- **AC-MC-1 (Logic)** — **GIVEN** `set_mouse_captured(true)`, **THEN** `Input.mouse_mode == MOUSE_MODE_CAPTURED` et `is_mouse_captured() == true`.
- **AC-MC-2 (Logic)** — **GIVEN** `set_mouse_captured(false)`, **THEN** `Input.mouse_mode == MOUSE_MODE_VISIBLE` et `is_mouse_captured() == false`.
- **AC-MC-3 (Logic — read-through)** — **GIVEN** `Input.mouse_mode` modifié directement par code externe, **THEN** `is_mouse_captured()` reflète la nouvelle valeur au prochain appel.
- **AC-MC-4 (Integration — focus loss, ADR-0004 D-5)** — Via hook `InputManager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)`, **GIVEN** un `GameStateManager` mock connecté à `application_focus_lost` avec `current_state = PLAYING`, **WHEN** notification émise, **THEN** (a) `Input.mouse_mode == MOUSE_MODE_VISIBLE`, (b) signal `application_focus_lost` émis exactement une fois, (c) mock reçoit le signal et son handler `_on_focus_lost()` a été invoqué une fois — **sans qu'InputManager ne contienne de référence à `GameStateManager`** (assert via grep lint sur `input_manager.gd`).
- **AC-MC-5 (Integration — focus regain fenêtre 50 ms, ADR-0004 D-6)** — **GIVEN** `InputManager.notification(NOTIFICATION_APPLICATION_FOCUS_IN)` déclenchée à `t0 = Time.get_ticks_usec()`, **WHEN** 3 `InputEventMouseMotion` avec `relative=Vector2(100,0)` injectés via `Input.parse_input_event` entre `t0` et `t0 + 30_000 µs` (30 ms, dans la fenêtre 50 ms), **THEN** aucun `mouse_motion` signal émis. **WHEN** un 4e event injecté à `t0 + 60_000 µs` (hors fenêtre), **THEN** `mouse_motion` émis normalement.
- **AC-MC-7 (Logic — Wayland burst simulé)** — **GIVEN** `_focus_regained_until_ticks_usec = Time.get_ticks_usec() + 50_000`, **WHEN** burst de 6 `InputEventMouseMotion(relative=Vector2(50, 0))` injectés sur 3 ticks physiques (2 par tick), **THEN** tous absorbés, zero `mouse_motion` signal. Couvre scénario Wayland documenté (ADR-0004 VC-2).
- **AC-MC-6 (Visual/Feel — Advisory)** — playtest Windows + macOS + Linux : alt-tab + retour = aucune rotation caméra brutale. Lead sign-off sur vidéo, ≥ 5 cycles par OS.

### Latency — Logic + Integration (BLOCKING)

- **AC-L-1 (Logic — p99 algo, ADR-0004 D-8)** — **GIVEN** `_latency_values_ms[0..5]` contient `[5, 5, 5, 5, 5, 32]` avec `_latency_sample_count = 6` et timestamps tous dans la fenêtre 1 s, **THEN** `get_latency_p99_ms()` ≥ 30 (spike non-moyenné — même si < 10 samples, le fallback `max` capture le pic).
- **AC-L-2 (Logic — horloge)** — **GIVEN** un sample de référence calibré à 5.0 ms exactes, **WHEN** mesuré via `Time.get_ticks_usec()`, **THEN** valeur ∈ [4.0, 6.0]. Hors range (ex : 0 ou 15 ms) = résolution horloge insuffisante, bloquer et investiguer.
- **AC-L-3 (Integration — cible)** — **GIVEN** scène `tests/performance/input_benchmark.tscn` (à créer) injectant 1000 `InputEventKey` + 1000 `InputEventMouseMotion` sur 1000 frames à 60 Hz physique, **THEN** `last_input_to_publish_latency_ms` ≤ 16.0 (release) ou ≤ 50.0 (debug interpreter).
- **AC-L-4 (Logic — âge samples, ADR-0004 D-8)** — **GIVEN** 50 samples injectés à `t0`, puis 2 secondes simulées (advance_time), **WHEN** `get_latency_p99_ms()` appelé à `t0 + 2_000_000 µs`, **THEN** aucun sample passe le filtre fenêtre 1 s → fallback `max` sur 0 samples retourne `0.0`. Le ring buffer physique garde les slots mais le filtre time-based les exclut de la lecture.

### Persistence — Logic (BLOCKING)

- **AC-P-1 (Logic)** — **GIVEN** `mouse_sensitivity = 0.0035` assigné, **WHEN** `save_settings()` appelé puis nouvelle instance via `_ready()`, **THEN** `mouse_sensitivity` lu == 0.0035.
- **AC-P-2 (Logic)** — **GIVEN** `input_settings.tres` absent, **WHEN** `_ready()`, **THEN** `mouse_sensitivity == 0.0022` (default). Au prochain save, fichier valide réécrit.
- **AC-P-3 (Logic)** — **GIVEN** fichier avec `mouse_sensitivity = NaN` ou hors safe range, **WHEN** `_ready()`, **THEN** fallback 0.0022 + `push_warning` émis.

### Intégration cross-system — Integration (BLOCKING)

- **AC-CS-1 (Integration — tick N parity, ADR-0004 D-3)** — **GIVEN** `InputManager` autoload #1 + un consumer Node dans la scene tree qui poll `was_pressed_this_tick(&"jump")` depuis son `_physics_process`, **WHEN** `Input.parse_input_event(InputEventAction{action=&"jump", pressed=true})` au frame render qui précède le `_physics_process` du tick N, **THEN** consumer lit `true` au `_physics_process` du **tick N** (pas N+1). Validation via log timestamps `_physics_process`.
- **AC-CS-2 (Integration — refcount multi-owner, ADR-0004 D-4)** — **GIVEN** 3 Node mocks (`Menu`, `Checkpoint`, `Cutscene`), **WHEN** la séquence suivante est exécutée : (1) `Menu.request_disable(Menu)` → `enabled == false`, (2) `Checkpoint.request_disable(Checkpoint)` → `enabled == false`, (3) `Menu.release_enable_request(Menu)` → `enabled == false` (Checkpoint encore actif), (4) `Checkpoint.release_enable_request(Checkpoint)` → `enabled == true`, **THEN** à chaque étape, `was_pressed_this_tick(<any>)` retourne conformément aux attentes ci-dessus.
- **AC-CS-3 (Integration — auto-cleanup tree_exited, ADR-0004 D-4)** — **GIVEN** un Node mock qui appelle `InputManager.request_disable(self)` puis `queue_free()` sans release, **WHEN** `tree_exited` émis automatiquement, **THEN** `_enable_blockers.size() == 0` et `enabled == true` — pas de fuite.
- **AC-CS-4 (Integration — no ghost post-release)** — **GIVEN** `request_disable(Node_A)` actif, actions pressées pendant disabled, puis `release_enable_request(Node_A)`, **THEN** `was_pressed_this_tick(&"jump")` renvoie `false` au premier tick enabled (flags vidés à la transition disabled — cf. règle 6).
- **AC-CS-5 (Visual/Feel — Advisory)** — playtest pause : ouvrir menu pause 5 s, unpause. Aucun saut caméra / input fantôme. Lead sign-off.

### Debug & telemetry — Logic + Manual

- **AC-DBG-1 (Logic)** — **GIVEN** `OS.has_feature("debug") == true` (build dev), **THEN** `InputMap.has_action(&"debug_toggle") == true` après `_ready()`.
- **AC-DBG-2 (Manual — smoke check pre-release)** — **GIVEN** build export release, **WHEN** un testeur presse `F3` pendant gameplay, **THEN** l'overlay n'apparaît pas. Binary check, évident visuellement.
- **AC-DBG-3 (Logic)** — **GIVEN** build dev, **WHEN** `F3` pressé, **THEN** `debug_overlay_enabled` toggle ; overlay affiche latency p99 + current action pressed + mouse mode indicator.

### Performance — Perf + Code Review

- **AC-PF-1 (Perf)** owner: performance-analyst — **GIVEN** build dev + Godot Profiler actif + scène `tests/performance/input_benchmark.tscn`, **WHEN** mesure sur 300 frames le coût de `InputManager._unhandled_input` + `InputManager._input` + `InputManager._physics_process`, **THEN** ≤ 0.5 ms p99 (debug tolérance 5× release ; cible release ≤ 0.1 ms). Evidence : screenshot profiler dans `production/qa/evidence/input-perf-{date}.png`.
- **AC-PF-2 (Code Review — zero-alloc hot paths, ADR-0004 D-8)** owner: godot-gdscript-specialist — **GIVEN** le code des hot paths (`_unhandled_input`, `_input`, `_physics_process`, `_record_latency_sample` de `InputManager`), **THEN** grep CI détecte zéro occurrence de : (a) `push_back(` sur `Array` ou `PackedArray`, (b) literal `{...}` Dictionary, (c) literal `[...]` Array, (d) `String(` conversion, (e) concat `+` de `String`, (f) `Dictionary.new()` / `Array.new()`. Lint rule `.claude/rules/no-alloc-hot-paths.md` (à créer). Forbidden pattern registry : `alloc_in_hot_path_via_literal_dict_or_pushback`.
- **AC-PF-3 (End-to-end — Polish phase)** owner: performance-analyst + gameplay-programmer — **GIVEN** mesure caméra 240 fps OU NVIDIA LDAT sur hardware cible, **WHEN** key press hardware enregistré → pixel change écran détecté, **THEN** délai p99 ≤ 50 ms. Non-bloquant MVP (hardware cible non garanti), gate Polish.
- **AC-PF-4 (Perf — zero-alloc stress test, ADR-0004 VC-3 + D-8)** owner: performance-analyst — **GIVEN** build dev + scène test injectant 10 000 `simulate_action_press` + 10 000 `simulate_mouse_motion(Vector2(1,0))` sur 60 s (≈ 166 events/s chaque, cumulé 333/s), **THEN** `Performance.get_monitor(Performance.MEMORY_STATIC)` delta entre t=0 et t=60s < **64 KB** (marge GC tolérée). **Évidence** : log memory samples toutes les 5 s dans `production/qa/evidence/input-zero-alloc-{date}.log`. **Si échec** : investigation sur `_latency_values_ms[slot] = value` / swap `_pressed ↔ _consumed` — replier si besoin sur 2× `PackedByteArray` parallèles (ADR-0004 Risk 2 mitigation).
- **AC-PF-5 (Perf — cost hot path p99 release, nouveau ADR-0004 Migration Plan)** owner: performance-analyst — **GIVEN** build **release** sur machine entry-level laptop cible, profiler Godot sur 300 frames, **THEN** coût cumulé `_unhandled_input` + `_physics_process` de `InputManager` p99 ≤ **0.1 ms / frame**. Profilé **séparément** du gate global 16 ms de AC-L-3 (une régression 0.01 → 5 ms passerait l'AC-L-3 mais échouerait ici — gate dédié contre régression silencieuse d'ordre de grandeur).

## Open Questions

| Question | Owner | Deadline | Résolution attendue |
|---|---|---|---|
| Remap UI : MVP ou Full Vision ? | game-designer + ux-designer | Avant Menu System GDD | **Résolu r2** : Full Vision. MVP = bindings fixes + overlay Controls (read-only) dans pause menu. Expose sensitivity slider + invert Y au MVP. Remap complet post-MVP. |
| Gamepad : infrastructure ready au MVP ou plus tard ? | gameplay-programmer | Avant Sprint 1 | Recommandation : **InputMap actions préparées dès le MVP** (mapper les boutons dans `project.godot`) mais feature "support officiel gamepad" = Tier 2. Coût marginal très faible, évite un refactor. |
| Accessibility minimum au MVP (hors sticky keys / remap) ? | ux-designer + accessibility-specialist | Avant Sprint 1 | **Ouvert** : ux-designer r2 argumente pour toggle-to-dash + single-press restart en Settings MVP (accessibility est un floor). À trancher via `/ux-design settings-input`. Si accepté, ajouter knob `dash_hold_mode: edge | toggle` et `restart_hold_enabled: bool` aux tuning knobs MVP. |
| Hint "Press Escape for menu" au premier spawn ? | ux-designer | Avant Menu System GDD | **Nouveau r2** : décision overlay Controls via pause menu laisse un risque de découvrabilité (joueur novice). À traiter en spec Menu System — Input n'a rien à faire. |
| ~~Rendering config (VSync / framerate display) pour Pillar 1 ?~~ | — | — | **RÉSOLUE 2026-04-21 par ADR-0003** (`docs/architecture/adr-0003-rendering-latency.md`). Stratégie tier : default VSync on @ 60 fps (Pillar 4 vsync-locked), opt-in Settings menu MVP (VSync mode / frame cap / AA / MSAA) pour low-latency 144 Hz / G-Sync (Pillar 1). E2E ≤ 50 ms atteignable en opt-in, ~51-67 ms en default (compromis assumé, documenté). TAA bannie. SMAA 1x default. Shader Baker activé. |
| ~~ADR pour physique 60 Hz explicite ?~~ | — | — | **RÉSOLUE 2026-04-21 par ADR-0001** (`docs/architecture/adr-0001-physics-rate-60hz.md`). 60 Hz acté, `_physics_process` unique autorité gameplay, Jolt default 4.6, pattern flag-via-signal anti-drop render > physics documenté. `max_physics_steps_per_frame = 4` (override défaut 8, entry-level laptop safety). |
| ~~API polling canonique (`is_action_just_pressed` vs `was_pressed_this_tick`) ?~~ | — | — | **RÉSOLUE 2026-04-21 par ADR-0004** (`docs/architecture/adr-0004-input-api-focus-handling.md`). `was_pressed_this_tick` canonique (D-1), `is_action_just_pressed` supprimée de l'API publique (D-2). Swap `_pressed ↔ _consumed` début `_physics_process` (D-3). |
| ~~Multi-owner enable gating (Menu+Checkpoint+Cutscene) ?~~ | — | — | **RÉSOLUE 2026-04-21 par ADR-0004 D-4**. `request_disable(owner) / release_enable_request(owner)` refcount idempotent avec auto-cleanup via `tree_exited`. `set_enabled(bool)` supprimée. |
| ~~Focus loss/regain Wayland burst ?~~ | — | — | **RÉSOLUE 2026-04-21 par ADR-0004 D-5+D-6**. Fenêtre 50 ms absolute time `_focus_regained_until_ticks_usec`. Signals `application_focus_lost/gained` one-way (Foundation découplée). Tunable 20-150 ms via `input_settings.tres`. |
| ~~Zero-alloc latency ring buffer ?~~ | — | — | **RÉSOLUE 2026-04-21 par ADR-0004 D-8**. 2× `PackedFloat32Array` + `PackedInt64Array` pré-alloués capacité 120, indexés `write_idx % CAPACITY`. Calcul p99 à la demande depuis HUD F3, pas dans hot path. |
| ~~Test fixture sans préprocesseur (GDScript) ?~~ | — | — | **RÉSOLUE 2026-04-21 par ADR-0004 D-9**. `OS.has_feature("debug")` runtime + no-op release + `assert`. Injection via `Input.parse_input_event(InputEventAction.new(...))` (seul pattern qui trigger `_unhandled_input`). |
