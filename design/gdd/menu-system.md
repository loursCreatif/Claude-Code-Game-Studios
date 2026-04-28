# Menu System

> **Status**: Designed r2 (full — r2 cosmetic 4 ship-blocking + RESOLVED OQ-MNU-1 + r2 PRE-IMPL/POLISH session 2026-04-27 résout les 36 findings différés ; pending fresh `/design-review` lean re-pass avant `/create-epics`)
> **Author**: Martin + design-system skill (auto mode) + creative-director (Player Fantasy) + game-designer + ux-designer (Detailed Rules + UI) + systems-designer (Edge Cases) + qa-lead (Acceptance Criteria) + 4 specialists adversariaux fresh review (game-designer + systems-designer + ux-designer + qa-lead)
> **Last Updated**: 2026-04-27 (r2 PRE-IMPL/POLISH — voir `reviews/menu-system-review-log.md`)
> **Implements Pillar**: Pillar 1 FLOW AVANT TOUT (primaire — pause/resume < 100 ms, anti-friction ESC, zero death-screen) + Pillar 3 UNE SECONDE CHANCE (par soustraction — pas de menu interruptif au respawn)
> **Depends on**: GameStateManager (APPROVED r1), Input System (r6 NEEDS REVISION mineur — structure PASS)
> **Depended on by**: Shop r1 (bouton Continuer / Main Menu ciblent main_menu.tscn ou start_etage), HUD r1 (visibility hide en PAUSED — peer no conflict avec Pause overlay), Audio r2.1 (peer ducking PAUSED owned Audio)
> **Architecture references**: ADR-0007 (Game State Manager — verbes publics 5 et signal state_changed), ADR-0004 (Input API — refcount request_disable/release_enable_request + ui_cancel_pressed), ADR-0008 (Collision Layer Taxonomy — non utilisé Menu = pas de Area3D), ADR-0011 (Level Scene Architecture — non utilisé Menu = container scenes via change_scene_to_file)

## Overview

Le Menu System est le **conteneur d'interface non-gameplay** : il regroupe les deux écrans MVP qui encadrent une session — le **Main Menu** (écran titre au boot, bouton "Start Run" qui appelle `GameStateManager.start_etage(1)`, bouton "Quitter") et le **Pause Menu** (overlay full-screen pendant `GameStateManager.State.PAUSED`, boutons "Reprendre" / "Quitter vers Menu Principal" / "Quitter le jeu"). Il est **consommateur strict** des verbes publics figés ADR-0007 D-10 (`start_etage`, `request_pause`, `request_resume`, `request_scene_transition`, `request_new_run`) et **propriétaire de son propre refcount** sur InputManager (ADR-0004 D-4 — pose `request_disable(&"Menu")` à l'ouverture du Pause Menu, release à la fermeture). Pattern d'implémentation : **deux scènes Control distinctes** — `main_menu.tscn` est une scène **container** (chargée via `change_scene_to_file` ADR-0007 D-5 §a, replace toute la scène courante) ; `pause_overlay.tscn` est un **overlay node-local** (CanvasLayer layer 80, instancié au démarrage de chaque étage gameplay et caché par défaut, visibility pilotée par `state_changed(State.PAUSED)`). Le Menu System ne possède aucune logique de gameplay — pas de score, pas d'inventaire, pas de stats summary à la mort (Pillar 3 UNE SECONDE CHANCE : respawn 50 ms direct, jamais d'écran intermédiaire). Le scope MVP couvre exactement 2 écrans + 1 trigger d'ouverture (touche `ui_cancel` / Escape) + la coordination mouse capture (`InputManager.set_mouse_captured(false)` à l'ouverture, `true` à la fermeture vers PLAYING). Settings menu (sensitivity souris, remap clavier, audio sliders), credits scrolling, options graphics, profil multi-save sont tous **explicitement hors scope MVP** — reportés Tier 2+ avec amendement de ce GDD.

> **Quick reference** — Layer: `Presentation` · Priority: `MVP` · Key deps: `GameStateManager (APPROVED r1), InputManager (r6 structure PASS)` — consommé par : `Shop r1 (boutons retour main_menu / start_etage), HUD r1 (hide PAUSED peer), Audio r2.1 (ducking PAUSED peer)`

## Player Fantasy

Le joueur ne touche le Menu System qu'à deux instants brefs : la première seconde du jeu (boot → Start Run) et chaque pause volontaire. Entre les deux, il n'existe pas. Aucun écran de mort, aucun écran de chargement visible, aucune confirmation, aucune narration. Le Menu est un sas — il s'ouvre, il libère, il disparaît. Sa qualité se mesure à ce qu'il NE fait PAS sentir : pas d'attente, pas de friction, pas de doute. Si le joueur remarque le Menu en tant que système, le Menu a échoué. La réussite est un Menu qu'on traverse sans s'en souvenir, exactement comme on ne se souvient pas d'avoir poussé une porte.

### Manifestations indirectes (ce que le joueur perçoit)

| Manifestation | Pilier servi | Mécanisme Menu |
|---|---|---|
| "J'ai cliqué Start Run et 200 ms après je tombais déjà dans l'étage 1" | Pillar 1 FLOW AVANT TOUT | Main Menu sans splash studio, sans logo animé, sans transition longue — appel direct `GSM.start_etage(1)` |
| "ESC, je bois, ESC, je repars — je n'ai pas perdu mon flow" | Pillar 1 FLOW AVANT TOUT | Pause/Reprise snap < 100 ms, freeze instantané, aucune animation overlay, aucun fade |
| "Je suis mort, je respawn, je n'ai jamais vu d'écran" | Pillar 3 SECONDE CHANCE | Pause Menu inaccessible pendant RESPAWNING (ADR-0007) — le Menu n'a pas le droit d'interrompre la die-retry < 2s |
| "Le Menu ressemble au Shop et au HUD — c'est le même jeu partout" | Pillar 2 LA PROGRESSION SE VOIT (cohérence Chrome Zen) | Monospace, palette achromatique #E8E8F0 + accent cyan #3EE4FF, géométrie corporate identique aux autres surfaces UI |
| "J'ai voulu quitter, j'ai cliqué Quitter, le jeu s'est fermé" | Pillar 1 FLOW AVANT TOUT (anti-friction) | Zéro confirm dialog "êtes-vous sûr ?" — `get_tree().quit()` immédiat, le clic EST la confirmation |
| "Le silence du Menu, comme le silence du Shop, m'a calmé entre deux courses" | Cohérence transversale (Pillar 1 + anti-pillar narration) | Aucun SFX MVP, ducking Music -12 dB owned Audio en PAUSED — le Menu hérite du silence de la pause |

### Pacte avec Pillar 1 FLOW

Le Menu s'efface, point. ESC → état PAUSED → freeze immédiat sous 100 ms ; ESC à nouveau → reprise immédiate, pas de fade-in, pas de countdown "3, 2, 1". Le Menu ne possède aucun fade overlay : les transitions visuelles entre états (PLAYING → PAUSED → PLAYING, MAIN_MENU → PLAYING) sont owned par le GSM (layer 100, fade noir), jamais par le Menu lui-même — un seul propriétaire du fade évite la double-transition qui sentirait molle. Aucun confirm dialog, jamais. Le clic sur "Quitter le jeu" depuis Pause appelle `get_tree().quit()` directement ; si le joueur a cliqué par erreur, c'est sa responsabilité, pas celle d'une boîte modale qui le ralentit à chaque vraie sortie. Référence Ghostrunner : ESC est un instrument de précision, pas une décision.

### Pacte avec Pillar 3 SECONDE CHANCE

Il n'y a pas de death-screen. Quand le joueur meurt, l'état machine passe en RESPAWNING et la fade die-retry < 2s s'enchaîne sans que le Menu apparaisse jamais — la matrice de transitions ADR-0007 interdit explicitement Pause Menu pendant RESPAWNING. Le joueur n'a ni à cliquer "Réessayer", ni à voir des stats post-mortem ("Vous avez survécu 47s, ennemis tués : 3"), ni à attendre une animation de défaite. La mort est une virgule, pas un point. Cette absence est un design positif, pas un oubli : `game-concept.md` ligne 96 stipule "L'UI est invisible", et l'anti-pillar "NOT un jeu à narration interruptive" interdit toute interface qui retient le joueur en dehors du gameplay. Le Menu respecte cet interdit en restant fermé pendant les phases où le joueur veut juste retomber dans la course.

### Anti-fantasy (ce que le joueur ne doit JAMAIS sentir)

- **Pas de "Are you sure you want to quit?"** — la confirmation modale est une insulte au temps du joueur. Un clic est une décision ; on n'audite pas les décisions du joueur.
- **Pas de splash screen studio long** — pas de logo Godot, pas de logo studio fade-in/fade-out de 3 secondes au boot. Le Main Menu est la première frame visible (ou aussi proche que techniquement possible).
- **Pas de menu animé qui retient** — pas de parallax background, pas de bouton "Start Run" qui pulse en cyan, pas de hover glow avec délai. Les boutons sont statiques, lisibles, cliquables. La beauté Chrome Zen est dans la retenue, pas dans le mouvement.
- **Pas de death-screen avec stats** — aucun écran "You died" entre la mort et le respawn. Aucun récap "ennemis tués / temps écoulé / crédits gagnés". Les stats vivent dans le HUD pendant la course et dans le Shop entre étages, jamais dans le Menu.
- **Pas d'écran "Loading..." visible** — le fade noir du GSM (layer 100) masque les chargements ; le joueur voit du noir, pas un spinner ni une barre de progression.
- **Pas de musique de menu différente** — le Menu n'introduit pas de track lounge ambient propre. Le Main Menu hérite du même silence/ambient que la première seconde de l'étage 1 ; le Pause Menu hérite de la track de l'étage en cours, duckée -12 dB. Un seul univers sonore, pas deux.
- **Pas de tutoriel intrusif** — aucun popup "Appuyez sur W pour avancer" au premier boot. Le Main Menu propose Start Run, point. L'apprentissage se fait dans l'étage 1, par le mouvement.
- **Pas de double-ESC qui flash le Pause** *(r2 — anti-fantasy U-10)* — un appui ESC + ESC très rapide (rebond clavier ou intention "annuler ce que je viens d'ouvrir") doit produire un toggle propre PLAYING → PAUSED → PLAYING géré par l'idempotence GSM, **pas** un flash visible de l'overlay (overlay qui apparaît 16 ms puis disparaît). Le joueur ne doit jamais sentir qu'il a "raté" sa pause. Le pattern `CONNECT_DEFERRED` + snap on/off (R-MNU-15) garantit que les deux events sont absorbés dans la même frame logique côté GSM ; aucun rendu intermédiaire ne montre l'overlay si les deux ESC tombent dans le même tick physics.

### Références — ce qu'on prend, ce qu'on jette

**Ghostrunner — pause snap (PRENDRE)** : ESC freeze instantané, ESC reprise instantanée, aucune animation entre les deux. Le menu est un interrupteur binaire. C'est exactement notre cible Pillar 1 < 100 ms. On reprend le timing et la philosophie "le menu n'est pas un moment, c'est une bascule".

**Hollow Knight — silence du bench/shop (PRENDRE)** : les écrans de pause et de shop sont silencieux ou quasi-silencieux, ce qui crée un contraste calmant avec l'intensité du gameplay. Notre Pause Menu et Shop héritent de cette respiration via le ducking Music -12 dB et l'absence de SFX. Le silence n'est pas un manque, c'est une décision.

**Mirror's Edge — UI invisible (PRENDRE)** : philosophie "l'interface ne doit pas voler l'attention au mouvement". Confirme notre anti-pillar "L'UI est invisible". Le Menu n'existe que pendant les microsecondes où le joueur le regarde activement.

**AAA opening cinematics 30s (REJETER)** : The Witcher 3, God of War et autres ouvrent sur des logos studio + cinématiques de 20-40 secondes avant le Main Menu. Ce pattern viole frontalement Pillar 1 et l'anti-pillar "pas de cutscenes mid-level" — il déplace le problème au boot mais c'est la même offense au temps du joueur. Notre Main Menu doit être visible le plus tôt possible après lancement.

**Apex Legends — warning popups au boot (REJETER)** : avertissements épilepsie, EULA, mises à jour, news du patch, popups de saison. Chaque popup est une dette de goodwill. Notre Main Menu ne contient AUCUN de ces écrans. Si un avertissement légal est requis (épilepsie), il vit dans une page Settings consultable, pas en interstitiel obligatoire au boot.

## Detailed Rules

### Core Rules (R-MNU-1 … R-MNU-18)

**R-MNU-1 — Architecture : deux scènes Control distinctes, zéro autoload Menu**

⚠️ **DESIGN DECISION** : le Menu System n'est **pas** un autoload. Il vit dans deux scènes Control indépendantes : `res://scenes/menus/main_menu.tscn` (scène container) et `res://scenes/menus/pause_overlay.tscn` (overlay node-local instancié dans chaque scène étage). Aucun singleton Menu n'existe — la logique de chaque écran est portée par un script `MainMenuControllerScript` / `PauseMenuControllerScript` attaché à la racine de sa scène respective. Justification : le Main Menu n'a pas d'état inter-session à maintenir entre les runs ; le Pause Overlay appartient au gameplay de l'étage et doit être détruit avec lui. Un autoload-menu serait un singleton qui tourne pendant tout le jeu pour une surface de 5 boutons combinés.

**R-MNU-2 — Main Menu : scène container chargée via `change_scene_to_file`**

⚠️ **DESIGN DECISION** : `main_menu.tscn` est une **scène container** au sens ADR-0007 D-5 §a two-path. Elle est chargée par `GameStateManager` via `get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")` — elle remplace intégralement la scène courante. Elle n'est jamais instanciée en overlay additif. Ce pattern garantit qu'aucun résidu de l'étage précédent (Player, LevelSystem, ennemis, PhysicsBody) ne subsiste en mémoire pendant que le joueur est au menu. La scène est chargée au boot (GSM initial state = MENU) et au retour menu depuis Pause (via `request_scene_transition`).

Hiérarchie de nœuds minimale `main_menu.tscn` :
```
MainMenuRoot : Control (fullscreen, ProcessMode = PROCESS_MODE_INHERIT)
├── Background : ColorRect (fullscreen #0A0A14)
├── TitleLabel : Label ("CHROME://ASCENT" — monospace, centré)
└── ButtonContainer : VBoxContainer
    ├── StartRunButton : Button ("Start Run")
    └── QuitButton : Button ("Quitter le jeu")
```

`ProcessMode = PROCESS_MODE_INHERIT` sur `MainMenuRoot` : la scène Main Menu est une scène container, `get_tree().paused` est `false` en état MENU (pas de gameplay actif à freezer), donc `INHERIT` depuis la racine SceneTree est correct. Aucune raison d'utiliser `PROCESS_MODE_ALWAYS` ici.

**R-MNU-3 — Pause Overlay : node-local dans chaque scène étage, CanvasLayer layer 80**

⚠️ **DESIGN DECISION** : `pause_overlay.tscn` est instancié comme **enfant direct de la scène étage** (e.g. `etage_01.tscn`), pas comme autoload, pas comme CanvasLayer top-level autoload. Il vit et meurt avec son étage. Cette philosophie — "le Pause Overlay vit avec le gameplay" — évite les failles de lifetime (un autoload Pause qui persiste entre deux `change_scene_to_file` alors que l'étage est déjà déchargé). Il est caché (`visible = false`) dès l'instanciation et piloté exclusivement par `state_changed(State.PAUSED)`.

Hiérarchie de nœuds `pause_overlay.tscn` *(r2 — naming canonique `PauseLayer` aligné K.2 + AC-MNU-37/55, DimRect explicité G-12)* :
```
PauseLayer : CanvasLayer (layer = 80, ProcessMode = PROCESS_MODE_ALWAYS)  # r2 cosmetic alignement K.2 + AC-MNU-37 + Tuning Knob PAUSE_OVERLAY_PROCESS_MODE — voir R-MNU-14
├── DimRect : ColorRect (anchor_preset = FULL_RECT, color = MENU_BG_OVERLAY_ALPHA token K.4)  # r2 G-12 — DimRect explicité dans la hiérarchie R-MNU-3 (était K.2-only)
└── PausePanel : Control (fullscreen, FULL_RECT)
    └── PanelContainer : PanelContainer (ancré centre-centre, MENU_PANEL_BG K.4)
        ├── PauseTitleLabel : Label ("PAUSE" — optionnel)
        └── ButtonContainer : VBoxContainer
            ├── ResumeButton : Button ("Reprendre")
            ├── MainMenuButton : Button ("Quitter vers Menu Principal")
            └── QuitButton : Button ("Quitter le jeu")
```

⚠️ **Naming canonique** *(r2 — G-14)* : la racine de `pause_overlay.tscn` est nommée **`PauseLayer`** (pas `PauseOverlayRoot`). Tous les ACs (`AC-MNU-37`, `AC-MNU-55`) référencent `PauseLayer`. L'ancienne mention `PauseOverlayRoot` est dépréciée — utiliser `PauseLayer` dans tous les nouveaux écrits scripts/scènes.

`CanvasLayer.layer = 80` : au-dessus du HUD (layer 50) et du Shop (layer 60), en-dessous du GSM fade overlay (layer 100). Toujours visible sur le gameplay, jamais masqué par une autre surface UI MVP.

**Pattern d'instanciation** *(r2 — G-4 + G-11)* : la décision de **qui** ajoute `pause_overlay.tscn` à chaque scène étage est tranchée au profit de l'**authoring static via le `.tscn` de l'étage** (pas instanciation runtime via code) :

- **MVP retenu (a)** : chaque `etage_XX.tscn` contient le nœud `pause_overlay.tscn` instancié comme enfant direct de la racine de la scène, sauvegardé visuellement dans le `.tscn` de l'étage (drag & drop dans l'éditeur Godot, `Instantiate Child Scene`). Pattern simple, zéro code dans `BaseEtage`, zéro instanciation runtime à orchestrer.
- **Alternative rejetée (b)** : classe `BaseEtage` parent qui ferait `add_child(preload("pause_overlay.tscn").instantiate())` dans son `_ready()`. Plus DRY mais introduit une dépendance hiérarchique côté Level System et complique la lecture de la scène (le Pause Overlay n'est pas visible dans le `.tscn` de l'étage).
- **Conséquence MVP** : un nouveau étage créé sans `pause_overlay.tscn` instancié ne pourra pas être pausé (ESC silencieux — couvert par EC-MNU-41 zero-instance + AC-MNU-59 grep enforce). Trade-off accepté : la responsabilité d'inclure le Pause Overlay incombe à l'auteur level (level-designer agent), validé en CI via lint.

**R-MNU-3b — Authoring lint : chaque scène étage gameplay DOIT instancier `pause_overlay.tscn` exactement 1×** *(r2 — G-4 + G-9 + EC-MNU-41)* — le test statique (AC-MNU-59) parse les `.tscn` du dossier `scenes/etages/` et compte les occurrences de `pause_overlay.tscn` : exactement 1 par fichier. Zéro instance = ESC silencieux non détecté ; deux instances = double-overlay (couvert EC-MNU-8).

**R-MNU-4 — Pattern pull au `_ready()` : lire `GSM.get_current_state()` avant la première frame**

Conformément à ADR-0007 D-9, les deux controllers (Main Menu et Pause Overlay) appliquent un **pattern pull synchrone** dans leur `_ready()` :

```gdscript
# Dans PauseMenuControllerScript._ready()
var initial_state := GameStateManager.get_current_state()
_apply_visibility(initial_state)  # → visible si PAUSED, hidden sinon
GameStateManager.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)
```

Ceci garantit que la visibility est correcte avant la première frame rendue, même si un signal `state_changed` est émis pendant le chargement de la scène avant que la connexion soit établie. Le `MainMenuControllerScript` n'a pas besoin de pull state pour la visibility (il est toujours visible à l'état MENU), mais doit connecter `state_changed` pour gérer un éventuel BOSS_DEFEATED futur (no-op MVP, connexion préventive).

**R-MNU-5 — Trigger ESC : signal `ui_cancel_pressed` émis par InputManager, consommé par PauseMenuController**

⚠️ **DESIGN DECISION** : l'ouverture et la fermeture du Pause Menu via ESC sont pilotées par le **signal** `InputManager.ui_cancel_pressed` (ADR-0004 D-4 — `ui_cancel_pressed` est émis même quand InputManager est `enabled == false`, car il appartient au canal UI, pas au canal gameplay). Le PauseMenuController écoute ce signal en `_ready()` :

```gdscript
InputManager.ui_cancel_pressed.connect(_on_ui_cancel)
```

Aucun polling `InputManager.was_pressed_this_tick()` pour cette action — la règle projet "interdire le mélange signal/polling pour la même action" (Input GDD Rule 11) est respectée. Le Main Menu ne consomme pas `ui_cancel_pressed` (ESC au Main Menu = no-op MVP — pas de fermeture possible, pas de sous-menu à quitter).

**R-MNU-6 — Comportement ESC conditionnel selon l'état GSM**

Le handler `_on_ui_cancel()` dans `PauseMenuControllerScript` est **state-conditional** :

```gdscript
func _on_ui_cancel() -> void:
    var state := GameStateManager.get_current_state()
    match state:
        GameStateManager.State.PLAYING:
            GameStateManager.request_pause()
        GameStateManager.State.PAUSED:
            GameStateManager.request_resume()
        _:
            pass  # RESPAWNING, BOSS_DEFEATED, MENU → no-op explicite
```

- **PLAYING** → appel `GSM.request_pause()`. GSM passe en PAUSED, émet `state_changed(PAUSED)`, le PauseOverlay se montre via R-MNU-15.
- **PAUSED** → appel `GSM.request_resume()`. GSM passe en PLAYING, émet `state_changed(PLAYING)`, le PauseOverlay se cache.
- **RESPAWNING** → `pass` (no-op). L'ESC pendant la fenêtre die-retry < 2 s est silencieusement ignoré — le joueur ne doit pas pouvoir geler l'animation de respawn.
- **BOSS_DEFEATED** → `pass` (no-op). État terminal géré ailleurs.
- **MENU** → non applicable (PauseOverlay n'est pas instancié dans `main_menu.tscn`).

**R-MNU-7 — Bouton "Start Run" (Main Menu) : appel `GSM.start_etage(1)`**

Le `StartRunButton` du Main Menu déclenche **exactement un verbe GSM** :

```gdscript
func _on_start_run_pressed() -> void:
    GameStateManager.start_etage(1)
```

`start_etage(1)` est le premier et unique verbe d'entrée dans le gameplay (ADR-0007 D-10 — verbe figé). Il déclenche le chargement de `etage_01.tscn` via le GSM, la transition de fade noir (layer 100 GSM), et le passage d'état MENU → PLAYING. Le Main Menu n'orchestre ni le chargement de scène, ni le fade, ni la capture souris (ces responsabilités appartiennent au GSM et à R-MNU-12). Le `MainMenuControllerScript` ne connaît pas le chemin de la scène étage — il délègue intégralement au GSM.

**R-MNU-8 — Bouton "Quitter le jeu" (Main Menu) : `get_tree().quit()` direct, zéro confirm**

⚠️ **DESIGN DECISION** : le bouton "Quitter le jeu" du Main Menu appelle `get_tree().quit()` immédiatement, sans modal de confirmation, sans délai.

```gdscript
func _on_quit_pressed() -> void:
    get_tree().quit()
```

Cohérent avec Pillar 1 FLOW anti-friction et Player Fantasy section "Pacte avec Pillar 1". La responsabilité de toute sauvegarde pre-quit est déléguée au SaveLoadSystem (écoute `NOTIFICATION_WM_CLOSE_REQUEST` — R-MNU-17b). Le Menu n'orchestre PAS de save explicite avant quit.

**R-MNU-9 — Bouton "Reprendre" (Pause Menu) : appel `GSM.request_resume()`**

```gdscript
func _on_resume_pressed() -> void:
    GameStateManager.request_resume()
```

`request_resume()` est le verbe GSM figé (ADR-0007 D-10) pour passer de PAUSED à PLAYING. La reprise est **immédiate** — pas de countdown, pas de fade-out du Pause Overlay, pas de "3, 2, 1 GO !". Le Pause Overlay disparaît en snap via R-MNU-15 dès que `state_changed(PLAYING)` arrive.

**R-MNU-10 — Bouton "Quitter vers Menu Principal" (Pause Menu) : appel `GSM.request_scene_transition`**

```gdscript
func _on_main_menu_pressed() -> void:
    GameStateManager.request_scene_transition("res://scenes/menus/main_menu.tscn")
```

Ce verbe (ADR-0007 D-10 — `request_scene_transition(scene_path: String)`) déclenche un `change_scene_to_file` côté GSM, avec fade noir layer 100. Le Pause Overlay est détruit automatiquement avec la scène étage lors du `change_scene_to_file` — pas de cleanup explicite requis dans le controller. L'InputManager release est géré en R-MNU-13 **avant** cet appel via `_on_visibility_off()`.

**R-MNU-11 — Bouton "Quitter le jeu" (Pause Menu) : `get_tree().quit()` direct, zéro confirm**

⚠️ **DESIGN DECISION** : cohérent avec R-MNU-8, le bouton "Quitter le jeu" depuis le Pause Menu appelle `get_tree().quit()` directement.

```gdscript
func _on_quit_pressed() -> void:
    GameStateManager.release_enable_request(&"PauseMenu")  # R-MNU-13 — release avant quit
    get_tree().quit()
```

⚠️ **DESIGN DECISION** : pas de confirm dialog "Êtes-vous sûr de vouloir quitter ?". Le clic est la confirmation. Cohérent avec l'anti-fantasy "Pas de 'Are you sure you want to quit?'" (Player Fantasy section). La save-on-quit est déléguée au SaveLoadSystem via `NOTIFICATION_WM_CLOSE_REQUEST` — le Menu n'orchestre aucune sauvegarde.

**R-MNU-12 — Mouse capture coordination : `set_mouse_captured(false)` à l'ouverture, `true` à la fermeture vers PLAYING**

L'état de capture souris est coordonné via `InputManager.set_mouse_captured(bool)` (ADR-0004) par les deux controllers :

| Événement | Appel | Rationale |
|---|---|---|
| `main_menu.tscn` instancié (`_ready()`) | `InputManager.set_mouse_captured(false)` | Menu plein écran — curseur libre pour cliquer les boutons |
| `pause_overlay.tscn` ouvre (state → PAUSED) | `InputManager.set_mouse_captured(false)` | Même raison — 3 boutons cliquables |
| Pause Overlay ferme vers PLAYING (state → PLAYING) | `InputManager.set_mouse_captured(true)` | Reprise gameplay FPS — mode FPS nécessite capture souris |
| `request_scene_transition` vers main_menu depuis Pause | Ne pas appeler `set_mouse_captured(true)` | La transition via GSM change de scène, main_menu fera son propre `set_mouse_captured(false)` au `_ready()` |

Le `PauseMenuControllerScript` implémente la coordination dans son handler visibility. **r2 cosmetic** : (1) guard `is_inside_tree()` ajouté en tête (BLK-3 S-1 — race tree_exiting pendant `change_scene_to_file`) ; (2) recapture souris paramétrée pour respecter EC-MNU-10 (transition PAUSED → MENU ne doit PAS recapturer — `main_menu._ready()` fera son propre `set_mouse_captured(false)`) :

```gdscript
func _apply_visibility(show: bool, recapture_mouse: bool = true) -> void:
    if not is_inside_tree():                          # r2 BLK-3 — guard race tree_exiting (S-1)
        return
    _root.visible = show
    if show:
        InputManager.set_mouse_captured(false)
        InputManager.request_disable(&"PauseMenu")    # R-MNU-13
        ResumeButton.grab_focus()                      # r2 G-8 — focus après visible=true (Godot ignore grab sur invisible)
    else:
        InputManager.release_enable_request(&"PauseMenu")  # R-MNU-13
        if recapture_mouse:                            # r2 BLK-2 G-2 — caller décide (resume=true, quit_to_menu=false)
            InputManager.set_mouse_captured(true)

# Callers :
# - _on_resume_pressed     → _apply_visibility(false, recapture_mouse=true)
# - _on_main_menu_pressed  → _apply_visibility(false, recapture_mouse=false)  # main_menu._ready() recapturera
# - _on_quit_pressed       → _apply_visibility(false, recapture_mouse=false)  # process exit imminent
# - _on_state_changed(PAUSED)   → _apply_visibility(true)
# - _on_state_changed(PLAYING)  → _apply_visibility(false, recapture_mouse=true)
```

Cohérence : AC-MNU-32 gate `captured_true_call_count == 0` lors d'une transition PAUSED → MENU est désormais respectée par construction (le caller `_on_main_menu_pressed` passe `recapture_mouse=false`). La guard `is_inside_tree()` est partagée par `_on_state_changed` (R-MNU-9 corollaire).

**R-MNU-13 — Input refcount discipline : Pause Menu pose `request_disable`, Main Menu n'en a pas besoin**

Le Pause Menu pose `InputManager.request_disable(&"PauseMenu")` à l'ouverture et `InputManager.release_enable_request(&"PauseMenu")` à la fermeture (ADR-0004 D-4 — refcount multi-owner). Cette discipline empêche que des actions gameplay (dash, tir, wall-run) soient déclenchées pendant que le Pause Overlay est visible. L'owner key utilisée est le `StringName` `&"PauseMenu"` — unique par scène pour éviter tout collision de refcount.

Le **Main Menu n'a pas besoin** de ce refcount : la scène Main Menu est chargée via `change_scene_to_file`, ce qui détruit la scène étage entière (Player, MovementController, CombatSystem). Il n'existe aucun système gameplay actif en état MENU — InputManager est sans consommateur actif, le refcount serait sans effet et créerait une dette de release.

**R-MNU-14 — Process mode discipline : `PROCESS_MODE_ALWAYS` sur le Pause Overlay uniquement** *(r2 cosmetic : valeur tranchée ALWAYS — convergence 4 specialists G-1/S-2/U-11/Q-1)*

⚠️ Conformément à ADR-0007 D-4 :

- `PauseOverlayRoot` (CanvasLayer) : `ProcessMode = PROCESS_MODE_ALWAYS` (Godot enum `5`). **Obligatoire** — quand `get_tree().paused = true` (positionné par GSM en PAUSED), `_process()` et `_input()` doivent continuer pour que les boutons restent cliquables. `PROCESS_MODE_WHEN_PAUSED` (4) serait théoriquement suffisant (n'exécute QUE quand `paused=true`), mais `PROCESS_MODE_ALWAYS` (5) garantit fonctionnement même si `get_tree().paused` est appliqué de façon asynchrone par le GSM (race fenêtres entre `state_changed(PAUSED)` reçu et `paused=true` propagé). ALWAYS retenue MVP par robustesse + simplicité de raisonnement.
- `MainMenuRoot` (Control) : `ProcessMode = PROCESS_MODE_INHERIT`. En état MENU, `get_tree().paused` est `false` — l'arbre n'est pas pausé, `INHERIT` est suffisant et correct.
- `MainMenuControllerScript._ready()` : si GSM émet `state_changed` vers PAUSED depuis MENU (impossible d'après la matrice ADR-0007, mais guard défensif), le controller ne fait rien de destructif.

Corollaire : tous les enfants de `PauseOverlayRoot` héritent `PROCESS_MODE_ALWAYS` via la hiérarchie — aucun enfant individuel n'a besoin de surcharger son `process_mode`. **Lint** : AC-MNU-58 (Q-3) gate `grep -c "process_mode" scenes/menus/pause_overlay.tscn` retourne exactement 1 match (la racine uniquement).

**R-MNU-15 — Visibility binding Pause Overlay : snap on/off, zéro tween fade**

⚠️ **DESIGN DECISION** : la visibility du Pause Overlay est un **toggle binaire instantané** — pas d'animation tween fade-in/fade-out.

```gdscript
func _on_state_changed(new_state: GameStateManager.State) -> void:
    if not is_inside_tree():                                      # r2 BLK-3 S-1 — guard race tree_exiting (CONNECT_DEFERRED peut délivrer pendant change_scene_to_file)
        return
    var should_show: bool = (new_state == GameStateManager.State.PAUSED)
    var recapture: bool = (new_state == GameStateManager.State.PLAYING)  # PAUSED → PLAYING uniquement recapture
    _apply_visibility(should_show, recapture_mouse=recapture)
```

Cohérent avec Pillar 1 — un fade de 200 ms à l'ouverture de pause est perceptible et ralentit le retour au gameplay. Le GSM owns son propre fade noir (layer 100) pour les transitions de scène — le Pause Overlay n'a pas de raison d'avoir le sien. Snap on/off : `PauseOverlayRoot.visible = true/false` dans le même frame que le `state_changed` reçu. **Guard `is_inside_tree()`** (r2 BLK-3 S-1) : le pattern `CONNECT_DEFERRED` (R-MNU-4) introduit une latence de 1 frame entre l'émission de `state_changed` et l'exécution du handler — pendant `change_scene_to_file`, le Pause Overlay (node-local) peut être en cours de destruction (`tree_exiting`) au moment de la délivrance deferred du signal. La guard évite tout appel `_apply_visibility` sur un nœud orphelin.

**R-MNU-16 — Zéro confirm dialog : tout clic de bouton est exécution immédiate**

⚠️ **DESIGN DECISION** : il n'existe aucun modal de confirmation dans le Menu System MVP. "Quitter le jeu", "Quitter vers Menu Principal" — tous les boutons exécutent leur action immédiatement au clic. L'anti-pattern "Are you sure?" viole Pillar 1 FLOW et dégrade le goodwill reservoir à chaque vraie sortie volontaire. Si le joueur a cliqué par erreur, il peut relancer le jeu ou ESC-reprise selon le contexte — c'est sa responsabilité, non un cas que le Menu doit gérer par un second clic obligatoire.

**R-MNU-17 — Idempotence ESC pendant transition GSM : no-op explicite**

Si ESC est pressé pendant qu'une transition GSM est déjà en cours (`request_scene_transition` ou `start_etage` appelé mais scène non encore chargée), le handler `_on_ui_cancel()` appelle `get_current_state()`. GSM retourne l'état **courant** (PLAYING, PAUSED, ou un état intermédiaire) — `request_pause()` pendant une transition déjà en cours est safe car le GSM contient sa propre guard d'idempotence (ADR-0007). Le Menu ne doit pas dupliquer cette guard — il délègue au GSM. Comportement attendu : au pire, l'appel est un no-op côté GSM, jamais un double-transition.

**R-MNU-19 — Save-on-quit : délégué au SaveLoadSystem, Menu n'orchestre rien** *(r2 — renommage R-MNU-17b → R-MNU-19, G-7 disambiguation : R-MNU-17 idempotence ESC ≠ R-MNU-19 save-on-quit ; cf. OQ-MNU-1 RESOLVED + AC-MNU-57)*

⚠️ **DESIGN DECISION** : le Menu ne contient aucun appel `SaveLoad.save_*()` avant `get_tree().quit()`. Toute sauvegarde pre-quit est la responsabilité du **SaveLoadSystem** via `NOTIFICATION_WM_CLOSE_REQUEST` (cf. Save/Load r1 R-SAV-9 + R-SAV-8 + R-SAV-5 + ADR-0007 D-1 — pattern standard Godot pour intercept de fermeture). Le Menu déclenche `get_tree().quit()` sans attendre aucun callback. Si SaveLoadSystem n'est pas encore implémenté au MVP (Not Started), cette règle reste valide — il n'y a rien à sauvegarder au moment où le Menu agit. **Lint** : AC-MNU-57 BLOCKING enforce `grep -rE "SaveLoad|save_int|save_string_array|save_now" src/gameplay/menu/` → 0 match.

> **Note de migration** *(r2)* : les anciennes références à `R-MNU-17b` dans les commits / reviews antérieurs pointent désormais vers `R-MNU-19`. Tout autre rapport ou story qui cite `R-MNU-17b` doit être amendé.

**R-MNU-18 — Zéro logique gameplay dans le Menu System**

Le `MainMenuControllerScript` et le `PauseMenuControllerScript` ne contiennent **aucune** référence à :
- `CreditEconomy`, `UpgradeSystem`, `SaveLoad` (sauf R-MNU-17b via SaveLoadSystem autonome)
- `Player`, `MovementController`, `CombatSystem`, `EnemySystem`, `LevelSystem`
- Variables de session en cours (health, crédits, étage actuel, ennemis tués)

Les seules dépendances autorisées pour les deux controllers sont : `GameStateManager` (5 verbes figés ADR-0007 D-10 + signal `state_changed`) et `InputManager` (signal `ui_cancel_pressed` + appels `set_mouse_captured` + `request_disable`/`release_enable_request`). Toute future référence gameplay requiert un amendement explicite de ce GDD et une justification Pillar.

**R-MNU-20 — `set_mouse_captured(bool)` est une API publique figée d'InputManager** *(r2 — G-10 clarification ADR-0004)*

L'appel `InputManager.set_mouse_captured(captured: bool)` (consommé par R-MNU-12) est un **setter public stable** d'InputManager, distinct de l'API refcount `request_disable` / `release_enable_request` (D-4 multi-owner). Référence canonique : ADR-0004 D-7 — "focus_regain_window pattern" (le setter diffère l'application de `MOUSE_MODE_CAPTURED` jusqu'au prochain `NOTIFICATION_WM_WINDOW_FOCUS_IN` si la fenêtre n'a pas le focus OS au moment de l'appel). Aucun owner key n'est requis (contrairement au refcount `&"PauseMenu"`). L'idempotence est garantie côté InputManager — appels successifs avec la même valeur sont no-op. Le Menu peut donc appeler `set_mouse_captured(false)` deux fois sans risque de race ou de double-state.

---

### States and Transitions

Le Menu System n'a pas de machine d'état interne — il est **consommateur** de l'état GSM. La table ci-dessous décrit le comportement de chaque composant Menu pour chaque valeur de `GameStateManager.State`.

#### Table GSM State → Menu System Behavior

| GSM State | Main Menu (`main_menu.tscn`) | Pause Overlay (`pause_overlay.tscn`) | ESC (via `ui_cancel_pressed`) | Mouse capture |
|---|---|---|---|---|
| `MENU` | **Visible, active** — scène container courante, 2 boutons accessibles | **N/A** — pas instancié (scène étage absente) | No-op — PauseController non instancié | `false` (libre) |
| `PLAYING` | **Absente** — `change_scene_to_file` a remplacé la scène main_menu | **Hidden** — instancié dans étage, `visible = false` | → `GSM.request_pause()` | `true` (capturée FPS) |
| `PAUSED` | **Absente** | **Visible** — Pause Overlay affiché, 3 boutons accessibles, InputManager disable posé | → `GSM.request_resume()` | `false` (libre) |
| `RESPAWNING` | **Absente** | **Hidden** — inaccessible pendant die-retry < 2 s (ADR-0007 matrice) | No-op (guard `_on_ui_cancel` R-MNU-6) | `true` (capturée FPS — die-retry en cours) |
| `BOSS_DEFEATED` | **Absente** | **Hidden** — état terminal post-MVP, scène boss-defeated owned ailleurs | No-op | N/A (état terminal) |

**Sub-states implicites non-GSM** *(r2 — G-3 + G-5 documentation explicite)*

ADR-0007 ne reconnaît que **5 états canoniques** (MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED). Les phases ci-dessous sont **des sous-états de transition** qui ne sont **jamais émis** par `state_changed` — le Menu ne reçoit aucun signal pour ces phases. La table documente le comportement Menu **par construction** :

| Sub-state implicite | GSM réel pendant cette phase | Comportement Menu | Notes |
|---|---|---|---|
| **LOADING** (transition `change_scene_to_file` en cours) | État source de la transition (PLAYING avant `start_etage`, PAUSED avant `request_scene_transition`, ou MENU pour boot) | Pause Overlay éventuel détruit avec la scène source par `change_scene_to_file` ; nouveau Pause Overlay pas encore instancié dans la scène destination. **Ni signal `state_changed` ni handler Menu actifs pendant la phase de chargement** — le fade noir GSM (layer 100) masque la transition visuellement. | Couvert EC-MNU-3 (ESC pendant chargement → no-op subscriber). Couvert EC-MNU-36 (quit pendant `change_scene_to_file`). |
| **SHOPPING** (Shop Menu visible) | **GSM reste PLAYING** — Shop r1 est un overlay qui n'utilise PAS l'état PAUSED (Shop `process_mode = ALWAYS` mais GSM ne mute pas state). Shop r1 owns son propre handler ESC (R-SHP-9) avec `set_input_as_handled()`. | Pause Overlay reste **hidden** car GSM est PLAYING. ESC pressé pendant Shop visible est **consommé en priorité par Shop** (Shop layer=60 + son ESC consume) — `ui_cancel_pressed` n'atteint jamais le PauseController. Si Shop laisse passer (bug), guard `_on_ui_cancel` lit GSM=PLAYING et appelle `request_pause()` — ouverture Pause par-dessus Shop visible (collision visuelle layer 80 > 60, mais comportement défini). | Conflit ESC potentiel résolu par Shop r1 R-SHP-9 first-handler. AC-MNU-60 lint vérifie zero collision. |
| **SHUTDOWN** (process termination en cours après `get_tree().quit()`) | État courant gelé au moment du quit. `NOTIFICATION_WM_CLOSE_REQUEST` émis, autoloads détruits **après** scene root. | `_on_state_changed` ne reçoit plus rien (signal table en cours de teardown). Tous handlers Menu sont no-op à ce stade. `tree_exiting` propre déclenche `release_enable_request(&"PauseMenu")` avant destruction (R-MNU-13 + EC-MNU-23). | SaveLoad r1 R-SAV-9 owns le notification handler (R-MNU-19 délégation). |

#### Lifecycle Main Menu

| Phase | Déclencheur | Durée | Notes |
|---|---|---|---|
| `LOADING` | `change_scene_to_file("main_menu.tscn")` déclenché par GSM | Dépend du I/O disque | Fade noir GSM layer 100 masque le loading |
| `READY` | `_ready()` de `MainMenuControllerScript` exécuté | Permanent jusqu'à navigation | Pull state GSM, `set_mouse_captured(false)`, 2 boutons actifs |
| `NAVIGATING_AWAY` | `StartRunButton` press → `GSM.start_etage(1)` | < 1 frame | Scène détruite par `change_scene_to_file` via GSM — aucun cleanup explicite requis |

#### Lifecycle Pause Overlay

| Phase | Déclencheur | Durée | Notes |
|---|---|---|---|
| `INSTANTIATED_HIDDEN` | `_ready()` de la scène étage parente | Permanent (jusqu'à destruction de l'étage) | `visible = false` initial, InputManager connect, state pull GSM |
| `VISIBLE` | `state_changed(State.PAUSED)` | Jusqu'à `PLAYING` ou destruction scène | `request_disable` posé, `set_mouse_captured(false)`, 3 boutons actifs |
| `NAVIGATING_AWAY` | Bouton "Quitter vers Menu Principal" → `request_scene_transition` | < 1 frame | Release InputManager avant appel GSM, détruit avec scène étage par `change_scene_to_file` |

#### Transitions critique à documenter explicitement

- **PLAYING → PAUSED → PLAYING (cycle normal)** : Pause Overlay `INSTANTIATED_HIDDEN → VISIBLE → INSTANTIATED_HIDDEN`. Mouse capture `true → false → true`. InputManager `enabled → disabled → enabled`. Aucun état intermédiaire — tout est synchrone dans le même frame que le `state_changed` (CONNECT_DEFERRED = frame suivante, donc un frame de décalage au maximum).
- **PLAYING → PAUSED → request_scene_transition(main_menu)** : Release InputManager (R-MNU-13), appel `request_scene_transition`, scène étage détruite par GSM avec `change_scene_to_file`, Pause Overlay détruit automatiquement en tant qu'enfant. Le `release_enable_request` DOIT précéder l'appel GSM pour éviter un refcount orphelin (InputManager reference à un nœud détruit).
- **MENU → PLAYING (boot run)** : Main Menu reçoit `start_etage(1)`, GSM détruit `main_menu.tscn` via `change_scene_to_file`, charge `etage_01.tscn` qui instancie le Pause Overlay dans son `_ready()`. Mouse capture passe `false → true` géré par `etage_01._ready()` ou le premier `state_changed(PLAYING)` que reçoit le Pause Overlay.

---

### Interactions with Other Systems

| System | Direction | Type | Contrat |
|---|---|---|---|
| **GameStateManager** (APPROVED r1) | **Bidir** | Hard | **Out** : Menu utilise 4 des 5 verbes figés ADR-0007 D-10 — `start_etage(1)` (Start Run), `request_pause()` (ESC en PLAYING), `request_resume()` (ESC en PAUSED + bouton Reprendre), `request_scene_transition("res://scenes/menus/main_menu.tscn")` (bouton Quitter vers Menu). `request_new_run()` non utilisé MVP. **In** : consomme `state_changed(new_state: State)` CONNECT_DEFERRED côté Menu (R-MNU-4) pour visibility binding Pause Overlay. Pull `get_current_state() -> State` au `_ready()` (ADR-0007 D-9 pattern pull). Le Menu ne lit jamais directement `State.*` sans passer par ce getter. |
| **InputManager** (ADR-0004, r6 structure PASS) | **Bidir** | Hard | **In** : signal `ui_cancel_pressed` (consommé par PauseMenuController uniquement — R-MNU-5 ; toujours émis même si enabled == false ADR-0004 D-4). **Out** : `set_mouse_captured(bool)` (R-MNU-12 — `false` à l'ouverture menu, `true` à la fermeture vers PLAYING) ; `request_disable(&"PauseMenu")` et `release_enable_request(&"PauseMenu")` (R-MNU-13 — refcount Pause Overlay uniquement, Main Menu exempté). |
| **HUD System** (Designed r1) | Peer | Aucun couplage direct | Le HUD masque son `CreditCounterLabel` en PAUSED via son propre handler `state_changed` (HUD r1 Rule 10). Menu ne coordonne rien avec HUD — aucun appel croisé. Le Pause Overlay (layer 80) s'affiche au-dessus du HUD (layer 50) sans conflit visuel car HUD est `visible = false` pendant PAUSED. |
| **Shop System** (Designed r1) | Peer | Indirect | Shop bouton "Continuer" appelle `GSM.request_scene_transition("res://scenes/menus/main_menu.tscn")` — le Menu reçoit la transition passivement (GSM orchestre). Shop bouton futur "Rejouer" (Tier 2+) appellera `GSM.start_etage(next_etage_id)`. Menu ne connaît pas Shop ; Shop ne connaît pas Menu. Ils sont deux scènes-containers indépendantes coordonnées par GSM. |
| **Audio System** (APPROVED r2.1) | Peer | Aucun couplage | Audio System écoute `state_changed` pour poser le ducking Music −12 dB en PAUSED (audio-system.md r2.1). Le Menu n'émet aucun signal audio, n'appelle aucune API AudioServer, n'a aucune SFX MVP. Le silence du Pause est owned Audio, pas Menu. |
| **Level System** (APPROVED r3) | Anti-dépendance | Aucun | Menu ne connaît pas LevelSystem. Les scènes étage sont identifiées par un `etage_id: int` passé à `GSM.start_etage()` — Menu n'inspecte jamais la scène d'étage ni ses signaux. ADR-0007 D-5 §a garantit que la scène container active est une scène ou l'autre (main_menu.tscn OU etage_XX.tscn), jamais les deux simultanément. |
| **Save/Load System** (Not Started, MVP) | Peer | Indirect | Menu n'orchestre aucune sauvegarde (R-MNU-17b). Le Save/Load est responsable de `NOTIFICATION_WM_CLOSE_REQUEST` (GSM EC-6). `get_tree().quit()` appelé par Menu déclenche la notification — SaveLoad agit de manière autonome. Aucun appel croisé Menu → SaveLoad. |
| **Camera System** (APPROVED) | Peer | Aucun MVP | La scène `main_menu.tscn` n'a pas de Camera3D MVP (fond 2D ColorRect suffisant). Tier 2+ : une Camera3D décorative animée dans le Main Menu serait instanciée dans `main_menu.tscn` en tant que nœud enfant — le Menu System ownera sa caméra locale sans interaction avec CameraSystem gameplay. Aucune coordination requise. |
| **Credit Economy / Upgrade System / Combat System** | Anti-dépendance | Aucun | Menu ne référence, n'écoute, et ne mute aucun de ces systèmes (R-MNU-18). La composition zero-gameplay-logic est une contrainte architecturale dure, pas une convention. Toute future référence requiert un amendement GDD.

## Formulas

Le Menu System est un consommateur d'API et un afficheur passif. Il contient peu de calcul numérique. Les "formules" ci-dessous sont des **budgets temporels** et **invariants binaires** qui contraignent l'implémentation.

### F-MNU-1 — Pause/Resume snap budget (Pillar 1 FLOW)

Latence perçue entre press ESC et état visible PAUSED (ou inverse) :

`pause_perceived_ms = INPUT_TO_SIGNAL_MS + GSM_TRANSITION_MS + DEFERRED_FRAME_MS + RENDER_FRAME_MS`

**Variables :**

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| `INPUT_TO_SIGNAL_MS` | `T_in` | float (ms) | [0, 16.6] | Latence de InputManager (ADR-0004 D-3 swap pattern, ≤ 1 tick physique). |
| `GSM_TRANSITION_MS` | `T_gsm` | float (ms) | [0, 1] | Coût `_transition_to(PAUSED)` + `state_changed.emit` SYNC (cf. GSM Formula 4 ~0 ms négligeable). |
| `DEFERRED_FRAME_MS` | `T_def` | float (ms) | [0, 16.6] | Latence CONNECT_DEFERRED handler `_on_state_changed` côté Menu (≤ 1 frame). |
| `RENDER_FRAME_MS` | `T_ren` | float (ms) | [16.6, 16.6] | Une frame rendue pour faire apparaître `PauseLayer.visible == true` à l'écran. |

**Output Range** : [16.6, 50.8] ms. Cible MVP : **< 100 ms** (Pillar 1) — large marge.
**Hard cap** : si `pause_perceived_ms > 100`, AC-MNU-40 fail. Investiguer ordre signal/CONNECT_DEFERRED.

**Example** : ESC pressé tick T0 (`T_in = 8 ms`), GSM mute state SYNC (`T_gsm = 0.5 ms`), CONNECT_DEFERRED handler appelé tick T1 (`T_def = 16.6 ms`), frame rendue T2 (`T_ren = 16.6 ms`) → total = **41.7 ms** ✅ sous Pillar 1.

**Mesurabilité headless** *(r2 — S-8)* : `Time.get_ticks_msec()` mesure le temps wall-clock, pas le temps "frame rendue à l'écran". En mode headless (`--headless` CI), `T_ren` n'est pas observable car aucun frame n'est rendu. **Stratégie de test** :
- Test `[Logic]` (AC-MNU-40 BLOCKING) : mesure `[input emit] → [pause_layer.visible == true]` SYNC en environnement headless via timestamps `Time.get_ticks_msec()`. Ce composé `T_in + T_gsm + T_def` est mesurable (couvre 3 des 4 termes) et doit être < 50 ms (50 ms = 100 ms − borne `T_ren` 16.6 ms × 3 marge).
- Test `[Performance manual]` (AC-MNU-65 ADVISORY r2) : mesure complète `T_in + T_gsm + T_def + T_ren` sur build avec rendu actif (CI `xvfb` ou local). Confirme que la chaîne complète tient sous 100 ms en conditions réelles.
- L'écart entre les deux tests = `T_ren` réel (16.6 ms à 60 fps cible). Si le test headless passe mais le test manuel échoue, le coût de rendu d'un frame Pause est anormal (investiguer Theme override, font preload, etc.).

### F-MNU-2 — Pause overlay alpha (perception du freeze, PAS lisibilité texte) *(r2 cosmetic — reformulé : suppression faux argument WCAG sur DimRect, S-4 + U-12 convergent)*

Choix d'alpha du `DimRect` plein écran derrière le `PanelContainer`. **Note critique r2** : le texte du Pause Panel (`MENU_TEXT_BASE #E8E8F0` sur `MENU_PANEL_BG #0A0A12`) est posé sur le `PanelContainer` opaque, **pas sur le DimRect translucide**. Le ratio WCAG 15.2:1 du panel est garanti indépendamment de la valeur alpha du DimRect (cf. K.9). La formule F-MNU-2 ne concerne donc **pas** la lisibilité du texte, mais uniquement la **perception du freeze** (le joueur doit sentir que le jeu attend, pas qu'il a disparu).

`dim_alpha = CLAMP(MENU_BG_OVERLAY_ALPHA, ALPHA_MIN_FREEZE_VISIBLE, ALPHA_MAX_CONTACT_MONDE)`

**Variables :**

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| `MENU_BG_OVERLAY_ALPHA` | `α` | float | [0, 1] | Tuning Knob K.4 ; default **0.65**. |
| `ALPHA_MIN_FREEZE_VISIBLE` | `α_min` | float | 0.55 | Plancher perceptuel : en dessous, le freeze gameplay ne lit pas comme "pause" — l'overlay est trop discret, l'utilisateur peut douter qu'il a vraiment pausé. |
| `ALPHA_MAX_CONTACT_MONDE` | `α_max` | float | 0.75 | Plafond perceptuel : au-delà, l'overlay ressemble à un écran noir et le joueur perd contact visuel avec le monde gelé (anti Pillar 1 — "le jeu n'a pas disparu, il attend"). |

**Output Range** : [0.55, 0.75]. Default = 0.65.
**Rationale (r2)** : 0.65 est calibré purement sur la perception : (1) le freeze gameplay reste lisible derrière (le joueur voit son personnage figé, la géométrie de l'étage, les ennemis) — Pillar 1 préservé ; (2) l'overlay lit clairement comme "pause" (assez sombre pour pas être confondu avec un simple panel sans dim). La lisibilité du texte du Pause Panel est **hors scope F-MNU-2** — elle est gouvernée par K.9 contraste WCAG AAA `#E8E8F0` sur `#0A0A12` (15.2:1) indépendamment de la valeur alpha du DimRect. Si playtest révèle des cas border (ex : étage très clair avec laser blanc), monter à 0.70.

### F-MNU-3 — Tab cycle wrap (navigation clavier déterministe)

`focus_next(current_index, direction) = (current_index + direction + N) mod N`

**Variables :**

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| `current_index` | `i` | int | [0, N-1] | Index du bouton actuellement focusé. |
| `direction` | `d` | int | {-1, +1} | Tab = +1, Shift+Tab = -1. |
| `N` | `N` | int | {2, 3} | Nombre de boutons : 2 (Main Menu) ou 3 (Pause Menu). |

**Output Range** : [0, N-1] toujours valide → wrap déterministe, pas de focus perdu en bout de liste.

**Example** : Pause Menu (N=3), focus initial `i=0` (Reprendre). Tab → `i=1` (Main Menu). Tab → `i=2` (Quit). Tab → `i=0` (wrap). Shift+Tab depuis `i=0` → `i=2` (wrap inverse).

**Bornes explicites** *(r2 — S-13)* :
- **N=0** (aucun bouton focusable) : impossible MVP par contrat (Main Menu = 2 boutons hardcodés, Pause Menu = 3 boutons hardcodés). Si une régression Tier 2+ produisait `N=0` (ex : tous boutons disabled simultanément via Settings Menu non-canonique), `(i + d + 0) mod 0` lèverait une division par zéro Godot → fail loud assertion. Guard préventif : `assert(N >= 1)` dans `focus_next` Tier 2+.
- **N=1** (un seul bouton focusable) : `(0 + 1 + 1) mod 1 = 0` → focus reste sur le bouton unique (Tab no-op visuel mais pas de crash). Comportement défini, pas un bug.
- **N=2** (Main Menu) et **N=3** (Pause Menu) : seuls cas MVP. Wrap déterministe garanti.

**Rationale** : Godot Control nodes implémentent `focus_neighbor_*` natif si configuré. MVP utilise simplement le défaut Godot (focus next/previous via Tab) et configure les `focus_next/previous` via inspector pour garantir le wrap. Aucun script custom requis MVP. Couvert AC-MNU-61 (test wrap inverse Shift+Tab depuis i=0).

### F-MNU-4 — Aucune formule de feel (par négation)

Le Menu System n'a **aucune** formule de easing, de tween, de fade, de spring. Toutes ces formules sont **interdites par Player Fantasy Pacte Pillar 1** : snap on/off, zéro animation. Si une future ADR Tier 2+ introduit une animation menu (ex : settings menu slide-in), elle exigera une F-MNU-5 dédiée + amendement de ce GDD + amendement Player Fantasy.

**Invariant binaire** : `tween_count_in_menu_code == 0` — testable AC-MNU-36.

## Edge Cases

### EC-MNU-1 — ESC pressé pendant RESPAWNING

- **If** `_on_ui_cancel()` est appelé alors que `GSM.get_current_state() == State.RESPAWNING` **:** le `match` tombe sur le bras `_:` → `pass`. Aucun appel GSM, aucun appel InputManager. Le die-retry < 2 s continue sans interruption. Justification : transition RESPAWNING → PAUSED interdite ADR-0007 D-2 (matrice de transitions) — forcer la pause pendant l'animation de respawn casserait Pillar 3 UNE SECONDE CHANCE.

### EC-MNU-2 — ESC pressé pendant une transition GSM en cours

- **If** ESC est pressé alors que `start_etage` ou `request_scene_transition` a été appelé mais la scène n'est pas encore chargée **:** `get_current_state()` retourne l'état courant du GSM au moment du call (PLAYING ou état intermédiaire). Si GSM est encore PLAYING, `request_pause()` est appelé — GSM contient sa propre guard d'idempotence (ADR-0007) et rejette silencieusement l'appel si une transition est déjà en cours. Pas de double-transition, pas de crash. Le Menu ne duplique pas cette guard (R-MNU-17).

### EC-MNU-3 — ESC pressé pendant le chargement Main Menu → étage

- **If** `ui_cancel_pressed` est émis pendant le fade noir GSM (layer 100) entre `main_menu.tscn` et `etage_01.tscn` **:** `PauseMenuControllerScript` n'est pas encore instancié (scène étage en cours de chargement) — aucun handler `_on_ui_cancel` connecté. Le signal est émis par InputManager (ADR-0004 D-4 — émis même si `enabled == false`) mais n'a aucun subscriber actif. No-op par absence de consumer. Aucun crash, aucun état corrompu.

### EC-MNU-4 — ESC pressé en BOSS_DEFEATED

- **If** `_on_ui_cancel()` est appelé alors que `GSM.get_current_state() == State.BOSS_DEFEATED` **:** bras `_:` → `pass`. No-op silencieux. État terminal post-MVP géré par un système distinct (hors scope Menu). Le Pause Overlay reste caché (sa visibility est `false` pour tout état autre que PAUSED — R-MNU-15).

### EC-MNU-5 — ESC double-pressé même frame

- **If** `ui_cancel_pressed` est émis deux fois dans le même `_physics_process` tick (ex. : rebond input, double événement) **:** le premier appel change l'état GSM (PLAYING → PAUSED ou PAUSED → PLAYING). Le second appel lit `get_current_state()` et obtient le nouvel état — il produit l'effet inverse ou un no-op idempotent si GSM guard rejette. Résultat net : état cohérent, jamais de crash. Comportement perçu : toggle (pause puis reprise immédiate) ou no-op selon l'ordre de réception. Pas de protection supplémentaire dans le Menu — idempotence déléguée au GSM.

### EC-MNU-6 — ESC pressé avant que PauseOverlay soit dans le tree (boot race)

- **If** `ui_cancel_pressed` est émis pendant le `_ready()` de la scène étage, avant que le signal `InputManager.ui_cancel_pressed.connect(_on_ui_cancel)` soit exécuté dans `PauseMenuControllerScript._ready()` **:** signal émis sans subscriber Menu actif → no-op. Dès que `_ready()` se termine, la connexion est établie. Aucun état manqué car le `_ready()` inclut un pattern pull `get_current_state()` (R-MNU-4) — si l'état est déjà PAUSED à l'issue du `_ready()`, `_apply_visibility(true)` est appelé immédiatement.

### EC-MNU-7 — ESC pressé en state MENU (Main Menu visible)

- **If** `ui_cancel_pressed` est émis alors que la scène active est `main_menu.tscn` **:** `PauseMenuControllerScript` n'est pas instancié dans cette scène — aucun subscriber. No-op silencieux. `MainMenuControllerScript` ne connecte pas `ui_cancel_pressed` (R-MNU-5 — le Main Menu n'a pas de contexte "fermer"). L'ESC est ignoré sur le menu racine, cohérent avec K.6.

### EC-MNU-8 — Pause overlay instancié deux fois dans la même scène (bug authoring)

- **If** `pause_overlay.tscn` est instancié deux fois comme enfant de la scène étage (erreur d'auteur level) **:** les deux instances connectent `state_changed` et `ui_cancel_pressed` indépendamment. Au premier ESC, les deux handlers s'exécutent : double `request_pause()` (GSM idempotent, second appel ignoré) et double `request_disable(&"PauseMenu")` (ADR-0004 D-4 refcount — EC-MNU-22 couvre l'idempotence owner). Visuellement : deux overlays superposés, `DimRect` doublé (alpha apparent 0.87 vs 0.65). Comportement défini, pas crash. Détectable en CI via `grep -c "pause_overlay"` dans `.tscn` : > 1 occurrence = warning lint authoring.

### EC-MNU-9 — Pause overlay détruit pendant ouverture (Level purge nœuds)

- **If** un bug Level purge les nœuds enfants de l'étage alors que le Pause Overlay est en cours d'affichage (state PAUSED, `visible = true`) **:** `tree_exiting` déclenché sur `PauseOverlayRoot`. Le `_notification(NOTIFICATION_PREDELETE)` ou `tree_exiting` signal doit appeler `InputManager.release_enable_request(&"PauseMenu")` pour éviter un refcount orphelin. Pattern : connecter `tree_exiting.connect(_cleanup_input_refcount)` dans `_ready()`. Si le release n'est pas exécuté, InputManager garde un owner mort dans son refcount — InputManager ne peut pas réactiver les inputs (ADR-0004 D-4 multi-owner). Mitigation : le Level System ne doit pas purger les nœuds hors `queue_free` propre, mais le guard `tree_exiting` est la défense en profondeur.

### EC-MNU-10 — Scene change PAUSED → MainMenu pendant que Pause overlay est visible

- **If** "Quitter vers Menu Principal" est cliqué alors que Pause Overlay est visible (PAUSED) **:** `_on_main_menu_pressed` appelle d'abord `_apply_visibility(false)` (qui exécute `release_enable_request(&"PauseMenu")` + `set_mouse_captured(true)`) puis `GSM.request_scene_transition("res://scenes/menus/main_menu.tscn")`. Le GSM déclenche `change_scene_to_file` qui détruit la scène étage — le Pause Overlay est détruit automatiquement en tant qu'enfant. Le release du refcount InputManager DOIT précéder l'appel GSM (R-MNU-10, transitions critiques). `set_mouse_captured(true)` est immédiatement corrigé par `main_menu.tscn._ready()` qui appelle `set_mouse_captured(false)` — pas de fenêtre visible avec souris capturée.

### EC-MNU-11 — Pause overlay reste visible après transition vers PLAYING (signal manqué)

- **If** `state_changed(PLAYING)` est émis mais le handler `_on_state_changed` n'est pas appelé (ex. : connexion `CONNECT_DEFERRED` exécutée après une compaction de frame anormale) **:** à la prochaine interaction (prochain ESC ou prochain `state_changed`), le pattern pull n'est pas re-invoqué automatiquement. Mitigation : connexion avec `CONNECT_DEFERRED` garantit livraison dans la frame suivante (Godot garantit DEFERRED avant fin de frame) — la désynchronisation ne devrait pas survenir. Defense en profondeur optionnelle Tier 2+ : un `_process` (en `PROCESS_MODE_ALWAYS`) compare `visible` vs `GSM.get_current_state() == PAUSED` et corrige si divergent. MVP : trust DEFERRED.

### EC-MNU-12 — `set_mouse_captured(true)` appelé depuis app sans focus (Wayland/macOS)

- **If** `InputManager.set_mouse_captured(true)` est appelé alors que la fenêtre n'a pas le focus OS (ex. : alt-tab mid-transition) **:** ADR-0004 D-7 (`focus_regain_window` pattern) — InputManager diffère l'application de `MOUSE_MODE_CAPTURED` jusqu'au prochain `NOTIFICATION_WM_WINDOW_FOCUS_IN`. L'appel depuis le Menu est safe car InputManager absorbe la race condition. Menu n'a pas besoin de guard propre.

### EC-MNU-13 — Bouton "Reprendre" cliqué très vite après ouverture (mouse capture race)

- **If** le joueur clique "Reprendre" dans la même frame que l'affichage du Pause Overlay (ex. : double ESC ultra-rapide suivi d'un clic) **:** `_on_resume_pressed` appelle `GSM.request_resume()`. `_on_state_changed(PLAYING)` est reçu (CONNECT_DEFERRED — frame suivante). `_apply_visibility(false)` exécute `release_enable_request(&"PauseMenu")` + `set_mouse_captured(true)`. La re-capture souris s'effectue après le release du disable — ordre correct. Pas de race : le clic sur un bouton Godot Button est géré via `button_down` / `pressed` signal, pas via InputManager gameplay.

### EC-MNU-14 — Alt-tab pendant Pause Menu ouvert

- **If** l'utilisateur alt-tab hors de la fenêtre pendant que Pause Overlay est visible **:** `Input.MOUSE_MODE_VISIBLE` est déjà actif (R-MNU-12 — Pause Overlay a relâché la capture). La souris reste visible (comportement cohérent). Godot reçoit `NOTIFICATION_WM_WINDOW_FOCUS_OUT` — InputManager ADR-0004 positionne `mouse_mode = VISIBLE` (inchangé). Au retour focus : `NOTIFICATION_WM_WINDOW_FOCUS_IN` → InputManager vérifie le refcount : si un owner `&"PauseMenu"` est actif, `set_mouse_captured` reste `false`. Cohérent ADR-0004 D-7.

### EC-MNU-15 — Resize fenêtre pendant Pause Menu visible

- **If** la fenêtre est redimensionnée pendant que Pause Overlay est visible **:** `PauseOverlayRoot` (CanvasLayer, `FULL_RECT` anchors sur `PausePanel`) se recalcule via le layout Godot Control automatiquement. `DimRect` (`FULL_RECT`) couvre toujours 100 % de la nouvelle surface. `PanelContainer` centré via ancres — repositionné automatiquement. Aucune logique manuelle requise. `set_mouse_captured(false)` reste actif — le curseur reste visible sur le panel repositionné. Aucun glitch de layout si les ancres `FULL_RECT` sont correctement configurées (K.2).

### EC-MNU-16 — Double-clic "Start Run" (start_etage 2× même frame)

- **If** `StartButton.pressed` est émis deux fois consécutivement (double-clic physique, ou deux connexions accidentelles) **:** deux appels `GSM.start_etage(1)`. GSM contient sa propre guard d'idempotence (ADR-0007) — le second appel pendant une transition en cours est ignoré ou retourne immédiatement. La scène étage n'est chargée qu'une fois. Pas de double-load. `MainMenuControllerScript` ne pose pas de guard propre — délégation au GSM (R-MNU-7).

### EC-MNU-17 — Double-clic "Quitter le jeu"

- **If** `QuitButton.pressed` est émis deux fois dans la même frame **:** le premier appel `get_tree().quit()` déclenche la terminaison du process Godot. Le second appel est sans effet — le process est déjà en cours de shutdown. `get_tree().quit()` est idempotent côté Godot (double call safe). `NOTIFICATION_WM_CLOSE_REQUEST` n'est émis qu'une fois — SaveLoadSystem intercepte une seule fois (R-MNU-17b).

### EC-MNU-18 — Clic "Reprendre" pendant que state_changed(PLAYING) n'a pas encore propagé

- **If** `ResumeButton` est cliqué alors que GSM est déjà en PLAYING mais que `state_changed(PLAYING)` n'a pas encore été reçu par le Pause Overlay (CONNECT_DEFERRED — latence 1 frame) **:** `_on_resume_pressed` appelle `GSM.request_resume()`. GSM est déjà PLAYING — `request_resume` en PLAYING est idempotent (EC-MNU-26 — no-op). Aucun double-state. Le `state_changed(PLAYING)` arrivera à la frame suivante et appellera `_apply_visibility(false)` → cleanup normal.

### EC-MNU-19 — Clic "Quitter vers Menu Principal" depuis Pause Menu (vérification matrice ADR-0007)

- **If** "Quitter vers Menu Principal" est cliqué depuis Pause Menu (state PAUSED) **:** `request_scene_transition(menu_path)` est un verbe GSM figé (ADR-0007 D-10) appelable depuis PAUSED — la matrice ADR-0007 autorise explicitement PAUSED → MENU via ce verbe. Pas de transition illégale. Release InputManager DOIT précéder l'appel (R-MNU-10 — ordre garanti dans `_on_main_menu_pressed`). GSM applique `get_tree().paused = false` avant `change_scene_to_file` pour éviter que la scène étage reste gelée pendant le chargement.

### EC-MNU-20 — Clic "Start Run" alors que GSM n'est pas en MENU

- **If** `StartButton.pressed` est émis alors que `GSM.get_current_state() != MENU` (impossible UX car `main_menu.tscn` n'est chargée qu'en état MENU, mais guard défensif) **:** `MainMenuControllerScript._on_start_run_pressed` appelle `GSM.start_etage(1)` sans vérification préalable d'état. GSM rejette l'appel via sa propre guard si l'état courant ne permet pas la transition MENU → PLAYING (ADR-0007 D-2 matrice). Résultat : no-op GSM, log warning. Pas de scène rechargée, pas de crash. Pattern "déléguer au GSM" (R-MNU-7) couvre ce cas.

### EC-MNU-21 — `request_disable(&"PauseMenu")` appelé deux fois même owner

- **If** `InputManager.request_disable(&"PauseMenu")` est appelé deux fois consécutifs par le même owner (ex. : `state_changed(PAUSED)` reçu deux fois par bug de reconnexion signal) **:** ADR-0004 D-4 refcount multi-owner — le refcount pour `&"PauseMenu"` est un Set (ou Dictionary keyed par owner), pas un compteur numérique. Second appel avec même owner = idempotent, pas de double-compte. `release_enable_request(&"PauseMenu")` un seul call suffit à retirer cet owner.

### EC-MNU-22 — `release_enable_request` appelé sans `request_disable` préalable

- **If** `InputManager.release_enable_request(&"PauseMenu")` est appelé sans qu'un `request_disable` correspondant ait été posé (ex. : Pause Overlay détruit avant ouverture, ou cleanup appelé deux fois) **:** ADR-0004 D-4 spécifie `push_warning("release called without matching request")` + no-op. Pas de crash, pas de refcount négatif. Le refcount pour cet owner est absent → appel ignoré proprement.

### EC-MNU-23 — Pause overlay détruit avant `release_enable_request` (tree_exiting)

- **If** `PauseOverlayRoot` est détruit (ex. : `change_scene_to_file` détruit la scène étage) alors que le refcount `&"PauseMenu"` est encore actif **:** `tree_exiting` signal connecté dans `_ready()` → `_cleanup_input_refcount` appelle `InputManager.release_enable_request(&"PauseMenu")` avant que le nœud soit purgé. Auto-cleanup garantit pas de refcount orphelin. Cohérent ADR-0004 D-4 : "tree_exited auto-cleanup" contractuel.

### EC-MNU-24 — Multi-owner actif simultané (Menu + futur système Tier 2+)

- **If** un futur système (ex. : Cutscene System Tier 2+) a posé `request_disable(&"Cutscene")` et que le Pause Menu fait ensuite `release_enable_request(&"PauseMenu")` **:** ADR-0004 D-4 refcount — `enabled` reste `false` tant qu'au moins un owner est dans le Set. Release Menu seul ne réactive pas InputManager. InputManager ne redevient actif que quand tous les owners ont releasé. Comportement correct — Menu ne peut pas accidentellement réactiver les inputs pendant une cutscene.

### EC-MNU-25 — Tentative d'ouvrir Pause Menu en MENU state

- **If** `ui_cancel_pressed` est émis depuis `main_menu.tscn` **:** `PauseMenuControllerScript` n'est pas instancié dans cette scène → aucun handler connecté. No-op par absence de subscriber. `MainMenuControllerScript` ne connecte pas ce signal (R-MNU-5). ESC est silencieusement ignoré sur le menu racine.

### EC-MNU-26 — `request_resume` appelé en PLAYING (idempotence GSM)

- **If** `GSM.request_resume()` est appelé alors que l'état courant est déjà PLAYING **:** GSM guard (ADR-0007 D-2 matrice) — PLAYING → PLAYING n'est pas une transition valide. Appel ignoré, `state_changed` n'est pas réémis. Pas de double-event, pas de double-apply_visibility. Menu reste cohérent.

### EC-MNU-27 — `request_pause` appelé en PAUSED (idempotence GSM)

- **If** `GSM.request_pause()` est appelé alors que l'état courant est déjà PAUSED **:** même guard ADR-0007 — no-op, `state_changed` non réémis. `request_disable(&"PauseMenu")` potentiellement appelé deux fois — couvert par EC-MNU-21 (idempotent).

### EC-MNU-28 — `request_scene_transition` pendant transition déjà en cours

- **If** `request_scene_transition("res://scenes/menus/main_menu.tscn")` est appelé alors qu'une transition de scène GSM est déjà en cours **:** GSM sérialise les transitions (ADR-0007 D-5) — pas de lock côté GSM MVP, second appel ignoré ou mis en queue selon l'implémentation GSM. Le Menu ne pose pas de lock propre (R-MNU-17 — délégation au GSM). Comportement défini : cohérent GSM EC-3.

### EC-MNU-29 — Focus initial Main Menu au boot

- **If** `main_menu.tscn` est chargé pour la première fois (boot) **:** `MainMenuControllerScript._ready()` appelle `StartButton.grab_focus()`. Premier bouton focusé = "Start Run". Tab cycle : Start Run → Quitter le jeu → (wrap) Start Run. Navigation clavier opérationnelle dès la première frame visible. Conforme K.6.

### EC-MNU-30 — Focus initial Pause Menu à l'ouverture

- **If** `state_changed(PAUSED)` est reçu par `PauseMenuControllerScript` **:** `_on_state_changed` appelle `_apply_visibility(true)` puis `ResumeButton.grab_focus()`. Premier bouton focusé = "Reprendre". Tab cycle : Reprendre → Quitter vers Menu Principal → Quitter le jeu → (wrap) Reprendre. Navigation clavier disponible immédiatement sans clic souris intermédiaire. Conforme K.6.

### EC-MNU-31 — `state_changed(PAUSED)` reçu avant que Pause overlay soit dans le tree

- **If** `state_changed(PAUSED)` est émis par GSM pendant le `_ready()` de la scène étage, avant que `PauseMenuControllerScript` ait connecté le signal **:** le signal est émis SYNC (ADR-0007 D-6 — `state_changed` est SYNC) mais la connexion `CONNECT_DEFERRED` n'est pas encore établie → signal manqué. Mitigation : pattern pull dans `_ready()` (R-MNU-4) — après connexion du signal, `get_current_state()` est appelé et `_apply_visibility` est forcé en fonction de l'état courant. Si GSM est en PAUSED à la fin du `_ready()`, le Pause Overlay s'affiche correctement sans avoir besoin du signal manqué.

### EC-MNU-32 — Pause overlay caché par défaut avant connexion signal

- **If** `PauseOverlayRoot.visible` est `true` par erreur dans la scène `.tscn` (attribut mal sauvegardé) **:** `PauseMenuControllerScript._ready()` appelle pattern pull → `get_current_state()` retourne PLAYING → `_apply_visibility(false)` → `visible = false` forcé avant la première frame rendue. Corrigé silencieusement sans artefact visuel. L'authoring bug est corrigible par CI (`grep "visible = true" pause_overlay.tscn` dans la scène root → warning).

### EC-MNU-33 — Visibility flicker entre snap show/hide

- **If** `state_changed(PAUSED)` et `state_changed(PLAYING)` sont émis dans la même frame (ex. : GSM bug transition rapide) **:** deux appels `_apply_visibility` consécutifs dans la même frame — CONNECT_DEFERRED garantit exécution dans la frame suivante, donc les deux calls arrivent dans des frames différentes. Aucun flicker possible via CONNECT_DEFERRED. Si CONNECT_ONESHOT ou connexion directe (sans DEFERRED) était utilisée, un flicker 1-frame serait possible — raison supplémentaire pour maintenir CONNECT_DEFERRED sur `state_changed` (R-MNU-4).

### EC-MNU-34 — Quit depuis Pause Menu (release refcount avant exit)

- **If** "Quitter le jeu" est cliqué depuis Pause Menu **:** `_on_quit_pressed` appelle `release_enable_request(&"PauseMenu")` puis `get_tree().quit()` (R-MNU-11). Le release est techniquement sans effet sur le process qui va se terminer, mais est maintenu pour la propreté : si un futur test d'intégration mocke `get_tree().quit()`, le refcount est correctement nettoyé. `NOTIFICATION_WM_CLOSE_REQUEST` est émis par Godot → SaveLoadSystem intercepte (R-MNU-17b).

### EC-MNU-35 — Crash mid-pause (next boot sans état corrompu)

- **If** le jeu crash pendant que Pause Overlay est visible (state PAUSED) **:** au prochain boot, GSM démarre en état MENU (état initial défini ADR-0007 D-1 — pas d'état persisté cross-session). `main_menu.tscn` est chargée directement. Aucun "pending pause" à hydrater — le Menu System est stateless cross-session MVP (pas de `user://` state pour le menu). InputManager démarre avec refcount vide (aucun `request_disable` orphelin — le crash a tué le process entier). Boot propre garanti.

### EC-MNU-36 — Quit pendant `change_scene_to_file` en cours (LOADING phase) *(r2 — S-3)*

- **If** le joueur clique "Quitter le jeu" depuis Main Menu pendant qu'une transition vers étage est déjà engagée (`start_etage` appelé, `change_scene_to_file` en cours, `main_menu.tscn` en cours de déchargement) **:** Godot émet `NOTIFICATION_WM_CLOSE_REQUEST` quel que soit l'état de transition en cours. Save/Load r1 R-SAV-9 garantit que SaveLoadSystem (autoload pos-3 PROCESS_MODE_ALWAYS) reçoit la notification **avant destruction de l'arbre** (ADR-0007 D-1 — autoloads détruits après scene root). Le quit fonctionne même si `MainMenuController` est en train d'être détruit. Aucun crash, aucune fuite. Si le second clic Quit arrive après que le process a déjà commencé à terminer (race extrême), `get_tree().quit()` est idempotent côté Godot (EC-MNU-17). Pattern OQ-MNU-1 RESOLVED option (a) couvre ce cas.

### EC-MNU-37 — Window minimize pendant Pause Menu visible *(r2 — S-5)*

- **If** l'utilisateur minimise la fenêtre OS (Win + D, dock click macOS, click sur titre) pendant que Pause Overlay est visible (state PAUSED) **:** Godot émet `NOTIFICATION_WM_WINDOW_MINIMIZED` (distinct de `NOTIFICATION_WM_WINDOW_FOCUS_OUT` qui est envoyé sur alt-tab). Le Pause Overlay continue d'exister en mémoire avec `visible = true`. `get_tree().paused` reste `true` (set par GSM). Aucun render n'est effectué pendant le minimize (Godot pause le rendu en background). Au restore (`NOTIFICATION_WM_WINDOW_RESTORED`), le rendu reprend exactement où il s'était arrêté — Pause Overlay visible, gameplay gelé. Mouse capture reste `false` (R-MNU-12). Aucun glitch perceptible. Menu n'a rien à faire — Godot gère la suspension/reprise rendu nativement.

### EC-MNU-38 — Sleep / wake OS pendant Pause Menu visible *(r2 — S-6)*

- **If** l'OS entre en sleep mode (hibernation macOS / sleep Windows) alors que le jeu tourne en état PAUSED (Pause Overlay visible) **:** au wake, le process Godot reprend où il s'était arrêté. `Time.get_ticks_msec()` continue depuis le moment du sleep — il n'y a pas de "delta sleep" injecté. Pause Overlay reste visible, GSM reste PAUSED, refcount InputManager intact. Comportement identique à un long minimize (EC-MNU-37). Si une animation Tier 2+ était active au moment du sleep, elle reprendrait depuis sa frame d'arrêt (pas de "skip" temporel) — MVP zéro animation = aucun risque. Le `state_changed(PLAYING)` éventuel reçu pendant le sleep est queue-é dans la signal queue Godot et délivré au wake (CONNECT_DEFERRED garantit livraison à la frame suivante).

### EC-MNU-39 — Controller hot-plug pendant Pause Menu visible *(r2 — S-7)*

- **If** un gamepad est branché ou débranché USB pendant que Pause Overlay est visible **:** Godot émet `Input.joy_connection_changed` signal. Aucun handler Menu MVP n'écoute ce signal (gamepad support = stretch goal Tier 2+). Le Pause Overlay reste fonctionnel via clavier/souris. **Risque résiduel** : si le gamepad émet un signal `pressed` automatique au branchement (boutons "fantôme"), il est consommé par `InputManager.ui_cancel_pressed` ou `ui_confirm_pressed` selon le mapping → peut activer un bouton focusé sans intention utilisateur. **Mitigation MVP** : ignorer (gamepad MVP=stretch). Tier 2+ : ajouter un debounce 100 ms après `joy_connection_changed` qui bloque les inputs gamepad. Aucun crash, comportement défini mais imperfect MVP.

### EC-MNU-40 — Lifecycle PRE_READY (visible state transient avant `_ready()`) *(r2 — S-12)*

- **If** `pause_overlay.tscn` est instancié dans une scène étage et la racine `PauseLayer.visible` est `true` dans le `.tscn` sauvegardé par erreur d'auteur **:** entre `enter_tree()` et `_ready()`, il existe une fenêtre de 1 frame minimum où la scène est dans le tree avec `visible=true` mais le pattern pull n'a pas encore corrigé l'état. Risque : flash 1 frame de l'overlay avant que `_ready()` exécute `_apply_visibility(false)`. **Mitigation** : le `.tscn` est gardé `visible=false` par défaut (R-MNU-3) — l'authoring lint AC-MNU-58 (legacy) → AC-MNU-62 (r2) grep `visible = true` dans `pause_overlay.tscn` racine retourne 0 match. Couplée avec EC-MNU-32, garantie zéro flash possible.

### EC-MNU-41 — Étage gameplay sans Pause Overlay instancié (zero-instance) *(r2 — G-6 + G-9)*

- **If** un étage `etage_XX.tscn` est créé sans instancier `pause_overlay.tscn` (oubli auteur level) **:** `ui_cancel_pressed` est émis par InputManager mais aucun PauseController n'est subscriber. ESC est silencieusement ignoré sur cet étage — le joueur ne peut pas pauser. Bug perceptuel ("la pause ne marche pas sur l'étage 3") difficile à détecter sans test manuel. **Mitigation lint** : AC-MNU-59 BLOCKING parse les `.tscn` du dossier `scenes/etages/` et exige `grep -c "pause_overlay" etage_*.tscn == 1` pour chaque étage. CI échoue si un étage est sans instance. Détection à l'authoring, pas au runtime.

### EC-MNU-42 — Dual-monitor focus loss pendant Pause Menu visible *(r2 — Q-11)*

- **If** l'utilisateur a deux moniteurs et clique sur un autre moniteur (focus passe à une autre app) pendant que Pause Overlay est visible **:** `NOTIFICATION_WM_WINDOW_FOCUS_OUT` émis par Godot. InputManager (ADR-0004 D-7) gère le `mouse_mode` automatiquement — la souris devient libre (déjà le cas en PAUSED). Au retour focus (clic sur fenêtre Godot), `NOTIFICATION_WM_WINDOW_FOCUS_IN` réapplique `mouse_mode = VISIBLE` (inchangé car PauseMenu refcount actif). **Risque** : si le Menu posait son propre `_notification(NOTIFICATION_WM_WINDOW_FOCUS_*)` handler qui dupliquerait la logique InputManager, double-set du `mouse_mode` créerait une race. **Mitigation par construction** : R-MNU-18 anti-dependency — le Menu n'écoute aucun NOTIFICATION_WM_* directement, délègue à InputManager (single source of truth ADR-0004). Lint AC-MNU-63 BLOCKING `grep -E "NOTIFICATION_WM_WINDOW_FOCUS" src/gameplay/menu/` → 0 match.

## Dependencies

### Hard upstream (le Menu ne fonctionne pas sans ces systèmes)

| System | Statut | Nature | Interface consommée |
|--------|--------|--------|---------------------|
| **GameStateManager** | APPROVED r1 | Hard — orchestrateur de state | 5 verbes publics ADR-0007 D-10 (`start_etage`, `request_pause`, `request_resume`, `request_scene_transition`, `request_new_run` — Menu utilise les 4 premiers MVP, `request_new_run` réservé Boss Tier 2+) ; signal `state_changed(new_state: State)` SYNC consommé via CONNECT_DEFERRED côté Menu ; getter `get_current_state()` pattern pull au `_ready` (ADR-0007 D-9) ; enum `State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }` immutable. |
| **InputManager** | In Review r6 (structure PASS) | Hard — refcount + signaux UI | API ADR-0004 D-4 : `request_disable(owner)` / `release_enable_request(owner)` posés par PauseMenu ; `set_mouse_captured(captured: bool)` setter ; signal `ui_cancel_pressed` (toujours émis même `enabled==false`) ; signal `ui_confirm_pressed` (consommé par Godot via les Buttons). |
| **Godot SceneTree** | Engine (Godot 4.6) | Hard — primitive engine | `get_tree().quit()` pour bouton "Quitter le jeu" (Menu autorisé — c'est l'unique site MVP qui appelle quit, conforme R-MNU-8/11). `change_scene_to_file` est appelé par GSM, pas par Menu directement. |

### Soft upstream / latent

| System | Statut | Nature | Interface |
|--------|--------|--------|-----------|
| **SaveLoadSystem** (Not Started) | Soft — quit save | Au clic "Quitter le jeu" depuis Pause ou Main Menu, Godot émet `NOTIFICATION_WM_CLOSE_REQUEST`. SaveLoadSystem (futur) intercepte dans son propre handler `_notification` (autoload `PROCESS_MODE_ALWAYS`) — Menu n'orchestre PAS save explicite. Cohérent GSM EC-6. **Pas de bloquage MVP** : si SaveLoadSystem n'existe pas encore, le quit fonctionne pareil (sans persistance). |
| **AudioSystem** | APPROVED r2.1 | Soft — ducking PAUSED owned Audio | Audio écoute `state_changed` GSM pour ducker Music -12 dB en PAUSED (cf. GSM Visual/Audio §). Menu n'émet aucun signal Audio MVP (zéro SFX). Tier 2+ : si SFX menu introduits → bus `MENU_UI` ou réutilisation `UI` (amendement Audio r2.2 requis). |

### Peers (cousins — cross-talk via GSM ou rien)

| System | Statut | Nature | Détail |
|--------|--------|--------|--------|
| **HUDSystem** | Designed r1 | Peer — visibility coordination | HUD écoute `state_changed` indépendamment du Menu et hide en MENU/PAUSED (HUD r1 R-7). Menu n'émet aucun signal vers HUD. Aucun conflit visuel : HUD layer=50, Pause overlay layer=80 (Pause par-dessus). |
| **ShopSystem** | Designed r1 | Peer — Menu cible | Shop r1 bouton "Continuer" appelle `GSM.start_etage(next_etage_id)` ; Shop bouton "Main Menu" appelle `GSM.request_scene_transition("res://scenes/menus/main_menu.tscn")`. Le Menu reçoit ces transitions passivement via state_changed côté GSM — aucun couplage direct Shop↔Menu. Layer Shop=60 vs Pause=80 ; Shop est sa propre scène container, jamais coexistant avec Pause overlay. |
| **CameraSystem** | In Review r2 | Peer — pas de couplage MVP | Aucun couplage. Tier 2+ : Main Menu pourrait avoir une Camera3D décorative (cyber-ronin idle pose) — exige amendement de ce GDD. |
| **LevelSystem** | APPROVED r3 | Anti-dependency stricte | Menu **ne connaît pas** Level. Seul GSM appelle `LevelSystem.load_etage(id)` après `start_etage(id)`. Aucun import, aucune référence Level dans le code Menu. Forbidden pattern : `preload("res://src/gameplay/level/...")` dans `main_menu_controller.gd` ou `pause_menu_controller.gd`. |
| **CombatSystem** | APPROVED r6 | Anti-dependency stricte | Menu ne connaît pas Combat. Sécurité : pas de "stats kills" dans pause overlay MVP. |
| **MovementController** | In Review r3 | Anti-dependency stricte | Menu ne connaît pas Movement. Sécurité : pas de "vélocité actuelle" affichée. |
| **CreditEconomy** | Designed r1 | Anti-dependency stricte | Menu ne lit pas `total_credits`. Pillar 3 SECONDE CHANCE : pas de stats summary post-mortem. |
| **SecretSystem** | Designed r1 | Anti-dependency stricte | Menu ne lit pas l'état des secrets. |

### Bidirectional check (réciprocité)

- **GameStateManager** §Dependencies Downstream cite déjà : "MenuSystem (inferred, Not Started) | Hard | Lit `get_current_state()` pattern pull au `_ready`, écoute `state_changed`. Appelle les 5 verbes MVP" ✅ bidirectionnel CONFIRMÉ par ce GDD r1 (réciprocité formelle établie — GSM peut promote `MenuSystem (inferred, Not Started)` → `MenuSystem (Designed r1)` en amendement éditorial).
- **InputManager** : InputManager est consommé one-way par les owners de refcount (Pause Menu ici). Aucune réciprocité formelle requise — InputManager ignore les owners par design ADR-0004 D-4.
- **HUDSystem** §Dependencies cite peers Tier 2+ (cooldown ratio, room indicator) mais pas Menu — pas de réciprocité requise (HUD et Menu sont des peers passifs qui écoutent GSM indépendamment).
- **ShopSystem** §Dependencies Soft cite "Menu System (Not Started — sibling) — bouton Continuer pointe ici" → réciprocité **partielle** établie côté Shop ; ce GDD complète : "Shop r1 cible `main_menu.tscn` via GSM.request_scene_transition" ✅.
- **AudioSystem** : Audio r2.1 ne cite pas Menu (zéro SFX MVP cohérent) — réciprocité non requise. Tier 2+ : amendement Audio r2.2 si bus `MENU_UI` introduit.

### Provisional contracts (à valider lors de l'écriture des dépendances) *(r2 — S-10 expansion)*

| Contract | Owner Menu | Owner provider | Status |
|----------|-----------|----------------|--------|
| `NOTIFICATION_WM_CLOSE_REQUEST` save handler | Menu n'intercepte PAS | SaveLoadSystem (Save/Load r1 R-SAV-9) | **RESOLVED 2026-04-27** (r2 cosmetic) — Save/Load r1 ratifie délégation pure (option a) ; OQ-MNU-1 fermée |
| `NOTIFICATION_WM_WINDOW_FOCUS_IN/OUT` | Menu n'écoute PAS (R-MNU-18) | InputManager (ADR-0004 D-7 single source of truth) | **CONFIRMED 2026-04-27** (r2) — lint AC-MNU-63 enforce 0 match Menu côté ; double-set `mouse_mode` impossible par construction |
| `NOTIFICATION_WM_WINDOW_MINIMIZED` / `_RESTORED` | Menu n'écoute PAS | Godot natif (rendu suspendu) | **CONFIRMED 2026-04-27** (r2 — EC-MNU-37) — aucun handler Menu requis, suspension/reprise rendu native Godot |
| `get_tree().paused` mutation autorité | Menu **lit** uniquement (jamais set) | GameStateManager (ADR-0007 D-4 unique authority) | **CONFIRMED** — AC-MNU-50 BLOCKING enforce 0 match `get_tree().paused = ` côté Menu |
| `ui_cancel_pressed` always emit (même `enabled == false`) | Menu (consommateur PauseController uniquement) | InputManager r6 (ADR-0004 D-4) | **CONFIRMED Input r6** — structure PASS par fresh design-review ; à re-vérifier post InputManager r6 amendement final si ACs modifiés |
| `set_mouse_captured(bool)` setter public | Menu (consommateur R-MNU-12) | InputManager (ADR-0004 D-7) | **CONFIRMED 2026-04-27** (r2 — R-MNU-20) — API stable figée, idempotente |
| `MENU_UI` bus audio Tier 2+ | Menu (consommateur si SFX introduits) | AudioSystem r2.2 | OQ-MNU-2 — différé Tier 2+ |
| `accessibility_font_scale` setting | Menu (consommateur) | Future SettingsManager Tier 2+ | OQ-MNU-3 — différé Tier 2+ |
| `prefers-reduced-motion` flag OS | Menu (consommateur Tier 2+) | Future AccessibilityManager Tier 2+ (lit `OS.is_reduce_motion_enabled()` Godot 4.5+) | OQ-MNU-3 — MVP de facto satisfait par zéro animation (K.7) ; AC-MNU-64 ADVISORY r2 enforce 0 tween même si flag OS désactivé |

## Tuning Knobs

### MVP design-active (modifiables sans amendement ADR/GDD)

| Knob | Default | Safe Range | Unit | What it affects | Out-of-range behavior |
|------|---------|------------|------|------------------|------------------------|
| `MENU_BG_OVERLAY_ALPHA` | 0.65 | [0.55, 0.75] | float | Alpha du `DimRect` derrière le Pause panel (F-MNU-2) — lisibilité vs contact avec le monde gelé. | < 0.55 : texte blanc se confond avec gameplay clair. > 0.75 : effet écran noir, perte de contact monde. |
| `PAUSE_PANEL_WIDTH_PX` | 360 | [300, 480] | int (px) | Largeur fixe du `PanelContainer` Pause Menu. | < 300 : "Quitter vers Menu Principal" tronqué à 15 px monospace. > 480 : panel domine le viewport 1280×720. |
| `PAUSE_PANEL_PADDING_VERTICAL_PX` | 32 | [16, 64] | int (px) | Padding interne haut/bas du PanelContainer. | < 16 : texte collé aux bords. > 64 : panel inutilement grand. |
| `PAUSE_PANEL_PADDING_HORIZONTAL_PX` | 40 | [24, 64] | int (px) | Padding interne gauche/droite. | < 24 : boutons collés aux bords. > 64 : panel inutilement large. |
| `BUTTON_SEPARATION_PX_MAIN` | 16 | [8, 32] | int (px) | Spacing VBoxContainer Main Menu entre Start Run et Quit. | < 8 : boutons collés. > 32 : trop d'espace, layout dilué. |
| `BUTTON_SEPARATION_PX_PAUSE` | 12 | [8, 24] | int (px) | Spacing VBoxContainer Pause Menu (3 boutons, espace plus contraint). | Idem. |
| `TITLE_FONT_SIZE_PX` | 28 | [22, 40] | int (px) | Taille titre "CHROME://ASCENT" Main Menu (K.3). | < 22 : titre invisible 1080p. > 40 : déborde 720p. |
| `BUTTON_FONT_SIZE_PX` | 15 | [13, 18] | int (px) | Taille texte boutons (Main + Pause). | < 13 : illisible. > 18 : casse layout, déborde panel 360 px à 18 px monospace. |
| `BUTTON_MIN_WIDTH_PX` | 220 | [180, 280] | int (px) | `custom_minimum_size.x` boutons (K.5). | < 180 : "Quitter vers Menu Principal" tronqué. > 280 : boutons inutilement larges en Main Menu. |

### Knobs structurels (modification = amendement ADR ou GDD requis)

| Knob | Default | Justification | Amendement requis |
|------|---------|--------------|-------------------|
| `PAUSE_CANVAS_LAYER` | 80 | Convention layer projet : HUD=50 (HUD r1), Shop=60 (Shop r1), Pause=80, GSM transition fade=100. | Amendement ce GDD §K.2 + cohérence cross-GDD. |
| `PAUSE_OVERLAY_PROCESS_MODE` | `PROCESS_MODE_ALWAYS` (5) | Boutons interactifs sous `get_tree().paused = true` impose ALWAYS (R-MNU-14 r2). WHEN_PAUSED (4) exécute uniquement quand `paused=true` — théoriquement suffisant mais expose à une race fenêtre entre `state_changed(PAUSED)` reçu et `paused=true` propagé par GSM. ALWAYS retenue par robustesse + simplicité (toujours actif, jamais de race). | Amendement ADR-0007 D-4 si changement. |
| `MAIN_MENU_SCENE_PATH` | `"res://scenes/menus/main_menu.tscn"` | Path canonique cité par Shop r1 R-SHP-11, ce GDD R-MNU-9, GSM EC-10. | Amendement GSM + Shop + ce GDD si renommé. |
| `BOOT_MAIN_SCENE` | `"res://scenes/menus/main_menu.tscn"` | `project.godot` `application/run/main_scene`. ADR-0007 D-9 boot pattern. | Amendement ADR-0007 si changement. |

### Knobs visuels Chrome Zen (tokens K.4 — modifiables si playtest visuel le justifie)

| Token | Default | Modifiable ? |
|-------|---------|--------------|
| `MENU_BG_BLACK` | `#050608` | Oui — coordination cross-GDD si écart de Shop_BG `#0A0A12` étendu (cohérence). |
| `MENU_PANEL_BG` | `#0A0A12` | Oui — doit rester aligné Shop_BG. |
| `MENU_PANEL_BORDER` | `#2A2A3A` | Oui — bordure subtile, peu critique. |
| `MENU_TEXT_BASE` | `#E8E8F0` | Non — token cross-projet identique HUD r1 + Shop r1. Modification = amendement 3 GDD. |
| `MENU_TEXT_SECONDARY` | `#6E6E8A` | Oui — usage limité (PAUSE label optionnel, version number). |
| `MENU_ACCENT_CYAN` | `#3EE4FF` | Non — token cross-projet identique Shop r1 + Secret r1. Modification = amendement 3 GDD. |
| `MENU_BTN_PRESSED_BG` | `#111120` | Oui — état pressed bouton, peu critique. |
| `MENU_BTN_DISABLED_TEXT` | `#3C3C50` | Oui — réservé Tier 2+. |

### Tier 2+ knobs réservés (hors scope MVP — amendement requis pour activer)

| Knob | Tier | Trigger d'activation |
|------|------|----------------------|
| `MENU_FADE_DURATION_MS` | Tier 2+ | Si playtest demande fade in/out doux (actuellement snap MVP — Player Fantasy Pacte Pillar 1 interdit). Amendement Player Fantasy + F-MNU-5 + Visual/Audio. |
| `accessibility_font_scale` | Tier 2+ | Activation Settings Menu Tier 2+ (cf. K.9 Tier 3). Range proposé [0.75, 1.5]. |
| `MENU_REDUCE_MOTION` | Tier 2+ | Si Tier 2+ introduit animations (settings slide-in, etc.) → flag accessibility pour les désactiver. |
| `MENU_UI_BUS_VOLUME_DB` | Tier 2+ | Si Audio r2.2 introduit bus `MENU_UI` (SFX boutons hover/click). MVP zéro SFX. |
| `MAIN_MENU_BG_PARALLAX_ENABLED` | Tier 2+ | Si direction artistique Tier 2+ ajoute camera décorative + parallax (actuellement interdit Player Fantasy anti-fantasy). Décision irréversible — exige amendement formel art-bible + ce GDD. |

## Visual/Audio Requirements

### Visual — Chrome Zen alignement

Le Menu System hérite intégralement de la direction Chrome Zen établie par HUD r1 et Shop r1. Aucune nouvelle décision visuelle n'est introduite — le Menu se conforme aux tokens existants.

**Palette tokens MVP** (cf. Section UI Requirements §K.4 pour la table complète) :

- Fond Main Menu : `#050608` (presque noir pur, plus sombre que Shop pour distinguer "scène container nue" vs "overlay avec panel").
- Fond Pause panel : `#0A0A12` (cohérent Shop).
- Texte primaire : `#E8E8F0` (token cross-GDD HUD/Shop/Menu).
- Accent unique cyan : `#3EE4FF` (token cross-GDD Shop/Secret/Menu — focus, hover underline, border focus).
- DimRect overlay alpha : `0.65` (F-MNU-2 calibré lisibilité vs contact monde).

**Géométrie** :

- Hard-edge : `corner_radius_* = 0` partout (AC-MNU-46).
- Aplats uniquement : pas de gradient, pas d'ombre portée, pas de glow (AC-MNU-48).
- Bordures 1 px solid uniquement (panel border, focus rect, hover underline).
- Spacing généreux mais pas dilué : 16 px (Main Menu) / 12 px (Pause Menu) entre boutons.

**Animation** :

- **Aucune animation MVP**. Pas de tween, pas de fade overlay menu (le fade de transition est owned GSM layer 100), pas de hover delay > 0 ms (snap), pas de parallax background, pas de logo animé (AC-MNU-47).
- Les transitions visuelles entre states sont snap : `visible = true/false` au même frame que le `state_changed` reçu (CONNECT_DEFERRED garantit 1 frame max).

**Asset Spec** : différé Tier 2+ — le Menu MVP est purement typographique + ColorRect/PanelContainer Godot natifs. Aucun mesh/texture/sprite/icon-asset à produire MVP. Si Tier 2+ introduit logo, illustration de fond Main Menu, ou icônes boutons → `/asset-spec system:menu-system` après art-bible approval.

### Audio — silence cohérent MVP

**Zéro SFX MVP** (cohérent Audio r2.1 + HUD r1 + Shop r1) :

- Pas de SFX d'ouverture Pause Menu.
- Pas de SFX de fermeture Pause Menu.
- Pas de SFX de hover bouton (focus changed).
- Pas de SFX de clic bouton (button_down / pressed).
- Pas de SFX de Main Menu boot.
- Pas de musique de menu différente — le Main Menu hérite de l'ambient track de l'étage 1 (ou silence si pas de track lounge MVP) ; le Pause Menu hérite de la track étage en cours, **duckée -12 dB owned AudioSystem** sur `state_changed(PAUSED)` (cf. GSM Visual/Audio § + Audio r2.1 ducking règle).

**Le Menu n'émet AUCUN signal vers AudioSystem MVP**. Aucune dépendance Audio dans le code Menu.

**Tier 2+ amendement Audio r2.2 si SFX introduits** :

- Bus dédié `MENU_UI` (parallèle au bus `UI` existant ADR-0009 D-1) ou réutilisation du bus `UI`.
- SFX candidats : button_hover (subtil), button_pressed (clic mécanique court < 50 ms), pause_open / pause_close (whoosh court).
- Volumes calibrés : -3 à -6 dB sous `MENU_TEXT_BASE` musique (assertion subjective).
- OQ-MNU-2 différée Tier 2+.

### Anti-patterns visuels/audio testables (6 lignes)

| Anti-pattern | Test | Rationale |
|--------------|------|-----------|
| SFX au clic / hover bouton | `grep AudioStreamPlayer scenes/menus/` → 0 (AC-MNU-44) | Cohérence Audio r2.1 zero SFX MVP. |
| Animation tween / fade menu | `grep Tween src/gameplay/menu/` → 0 (AC-MNU-36) | Player Fantasy Pacte Pillar 1 snap. |
| Logo animé / splash long | Aucun `AnimationPlayer` dans `main_menu.tscn` (AC-MNU-47) | Anti-fantasy "pas de splash 3s". |
| Parallax background | `grep Parallax scenes/menus/` → 0 (AC-MNU-47) | Distraction non-liée gameplay. |
| Confirm dialog "Quitter ?" | `grep ConfirmationDialog` → 0 (AC-MNU-45) | R-MNU-16 anti-friction. |
| Musique de menu différente | Aucun `AudioStreamPlayer` ni track switch dans Menu code | Cohérence Player Fantasy "un seul univers sonore". |

## UI Requirements

### K.1 — Layout Main Menu

**Architecture de la scène `main_menu.tscn`**

```
main_menu.tscn
└── MainMenuRoot : Control (anchor_preset = FULL_RECT, CanvasLayer.layer = 0 — scène container, pas d'overlay)
    ├── Background : ColorRect (fullscreen, color #050608)
    ├── TitleLabel : Label  (texte "CHROME://ASCENT")
    └── ButtonContainer : VBoxContainer (centré horizontalement + verticalement)
        ├── StartButton : Button ("Start Run")
        └── QuitButton  : Button ("Quitter le jeu")
```

**Positionnement et ancres**

- `MainMenuRoot` : `anchor_preset = FULL_RECT` — couvre 100 % de la fenêtre à toute résolution.
- `ButtonContainer` : ancre centre-centre, `grow_horizontal = BOTH`, `grow_vertical = BOTH`. Margin horizontale minimale : 480 px à gauche et à droite à 1280 × 720 (les boutons ne dépassent pas 320 px de large). Position verticale : centre viewport − 40 px (décalage léger vers le bas du centre optique pour que le titre ait de l'air au-dessus).
- `TitleLabel` : ancré `TOP_WIDE`, padding-top 80 px, centré horizontalement. Pas de positionnement absolu — utiliser `SIZE_FLAGS_EXPAND + FILL` sur un `VBoxContainer` racine si le titre et les boutons sont empilés.
- Spacing `ButtonContainer.separation` : 16 px entre les deux boutons.
- Version number (optionnel MVP) : `Label` ancré `BOTTOM_RIGHT`, taille 11 px, couleur `#3C3C50` (quasi-invisible, couleur secondaire sombre), padding 12 px bord droit / 8 px bord bas. Masqué par défaut — visible uniquement si constante `DEBUG_SHOW_VERSION = true`.

**Breakpoints** *(r2 — U-1 ultrawide + portrait + safe-area documentés)*

| Résolution / Aspect | Remarques |
|---|---|
| 1280 × 720 (16:9 min supportée) | `ButtonContainer` width ≤ 320 px. TitleLabel font-size titre réduit si nécessaire (voir K.3). Valider que les deux boutons restent entièrement visibles sans scroll. |
| 1920 × 1080 (16:9 cible) | Layout de référence. Marges latérales libres, centrage parfait. |
| 2560 × 1440 (16:9 confort) | Boutons ne s'élargissent pas : `custom_minimum_size.x = 240`, `SIZE_FLAGS` sans EXPAND horizontal sur les boutons eux-mêmes. |
| **3440 × 1440 (21:9 ultrawide)** *(r2 — U-1)* | `ButtonContainer` reste centré horizontalement à `viewport.size.x / 2`. Pas de bandes noires ajoutées (les ColorRect/Background couvrent FULL_RECT — fond `MENU_BG_BLACK` étiré sans déformation visuelle car aplat unicolore). Aucune image background MVP, donc zéro stretch artifact. Validé via test manuel `--resolution 3440x1440` sur build dev. |
| **5120 × 1440 (32:9 super-ultrawide)** *(r2 — U-1)* | Même logique que 21:9 — centrage strict. **Garde-fou** : `BUTTON_MIN_WIDTH_PX` (220) reste fixe, le panel n'étire pas. Pas de breakpoint dédié MVP. |
| **Portrait 1080 × 1920 ou rotated 720 × 1280** *(r2 — U-1)* | **Hors scope MVP** — le jeu cible PC desktop landscape (cf. `.claude/docs/technical-preferences.md` : Touch=None). Si une fenêtre est forcée en portrait (utilisateur exotique resize), le layout reste fonctionnel par les ancres `FULL_RECT` — boutons potentiellement débordent verticalement si > 5 boutons (impossible MVP avec N=2/3). Aucun support officiel portrait Tier 2+. |
| **Safe-area** *(r2 — U-1)* | Aucun padding safe-area MVP (PC desktop = pas de notch / pas de software bars). Tier 2+ Steam Deck = ajouter padding 24 px pour les bords arrondis (couvert par `PAUSE_PANEL_PADDING_*` knobs déjà en place). |

### K.2 — Layout Pause Menu

**Architecture de la scène `pause_overlay.tscn`**

```
pause_overlay.tscn
└── PauseLayer : CanvasLayer (layer = 80, process_mode = ALWAYS)
    ├── DimRect : ColorRect (anchor_preset = FULL_RECT, color #000000, alpha 0.65)
    └── PauseRoot : Control (anchor_preset = FULL_RECT)
        └── PanelContainer : PanelContainer (ancré centre-centre)
            ├── PauseTitleLabel : Label ("PAUSE" — optionnel)
            └── ButtonContainer : VBoxContainer
                ├── ResumeButton      : Button ("Reprendre")
                ├── MainMenuButton    : Button ("Quitter vers Menu Principal")
                └── QuitButton        : Button ("Quitter le jeu")
```

**Superposition et transparence**

- `CanvasLayer.layer = 80` : au-dessus du HUD (50) et du Shop (60), en-dessous du fade GSM (100). Conséquence : le fond du gameplay reste visible derrière le `DimRect`.
- `DimRect` : `color = Color(MENU_BG_OVERLAY_ALPHA_RGB, MENU_BG_OVERLAY_ALPHA_A)` *(r2 — U-3 alignement K.4 token)* — la couleur RGB est `#000000` (noir pur, token K.4 `MENU_BG_OVERLAY_RGB`) et l'alpha est `0.65` (token K.4 `MENU_BG_OVERLAY_ALPHA`). **Aucun hex hardcodé `Color(0, 0, 0, 0.65)` inline dans `.tscn` ou script** — référencer le token. Lint AC-MNU-51 (étendu r2 Q-13) enforce déclaration des tokens via `const`. L'alpha 0.65 est le compromis perception du freeze (cf. F-MNU-2 r2 reformulé) : plancher 0.55 (en deçà, le freeze ne lit pas comme "pause") ; plafond 0.75 (au-delà, effet "écran noir", perte contact monde).
- `DimRect` n'est PAS un écran opaque. Le joueur voit son personnage gelé, la géométrie de l'étage, les ennemis au freeze. Cet effet visuel de "monde suspendu" renforce Pillar 1 : le jeu n'a pas disparu, il attend.
- `PanelContainer` : largeur fixe 360 px, hauteur auto-ajustée par contenu. Fond `#0A0A12` (cohérence Shop background). Border : 1 px solid `#2A2A3A`. Padding interne : 32 px haut/bas, 40 px gauche/droite.
- Spacing `ButtonContainer.separation` : 12 px.
- `PauseTitleLabel` : optionnel MVP. Si présent — taille 13 px, `#6E6E8A` (couleur secondaire, sobre). Si absent — aucun titre ; `PanelContainer` commence directement sur `ResumeButton`. Décision : omettre le titre est préférable (Chrome Zen minimal), mais l'inclure aide la lisibilité à 1280×720 bas-contraste.

**Comportement visibility**

- `PauseLayer` est instancié dans chaque scène étage gameplay, `visible = false` par défaut.
- `_on_gsm_state_changed(state)` → si `State.PAUSED` : `visible = true` ; sinon : `visible = false`. Snap instantané, pas de tween.
- `process_mode = ALWAYS` : nécessaire car le scène tree est pausé pendant `PAUSED` (si GSM applique `get_tree().paused = true`). Sans `ALWAYS`, le `_unhandled_input` du Pause Menu ne serait jamais appelé et les boutons seraient non-interactifs.

### K.3 — Typographie

**Police principale**

| Rôle | Police | Fallback 1 | Fallback 2 |
|---|---|---|---|
| Toutes surfaces UI MVP | JetBrains Mono Regular | IBM Plex Mono Regular | Fira Code Regular |

- Fichier TTF embarqué dans `assets/fonts/JetBrainsMono-Regular.ttf` (licence SIL OFL 1.1 — libre, redistribuable dans builds commerciaux).
- Fallback si TTF absent : Godot utilise la police système monospace par défaut. Acceptable en dev, inacceptable en build distribuable — AC-MNU-fonts vérifie la présence du TTF en CI.

**Tailles et graisses**

| Élément | Taille (px) | Graisse | Letter-spacing | Interlignage |
|---|---|---|---|---|
| Titre "CHROME://ASCENT" | 28 px | Bold (JetBrains Mono Bold) | 2 px (léger élargissement) | N/A (monoligne) |
| Label sous-titre / PAUSE | 13 px | Regular | 1 px | N/A |
| Texte bouton | 15 px | Regular | 0 px | N/A |
| Version number (discret) | 11 px | Regular | 0 px | N/A |

- À 1280 × 720, réduire le titre à 22 px si le label déborde horizontalement. Condition : `TitleLabel.size.x > viewport.size.x - 160`. Implémenter via `theme_override_font_sizes` conditionnel dans `_ready()` du contrôleur Main Menu, ou via un `ThemeVariation` préconfiguré.
- Pas de `Bold` sur les boutons — le gras distrait; la sélection par couleur suffit (voir K.5).
- Pas d'italique. Jamais.
- Espacement interligne des VBoxContainers : `separation = 16 px` (Main Menu) / `12 px` (Pause Menu — espace plus contraint).

### K.4 — Palette et tokens

**Table des tokens MVP**

| Token | Valeur hex | Alpha | Usage |
|---|---|---|---|
| `MENU_BG_BLACK` | `#050608` | 1.0 | Fond Main Menu (ColorRect fullscreen) |
| `MENU_PANEL_BG` | `#0A0A12` | 1.0 | PanelContainer Pause Menu |
| `MENU_PANEL_BORDER` | `#2A2A3A` | 1.0 | Bordure panel 1 px |
| `MENU_TEXT_BASE` | `#E8E8F0` | 1.0 | Texte bouton default, titre |
| `MENU_TEXT_SECONDARY` | `#6E6E8A` | 1.0 | Label "PAUSE", version number (si visible) |
| `MENU_ACCENT_CYAN` | `#3EE4FF` | 1.0 | Focus/hover border bouton, border titre |
| `MENU_BG_OVERLAY_RGB` *(r2 — U-3 split token)* | `#000000` | n/a | DimRect Pause RGB (composé avec alpha ci-dessous) |
| `MENU_BG_OVERLAY_ALPHA` | n/a | 0.65 | DimRect Pause alpha — float scalaire, range Tuning Knob [0.55, 0.75] F-MNU-2 |
| `MENU_BTN_PRESSED_BG` | `#111120` | 1.0 | Background bouton état pressed |
| `MENU_BTN_DISABLED_TEXT` | `#3C3C50` | 1.0 | Texte bouton disabled (réservé Tier 2+) |
| `MENU_VERSION_TEXT` | `#3C3C50` | 1.0 | Version number discret |

**Cohérence cross-surface**

- `MENU_TEXT_BASE = #E8E8F0` est identique à `SHOP_TEXT_PRIMARY` (Shop r1 J.7) et au texte du counter HUD r1. Un seul token, trois surfaces — le joueur ne voit jamais de blanc différent entre le menu, le shop et le HUD.
- `MENU_ACCENT_CYAN = #3EE4FF` est identique à `SHOP_ACCENT` (Shop r1 J.7). L'accent cyan est le seul marqueur "interactif" dans l'ensemble du jeu — cohérence sémantique forte : cyan = "tu peux agir ici".
- `MENU_BG_BLACK = #050608` diffère légèrement de `SHOP_BG = #0A0A12`. Justification : le Main Menu est une scène container fullscreen (fond nu), le Shop est un overlay avec panel. Le Main Menu peut être plus sombre car sans panel sur fond — `#050608` est quasiment noir pur. Le Shop a besoin de `#0A0A12` pour distinguer le fond de la surface du panel. Cohérence visuelle maintenue : les deux sont perçus comme "noir" à l'œil.
- Aucune autre couleur n'est autorisée MVP. Pas de rouge d'erreur, pas d'orange de warning, pas de vert de succès dans les menus. Si un état d'erreur doit être communiqué (Tier 2+), utiliser `MENU_TEXT_SECONDARY` + iconographie monochrome.

### K.5 — États visuels des boutons

Cinq états max. Toutes les transitions sont snap (aucun tween — cf. K.7). Le moteur de rendu est le `Theme` Godot configuré une fois sur `MainMenuRoot` / `PauseRoot` et hérité par tous les boutons enfants.

| État | Background | Texte | Bordure | Notes |
|---|---|---|---|---|
| **Default** | transparent (fond parent visible) | `#E8E8F0` | aucune | Bouton "plat" — pas de boîte autour par défaut |
| **Hover** | transparent | `#E8E8F0` | 1 px solid `#3EE4FF` en bas uniquement (underline) | Underline bottom — soulignement monospace, pas de box border complète |
| **Focus** (clavier/gamepad) | transparent | `#E8E8F0` | 1 px solid `#3EE4FF` complet (rect entier) | Distingue focus clavier (rect) du hover souris (underline) — Accessibility K.6 |
| **Pressed** | `#111120` | `#E8E8F0` | 1 px solid `#3EE4FF` | Background sombre pendant `button_down` — feedback immédiat au clic |
| **Disabled** | transparent | `#3C3C50` | aucune | Réservé Tier 2+ (ex. "Reprendre" désactivé si déjà PLAYING) |

**Règles de transition**

- Toutes les transitions entre états sont `instantanées` — pas de `Tween`, pas de `lerp`, pas de délai d'entrée/sortie. L'état change dans le même frame que l'event input.
- `hover_delay = 0 ms`. L'underline cyan apparaît au premier pixel de survol, disparaît au premier pixel de sortie.
- Pas de glow (aucun `CanvasItem.use_parent_material` avec bloom), pas d'ombre portée (`StyleBoxFlat.shadow_size = 0`), pas de coin arrondi (`corner_radius_* = 0`).
- Largeur minimale des boutons : `custom_minimum_size.x = 220 px` (assez large pour accommoder "Quitter vers Menu Principal" sans truncation à 15 px monospace).

**Coexistence hover (souris) ↔ focus (clavier/gamepad)** *(r2 — U-4)*

Quand la souris survole le bouton A et que le focus clavier est sur le bouton B (cas où l'utilisateur navigue au clavier puis bouge la souris sans cliquer), **les deux indicateurs coexistent visuellement** :

- Bouton A : underline cyan bottom (état Hover) — fournit le feedback "tu peux cliquer ici".
- Bouton B : rect cyan complet (état Focus) — fournit le feedback "Enter activera celui-ci".

**Décision MVP** : pas de "focus follows pointer" (pattern X11/Wayland qui synchronise focus avec position souris). Raisons :
1. Anti-fantasy double-input : si `focus_follows_pointer = true`, bouger la souris déplace le focus → presser Enter active un bouton non-anticipé.
2. Cohérence cross-OS : Windows/macOS desktop default = focus explicit (clic ou Tab), pas pointer-follows.
3. Accessibility K.9 Tier 1 : navigation clavier 100% indépendante de la souris.

**Cas où hover et focus sont sur le même bouton** : visuellement, le rect Focus l'emporte (border complet > underline bottom — pas de double-rendu). Implémenté via Theme StyleBoxFlat composé : `Button.add_theme_stylebox_override("focus", focus_box)` + `("hover", hover_box)`. Godot rend Focus par-dessus Hover natively.

**Cas où la souris quitte tout bouton (curseur sur fond)** : aucun bouton n'a Hover. Le bouton focusé (clavier) garde son rect cyan. Tab continue de naviguer. Pas de "focus perdu".

**Couvert** : AC-MNU-65 ADVISORY r2 — test manuel `production/qa/evidence/menu-hover-focus-coexistence-2026-04-28.md` (screenshot souris-sur-A + focus-sur-B).

### K.6 — Navigation clavier/souris

**Ordre de focus (tab order)**

| Écran | Ordre tab | Focus initial à l'ouverture |
|---|---|---|
| Main Menu | Start Run → Quitter le jeu (→ wrap vers Start Run) | `StartButton.grab_focus()` dans `_ready()` |
| Pause Menu | Reprendre → Quitter vers Menu Principal → Quitter le jeu (→ wrap vers Reprendre) | `ResumeButton.grab_focus()` dans `_on_gsm_state_changed(PAUSED)` |

**Actions input**

| Action | Résultat |
|---|---|
| `Tab` / `Shift+Tab` | Navigation entre boutons dans l'ordre tab défini ci-dessus |
| `ui_confirm` (Enter / Space / gamepad A) | Active le bouton focusé |
| `ui_cancel` (Escape / gamepad B) | **Pause Menu uniquement** : équivalent clic "Reprendre" (`GSM.request_resume()`) — cohérence R-SHP-11 Shop (ESC = avancer). **Main Menu** : ESC est ignoré (pas de contexte "fermer" sur le menu racine). |
| Clic souris | Active le bouton survolé, focus suivant le clic |

**Conventions ADR-0004**

- `ui_cancel` est l'action InputMap standard Godot (ADR-0004, action `ui_cancel_pressed`). Le Pause Menu ne reçoit `ui_cancel` que si son nœud est le receveur le plus prioritaire — garanti par `CanvasLayer.layer = 80` (plus haute priorité UI active).
- Le Pause Menu pose `InputManager.request_disable(&"PauseMenu")` à l'ouverture (bloque les inputs gameplay) et `InputManager.release_enable_request(&"PauseMenu")` à la fermeture. Conformément au refcount ADR-0004 D-4.
- Le Main Menu n'appelle pas `InputManager.request_disable` — il n'y a pas de gameplay actif à protéger dans le contexte Main Menu (scène container indépendante).
- `mouse_mode` : Main Menu → `Input.MOUSE_MODE_VISIBLE` (défaut). Pause Menu ouverture → `InputManager.set_mouse_captured(false)` ; fermeture vers PLAYING → `set_mouse_captured(true)`.

**Space bar comportement Godot natif** *(r2 — U-5)*

Godot `Button` consomme nativement `Space` ET `Enter` (`ui_accept`) sur le bouton focusé — c'est un comportement built-in du `BaseButton.shortcut_in_tooltip = true` + `ui_accept` action mapping. **Aucun script custom requis MVP.** L'utilisateur tabbe vers un bouton, presse Space ou Enter, le signal `pressed` est émis. Cohérent avec convention OS desktop standard. Le Menu n'a pas besoin de polling `is_action_pressed("ui_accept")` — Godot le route automatiquement vers le bouton focusé.

**Remap accelerators Tier 2+** *(r2 — U-5)*

MVP : pas de raccourcis clavier custom (genre "1 = Reprendre, 2 = Quitter Menu", ou shortcut `Q` = Quit). Le Menu utilise exclusivement Tab/Enter/Space + souris. Tier 2+ Settings Menu pourra introduire :
- Letter accelerators (`R` = Resume underlined dans le bouton "**R**eprendre", etc.) — cohérent OS desktop conventions.
- Custom shortcuts user-définis via remap dialog Settings Menu.

Réservé `OQ-MNU-3` Settings Menu Tier 2+. MVP zéro accelerator pour simplicité + zéro learning curve playtest 1.

### K.7 — Transitions ouverture / fermeture

**Règle absolue : aucune animation sur les menus eux-mêmes.**

Les transitions visuelles entre états (PLAYING → PAUSED, MAIN_MENU → PLAYING) sont **owned par le GSM** (CanvasLayer layer 100, fade noir). Le Menu ne possède aucun tween d'apparition ou de disparition — un seul propriétaire du fade évite la double-transition (Player Fantasy, §Pacte Pillar 1).

| Transition | Comportement Menu | Propriétaire de l'animation |
|---|---|---|
| Boot → Main Menu visible | `MainMenuRoot.visible = true` immédiat, dès que la scène est chargée | GSM fade-out → scène chargée → fade-in (layer 100) |
| Main Menu → PLAYING (Start Run) | `GSM.start_etage(1)` appelé → scène déchargée par GSM | GSM |
| PLAYING → PAUSED (Escape) | `PauseLayer.visible = true` snap, même frame | Aucun fade — instantané Pillar 1 |
| PAUSED → PLAYING (Reprendre) | `PauseLayer.visible = false` snap, même frame | Aucun fade — instantané Pillar 1 |
| PAUSED → Main Menu | `PauseLayer.visible = false` + `GSM.request_scene_transition(main_menu.tscn)` | GSM fade (layer 100) |
| PAUSED → Quit | `get_tree().quit()` | Aucun — fermeture OS immédiate |

**Budget temps**

- PLAYING → PAUSED visiblement gelé : < 100 ms (Pillar 1). `Engine.time_scale` n'est pas utilisé — GSM applique `get_tree().paused = true` (Jolt physics stop, `_process` des nœuds non-ALWAYS stoppé). Le Pause Menu tourne en `PROCESS_MODE_ALWAYS`.
- Aucun spinner, aucun "Chargement…", aucun progress bar dans le menu. Si un changement de scène prend > 200 ms (GSM fade), le fade noir du GSM masque l'attente — le Menu n'a rien à afficher pendant ce temps.

**Précision "snap" dans le contexte CONNECT_DEFERRED** *(r2 — U-6 clarification)*

Quand ce GDD écrit "snap instantané" ou "même frame" pour les transitions de visibility (R-MNU-15, K.7 ligne PLAYING → PAUSED), la définition opérationnelle est :

- **`state_changed` est émis SYNC par GSM** (ADR-0007 D-6) — au moment de l'émission, l'état GSM est déjà muté.
- **Le handler `_on_state_changed` est connecté CONNECT_DEFERRED côté Menu** (R-MNU-4) — Godot délivre le callback **à la fin de la frame courante** (avant `_process` de la frame suivante).
- **Latence effective** : 0 à 1 frame (≤ 16.6 ms à 60 fps). Le pire cas est si `state_changed` est émis en début de frame N et le handler exécute en fin de frame N (juste avant render) — visiblement perçu comme "frame N+1" par le joueur.
- **Aucun await `process_frame` n'est requis** dans les ACs `[Logic — BLOCKING]` qui testent `_apply_visibility` directement (AC-MNU-33). L'AC teste la fonction synchrone, pas le pipeline complet `state_changed → handler exécuté`. Pour le pipeline complet (intégration end-to-end), AC-MNU-12 utilise `await get_tree().process_frame`.
- **"Même frame que `state_changed` reçu"** = même frame que la **délivrance** du handler deferred, pas même frame que l'**émission** SYNC. Cette précision élimine la contradiction apparente "K.7 dit même frame, AC-MNU-33 sans await".

Cette précision est cohérente avec le pattern `_apply_visibility(false)` snap (R-MNU-15) et garantit que le budget Pillar 1 < 100 ms tient (16.6 ms `T_def` + 16.6 ms `T_ren` = 33 ms ≪ 100 ms).

### K.8 — Cohérence Chrome Zen avec HUD r1 et Shop r1

Les anti-patterns ci-dessous sont vérifiables par inspection visuelle + lecture du fichier `.tscn` / du script associé.

| Anti-pattern visuel | Comment tester | Rationale |
|---|---|---|
| Gradient sur fond ou panel | Inspecter `ColorRect.color` et `StyleBoxFlat.bg_color` — valeur unique, pas de `StyleBoxFlat.bg_color_2` ni gradient shader (AC-MNU-66 r2 grep `bg_color_2` dans `.tres`/`.tscn` → 0 match) | Chrome Zen = aplats, pas de dégradé. Cohérence Shop `#0A0A12` aplat. |
| Coins arrondis (`corner_radius > 0`) | `grep -r "corner_radius" scenes/menus/` → zéro match attendu | Géométrie carrée projet. HUD r1 et Shop r1 utilisent tous `corner_radius = 0`. |
| Glow / bloom sur bouton ou titre | Inspecter `CanvasItem.material` sur boutons et labels — `null` attendu. Aucun `WorldEnvironment.environment.glow` dans la scène. | Glow = distraction visuelle. Anti-pillar "L'UI est invisible". |
| Parallax background | `grep -r "ParallaxBackground\|ParallaxLayer" scenes/menus/` → zéro match | Bouger le fond pendant un menu = mouvement non-lié au gameplay = distraction. |
| Logo animé / splash screen | Aucun `AnimationPlayer` sur `TitleLabel` ni nœud `AnimatedSprite2D` dans `main_menu.tscn` | Boot → Main Menu direct. Anti-anti-pillar : "pas de logo studio fade-in 3s". |
| Hover delay > 50 ms | Vérifier `theme.button.hover_delay` = 0. Confirmer visuellement : underline doit apparaître au pixel 1 du survol, frame suivante. | Hover delay = sensation de mollesse. Pillar 1 snap. Cohérence Shop : hover = frame suivante. |
| SFX sur bouton / open / close | `grep -r "AudioStreamPlayer\|play_sfx\|play_sound" src/gameplay/menu*` → zéro match pour les menus MVP. Aucun `AudioStreamPlayer` dans les scènes menu. | Audio r2.1 scope : zéro SFX MVP. Cohérence Shop r1 (silencieux). |
| Confirm dialog "Êtes-vous sûr ?" | `grep -r "AcceptDialog\|ConfirmationDialog\|PopupPanel" scenes/menus/` → zéro match | Pillar 1 anti-friction. Player Fantasy : "le clic EST la décision". |

### K.9 — Accessibilité minimum MVP

**Tier 1 — Obligatoire MVP (livrable)**

- Navigation clavier 100 % : tous les boutons des deux écrans atteignables et activables sans souris. Focus visible via bordure cyan `#3EE4FF` (K.5 état Focus). Tab cycling wrap implémenté (focus ne se perd pas en bout de liste).
- Aucun élément interactif accessible uniquement à la souris. Aucun clic-droit, aucun drag-and-drop.
- Contraste texte/fond : `MENU_TEXT_BASE (#E8E8F0)` sur `MENU_BG_BLACK (#050608)` → ratio ~15.2:1 (WCAG AAA, seuil 7:1). `MENU_ACCENT_CYAN (#3EE4FF)` sur `#050608` → ratio ~8.9:1 (WCAG AAA). Aucune combinaison sous AA (4.5:1) dans les menus MVP.
- Taille de police minimale : 15 px texte bouton. En deçà de 12 px aucun texte ne doit être présent (la version number à 11 px est admise car non-fonctionnelle).
- **Lisibilité du version number 11 px** *(r2 — U-2)* : la version number à 11 px (`#3C3C50` quasi-invisible) est **délibérément en deçà du seuil WCAG 2.5.3 confort 12 px** car (a) elle est non-fonctionnelle (lecture diagnostic build version uniquement), (b) le contraste est volontairement faible pour rester discret (le joueur ne doit pas être attiré par cet élément), (c) `DEBUG_SHOW_VERSION = false` par défaut MVP (masqué — visible uniquement en debug build). Tier 2+ Settings Menu pourra introduire un toggle "show version number" + scaling 12px+ via `accessibility_font_scale`. Couvert par AC-MNU-67 ADVISORY r2 (DEBUG flag verification).
- Aucun contenu clignotant (flash > 3 Hz) — pas d'animation sur les menus (K.7). Conformité photosensibilité WCAG 2.3.
- **`prefers-reduced-motion` flag OS** *(r2 — U-8)* : MVP zéro animation (K.7) → flag OS non-applicable de facto (rien à désactiver). Tier 2+ : si une animation est introduite (settings slide-in, fade pause), `OS.is_reduce_motion_enabled()` (Godot 4.5+ via AccessKit) doit la désactiver. AC-MNU-64 ADVISORY r2 enforce 0 tween dans le code Menu, indépendamment du flag OS — défense en profondeur.

**Tier 2 — si gratuit via Godot 4.6 AccessKit (optionnel MVP)**

Godot 4.5+ intègre AccessKit (lecteur d'écran natif via AT-SPI / Windows UI Automation). Si Godot 4.6 expose AccessKit dans la version de build :
- S'assurer que chaque `Button` a un `tooltip_text` ou un `text` non-vide (déjà satisfait par design — "Start Run", "Reprendre", etc.).
- S'assurer que le `TitleLabel` a un texte non-vide (déjà satisfait — "CHROME://ASCENT").
- Aucun effort de développement supplémentaire requis si le thème Godot standard transmet les labels nativement. Vérifier via NVDA (Windows) ou VoiceOver (macOS) sur une build debug.
- Si AccessKit n'est pas fonctionnel sans configuration supplémentaire : différer Tier 2.

**Tier 3 — Différé Tier 2+ (hors scope MVP)**

- Font scaling 75 % – 150 % : implémenté via `theme_override_font_sizes` conditionnel depuis un `AccessibilityManager` autoload. Déclenchable par setting `accessibility_font_scale: float` (Tier 2+ Settings Menu).
- `reduce_motion` flag : supprime toute animation résiduelle (si Tier 2+ introduit des tweens dans les menus). Cohérence Shop r1 EC-SHP-29.
- Remap clavier/gamepad : hors scope MVP — différé avec Settings Menu Tier 2+.

### K.10 — UX Flag : specs UX requises avant création des epics

> **📌 UX Flag — Menu System** : `/ux-design main-menu.md` et `/ux-design pause-menu.md` doivent être écrits et validés AVANT de lancer `/create-epics menu-system`.

Ce flag reproduit le pattern établi par HUD r1 et Shop r1 :

| Fichier | Contenu attendu | Bloque |
|---|---|---|
| `design/ux/main-menu.md` | Wireframe textuel, flow boot→gameplay, états focus, breakpoints 720p/1080p, mapping nœuds Godot ↔ comportement | Toutes stories `main_menu.tscn` |
| `design/ux/pause-menu.md` | Wireframe textuel, flow pause/resume/quit, overlay alpha, comportement ESC, InputManager refcount flow | Toutes stories `pause_overlay.tscn` |
| **`design/ux/quit-flow.md`** *(r2 — U-9 ajouté)* | Rationale "zero-confirm Quit" + UX exception path pour OQ-MNU-7 (épilepsie / parental advisory Tier 3 Steam submission) + diagramme cross-screen Quit (Main Menu / Pause Menu / Alt+F4 / Cmd+Q convergent vers `NOTIFICATION_WM_CLOSE_REQUEST`) | Tier 3 Steam submission + résolution OQ-MNU-7 |

**Note sur `quit-flow.md`** *(r2 — U-9)* : ce document est **NOT-blocking MVP** (le quit fonctionne sans), mais **mandatory avant Tier 3 Steam/itch.io submission** car les exigences légales régionales (épilepsie warning, parental advisory) doivent être documentées + alignées avec l'anti-fantasy "Pas de Are you sure?". Pattern `P-MENU-NO-CONFIRM-001` cross-screen Menu/Shop/Pause à formaliser dans `design/ux/interaction-patterns.md` Tier 2+.

Ces fichiers sont produits par `/ux-design [screen-name]` et validés par `art-director` (cohérence Chrome Zen) avant passage à `/team-ui`. Le présent GDD §K constitue le cahier des charges source pour ces deux fichiers UX — les specs UX ne doivent pas contredire les tokens K.4, les états K.5, ou les règles de transition K.7.

## Acceptance Criteria

Total ACs : **66** *(r2 : 56 r1 + 2 r2 cosmetic AC-MNU-57/58 + 1 r2 AC-MNU-5b + 9 r2 AC-MNU-59..67 ; supersedes legacy AC-MNU-33 supprimé doublon r1.1 cosmetic — total net 67−1=66)* — Groupes A-M + r2 ajouts, ~42 BLOCKING + ~24 ADVISORY, ~65% AUTO + ~30% STATIC + ~5% MANUAL.

### Groupe A — Boot & Lifecycle Main Menu

- **AC-MNU-1** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** le projet Godot est configuré avec `main_scene = "res://scenes/menus/main_menu.tscn"`, **WHEN** l'application démarre (premier `_ready()` exécuté), **THEN** `MainMenuControllerScript._ready()` s'exécute et `GameStateManager.get_current_state()` retourne `State.MENU` avant toute interaction utilisateur. *Mécanisme GUT : `assert_eq(GameStateManager.get_current_state(), GameStateManager.State.MENU)` dans une fixture boot avec `MockGameStateManager` initialisé à MENU. Covers R-MNU-2, ADR-0007 D-9.*
- **AC-MNU-2** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** `main_menu.tscn` est chargée et `MainMenuControllerScript._ready()` s'exécute, **WHEN** la scène devient active, **THEN** `StartButton.grab_focus()` a été appelé exactement 1× — vérifié via `assert_eq(StartButton.has_focus(), true)` dans `await get_tree().process_frame`. *Covers K.6 focus initial.*
- **AC-MNU-3** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** `main_menu.tscn` est chargée et GSM est en état MENU, **WHEN** `_ready()` est exécuté, **THEN** aucun signal `GameStateManager.state_changed` n'a été émis — `watch_signals(gsm)` avant `_ready()`, `assert_signal_not_emitted(gsm, "state_changed")` après. *Covers ADR-0007 D-9 pattern pull — zéro emit au boot.*
- **AC-MNU-4** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** le GSM est en état MENU et `main_menu.tscn` est la scène active, **WHEN** `MainMenuControllerScript._ready()` se termine, **THEN** `InputManager.set_mouse_captured` a été appelé avec `false` exactement 1× — vérifié via `MockInputManager.set_mouse_captured_call_count == 1` et `MockInputManager.last_captured == false`. *Covers R-MNU-12.*
- **AC-MNU-5** `[Static — ADVISORY] [Owner: ui-programmer]` — **GIVEN** la scène `main_menu.tscn` est commitée en dépôt, **WHEN** on exécute `grep -c "change_scene_to_file\|additive\|add_child.*main_menu" src/gameplay/**/*.gd`, **THEN** le résultat est 0 match hors du GSM — seul le GameStateManager charge `main_menu.tscn` via `change_scene_to_file`. *Covers ADR-0007 D-5 §a anti-pattern.*
- **AC-MNU-5b** `[Static — BLOCKING] [Owner: ui-programmer]` *(r2 — Q-9 R-MNU-1 zero autoload Menu)* — **GIVEN** le fichier `project.godot`, **WHEN** on exécute `grep -E '^MenuSystem|^MainMenuController|^PauseMenuController|^Menu\b' project.godot` dans la section `[autoload]`, **THEN** 0 match — aucun autoload Menu n'est déclaré (R-MNU-1 zéro autoload Menu). *Mécanisme : `awk '/\[autoload\]/,/^\[/' project.godot | grep -E '^(MenuSystem|MainMenuController|PauseMenuController|Menu)'`. Covers R-MNU-1 architecture decision MVP.*

### Groupe B — Lifecycle Pause Overlay

- **AC-MNU-6** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** une scène étage gameplay (`etage_01.tscn`) est chargée et le GSM est en état PLAYING, **WHEN** `PauseMenuControllerScript._ready()` s'exécute, **THEN** `PauseLayer.visible == false` — `assert_false(pause_layer.visible)`. *Covers R-MNU-3 hidden par défaut.*
- **AC-MNU-7** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** `PauseMenuControllerScript._ready()` s'exécute et GSM est en état PAUSED (cas edge : overlay ajouté à une scène déjà pausée), **WHEN** le pattern pull `_apply_visibility(GameStateManager.get_current_state())` est exécuté, **THEN** `PauseLayer.visible == true` — `assert_true(pause_layer.visible)`. *Mécanisme : MockGSM.get_current_state() retourne PAUSED. Covers ADR-0007 D-9 resync.*
- **AC-MNU-8** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** une scène étage est active avec un `pause_overlay.tscn` instancié, **WHEN** `GameStateManager.request_scene_transition("res://scenes/menus/main_menu.tscn")` est appelé et `change_scene_to_file` complète, **THEN** il n'existe aucun node `PauseOverlayRoot` dans le SceneTree — `assert_eq(get_tree().get_nodes_in_group("pause_overlay").size(), 0)`. *Covers R-MNU-3 nettoyage propre, no orphan.*
- **AC-MNU-9** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** une scène étage avec Pause Overlay est active, **WHEN** `get_tree().change_scene_to_file` est invoqué par le GSM, **THEN** `tree_exiting` est émis par `PauseOverlayRoot` avant que la nouvelle scène ne soit prête — `watch_signals(pause_layer)`, `assert_signal_emitted(pause_layer, "tree_exiting")`. *Covers no orphan instance, lifecycle propre.*
- **AC-MNU-10** `[Static — ADVISORY] [Owner: ui-programmer]` — **GIVEN** le fichier `pause_overlay.tscn` est inspecté, **WHEN** on parse le `.tscn` pour trouver la propriété `process_mode`, **THEN** `PauseLayer (CanvasLayer)` a `process_mode = 5` (PROCESS_MODE_ALWAYS). *Grep : `grep -A2 "PauseLayer\|CanvasLayer" scenes/menus/pause_overlay.tscn | grep "process_mode"` doit retourner `process_mode = 5`. Covers R-MNU-14, ADR-0007 D-4.*

### Groupe C — Trigger ESC / ui_cancel

- **AC-MNU-11** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PLAYING et `pause_overlay.tscn` est instancié, **WHEN** `InputManager.ui_cancel_pressed` est émis (simulé via `MockInputManager.ui_cancel_pressed.emit()`), **THEN** `GameStateManager.request_pause()` est appelé exactement 1× — `MockGSM.request_pause_call_count == 1`. *Covers R-MNU-6 branche PLAYING.*
- **AC-MNU-12** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PLAYING et l'appel précédent à `request_pause()` a transitionné vers PAUSED, **WHEN** `state_changed(PAUSED)` est reçu par `PauseMenuControllerScript`, **THEN** `PauseLayer.visible == true` dans le même frame (CONNECT_DEFERRED = frame suivante au plus tard) — `await get_tree().process_frame` puis `assert_true(pause_layer.visible)`. *Covers R-MNU-15.*
- **AC-MNU-13** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PAUSED et Pause Overlay est visible, **WHEN** `InputManager.ui_cancel_pressed` est émis, **THEN** `GameStateManager.request_resume()` est appelé exactement 1× et, après `state_changed(PLAYING)`, `PauseLayer.visible == false` — `assert_eq(MockGSM.request_resume_call_count, 1)`, `await process_frame`, `assert_false(pause_layer.visible)`. *Covers R-MNU-6 branche PAUSED.*
- **AC-MNU-14** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état RESPAWNING, **WHEN** `InputManager.ui_cancel_pressed` est émis, **THEN** ni `request_pause()` ni `request_resume()` ne sont appelés et aucune exception n'est levée — `assert_eq(MockGSM.request_pause_call_count, 0)`, `assert_eq(MockGSM.request_resume_call_count, 0)`. *Covers R-MNU-6 branche `_:` no-op, ADR-0007 matrice.*
- **AC-MNU-15** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état MENU (aucun Pause Overlay instancié), **WHEN** `ui_cancel_pressed` est émis depuis `InputManager`, **THEN** aucune erreur, aucune transition GSM, aucun crash — le signal est émis dans le vide sans handler connecté. *Test : `watch_signals(mock_gsm)`, `assert_signal_not_emitted(mock_gsm, "state_changed")`. Covers R-MNU-5 — PauseController non instancié en MENU.*
- **AC-MNU-16** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PLAYING, **WHEN** `ui_cancel_pressed` est émis deux fois dans le même frame physique (double-press rapide), **THEN** `request_pause()` est appelé exactement 1× — le GSM absorbe le second appel en idempotence. *`assert_eq(MockGSM.request_pause_call_count, 1)`. Covers R-MNU-17 idempotence.*

### Groupe D — Boutons MainMenu

- **AC-MNU-17** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** `main_menu.tscn` est active et GSM est en état MENU, **WHEN** `StartButton` reçoit un signal `pressed`, **THEN** `GameStateManager.start_etage(1)` est appelé exactement 1× — `assert_eq(MockGSM.start_etage_call_count, 1)` et `assert_eq(MockGSM.start_etage_last_arg, 1)`. *Covers R-MNU-7.*
- **AC-MNU-18** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** `start_etage(1)` a été appelé par le Main Menu et GSM orchestre le chargement de `etage_01.tscn`, **WHEN** `LevelSystem.level_active` est émis et GSM appelle `_transition_to(PLAYING)`, **THEN** `state_changed(PLAYING)` est émis — `watch_signals(gsm)`, `assert_signal_emitted(gsm, "state_changed")` avec argument `State.PLAYING`. *Integration test niveau de signal chain. Covers ADR-0007 D-5 §b, D-8.*
- **AC-MNU-19** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** `main_menu.tscn` est active, **WHEN** `QuitButton` reçoit un signal `pressed`, **THEN** `get_tree().quit()` est appelé exactement 1× — vérifié via `MockSceneTree.quit_call_count == 1`. *Covers R-MNU-8 zero confirm.*
- **AC-MNU-20** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** `StartButton` reçoit deux signaux `pressed` rapides (double-clic simulé via deux `emit_signal("pressed")`), **WHEN** les deux sont traités, **THEN** `GameStateManager.start_etage` est appelé exactement 1× — idempotence GSM absorbe le second. *`assert_eq(MockGSM.start_etage_call_count, 1)`. Covers R-MNU-17 double-click guard.*

### Groupe E — Boutons PauseMenu

- **AC-MNU-21** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PAUSED et Pause Overlay est visible, **WHEN** `ResumeButton` reçoit un signal `pressed`, **THEN** `GameStateManager.request_resume()` est appelé exactement 1× et, après `state_changed(PLAYING)`, `PauseLayer.visible == false` — `assert_eq(MockGSM.request_resume_call_count, 1)`. *Covers R-MNU-9.*
- **AC-MNU-22** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PAUSED et Pause Overlay est visible, **WHEN** `MainMenuButton` reçoit un signal `pressed`, **THEN** (1) `InputManager.release_enable_request(&"PauseMenu")` est appelé avant `request_scene_transition`, (2) `GSM.request_scene_transition("res://scenes/menus/main_menu.tscn")` est appelé exactement 1×. *`assert_eq(MockInput.release_call_count, 1)`, `assert_true(MockInput.release_called_before_transition)`. Covers R-MNU-10, ordre release-avant-GSM.*
- **AC-MNU-23** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PAUSED et Pause Overlay est visible, **WHEN** `QuitButton` reçoit un signal `pressed`, **THEN** `get_tree().quit()` est appelé exactement 1× et `release_enable_request(&"PauseMenu")` est appelé avant quit — `assert_eq(MockSceneTree.quit_call_count, 1)`, `assert_true(MockInput.release_called_before_quit)`. *Covers R-MNU-11.*
- **AC-MNU-24** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PAUSED, **WHEN** `ResumeButton.pressed` est émis deux fois dans le même frame, **THEN** `request_resume()` est appelé exactement 1× — idempotence GSM absorbe le second. *`assert_eq(MockGSM.request_resume_call_count, 1)`. Covers R-MNU-17 double-click.*
- **AC-MNU-25** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** la matrice de transitions ADR-0007, **WHEN** `request_scene_transition(main_menu_path)` est appelé depuis l'état PAUSED, **THEN** GSM transite vers MENU (via change_scene_to_file) — état résultant `get_current_state() == State.MENU`. *Transition valide PAUSED → MENU confirmée. Covers ADR-0007 table transitions.*

### Groupe F — Input refcount discipline

- **AC-MNU-26** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** Pause Overlay est caché et InputManager n'a aucun blocker `"PauseMenu"`, **WHEN** `state_changed(PAUSED)` est reçu et `_apply_visibility(true)` exécuté, **THEN** `InputManager.request_disable(&"PauseMenu")` est appelé exactement 1× — `MockInputManager.disable_call_count == 1` et `MockInputManager.disable_owners.has(&"PauseMenu") == true`. *Covers R-MNU-13.*
- **AC-MNU-27** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** Pause Overlay est visible et `request_disable(&"PauseMenu")` a été posé, **WHEN** `state_changed(PLAYING)` est reçu et `_apply_visibility(false)` exécuté, **THEN** `InputManager.release_enable_request(&"PauseMenu")` est appelé exactement 1× et `MockInputManager.disable_owners.has(&"PauseMenu") == false`. *Covers R-MNU-13 release propre.*
- **AC-MNU-28** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** Pause Overlay est visible et `request_disable(&"PauseMenu")` est posé, **WHEN** la scène étage est détruite via `change_scene_to_file` sans que `_apply_visibility(false)` ait été explicitement appelé (ex : crash path), **THEN** `tree_exiting` du nœud déclenche `release_enable_request(&"PauseMenu")` — le refcount est nettoyé automatiquement. *Fixture : `PauseLayer.tree_exiting.emit()` manuellement, `assert_false(MockInput.disable_owners.has(&"PauseMenu"))`. Covers CONNECT_ONE_SHOT ADR-0004, R-MNU-10 cleanup.*
- **AC-MNU-29** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** deux owners ont posé `request_disable` : `&"PauseMenu"` et `&"CutsceneSystem"` (simulé), **WHEN** `release_enable_request(&"PauseMenu")` est appelé seul, **THEN** InputManager reste disabled (`_enable_blockers.size() == 1`) — retrait d'un seul owner ne réactive pas l'input. *`assert_eq(MockInput.disable_owners.size(), 1)`. Covers ADR-0004 D-4 refcount multi-owner.*

### Groupe G — Mouse capture coordination

- **AC-MNU-30** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM est en état PLAYING et mouse est capturée (`mouse_mode == MOUSE_MODE_CAPTURED`), **WHEN** `state_changed(PAUSED)` est reçu et Pause Overlay s'affiche, **THEN** `InputManager.set_mouse_captured(false)` est appelé exactement 1× et `MockInput.last_captured == false`. *Covers R-MNU-12 ouverture pause.*
- **AC-MNU-31** `[Integration — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** Pause Overlay est visible et mouse est libre, **WHEN** `state_changed(PLAYING)` est reçu (bouton Reprendre ou ESC-PAUSED), **THEN** `InputManager.set_mouse_captured(true)` est appelé exactement 1× et `MockInput.last_captured == true`. *Covers R-MNU-12 fermeture vers PLAYING.*
- **AC-MNU-32** `[Logic — BLOCKING] [Owner: gameplay-programmer]` *(r2 — Q-2 ordre release_called_before_transition ajouté)* — **GIVEN** Pause Overlay appelle `request_scene_transition(main_menu.tscn)` (transition PAUSED → MENU), **WHEN** la séquence `_apply_visibility(false, recapture_mouse=false)` est exécutée avant l'appel GSM, **THEN** (1) `set_mouse_captured(true)` n'est PAS appelé — `assert_eq(MockInput.captured_true_call_count, 0)` ; (2) **`release_enable_request(&"PauseMenu")` est appelé strictement avant `request_scene_transition`** — `assert_true(MockInput.release_called_before_transition)` (timestamp ordering via `Time.get_ticks_usec()` capture côté mock). *Covers R-MNU-12 table ligne "request_scene_transition" + R-MNU-10 ordre release-avant-GSM. Mécanisme : MockInputManager + MockGSM enregistrent `last_call_timestamp_usec` à chaque invocation ; assertion compare les deux.*

### Groupe H — State sync via state_changed

- **AC-MNU-33** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** Pause Overlay est en état hidden, **WHEN** `_on_gsm_state_changed(GameStateManager.State.PAUSED)` est appelé, **THEN** `PauseLayer.visible == true` dans le même frame d'exécution — `assert_true(pause_layer.visible)` sans `await`. *Covers R-MNU-15 snap synchrone.*
- **AC-MNU-34** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** Pause Overlay est visible, **WHEN** `_on_gsm_state_changed(GameStateManager.State.RESPAWNING)` est appelé, **THEN** `PauseLayer.visible == false` — `assert_false(pause_layer.visible)`. *Covers Groupe H visible == false en RESPAWNING anti-flicker, Pillar 3.*
- **AC-MNU-35** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** Pause Overlay vient d'être instancié avec GSM en PAUSED (pattern pull), **WHEN** `_ready()` exécute `_apply_visibility(GameStateManager.get_current_state())`, **THEN** `PauseLayer.visible == true` avant la première frame rendue — `assert_true(pause_layer.visible)` immédiatement après `_ready()` via `await get_tree().process_frame`. *Covers ADR-0007 D-9 resync pull.*
- **AC-MNU-36** `[Static — ADVISORY] [Owner: ui-programmer]` — **GIVEN** le fichier `src/gameplay/menu/pause_menu_controller.gd` (ou chemin équivalent), **WHEN** on grep `Tween\|create_tween\|tween_property\|InterpolateValue` dans ce fichier, **THEN** 0 match — aucune animation tween entre visible true et visible false. *Covers R-MNU-15, K.7 règle absolue anti-tween.*

### Groupe I — Process_mode discipline

- **AC-MNU-37** `[Static — BLOCKING] [Owner: ui-programmer]` — **GIVEN** le fichier `scenes/menus/pause_overlay.tscn` est inspecté, **WHEN** on parse les propriétés du nœud racine `PauseLayer : CanvasLayer`, **THEN** `process_mode = 5` (valeur enum Godot `PROCESS_MODE_ALWAYS`) — `grep "process_mode = 5" scenes/menus/pause_overlay.tscn` retourne 1 match. *Gate BLOCKING car si WHEN_PAUSED (4), les boutons sont non-interactifs sous `get_tree().paused = true`. Covers R-MNU-14, ADR-0007 D-4, K.2.*
- **AC-MNU-38** `[Logic — ADVISORY] [Owner: gameplay-programmer]` — **GIVEN** GSM applique `get_tree().paused = true` lors de la transition vers PAUSED, **WHEN** `PauseLayer` a `process_mode == PROCESS_MODE_ALWAYS`, **THEN** `PauseLayer._process(delta)` est appelé — vérifié via `MockPauseLayer.process_called_under_tree_paused == true`. *Confirme que ALWAYS est opérationnel, pas seulement déclaré. Covers ADR-0007 D-4 opérationnel.*
- **AC-MNU-39** `[Static — ADVISORY] [Owner: ui-programmer]` — **GIVEN** les fichiers `.tscn` des scènes gameplay (`etage_01.tscn`, etc.), **WHEN** on grep `process_mode` sur les nœuds `MovementController`, `CombatSystem`, `LevelSystem`, **THEN** chacun retourne `process_mode = 1` (PROCESS_MODE_PAUSABLE) ou absence de propriété (héritage INHERIT = cohérent car root non pausé) — confirme que les nodes gameplay se figent bien pendant PAUSED. *Covers ADR-0007 D-4 cohérence PAUSABLE.*

### Groupe J — Performance & timing

- **AC-MNU-40** `[Performance — BLOCKING] [Owner: performance-analyst]` *(r2 — Q-4 P95 + nb runs spécifiés)* — **GIVEN** GSM est en état PLAYING et Input est capturé, **WHEN** `ui_cancel_pressed` est émis 60 fois consécutives (avec reset PAUSED→PLAYING entre chaque, 1 seconde wait entre runs pour stabilisation), **THEN** la latence `[input emit] → [pause_layer.visible == true]` mesurée via `Time.get_ticks_msec()` doit avoir **P95 < 100 ms ET P99 < 100 ms ET max < 100 ms** — `assert_true(p95_ms < 100 AND p99_ms < 100 AND max_ms < 100)`. *Mécanisme : array `latencies_ms[60]` + tri quantile P95/P99 ; stratégie headless documentée F-MNU-1 r2 (composé `T_in + T_gsm + T_def`, exclut `T_ren` non observable headless). Covers Pillar 1 FLOW pause < 100 ms ; échec à P95 ou P99 = blocker production.*
- **AC-MNU-41** `[Performance — BLOCKING] [Owner: performance-analyst]` *(r2 — Q-4 P95 + nb runs spécifiés)* — **GIVEN** GSM est en état PAUSED et Pause Overlay est visible, **WHEN** `ui_cancel_pressed` est émis 60 fois consécutives (cycles), **THEN** la latence resume P95 < 100 ms ET P99 < 100 ms ET max < 100 ms — même mécanisme array + quantile que AC-MNU-40. *Covers Pillar 1 FLOW resume < 100 ms.*
- **AC-MNU-42** `[Performance — ADVISORY] [Owner: performance-analyst]` *(r2 — Q-5 warmup baseline)* — **GIVEN** un test stress ouvre et ferme le Pause Overlay, **WHEN** on exécute (a) 10 cycles **warmup** ignorés (laissent Godot stabiliser allocs initiales : Theme cache, font preload, signal table) puis (b) 100 cycles mesurés, **THEN** `delta_memory_bytes = MEMORY_STATIC_after_100 − MEMORY_STATIC_after_warmup < 64 KB` — `assert_true(delta_memory_bytes < 65536)`. *Mécanisme : `Performance.get_monitor(Performance.MEMORY_STATIC)` snapshot après warmup (baseline) puis après 100 cycles ; warmup absorbe les faux positifs (premier cycle alloue ~12 KB pour Theme cache cold). Covers ADR-0004 D-8 pattern zero-alloc + Q-5 mitigation alloc GUT.*
- **AC-MNU-43** `[Performance — ADVISORY] [Owner: performance-analyst]` — **GIVEN** une transition PAUSED → PLAYING via bouton Reprendre, **WHEN** `PauseLayer.visible = false` est appliqué (snap sans tween), **THEN** aucun frame skip n'est enregistré — `Performance.get_monitor(Performance.TIME_PROCESS)` reste < 16.6 ms pendant la transition. *Covers K.7 vsync, anti-tween performance.*

### Groupe K — Anti-patterns testables

- **AC-MNU-44** `[Static — BLOCKING] [Owner: qa-tester]` *(r2 — Q-14 scope élargi aux étages instanciant `pause_overlay.tscn`)* — **GIVEN** le code source et les scènes Menu + les scènes étage qui instancient `pause_overlay.tscn`, **WHEN** on exécute `grep -rE "AudioStreamPlayer|play_sfx|audio_play" scenes/menus/ src/gameplay/menu/ scenes/etages/`, **THEN** 0 match dans `scenes/menus/` et `src/gameplay/menu/` ; pour `scenes/etages/`, les éventuels `AudioStreamPlayer` détectés doivent appartenir à des nœuds non-Menu (gameplay ambient track, etc.) — vérifié via parse `.tscn` qui isole les nœuds enfants de `pause_overlay`. *Mécanisme : script Python ou GDScript helper qui parse les `.tscn` étages et filtre les `AudioStreamPlayer` dont le parent canonical est `pause_overlay` instance. Covers Player Fantasy "Aucun SFX MVP" + portée étages.*
- **AC-MNU-45** `[Static — BLOCKING] [Owner: qa-tester]` — **GIVEN** le code source et les scènes Menu, **WHEN** on exécute `grep -r "AcceptDialog\|ConfirmationDialog\|PopupPanel\|PopupMenu" scenes/menus/ src/gameplay/menu/`, **THEN** 0 match — aucun confirm dialog. *Covers R-MNU-16, Player Fantasy anti-fantasy "Pas de Are you sure?".*
- **AC-MNU-46** `[Static — BLOCKING] [Owner: qa-tester]` — **GIVEN** les fichiers `.tscn` des menus, **WHEN** on exécute `grep -r "corner_radius" scenes/menus/`, **THEN** 0 match ou toutes valeurs sont `= 0` — zéro coin arrondi, géométrie Chrome Zen hard-edge. *Covers K.5 `corner_radius_* = 0`.*
- **AC-MNU-47** `[Static — ADVISORY] [Owner: qa-tester]` — **GIVEN** les fichiers `.tscn` des menus, **WHEN** on exécute `grep -r "ParallaxBackground\|ParallaxLayer\|AnimationPlayer\|AnimationTree" scenes/menus/`, **THEN** 0 match — aucun parallax, aucun AnimationPlayer dans les scènes menu. *Covers Player Fantasy anti-fantasy "pas de menu animé".*
- **AC-MNU-48** `[Static — ADVISORY] [Owner: qa-tester]` — **GIVEN** les scripts controllers Menu, **WHEN** on exécute `grep -r "Gradient\|GradientTexture\|CanvasItemMaterial\|ShaderMaterial" src/gameplay/menu/`, **THEN** 0 match — aucun gradient material dans le Menu System. *Covers Chrome Zen flat-design.*
- **AC-MNU-49** `[Static — BLOCKING] [Owner: qa-tester]` — **GIVEN** les scripts controllers Menu, **WHEN** on exécute `grep -r "Engine\.time_scale\|Engine.time_scale" src/gameplay/menu/`, **THEN** 0 match — le Menu ne modifie jamais `Engine.time_scale`. *Covers ADR-0007 D-4 GSM seul possède l'autorité pause ; time_scale interdit Menu.*
- **AC-MNU-50** `[Static — BLOCKING] [Owner: qa-tester]` — **GIVEN** les scripts controllers Menu, **WHEN** on exécute `grep -r "get_tree()\.paused\|SceneTree.*paused" src/gameplay/menu/`, **THEN** 0 match — aucun controller Menu ne mutate `get_tree().paused` directement ; seul le GSM possède cette autorité. *Covers ADR-0007 D-4 unique authority.*
- **AC-MNU-57** `[Static — BLOCKING] [Owner: qa-tester]` *(r2 cosmetic — Q-6 OQ-MNU-1 RESOLVED enforce délégation save-on-quit)* — **GIVEN** les scripts controllers Menu, **WHEN** on exécute `grep -rE "SaveLoad|\bsave_int\b|\bsave_string_array\b|save_now" src/gameplay/menu/`, **THEN** 0 match — le Menu ne contient aucun appel à l'API SaveLoadSystem. La sauvegarde pre-quit est **exclusivement** owned par `SaveLoadSystem._notification(NOTIFICATION_WM_CLOSE_REQUEST)` (Save/Load r1 R-SAV-9 + R-SAV-8). *Covers R-MNU-17b + R-MNU-18 + OQ-MNU-1 RESOLVED option (a).*
- **AC-MNU-58** `[Static — ADVISORY] [Owner: qa-tester]` *(r2 cosmetic — Q-3 héritage process_mode Pause Overlay)* — **GIVEN** le fichier `scenes/menus/pause_overlay.tscn`, **WHEN** on exécute `grep -c "process_mode" scenes/menus/pause_overlay.tscn`, **THEN** retour exactement `1` match (sur le `CanvasLayer` racine `PauseLayer`) — aucun enfant ne surcharge `process_mode`, l'héritage `PROCESS_MODE_ALWAYS` est garanti par la hiérarchie (R-MNU-14 corollaire). *Covers R-MNU-14 + AC-MNU-37 héritage.*

- **AC-MNU-59** `[Static — BLOCKING] [Owner: qa-tester]` *(r2 — G-6 + G-9 + EC-MNU-41 zero-instance lint)* — **GIVEN** chaque scène étage gameplay dans `scenes/etages/etage_*.tscn`, **WHEN** on exécute `grep -c "pause_overlay.tscn" scenes/etages/etage_*.tscn`, **THEN** chaque fichier retourne **exactement `1` match** — chaque étage instancie `pause_overlay.tscn` exactement une fois (R-MNU-3b authoring lint). *Mécanisme : boucle bash sur les fichiers étages, fail si zero ou >1. Covers EC-MNU-41 (zero-instance silent ESC) + EC-MNU-8 (double-instance double-overlay).*

- **AC-MNU-60** `[Static — BLOCKING] [Owner: qa-tester]` *(r2 — G-5 SHOPPING ESC collision)* — **GIVEN** Shop r1 R-SHP-9 first-handler ESC consume + Pause Menu R-MNU-6 second-handler ESC, **WHEN** on inspecte `src/gameplay/shop/` pour vérifier la présence de `set_input_as_handled()` après le handle ESC dans Shop, **THEN** `grep -rE 'set_input_as_handled\b' src/gameplay/shop/` retourne ≥ 1 match dans le handler ESC du Shop. *Validation cross-system : si Shop ne consume pas ESC, Pause Menu reçoit ESC pendant SHOPPING phase et ouvre Pause par-dessus Shop (collision visuelle layer 80 > 60). Covers G-5 SHOPPING gap + Shop r1 R-SHP-9 enforcement côté Menu — flag cross-GDD à monitorer.*

- **AC-MNU-61** `[Logic — BLOCKING] [Owner: gameplay-programmer]` *(r2 — Q-12 F-MNU-3 tab cycle wrap dédié)* — **GIVEN** Pause Overlay visible (N=3 boutons : Resume, MainMenu, Quit) avec `ResumeButton.has_focus() == true`, **WHEN** Shift+Tab est pressé une fois, **THEN** `QuitButton.has_focus() == true` (wrap vers le dernier bouton de la liste) — `assert_true(quit_button.has_focus())`. *Mécanisme : `Input.parse_input_event(InputEventKey.with_shift_tab)` dans une fixture GUT ; alternative : `gut.simulate_action_pressed("ui_focus_prev")`. Covers F-MNU-3 wrap inverse + K.6 navigation clavier 100% Tier 1.*

- **AC-MNU-62** `[Static — ADVISORY] [Owner: qa-tester]` *(r2 — EC-MNU-40 + Q-8 — visible=true par erreur authoring)* — **GIVEN** le fichier `scenes/menus/pause_overlay.tscn`, **WHEN** on parse les propriétés du nœud racine `PauseLayer`, **THEN** la propriété `visible` est soit absente (default = true pour CanvasLayer mais Control children obéissent à leur propre `visible`), soit explicitement `visible = false` côté `PausePanel` (Control enfant du CanvasLayer). *Mécanisme : `grep -A3 'name="PausePanel"' scenes/menus/pause_overlay.tscn | grep 'visible = true'` doit retourner 0 match (default Godot Control = visible mais piloté par `_apply_visibility(false)` au `_ready()`). Couvert par pattern pull R-MNU-4 même si visible=true au boot. Covers EC-MNU-32 + EC-MNU-40 anti-flash 1-frame.*

- **AC-MNU-63** `[Static — BLOCKING] [Owner: qa-tester]` *(r2 — Q-11 + EC-MNU-42 dual-monitor focus loss)* — **GIVEN** les scripts controllers Menu, **WHEN** on exécute `grep -rE 'NOTIFICATION_WM_WINDOW_FOCUS|_notification\b.*_focus' src/gameplay/menu/`, **THEN** 0 match — aucun controller Menu ne pose son propre handler `_notification` pour les events de focus fenêtre. La gestion `mouse_mode` est exclusivement déléguée à InputManager (ADR-0004 D-7 single source of truth). *Covers EC-MNU-42 (dual-monitor) + R-MNU-18 (anti-dependency) + provisional contract `NOTIFICATION_WM_WINDOW_FOCUS_*` confirmed côté Menu.*

- **AC-MNU-64** `[Static — ADVISORY] [Owner: qa-tester]` *(r2 — U-8 prefers-reduced-motion défense en profondeur)* — **GIVEN** les scripts controllers Menu, **WHEN** on exécute `grep -rE '\b(Tween|create_tween|tween_property|InterpolateValue|AnimationPlayer|AnimationTree)\b' src/gameplay/menu/`, **THEN** 0 match — aucune animation ni tween dans le code Menu. Cette assertion est **indépendante du flag OS `OS.is_reduce_motion_enabled()`** : MVP zéro animation par construction, donc le flag OS est non-applicable de facto. Tier 2+ : si une animation est introduite, elle DOIT être gardée par `if not OS.is_reduce_motion_enabled():`. *Covers K.7 zéro tween + K.9 Tier 1 reduced-motion compliance par défaut + AC-MNU-36 superset.*

- **AC-MNU-65** `[Performance — ADVISORY] [Owner: performance-analyst]` *(r2 — F-MNU-1 mesurabilité headless complément)* — **GIVEN** un build avec rendu actif (CI `xvfb` ou local desktop), **WHEN** un test mesure la latence complète `[input emit] → [pause_layer.visible == true rendered on screen]`, **THEN** la valeur P95 < 100 ms ET max < 100 ms confirme le budget Pillar 1 incluant `T_ren`. *Mécanisme : test manual ou CI avec rendu (capture `Time.get_ticks_msec()` au signal `RenderingServer.frame_post_draw`). Covers F-MNU-1 r2 mesurabilité + complement AC-MNU-40 (headless composé).*

- **AC-MNU-66** `[Static — ADVISORY] [Owner: qa-tester]` *(r2 — U-7 K.8 bg_color_2 anti-pattern)* — **GIVEN** les fichiers `.tscn` et `.tres` (StyleBoxFlat resources) du Menu, **WHEN** on exécute `grep -rE '\bbg_color_2\b|\bgradient\b|\bGradientTexture\b' scenes/menus/ assets/themes/menu*`, **THEN** 0 match — aucun gradient natif `StyleBoxFlat.bg_color_2` ou `GradientTexture` dans les ressources Menu. *Couvert par AC-MNU-48 (gradient material côté script) + ce nouveau lint pour ressources `.tres/.tscn`. Covers K.8 anti-pattern complet.*

- **AC-MNU-67** `[Static — ADVISORY] [Owner: ui-programmer]` *(r2 — U-2 K.9 11px version number debug-only)* — **GIVEN** le script `MainMenuControllerScript`, **WHEN** on inspecte la déclaration `DEBUG_SHOW_VERSION`, **THEN** la constante est `false` par défaut MVP — `grep -E 'const\s+DEBUG_SHOW_VERSION\s*:?\s*bool\s*=\s*false' src/gameplay/menu/main_menu_controller.gd` retourne ≥ 1 match. Le label version 11 px est masqué en build release. *Covers K.9 lisibilité 11 px exception (non-fonctionnelle, debug-only).*

### Groupe L — Cohérence Chrome Zen

- **AC-MNU-51** `[Static — ADVISORY] [Owner: ui-programmer]` — **GIVEN** les scripts `main_menu_controller.gd` et `pause_menu_controller.gd`, **WHEN** on grep `const MENU_BG_BLACK\|const MENU_PANEL_BG\|const MENU_TEXT_BASE\|const MENU_ACCENT_CYAN`, **THEN** les 4 tokens K.4 sont déclarés comme `const` de type `Color` en tête de fichier — aucune valeur hex inline hardcodée dans le corps des fonctions. *Covers K.4 tokens palette.*
- **AC-MNU-52** `[Static — ADVISORY] [Owner: ui-programmer]` — **GIVEN** le répertoire `assets/fonts/`, **WHEN** on exécute `ls assets/fonts/JetBrainsMono-Regular.ttf`, **THEN** le fichier existe — `exit code 0`. *Si absent : build distribuable non conforme K.3. Covers K.3 police embarquée.*
- **AC-MNU-53** `[Manual — ADVISORY] [Owner: ux-designer]` — **GIVEN** `main_menu.tscn` et `pause_overlay.tscn` sont ouverts dans l'éditeur Godot à résolution 1920×1080, **WHEN** l'inspecteur Theme est lu pour les éléments `TitleLabel`, `Button`, `SubtitleLabel`, **THEN** les tailles sont respectivement 28 px (titre), 15 px (bouton), 13 px (PAUSE label), 11 px (version) — conformes K.3. *Evidence : screenshot inspecteur + sign-off ux-designer dans `production/qa/evidence/menu-typography-[date].png`.*
- **AC-MNU-54** `[Manual — ADVISORY] [Owner: ux-designer]` — **GIVEN** `main_menu.tscn` rendu à 1920×1080, **WHEN** le contraste `MENU_TEXT_BASE (#E8E8F0)` sur fond `MENU_BG_BLACK (#050608)` est mesuré via outil WCAG (ex. axe Devtools ou script), **THEN** ratio ≥ 15.2:1 (WCAG AAA) et `MENU_ACCENT_CYAN (#3EE4FF)` sur fond dark ≥ 8.9:1. *Evidence : screenshot + valeurs ratio dans `production/qa/evidence/menu-contrast-[date].md`.*

### Groupe M — Layer convention

- **AC-MNU-55** `[Static — BLOCKING] [Owner: ui-programmer]` — **GIVEN** le fichier `scenes/menus/pause_overlay.tscn`, **WHEN** on exécute `grep "layer = " scenes/menus/pause_overlay.tscn`, **THEN** la valeur retournée est `layer = 80` sur le nœud `CanvasLayer` racine — 1 match exact. *Covers R-MNU-3, K.2 layer convention Pause=80.*
- **AC-MNU-56** `[Static — ADVISORY] [Owner: ui-programmer]` *(r2 — Q-13 filter complet)* — **GIVEN** les fichiers `.tscn` de tous les overlays actifs MVP (HUD, Shop, Pause, GSM fade), **WHEN** on collecte toutes les valeurs `CanvasLayer.layer` via `grep -rE '^layer\s*=\s*[0-9]+' scenes/ --include='*.tscn'` (filter strict : ligne commence par `layer = N` au top-level d'un nœud `.tscn`, **exclut** par construction `physics_layer = ...`, `render_layer = ...`, `collision_layer = ...`, `light_mask = ...`, `visibility_layer = ...` car ces propriétés ne match pas le pattern `^layer\s*=`), **THEN** les valeurs uniques sont {50, 60, 80, 100} — aucun doublon, aucun conflit. *Mécanisme : script awk ou GDScript helper qui ouvre chaque `.tscn`, parse les sections `[node ...]` qui ont `type="CanvasLayer"`, lit la propriété `layer = N` (top-level, pas qualifiée comme `physics_layer`), agrège, vérifie unicité. Covers architecture layer convention HUD=50/Shop=60/Pause=80/GSM-fade=100.*

## Open Questions

### OQ-MNU-1 — Save-on-quit handler ownership ✅ **RESOLVED 2026-04-27 (r2 cosmetic) — Option (a) délégation pure confirmée par Save/Load r1**

**Question** : MVP délègue le save-on-quit à SaveLoadSystem via son propre `NOTIFICATION_WM_CLOSE_REQUEST` handler (cohérent GSM EC-6, R-MNU-17b). Le Menu n'orchestre rien. Est-ce que ce contrat survit quand SaveLoadSystem sera écrit, ou faut-il que Menu appelle explicitement `SaveLoadSystem.save_now()` avant `get_tree().quit()` ?

**Options** :
- (a) **Délégation pure** — Menu appelle `get_tree().quit()` direct, SaveLoadSystem intercepte via `NOTIFICATION_WM_CLOSE_REQUEST`.
- (b) **Save-then-quit explicite** — Menu appelle `SaveLoadSystem.save_now()` SYNC puis `get_tree().quit()`. Couplage explicite Menu ↔ SaveLoadSystem.
- (c) **Verbe GSM `request_quit(save_first: bool)`** — extension ADR-0007 D-10 (cf. GSM OQ-3) qui centralise la logique. Le Menu appelle `GSM.request_quit(true)`.

**RESOLUTION (r2 — Save/Load r1 ratifie option (a))** : la délégation pure est validée par 4 garanties Save/Load r1 + ADR-0010 :

1. **R-SAV-9** — SaveLoadSystem possède son propre handler `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` qui flush l'état (no-op MVP grâce au write-through).
2. **R-SAV-8** — SaveLoadSystem est `PROCESS_MODE_ALWAYS` : reçoit le notification même si le quit est déclenché depuis Pause Menu (`get_tree().paused == true`).
3. **R-SAV-5** — write-through synchrone : zéro état RAM dirty au moment du quit. Le `_flush_pending()` est volontairement no-op MVP (filet de sécurité Tier 2+).
4. **ADR-0007 D-1 (autoload position 3)** — SaveLoadSystem est autoload pos-3 (`InputManager → GameStateManager → SaveLoadSystem → AudioSystem`), garanti vivant à la frame de quit (Godot délivre `NOTIFICATION_WM_CLOSE_REQUEST` avant destruction de l'arbre, autoloads détruits **après** scene root).

**Conséquences MVP** :
- R-MNU-17b reste tel quel : Menu appelle `get_tree().quit()` direct, ne fait aucun appel `SaveLoad.*`.
- Aucun amendement R-MNU requis. Aucune ADR nouvelle requise.
- Lint AC-MNU-57 ajouté (r2 — voir Groupe K) : `grep -r "save\|SaveLoad" src/gameplay/menu/` → 0 match enforce la délégation par construction.
- OQ-MNU-6 (Alt+F4 / Cmd+Q) résolue par cascade : même pattern (a) couvre toutes les sources de `NOTIFICATION_WM_CLOSE_REQUEST`.

**Option (b)** : rejetée — couplage Menu ↔ SaveLoadSystem viole R-MNU-18 (zéro logique gameplay/save dans Menu).
**Option (c)** : déférée Tier 2+ uniquement si Settings Menu introduit dialog "Save before quit?" (anti-fantasy MVP exclut ce cas).

**Owner** : SaveLoadSystem r1 author + ce GDD r2. **Status** : **RESOLVED**. **Target** : N/A — résolu par Save/Load r1 (committed `?? design/gdd/save-load-system.md` + ADR-0010 Proposed). Réouverture si Save/Load r2 amendement casse le pattern.

### OQ-MNU-2 — Bus audio `MENU_UI` Tier 2+

**Question** : MVP zéro SFX cohérent Audio r2.1. Si playtest 1 demande feedback sonore sur clic boutons (pour différencier "j'ai cliqué" vs "ça n'a pas pris"), faut-il :

**Options** :
- (a) **Ajouter bus dédié `MENU_UI`** (parallèle à `UI` ADR-0009 D-1) — propre, isolé, mute-able indépendamment.
- (b) **Réutiliser bus `UI` existant** — moins de buses, cohérent ADR-0009.
- (c) **Aucun SFX, jamais** — assume MVP scope définitif, le silence est design positif.

**Recommandation** : (b) réutilisation `UI` si SFX décidés Tier 2+ (parsimonieux). Décision dépend du playtest 1 — si le silence est critiqué comme "incertitude bouton", introduire SFX click court < 30 ms ; sinon (c) maintenir scope MVP.

**Owner** : audio-director + ux-designer + sound-designer. **Target** : post-playtest 1 — amendement Audio r2.2 + ce GDD r2 si activé.

### OQ-MNU-3 — Settings Menu Tier 2+ scope

**Question** : MVP livre 0 settings menu. Tier 2+ requerra : sensitivity souris, mouse Y inverted, audio sliders Master/Music/SFX, font scaling accessibility, remap clavier (ADR-0004 mentionne `remap_overrides` Dictionary). Quelle structure pour le Settings Menu ?

**Options** :
- (a) **Scène distincte** `settings_menu.tscn` chargée via `request_scene_transition` depuis Main Menu et Pause Menu. Cohérent two-path scene container.
- (b) **Overlay sub-menu** dans Pause Menu et Main Menu (deux instances Control fillins). Plus de code, moins de transitions visuelles.
- (c) **Tab interne** dans le Pause Menu (tabs General / Audio / Controls). Compact mais complexe MVP-style.

**Recommandation** : (a) scène distincte — cohérent ADR-0007 D-5 §a, réutilisable depuis Main Menu et Pause. Architecturalement le plus propre.

**Owner** : ux-designer + game-designer. **Target** : Tier 2+ scope freeze — exigera amendement ce GDD r2 + nouveau /design-system settings-system ou extension Menu r2.

### OQ-MNU-4 — Splash screen Godot logo (boot first impression)

**Question** : Godot 4.6 affiche par défaut un splash screen "Made with Godot" au boot (configurable dans `project.godot`). Le Player Fantasy section §Anti-fantasy interdit "splash screen studio long". Faut-il :

**Options** :
- (a) **Désactiver le splash Godot** entièrement (`application/boot_splash/show_image = false`). Cohérent anti-fantasy.
- (b) **Garder splash Godot court** (≤ 500 ms, image custom Chrome Zen). Compromis brand-light / cohérent direction visuelle.
- (c) **Splash custom studio** ≤ 2 secondes (logo studio Chrome Zen). Pour quand le projet aura un studio name.

**Recommandation MVP** : (a) désactiver splash Godot pour l'instant. Le Main Menu apparaît dès la première frame possible, conforme anti-fantasy "AAA opening cinematics 30s REJETER". (c) reportée Full Vision si rebrand studio.

**Owner** : Martin (vision branding) + art-director. **Target** : avant build distribuable Tier 2+ (Vertical Slice itch.io).

### OQ-MNU-5 — Pause Menu structure : autoload vs node-local

**Question** : R-MNU-3 décide node-local (instancié dans chaque scène étage). Une alternative est l'autoload (instancié 1× au boot, persiste cross-scene). Décision tranchée MVP via R-MNU-3 mais à valider en playtest.

**Options** :
- (a) **Node-local** (statu quo MVP R-MNU-3) — Pause Menu vit avec la scène étage, détruit au scene change. Cohérent "Pause vit avec le gameplay". Pattern simple.
- (b) **Autoload** — Pause Menu instancié au boot, écoute state_changed cross-scene. Survit au change_scene_to_file. Plus de code mais moins de duplication par scène.

**Recommandation MVP** : (a) node-local définitive — simple, clear ownership. (b) considéré rejeté car le Pause Menu n'a pas vocation à exister hors gameplay (impossible en Main Menu où il n'y a rien à pauser).

**Owner** : gameplay-programmer + ce GDD. **Status** : RESOLVED MVP via R-MNU-3. Réouverture si pattern fail au playtest 1.

### OQ-MNU-6 — Quit shortcut (Alt+F4 / Cmd+Q) handling ✅ **RESOLVED 2026-04-27 (r2 cosmetic) — par cascade OQ-MNU-1**

**Question** : Godot intercepte par défaut Alt+F4 (Windows/Linux) et Cmd+Q (macOS) → émet `NOTIFICATION_WM_CLOSE_REQUEST`. Le Menu doit-il faire quelque chose de spécial, ou laisser le pattern (a) OQ-MNU-1 (délégation SaveLoadSystem) gérer ?

**RESOLUTION** : la même délégation pure que OQ-MNU-1 RESOLVED couvre Alt+F4 et Cmd+Q par construction — Save/Load r1 R-SAV-9 owns un handler `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` qui flush l'état quel que soit le déclencheur du notification (bouton "Quitter le jeu", Alt+F4, Cmd+Q, kill window via OS). Le Menu ne fait **rien de spécifique** pour ces shortcuts. Aucun amendement R-MNU requis.

**Conséquences MVP** : Alt+F4 / Cmd+Q fonctionnent identiquement au bouton "Quitter le jeu" — quit immédiat, save-on-quit délégué. Si MVP livre sans SaveLoadSystem (Not Started), Alt+F4 quit le jeu sans save (acceptable car Menu stateless cross-session R-MNU-18).

**Owner** : SaveLoadSystem r1 (déjà confirmé). **Status** : **RESOLVED**. **Target** : N/A.

### OQ-MNU-7 — Confirm dialog future-proof exception (épilepsie / parental advisory)

**Question** : Player Fantasy interdit confirm dialogs. Si distribution Steam exige avertissement épilepsie au premier boot, ou parental advisory dans certaines régions, comment réconcilier ?

**Options** :
- (a) **Page Settings consultable** (Tier 2+) — l'avertissement vit en page Settings dédiée, pas en interstitiel boot.
- (b) **Splash screen 1× au tout premier boot** — flag persisté `first_boot_warning_shown` (Save key), affiché 1× puis jamais. Compromis légal.
- (c) **Aucune dérogation** — refuse les exigences légales si elles compromettent l'anti-fantasy.

**Recommandation** : (a) en MVP cohérent direction. (b) si exigence légale dure (éviter (c) qui bloquerait distribution).

**Owner** : release-manager + Martin. **Target** : avant submission Steam/itch.io Tier 3.

### OQ-MNU-8 — Localization fallback strategy

**Question** : MVP français uniquement (boutons "Reprendre", "Quitter vers Menu Principal", "Quitter le jeu", titre "CHROME://ASCENT"). Tier 2+ va vouloir EN/ES/DE. Quelle stratégie ?

**Options** :
- (a) **Godot tr() partout** dès MVP — anticipation, mineur overhead. Translation key `menu.button.start_run`, etc.
- (b) **Strings hardcodés FR MVP** + refactor Tier 2+ avec `/localize` skill.
- (c) **CSV translation MVP** dès le départ — plus carré mais demande travail upfront.

**Recommandation MVP** : (b) hardcodé FR — refactor Tier 2+ via `/localize` skill (existe dans le studio). Évite overhead i18n MVP solo dev.

**Owner** : localization-lead Tier 2+. **Target** : pré-Vertical Slice.

### OQ-MNU-9 — Pause overlay layer collision avec future cinematic / cutscene Tier 2+

**Question** : Layer 80 réservé Pause overlay. Si Tier 2+ introduit Cutscene System avec overlay (letterbox bars, subtitles), quel layer ?

**Recommandation** : Cutscene Tier 2+ utilise layer 70 (entre Shop=60 et Pause=80) — cutscene peut être paused par-dessus, mais ne couvre pas Pause Menu. Validé via amendement collision-layer-taxonomy ADR-0008 si Cutscene activé. Anti-collision documentée.

**Owner** : technical-director + cutscene-system author. **Target** : Tier 2+ activation Cutscene.

### OQ-MNU-10 — Boot directement sur étage gameplay (skip Main Menu) — debug feature

**Question** : Pendant le développement, est-il utile d'avoir un mode "boot direct sur etage_01.tscn" pour gain de temps dev (skip Main Menu click) ?

**Options** :
- (a) **Project Setting + flag CLI** (`godot --skip-menu`) qui force `start_etage(1)` au boot. Debug-only.
- (b) **Aucune option** — toujours boot Main Menu pour cohérence playtest.

**Recommandation** : (a) debug-only feature, guard `OS.has_feature("debug")`. Utile dev velocity. Cohérent avec convention `simulate_*` debug-only Input ADR-0004 D-9.

**Owner** : devops-engineer + gameplay-programmer. **Status** : nice-to-have, pas bloquant. **Target** : Sprint 1 quality-of-life dev tooling.
