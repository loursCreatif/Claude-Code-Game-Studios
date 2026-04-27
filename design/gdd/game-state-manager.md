# Game State Manager

> **Status**: APPROVED r1 (2026-04-24 — `/design-review` lean fresh session : verdict initial NEEDS REVISION, 6 fixes éditoriaux appliqués (2 BLOCKING + 4 RECOMMENDED), 1 fix réciproque ADR-0007 D-6, 12 alignements GDD↔ADR validés, scope M ; user accepted revisions → APPROVED)
> **Author**: game-designer + systems-designer + gameplay-programmer (primary/supporting per skill routing)
> **Last Updated**: 2026-04-23 (r1 post-design-review fresh session : status ADR-0007 corrigé Proposed→Accepted r2, header `Detailed Design`→`Detailed Rules` standard-conforme, refs stale `architecture.yaml l.125` remplacées par autorité ADR-0007 D-2, refs "ADR-0011 à venir"→"ADR-0011 (Proposed)", OQ-4/OQ-6 marquées RESOLVED)
> **Implements Pillar**: Pillar 3 (UNE SECONDE CHANCE N'EST JAMAIS LOIN — orchestration respawn < 1 s) + Pillar 1 (FLOW — pause propre, transitions sans stutter)
> **Depends on**: (none — foundation layer) ; consomme one-way `InputManager.application_focus_lost`
> **Depended on by**: Level, Menu, Save/Load, Shop, Camera (via Input refcount), Combat (via Input refcount), Movement, Checkpoint, HUD, Audio
> **Architecture references**: `docs/architecture/architecture.md §6.4`, `docs/registry/architecture.yaml` l.419–422 (one-way `InputManager.application_focus_lost` consumer contract), ADR-0004 D-4 (Input refcount API), **ADR-0007 (Accepted 2026-04-23 r2) — API publique de ce GDD alignée strictement sur ADR-0007 D-10 (API figée MVP) ; enum State autorité = ADR-0007 D-2 (pas registré comme entry architecture.yaml — référence directe ADR-0007 D-2)**. Ce GDD spécifie les comportements **fonctionnels** ; ADR-0007 spécifie les **décisions techniques** (process_mode, connection modes, autoload order). Cohérent bidirectionnel.

## Overview

Le Game State Manager (GSM) est le **chef d'orchestre de run** : un autoload Godot unique qui possède la machine d'état globale de la session (`MENU / PLAYING / PAUSED / RESPAWNING / BOSS_DEFEATED`), orchestre les transitions de scène (Main Menu → Étage N → Shop → Étage N+1 → Credits), pilote le pause global (`get_tree().paused`), et coordonne le refcount d'`InputManager` via les owners `GSMPause` et `GSMRespawning` (ADR-0004 D-4). Il est **foundationnel** : aucun couplage aval n'est autorisé dans son code — il **expose** des signaux (`state_changed`, `scene_transition_requested`, `run_started`, `run_ended`) que les autres systèmes écoutent, et **appelle** des méthodes publiques de ses dépendants (Level.load_etage, Level.unload_current). Le GSM ne connaît rien du gameplay : il ignore les crédits, les ennemis, le katana, les upgrades. Sa seule responsabilité est de garantir que **toute transition d'état du jeu passe par un seul endroit du code**, dans un ordre déterministe, et que les systèmes consommateurs (Level, Menu, Camera, Input, Save/Load, HUD) reçoivent des notifications fiables. Le scope MVP couvre : démarrage de run, transition étage ↔ shop, pause/unpause (menu explicite ou focus loss auto), gestion du respawn window (coordination Movement.died → pause input → Checkpoint.pull → reprise), et retour au menu principal. Boot sequence, crash-safe scene reload, error-path sur `level_load_failed`, et quit propre sont inclus. Le **quit vers le desktop**, les **transitions fade in/out** visuelles, et la **file d'attente de transitions multiples** (rejeter les requêtes concurrentes pendant une transition en cours) sont tous traités par ce système. Aucune logique de gameplay — jamais.

## Player Fantasy

**Cadrage** : système **indirect** — le joueur ne "sent" jamais le GSM en tant que tel. Il sent ce que le GSM **rend possible** : transition invisible entre étage et shop (moins de 1 seconde de noir, jamais un chargement interrompu), respawn qui se déclenche immédiatement après la mort sans que l'input ne "pète" un tick plus tôt ou plus tard que prévu, menu pause qui fige le monde sans glitch de caméra. Le GSM sert donc la **confiance** du joueur dans la stabilité du cadre : la machine ne bloque jamais, n'oublie jamais, ne se dédouble jamais.

### Manifestations indirectes (ce que le joueur perçoit)

| Manifestation | Pilier servi | Mécanisme GSM |
|---------------|--------------|---------------|
| "La mort amène au respawn instantané — je peux retenter sans réfléchir" | Pillar 3 (SECONDE CHANCE) | État `RESPAWNING` pendant `RESPAWN_DELAY = 0.05 s`, orchestre Input.request_disable(GSMRespawning) + Checkpoint pull + release → retour PLAYING |
| "La transition étage → shop est propre, pas de stutter" | Pillar 1 (FLOW) | `scene_transition_requested` émis UN seul coup, chargement async bloqué sur la 1ère frame rendue de la nouvelle scène, aucun double-load possible (transition lock) |
| "Ouvrir le menu ne glitche pas la caméra ni mes inputs" | Pillar 1 (FLOW) | Transition `PLAYING → PAUSED` : `get_tree().paused = true` + `Input.request_disable(GSMPause)` exactement au même tick, signaux `state_changed` émis SYNC dans le même process step |
| "Alt-tab pendant une course ne me fait pas mourir au retour" | Pillar 1 (FLOW) + Pillar 3 | Écoute `application_focus_lost` depuis InputManager → auto-pause en `PLAYING` seulement (ignoré en `MENU` / `PAUSED` déjà) |
| "Quitter le jeu ne corrompt pas ma progression" | Confiance de base | Quit passe systématiquement par `request_quit()` → save appelé SYNC avant `get_tree().quit()` — jamais de quit brut |

### Non-fantasy (anti-perceptions — ce que le joueur ne doit JAMAIS sentir)

- **Un double-respawn** : si `died` est émis 2 fois à la suite (bug amont) → le 2ème est absorbé (idempotence de la transition `PLAYING → RESPAWNING`)
- **Un input qui "traîne"** : si le menu s'ouvre pendant un dash, le dash ne continue pas en arrière-plan (Input.enabled=false coupe l'émission des nouveaux signaux `dash_started`)
- **Un chargement qui dure plus de 1 s sans feedback** : si Level émet `level_load_slow`, le GSM réagit au minimum par un log ; en Vertical Slice+, il pourra afficher une indication UX (hors scope MVP)
- **Un crash silencieux sur transition ratée** : si Level émet `level_load_failed`, le GSM route vers `MENU` avec un message d'erreur — jamais un écran noir figé

## Detailed Rules

### Core Rules

1. **Autoload singleton unique.** `GameStateManager` est enregistré comme autoload Godot (`Project Settings → Autoload`) sous le nom `GameStateManager` — name resolves via `get_node("/root/GameStateManager")`. Le node attache au top level du scene tree et n'est jamais libéré de la durée du process. Aucune autre instance ne peut exister. Le singleton suit la règle projet `class_name` ≠ name d'autoload (mémoire memory) : le `class_name GameStateManagerScript` (suffixe `-Script`) est déclaré en tête du fichier, le nom d'autoload reste `GameStateManager`. Pas de collision identifier.

2. **Machine d'état stricte avec 5 states MVP.** Les 5 states `MENU`, `PLAYING`, `PAUSED`, `RESPAWNING`, `BOSS_DEFEATED` forment l'enum `State`. Tout autre état hypothétique (Cutscene, Loading, Credits) est hors scope MVP ; `BOSS_DEFEATED` est inclus pour le boss final (Full Vision) mais déjà codé au MVP comme terminus propre. Les noms de valeurs enum sont **immutables** — autorité ADR-0007 D-2 (les valeurs ne sont pas registrées comme entry distincte dans `architecture.yaml` au MVP : ADR-0007 D-2 est la source unique de vérité, voir aussi `architecture.yaml` `last_updated` 2026-04-23 confirmant ce choix). Tout renommage requiert amendement ADR-0007 D-2.

3. **Transitions déterministes, API publique figée MVP (ADR-0007 D-10).** Aucun autre système ne peut muter `_current_state`. Le GSM expose **exactement 5 verbes publics** : `start_etage(etage_id: int)`, `request_pause()`, `request_resume()`, `request_scene_transition(scene_path: String)`, `request_new_run()`. Mort et respawn ne sont **pas** des verbes publics — le GSM les consomme via signaux `Player.died / Player.respawned` (ADR-0007 D-7) connectés `CONNECT_DEFERRED` après `level_active`. Chaque verbe est **idempotent** : appeler deux fois `request_pause()` pendant `PAUSED` ne fait rien (pas d'erreur). Les transitions illégales sont `assert()` en debug, no-op + `push_error` en release. **Extension post-MVP** (amendement ADR-0007 requis) : verbes additionnels `request_quit()`, signaux richer (run_started/ended, scene_transition_completed) considérés mais volontairement exclus du MVP pour minimiser surface API.

4. **Un seul `state_changed(new_state)` par transition réelle.** Le signal public est `state_changed(new_state: State)` — **un seul paramètre** (valeur enum, zero-alloc garanti). Émis UNE fois par transition effective via `_transition_to(new_state)`. Il n'est **pas** émis pour un no-op (re-appel idempotent) NI au boot (pattern pull — consumers lisent `get_current_state()` dans leur propre `_ready()`, cf. ADR-0007 D-9). L'émission est **SYNCHRONE** — dans le corps même de `_transition_to()`, avant retour à l'appelant. Les consumers lourds (Audio fade, HUD rebuild) doivent se connecter avec `CONNECT_DEFERRED` côté consumer (pas côté GSM).

5. **Pause discipline : GSM possède l'autorité unique sur `get_tree().paused` (ADR-0007 D-4).** `get_tree().paused = true` est positionné pendant `PAUSED` uniquement (pas pendant RESPAWNING — respawn doit progresser). `process_mode` discipline : GSM + InputManager + AudioSystem + SaveLoadSystem en `PROCESS_MODE_ALWAYS` (continuent sous pause). Movement / Camera / Combat / Level en `PROCESS_MODE_PAUSABLE` (hérité par défaut). Menu UI en `PROCESS_MODE_WHEN_PAUSED`. **Input.enabled disable** : pendant PAUSED, c'est la scène Menu qui `InputManager.request_disable(&"Menu")` (ADR-0004 D-4) — PAS le GSM directement. Pendant RESPAWNING, c'est la CheckpointSystem qui `request_disable(&"Checkpoint")` côté consumer, pas le GSM. Le GSM garde zero couplage avec Input refcount : il ne fait que pauser l'arbre et transitionner l'état. Rationale : découple GSM de l'API Input owner-string.

6. **Two-path scene transition (ADR-0007 D-5).** Deux voies distinctes selon le type de scène : (a) **Scenes menu "container"** (main_menu.tscn, hub_scene.tscn, credits.tscn) passent par `request_scene_transition(scene_path: String)` qui appelle `get_tree().change_scene_to_file(scene_path)` — remplace toute la scène courante, détruit autoloads-non-persistants. (b) **Étages gameplay** (etage_01.tscn...) passent par `start_etage(etage_id: int)` qui appelle `LevelSystem.load_etage(id)` **additive** — instancie l'étage sous root, préserve Player + autoloads (ADR-0011 (Proposed) formalise). Forbidden pattern : `get_tree().change_scene_to_file()` direct depuis Menu / Level / Combat — tout passe par le GSM.

7. **Scene loading discipline.** `request_scene_transition(menu_path)` utilise `change_scene_to_file()` (4.6 stable, loading bloquant mineur mais acceptable pour scenes menu < 500 nodes). Pour étages gameplay, `LevelSystem.load_etage(id)` délègue au Level System qui utilise `ResourceLoader.load_threaded_request` (cf. Level GDD F4 budget 1000 ms). Le GSM ne poll pas les ResourceLoader statuses lui-même — c'est Level qui le fait, et notifie via `level_active`. Rationale : un `load()` bloquant sur étage = stutter visible → Level possède async ; menu transitions rares + courtes = blocking acceptable.

8. **Level integration (ADR-0007 D-5, formalisation ADR-0011 (Proposed)).** Quand `start_etage(etage_id)` est appelé depuis MENU, le GSM : (a) appelle `LevelSystem.load_etage(etage_id)`, (b) attend le signal `LevelSystem.level_active(etage_id, player_start)`, (c) dans le handler `_on_level_active`, connecte `Player.died / Player.respawned` en `CONNECT_DEFERRED` et appelle `_transition_to(PLAYING)`. **Le GSM ne connaît pas la liste des étages** — `etage_id` est passé par l'appelant (Menu, Shop). Registry d'étages vit dans un futur `etage-manifest.tres` (hors scope MVP — 1 seul étage au MVP). L'unload se fait via `level.unload_current()` avant transition vers shop/menu/next étage (owned Level).

9. **Focus loss auto-pause, uniquement en `PLAYING`.** Le GSM se connecte à `InputManager.application_focus_lost` (signal défini par ADR-0004). Handler : si `_current_state == PLAYING`, appelle `request_pause()` ; sinon, no-op silencieux. Il ne se re-connecte PAS à `application_focus_gained` — le joueur doit explicitement fermer son menu pause pour reprendre (règle UX : pas de reprise auto involontaire, ex : alt-tab de 2 s).

10. **Respawn flow : state tracker pur (ADR-0007 D-7).** Le GSM **n'a pas de méthode publique** pour trigger respawn — il est observateur. Dans `_on_level_active(etage_id, player_start)`, connecte `player.died.connect(_on_player_died, CONNECT_DEFERRED)` et `player.respawned.connect(_on_player_respawned, CONNECT_DEFERRED)`. Handler `_on_player_died` : si `_current_state == PLAYING`, `_transition_to(RESPAWNING)`. Handler `_on_player_respawned(spawn_position: Vector3)` : si `_current_state == RESPAWNING`, `_transition_to(PLAYING)`. Le délai `RESPAWN_DELAY = 0.05 s` reste **owned MovementController** (ADR-0005 D-3) — le GSM ne gère pas de timer. **Encapsulation stricte** : le GSM ne mute jamais `player.velocity`, n'appelle jamais `player.die()` ou `player.respawn()`. Pas de safety timeout interne — la responsabilité du respawn propre reste sur MovementController + CheckpointSystem.

11. **Quit = exit_application via main menu.** Le quit propre passe par **le main menu** (bouton "Quitter jeu") qui appelle `get_tree().quit()` directement. Le GSM n'a pas de verbe `request_quit()` MVP. Rationale : minimiser surface API publique GSM (ADR-0007 D-10 figée 5 méthodes). Le save-on-quit est délégué à SaveLoadSystem qui écoute `NOTIFICATION_WM_CLOSE_REQUEST` dans son propre `_notification` handler. **Extension post-MVP** considérée : `request_quit(save_first: bool)` verbe centralisé — requiert amendement ADR-0007 D-10.

12. **Boot sequence déterministe (ADR-0007 D-9).** Au `_ready()` du GSM : (a) `process_mode = Node.PROCESS_MODE_ALWAYS`, (b) `InputManager.application_focus_lost.connect(_on_application_focus_lost)`, (c) valeur initiale `_current_state = State.MENU` (pas d'emit). Si `project.godot` `main_scene = main_menu.tscn`, le boot se fait naturellement sur cette scène. **Pattern pull** : les consumers (Menu, HUD) lisent `GameStateManager.get_current_state()` dans leur propre `_ready()` pour se synchroniser. Pas de `game_booted` signal (minimiser API) — si un consumer a besoin de se synchroniser post-boot, il peut implémenter son propre autoload ordering check.

13. **Scene reload re-wires Player-Camera-Input signals.** Quand un étage gameplay termine et un nouveau démarre via `start_etage(next_id)`, le Player node peut être détruit (selon pattern additive Level) et un nouveau spawnera. Au `level_active` de la nouvelle scène, le GSM re-connecte **les signaux dont il a besoin** : `player.died` et `player.respawned` (handlers internes GSM). Les connexions Camera ↔ Input et Camera ↔ Movement sont **owned par CameraSystem / MovementController eux-mêmes** dans leur `_ready()` — le GSM n'en est pas responsable. Documenté en Edge Case EC-5.

14. **Zéro allocation sur les transitions chaudes.** `state_changed.emit(new_state)` utilise une enum value (int) — pas d'alloc. Aucun `Dictionary` literal, `Array.push_back`, `String.format` dans les handlers de signal ou `request_*` / `_transition_to` methods. Les 5-10 transitions d'une session typique (boot → menu → etage → menu → ...) n'allouent rien au-delà des alloc intrinsèques à `change_scene_to_file` (owned par Godot engine).

15. **Pas de gameplay dans le GSM.** Règle négative stricte : aucun code du GSM ne référence `credits`, `health`, `upgrades`, `katana`, `enemies`. Tout concept gameplay passe par les systèmes dédiés. Si un jour un concept semble appartenir au GSM ("on pause le timer de speedrun au pause"), il doit vivre dans un système dédié qui écoute `state_changed` — pas dans le GSM lui-même. Violation = review bloc.

### States and Transitions

**Enum canonique** (immutable, tracé registry) :

```gdscript
enum State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }
```

**Table des états** :

| State | Entry conditions | Exit conditions | `get_tree().paused` | Typical process_mode behavior | Camera active | Level loaded |
|-------|------------------|------------------|---------------------|-------------------------------|---------------|--------------|
| `MENU` | Boot initial ; retour via `request_scene_transition(main_menu_path)` ; post `request_new_run()` | `start_etage(etage_id)` → PLAYING (après `level_active`) | `false` | Menu UI en `WHEN_PAUSED` → inactif ici (tree not paused). Menu scene has own UI routing. | scene menu (pas gameplay Camera3D) | `null` |
| `PLAYING` | `level_active` reçu après `start_etage` ; `request_resume()` depuis PAUSED ; `player.respawned` depuis RESPAWNING | `request_pause()` → PAUSED ; `player.died` → RESPAWNING ; `etage_completed(boss=true)` → BOSS_DEFEATED ; `etage_completed(boss=false)` / `request_scene_transition(menu)` → MENU | `false` | Movement/Camera/Combat/Level en PAUSABLE → actifs | actif | actif |
| `PAUSED` | `request_pause()` depuis PLAYING ; `application_focus_lost` depuis PLAYING | `request_resume()` → PLAYING ; `request_scene_transition(menu)` → MENU | `true` | PAUSABLE gameplay figé, WHEN_PAUSED menu UI actif | figée (PAUSABLE gated) | en mémoire, gated |
| `RESPAWNING` | `player.died` depuis PLAYING | `player.respawned` (après RESPAWN_DELAY=0.05 s owned Movement) → PLAYING | `false` | PAUSABLE actif (respawn progresse) ; overlay rouge Camera via CameraSystem state-machine interne | freeze rotation (Camera GDD Rule 9) | actif |
| `BOSS_DEFEATED` | `etage_completed` avec flag boss=true depuis PLAYING | `request_new_run()` → MENU ; `request_scene_transition(menu)` → MENU | `false` (MVP — transitoire vers menu credits rapide) | PAUSABLE continue brièvement pour VFX kill | active pour afterimage | active |

**Transitions valides (matrice complète — ADR-0007 D-2)** :

| Depuis → Vers | MENU | PLAYING | PAUSED | RESPAWNING | BOSS_DEFEATED |
|-----|------|---------|--------|------------|---------------|
| **MENU** | — | `start_etage(id)` ✓ (après level_active) | ❌ | ❌ | ❌ |
| **PLAYING** | `request_scene_transition(menu_path)` ✓ / `etage_completed(boss=false)` ✓ | — | `request_pause()` ✓ / `_on_application_focus_lost` ✓ | `_on_player_died` ✓ (CONNECT_DEFERRED) | `etage_completed(boss=true)` ✓ |
| **PAUSED** | `request_scene_transition(menu_path)` ✓ | `request_resume()` ✓ | — | ❌ | ❌ |
| **RESPAWNING** | ❌ | `_on_player_respawned` ✓ (CONNECT_DEFERRED) | ❌ | — | ❌ |
| **BOSS_DEFEATED** | `request_new_run()` ✓ / `request_scene_transition(menu_path)` ✓ | ❌ | ❌ | ❌ | — |

**Pas de `LOADING` state public (ADR-0007 D-2 + D-9).** Les transitions impliquant chargement (start_etage, request_scene_transition) sont atomiques du point de vue des consumers : `state_changed` émis uniquement quand la transition est effective (réception `level_active` pour PLAYING, ou après `change_scene_to_file` complete). Pendant le chargement intermédiaire, le state reste à la valeur précédente. Avantage : les consumers voient soit l'ancien soit le nouveau state — jamais un hybride. La latence perçue (jusqu'à 1000 ms pour étage complet) est absorbée par le Level via `load_threaded_request` (Level GDD Formula 4).

### Interactions with Other Systems

**Liste canonique des peers et flux de données** (direction + interface) :

| Peer system | Direction | Flux |
|-------------|-----------|------|
| **InputManager** | In (one-way) | Consomme `application_focus_lost` (auto-pause PLAYING). **Ne positionne PAS** `Input.enabled` directement — c'est la scène Menu qui pose son propre refcount pendant pause (ADR-0004 D-4 owner `&"Menu"`). InputManager ignore l'existence du GSM. Registry l.419–422 one-way respecté. |
| **LevelSystem** | Bidirectionnel | GSM appelle `LevelSystem.load_etage(id)` depuis `start_etage`. Écoute `level_active(etage_id, player_start)` pour transition PLAYING + re-wire Player signals. Écoute `level_load_failed(etage_id, reason)` pour rester en MENU. Écoute `etage_completed(etage_id, boss_defeated: bool)` pour décider transition MENU vs BOSS_DEFEATED. Level.unload_current() appelé implicitement par change_scene_to_file (si menu scenes) ou orchestré par Shop. |
| **PlayerMovement (MovementController)** | In | Écoute `died` → handler `_on_player_died` CONNECT_DEFERRED → `_transition_to(RESPAWNING)`. Écoute `respawned(spawn_position: Vector3)` → handler `_on_player_respawned` CONNECT_DEFERRED → `_transition_to(PLAYING)`. Les connexions sont établies **dans `_on_level_active` post-spawn** (ADR-0007 D-7), pas dans `_ready()`. MovementController ignore le GSM. |
| **CameraSystem** | Out (indirect) | Le GSM ne parle pas à Camera directement. Camera possède sa propre state-machine Active/Paused/Respawning pilotée par ses propres signaux upstream (Input.enabled + Movement signals, cf. Camera GDD). `state_changed` est public mais Camera ne s'y abonne pas MVP. |
| **SaveLoadSystem (autoload, à écrire)** | Soft | GSM n'appelle pas SaveSystem directement (pas de verbe `request_quit` MVP). SaveSystem écoute `state_changed` pour décider triggers de sauvegarde (ex : save au passage MENU → PLAYING pour snapshot crédits). Quit save = via `NOTIFICATION_WM_CLOSE_REQUEST` handler propre SaveSystem. |
| **MenuSystem (UI)** | Bidirectionnel | Menu lit `get_current_state()` (pattern pull au `_ready`) pour afficher Pause Menu vs Main Menu. Appelle `request_pause()` à l'ouverture du pause menu, `request_resume()` à la fermeture, `request_scene_transition("res://scenes/main_menu.tscn")` au bouton "Quitter vers menu", `get_tree().quit()` direct au bouton "Quitter jeu". GSM ne connaît pas Menu. |
| **ShopSystem** | In | Shop est une scène transitoire entre étages. Accès depuis Level via `etage_completed(etage_id, boss=false)` → GSM transitionne MENU (selon routing MVP 1 étage) ou orchestre load de shop scene Tier 2+ via `request_scene_transition("res://scenes/shop.tscn")`. Shop scene elle-même appelle `start_etage(next_etage_id)` au bouton "Continuer". |
| **HUDSystem** | In | HUD lit `state_changed` pour afficher/masquer le HUD (caché en MENU, visible PLAYING, masqué PAUSED pour ne pas chevaucher menu). Pattern pull au boot via `get_current_state()` pour init visibility. Consomme également `room_entered` mais via Level, pas GSM. |
| **AudioSystem** | In | Audio lit `state_changed` pour ducker la musique en PAUSED (baisser bus volume). Pattern pull au boot via `get_current_state()` pour init bus volumes. |
| **CheckpointSystem** | In | Checkpoint écoute `state_changed(RESPAWNING)` via GSM pour déclencher respawn visuals (CONNECT_DEFERRED). Le timing de respawn reste owned Movement (ADR-0005 D-3) — Checkpoint orchestrate le pull position mais ne notifie pas GSM directement. Le retour PLAYING vient du signal `player.respawned` consommé par GSM. |

**Architecture principle** : le GSM est **central mais unidirectionnel par domaine** : il **lit** les signaux de vie gameplay (died/respawned via CONNECT_DEFERRED, level_active), **appelle** directement les APIs publiques des Core/Feature (`LevelSystem.load_etage`, `get_tree().change_scene_to_file`), et **notifie** via `state_changed` les observateurs passifs (HUD, Audio, Menu). `get_current_state()` est une copie d'enum value (zero-alloc).

**Règle négative cross-system** : **jamais** un système ne peut muter `_current_state` par setter public. Le GSM n'expose PAS `set_current_state()`. Les seules entrées de mutation sont les 5 verbes publics ADR-0007 D-10 (`start_etage`, `request_pause`, `request_resume`, `request_scene_transition`, `request_new_run`) + 2 handlers de signaux internes (`_on_player_died`, `_on_player_respawned`). Garantit qu'aucune transition illégale ne peut être forcée par un bug amont.

## Formulas

Le Game State Manager est un système d'orchestration — il contient peu de calcul numérique. Les formules ci-dessous décrivent les **fenêtres temporelles** et les **bornes de budget** qui contraignent l'implémentation.

### Formula 1 — Scene transition latency budget

Le budget de transition de scène (étage → shop, étage → étage suivant, menu → étage) doit rester sous un seuil perceptuel pour préserver Pillar 1 FLOW.

`transition_total_ms = LOAD_ASYNC_MS + FREE_OLD_SCENE_MS + FIRST_FRAME_MS`

**Variables :**

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| `LOAD_ASYNC_MS` | `L_a` | int (ms) | [200, 1000] | Durée du `ResourceLoader.load_threaded_get_status()` jusqu'à `THREAD_LOAD_LOADED`. Budget Level GDD Formula 4 = 1000 ms max pour un étage 10 salles. |
| `FREE_OLD_SCENE_MS` | `L_f` | int (ms) | [5, 50] | Durée de l'unload précédent (`old_scene.queue_free()` + wait 1 frame). Négligeable sur scènes < 500 nodes. |
| `FIRST_FRAME_MS` | `L_1` | int (ms) | [16, 50] | Durée du premier frame rendu de la nouvelle scène — inclut shader warmup. ADR-0003 Shader Baker réduit cette valeur. |

**Output Range** : [221, 1100] ms normal, cible MVP < 1200 ms total.
**Hard cap** : si `transition_total_ms > 2000`, émettre `scene_transition_slow(total_ms)` (advisory). Plus de 3000 ms = log CRITICAL en telemetry (hors scope MVP).

**Example** : Étage → Shop typique : `L_a = 250` (shop scène 80 nodes), `L_f = 15`, `L_1 = 20` (shader baker hit) → total = **285 ms**. ✅ sous seuil perceptuel ~300 ms.

**Example worst case** : Étage → Next Étage : `L_a = 900` (étage 10 salles), `L_f = 20`, `L_1 = 30` → **950 ms**. ✅ sous cap 1200 ms.

**Rationale** : la fenêtre 1200 ms inclut une marge de 20 % sur le budget Level (1000 ms). Le GSM ne contrôle pas `L_a` (c'est Level) — il monitor et route le fallback `scene_transition_slow`.

### Formula 2 — Respawn window duration

`respawn_window_ms = RESPAWN_DELAY × 1000`

**Variables :**

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| `RESPAWN_DELAY` | `R_d` | float (seconds) | [0.03, 0.2] | Registry constante, owned Movement. Valeur MVP : **0.05 s**. Source : registry `RESPAWN_DELAY`. |

**Output Range** : [30, 200] ms. Value MVP = **50 ms = 3 physics ticks @ 60 Hz**.

**Invariant impératif** (hérité registry notes) : `RESPAWN_DELAY ≥ 1 / DISPLAY_TICK_RATE` = 16.6 ms — garantit que les consumers en `CONNECT_DEFERRED` du signal `died` voient bien la transition avant reprise gameplay. À 60 Hz : 50 ms = 3 frames → 3 trames de marge pour les handlers deferred. ✅

**Example** : Joueur meurt au tick T, `notify_player_died()` fires au tick T, `state_changed(PLAYING, RESPAWNING)` SYNC au même tick. Checkpoint pull lance un timer 50 ms (`Timer.wait_time = 0.05`). À T+3 ticks, Checkpoint téléporte player et appelle `notify_respawn_complete()` → `state_changed(RESPAWNING, PLAYING)`. Durée effective : **50 ms = 3 ticks**.

### Formula 3 — Transition lock timeout (DÉLÉGUÉ Level System)

Le timeout des chargements d'étage gameplay est **owned par Level System** (Level GDD Formula 4, budget 1000 ms, signal `level_load_slow` à 500 ms). Le GSM ne possède **pas** de timer de timeout propre MVP — il attend `level_active` ou `level_load_failed` indéfiniment. Pour les transitions menu via `change_scene_to_file`, Godot bloque brièvement le thread principal (scenes < 500 nodes → < 200 ms typique) ; aucun timeout GSM nécessaire.

**Post-MVP extension** considérée : timer GSM `TRANSITION_LOCK_HARD_CAP_MS = 5000 ms` comme safety net si Level ne répond pas. Requiert amendement ADR-0007 D-5 pour formaliser le cancel path. Reporté à Sprint Menu / Checkpoint.

### Formula 4 — Pause propagation latency

Latence entre requête de pause et effet complet (gameplay figé).

`pause_propagation_ms = STATE_MUTATION_MS + TREE_PAUSED_PROP_MS`

**Variables :**

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| `STATE_MUTATION_MS` | `P_s` | float (ms) | [0, 1] | Coût mutation `_current_state = PAUSED` + signal emit. Négligeable (~0 ms). |
| `TREE_PAUSED_PROP_MS` | `P_t` | float (ms) | [0, 16.6] | Délai entre `get_tree().paused = true` et la prochaine frame où `_process/_physics_process` sont gated sur nodes PAUSABLE (Godot propage en fin de frame courante — worst case 1 frame). |

**Output Range** : [0, ~17 ms] worst case = **1 frame @ 60 Hz**.

**Invariant** : le GSM mute `_current_state` ET pose `get_tree().paused` dans la **même méthode** `_transition_to(new_state)`, **dans cet ordre**, **SYNC avant retour**. Le signal `state_changed(new_state)` est émis APRÈS les deux mutations pour que les consumers voient déjà l'état cohérent.

**Example** : Joueur presse ESC au tick T. Menu scene reçoit action, appelle `GameStateManager.request_pause()` au tick T. GSM mute state, pause tree, emit signal SYNC. Au tick T+1 : `_physics_process` gated sur Player/Camera/Combat. **Latence utilisateur : 1 frame** (16.6 ms). Input disable owned scène Menu (pose son `request_disable(&"Menu")` dans son propre `_ready()` pause scene).

### Formula 5 — State transition determinism (no formula, but invariant)

Aucune formule — règle binaire. Chaque transition est vérifiée par une table de validité (voir Matrice Transitions Section C). L'invariant associé :

`∀ verb ∈ public_verbs, (old_state, verb) → new_state ∈ valid_transitions(old_state) ∨ no_op`

Si `(old_state, verb) → illégal` : debug build = `assert(false, "GSM: illegal transition %s in state %s" % [verb, old_state])` ; release build = `push_error(...)` + no-op. **Aucune exception** : pas de "try to apply anyway" — les transitions illégales sont des bugs amont à corriger, pas à tolérer.

## Edge Cases

### EC-1 — `Player.died` émis 2× rapidement (double-mort)

- **If** `died` est émis deux fois dans la même frame ou à 1 frame d'écart (bug amont Movement, cas hors prod mais possible en développement) **:** la 2ème notification est **absorbée** — le handler `_on_player_died()` vérifie `if _current_state != PLAYING: return` (idempotence ADR-0007 D-7). Pas d'erreur, pas de double transition `state_changed`. En debug build : `push_warning("GSM: _on_player_died while %s — ignored" % [_current_state])`.

### EC-2 — `application_focus_lost` reçu pendant `RESPAWNING`

- **If** le joueur alt-tab pendant la fenêtre 50 ms de respawn **:** le GSM **ne transite pas** vers PAUSED. `RESPAWNING → PAUSED` est illégale (voir matrice). Le handler `_on_application_focus_lost` vérifie `if _current_state != PLAYING: return` (ADR-0007 D-6). Le respawn se termine normalement (Player émet `respawned` → PLAYING). Le signal focus_lost est edge-triggered côté InputManager → pas de file d'attente. **Conséquence acceptable** : si le focus reste perdu au retour PLAYING, le joueur revient en PLAYING avec focus perdu — au prochain focus_lost il sera auto-paused.

### EC-3 — `request_scene_transition` pendant une autre transition

- **If** un deuxième `request_scene_transition(path)` est appelé alors que Godot exécute déjà un `change_scene_to_file` précédent (rare — Godot sérialise les appels) **:** le 2ème appel remplace le précédent dans la file. Pas de lock interne GSM MVP — Godot gère sa propre sérialisation. **Rationale** : minimiser complexité, faire confiance à Godot. Si double-transition cause des bugs observés en Tier 2, amendement ADR-0007 D-5 pour introduire un `_transition_in_progress` flag.

### EC-4 — `LevelSystem.load_etage` échoue (`level_load_failed` reçu)

- **If** Level émet `level_load_failed(etage_id, reason)` après `start_etage(etage_id)` **:** le handler GSM `_on_level_load_failed` : (a) `push_error("GSM: level_load_failed etage_id=%d reason=%s" % [etage_id, reason])`, (b) reste en `MENU` car `level_active` n'a pas été reçu (pas de transition vers PLAYING), (c) le Menu scene reste courante. Le Menu peut afficher une pop-up d'erreur via sa propre connexion au signal Level. **Rationale** : jamais d'écran noir figé. Menu toujours reachable.

### EC-5 — Nouveau Player après `level_active` — GSM re-wire ses propres signaux

- **If** un nouveau Player node est spawné dans la scène étage chargée qui émet `level_active(etage_id, player_start)` **:** le handler GSM `_on_level_active` (ADR-0007 D-7) : (a) `get_tree().get_first_node_in_group("player")` pour retrouver le Player frais, (b) assert player != null, (c) connect `player.died.connect(_on_player_died, CONNECT_DEFERRED)`, (d) connect `player.respawned.connect(_on_player_respawned, CONNECT_DEFERRED)`, (e) `_transition_to(PLAYING)`. **Les connexions Camera ↔ Input et Camera ↔ Movement sont owned Camera/Movement** dans leurs propres `_ready()` — pas responsabilité GSM. **If** `player == null` **:** `push_error("GSM: player missing after level_active — scene authoring bug")` → idéalement Level détecte ce cas en amont et émet `level_load_failed` au lieu.

### EC-6 — Quit du jeu (delegate to Menu + SaveSystem, pas de verbe GSM MVP)

- **If** le joueur clique "Quitter jeu" dans le menu pause ou le menu principal **:** c'est la scène Menu qui appelle `get_tree().quit()` directement. Le GSM n'a **pas** de verbe `request_quit()` MVP (ADR-0007 D-10). Le save-on-quit est owned par SaveLoadSystem via `NOTIFICATION_WM_CLOSE_REQUEST` handler. **Si** le quit arrive en state PAUSED : `get_tree().paused == true` ne bloque pas `quit()` (callé sur SceneTree direct). **Si** le quit arrive en RESPAWNING : le respawn est abandonné, SaveSystem récupère le state pre-mort via son propre buffer checkpoint.

### EC-7 — Focus regained pendant `PAUSED` (menu ouvert)

- **If** le joueur alt-tab revient sur le jeu alors que Menu Pause est ouvert (state PAUSED) **:** **rien ne se passe côté GSM**. `application_focus_gained` n'est pas écouté (règle Core 9). Le joueur doit explicitement fermer le menu pause pour reprendre. Rationale UX : évite un unpause accidentel si le joueur alt-tab rapide (ex : notification Discord) et revient — il veut probablement rester pause quelques secondes.

### EC-8 — Deux consumers écoutent `state_changed` avec coûts > 1 frame

- **If** HUD et Audio sont tous deux connectés à `state_changed` en SYNC et l'un d'eux (Audio) prend 3 ms pour fade out la musique **:** l'émission SYNC bloque `request_pause()` pendant ~3 ms. **Solution recommandée ADR-0007 Contract signals** : les consumers lourds se connectent en `CONNECT_DEFERRED` côté consumer. Convention documentée — pas enforcée par GSM. Edge case détecté si telemetry agrège > 5 ms → push_warning en debug.

### EC-9 — `Player.died` pendant `MENU` ou `BOSS_DEFEATED`

- **If** un bug amont (Movement en scène menu pour une raison exotique) émet `died` en MENU ou BOSS_DEFEATED **:** le handler `_on_player_died` vérifie `if _current_state != PLAYING: return`. Idempotent, push_warning debug. Pas de transition.

### EC-10 — Scène `main_menu.tscn` manquante au boot

- **If** `project.godot` pointe vers une `main_scene = main_menu.tscn` absente **:** Godot lui-même ne peut pas démarrer et affiche un écran d'erreur moteur. Hors scope GSM — c'est une erreur de packaging, pas un bug runtime. Responsabilité : release-manager + CI de packaging.

### EC-11 — `start_etage(etage_id)` avec id invalide

- **If** Menu appelle `start_etage(etage_id=42)` et aucun fichier `res://scenes/levels/etage_42.tscn` n'existe **:** le GSM appelle `LevelSystem.load_etage(42)`. Level résout le chemin, `ResourceLoader.load_threaded_request` retourne INVALID_RESOURCE, Level émet `level_load_failed(42, &"invalid_etage_id")`. GSM reçoit via EC-4 flow → reste en MENU. Pas de crash.

### EC-12 — `Player.respawned` jamais émis (Movement bug)

- **If** MovementController oublie d'émettre `respawned` après `RESPAWN_DELAY = 0.05 s` (bug amont) **:** le GSM reste bloqué en RESPAWNING indéfiniment — Input gameplay toujours coupé côté Movement (ADR-0005 D-3 owns timing), pas d'interruption GSM. **ADR-0007 D-7 laisse le timing à Movement** : pas de safety timeout GSM MVP. **Post-MVP mitigation** : ajouter `RESPAWN_SAFETY_TIMEOUT_MS = 500 ms` force-exit (hors scope MVP, requiert amendement ADR-0007 D-7). Symptôme visible au QA = softlock respawn → blame Movement System, pas GSM.

### EC-13 — `etage_completed(boss=true)` pendant PAUSED

- **If** Level émet `etage_completed(boss=true)` pendant state PAUSED (test malformé ou bug Level) **:** transition PAUSED → BOSS_DEFEATED est illégale (voir matrice). Handler GSM vérifie `if _current_state != PLAYING: return`. Assert debug, no-op release, push_error. **Rationale** : seul PLAYING peut transiter vers BOSS_DEFEATED — le boss est mort pendant qu'on joue, pas pendant qu'on regarde un menu.

## Dependencies

### Upstream (GSM dépend de)

Le GSM est **foundationnel par définition** : il ne dépend d'aucun autre système de gameplay. Les seules dépendances sont :

| System | Statut | Nature | Interface consommée |
|--------|--------|--------|---------------------|
| **InputManager** | Accepted ADR-0004 (GDD In Review r4) | Soft (one-way consumer) | Signal `application_focus_lost` connecté SYNC dans `_ready()` (ADR-0007 D-6). **Aucun appel** à `request_disable` ou autre API Input depuis le GSM MVP (scope minimal). |
| **Godot SceneTree** | Engine (Godot 4.6) | Hard (engine primitive) | `get_tree().paused: bool` (autorité unique GSM, ADR-0007 D-4), `get_tree().change_scene_to_file(path)` (scenes menu uniquement, D-5), `get_tree().get_first_node_in_group("player")` (re-wire post level_active). |

**Règle d'architecture** : GSM est autoload Foundation — aucune dépendance amont gameplay. Un ajout de dépendance amont gameplay (ex : Movement) serait une violation bloc du layering.

### Downstream (systèmes qui dépendent du GSM)

| System | Statut | Nature | Contrat consommé depuis GSM |
|--------|--------|--------|------------------------------|
| **LevelSystem** | APPROVED r3 | Hard — lifecycle owner | GSM appelle `LevelSystem.load_etage(id)` depuis `start_etage`. Écoute `level_active / level_load_failed / etage_completed(boss_defeated)`. Level.unload_current() géré par scène Shop ou par `change_scene_to_file(menu)`. |
| **MenuSystem** (inferred, Not Started) | Hard | Lit `get_current_state()` pattern pull au `_ready`, écoute `state_changed`. Appelle les 5 verbes MVP : `request_pause / request_resume / start_etage(id) / request_scene_transition(menu_path) / request_new_run`. Quit direct via `get_tree().quit()`. |
| **SaveLoadSystem** (inferred, Not Started) | Soft | Écoute `state_changed` pour triggers save. Quit save via propre handler `NOTIFICATION_WM_CLOSE_REQUEST` — pas d'orchestration GSM MVP. |
| **CheckpointSystem** (inferred, Not Started) | Soft | Écoute `state_changed(RESPAWNING)` CONNECT_DEFERRED pour déclencher respawn visuals. Le timing respawn reste owned Movement (ADR-0005 D-3). Retour PLAYING vient de `player.respawned` consommé par GSM. |
| **ShopSystem** (inferred, Not Started) | Hard (Tier 2+) | Shop scene chargée via `request_scene_transition("res://scenes/shop.tscn")` (hors scope MVP 1 étage). Au bouton "Continuer", Shop appelle `start_etage(next_etage_id)`. |
| **HUDSystem** (inferred, Not Started) | Soft | Écoute `state_changed` + pattern pull au boot. Visibility logic. Read-only consumer. |
| **AudioSystem** (inferred, Not Started) | Soft | Écoute `state_changed` pour ducking pause. Pattern pull au boot. Read-only consumer. |
| **CameraSystem** | In Review r2 | Indirect | Pas de couplage direct. Camera possède sa propre state machine pilotée par Input.enabled + Movement signals. |
| **PlayerMovement (MovementController)** | In Review r3 | In (GSM consume) | GSM écoute `died` / `respawned(spawn_position)` signaux Movement (ADR-0005) via CONNECT_DEFERRED établi dans `_on_level_active`. MovementController ignore le GSM. |
| **PlayerCombat** | Approved r6 | Indirect | Pas de couplage direct. Combat en pause effective via `get_tree().paused = true` + `PROCESS_MODE_PAUSABLE` héritage (ADR-0007 D-4). |

### Interface publique verrouillée (API contract — ADR-0007 D-10)

Ce bloc est **la source de vérité** pour les implementers, strictement aligné sur ADR-0007 D-10 ("API publique figée MVP").

```gdscript
class_name GameStateManagerScript
extends Node

# ─── ENUM (immutable — autorité ADR-0007 D-2) ─────────────────────────────
enum State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }

# ─── SIGNALS (outbound — 1 signal total MVP) ──────────────────────────────
signal state_changed(new_state: State)
# - 1 paramètre (enum value = int, zero-alloc)
# - Émis SYNCHRONE depuis _transition_to(new_state), UNE fois par transition effective
# - PAS émis pour no-op (idempotent)
# - PAS émis au boot (pattern pull — consumers lisent get_current_state() dans leur _ready)
# - Consumers lourds se connectent en CONNECT_DEFERRED côté consumer

# ─── PUBLIC VERBS — 5 méthodes MVP figées ─────────────────────────────────
func start_etage(etage_id: int) -> void
# Transition : MENU → (async load via Level) → PLAYING
# Assert : _current_state == MENU
# Appelle LevelSystem.load_etage(etage_id), attend level_active pour transition

func request_pause() -> void
# Transition : PLAYING → PAUSED (idempotent, no-op si PAUSED ou autre)
# Pose get_tree().paused = true

func request_resume() -> void
# Transition : PAUSED → PLAYING (idempotent, no-op si PLAYING ou autre)
# Pose get_tree().paused = false

func request_scene_transition(scene_path: String) -> void
# Transition : * → MENU (ou hub_scene, credits)
# Utilise get_tree().change_scene_to_file(scene_path)
# Usage limité aux scenes menu "container" — PAS pour étages gameplay (cf. start_etage)

func request_new_run() -> void
# Transition : BOSS_DEFEATED → MENU
# Usage spécifique end-screen "New Run" ; alias de request_scene_transition(main_menu_path)
# depuis BOSS_DEFEATED uniquement

# ─── PUBLIC GETTERS (read-only, thread-safe) ──────────────────────────────
func get_current_state() -> State                        # copy of enum value, zero-alloc

# ─── PRIVATE (centralisation transitions — ne pas appeler externe) ────────
func _transition_to(new_state: State) -> void            # centralise toutes les transitions
func _on_application_focus_lost() -> void                # handler ADR-0004 D-5
func _on_level_active(etage_id: int, player_start: Vector3) -> void  # connecte died/respawned
func _on_player_died() -> void                           # CONNECT_DEFERRED depuis Player
func _on_player_respawned(spawn_position: Vector3) -> void  # CONNECT_DEFERRED depuis Player
```

**Signatures verrouillées** : les types, noms et ordres de paramètres sont **immutables** — alignement strict sur ADR-0007 D-10. Toute extension (ex : `request_quit`, signaux additionnels) exige un amendement ADR-0007.

**Convention d'idempotence** : tout verbe public vérifie le state courant en tête de méthode, `return` si no-op ou illégal (avec `assert` en debug, `push_error` en release — pas de crash).

### Notes de réciprocité

- `design/gdd/level-system.md` §Dependencies Upstream cite déjà : "Game State Manager | Lifecycle owner — appelle `load_etage()` / `unload_current()`". ✅ bidirectionnel.
- `design/gdd/camera-system.md` cite Game State Manager ligne 114, 220, 240. ✅ bidirectionnel (Camera ne dépend pas directement mais documente l'existence du contrôleur).
- `design/gdd/player-combat-system.md` cite Game State Manager ligne 277 (pause global). ✅ bidirectionnel.
- `design/gdd/player-movement-system.md` : Movement ne cite pas explicitement GSM mais son lifecycle (died/respawned) est consommé par GSM. Pas de réciprocité formelle requise — Movement ignore GSM par design.
- `design/gdd/input-system.md` : InputManager est consommé one-way par GSM (`application_focus_lost`). Documenté en registry `architecture.yaml` l.419–422. ✅

**Forward-looking réciprocité** (GDDs pas encore écrits) :
- `design/gdd/menu-system.md` (à écrire) → §Dependencies Upstream doit citer GSM comme contrôleur de state, avec les 8 verbes utilisés.
- `design/gdd/save-load-system.md` (à écrire) → §Dependencies doit citer GSM comme émetteur de `run_started`, `run_ended`, `game_quitting`.
- `design/gdd/checkpoint-system.md` (à écrire) → §Dependencies doit citer GSM pour `state_changed(_, RESPAWNING)` trigger et appel `notify_respawn_complete()`.
- `design/gdd/shop-system.md` (à écrire) → §Dependencies doit citer GSM pour `request_scene_transition` et `start_run(next_etage_id)`.
- `design/gdd/hud-system.md`, `audio-system.md` (à écrire) → §Dependencies doivent citer GSM comme source de `state_changed`.

## Tuning Knobs

Le GSM est un système d'orchestration — il a peu de knobs designer-tweakables. Les knobs ci-dessous sont des **budgets runtime** et **flags de debug**, pas des valeurs de game feel.

| Knob | Default | Safe Range | Unit | What it affects | Out-of-range behavior |
|------|---------|------------|------|------------------|------------------------|
| `FOCUS_LOSS_AUTO_PAUSE_ENABLED` | true | {true, false} | bool | Active/désactive l'auto-pause sur `application_focus_lost`. Utile pour debug (disable pour éviter pause en break dev). | false : joueur alt-tab continue à jouer en arrière-plan (potentiel FOV/death indésirable). Production toujours true. |
| `DEBUG_LOG_STATE_TRANSITIONS` | false | {true, false} | bool | Si true, chaque `state_changed` émet un `print_rich("[GSM] → %s" % [new_state])` en console. OFF en release. | true en release : spam console. Désactiver via `OS.has_feature("debug")`. |

**Post-MVP tuning knobs considérés** (amendement ADR-0007 requis) :
- `TRANSITION_LOCK_HARD_CAP_MS` (5000 ms) — safety net timeout si Level ne répond pas
- `SCENE_TRANSITION_SLOW_THRESHOLD_MS` (1000 ms) — seuil d'émission `scene_transition_slow`
- `RESPAWN_SAFETY_TIMEOUT_MS` (500 ms) — timer force-exit RESPAWNING
- `QUIT_SAVE_TIMEOUT_MS` (200 ms) — budget save au quit

**Knobs hors scope MVP** :
- Liste des étages et leur ordre (futur `design/registry/etage-manifest.tres` — hors MVP)
- Timing du menu pause ouvert/fermé (owned Menu System)
- Paramètres de fade visuel de transition (si implémenté post-MVP, owned scene Menu ou VFX, pas GSM)

## Visual/Audio Requirements

Le GSM lui-même **n'a pas de manifestation visuelle ou audio directe** — c'est une Foundation layer. Les effets visuels et audio associés aux changements d'état sont **délégués** à d'autres systèmes :

| Event déclencheur GSM | Conséquence visuelle/audio | Système owner |
|------------------------|-----------------------------|---------------|
| `state_changed(PLAYING, PAUSED)` | Fade musique à -12 dB (duck), affichage menu pause overlay | AudioSystem, MenuSystem |
| `state_changed(PLAYING, RESPAWNING)` | Fondu rouge 40 ms, son `death.wav`, freeze rotation caméra | CameraSystem (overlay), AudioSystem (SFX), MovementController (die) |
| `state_changed(RESPAWNING, PLAYING)` | Fondu out rouge, son `respawn.wav`, reprise caméra | CameraSystem, AudioSystem |
| `scene_transition_requested` | Black fade-out 200 ms (CanvasLayer transient) | **GSM possède ce `CanvasLayer`** — seule exception visuelle (voir ci-dessous) |
| `scene_transition_completed` | Black fade-in 200 ms | GSM |
| `notify_boss_defeated()` | Ralenti global + jingle "boss down" + credits scroll | AudioSystem, HUDSystem, post-MVP credits scene |
| `game_booted()` | Dismiss splash screen éventuel | BootScene standalone |

### Exception : Transition Fade Overlay (owned GSM)

Le GSM possède **un unique `CanvasLayer` top-most, `_transition_overlay`**, dédié à masquer visuellement les transitions de scène. Spec :

- **Nœud** : `CanvasLayer` + `ColorRect` (fill viewport, color black)
- **Visibilité** : `modulate.a = 0.0` par défaut, monte à `1.0` pendant la phase de unload + load, redescend à `0.0` au `level_active` de la nouvelle scène.
- **Fade-out duration** : 200 ms (quand on quitte une scène)
- **Fade-in duration** : 200 ms (quand on arrive sur une nouvelle scène)
- **Hold** : durée variable (le temps du chargement — Formula 1)
- **Layer order** : `layer = 100` — au-dessus de HUD, Menu, overlays gameplay
- **Process mode** : `PROCESS_MODE_ALWAYS` — immune au `get_tree().paused`

**Justification** : cacher le moment où `get_tree().change_scene_to_packed` se produit (le premier frame de la nouvelle scène peut avoir des artefacts — placement non encore fait, shader warmup). Pillar 1 FLOW : jamais un stutter visible. Le fade masque 100% de la transition visuelle.

**Rationale** : pourquoi GSM et pas CameraSystem/VFXSystem ? Parce que ce fade doit survivre à la destruction ET du Camera ET du VFX (qui sont dans la scène gameplay unloadée). Seul le GSM, autoload persistant, peut garantir la continuité.

### Audio mixing (règles à respecter côté AudioSystem quand il sera écrit)

- Pendant `state_changed(*, PAUSED)` : duck bus `Music` à -12 dB en 100 ms, bus `SFX` à -24 dB (quasi mute), bus `UI` inchangé (menu sounds plein volume)
- Pendant `state_changed(PAUSED, PLAYING)` : reverse en 100 ms
- Pendant `scene_transition_*` : pas de duck spécifique GSM, mais Audio peut crossfade musique étage A → étage B sur `scene_transition_completed`
- Pendant `state_changed(_, RESPAWNING)` : stop all gameplay sounds (laser, dash, wall-run) ; seul `death.wav` joue

## UI Requirements

Le GSM **n'a aucune UI propre** au sens widgets/menus. Sa seule surface UI est le **transition fade overlay** spec Visual/Audio ci-dessus (c'est un `ColorRect`, pas un menu).

Toutes les UIs état-dépendantes (Pause Menu, Main Menu, HUD, Shop UI, Credits) sont **portées par leurs systèmes respectifs** qui s'abonnent à `state_changed` pour leur visibility :

| UI surface | System owner | GSM signal consumed |
|------------|--------------|----------------------|
| Main Menu (écran titre) | MenuSystem | `state_changed(*, MENU)` → show |
| Pause Menu (overlay) | MenuSystem | `state_changed(PLAYING, PAUSED)` → show ; `(PAUSED, *)` → hide |
| HUD (crédits, checkpoint indicator) | HUDSystem | `state_changed(*, PLAYING)` → show ; `(*, PAUSED)` → hide (optionnel — spec HUD) ; `(*, MENU)` → hide |
| Shop UI | ShopSystem | GSM pilote le chargement de la scène shop.tscn qui embarque sa propre UI |
| Death screen (r1 MVP : aucun, respawn instantané) | CameraSystem (overlay rouge) | État RESPAWNING pilote Camera overlay via Input.enabled=false ; pas d'UI menu |
| Credits screen (Full Vision) | dedicated scene, chargée après `notify_boss_defeated` | `scene_transition_requested("res://scenes/credits.tscn", &"boss_completed")` |

**📌 UX Flag — Game State Manager** : ce système expose des API UI (verbes `request_pause`, `return_to_menu`, `request_quit`) appelées par MenuSystem. Le flux UX complet (Main Menu → jouer → Pause Menu → settings → quit) vit dans `design/ux/main-menu.md` et `design/ux/pause-menu.md` (à écrire en Phase 4 via `/ux-design`). Les stories MenuSystem devront citer ces fichiers UX, pas le GDD GSM directement.

### UI timing contracts

- **Pause menu doit apparaître < 100 ms** après clic ESC (du press à visible full opacity). GSM contribue ≤ 33 ms (Formula 4) ; les 67 ms restants sont pour le fade in UI côté Menu.
- **Transition fade-out doit être imperceptible < 200 ms** (pas de "je vois un éclair noir avant de partir"). Le fade démarre dès `request_scene_transition` ACCEPTÉ.
- **Black screen hold** : jamais > 1000 ms sans un feedback (ce qui est géré par `scene_transition_slow` signal — Menu peut afficher un spinner sur ce signal en Tier 2+, hors scope MVP MVP = hold silencieux jusqu'à 1200 ms).

## Acceptance Criteria

Total ACs : 18 (Groupe A boot × 3 + Groupe B transitions × 5 + Groupe C pause × 3 + Groupe D respawn × 3 + Groupe E scene × 2 + Groupe F perf × 2).

### Groupe A — Boot & Lifecycle

- **AC-GSM-1** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** le process Godot vient de démarrer, **WHEN** `_ready()` du GSM autoload s'exécute, **THEN** `get_current_state() == State.MENU`, `process_mode == PROCESS_MODE_ALWAYS`, et **aucun** `state_changed` n'est émis (pattern pull). *Covers Rule 12 + ADR-0007 D-9.*

- **AC-GSM-2** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** le GSM et InputManager sont instanciés, **WHEN** GSM `_ready()` exécute, **THEN** `InputManager.application_focus_lost` est connecté au handler GSM (vérifiable via `signal.get_connections()`), mode SYNC (pas CONNECT_DEFERRED per ADR-0007 D-6). *Covers Rule 9.*

- **AC-GSM-3** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** `state == MENU`, **WHEN** `start_etage(etage_id=1)` est appelé, **THEN** `LevelSystem.load_etage(1)` est appelé, `state_changed` n'est **pas** émis avant que `level_active(1, player_start)` soit reçu ; **THEN** sur réception du signal, `state_changed(PLAYING)` émis 1 fois et `_transition_to(PLAYING)` atomique. *Covers Rule 8 + ADR-0007 D-5.*

### Groupe B — State Transitions Validity

- **AC-GSM-4** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** une debug build avec `assert` actif, **WHEN** une transition illégale est tentée (ex : appel direct de `_transition_to(RESPAWNING)` depuis MENU via reflection de test), **THEN** `assert(false)` fail en debug avec message `"GSM: illegal transition %s → %s"`. En release : `push_error` + no-op, `_current_state` inchangé. *Covers Rule 3 + Formula 5.*

- **AC-GSM-5** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `state == PLAYING`, **WHEN** `request_pause()` est appelé 3 fois consécutives dans le même frame, **THEN** `state_changed(PAUSED)` est émis exactement 1 fois, `get_tree().paused == true` reste true. *Covers Rule 3 — idempotence.*

- **AC-GSM-6** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `state == PAUSED`, **WHEN** `request_resume()` est appelé, **THEN** `state_changed(PLAYING)` est émis SYNC avant retour de la méthode, `get_tree().paused == false` au même tick. *Covers Rule 4 + Rule 5 + Formula 4.*

- **AC-GSM-7** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** la matrice complète des transitions (voir Section C matrice), **WHEN** un test GUT itère chaque (old_state, verb_ou_signal) combination, **THEN** toutes les transitions listées valides réussissent (state_changed émis avec new_state attendu), toutes les listées illégales sont no-op + push_error. *Covers Rule 3 + matrice.*

- **AC-GSM-8** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `state == PLAYING`, **WHEN** le GSM reçoit `InputManager.application_focus_lost`, **THEN** `state_changed(PAUSED)` est émis 1 fois ; **WHEN** même signal reçu en `state == PAUSED` ou `MENU`, **THEN** aucun `state_changed` n'est émis (handler early-return conditionnel). *Covers Rule 9 + EC-2 + ADR-0007 D-6.*

### Groupe C — Pause Semantics

- **AC-GSM-9** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `state == PAUSED`, **WHEN** on mesure `get_tree().paused`, **THEN** = `true` ; **WHEN** le state bascule PAUSED → PLAYING, **THEN** `get_tree().paused == false` au même tick que `state_changed(PLAYING)` émis. *Covers Rule 5 + ADR-0007 D-4 — autorité unique pause.*

- **AC-GSM-10** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** une debug build avec grep CI sur `src/`, **WHEN** on cherche `get_tree().paused = ` en dehors de `src/core/game_state_manager.gd`, **THEN** aucun résultat. *Covers ADR-0007 D-4 forbidden pattern — autorité unique.*

- **AC-GSM-11** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** le joueur joue, **WHEN** il alt-tab (OS-level focus loss), **THEN** dans les 2 frames le state passe à PAUSED, `get_tree().paused == true` ; en alt-tab retour (focus_gained), le state **reste PAUSED** jusqu'à `request_resume` explicite. *Covers Rule 9 + EC-7 — auto-pause UX no auto-resume.*

### Groupe D — Respawn Orchestration

- **AC-GSM-12** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `state == PLAYING` avec Player spawné, **WHEN** MovementController émet `died`, **THEN** dans les 1 frame (DEFERRED), GSM handler `_on_player_died` exécute, `_transition_to(RESPAWNING)` appelé, `state_changed(RESPAWNING)` émis. *Covers Rule 10 + ADR-0007 D-7.*

- **AC-GSM-13** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `state == RESPAWNING` depuis N ticks (RESPAWN_DELAY owned Movement), **WHEN** Player émet `respawned(spawn_position)`, **THEN** dans les 1 frame DEFERRED, `_on_player_respawned` exécute, `_transition_to(PLAYING)` appelé. *Covers Rule 10 + Formula 2.*

- **AC-GSM-14** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** le GSM reçoit `level_active(etage_id, player_start)`, **WHEN** on inspecte les connexions Player → GSM via GUT, **THEN** `player.died` est connecté à `_on_player_died` avec `CONNECT_DEFERRED`, `player.respawned` à `_on_player_respawned` avec `CONNECT_DEFERRED`. *Covers Rule 13 + EC-5 — scene reload re-wire.*

### Groupe E — Scene Transitions

- **AC-GSM-15** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** `state == MENU`, **WHEN** `request_scene_transition("res://scenes/main_menu.tscn")` est appelé (edge case : déjà sur main_menu, transition vers elle-même valide), **THEN** `get_tree().change_scene_to_file()` est appelé 1 fois avec le path, `state_changed` n'est **pas** émis (MENU → MENU = no-op state, mais scène effectivement rechargée). *Covers Rule 6 + ADR-0007 D-5 idempotence.*

- **AC-GSM-16** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `state == BOSS_DEFEATED`, **WHEN** `request_new_run()` est appelé, **THEN** `get_tree().change_scene_to_file("res://scenes/main_menu.tscn")` est appelé, `state_changed(MENU)` émis après scene ready. *Covers Rule 6 + ADR-0007 D-8.*

### Groupe F — Performance

- **AC-GSM-17** `[Performance — BLOCKING] [Owner: performance-analyst]` — **GIVEN** une session de 10 minutes simulant 30 transitions d'état (menu ↔ play × 5, pause × 10, respawn × 15), **WHEN** `Performance.get_monitor(MEMORY_STATIC)` est échantillonné avant/après, **THEN** delta < 256 KB. *Covers Rule 14.*

- **AC-GSM-18** `[Performance — ADVISORY] [Owner: performance-analyst]` — **GIVEN** un test GUT qui appelle `_transition_to(PAUSED)` 1000 fois à la suite, **WHEN** on mesure le temps total via `Time.get_ticks_usec()`, **THEN** moyenne par appel < 50 µs (couvre state mutation + emit + consumers lightweight). *Covers Rule 14 + Formula 4.*

## Open Questions

### OQ-1 — Où vit le registry des étages (liste + ordre) ?

**Question** : quand la liste des étages dépasse 1 (Tier 2+), qui possède le mapping `etage_id → scene_path` et l'ordre `1 → 2 → 3 → Shop → 4 → 5 → Boss` ?

**Options identifiées** :
- (a) Dans le GSM (`const ETAGE_MANIFEST = {1: "res://...", 2: "res://..."}`) — simple, mais couple GSM au contenu
- (b) Dans un Resource dédié `design/registry/etage-manifest.tres` lu au boot — découpleux, éditable designer
- (c) Dans SaveSystem (progression persistante) — mais SaveSystem ne doit pas dicter le contenu

**Recommandation MVP** : aucune urgence au MVP (1 étage unique = `start_run(1)` en hardcoded). Reporter à l'écriture de SaveSystem ou du Shop GDD, quand le "next etage after shop" doit être résolu.

**Owner** : gameplay-programmer + game-designer. **Target** : avant Sprint 3 (Tier 2 planning).

### OQ-2 — Faut-il ajouter un state `LOADING` public dans l'enum ?

**Question** : l'implémentation utilise un sous-état interne LOADING (voir Section C), mais pas exposé dans `State`. Certains consumers (HUD, Audio) pourraient vouloir afficher un feedback pendant LOADING. Faut-il exposer l'état LOADING publiquement ?

**Options** :
- (a) Garder LOADING privé (statut actuel) — les consumers utilisent `is_transitioning() : bool` pour détecter
- (b) Ajouter `State.LOADING` public — état visible, 6 states au lieu de 5
- (c) Ajouter un signal `loading_started(path)` / `loading_ended(path, success: bool)` complémentaire

**Recommandation MVP** : (a) + (c) = garder LOADING privé mais exposer via les signaux `scene_transition_requested/completed/failed` qui sont déjà prévus. Les consumers n'ont pas besoin d'un state enum — ils ont les signaux. Ajouter LOADING à l'enum casse le registry `architecture.yaml` l.125 (immutabilité des noms de states).

**Owner** : gameplay-programmer. **Résolution** : à valider à la 1ère story Menu/HUD — si un système demande le state LOADING, rouvrir.

### OQ-3 — `request_quit` doit-il offrir un dialog "save first ?" UX ?

**Question** : actuellement `request_quit(save_first: bool = true)` prend le flag en paramètre. L'UX Menu doit-il afficher un dialog "Sauvegarder avant de quitter ?" ou passer save_first=true silencieusement ?

**Options** :
- (a) Silencieux, save_first=true par défaut — simple, pas de friction joueur
- (b) Dialog UX au clic "Quit" → "Quit without saving" vs "Save and quit"
- (c) Auto-save à chaque checkpoint, donc quit always save_first=false car déjà à jour

**Recommandation MVP** : (a) par défaut + (c) en architecture cible. Le GSM expose le flag, Menu appelle `request_quit(save_first=true)` au bouton Quit. Dialog peut être ajouté Tier 2 si playtest demande. Pas bloquant MVP.

**Owner** : ux-designer + game-designer. **Target** : `/ux-design design/ux/pause-menu.md`.

### OQ-4 — ADR-0007 status : promotion Proposed → Accepted [RESOLVED 2026-04-23 r2]

**Status** : ✅ RESOLVED. ADR-0007 promu Proposed → **Accepted 2026-04-23 r2** via `/architecture-review full` r2 (verdict PASS : 0 cross-ADR conflict, 5 TRs Level G-6 closed, TR-inp-006 consumer formalisé, Engine LOW risk APIs stables 4.0+). Le scénario (b) recommandé a été exécuté : `/design-review fresh session` (ce review r1) a validé indépendamment la cohérence GDD ↔ ADR ; `/architecture-review` a ensuite promu Accepted r2. Cohérence bidirectionnelle confirmée par les 12 alignements forts vérifiés Phase 4 du present review.

**Historique** : (a) immédiate était considérée, (c) post-impl rejetée, (b) GDD-first APPROVED → ADR-promotion retenue et exécutée.

### OQ-5 — Extensions considérées mais exclues MVP (amendement ADR-0007 D-10)

**Question** : quelles extensions post-MVP ajouter à l'API GSM ? Ce GDD a considéré 4 candidats :

| Extension | Motivation | Amendement requis | Trigger |
|-----------|------------|---------------------|---------|
| `request_quit(save_first: bool)` verbe centralisé | Unifier quit paths, save-on-quit orchestré | ADR-0007 D-10 | Sprint Menu si quit UX complexe (dialog "save first ?") |
| Signal `run_started(etage_id) / run_ended(reason)` | Analytics + Speedrun timer clean boundaries | ADR-0007 D-3 | Sprint Speedrun (Full Vision) |
| Signal `scene_transition_completed / failed / slow` | UX feedback pendant chargements longs | ADR-0007 D-3 + D-5 | Tier 2+ si `scene_transition_slow` utile côté Menu UI spinner |
| `RESPAWN_SAFETY_TIMEOUT_MS` force-exit RESPAWNING | Safety net si Movement bug | ADR-0007 D-7 | QA catches softlock respawn en playtest |
| `CanvasLayer` transition fade overlay owned GSM | Masquer flash blanc Godot change_scene_to_file | ADR-0007 D-5 | Tier 2+ si flash observé au playtest MVP |

**Résolution** : tous EXCLUS du MVP pour respecter ADR-0007 D-10 "API publique figée". Réouverture via amendement ADR-0007 dédié si un trigger se matérialise. **Status** : CLOSED for MVP, OPEN for Tier 2+.

**Owner** : technical-director. **Target** : rouvrir par sprint-by-sprint review selon triggers observés.

### OQ-6 — Divergences draft initial vs ADR-0007 — reconciliation log [RESOLVED — historical appendix]

**Status** : ✅ RESOLVED. Cette entrée n'est pas une question ouverte mais un **changelog historique** des 8 réconciliations appliquées entre le draft initial du GDD (API plus riche : 9 verbes, 10 signaux) et l'alignement final ADR-0007 D-10 (API figée 5 verbes + 1 signal). Conservé en "Open Questions" pour traçabilité ; à déplacer en Appendix dédié lors d'un prochain pass éditorial.

**Question** : ce GDD a été initialement drafté (Section C Rule 3, 10, 14 + Formula 4, EC-1, AC Groupes A-F) avec une API plus riche (9 verbes, 10 signaux) avant lecture de l'ADR-0007 existant. Les divergences ont été résolues en alignement strict sur ADR-0007 D-10.

**Log des réconciliations appliquées** :
1. Signal `state_changed(old_state, new_state)` → `state_changed(new_state)` (1 param per D-3)
2. Verbes publics 9 → 5 (`start_etage`, `request_pause`, `request_resume`, `request_scene_transition`, `request_new_run` per D-10)
3. Verbes retirés en PUBLIC et convertis en HANDLERS privés : `notify_player_died` → `_on_player_died`, `notify_respawn_complete` → `_on_player_respawned`, `notify_boss_defeated` → handler `etage_completed(boss=true)` côté Level, `return_to_menu` → `request_scene_transition(main_menu_path)`, `request_quit` → removed MVP (delegate Menu + SaveSystem)
4. Signaux additionnels retirés : `run_started`, `run_ended`, `scene_transition_requested/completed/failed/rejected/slow`, `game_booted`, `game_quitting` — tous considérés mais exclus per D-3 (1 signal `state_changed` seul MVP). Déplacés en OQ-5 extensions.
5. Two-path scene transition (D-5) intégré : `change_scene_to_file` pour scenes menu vs `LevelSystem.load_etage` additive pour étages — remplace mon concept initial "single path request_scene_transition universal"
6. Respawn safety timeout `RESPAWN_SAFETY_TIMEOUT_MS` retiré en constante registry (sera purgé au prochain `/consistency-check` si ADR ne l'amende pas)
7. Pattern pull au boot (D-9) : pas d'emit `state_changed(MENU)` ; consumers lisent `get_current_state()` dans leur `_ready`
8. Pause discipline simplifiée : GSM ne touche pas à `Input.enabled` refcount MVP (scène Menu porte son propre blocker), seulement `get_tree().paused`

**Résolution** : GDD aligné ADR-0007 D-10 strictement. Les extensions draft initial sont conservées en OQ-5 comme candidats post-MVP. **Status** : CLOSED — divergences résolues, GDD cohérent avec ADR-0007.

**Owner** : gameplay-programmer (réalignement). **Timestamp** : 2026-04-23 solo auto-approve.
