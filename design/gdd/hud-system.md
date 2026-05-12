# HUD System

> **Status**: In Design (r1.1 — solo auto-approve, amendement r2.2 cascade NB-CRD-6 Option A 2026-04-28 — pulse différencié SECRET tween +50% durée)
> **Author**: Martin + game-designer + ux-designer + ui-programmer + art-director + qa-lead (r1.1 amendement creative-director adjudication NB-CRD-6 cascade Audio r2.2)
> **Last Updated**: 2026-04-28 (r1.1 amendement — Rule 5 différenciation source KILL/SECRET, F-HUD-1 variables, Tuning Knob `CREDIT_COUNTER_TWEEN_SECRET_MS`, AC-HUD-36)
> **Implements Pillar**: Pillar 2 (LA PROGRESSION SE VOIT) primaire, Pillar 1 (FLOW AVANT TOUT) garde-fou contraint
> **Depends on**: Credit Economy (Designed r1), Game State Manager (APPROVED r1), Player Combat (APPROVED r6), Level System (APPROVED r3) ; consume only — zero outbound dependencies.
> **Depended on by**: Tutorial (Tier 2+), Accessibility System (Tier 3 text scaling)

---

## Overview

Le HUD System est un autoload Godot 4.6 qui pilote l'unique élément d'interface visible pendant le gameplay actif de CHROME://ASCENT : **un counter de crédits monospace en blanc froid, ancré en coin supérieur droit**. Il est exclusivement consommateur — il ne mute aucun système amont, ne route aucune décision gameplay, et n'émet aucun signal. Au boot, il pull synchronement `CreditEconomy.get_total()` et `GameStateManager.get_current_state()` (ADR-0007 D-9 pattern pull). À chaque émission `CreditEconomy.credits_changed(total, delta, source: SourceKind)` SYNC, il met à jour le Label dans le même `_physics_process` tick que le kill (Pillar 1 FLOW garde-fou). Sa visibilité est gouvernée par `GameStateManager.state_changed`: visible en `PLAYING` et `RESPAWNING`, masqué en `MENU`, `PAUSED`, `BOSS_DEFEATED`. Le scope MVP **exclut** intentionnellement health bar, ammo, minimap, compass, objective marker, hint UI, death screen, et damage numbers — tous violent un anti-pillar du game-concept.

> **Quick reference** — Layer: `Presentation` · Priority: `MVP` · Key deps: `Credit Economy (Designed r1, signal credits_changed SYNC + getter get_total), Game State Manager (APPROVED r1, signal state_changed SYNC + getter get_current_state)` · Soft deps: `Player Combat (cooldown_ratio property — non affiché MVP), Level System (room_entered signal — Tier 2+)` · Consumed by: aucun (terminal aval).

> **CanvasLayer.layer** : `< 100` (typique `50`) — GSM owns layer 100 pour fade overlay et focus auto-pause (GSM GDD ligne 395).

> **ADR de référence** : aucun ADR dédié HUD MVP (la complexité ne le justifie pas — pattern pull GSM ADR-0007 D-9 + signal SYNC Credit Economy r1 sont les seules contraintes architecturales). Tier 2+ pourra justifier ADR si UI Toolkit Godot 4.5+ ou Accessibility Tier 3 introduisent des nouveaux trade-offs.

## Player Fantasy

> **North Star** — *"Tu ne regardes pas l'UI. Tu sens le crédit grimper en périphérie, comme un odomètre qui chuchote pendant que tu danses."*

Le HUD de CHROME://ASCENT est un compteur silencieux. Il vit dans le vide corporate de la salle — même typographie monospace que les portes du shop, même blanc cassé que les murs. Il n'est pas plaqué au-dessus du jeu : il *appartient* au monde. Quand tu enchaînes un wall-run, un dash et une exécution, tu n'as jamais quitté la lame des yeux ; pourtant ton cerveau sait que tu es passé de 12 à 47. Le chiffre s'est inscrit sans interrompre.

Le HUD sert **Pillar 2 — La progression se voit** comme contrat primaire : le crédit est l'unique élément matérialisé parce qu'il est l'unique chose qui *doit* se voir. Il sert aussi **Pillar 1 — Flow avant tout** par soustraction : tout ce qui n'est pas le compteur est absent par discipline, pas par oubli. Il sert **Pillar 3 — Une seconde chance** par silence : pas de death-screen, pas de stats summary, pas de "+1 CREDIT" floating text. La punition de la mort est lisible (le crédit a baissé / n'a pas changé) sans être commentée.

> **Moment d'ancrage** — Tu finis une salle. Tu n'as pas regardé l'UI une seule fois. Pourtant, sans y penser, tu sais que tu as 47 crédits. C'est le HUD qui a fait son travail.

> **Ce que le HUD n'est PAS** — Pas un tableau de bord. Pas de combo counter qui pop, pas de "+1 CREDIT" floating text, pas de breakdown ("3× grunt + 2× secret"), pas de mini-map, pas de quest log, pas d'objective marker, pas de death screen, pas de damage flash propre (le damage flash mort est owned par Camera/VFX). Si le joueur *lit* le HUD pendant un combat, on a échoué.

> **Design test playtest (gate Pillar 2)** — Après une run de 90 secondes, demande au playtester son crédit final. S'il peut le citer à ±5 sans avoir détourné les yeux du jeu, le HUD remplit sa fantasy. S'il dit "attends, je regarde", on a un overlay, pas un odomètre.

**Cohérence inter-systèmes** : ce framing prolonge directement la Player Fantasy de Credit Economy ("ticker silencieux qui grimpe quand tu danses bien"). Le HUD est la **manifestation visuelle** du ticker que le Credit Economy maintient en interne — même fréquence émotionnelle, même discipline du silence.

## Detailed Rules

### Core Rules

1. **Autoload data-light, instanciation explicite.** Le `HUDSystem` est enregistré comme **autoload Godot** dans `project.godot`. Il instancie un `CanvasLayer` enfant à `_ready()`, qui contient les éléments d'UI MVP (Label `CreditCounterLabel`). Les autoloads `CreditEconomy` et `GameStateManager` doivent être listés **AVANT** `HUDSystem` dans `Project Settings > Autoload` afin que le pattern pull au `_ready()` HUD trouve les singletons initialisés (cf. OQ-HUD-4).

2. **Pattern pull au boot, jamais d'attente de signal `game_booted`.** Au `_ready()` du HUD, deux appels synchrones :
   - `var current_state := GameStateManager.get_current_state()` → applique la visibility logic immédiatement (avant la première frame rendue).
   - `var initial_total := CreditEconomy.get_total()` → set `Label.text = str(initial_total)` sans tween (hard set, pas d'animation roll-up depuis 0).
   Aucun signal `game_booted` n'existe (GSM Rule 12 — minimisation API).

3. **Connexion SYNC à `CreditEconomy.credits_changed`.** Connecter au `_ready()` :
   ```
   CreditEconomy.credits_changed.connect(_on_credits_changed)  # SYNC
   ```
   Pas de `CONNECT_DEFERRED` — le counter doit s'updater au même `_physics_process` tick que le kill (Pillar 1 FLOW). Le handler est un cold path (~3 lignes : update var cible, lance Tween, end).

4. **Connexion CONNECT_DEFERRED à `GameStateManager.state_changed`.** Conformément à GSM Rule 4 (consumers lourds en CONNECT_DEFERRED côté consumer) :
   ```
   GameStateManager.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)
   ```
   Rationale : la visibility logic implique potentiellement un rebuild structurel (show/hide CanvasLayer enfants, animation de transition), ce qui ne doit pas bloquer le SYNC emit du GSM. Un retard d'une frame (~16 ms) sur l'apparition/disparition du HUD est imperceptible.

5. **Animation increment positive : pulse de scale (différencié par source — r1.1 NB-CRD-6 Option A).** Sur `delta > 0`, exécuter en parallèle :
   - `Label.text = str(total)` — hard set immédiat (pas de roll-up numérique au MVP).
   - Tween `Label.scale` de `Vector2.ONE` → `Vector2(PULSE_SCALE_MAGNITUDE, PULSE_SCALE_MAGNITUDE)` → `Vector2.ONE`, easing `Tween.EASE_IN_OUT TRANS_SINE`.
   - **Durée tween différenciée par `source`** (r1.1 amendement NB-CRD-6 cascade Audio r2.2) :
     - `source == SourceKind.KILL` → `CREDIT_COUNTER_TWEEN_KILL_MS = 100 ms` (default historique r1, inchangé).
     - `source == SourceKind.SECRET` → `CREDIT_COUNTER_TWEEN_SECRET_MS = 150 ms` (+50% durée — Pillar 4 viscéralité MVP minimum, "le compteur sait que c'était un riff, pas un battement"). Cohérent avec Audio r2.2 Rule 17 (clac aigu pitch +5 semitones bus `SFX`) — la **durée plus longue** du pulse HUD est l'extension visuelle du **timbre plus long perçu** côté audio.
   - Si un tween est déjà en cours quand un nouveau signal arrive (multi-kill 3 emits dans le même tick — Combat `MAX_KILLS_PER_SWING = 3`), tuer le tween précédent (`tween.kill()`) et re-démarrer un nouveau pulse à partir de la scale courante avec la durée correspondant au `source` du nouveau signal. Le total final affiché atteint donc toujours `N + Σdelta` sans overshoot (AC-HUD-19/20).
   - **Magnitude pulse identique** pour KILL et SECRET au MVP (`PULSE_SCALE_MAGNITUDE = 1.05`). Différenciation magnitude réservée Tier 2+ via knob `PULSE_SCALE_MAGNITUDE_SECRET` (provisoire, non implémenté MVP).
   - **Edge case kill simultané + secret au même tick** : si Combat `enemy_killed` (KILL) et Secret `secret_collected` (SECRET) émettent tous deux dans le même `_physics_process`, l'ordre d'arrivée déterministe Credit Economy (séquentiel sur stack) garantit deux `credits_changed` SYNC consécutifs ; le 2e tween écrase le 1er via `tween.kill()`, durée du 2e source l'emporte. Pas de race observable. AC-HUD-36.

6. **Action sur `delta < 0` (`SourceKind.SPEND_SHOP`) : hard set sans animation.** `Label.text = str(total)` sans tween. Le scale reste à `Vector2.ONE`. Rationale : le spend a lieu hors gameplay direct (écran shop), pas besoin de feedback de gain — la valeur baisse silencieusement. AC-HUD-08.

7. **Action sur `delta == 0` (`SourceKind.BOOT_HYDRATE`) : hard set, jamais de tween.** `Label.text = str(total)` sans animation. Mécanisme garde-fou : le handler vérifie `if delta == 0: skip tween branch`. Évite un faux pulse au boot. AC-HUD-24.

8. **Visibility par State (machine binaire visible/hidden).** Le handler `_on_state_changed(new_state: State)` applique la table de visibilité (cf. States and Transitions §). Implémentation : `_canvas_layer.visible = (new_state in [State.PLAYING, State.RESPAWNING])`. Pas de tween de fade au MVP — show/hide instantané. Le respawn 50 ms ne peut pas accommoder un fade.

9. **Pendant `RESPAWNING` : counter visible, pas de freeze.** Le RESPAWN_DELAY de 50 ms est trop court pour un masquage sans flicker. Maintenir `Label.visible = true` ; si un tween d'increment est actif au moment où le state passe `PLAYING → RESPAWNING`, le laisser s'achever (Pillar 3 — pas d'interruption visible du visuel pré-mort). AC-HUD-15.

10. **Pendant `PAUSED` : counter masqué.** Le Menu System owns le pause overlay (full-screen depuis MVP). Le counter HUD est redondant et peut chevaucher visuellement le menu. `Label.visible = false`. Quand `PAUSED → PLAYING` resume, `Label.visible = true` instantané. AC-HUD-14.

11. **Layer ordering strict.** `CanvasLayer.layer` du HUD est figé à `50` (constante `HUD_CANVAS_LAYER`). GSM owns `layer = 100` pour ses overlays (fade transitions, focus pause overlay). Le HUD doit toujours être *en-dessous* du GSM overlay. AC-HUD-25/26.

12. **Outbound-only, zero couplage cross-feature.** Le HUD ne référence **jamais** `CombatSystem`, `LevelSystem`, `MovementController`, `EnemySystem`, `AudioSystem`, ou `Player.*` directement. Les seules deps autorisées sont `CreditEconomy` et `GameStateManager` (et indirectement `InputManager` via GSM, mais HUD ne touche pas Input). Toute future extension (e.g. cooldown_ratio Tier 2+) doit être justifiée par amendement de cette rule. AC-HUD-35.

13. **Zero allocation hot path.** Le handler `_on_credits_changed` ne doit jamais allouer (pas de `String + ` concat, pas de `Dictionary` literal, pas de `Array.new()`). Pattern : `Label.text = str(total)` est l'unique alloc tolerée (boxing int → String — Godot intern handle), tween pré-instancié recyclé via `tween.kill() + create_tween()` rather than allocating new tween every event. AC-HUD-28 + lint cover-all `.claude/rules/no-alloc-hot-paths.md` à étendre au HUD si MVP révèle un budget delta > 64 KB / 60 s.

14. **Aucun input HUD MVP.** Le HUD ne consomme **jamais** `InputManager.*` ni `Input.*` directement. Toutes les actions UI (pause, menu) sont owned par Menu System. Cette rule durcit la compliance avec ADR-0004 D-7 (Input main thread only). AC-HUD-35 + lint `.claude/rules/input-singleton-main-thread-only.md`.

15. **Aucun SFX HUD MVP.** Le HUD n'appelle **jamais** `AudioServer.*`, `AudioStreamPlayer.*`, ni `AudioSystem.play_2d/3d`. Cohérent avec audio-system.md ligne 169. Si Tier 2+ veut un pickup chime, il sera router via Audio System — jamais en local au HUD. AC-HUD-34.

### States and Transitions

Le HUD a une seule "machine" : visibility par GSM State. Pas de state machine interne au HUD MVP.

| GSM State | `Label.visible` | Notes |
|---|---|---|
| `MENU` | `false` | Avant le boot run. Counter inutile, Main Menu overlay couvre l'écran. AC-HUD-12 |
| `PLAYING` | `true` | État nominal — gameplay actif, counter visible. AC-HUD-13 |
| `PAUSED` | `false` | Menu de pause owned par Menu System couvre l'écran. AC-HUD-14 |
| `RESPAWNING` | `true` | Fenêtre 50 ms wall-clock. Pas de freeze, pas de fade. Pillar 3 — la transition est invisible pour le joueur. AC-HUD-15 |
| `BOSS_DEFEATED` | `false` | État terminal post-MVP (boss final non livré MVP). Quand atteint, le HUD se retire pour laisser place aux credits roll. AC-HUD-16 |

**Transitions critiques** :
- `MENU → PLAYING` (run start) : show. Boot pull a déjà fait le `Label.text = str(initial_total)` au `_ready()`.
- `PLAYING → PAUSED → PLAYING` : hide → show. Le tween d'increment éventuellement actif est tué à `PAUSED` (frees), redémarre uniquement sur prochain `credits_changed` post-resume.
- `PLAYING → RESPAWNING → PLAYING` : reste `true` au fil des transitions. Le respawn ne re-pull pas `get_total()` (idempotence Credit Economy Rule 2 + AC-HUD-22).
- `PLAYING → BOSS_DEFEATED` : hide définitif jusqu'à `MENU` (run end).

### Interactions with Other Systems

| System | Direction | Type | Contract |
|---|---|---|---|
| **Credit Economy** (Designed r1) | In | Hard | `get_total() -> int` au `_ready()` (boot pull) ; signal `credits_changed(total: int, delta: int, source: SourceKind)` SYNC pendant le run. Le HUD lit, n'écrit jamais. |
| **Game State Manager** (APPROVED r1) | In | Hard | `get_current_state() -> State` au `_ready()` (boot pull) ; signal `state_changed(new_state: State)` CONNECT_DEFERRED côté HUD (GSM Rule 4). Le HUD lit, n'écrit jamais. |
| **Player Combat** (APPROVED r6) | In | Soft (post-MVP) | Property `cooldown_ratio: float` accessible mais **non affichée MVP** (Combat §Interactions ligne 275 — feel "no UI"). Tier 2+ uniquement si playtest demande un indicateur cooldown visible. |
| **Level System** (APPROVED r3) | In | Soft (post-MVP) | Signal `room_entered(room_index: int, total_rooms: int)` accessible mais **non consommé MVP** (cf. OQ-HUD-2). Décision Tier 2+ après playtest 1 — l'architecture Level (verticalité visuelle) est censée orienter le joueur sans HUD. |
| **Menu System** (Not Started, MVP) | Peer | Soft | Aucun couplage direct. Menu owns le pause overlay (full-screen) ; le HUD se masque pendant `PAUSED` via signal GSM, pas via appel Menu. |
| **VFX & Feedback System** (Not Started, MVP) | Peer | Soft | Aucun couplage. Le damage flash mort (fondu rouge 200ms — game-concept ligne 98) est **owned par Camera System ou VFX**, pas par HUD. Le HUD n'a aucun élément full-screen. |
| **Audio System** (APPROVED r2.1) | Peer | Aucun MVP | Aucun SFX HUD au MVP (audio-system.md ligne 169). Tier 2+ pickup chime à designer en `/design-system secret-system` ou amendement Audio. |
| **Save/Load System** (Not Started, MVP) | Peer | Aucun | Le HUD ne persiste rien — l'état visuel est dérivé du `total_credits` Credit Economy. |
| **Input System** (APPROVED... pending r4) | Aucun | Aucun MVP | Le HUD ne consomme jamais Input. Lint cover-all `.claude/rules/input-singleton-main-thread-only.md` couvre le HUD par défaut. |
| **Tutorial / Onboarding** (Not Started, Tier 2+) | Peer | Aucun MVP | Tier 2+ pourra ajouter un room indicator subtil consommant `LevelSystem.room_entered`, à designer alors. |
| **Accessibility System** (Not Started, Tier 3) | Peer | Future | Text scaling slider, font weight options, contrast modes — tous Tier 3. AC-HUD-29/30 confirme passive resize tolerance MVP. |

**Architecture principle** : le HUD est **terminal aval** — il n'émet aucun signal et aucun système ne dépend de lui. Toute future extension (Tier 2+ room indicator, Tier 3 accessibility) suit la même règle outbound-only.

## Formulas

Le HUD MVP est un système data-passif quasi-pur — il n'effectue aucun calcul gameplay. Les seules formules sont des **paramètres d'animation** et un **mapping de positionnement responsive**, exposés ici pour traçabilité tuning.

### F-HUD-1 — Pulse de scale credit counter (animation increment, différencié source r1.1)

`scale(t) = lerp(1.0, PULSE_SCALE_MAGNITUDE, ease_in_out_sine(t / (D / 2))) puis lerp(PULSE_SCALE_MAGNITUDE, 1.0, ease_in_out_sine((t - D / 2) / (D / 2)))`

où `D = CREDIT_COUNTER_TWEEN_KILL_MS` si `source == SourceKind.KILL`, sinon `D = CREDIT_COUNTER_TWEEN_SECRET_MS` si `source == SourceKind.SECRET`.

**Variables** :

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| Durée pulse KILL | `CREDIT_COUNTER_TWEEN_KILL_MS` | int | `[60, 200]` ms | Tuning knob (renommé r1.1 depuis `CREDIT_COUNTER_TWEEN_MS`). Default `100 ms`. < 60 ms imperceptible (anti-Pillar 2) ; > 200 ms distraction (anti-Pillar 1). |
| Durée pulse SECRET (r1.1) | `CREDIT_COUNTER_TWEEN_SECRET_MS` | int | `[120, 250]` ms | Tuning knob nouveau r1.1 amendement NB-CRD-6 Option A. Default `150 ms` (+50% vs KILL). Doit rester `> CREDIT_COUNTER_TWEEN_KILL_MS` (invariant balance — différenciation perceptive Pillar 4 viscéralité). |
| Magnitude pulse | `PULSE_SCALE_MAGNITUDE` | float | `[1.02, 1.10]` | Tuning knob. Default `1.05` — multiplicateur de scale au pic. Identique KILL et SECRET MVP (différenciation magnitude Tier 2+). |
| Easing | — | enum | `Tween.EASE_IN_OUT TRANS_SINE` | Cohérent Chrome Zen (pas de bounce, pas de spring, pas d'élastique). |

**Output range** : `scale ∈ [1.0, 1.05]`, durée ∈ `[100, 150]` ms wall-clock selon source. Tween non bloquant `_physics_process` (Godot Tween system tourne en `_process`).

**Example KILL** : kill grunt à `t = 0`, `source = KILL`. À `t = 0` : `scale = 1.0`. À `t = 50 ms` : `scale = 1.05` (pic). À `t = 100 ms` : `scale = 1.0` (retour au repos).

**Example SECRET (r1.1)** : secret tier-1 collecté à `t = 0`, `source = SECRET`. À `t = 0` : `scale = 1.0`. À `t = 75 ms` : `scale = 1.05` (pic — milieu du tween 150 ms). À `t = 150 ms` : `scale = 1.0` (retour au repos). Le pulse dure 50% plus longtemps que pour un kill — perception viscérale "ce gain a pris plus de temps à mériter" cohérente Audio Rule 17 (clac aigu signature distincte).

**Wall-clock invariance** : durée 100 ms (KILL) ou 150 ms (SECRET) reste wall-clock indépendant de `Engine.time_scale` — au cas où un kill déclenche slow-mo Combat (`SLOW_MO_SCALE = 0.3`) au même tick, le pulse HUD utilise `wall-clock` (pas time_scaled) en passant `tween.set_ignore_time_scale(true)` (Godot 4.6 API — pattern Enemy GDD r2 set_ignore_time_scale, RESOLVED).

**Edge case** : multi-kill 3 emits dans le même tick. Trois `_on_credits_changed(N+i, +1, KILL)` séquentiels SYNC. À chaque emit : `tween.kill()` puis `create_tween()` redémarre le pulse à scale courante. Le pulse final atteint son pic ~50 ms après le dernier emit, puis retombe. Pas d'overshoot de scale > 1.05 ni de drift permanent. AC-HUD-19/20.

---

### F-HUD-2 — Positionnement responsive du counter

```
position_x = viewport_width - margin_right - label_width
position_y = margin_top
```

**Variables** :

| Variable | Symbole | Type | Range | Description |
|----------|---------|------|-------|-------------|
| Marge droite | `HUD_MARGIN_RIGHT_PX` | int | `[16, 48]` px | Tuning knob. Default `24 px`. Distance du bord droit. |
| Marge haut | `HUD_MARGIN_TOP_PX` | int | `[16, 48]` px | Tuning knob. Default `20 px`. |
| Largeur label calculée | `label_width` | float | dynamique | `Label.get_minimum_size().x` après `Label.text` set. Recalculé à chaque update. |

**Output range** : `position ∈ [0, viewport_size - label_size]`. Garantit que le counter reste in-bounds sur 1080p / 1440p / 4K (resize passifs validés AC-HUD-29).

**Example** : viewport `1920×1080`, `Label.text = "₵ 47"`, font `JetBrainsMono 18px` → `label_width ≈ 64 px`, `label_height ≈ 24 px`. `position_x = 1920 - 24 - 64 = 1832`. `position_y = 20`. Coin supérieur droit, hors zone centrale crosshair (Pillar 1).

**Anchor Godot** : utiliser `Control.LayoutPreset.PRESET_TOP_RIGHT` avec offsets négatifs `offset_right = -HUD_MARGIN_RIGHT_PX`, `offset_top = HUD_MARGIN_TOP_PX`. Resize passif géré nativement par Godot (AC-HUD-29).

---

### F-HUD-3 — (Provisoire — Tier 2+) Flash couleur source-dependent

Conditionnelle à OQ-HUD-1 (décision art-director documentée Visual section). MVP : pas de flash distinct par source. Tier 2+ ou décision r2 :

```
if source == SourceKind.SECRET and delta > 0:
    label_color_tween(Color("#E8E8F0") -> Color("#00D4FF") -> Color("#E8E8F0"), 180 ms)
```

**Output range** : couleur `Color3 ∈ {#E8E8F0, #00D4FF}`, durée 180 ms wall-clock. Tween parallèle au pulse de scale.

**Activation MVP** : `false` par défaut (knob `HUD_SECRET_FLASH_ENABLED = false` — voir Tuning Knobs). Activable r2 si playtest 1 montre que les joueurs n'identifient pas la nature du gain.

> **Note** : aucune autre formule n'est nécessaire — pas de calcul de damage, pas de cost curve (Shop side), pas de progression XP (n'existe pas), pas de health interpolation (one-shot strict).

## Edge Cases

- **EC-HUD-01 — Boot avant CreditEconomy ou GSM autoload prêt** : Si l'ordre d'autoload dans `project.godot` place `HUDSystem` avant `CreditEconomy` ou `GameStateManager`, les appels `_ready()` `CreditEconomy.get_total()` / `GameStateManager.get_current_state()` lèvent une erreur (autoload non instancié). Résolution : **forcer l'ordre d'autoload** `InputManager → GameStateManager → CreditEconomy → HUDSystem` (et autres autoloads avant HUD). À documenter dans le GDD Tuning Knobs comme contrainte projet (OQ-HUD-4 RESOLUE par convention). Garde-fou `assert(GameStateManager != null and CreditEconomy != null, "HUD: autoload order broken")` au début de `_ready()`.

- **EC-HUD-02 — credits_changed reçu pendant `MENU` ou `BOSS_DEFEATED`** : Cas improbable (CreditEconomy guard Rule 8 `state in [PLAYING, RESPAWNING, BOOT_HYDRATE_phase]` n'émet pas hors PLAYING). Mais si un signal arrive : le HUD met à jour `Label.text` silencieusement et lance le pulse de scale ; le `Label.visible == false` masque le visuel. Pas de crash, pas d'effet observable. Rationale : robustesse défensive sans coût (Pillar 1 — ne jamais bloquer un signal valide).

- **EC-HUD-03 — credits_changed reçu pendant `PAUSED`** : Même comportement qu'EC-HUD-02 — update silencieuse, pas de visuel (counter masqué). Quand `PAUSED → PLAYING`, le counter affiche immédiatement la valeur courante (qui aura déjà été synchronisée par le silent update). Pas de tween de "rattrapage" — le visuel apparaît tel quel.

- **EC-HUD-04 — state_changed et credits_changed dans le même `_physics_process` tick** : Les deux signaux arrivent au même tick (e.g. kill au tick N déclenche credits_changed SYNC + Player.die au même tick déclenche state_changed → RESPAWNING DEFERRED côté HUD). Le credits_changed SYNC s'exécute en premier (handler met à jour Label, lance pulse). Le state_changed CONNECT_DEFERRED s'exécute idle frame N+1 (hide ou maintien visible selon RESPAWNING). Aucun race condition observable car ordre déterministe. AC-HUD-15.

- **EC-HUD-05 — Multi-kill 3 emits simultanés (MAX_KILLS_PER_SWING = 3)** : 3 SYNC handlers consécutifs dans la stack `_physics_process` Combat. Chaque handler kill le tween précédent et redémarre. La valeur Label.text saute `N → N+1 → N+2 → N+3` sans frame intermédiaire visible (tous dans le même tick). Le pulse final atteint son pic 50ms après le 3e emit. Aucun overshoot scale > 1.05. AC-HUD-19/20.

- **EC-HUD-06 — Tween en cours quand state passe PLAYING → PAUSED** : Le tween de pulse continue jusqu'à expiration s'il dépend de `_process` (Godot default Tween). Si `Label.visible = false`, le tween est invisible mais consomme ~0 cycles. Recommandation MVP : `tween.kill()` au passage PAUSED pour propreté. Implémentation Rule 10. Ne casse pas Pillar 3 (PAUSED hors-gameplay).

- **EC-HUD-07 — Tween en cours quand state passe PLAYING → RESPAWNING** : Pillar 3 — le tween reste actif. La fenêtre RESPAWN_DELAY = 50 ms est plus courte que CREDIT_COUNTER_TWEEN_MS = 100 ms ; le tween peut donc finir post-respawn (back en PLAYING). Pas de freeze visuel. AC-HUD-15.

- **EC-HUD-08 — credits_changed avec `total < 0`** : Cas impossible par contrat Credit Economy Rule 1 (`total_credits >= 0`). Garde défensive : `assert(total >= 0)` au handler en debug ; en release, accept et display (l'engine n'aura jamais émis cela). Pas de crash, pas de code path spécifique.

- **EC-HUD-09 — credits_changed avec `total > 999999`** : Le Label affiche le chiffre en clair (Godot Label gère int64). Width du label augmente, le `LayoutPreset.PRESET_TOP_RIGHT` ré-anchor automatiquement. Pas de scientific notation, pas de truncation. Tier 2+ pourra introduire `MAX_CREDITS` cap (Credit OQ-CRD-3).

- **EC-HUD-10 — Resize fenêtre pendant un tween actif** : Le resize Godot recalcule `Label.position` automatiquement via anchor. Le tween de scale continue indépendamment (il opère sur `Label.scale`, pas position). Aucun glitch observable. AC-HUD-29.

- **EC-HUD-11 — Toggle fullscreen → windowed pendant le tween** : Same comportement — anchor préserve la position, tween scale continu. AC-HUD-30.

- **EC-HUD-12 — Save/Load pendant le run (Tier 2+)** : Si Save/Load future implementation re-hydrate `total_credits` mid-run (e.g. quick-load), CreditEconomy émettra `credits_changed(N, 0, BOOT_HYDRATE)`. Le HUD applique Rule 7 (hard set, pas de tween). Pas de "+50 burst visuel" indésirable. AC-HUD-24.

- **EC-HUD-13 — Player.die() suivi immédiatement par kill du dernier ennemi (mutual kill, Combat r6 §H)** : Dans le scénario "mutual kill" (Combat AC-CMB-41) : le tick N voit (a) Player.attacked → Combat sweep → enemy dies → credits_changed SYNC delta=+1 (b) Enemy laser hit → Player.die SYNC → state_changed → RESPAWNING DEFERRED. Le counter reflète le crédit gagné AVANT la transition d'état. Le joueur voit son crédit monter même en mourant — Pillar 2 + Pillar 3 cohérents (la mort ne nie pas l'action accomplie). Validé EC-HUD-04.

- **EC-HUD-14 — Float scaling (Window.content_scale_factor != 1.0)** : Si l'utilisateur configure un scale UI custom (Tier 3 Accessibility ou option projet), le Label scale via Godot. La pulse F-HUD-1 reste cohérente (multiplicateur `1.05` est appliqué post-content-scale). Aucun fix MVP — laisse Godot gérer.

- **EC-HUD-15 — Mode debug F3 (CombatSystem.debug_hits_last_swing affichage)** : Combat GDD ligne 354 mentionne F3 debug HUD pour "last swing hit: 2 enemies". MVP HUD ne l'implémente pas (debug = developer-only) — Combat fournit la property en read-only mais HUD ne l'affiche pas. Tier 2+ ou debug build only. Pas d'impact MVP.

- **EC-HUD-16 — UI Master mute (Audio System OQ#6 RESOLU r2.1)** : Le HUD ne joue aucun son MVP. Le mute UI bus est sans effet observable sur le HUD. Cohérent audio-system.md.

## Dependencies

### Hard Dependencies (le HUD ne peut pas démarrer sans)

| System | Status | Interface consommée | Justification |
|---|---|---|---|
| **Credit Economy** | Designed r1 | `get_total() -> int` (boot pull au `_ready()`) ; signal `credits_changed(total: int, delta: int, source: SourceKind)` SYNC ; enum `SourceKind { KILL, SECRET, SPEND_SHOP, BOOT_HYDRATE }` | Sans Credit Economy, le HUD n'a aucune valeur à afficher — la raison d'être MVP du HUD disparaît. Bidirectional check : Credit Economy GDD r1 §Cousins 3 mentionne "HUD downstream consume `credits_changed` aval" ✅ |
| **Game State Manager** | APPROVED r1 | `get_current_state() -> State` (boot pull) ; signal `state_changed(new_state: State)` CONNECT_DEFERRED côté HUD ; enum `State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }` | Sans GSM, le HUD ne peut pas appliquer la visibility logic — il afficherait le counter en MENU/PAUSED, viole Pillar 1. Bidirectional check : GSM GDD §Interactions ligne 113 + UI Requirements ligne 419 mentionnent HUD comme consumer ✅ |

### Soft Dependencies (interface accessible mais non consommée MVP)

| System | Status | Interface accessible | MVP usage |
|---|---|---|---|
| **Player Combat** | APPROVED r6 | Property `cooldown_ratio: float` (read-only) | Non affiché MVP. Combat §Interactions ligne 275 : "MVP : pas d'indicateur visible (feel 'no UI' art-bible)". Bidirectional check : Combat GDD ligne 275 mentionne HUD ✅ — "Tier 2+" différé. |
| **Level System** | APPROVED r3 | Signal `room_entered(room_index: int, total_rooms: int)` | Non consommé MVP (cf. OQ-HUD-2). Bidirectional check : Level GDD ligne 229 mentionne HUD comme consumer optionnel ✅ — décision Tier 2+ après playtest 1. |

### Cousin Dependencies (peers, no shared interface)

| System | Status | Coordination |
|---|---|---|
| **Menu System** | Not Started, MVP | Menu owns le full-screen pause overlay. HUD se masque pendant `PAUSED` via signal GSM, jamais via appel direct au Menu. Pas de shared API. |
| **VFX & Feedback** | Not Started, MVP | VFX (ou Camera) owns le damage flash mort (200 ms fondu rouge — game-concept ligne 98). HUD n'a aucun élément full-screen. |
| **Audio System** | APPROVED r2.1 | Aucun SFX HUD MVP (audio-system.md ligne 169). Tier 2+ : pickup chime à router via `AudioSystem.play_2d` si décidé. |
| **Tutorial / Onboarding** | Not Started, Tier 2+ | Tutorial pourra ajouter un room indicator subtil consommant `LevelSystem.room_entered` Tier 2+, à designer alors. Pas de shared API MVP. |
| **Accessibility** | Not Started, Tier 3 | Text scaling slider, contrast modes, font weight options Tier 3. AC-HUD-29/30 confirme passive resize tolerance MVP. |

### Foundation Dependencies (transitif)

- **InputManager** : zero couplage direct (HUD ne consomme jamais Input). Lint cover-all `.claude/rules/input-singleton-main-thread-only.md` couvre HUD par défaut.
- **AudioServer / AudioStreamPlayer** : zero couplage direct (Rule 15). Audio System APPROVED r2.1 mais HUD ne route aucun SFX MVP.

### Bidirectional consistency check

| Dépendance amont | Cite HUD ? | Section |
|---|---|---|
| Credit Economy r1 | ✅ | Cross-system contracts table (HUD downstream `credits_changed`) |
| Game State Manager r1 | ✅ | §Interactions table HUDSystem In + §UI Requirements |
| Player Combat r6 | ✅ | §Interactions table HUD aval (cooldown_ratio Tier 2+) |
| Level System r3 | ✅ | §Interactions table room_entered HUD consumer |
| Audio System r2.1 | ✅ | §Cross-Refs HUD peer no SFX MVP |

Toutes les dépendances amont citent HUD. Bidirectional check ✅.

### ADR References

- **ADR-0007 D-9** (Game State Manager) — Pattern pull boot. Le HUD lit `GSM.get_current_state()` dans son `_ready()` plutôt que d'attendre un signal `game_booted` (qui n'existe pas par design, GSM Rule 12).
- **ADR-0007 D-10** (Game State Manager) — API canonique `state_changed(new_state)`. Signal SYNC côté GSM, CONNECT_DEFERRED côté HUD (consumer lourd).
- **ADR-0001** (Physics rate 60 Hz) — Le handler `_on_credits_changed` SYNC s'exécute dans le `_physics_process` tick de Credit Economy. Pillar 1 FLOW garde-fou.
- **ADR-0015 D-1** (Accessibility Interface Layer — autoload `AccessibilityService`) — Single-source-of-truth des préférences accessibility cross-system. Le HUD est listé comme consumer Tier 3 dans D-4 : `HUDController` consomme `AccessibilityService.is_reduce_motion_enabled()` pour désactiver le pulse (OQ-HUD-6). L'interface API est déjà exposée par le service ; l'implémentation HUD est différée Tier 3. Voir `docs/architecture/adr-0015-accessibility-interface-layer.md`.
- Aucun ADR dédié HUD MVP n'est requis — la complexité ne le justifie pas. Tier 2+ ou Accessibility Tier 3 pourra justifier un ADR si UI Toolkit Godot 4.5+ est introduit ou si Accessibility Tier 3 nécessite des contraintes architecturales non absorbables par le code.

## Tuning Knobs

### MVP knobs (5 knobs design-active — r1.1 différenciation source)

| Knob | Default | Safe Range | Affecte | Notes |
|---|---|---|---|---|
| `CREDIT_COUNTER_TWEEN_KILL_MS` (r1.1) | `100` | `[60, 200]` ms | Pulse de scale credit counter sur `source == KILL` (F-HUD-1) | Renommé r1.1 depuis `CREDIT_COUNTER_TWEEN_MS`. < 60 ms : pulse imperceptible (anti-Pillar 2). > 200 ms : distrait (anti-Pillar 1). Marqué provisoire — playtest 1 calibrera. |
| `CREDIT_COUNTER_TWEEN_SECRET_MS` (r1.1) | `150` | `[120, 250]` ms | Pulse de scale credit counter sur `source == SECRET` (F-HUD-1) | Nouveau r1.1 amendement NB-CRD-6 Option A. **Invariant** : `CREDIT_COUNTER_TWEEN_SECRET_MS > CREDIT_COUNTER_TWEEN_KILL_MS` (différenciation perceptive Pillar 4 viscéralité). Cohérent Audio Rule 17 (clac aigu signature distincte +5 semitones). |
| `PULSE_SCALE_MAGNITUDE` | `1.05` | `[1.02, 1.10]` | Magnitude du pic de scale (F-HUD-1) | < 1.02 : pulse invisible. > 1.10 : attire l'œil hors zone centrale (anti-Pillar 1). Identique KILL/SECRET MVP. |
| `HUD_MARGIN_RIGHT_PX` | `24` | `[16, 48]` px | Position du counter (F-HUD-2) | Distance du bord droit. < 16 : risque de clipping sur certains aspects ratios. > 48 : counter empiète zone centrale. |
| `HUD_MARGIN_TOP_PX` | `20` | `[16, 48]` px | Position du counter (F-HUD-2) | Distance du bord haut. Mêmes contraintes que ci-dessus. |

### Layer / Architecture knobs (2 knobs structurels — modifier avec ADR)

| Knob | Default | Safe Range | Affecte | Notes |
|---|---|---|---|---|
| `HUD_CANVAS_LAYER` | `50` | `[10, 99]` | CanvasLayer.layer du HUD | **Doit rester < 100** (GSM owns `100` pour fade overlay et focus pause). Modifier = ADR amendement requis. AC-HUD-25/26. |
| `HUD_AUTOLOAD_ORDER_INDEX` | `>= 4` | dynamique | Ordre d'autoload dans `project.godot` | **Doit être APRÈS** `InputManager`, `GameStateManager`, `CreditEconomy`. Pas de slider — c'est une contrainte build, validée au boot par `assert(GameStateManager != null and CreditEconomy != null)`. |

### Visibility knobs (2 knobs débats résolus MVP, latents Tier 2+)

| Knob | Default | Safe Range | Affecte | Notes |
|---|---|---|---|---|
| `HUD_VISIBILITY_DURING_PAUSED` | `false` | `{true, false}` | Counter visible pendant `PAUSED` | MVP `false` (Menu owns full-screen overlay — counter redondant et chevauche le menu). Tier 2+ pourrait passer `true` si pause overlay devient semi-transparent (style Ghostrunner). Décision Visual/Art à r2 (cf. OQ-HUD-3). |
| `HUD_VISIBILITY_DURING_RESPAWNING` | `true` | `{true, false}` | Counter visible pendant `RESPAWNING` (50 ms) | MVP `true` (Pillar 3 — pas de freeze, transition invisible). `false` créerait un flicker visible lors du respawn (anti-Pillar 3). Ne pas changer sans amendement Pillar. |

### Color / Visual knobs (3 knobs latents — activable Tier 2+)

| Knob | Default | Safe Range | Affecte | Notes |
|---|---|---|---|---|
| `HUD_COLOR_BASE` | `#E8E8F0` | tout hex valide | Couleur de base du Label | Blanc froid Chrome Zen (art-director). Pas de full `#FFFFFF`. Pas de couleur warm (Pillar visual). |
| `HUD_SECRET_FLASH_ENABLED` | `false` | `{true, false}` | Flash cyan sur `SourceKind.SECRET` | MVP `false` — décision Visual r2 (OQ-HUD-1). Si activé Tier 2+, déclenche F-HUD-3. |
| `HUD_SECRET_FLASH_COLOR` | `#00D4FF` | tout hex valide | Couleur du flash secret si activé | Cyan néon = mécanique secret (game-concept). Si HUD_SECRET_FLASH_ENABLED = false, knob ignoré. |

### Future Tier 2+/Tier 3 knobs (non actifs MVP, listés pour roadmap)

| Knob | Tier | Affecte |
|---|---|---|
| `HUD_ROOM_INDICATOR_ENABLED` | Tier 2+ | Activation d'un indicateur de progression de salle (consume `LevelSystem.room_entered`). MVP : `false`. Décision après playtest 1 (OQ-HUD-2). |
| `HUD_COOLDOWN_INDICATOR_ENABLED` | Tier 2+ | Activation d'un indicateur de cooldown katana (consume `CombatSystem.cooldown_ratio`). MVP : `false`. Décision après playtest 1. |
| `HUD_TEXT_SCALE_FACTOR` | Tier 3 (Accessibility) | Multiplicateur de taille de texte UI (HUD + futurs Menu, Shop, Tutorial). |
| `HUD_HIGH_CONTRAST_MODE` | Tier 3 (Accessibility) | Mode contraste élevé : background opaque, font weight bold, palette adaptée. |
| `HUD_FONT_FAMILY` | Tier 3 | Choix de font (default monospace JetBrainsMono ou alt sans-serif si Accessibility). |

### Knobs interaction matrix

- `CREDIT_COUNTER_TWEEN_MS` × `PULSE_SCALE_MAGNITUDE` : si tween < 80 ms ET magnitude > 1.08 → effet "snap brutal" anti-Pillar 1. Combinaison à éviter en playtest.
- `HUD_VISIBILITY_DURING_PAUSED` × `HUD_VISIBILITY_DURING_RESPAWNING` : changer les deux simultanément invalide l'AC-HUD-14/15. Tester en isolation seulement.
- `HUD_SECRET_FLASH_ENABLED` × `HUD_COLOR_BASE` : si base = cyan (illegal), le flash n'aura aucun delta visuel. Garde-fou : `HUD_COLOR_BASE` doit toujours être `Color.distance_to(Color("#00D4FF")) > 0.3`.

### Source de tuning

- Toutes les valeurs MVP par défaut sont **provisoires — playtest** sauf indication contraire. Calibration post-playtest 1.
- `HUD_CANVAS_LAYER` est un knob structurel : modification = ADR requis (impacte rendering order avec GSM).
- `HUD_AUTOLOAD_ORDER_INDEX` est une contrainte projet, pas un slider runtime.

## Visual/Audio Requirements

### Visual

**Counter crédits — direction Chrome Zen**

La règle centrale — *"Le vide rend la lame visible"* — implique que tout pixel occupé par le HUD est un pixel volé à la lecture de la scène. Le counter MVP est un **élément typographique seul**, ancré en coin supérieur droit à `(viewport_width − HUD_MARGIN_RIGHT_PX, HUD_MARGIN_TOP_PX)` depuis le bord (defaults 24 et 20 px). Justification : le quadrant supérieur droit est hors du chemin de regard naturel en FPS (mouvement centré sur crosshair, wall-run et sauts lus en zone basse-centrale). Il reste accessible en vision périphérique sans jamais rivaliser avec la zone d'action. Top-left est réservé pour un futur room indicator Tier 2+ ; center-top violerait directement Pillar 1 (toute animation HUD dans l'axe de tir perturbe le flow).

**Table de tokens visuels**

| Token | Valeur | Justification |
|---|---|---|
| **Font family** | Monospace — style "terminal corporate" (e.g. JetBrains Mono, ou Godot built-in `DynamicFont` sur fichier TTF monospace libre) | Chrome Zen = géométrie froide, machine. Monospace évoque terminal Arasaka sans nostalgie LCD 80s. Pas de serif, pas de handwriting. |
| **Font size** | `18 px` à 1080p / `24 px` à 1440p (scaled via `get_viewport().size` ratio) | Minimum lisible au-delà de 60 cm écran. Sous 16 px le counter passe invisible en mouvement. |
| **Couleur base** | `#E8E8F0` — blanc froid légèrement bleuté | Blanc chaud (`#FFFAF0`) est réservé aux sujets skin/sang (Pillar 3 règle warm). Froid = path Chrome Zen. Pas de full `#FFFFFF` qui flashe en surbrillance. |
| **Couleur flash SECRET (latent)** | `#00D4FF` (cyan néon) pendant `180 ms` | Cyan = accent mécanique "secret/interactif" (game-concept ligne 138). Activable via knob `HUD_SECRET_FLASH_ENABLED` Tier 2+ après playtest. Voir OQ-HUD-1. |
| **Couleur flash SPEND_SHOP** | Pas de flash MVP | `SPEND_SHOP` intervient hors gameplay direct (écran shop). Aucune animation HUD sur ce source au MVP. |
| **Background** | Aucun — texte pur sur scène | Un fond semi-opaque contredit "le vide rend la lame visible". Le contraste est assuré par le choix de blanc froid sur environnements majoritairement sombres Chrome Zen. |
| **Iconographie** | `₵` devant le chiffre, même font, même taille, opacity `60 %` | Sigle = rappel contextuel discret, pas affordance. L'atténuation à 60 % fait reculer l'icône derrière le nombre (hiérarchie de lecture : chiffre d'abord). Rejeter "CR" — deux lettres capital = poids visuel excessif. |
| **Feedback d'incrément — option principale** | Pulse de scale : `1.0 → 1.05 → 1.0` sur `100 ms`, easing `Tween.EASE_IN_OUT TRANS_SINE` | Minimal, non-intrusif, communicatif. Ne déplace pas le counter (pas de fly-up text), ne pollue pas la zone centrale. Implémentable en 3 lignes de Tween GDScript. |
| **Feedback d'incrément — option alternative latente** | Hard set + flash opacity : `opacity 100 % → 60 %` sur `120 ms` | Plus sobre encore. Privilégié si playtest révèle que le scale pulse attire l'oeil de manière gênante sur les multi-kills rapides (3 gains en < 200 ms). Activable r2 en swap option principale. |
| **Easing** | `Tween.EASE_IN_OUT`, `Tween.TRANS_SINE` | Cohérent avec la géométrie molle Chrome Zen — pas de rebond, pas de spring, pas d'élastique. |

**Références d'inspiration** : *Ghostrunner* (counter crédits top-right sobre, pas de glow) en premier, *Mirror's Edge* (blanc sur vide, lisibilité mouvement rapide) en deuxième. *Cyberpunk 2077* et *Mr. Robot* terminal aesthetic sont des directions trop chargées pour le MVP — à envisager uniquement pour les écrans de shop Tier 2+.

---

### Anti-patterns visuels (interdits dans toute implémentation HUD MVP)

- **Skeuomorphisme LCD** : pas de police digital-7, pas de chiffres à segments, pas de texture de fond façon tableau de bord. Le counter n'est pas une jauge physique — c'est du texte.
- **Halos et glow** : pas de `emission_energy_multiplier > 0` sur le label HUD, pas d'ombrage lumineux autour des chiffres. Le glow dilate visuellement l'élément et consomme le vide.
- **Ombres portées multiples** : zéro `shadow_color` sur `Label` Godot. Au plus une ombre d'un pixel offset si le contraste sur fond clair est insuffisant — jamais deux ombres superposées.
- **Couleurs warm** (orange, jaune, rouge) : réservées au sang. Un gain de crédits n'est jamais warm — le sang est la seule récompense émotionnelle warm du jeu.
- **Animations qui propagent dans la zone centrale** : tout tween qui déplace le counter (fly-up, slide, bounce) hors de son coin d'ancrage est interdit. L'animation ne quitte jamais le bounding-box du counter.
- **Floating "+1" text** : la valeur affichée est l'unique vecteur d'information. Pas de pop-up additionnel, pas de combo counter, pas de "+50 CREDITS!" qui apparaît temporairement. Le pulse de scale + l'update du chiffre suffit.
- **Death screen ou stats summary** : violation Pillar 3 SECONDE CHANCE. Le HUD ne contient AUCUN noeud de type "death panel", "respawn countdown", "game over". AC-HUD-31.

---

### Audio

**Aucun SFX HUD au MVP**. Le bus `UI` existe dans l'Audio System APPROVED r2.1 mais aucun trigger HUD n'y est branché — le compteur de crédits est muet. Cohérent avec audio-system.md ligne 169 ("HUD update (credit count, etc.) ne déclenche pas de SFX au MVP — Tier 2+ pour audio feedback HUD"). Un pickup chime distinct pour `source=SECRET` est prévu Tier 2+ (Audio GDD OQ-CRD-8 + Credit Economy OQ-CRD-8), à designer lors de `/design-system secret-system` ou amendement Audio.

---

### Asset Spec

`/asset-spec system:hud-system` est **à différer Tier 2+**. Le HUD MVP est purement typographique — un `Label` Godot avec une `DynamicFont` TrueType monospace libre. Aucun mesh, aucune texture, aucune icône-sprite à produire. La seule décision d'asset est le choix du fichier `.ttf` monospace (résolu lors du `/art-bible` sprint ; recommendation : JetBrains Mono ou Inter Mono — open-source, support Unicode incluant `₵`). Quand le HUD s'étendra (room indicator, combo counter, cooldown icon Tier 2+), une spec asset deviendra pertinente — elle sera déclenchée par `/asset-spec system:hud-system` à ce moment.

> **📌 Asset Spec — DIFFÉRÉ Tier 2+** : Le HUD MVP n'a aucun asset à produire. Skip `/asset-spec system:hud-system` au sprint MVP.

## UI Requirements

> **📌 UX Flag — HUD System** : Cette section figeait les contrats GDD. Avant les epics, run `/ux-design hud.md` pour produire la spec UX écran complète (mockups, états, transitions, comportements interactifs). Les stories d'implémentation citeront `design/ux/hud.md`, pas le présent GDD directement.

### Layout MVP

| Element | Position | Anchor Godot | Visibilité |
|---|---|---|---|
| `CreditCounterLabel` | Top-right | `Control.LayoutPreset.PRESET_TOP_RIGHT`, `offset_right = -24px`, `offset_top = 20px` | Visible en `PLAYING` + `RESPAWNING`. Hidden ailleurs. |

**Anchoring strategy** : utiliser `LayoutPreset.PRESET_TOP_RIGHT` natif Godot 4.6 — resize fenêtre = anchoring automatique sans code. AC-HUD-29.

### Information hierarchy

Le HUD MVP affiche **un seul élément** : le total des crédits. Aucun écran de stats, aucun panel d'info, aucun overlay de progression de salle, aucun indicateur de cooldown ou d'inventaire.

### Interaction model

Le HUD est **purement passif** : aucun input keyboard/mouse/gamepad n'est consommé par le HUD au MVP. L'utilisateur ne peut pas cliquer dessus, ne peut pas le dépasser, ne peut pas le repositionner runtime (Tier 3 Accessibility seulement).

### Responsive behavior

| Resolution | Counter font size | Margin behavior |
|---|---|---|
| 1080p (`1920×1080`) | 18 px | `(24, 20)` px |
| 1440p (`2560×1440`) | 24 px | `(32, 26)` px (scaled proportionnel) |
| 4K (`3840×2160`) | 36 px | `(48, 40)` px (scaled proportionnel) |
| Ultrawide (`3440×1440`) | 24 px | `(40, 26)` px (margin droite augmentée pour rester en zone visible) |

**Scaling formula** : `font_size = base_18px × (viewport_height / 1080)` arrondi entier proche, capped à `[14, 36]` px.

### Visibility state machine (synthèse)

| GSM State | HUD visible | Tween d'increment in-flight |
|---|---|---|
| `MENU` | `false` | killed |
| `PLAYING` | `true` | continues |
| `PAUSED` | `false` | killed (Rule 10) |
| `RESPAWNING` | `true` | continues (Rule 9) |
| `BOSS_DEFEATED` | `false` | killed |

### Accessibility considerations (Tier 3 latents)

> **ADR-0015 D-1 tier coverage** — Les features ci-dessous sont classifiées selon le modèle de tiers défini dans `docs/architecture/adr-0015-accessibility-interface-layer.md` D-1. Le HUD est déclaré consumer Tier 3 dans ADR-0015 D-4 via `AccessibilityService.is_reduce_motion_enabled()` (OQ-HUD-6). Les Tier 2+ et Tier 3 sont hors scope Sprint 1 (Polish P3).

| Concern | Tier (ADR-0015 D-1) | MVP behavior | Tier plan |
|---|---|---|---|
| Text scaling | Tier 3 | Passive (resize-only) | Slider 80%–200% sur `HUD_TEXT_SCALE_FACTOR` |
| High contrast mode | Tier 3 | Aucun | Background opaque + font weight bold + palette adaptée |
| Color-blind support | Tier 3 | Aucun (counter monochrome MVP — pas de couleur sémantique sauf flash secret latent) | Si flash secret activé Tier 2+, prévoir variante "icône + flash" pour deutéranopie |
| Screen reader | Tier 3 | Aucun (Godot 4.5+ AccessKit support, mais MVP zero) | `Label.accessible_text` exposera la valeur du counter pour TTS |
| Motion sensitivity (disable pulse) | Tier 3 | Pulse 100ms = sub-seuil épileptique | `AccessibilityService.is_reduce_motion_enabled()` → `HUD_DISABLE_PULSE` (OQ-HUD-6 — API ready ADR-0015 D-4) |

### Frame integration (Godot scene tree)

```
HUDSystem (autoload, Node)
└── HUDCanvasLayer (CanvasLayer, layer = 50)
    └── CreditCounterContainer (Control, anchor TOP_RIGHT)
        ├── CreditIcon (Label, "₵", opacity 0.6)
        └── CreditCounterLabel (Label, "0")
```

Le `Container` parent permet l'animation de scale unifiée (icon + label en bloc) lors du pulse F-HUD-1.

### Frame budget

| Tick | Allocation HUD |
|---|---|
| `_process` | Tween rendering (Godot internal) ≤ 0.2 ms |
| `_physics_process` | 0 ms (HUD ne tick rien en physics) |
| Handler `_on_credits_changed` SYNC | ≤ 0.5 ms (AC-HUD-27) |
| Handler `_on_state_changed` DEFERRED | ≤ 0.3 ms (visibility toggle minimal) |

**Total HUD budget** : ≤ 0.5 ms par frame en pic d'activité (kill + state change même tick — ne se produit qu'au mutual kill, EC-HUD-13).

## Cross-References

| Concept | Référence interne | Référence externe (autres GDDs / docs) |
|---|---|---|
| `credits_changed` signal SYNC | Rule 3 + Interactions table | `design/gdd/credit-economy-system.md` Rule 8 + §Interactions table HUD downstream |
| `state_changed` signal CONNECT_DEFERRED | Rule 4 + EC-HUD-04 | `design/gdd/game-state-manager.md` Rule 4 (consumers lourds DEFERRED) + ligne 113 + ligne 419 |
| Pattern pull boot | Rule 2 | `docs/architecture/adr-0007-game-state-manager.md` D-9 + GSM Rule 12 |
| Enum `State` 5 values | States and Transitions table | `design/gdd/game-state-manager.md` enum State + ADR-0007 D-2 |
| Enum `SourceKind` 4 values | Rule 6/7 + EC-HUD-12 | `design/gdd/credit-economy-system.md` Rule 13 enum SourceKind |
| `MAX_KILLS_PER_SWING = 3` | EC-HUD-05 + AC-HUD-19/20 | `design/registry/entities.yaml` constant + `design/gdd/player-combat-system.md` Rule 10 + `design/gdd/credit-economy-system.md` F-CRD-1 |
| `RESPAWN_DELAY = 0.05 s` | Rule 9 + EC-HUD-07 | `design/registry/entities.yaml` constant + `design/gdd/player-movement-system.md` Tuning Knobs r3 + GSM Formula 2 |
| `cooldown_ratio` property Combat | Soft dep + Tier 2+ knob | `design/gdd/player-combat-system.md` ligne 275 (HUD soft dep, MVP no display) |
| `room_entered` signal Level | Soft dep + Tier 2+ knob | `design/gdd/level-system.md` ligne 229 (HUD signal consumer Tier 2+) |
| Bus `UI` Audio System | Visual/Audio §Audio | `design/gdd/audio-system.md` ligne 169 (HUD no SFX MVP) + ADR-0009 D-1 bus naming |
| Damage flash mort (200ms fondu rouge) | EC-HUD-13 | `design/gdd/game-concept.md` ligne 98 (Camera/VFX owns, pas HUD) |
| `CanvasLayer.layer = 50` HUD vs `100` GSM | Rule 11 + AC-HUD-25/26 | `design/gdd/game-state-manager.md` ligne 395 (GSM layer 100 ownership) |
| Pillar 1 FLOW garde-fou | Rule 3 + Visual anti-patterns | `design/gdd/game-concept.md` ligne 152 + Rule 13 zero-alloc hot path |
| Pillar 2 PROGRESSION SE VOIT | Player Fantasy + F-HUD-1 | `design/gdd/game-concept.md` ligne 157 |
| Pillar 3 SECONDE CHANCE | Rule 9 + EC-HUD-07 + AC-HUD-21/22 | `design/gdd/game-concept.md` ligne 162 |
| Pillar 4 SECRETS = MOUVEMENT | Anti-patterns "no minimap" + AC-HUD-32 | `design/gdd/game-concept.md` ligne 167 |
| Anti-pillar "L'UI est invisible" | Player Fantasy moment d'ancrage + AC-HUD-31/32/33 | `design/gdd/game-concept.md` ligne 96 |
| Lint cover-all Input main thread | Rule 14 | `.claude/rules/input-singleton-main-thread-only.md` |
| Lint cover-all no-alloc hot paths | Rule 13 + AC-HUD-28 | `.claude/rules/no-alloc-hot-paths.md` (à étendre au HUD si MVP révèle delta > 64 KB / 60 s) |
| Asset Spec différé Tier 2+ | Visual/Audio §Asset Spec | (Aucun fichier asset MVP) |
| GUT testing framework | AC-HUD-* AUTO tags | `tests/unit/hud/` + `tests/integration/hud/` (à créer Sprint HUD) |

## Acceptance Criteria

> **Format** : `[BLOCKING|ADVISORY] [AUTO|PLAYTEST|MANUAL]` puis GIVEN-WHEN-THEN. Total **35 ACs** — **33 BLOCKING, 2 ADVISORY** ; **33 AUTO (94%), 1 PLAYTEST, 1 MANUAL**.

### Constantes nommées de référence

| Constante | Valeur design | Source |
|---|---|---|
| `CREDIT_COUNTER_TWEEN_MS` | 80–120 ms (default 100) | F-HUD-1 + Tuning Knobs |
| `HUD_LAYER_MAX` | 99 | Rule 11 (GSM owns 100) |
| `RESPAWN_DELAY_S` | 0.05 s | registry constant + Movement r3 + GSM Formula 2 |
| `MAX_KILLS_PER_SWING` | 3 | registry constant + Combat Rule 10 |
| `BASE_SECRET_CREDIT_T1` | 5 | Credit Economy F-CRD-2 |

### A. Boot & Init

- **AC-HUD-01** [BLOCKING][AUTO] **GIVEN** le HUD est instancié comme autoload, **WHEN** `_ready()` s'exécute et `GameStateManager.get_current_state() == State.MENU`, **THEN** le credit counter `Label.visible == false` et aucune erreur loggée.
- **AC-HUD-02** [BLOCKING][AUTO] **GIVEN** le HUD est instancié et `CreditEconomy.get_total()` retourne `N >= 0`, **WHEN** `_ready()` s'exécute, **THEN** le `Label.text == str(N)` avant tout signal `credits_changed` reçu (boot pull, hard set).
- **AC-HUD-03** [BLOCKING][AUTO] **GIVEN** le HUD possède un `CanvasLayer`, **WHEN** le node est prêt, **THEN** `CanvasLayer.layer < HUD_LAYER_MAX` (`< 100`) — assertion sur la propriété directe.
- **AC-HUD-04** [BLOCKING][AUTO] **GIVEN** le HUD est instancié, **WHEN** `_ready()` s'exécute, **THEN** le HUD est connecté au signal `CreditEconomy.credits_changed` ET au signal `GameStateManager.state_changed` (vérifiable via `Signal.get_connections()`), avant tout tick `_physics_process`.

### B. Counter increment (kill / secret)

- **AC-HUD-05** [BLOCKING][AUTO] **GIVEN** State.PLAYING actif et counter affiche `N`, **WHEN** `credits_changed(N+1, +1, SourceKind.KILL)` est émis SYNC, **THEN** le tween de pulse démarre dans le même tick `_physics_process` ; la valeur finale `Label.text` atteint `str(N+1)` dans `≤ CREDIT_COUNTER_TWEEN_MS` (120 ms wall-clock).
- **AC-HUD-06** [BLOCKING][AUTO] **GIVEN** State.PLAYING et counter affiche `N`, **WHEN** `credits_changed(N+5, +5, SourceKind.SECRET)` est émis, **THEN** `Label.text == str(N+5)` instantanément (Rule 5 — hard set du chiffre, pulse de scale parallèle) ; aucune frame intermédiaire avec `Label.text == str(N+1)..str(N+4)`.
- **AC-HUD-07** [BLOCKING][AUTO] **GIVEN** counter affiche `N` et un tween d'incrément en cours (delta > 0), **WHEN** un second `credits_changed(N+2, +1, SourceKind.KILL)` arrive pendant le tween actif, **THEN** le tween précédent est tué (`tween.kill()`) et un nouveau démarre à scale courante (Rule 5) ; valeur finale `Label.text == str(N+2)` sans rester bloquée sur valeur intermédiaire après `2 × CREDIT_COUNTER_TWEEN_MS`.

### C. Counter decrement (try_spend success)

- **AC-HUD-08** [BLOCKING][AUTO] **GIVEN** counter affiche `N` et `try_spend(cost)` réussit (`N >= cost`), **WHEN** `credits_changed(N-cost, -cost, SourceKind.SPEND_SHOP)` est émis SYNC, **THEN** `Label.text` est hard-set à `str(N-cost)` immédiatement (pas de tween descendant) ; aucune animation de roll-up n'est lancée ; `Label.scale == Vector2.ONE`.
- **AC-HUD-09** [BLOCKING][AUTO] **GIVEN** counter affiche `N`, **WHEN** `credits_changed(_, delta, SourceKind.SPEND_SHOP)` reçu avec delta < 0, **THEN** `Label.text` est mis à jour dans le même `_physics_process` tick (frame-synchronous, pas DEFERRED).

### D. Counter rollback (try_spend fail — aucune émission)

- **AC-HUD-10** [BLOCKING][AUTO] **GIVEN** counter affiche `N` et `try_spend(cost)` échoue (`N < cost`), **WHEN** aucun signal `credits_changed` n'est émis (Credit Economy Rule 4 atomicité), **THEN** counter reste à `str(N)` ; aucun tween déclenché ; aucune mutation de `Label.text` observée dans 200 ms suivant l'appel.
- **AC-HUD-11** [BLOCKING][AUTO] **GIVEN** le HUD est connecté à `credits_changed` via spy, **WHEN** un spy capture les connexions sur `credits_changed`, **THEN** le spy ne reçoit aucun appel suite à un `try_spend` échoué — le HUD ne peut pas réagir à un événement non émis (test d'intégration : real CreditEconomy + real HUD).

### E. Visibility par State

- **AC-HUD-12** [BLOCKING][AUTO] **GIVEN** le HUD est initialized, **WHEN** `state_changed(State.MENU)` est reçu, **THEN** `Label.visible == false` dans le même tick de traitement du signal (CONNECT_DEFERRED → idle frame N+1).
- **AC-HUD-13** [BLOCKING][AUTO] **GIVEN** counter hidden (State.MENU), **WHEN** `state_changed(State.PLAYING)` est reçu, **THEN** `Label.visible == true` avant le prochain `_physics_process` tick.
- **AC-HUD-14** [BLOCKING][AUTO] **GIVEN** counter visible (State.PLAYING), **WHEN** `state_changed(State.PAUSED)` reçu, **THEN** `Label.visible == false` ; le pause overlay (Menu System) reste seul élément UI visible de sa couche.
- **AC-HUD-15** [BLOCKING][AUTO] **GIVEN** State.RESPAWNING actif (durée ≤ `RESPAWN_DELAY_S` = 50 ms), **WHEN** `state_changed(State.RESPAWNING)` reçu, **THEN** `Label.visible == true` ; aucun freeze, aucun hide pendant la fenêtre respawn.
- **AC-HUD-16** [BLOCKING][AUTO] **GIVEN** State.PLAYING, **WHEN** `state_changed(State.BOSS_DEFEATED)` reçu, **THEN** `Label.visible == false`.

### F. Pattern pull boot

- **AC-HUD-17** [BLOCKING][AUTO] **GIVEN** processus vient de démarrer (première frame), **WHEN** `HUDSystem._ready()` s'exécute, **THEN** `GameStateManager.get_current_state()` est appelé exactement une fois (spy/mock vérifiable) ET `CreditEconomy.get_total()` est appelé exactement une fois ; le HUD n'attend pas de signal `game_booted` (n'existe pas — GSM Rule 12).
- **AC-HUD-18** [BLOCKING][AUTO] **GIVEN** `CreditEconomy` émet `credits_changed(N, 0, SourceKind.BOOT_HYDRATE)` au démarrage, **WHEN** le HUD reçoit ce signal, **THEN** counter est hard-set à `str(N)` (delta == 0 → pas de tween) ; `Tween.is_running() == false` après traitement.

### G. Multi-kill en un swing

- **AC-HUD-19** [BLOCKING][AUTO] **GIVEN** State.PLAYING et counter affiche `N`, **WHEN** 3 signaux `credits_changed` séquentiels (delta=+1, SourceKind.KILL) arrivent dans le même tick `_physics_process` (simulant `MAX_KILLS_PER_SWING = 3`), **THEN** valeur finale après `≤ 3 × CREDIT_COUNTER_TWEEN_MS` est `str(N+3)` ; valeur intermédiaire jamais > `N+3` ni < `N`.
- **AC-HUD-20** [BLOCKING][AUTO] **GIVEN** 3 signals `credits_changed` séquentiels dans le même tick, **WHEN** chaque signal reçu, **THEN** le HUD ne produit pas 3 tweens superposés causant overshoot — vérifier que `Label.text` ne dépasse jamais `str(N+3)` à aucune frame.

### H. Idempotence respawn

- **AC-HUD-21** [BLOCKING][AUTO] **GIVEN** joueur meurt et `Checkpoint._restore_from_snapshot()` s'exécute, **WHEN** `_restore_from_snapshot` ne réémet pas `credits_changed` (Credit Economy Rule 2 — irréversibilité à la mort), **THEN** counter HUD reste à valeur pré-mort `N` ; aucune variation observée dans 200 ms post-State.RESPAWNING.
- **AC-HUD-22** [BLOCKING][AUTO] **GIVEN** State passe `PLAYING → RESPAWNING → PLAYING`, **WHEN** State.PLAYING restauré, **THEN** counter affiche toujours `str(N)` (valeur pré-mort) — le HUD ne re-pull pas `get_total()` au retour PLAYING (pas de double-hydration).

### I. Source-dependent feedback visuel

- **AC-HUD-23** [ADVISORY][PLAYTEST] **GIVEN** `credits_changed(total, delta, SourceKind.SECRET)` reçu avec delta ≥ `BASE_SECRET_CREDIT_T1` (≥ 5), **WHEN** le tween démarre, **THEN** un observateur humain distingue visuellement ce feedback de SourceKind.KILL — la décision de design (flash cyan vs neutre) doit être documentée Visual section avant impl. ADVISORY jusqu'à OQ-HUD-1 résolue.
- **AC-HUD-24** [BLOCKING][AUTO] **GIVEN** `credits_changed(total, 0, SourceKind.BOOT_HYDRATE)` reçu, **WHEN** HUD traite le signal, **THEN** aucun tween n'est lancé (delta == 0 → hard set uniquement) ; `Tween.is_running() == false` après traitement.

### J. Layer ordering

- **AC-HUD-25** [BLOCKING][AUTO] **GIVEN** HUD dans le scene tree, **WHEN** la propriété est lue, **THEN** `CanvasLayer.layer ≤ HUD_LAYER_MAX` (`< 100`) — assertion GUT directe sans rendu.
- **AC-HUD-26** [BLOCKING][AUTO] **GIVEN** GSM possède son overlay fade sur `CanvasLayer.layer == 100`, **WHEN** les deux CanvasLayers coexistent en State.PLAYING, **THEN** le render order place HUD derrière fade overlay GSM — vérifiable via comparaison de propriété layer.

### K. Performance

- **AC-HUD-27** [BLOCKING][AUTO] **GIVEN** State.PLAYING actif, 60 fps steady, **WHEN** `credits_changed` émis (SourceKind.KILL, delta=+1), **THEN** handler HUD s'exécute en `≤ 0.5 ms` wall-clock (mesuré via `Time.get_ticks_usec()` avant/après handler dans test harness headless) ; budget `_physics_process` total HUD ne dépasse pas 0.5 ms par tick avec tween actif.
- **AC-HUD-28** [BLOCKING][AUTO] **GIVEN** HUD tourne 60 s gameplay simulé (1000 events `credits_changed`), **WHEN** mémoire inspectée via `Performance.get_monitor(Performance.MEMORY_STATIC)`, **THEN** delta mémoire attribué aux handlers HUD `< 64 KB` (pas d'alloc heap par tick — pas de Dictionary literal, String concat, Array.new() en hot path).

### L. Edge cases UI

- **AC-HUD-29** [BLOCKING][AUTO] **GIVEN** jeu démarre en 1080p, **WHEN** résolution changée programmatiquement en 1440p (`DisplayServer.window_set_size`), **THEN** `Label` reste lisible et in-bounds CanvasLayer — pas de text clipping, pas de position out-of-screen (`Label.get_rect()` post-resize).
- **AC-HUD-30** [ADVISORY][MANUAL] **GIVEN** jeu en plein écran, **WHEN** toggle vers fenêtré, **THEN** counter reste positionné selon anchor — observateur humain confirme lisibilité sans dérive de position. *Note* : text scaling Tier 3 hors scope MVP.

### M. Anti-patterns — no-op explicites testables

- **AC-HUD-31** [BLOCKING][AUTO] **GIVEN** HUD fully loaded en State.PLAYING, **WHEN** scene tree inspecté (`get_children` récursif sur HUD node), **THEN** aucun node de type "death screen", "game over panel", "respawn countdown" n'existe dans HUD — absence assertée par type name ou group membership. Garde-fou Pillar 3.
- **AC-HUD-32** [BLOCKING][AUTO] **GIVEN** HUD fully loaded, **WHEN** scene tree inspecté, **THEN** aucun node de type "minimap", "radar", "enemy marker" n'existe dans HUD (anti-Pillar 4 — SECRETS=MOUVEMENT).
- **AC-HUD-33** [BLOCKING][AUTO] **GIVEN** HUD fully loaded, **WHEN** scene tree inspecté, **THEN** aucun node de type "health bar", "shield bar", "ammo counter" n'existe dans HUD (anti-Pillar 1 + anti-pillars game-concept).
- **AC-HUD-34** [BLOCKING][AUTO] **GIVEN** `credits_changed(total, delta, SourceKind.KILL)` reçu, **WHEN** handler HUD s'exécute, **THEN** aucun appel à `AudioServer` ou `AudioStreamPlayer` (zero SFX MVP — audio-system.md ligne 169) — assertion via mock AudioServer ou spy method calls.
- **AC-HUD-35** [BLOCKING][AUTO] **GIVEN** HUD initialized, **WHEN** scene tree inspecté + grep sur `.gd` source HUD, **THEN** HUD ne détient aucune référence directe à `CombatSystem`, `LevelSystem`, `MovementController`, `EnemySystem`, `Player`, `AudioSystem` — seules deps autorisées : `CreditEconomy` + `GameStateManager` (Rule 12 + lint cover-all à étendre).

- **AC-HUD-36** (r1.1 — pulse durée différenciée par source) [BLOCKING][AUTO] **GIVEN** HUD initialisé en `State.PLAYING`, spy injecté sur `Tween.tween_property(Label, "scale", ...)`. **WHEN** deux signaux `credits_changed` séquentiels émis : (1) `credits_changed(N+1, +1, SourceKind.KILL)` puis (2) `credits_changed(N+6, +5, SourceKind.SECRET)` 500 ms plus tard (pas de chevauchement). **THEN** :
    - (a) Le tween du 1er signal (KILL) a `duration ≈ 0.100 s ± 0.005 s` (`CREDIT_COUNTER_TWEEN_KILL_MS / 1000`).
    - (b) Le tween du 2e signal (SECRET) a `duration ≈ 0.150 s ± 0.005 s` (`CREDIT_COUNTER_TWEEN_SECRET_MS / 1000`).
    - (c) **Invariant balance** : `tween_secret.duration > tween_kill.duration` strictement. Pas d'égalité, pas d'inversion. Si invariant violé : FAIL avec message "Pillar 4 différenciation perceptive cassée — secret pulse durée doit dépasser kill pulse durée".
    - (d) Magnitude pic de scale `(1.05, 1.05)` identique pour les deux tweens (différenciation magnitude réservée Tier 2+).
    - (e) **Edge case `tween.kill()` collision** : si un 3e signal `credits_changed(... KILL)` arrive pendant que le tween (b) SECRET est encore en cours, le tween SECRET est `kill()` et un nouveau tween KILL démarre avec `duration ≈ 0.100 s`. La durée du tween courant reflète toujours le `source` du dernier signal reçu.
    Test : `tests/integration/hud/credit_counter_pulse_source_diff_test.gd`. Pillar 4 viscéralité MVP minimum, cohérent Audio Rule 17 (clac aigu pitch +5 semitones bus `SFX`). Cascade NB-CRD-6 Option A creative-director adjudication 2026-04-28.

### Coverage matrix

| Sous-thème | ACs | AUTO | PLAYTEST/MANUAL |
|---|---|---|---|
| A. Boot & Init | 4 | 4 | 0 |
| B. Counter increment | 3 | 3 | 0 |
| C. Counter decrement | 2 | 2 | 0 |
| D. Counter rollback | 2 | 2 | 0 |
| E. Visibility par State | 5 | 5 | 0 |
| F. Pattern pull boot | 2 | 2 | 0 |
| G. Multi-kill swing | 2 | 2 | 0 |
| H. Idempotence respawn | 2 | 2 | 0 |
| I. Source-dependent feedback | 2 | 1 | 1 (ADVISORY) |
| J. Layer ordering | 2 | 2 | 0 |
| K. Performance | 2 | 2 | 0 |
| L. Edge cases UI | 2 | 1 | 1 (ADVISORY MANUAL) |
| M. Anti-patterns | 5 | 5 | 0 |
| **Total** | **35** | **33 (94%)** | **2 (6%)** |

**BLOCKING : 33 — ADVISORY : 2.**

## Open Questions

| ID | Question | Owner | Target resolution | Status |
|---|---|---|---|---|
| **OQ-HUD-1** | `SourceKind.SECRET` doit-il déclencher un flash visuel distinct (cyan néon `#00D4FF` 180 ms — F-HUD-3 latent) ou rester neutre comme un kill ? Décision impacte le knob `HUD_SECRET_FLASH_ENABLED` et l'AC-HUD-23. | art-director + game-designer | `/design-review hud-system` r2 ou playtest 1 | OPEN — MVP `false` par défaut. |
| **OQ-HUD-2** | Faut-il implémenter un room indicator (consume `LevelSystem.room_entered`) au MVP ou différer Tier 2+ ? L'architecture verticale du Level (Pillar 4) est censée orienter sans HUD. Risk : implémenter pour le retirer après playtest 1. | game-designer + level-designer | Playtest session 1 (post-MVP build) | OPEN — MVP différé Tier 2+ recommandé. |
| **OQ-HUD-3** | Doit-on laisser le counter visible à 50% opacité pendant `PAUSED` si le pause overlay devient semi-transparent (style Ghostrunner) ? Décision art-bible — Menu System + visual identity dependency. | art-director + ux-designer | `/design-system menu-system` ou amendement Menu r1 | OPEN — MVP hidden (full overlay supposé). |
| **OQ-HUD-4** | Ordre d'autoload `project.godot` : doit-on documenter formellement la contrainte `InputManager → GSM → CreditEconomy → HUD` dans un ADR ou un Tuning Knob ? Si l'ordre est cassé, AC-HUD-04/17/18 fail au boot. | gameplay-programmer + technical-director | Sprint 1 implémentation (avant 1ère story HUD) | OPEN — MVP convention par contrat (assert dans `_ready`). |
| **OQ-HUD-5** | Le tween de pulse F-HUD-1 doit-il être `set_ignore_time_scale(true)` (wall-clock — pattern Enemy r2) pour rester cohérent quand un kill déclenche slow-mo Combat (`SLOW_MO_SCALE = 0.3`) au même tick ? Sinon le pulse durerait `100 / 0.3 = 333 ms` perçus, rivalisant avec le slow-mo visuel. | game-designer + technical-artist | `/design-review hud-system` r2 | OPEN — recommandation MVP `true` (wall-clock). |
| **OQ-HUD-6** | La pulse de scale (Rule 5 + F-HUD-1) doit-elle pouvoir être désactivée via un knob `HUD_DISABLE_PULSE` Tier 3 (motion sensitivity accessibility) ou prévoir une animation alternative non-motion (flash opacity uniquement) ? | accessibility-specialist | Tier 3 Accessibility pass | OPEN — Tier 3, latent. |
| **OQ-HUD-7** | Faut-il une UI Toolkit Godot 4.5+ migration (vs Control nodes legacy) au MVP ou Tier 2+ ? UI Toolkit offre data binding mais demande apprentissage + impact perf. | ui-programmer + technical-director | Sprint 1 ou ADR HUD architecture | OPEN — MVP Control nodes legacy (simplicité). |
| **OQ-HUD-8** | Pickup chime audio Tier 2+ (`source = SECRET` → `Audio.play_2d("ui_secret_chime.wav")`) : décision attendue lors `/design-system secret-system` ou amendement Audio. Cohérence Pillar 4 — un chime distinct récompense le mouvement. | audio-director + game-designer | `/design-system secret-system` Sprint A | OPEN — Tier 2+. |
| **OQ-HUD-9** | Mode debug F3 (Combat `debug_hits_last_swing`) doit-il être consommé par HUD en developer build only ou rester totalement absent du HUD (debug = developer overlay séparé) ? | gameplay-programmer | Sprint debug tooling | OPEN — MVP absent du HUD (Combat fournit la property en lecture pour developer overlay séparé). |
| **OQ-HUD-10** | Ratio kill-to-secret feedback : doit-on prévoir un "burst" visuel cumulatif quand le joueur enchaîne 3 kills consécutifs (combo non explicite mais visuel implicite) ? Risk anti-Pillar 1 si trop chargé. | game-designer + creative-director | Playtest session 2 (Vertical Slice) | OPEN — Tier 2+, latent. |

> **Note** : les 4 OQ critiques pour le MVP (OQ-HUD-1, OQ-HUD-2, OQ-HUD-4, OQ-HUD-5) doivent être tranchées avant `/create-epics hud-system`. Les autres sont latentes (Tier 2+ / Tier 3).
