# Camera System

> **Status**: Revised post design-review r2 — pending fresh re-review
> **Author**: Martin + design-system skill (auto mode, solo review) — revisé r1 après `/design-review` (7 specialists + creative-director, 2026-04-21) ; revisé r2 après `/design-review` lean r2 (2026-04-21)
> **Last Updated**: 2026-04-21 (r2 revision — 5 BLOCKING résolus : B-1 dérivation `wall_side` Camera-owned, B-2 patches Movement GDD tilt 12°→ref Camera + nœud `CameraEffects`, B-3 nomenclature nœuds dans Formulas, B-4 AC classification+atomisation+evidence, B-5 state table Respawning pitch-préservé. + R-1 `is_mouse_captured` gate, R-2 Rule `reduce_motion`, R-3 ref ADR-0005, R-4 signal `wall_jumped` canon, R-5 AC Perf p50/p99, R-6 `_exit_tree` cleanup.)
> **Implements Pillar**: Pillar 1 (FLOW AVANT TOUT) — primaire, la caméra ne doit jamais rompre le flow ; Pillar 2 (LA PROGRESSION SE VOIT) — indirect, la caméra est le médium par lequel le joueur *voit* son mouvement ; Pillar 3 (UNE SECONDE CHANCE) — via fade rouge + reset rapide au respawn.

## Overview

Le Camera System est la fenêtre perceptive du joueur sur le monde. Il orchestre trois rôles couplés : (1) appliquer le pitch vertical à une `Camera3D` child du Player node, en consommant le signal `mouse_motion` de l'Input System et la sensibilité/inversion Y configurées par le joueur ; (2) rendre visibles les états de mouvement du Player via des transforms visuels obligatoires — tilt latéral pendant le wall-run, FOV pulse pendant le dash, kick léger au wall-jump ; (3) servir de source de direction pour les systèmes aval (le Player Combat lit le forward caméra pour orienter la hitbox katana, le HUD ancre son crosshair à la caméra). Le yaw horizontal est *délégué* au Player node (`rotation.y`) et non à la caméra elle-même — le Player pivote sous la caméra ; la caméra ne fait que pitcher. Le système est **purement réactif** : il ne prend aucune décision gameplay, il ne filtre aucun input, et il n'a aucun état propre au-delà de ses transforms visuels (tilt courant, FOV courant, shake offset courant). La latence mouse→rotation doit rester ≤ 1 frame d'affichage (16 ms cible, 8 ms idéal), en cohérence avec le budget Pillar 1.

> **Quick reference** — Layer: `Core` · Priority: `MVP` · Key deps: `Input System (amont, mouse_motion + sensitivity), Player Movement System (amont, state + velocity)` · Consumed by: `Player Combat (forward vector pour katana), VFX (shake triggers), HUD (crosshair anchor), Menu (settings readout)`

## Player Fantasy

**Cible émotionnelle : la caméra est invisible sauf quand elle doit parler.**

Le joueur ne "joue" pas la caméra — il *est* derrière elle. Tant que tout fonctionne, il oublie son existence : la souris bouge, le monde bouge, fin. La caméra ne devient palpable qu'aux trois moments où elle *doit* parler au corps du joueur :

1. **Quand le joueur longe un mur**, la caméra bascule vers lui comme si son poids incliné l'attirait. C'est ce qui transforme le wall-run d'une mécanique invisible (jambes qui collent à un mur en vue FPS) en sensation kinesthésique. Référence nommée : **Mirror's Edge** — le tilt latéral est la signature qui a fait fonctionner le wall-run en vue FPS.

2. **Quand le joueur dash**, le FOV s'élargit brièvement. Le monde se "tire" d'un coup vers les côtés, puis se remet en place. Référence : **Titanfall 2**, **Ghostrunner** — le FOV kick est la différence entre un dash qui "feel like magic" et un dash qui "feel like a teleport bug".

3. **Quand le joueur meurt**, l'écran bascule rouge sombre en un frame. Pas de ragdoll, pas de cinématique, pas de zoom-out. La caméra reste figée pendant 50 ms (`RESPAWN_DELAY` owned par Movement — valeur r3 Martin 2026-04-21), puis respawn au checkpoint avec un flash blanc inversé. Le joueur ne voit pas sa mort ; il la *subit*, puis il est rendu à la vie.

**Anti-référence** : les jeux où la caméra "s'anime" en permanence (head-bob agressif, breathing, weapon sway permanent). CHROME://ASCENT n'en a pas — ça viole Pillar 1 sans rien donner. **Anti-référence bis** : les jeux où la caméra tourne avec un smoothing qui ajoute 50 ms à chaque rotation. Ici, la rotation normale est *raw* — le delta souris est appliqué tel quel (après multiplication par `mouse_sensitivity`), sans interpolation. Seules les trois interruptions narratives (tilt, FOV pulse, shake) ont des courbes d'interpolation contrôlées.

**Ce que le joueur ne doit jamais ressentir** : "la caméra lag", "ça tourne bizarre quand je sprinte", "j'ai mal au crâne après 20 minutes", "je sais pas si je wall-run ou je tombe", "le dash ne se sent pas". Chacune de ces phrases est un bug dans ce système.

> *Note* : Player Fantasy indirecte. Le joueur ne dit pas « j'adore la caméra » ; il dit « le mouvement est parfait » — et c'est la caméra qui l'a rendu lisible.

## Detailed Design

### Core Rules

1. **Structure scene-tree** (source de vérité : ADR-0002, hiérarchie à trois étages). La caméra vit dans une chaîne `CharacterBody3D (Player) → CameraArm: Node3D → CameraEffects: Node3D → Camera3D → AudioListener3D`. Ownership des mutations :
   - **Yaw** (rotation horizontale) → `player.rotation.y` (jamais sur la caméra).
   - **Pitch** (rotation verticale) → `camera_arm.rotation.x` exclusivement, clampé `[-PITCH_LIMIT, +PITCH_LIMIT]`.
   - **Tilt wall-run** (roll Z) → `camera_effects.rotation.z` exclusivement. Isolé du pitch et du head-bob pour éviter tout conflit de Tween/lerp sur la même propriété.
   - **FOV** → `camera3d.fov`.
   - **Shake additif** → `camera3d.rotation` (assignation, pas `+=`, cf. Rule 8).
   - **Head-bob** (Tier 2 OFF au MVP) → `camera_arm.position.y` si ré-introduit, jamais sur rotation.
   Cette séparation garantit que les systèmes qui lisent le forward du Player (hitbox de collision, spawn) ne sont pas affectés par le pitch, et que trois effets visuels simultanés (pitch + tilt + shake) n'entrent jamais en collision sur le même noeud.

2. **Rotation yaw.** À chaque signal `mouse_motion(delta)` émis par l'InputManager, le Camera System calcule `yaw_delta = -delta.x * InputManager.mouse_sensitivity`, **clampe la magnitude** à `±MAX_ROT_PER_FRAME` (PI rad ≈ 180° — protège flick extrême × sensitivity max), et l'applique via `player.rotation.y += yaw_delta`. Aucune interpolation, aucun smoothing. Raison : feel raw, cf. Player Fantasy. Movement lit `player.rotation.y` en *lecture seule* ; n'écrit jamais cette propriété (ownership yaw = Camera).

3. **Rotation pitch.** `pitch_delta = -delta.y * InputManager.mouse_sensitivity * (-1 si mouse_y_inverted else 1)`, **clampé** à `±MAX_ROT_PER_FRAME`. Appliqué à `camera_arm.rotation.x += pitch_delta`, puis clamp `camera_arm.rotation.x = clamp(camera_arm.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)` avec `PITCH_LIMIT = PI/2 - 0.05` (évite le gimbal lock visuel).

4. **Tilt wall-run — OBLIGATOIRE.** Camera **dérive** `wall_side ∈ {-1 (gauche), 0 (aucun), +1 (droite)}` depuis `player.wall_normal` (Movement-owned, `Vector3.ZERO` quand pas WallRunning — cf. Movement GDD Published API) — **aucune propriété `player.wall_side` n'est exposée par Movement**. Dérivation canonique :
   ```gdscript
   # wall_side = +1 quand le mur est à droite du Player, -1 à gauche, 0 sinon.
   # wall_normal pointe du mur vers le Player, donc -wall_normal pointe vers le mur.
   var wall_side: int = sign((-player.wall_normal).dot(player.global_transform.basis.x))
   # sign(0) == 0, donc pas WallRunning (wall_normal == Vector3.ZERO) → wall_side == 0 ✓
   ```
   Sur réception du signal Movement `wall_run_entered(wall_normal: Vector3)` (ADR-0005 D-2), Camera cache `_is_wall_running = true` + `_wall_side_cached = sign((-wall_normal).dot(camera_arm.global_transform.basis.x))` ; sur `wall_run_exited`, reset à `false` / `0` (ADR-0002 Amendment A-1). Tant que `_is_wall_running == true`, le roll (rotation autour de l'axe Z local) cible `WALL_RUN_TILT_ANGLE * _wall_side_cached`. Sinon, target = 0. L'interpolation utilise `camera_effects.rotation.z = lerp(camera_effects.rotation.z, target_roll, TILT_LERP_SPEED * delta)` — appliqué sur **CameraEffects**, pas sur Camera3D ni CameraArm (cf. Rule 1 + ADR-0002). **Cette règle est non-négociable** : sans elle, le wall-run est indistinguable d'un saut pour le joueur en vue FPS (learning prototype #7). Le tilt doit être visible à 95% de sa valeur cible dans ≤ 200 ms après l'entrée en wall-run.

5. **Résolution conflit tilt.** Le prototype a validé `WALL_RUN_TILT_ANGLE = 0.35 rad (≈ 20°)` au playtest (« bon » — Martin, 2026-04-21). Le Player Movement GDD mentionnait 12° comme valeur indicative — elle était *provisoire*, rédigée avant le playtest. **Le Camera System est désormais la source de vérité** : `WALL_RUN_TILT_ANGLE = 0.35 rad`. Le Player Movement GDD sera mis à jour via `/consistency-check` pour refléter cette ownership.

6. **FOV pulse dash.** Camera connecte les signals Movement `dash_started()` / `dash_ended()` (ADR-0005 D-2) et cache `_is_dashing: bool` localement (ADR-0002 Amendment A-1). Quand `_is_dashing == true`, la caméra cible `BASE_FOV + DASH_FOV_KICK` (90° + 10° = 100°). Sinon, target = `BASE_FOV`. Interpolation `camera3d.fov = lerp(camera3d.fov, target_fov, DASH_FOV_LERP_SPEED * delta)` avec `DASH_FOV_LERP_SPEED = 14.0` — courbe snap-in ease-out, attrape le kick en ~150 ms et relâche en ~100 ms.

7. **Kick wall-jump.** Camera connecte le signal Movement `wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)` (signature canonique Movement r3 ; `launch_velocity` ignoré via paramètre `_`). La caméra ajoute un impulse au roll via le système de shake (cf. Rule 8) : `add_shake_roll(WALL_JUMP_KICK_MAGNITUDE * sign_with_fallback(wall_normal.dot(-camera_arm.global_transform.basis.x)))`. Magnitude par défaut : 0.05 rad (~3°), décroissance exponentielle. **Edge case dot=0** (wall_normal ⊥ -basis.x exact) : `sign_with_fallback` retourne `+1.0` au lieu de `0.0` (évite kick nul silencieux). Le kick s'applique sur `camera3d.rotation` (shake additif), pas sur `camera_effects.rotation.z` (qui porte le tilt steady).

8. **Shake générique additif.** Un `shake_offset: Vector3` (radians, x=pitch, y=yaw, z=roll) s'additionne à la rotation rendue de la caméra *après* le calcul de tilt/pitch/yaw. Décroissance exponentielle : `shake_offset *= exp(-SHAKE_DECAY * delta)` avec `SHAKE_DECAY = 12.0` (retour à <5% en ~250 ms). API publique : `CameraSystem.add_shake(offset_radians: Vector3)` et `CameraSystem.add_shake_roll(magnitude: float)`. Utilisation MVP : wall-jump uniquement ; l'infrastructure est prête pour hit katana et boss impact post-MVP.

9. **Respawn behavior.** À réception du signal `Player.died` :
   - fige la rotation pendant `RESPAWN_DELAY` (50 ms — constante owned par Movement r3, lue par Camera) ;
   - applique un overlay plein écran `Color(0.4, 0.0, 0.0, 0.6)` via un `ColorRect` enfant d'un `CanvasLayer` dédié au Camera System ;
   - ignore les signals `mouse_motion` reçus pendant ce délai (ne modifie pas `player.rotation.y` ni `camera_arm.rotation.x`) ;
   - à la réception de `Player.respawned(position)` : reset `camera_effects.rotation.z = 0` (tilt), `camera3d.fov = BASE_FOV`, `camera3d.rotation = Vector3.ZERO` (shake), `shake_offset = Vector3.ZERO`. **Le pitch (`camera_arm.rotation.x`) ET le yaw (`player.rotation.y`) sont PRÉSERVÉS** (Ghostrunner approach — décision post-design-review r1 2026-04-21 : éviter désorientation post-mort, aligné Pillar 3 "die-retry sous 2s, pas de réorientation forcée") ;
   - l'overlay alpha transite 0.6 → 0 en 100 ms, avec un flash blanc intermédiaire (`Color(1,1,1,0.9)` pendant 50 ms) — le fameux « respawn pop ».

10. **Head-bob : DÉSACTIVÉ au MVP.** Aucune oscillation verticale de la caméra en Grounded moving. Raisons : viole Pillar 1 (snap), vecteur de motion sickness, inaudible visuellement sans viewmodel de jambes. À reconsidérer post-MVP *uniquement* si playtest réclame, jamais comme default.

11. **Weapon sway : DÉSACTIVÉ au MVP.** Le viewmodel katana (owned par Combat, pas par ce GDD) suit rigidement la caméra. Pas de sway pendant la rotation.

12. **Performance.** La logique caméra tourne en `_process(delta)` (frame rate affichage, 60+ fps). La consommation de `mouse_motion` est event-driven via signal connection. **Aucune logique caméra en `_physics_process`** — pitch/yaw sont des *inputs visuels*, pas de la physique.

13. **Aim forward exposé.** `CameraSystem.aim_forward` est calculé en forme close trigonométrique à partir de `player.rotation.y` (yaw) et `camera_arm.rotation.x` (pitch), en ignorant explicitement `camera_effects.rotation.z` (tilt) — cf. ADR-0002 Formula close : `aim_forward = Vector3(-sin(yaw)*cos(pitch), -sin(pitch), -cos(yaw)*cos(pitch))`. Utilisé par Combat pour orienter le swept katana — garantit que le tilt wall-run ne dévie pas la hitbox horizontalement. **Pas de manipulation `Basis` manuelle** (la version r1 reconstruisait une basis sans roll et était algébriquement fragile).

14. **`reduce_motion` gate (accessibility floor MVP).** Lu à chaque frame depuis `InputManager.reduce_motion` (ou équivalent settings — ownership registry). Applique multiplicateurs avant commit :
    - Rule 4 tilt target : `target_roll *= tilt_mult` avec `tilt_mult = 0.25` si `reduce_motion`, sinon `1.0`.
    - Rule 6 FOV target : `dash_kick *= fov_kick_mult` avec `fov_kick_mult = 0.5` si `reduce_motion`, sinon `1.0` (peak ≤ 95° au lieu de 100°).
    - Rule 7/8 shake : `shake_offset *= shake_mult` avec `shake_mult = 0.0` si `reduce_motion` (shake désactivé).
    Hot-reload — lu chaque frame, pas caché. **MVP obligatoire** (décision creative-director r1 — évite exclusion 15-25% public motion-sensitive).

15. **`is_mouse_captured()` gate (contract Input GDD).** Avant d'appliquer `yaw_delta` et `pitch_delta` (Rules 2-3), Camera vérifie `InputManager.is_mouse_captured() == true`. Si false, ignore silencieusement le delta. Raison : évite rotation caméra silencieuse pendant menu open — contrat explicite côté Input GDD ("Contract `mouse_motion` en MouseFree"). Redondant avec `InputManager.enabled == false` pour gameplay pause, mais couvre l'état MouseFree standalone (ex : main menu avant capture).

16. **Cleanup signals au scene reload.** Dans `_exit_tree()`, Camera **disconnect explicitement** tous les signals Input/Movement connectés dans `_ready()` (`mouse_motion`, `died`, `respawned`, `wall_jumped`). Évite `"Signal target was freed"` au scene reload. Pattern canonique Godot — symétrie `_ready()` ↔ `_exit_tree()`.

### States and Transitions

La caméra n'a qu'un axe d'état propre (actif / désactivé) ; les autres "états visuels" sont dérivés des **signals Movement ADR-0005** via un cache local (`_is_dashing`, `_is_wall_running`, `_wall_side_cached`, etc.) — cf. **ADR-0002 Amendment A-1** (signal-driven consumption, pas de polling `player.state` / `player.is_dashing`).

| State | Entry Condition | Exit Condition | Behavior |
|---|---|---|---|
| **Active** | Game State == Playing ET `InputManager.enabled == true` | `died` reçu (→ Respawning) ; Menu ouvert (→ Paused) | Consomme `mouse_motion`, applique tilt/FOV selon l'état local mis en cache depuis les signals Movement (ADR-0002 Amendment A-1), intègre shake, expose `aim_forward` |
| **Respawning** | Signal `died` reçu | `respawned(position)` reçu + fade overlay terminé | Ignore `mouse_motion`, fige rotation, applique overlay rouge 100 ms → flash blanc 50 ms → clear. **Reset roll/FOV/shake en fin ; pitch ET yaw préservés** (Ghostrunner approach, cf. Rule 9) |
| **Paused** | `InputManager.enabled == false` (Menu ouvert) | Retour gameplay | Ignore `mouse_motion`, **fige** tilt/FOV courants (ne revient PAS à 0 — si le joueur pause en plein wall-run, on garde le tilt). Shake s'arrête de décroître. |

Les états Movement (Grounded / Airborne / Dashing / WallRunning) sont cachés localement via les signals ADR-0005 (`dash_started` / `dash_ended` / `wall_run_entered` / `wall_run_exited` / `died` / `respawned` / `wall_jumped`) — **jamais lus par polling** depuis `player.state` / `player.is_dashing` (interdiction ADR-0002 Amendment A-1, VC-7). Les targets de tilt et FOV sont calculés chaque frame à partir de ces membres locaux — aucune machine à états interne ne duplique cette info.

### Interactions with Other Systems

| Système | Rôle | Interface |
|---|---|---|
| **Input System** (amont) | Source des deltas souris + sensibilité | Connecte `InputManager.mouse_motion(delta)` signal. Lit `InputManager.mouse_sensitivity` et `InputManager.mouse_y_inverted` à chaque application. Respecte `InputManager.enabled` (ignore motion si false). |
| **Player Movement System** (amont) | Source des états de mouvement | **Signal-driven (ADR-0002 Amendment A-1)** — Camera connecte et cache localement : `dash_started()` / `dash_ended()` → `_is_dashing` ; `wall_run_entered(wall_normal)` / `wall_run_exited()` → `_is_wall_running` + `_wall_side_cached` (dérivé depuis le payload, cf. Rule 4) ; `died()` / `respawned(spawn_position)` / `wall_jumped(wall_normal, launch_velocity)` (signatures canoniques ADR-0005). Aucune lecture de `player.state` / `player.is_dashing` (grep-banned CI, VC-7). Lit la constante `RESPAWN_DELAY=0.05s` (owned par Movement). |
| **Player Combat System** (aval) | Forward direction pour hitbox katana | Combat lit `CameraSystem.aim_forward` (sans roll) pour orienter le swept katana. Combat ne lit jamais directement `camera.basis.z`. |
| **VFX System** (aval) | Déclenche shake externe, effets additionnels | Appelle `CameraSystem.add_shake()`. VFX s'occupe des particules / trails ; l'overlay rouge/blanc respawn est owned par Camera (non dupliqué côté VFX). |
| **HUD System** (aval) | Crosshair anchoring | Crosshair rendu via `CanvasLayer` centré écran (indépendant de la caméra). Aucun call direct. |
| **Menu / Settings** (aval) | Lit/écrit mouse_sensitivity via Input | Menu écrit dans `InputManager.mouse_sensitivity` — Camera lit Input, pas Menu directement. Aucune settings caméra ne vit dans ce système. |
| **Audio System** (aval) | Listener 3D | `AudioListener3D` est child de la `Camera3D` (convention Godot) — aucune interaction code requise. |
| **Game State Manager** (contrôleur) | Bascule Active ↔ Paused | Game State Manager coordonne avec Input (enabled) qui est lu par Camera. Pas d'appel direct. |

## Formulas

### 1. Mouse delta → rotation

```
yaw_delta   = -mouse_motion.x * mouse_sensitivity                                # applied to player.rotation.y
pitch_delta = -mouse_motion.y * mouse_sensitivity * (-1 if invert_y else 1)      # applied to camera_arm.rotation.x
camera_arm.rotation.x = clamp(camera_arm.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)
# Clamp magnitude (Rules 2-3) appliqué AVANT commit, cf. MAX_ROT_PER_FRAME.
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `mouse_motion` | `Δm` | Vector2 | pixels/frame | Delta brut Input System |
| `mouse_sensitivity` | `s_m` | float | 0.0005 – 0.012 rad/px | Owned par Input System — voir `design/registry/entities.yaml` → constants (source de vérité). Range élargi r2 pour couvrir high-sens FPS et low-sens sniper. |
| `mouse_y_inverted` | — | bool | true / false | Owned par Input System |
| `PITCH_LIMIT` | `θ_max` | float | `PI/2 - 0.05` ≈ 1.521 rad | Constante Camera |

**Output range** : `camera_arm.rotation.x ∈ [-1.521, +1.521]` rad ≈ ±87.1°. `player.rotation.y` non clampé (wrap libre).
**Exemple** : flick souris de 400 px horizontal à `s_m = 0.0022` → `yaw_delta = -400 * 0.0022 = -0.88 rad ≈ -50.4°`.

### 2. Tilt wall-run (target + interpolation)

```
wall_side   = sign((-player.wall_normal).dot(player.global_transform.basis.x))    # -1/0/+1, dérivé Camera (cf. Rule 4)
target_roll = WALL_RUN_TILT_ANGLE * wall_side                                      # rad
camera_effects.rotation.z = lerp(camera_effects.rotation.z, target_roll, min(TILT_LERP_SPEED * delta, 1.0))
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `WALL_RUN_TILT_ANGLE` | `θ_w` | float | 0.25 – 0.45 rad (14°–26°) | **Source de vérité ici**, défaut **0.35 rad (~20°)** — prototype validé playtest 2026-04-21 |
| `wall_side` | — | int | {-1, 0, +1} | **Dérivé Camera** depuis `player.wall_normal` (cf. Rule 4 ; pas de propriété `player.wall_side` côté Movement) |
| `TILT_LERP_SPEED` | `k_t` | float | 8.0 – 16.0 unit/s | Défaut 12.0 |
| `delta` | `Δt` | float | ~1/60 s | Frame delta `_process` |

**Output range** : `camera_effects.rotation.z ∈ [-0.45, +0.45]` rad selon tuning. **Temps pour atteindre 95% cible** : `t_95 ≈ ln(20) / k_t ≈ 250 ms` à k=12 (valable tant que `k * delta < 0.3`).
**Exemple** : entrée wall-run côté gauche → `target_roll = -0.35` rad. t=0 : z=0. t=166 ms (k=12) : z ≈ -0.315 rad (90% cible).
**Note stabilité framerate** : `t_95` calculé pour 60 fps ; variance acceptée ±20% sur 30-144 fps (dette tech, cf. Open Questions). Refactor vers `1 - exp(-k*delta)` si dérive perçue à 144 fps.

### 3. FOV pulse dash

```
# _is_dashing est un membre Camera caché depuis signals dash_started/dash_ended (ADR-0002 Amendment A-1).
target_fov = BASE_FOV + (DASH_FOV_KICK if _is_dashing else 0.0)
camera3d.fov = lerp(camera3d.fov, target_fov, min(DASH_FOV_LERP_SPEED * delta, 1.0))
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `BASE_FOV` | `F_0` | float | 80° – 100° | Défaut **90°** — prototype validé |
| `DASH_FOV_KICK` | `ΔF` | float | 6° – 14° | Défaut 10° |
| `DASH_FOV_LERP_SPEED` | `k_f` | float | 10.0 – 18.0 unit/s | Défaut 14.0 |

**Output range** : `camera3d.fov ∈ [BASE_FOV, BASE_FOV + DASH_FOV_KICK]` = [90°, 100°] par défaut.
**Exemple** : dash démarre t=0 (fov=90). t=0.15 s (fin du burst), k=14 → convergence ≈ `1 - exp(-14*0.15) = 0.878` → fov ≈ 98.8°. Retour à 90° en ~100 ms après fin de dash.

### 4. Shake additif (décroissance exponentielle + cap)

```
# Injection externe:
shake_offset += injected_offset
shake_offset = shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)   # cap obligatoire post-r1 (évite cumul nauséeux si plusieurs add_shake concurrents)

# Chaque frame _process:
shake_offset *= exp(-SHAKE_DECAY * delta)

# Application (assignation, pas += — garantit reset implicite au-dessus de la transform CameraEffects) :
camera3d.rotation = shake_offset
```

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `shake_offset` | `σ` | Vector3 (rad) | \|σ\| ≤ 0.2 rad recommandé | État interne Camera |
| `SHAKE_DECAY` | `λ` | float | 8.0 – 16.0 /s | Défaut 12.0 |
| `WALL_JUMP_KICK_MAGNITUDE` | `κ_wj` | float | 0.03 – 0.08 rad | Défaut 0.05 rad (~3°) |

**Output range** : retour <1% de la valeur initiale après `t ≈ ln(100)/λ ≈ 384 ms` (perceptible ~250 ms).
**Exemple** : wall-jump → `add_shake_roll(0.05)`. À t=0.1s : `0.05 * exp(-1.2) ≈ 0.0151 rad`. À t=0.25s : ≈ 0.0025 rad (quasi nul).

### 5. Aim forward (forme close trigonométrique)

```gdscript
var yaw: float = player.rotation.y
var pitch: float = camera_arm.rotation.x
aim_forward = Vector3(-sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
```

**Raison** : la version r1 (`Basis(UP, -roll) * basis_globale`) était **algébriquement incorrecte** — une rotation autour de l'axe world UP par `-roll` n'annule pas un roll local Z (analyse systems-designer post-review r1). La forme close trigonométrique est analytiquement équivalente à `-Basis.from_euler(Vector3(pitch, yaw, 0)).z` (Godot EULER_ORDER_YXZ) et ignore le roll (tilt CameraEffects) par construction — aucune manipulation Basis sujette à erreur.
**AC vérifiable** : `pitch=-0.5, yaw=0.3, roll=0.2` (roll n'apparaît pas dans la formule) → `aim_forward ≈ (-sin(0.3)*cos(-0.5), -sin(-0.5), -cos(0.3)*cos(-0.5)) ≈ (-0.259, 0.479, -0.838)`.
**Exemple** : pendant wall-run droit, `camera_effects.rotation.z = +0.35` n'affecte pas `aim_forward` — identique à une caméra non-tiltée au même pitch/yaw.

## Edge Cases

- **If `mouse_motion` arrive pendant `Respawning`** : l'event est ignoré silencieusement (pas de rotation, pas d'accumulation bufferisée). Au retour en Active, le premier delta post-respawn est appliqué normalement — Input System ne republie pas les motions pendant `enabled=false`, donc pas de saut de vue.
- **If l'app perd le focus (alt-tab) pendant un tilt wall-run actif** : Input System auto-pause et met `enabled=false` → Camera entre en Paused → tilt courant figé. Au retour : si `_is_wall_running == true` (aucun `wall_run_exited` reçu pendant la perte de focus), le tilt reprend sa convergence vers `WALL_RUN_TILT_ANGLE * _wall_side_cached` ; sinon le tilt converge vers 0. Pas de glitch.
- **If wall-jump déclenché pendant que le tilt est encore à pleine valeur** : le shake Z s'ajoute au roll courant. Le roll total peut dépasser `WALL_RUN_TILT_ANGLE + WALL_JUMP_KICK_MAGNITUDE` ≈ 0.40 rad (~23°) un instant — acceptable. Le tilt "principal" converge vers 0 (sortie wall-run), le shake décroît en parallèle — double convergence réglée en ~300 ms.
- **If le Player entre et sort de wall-run dans la même frame** (oscillation raycast) : `target_roll` alterne 0 → ±0.35 → 0. Avec lerp k=12, l'amplitude visible reste <5% cible sur 1 frame à 60 fps. Filtrage hystérésis relève du Movement System, pas Camera.
- **If `wall_side` change sans passer par 0** (wall-run gauche → immédiatement droit) : target bascule -0.35 → +0.35 d'un coup. Le lerp traverse 0 en ~200 ms, transition visible mais propre.
- **If deux dashes consécutifs avant que FOV ne revienne à `BASE_FOV`** : `target_fov` repasse à `BASE_FOV + DASH_FOV_KICK`, le lerp reprend depuis la valeur courante. Le kick n'est pas additif, il est absolute-target. Voulu.
- **If `mouse_sensitivity` change en cours de jeu** : lue à chaque application, effective au motion suivant. Aucun glitch.
- **If `mouse_y_inverted` change en cours de jeu** : idem ; le pitch courant n'est pas réaffecté — seules les futures motions.
- **If `camera_arm.rotation.x` atteint `PITCH_LIMIT`** : clamp dur, delta excédentaire perdu (pas d'accumulation). Godot gère proprement tant que le clamp est appliqué chaque frame.
- **If Combat lit `aim_forward` alors que `camera_effects.rotation.z` est NaN** : chaque tick, la Camera vérifie `is_finite(camera_effects.rotation.z)` ; si false, reset à 0 + log warning (channel `camera`, severity WARN). Non observé au prototype mais low-cost.
- **If le Player node est détruit et reconstruit** (scene reload) : la Camera étant son child, elle est également détruite. Le Game State Manager doit reconnecter les signals Input→Camera au prochain spawn. Protocole documenté par Game State Manager GDD (à venir).
- **If le jeu boote directement dans un niveau sans main menu** : Input System applique `mouse_sensitivity=0.0022` default à `_ready` ; Save/Load update au tick suivant. Camera lit la valeur courante, aucun traitement spécial.
- **If l'overlay respawn `ColorRect` n'existe pas dans la scène** (bug setup) : Camera crée dynamiquement l'overlay à `_ready` via un `CanvasLayer + ColorRect` auto-instancié. Aucune dépendance à une scène externe préfaite.
- **If le joueur respawn pendant qu'un shake est actif** : `shake_offset` est reset à `Vector3.ZERO` dans la routine `respawned`. Pas d'héritage de shake run précédent.
- **If `RESPAWN_DELAY` (owned par Movement) change en cours de run** : Camera lit la constante à chaque `died` — pas de cache. Aucune incohérence.
- **If Godot 4.6 change le comportement de `Camera3D.fov`** (post-cutoff LLM knowledge) : vérifier à l'implémentation. Prototype a validé assignation frame-per-frame OK sur macOS Metal. Flag MEDIUM risk.
- **If pitch ET yaw arrivent dans le même `InputEventMouseMotion`** (cas normal) : appliqués dans la même frame — yaw au Player puis pitch à la Camera. Axes orthogonaux, ordre sans importance.

## Dependencies

| Système | Direction | Nature |
|---|---|---|
| **Godot Engine** (`Camera3D`, `CanvasLayer`, `ColorRect`) | Amont direct | Primitives caméra + overlay. Tout changement d'API Camera3D entre versions Godot 4.x casserait ce système. |
| **Input System** | Amont | Signal `mouse_motion(delta)`, lecture de `mouse_sensitivity`, `mouse_y_inverted`, `enabled`. Sans Input, la Camera ne peut ni tourner ni savoir quand ignorer les motions. |
| **Player Movement System** | Amont | **Signal-driven (ADR-0002 Amendment A-1, gouverné par ADR-0005 Accepted)** — connecte + cache : `dash_started` / `dash_ended` → `_is_dashing` ; `wall_run_entered(wall_normal)` / `wall_run_exited` → `_is_wall_running` + `_wall_side_cached` (dérivation cf. Rule 4) ; `died()` / `respawned(spawn_position)` / `wall_jumped(wall_normal, launch_velocity)`. Aucune lecture `player.state` / `player.is_dashing` (VC-7 grep-banned). Constante `RESPAWN_DELAY=0.05s` (owned Movement). Hard dependency. |
| **Player Combat System** | Aval | Combat lit `CameraSystem.aim_forward` pour orienter le swept katana. Contrat unidirectionnel. |
| **VFX & Feedback System** | Aval | Appelle `CameraSystem.add_shake()` / `add_shake_roll()`. Écoute signals `died`/`respawned` en parallèle. L'overlay rouge/blanc respawn reste owned par Camera. |
| **HUD System** | Aval (soft) | Crosshair ancré en `CanvasLayer` indépendant ; aucun appel code. Peut lire `camera3d.fov` pour scaling optionnel post-MVP. |
| **Menu / Settings System** | Indirect via Input | Menu écrit dans `InputManager.mouse_sensitivity`. Camera voit la nouvelle valeur automatiquement. Pas d'API directe Menu↔Camera. |
| **Audio System** | Aval (passif) | `AudioListener3D` child de `Camera3D` — convention Godot, aucune interaction code. |
| **Game State Manager** | Aval (contrôleur) | Bascule Camera entre Active / Paused / Respawning via signaux Player + Input.enabled. Reconnecte signals au scene reload. |
| **Save/Load System** | Aval (indirect) | Persiste `input_settings.tres` contenant `mouse_sensitivity`. Camera en bénéficie sans le savoir. |

**Note de cohérence bidirectionnelle** :
- **Input System GDD** référence Camera comme consommateur de `mouse_motion` + `mouse_sensitivity` + `mouse_y_inverted` ✅ (déjà présent sections Dependencies + Cross-References).
- **Player Movement GDD** référence Camera comme consommateur des signals ADR-0005 (`dash_started` / `dash_ended` / `wall_run_entered` / `wall_run_exited` / `died` / `respawned` / `wall_jumped`) ✅ (déjà présent sections Dependencies + Interactions with Other Systems, signal-driven depuis ADR-0002 Amendment A-1). **Conflit à résoudre** : Movement GDD mentionne un tilt de ~12° provisoire → Camera GDD est la source de vérité à 20° (0.35 rad). `/consistency-check` doit corriger Movement GDD pour retirer la valeur et pointer Camera comme owner. Flag dans Open Questions et Cross-References.

## Tuning Knobs

| Paramètre | Valeur courante | Safe Range | Effet si augmenté | Effet si diminué |
|---|---|---|---|---|
| `BASE_FOV` | 90° | 80° – 100° | Vision latérale élargie, plateformes paraissent proches | Vision resserrée, "cinématique", moins Pillar 1 |
| `DASH_FOV_KICK` | 10° | 6° – 14° | Pulse plus fort, risque motion sickness | Pulse discret, dash plus plat |
| `DASH_FOV_LERP_SPEED` | 14.0 | 10.0 – 18.0 | Pulse snap, immédiat | Pulse smoothé, moins percutant |
| `WALL_RUN_TILT_ANGLE` | 0.35 rad (~20°) | 0.25 – 0.45 rad (14°–26°) | Wall-run viscéral, possible nausée sessions longues | Wall-run invisible → viole règle OBLIGATOIRE Detailed Design |
| `TILT_LERP_SPEED` | 12.0 | 8.0 – 16.0 | Tilt rapide, peut être sec | Tilt smooth mais lent → indistinguable du saut |
| `PITCH_LIMIT` | `PI/2 - 0.05` ≈ 1.521 rad | 1.40 – 1.55 rad | Limite permissive, risque gimbal lock extrême | Limite stricte, "plafond" perçu |
| `SHAKE_DECAY` | 12.0 | 8.0 – 16.0 | Shake court, percutant | Shake long, distrayant |
| `WALL_JUMP_KICK_MAGNITUDE` | 0.05 rad (~3°) | 0.03 – 0.08 rad | Kick appuyé, poussée forte | Kick discret, wall-jump sans identité |
| `RESPAWN_OVERLAY_COLOR` | `Color(0.4, 0, 0, 0.6)` rouge sombre | — | Plus rouge/opaque = plus agressif | Plus transparent = mort moins marquée |
| `RESPAWN_OVERLAY_FADE_DURATION` | 100 ms | 50 – 200 ms | Fade doux | Fade abrupt |
| `RESPAWN_FLASH_DURATION` | 50 ms | 30 – 100 ms | Flash visible plus longtemps | Flash imperceptible, perd son pop |
| `MAX_ROT_PER_FRAME` | `PI` rad (180°) | 0.5 – PI rad | Cap permissif (rotation explosive autorisée) | Cap strict (atténue flick mais peut perdre rotation légitime) |
| `MAX_SHAKE_MAGNITUDE` | 0.2 rad (~11.5°) | 0.10 – 0.30 rad | Cap permissif (cumul nauséeux possible) | Cap strict (kick wall-jump tronqué si concurrent) |
| `reduce_motion` (toggle MVP) | `false` (default OFF) | bool | Tilt ×0.25, FOV kick ×0.5, shake ×0 (floor accessibility — évite exclusion 15-25% public motion-sensitive) | Effets pleine intensité (default) |
| `MOUSE_SMOOTHING` | 0.0 (désactivé) | 0.0 – 0.15 s | Rotation plus douce mais ajoute latence → viole Pillar 1 | — (valeur plancher) |
| `HEAD_BOB_ENABLED` | `false` | `true` / `false` | Bob marche = motion sickness trigger | Pas de bob (default) |
| `VIEW_MODEL_SWAY_ENABLED` | `false` | `true` / `false` | Sway katana = feel lourd déconseillé | Pas de sway (default) |

**Interactions notables** :
- `WALL_RUN_TILT_ANGLE` et `TILT_LERP_SPEED` doivent être tunés ensemble. Grand angle (25°) + interp rapide (16) provoque nausée. Si on monte l'angle, baisser la vitesse d'interp.
- `BASE_FOV + DASH_FOV_KICK` ne doit pas dépasser 110° (distorsion optique en périphérie Godot).
- `MOUSE_SMOOTHING > 0` annule Pillar 1. À exposer uniquement en accessibility mode (Tier 3), jamais default.

**Persistence** :
- `HEAD_BOB_ENABLED`, `VIEW_MODEL_SWAY_ENABLED`, `MOUSE_SMOOTHING` → settings utilisateur, persistés via `input_settings.tres` (extension post-MVP).
- Les autres knobs (`BASE_FOV`, `WALL_RUN_TILT_ANGLE`, etc.) vivent dans une ressource `camera_tuning.tres` hot-reload-able en dev, figés en build release.

## Visual/Audio Requirements

| Événement | Feedback visuel | Feedback audio | Priorité | Notes |
|---|---|---|---|---|
| Wall-run entre | Tilt caméra 0.35 rad vers le mur, interp 250 ms | Whoosh grave (owned par Audio System) | **Critical** | Sans ce feedback, wall-run invisible (learning prototype #7) |
| Wall-run sort | Tilt retour à 0, interp 300 ms | Fade du whoosh | High | — |
| Wall-jump | Kick shake Z 0.05 rad, decay exponentiel 250 ms | Punchy (Audio) | High | Direction dérivée de `wall_normal` |
| Dash démarre | FOV 90 → 100°, interp 150 ms | — (swoosh géré par Audio) | **Critical** | Pulse signature Pillar 1 |
| Dash finit | FOV 100 → 90°, interp 100 ms | — | Medium | — |
| Mort | Overlay rouge `Color(0.4, 0, 0, 0.6)` instant, rotation figée | Son mort (Audio) | **Critical** | Fade 100 ms après RESPAWN_DELAY |
| Respawn | Flash blanc `Color(1, 1, 1, 0.9)` 50 ms, reset pitch/roll/fov | Pop respawn (Audio) | **Critical** | Flash intercalé dans le fade overlay |

> Détails animation à affiner dans l'art-bible (section Camera/Post-processing — art-bible pas encore créée, à produire via `/art-bible`).

📌 **Asset Spec** — Visual requirements définis. Après approbation de l'art bible, lancer `/asset-spec system:camera-system` pour produire les specs visuelles des overlays (couleurs exactes, shaders optionnels, courbes d'interpolation).

## Game Feel

### Feel Reference

**Mirror's Edge** (tilt wall-run, signature qui a fait fonctionner le wall-run en vue FPS) + **Ghostrunner** (FOV dash, rotation raw sans smoothing) + **Titanfall 2** (kick wall-jump subtil, directionnel).

Anti-références explicites : Destiny (weapon sway permanent, head-bob marche), COD (mouse smoothing imposé ajoutant ~30 ms de latence), Quake Champions (head-bob trop fort en sprint). Aucun smoothing, aucune inertie caméra, aucun filtrage.

### Input Responsiveness

| Action | Max latency | Frame budget | Notes |
|---|---|---|---|
| Mouse motion → rotation rendue | ≤ 16 ms | ≤ 1 frame affichage | Event-driven via signal, pas polling |
| Signal Movement (`dash_started`/`wall_run_entered`/…) → tilt/FOV target | ≤ 16 ms | ≤ 1 frame | Handler signal met à jour le membre caché ; target recalculé dans `_process` et appliqué le même frame (ADR-0002 Amendment A-1) |
| `died` signal → overlay visible | ≤ 16 ms | ≤ 1 frame | Signal sync immédiat |

### Animation Feel Targets

| Animation | Startup | Active | Recovery | Feel Goal |
|---|---|---|---|---|
| Tilt wall-run | 250 ms (95%) | maintenu | 300 ms (1%) | Sticky, confortable, pas brutal |
| FOV dash pulse | 150 ms (snap-in) | 150 ms | 100 ms (ease-out) | Punch vers l'avant |
| Kick wall-jump | 0 ms (instant) | — | 250 ms (exp decay) | Secousse brève, directionnelle |
| Overlay mort | 0 ms (snap) | 200 ms | 100 ms fade | Punitif, immédiat |
| Flash respawn | 0 ms (snap) | 50 ms | — | Pop binaire |

### Impact Moments

| Type | Durée | Description | Configurable |
|---|---|---|---|
| Hit-stop | 0 ms | **Aucun** — le flow ne doit pas être interrompu | N/A |
| Screen shake (wall-jump) | 250 ms | 0.05 rad roll, exp decay `λ=12` | Oui (`WALL_JUMP_KICK_MAGNITUDE`) |
| Camera impact (mort) | 0 ms | Overlay snap, rotation figée, pas de ragdoll | Non |
| Time-scale slowdown | N/A | Pas de slow-mo côté Camera (slow-mo aérien = upgrade distinct) | N/A |

### Weight and Responsiveness Profile

- **Weight** : ultralight. Rotation raw, aucune inertie, aucun smoothing.
- **Contrôle joueur** : total, sauf pendant RESPAWN_DELAY (50 ms, owned par Movement r3).
- **Snap quality** : rotation pixel-perfect. Tilt/FOV sont snap-in ease-out, jamais linéaire.
- **Modèle d'accélération** : aucune pour la rotation ; exp lerp pour les transitions d'état visuel.
- **Texture d'échec** : si la caméra paraît laggy, vérifier (1) frame rate, (2) `MOUSE_SMOOTHING == 0`, (3) aucun `_physics_process` dans le Camera System.

### Feel Acceptance Criteria

- [ ] Aucun playtester ne dit "la caméra lag", "ça tourne bizarre", "j'ai mal au crâne" après 20 min de session.
- [ ] Le wall-run est visuellement distinct du saut dès le premier essai (« ah j'ai wall-run » sans explication).
- [ ] Le dash est visuellement distinct du sprint (le FOV pulse est perçu).
- [ ] Respawn total visible (mort + fade + flash) ≤ 400 ms.

## UI Requirements

| Information | Emplacement | Fréquence update | Condition |
|---|---|---|---|
| Overlay rouge mort | Plein écran via `CanvasLayer` owned par Camera | Toggle instant on `died` | État Respawning |
| Flash blanc respawn | Plein écran via le même `CanvasLayer` | 50 ms burst | Lors de `respawned` |
| Crosshair | Centre écran (owned par HUD, pas Camera) | — | Permanent en gameplay |
| FOV courant (debug) | Overlay F3 | Par frame | Dev only, via Input `debug_toggle` |
| Tilt courant (debug) | Overlay F3 | Par frame | Dev only |
| Sensitivity slider | Menu Settings (owned par Menu) | — | Écrit dans `InputManager.mouse_sensitivity` |

> **📌 UX Flag — Camera System** : les settings FOV (si exposé) et motion-reduction (toggles pour retirer tilt / shake / FOV-pulse) nécessiteront un spec UX en Phase 4 (Pre-Production). Lancer `/ux-design settings-camera` si ces options sont priorisées — **non-MVP par défaut**. L'Accessibility System (Tier 3) les incorporera alors.

## Cross-References

| Ce document référence | GDD cible | Élément référencé | Nature |
|---|---|---|---|
| `mouse_motion` signal, `mouse_sensitivity`, `mouse_y_inverted`, `enabled` | `design/gdd/input-system.md` *(existant)* | API Input consommée | Data + event dependency |
| Signals ADR-0005 : `dash_started` / `dash_ended` / `wall_run_entered(wall_normal)` / `wall_run_exited` / `died()` / `respawned(spawn_position)` / `wall_jumped(wall_normal, launch_velocity)` (signal-driven consumption via cache local, ADR-0002 Amendment A-1 ; aucun polling de `player.state` / `player.is_dashing`). Dérivation `_wall_side_cached` Camera-side (cf. Rule 4). Constante `RESPAWN_DELAY=0.05s` | `design/gdd/player-movement-system.md` *(existant)* | Signals + constantes uniquement | Event dependency |
| `CameraSystem.aim_forward` consommé par katana swept | `design/gdd/player-combat-system.md` *(à écrire)* | Forward direction sans roll | API Camera owned ici |
| `CameraSystem.add_shake()` / `add_shake_roll()` appelés par VFX | `design/gdd/vfx-feedback-system.md` *(à écrire)* | Déclenchement d'impact visuel | API Camera owned ici |
| Overlay fade respawn (rouge + flash blanc) | `design/gdd/vfx-feedback-system.md` *(à écrire)* | Délégation owned ici, VFX synchronisé via signals | Ownership resolved |
| Menu écrit dans `InputManager.mouse_sensitivity` | `design/gdd/menu-system.md` *(à écrire)* | Settings plumbing via Input, pas direct | Indirect dep |

> **Registry conflict to resolve** : `WALL_RUN_TILT_ANGLE = 0.35 rad (~20°)` est désormais owned par ce GDD. Le Player Movement GDD mentionne un tilt "~12°" qui était provisoire pré-playtest. **`/consistency-check` doit corriger Movement GDD** pour retirer la valeur numérique et pointer vers Camera System comme owner. Flag dans Open Questions.
>
> **Registry candidates (nouveaux)** : `base_fov` (90°, unit: degrés), `wall_run_tilt_angle` (0.35 rad), `dash_fov_kick` (10°) — à enregistrer via Phase 5 du design-system.

## Acceptance Criteria

> **Convention** (alignée Movement r3 / Input r2) : `AC-CAM-NN [Type — BLOCKING/ADVISORY] [Owner: qa-tester]`. Types : Logic (test unitaire GUT), Integration (test multi-système GUT/headless), Visual/Feel (screenshot + sign-off), Perf (mesure instrumentée). Evidence paths pour Visual/Feel : `production/qa/evidence/camera-[ac-id]-[date].png`.

### Rotation mouse → caméra

- **AC-CAM-01** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** Camera Active, `mouse_sensitivity=0.0022`, `invert_y=false`, **WHEN** un `InputEventMouseMotion(Vector2(100, 0))` est émis, **THEN** au frame suivant `player.rotation.y` a décru de `0.22 rad ± 0.001` et `camera_arm.rotation.x` est inchangé (`Δ < 1e-6`).
- **AC-CAM-02** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** Camera Active, `mouse_sensitivity=0.0022`, **WHEN** motion `Vector2(0, 100)` est émis avec `invert_y=false`, **THEN** `camera_arm.rotation.x` a décru de `0.22 rad ± 0.001`. **WHEN** répété avec `invert_y=true`, **THEN** `camera_arm.rotation.x` a augmenté de `0.22 rad ± 0.001`.
- **AC-CAM-03** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `camera_arm.rotation.x == PITCH_LIMIT`, **WHEN** un motion vers le haut équivalent à +0.5 rad est émis, **THEN** `camera_arm.rotation.x == PITCH_LIMIT` exactement (clamp dur, pas d'accumulation interne).
- **AC-CAM-04** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `mouse_sensitivity=0.012` (max safe range), **WHEN** un motion `Vector2(10000, 0)` est émis (flick dégénéré 10 000 px / frame), **THEN** `|yaw_delta|` appliqué est `≤ MAX_ROT_PER_FRAME == PI` — le delta excédentaire est clampé et **pas** accumulé dans une variable interne.

### Tilt wall-run

- **AC-CAM-10** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Player entre en WallRunning avec mur à droite (`wall_normal` pointe du mur vers le Player → dérivé `wall_side=+1`), `camera_effects.rotation.z=0`, **THEN** à frame+1 `z > 0` ; à `t=250 ms` (60 fps = 15 frames), `z ≥ 0.95 * WALL_RUN_TILT_ANGLE == 0.3325 rad`.
- **AC-CAM-11** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Player sort de WallRunning (`wall_normal == Vector3.ZERO` → `wall_side=0`), **THEN** `camera_effects.rotation.z` converge vers 0 et `|z| < 0.01 rad` dans ≤ 300 ms.
- **AC-CAM-12** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** `wall_normal` bascule de `(-1,0,0)` à `(+1,0,0)` en 1 frame (wall gauche → wall droit), **THEN** `wall_side` passe `+1` → `-1`, `camera_effects.rotation.z` traverse 0 dans [100, 200] ms, sans overshoot > 0.05 rad.
- **AC-CAM-13** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` — **GIVEN** wall-run côté droit pendant 500 ms, **THEN** screenshot à `t=300 ms` montre tilt visuellement lisible (angle perçu distinct du saut). Evidence : `production/qa/evidence/camera-tilt-wallrun-[date].png` + sign-off.

### FOV dash

- **AC-CAM-20** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Camera `_is_dashing == false`, **WHEN** Movement émet `dash_started()`, **THEN** `_is_dashing` devient `true` dans le même tick (handler signal) et `camera3d.fov` converge vers `BASE_FOV + DASH_FOV_KICK = 100°` ; à `t=150 ms`, `fov ≥ 98.5°`.
- **AC-CAM-21** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Camera `_is_dashing == true`, **WHEN** Movement émet `dash_ended()`, **THEN** `_is_dashing` devient `false` dans le même tick et `camera3d.fov` converge vers `BASE_FOV = 90°` et `|fov - 90| < 0.5°` dans ≤ 250 ms.
- **AC-CAM-22** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` — **GIVEN** dash déclenché, **THEN** screenshot à `t=100 ms` et `t=250 ms` — le FOV pulse est perceptuellement distinct (worldspace "tire" vers les côtés puis relaxe). Evidence : `production/qa/evidence/camera-fov-dash-pulse-[date].png` (pair before/peak/after).

### Shake + wall-jump

- **AC-CAM-30** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `CameraSystem.add_shake_roll(0.05)` est appelé frame 0, **THEN** frame 1 : `shake_offset.z ≈ +0.05` ± décroissance 1 tick ; à `t=250 ms` : `|shake_offset.z| < 0.005 rad`.
- **AC-CAM-31** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Movement émet `wall_jumped(wall_normal=Vector3(1,0,0), launch_velocity=Vector3(10,10,0))`, **THEN** Camera consomme le signal (signature canon ADR-0005), appelle `add_shake_roll` avec signe dérivé de `sign_with_fallback(wall_normal.dot(-camera_arm.global_transform.basis.x))`, et `camera3d.rotation` final = `shake_offset` (pas d'addition `+=` sur la transform existante).
- **AC-CAM-32** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** 3 `add_shake_roll(0.05)` concurrents dans le même tick, **THEN** `shake_offset.length() ≤ MAX_SHAKE_MAGNITUDE == 0.2 rad` post-`limit_length()` — pas de cumul nauséeux non borné.

### Respawn (3 ACs atomiques)

- **AC-CAM-40** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Camera Active, **WHEN** Movement émet `died()`, **THEN** dans le même tick : Camera entre en Respawning, overlay `ColorRect` à `alpha=0.6` couleur `(0.4, 0.0, 0.0, 0.6)`, signals `mouse_motion` suivants ignorés (rotation figée).
- **AC-CAM-41** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Camera Respawning depuis `RESPAWN_DELAY=50ms`, **WHEN** Movement émet `respawned(Vector3(10, 2, 5))`, **THEN** `camera_effects.rotation.z == 0`, `camera3d.fov == BASE_FOV == 90°`, `camera3d.rotation == Vector3.ZERO`, `shake_offset == Vector3.ZERO`, ET **`camera_arm.rotation.x` inchangé (pitch préservé)**, ET **`player.rotation.y` inchangé (yaw préservé)** — Ghostrunner approach.
- **AC-CAM-42** `[Visual/Feel — ADVISORY] [Owner: QA Lead]` — **GIVEN** séquence died → respawned, **THEN** la transition overlay `alpha=0.6 → 0` dure 100 ms avec un flash blanc `(1,1,1,0.9)` intercalé 50 ms. Evidence : `production/qa/evidence/camera-respawn-fade-[date].png` (5 frames capture : death, mid-red, flash-white, mid-fade, clear).
- **AC-CAM-43** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** Camera en état Respawning, **WHEN** Movement émet un second `died()` dans le délai (cas edge idempotence), **THEN** aucun second cycle de fade n'est déclenché (early return `if state == Respawning: return` en première ligne du handler `died`). Miroir de Movement AC-MV-41.

### Aim forward (roll-corrigé)

- **AC-CAM-50** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `camera_effects.rotation.z = +0.35` (wall-run droit), `camera_arm.rotation.x = 0` (pitch), `player.rotation.y = 0` (yaw), **THEN** `CameraSystem.aim_forward == Vector3(0, 0, -1)` à `± 1e-5` (roll ignoré par construction closed-form).
- **AC-CAM-51** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `pitch=-0.5 rad, yaw=0.3 rad, roll=0.2 rad`, **THEN** `aim_forward ≈ (-0.2594, 0.4794, -0.8383)` à `± 1e-4`. Vérification indépendante : `aim_forward.distance_to(-Basis.from_euler(Vector3(-0.5, 0.3, 0), EULER_ORDER_YXZ).z) < 1e-4` — le roll n'apparaît pas dans la formule, donc résultat invariant au roll.

### État / mode

- **AC-CAM-60** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `InputManager.enabled == false`, **WHEN** `mouse_motion` émis (pour ce test, `simulate_mouse_motion` Input API), **THEN** ni `player.rotation.y` ni `camera_arm.rotation.x` ne bougent, tilt/FOV courants figés (ne reviennent **pas** à 0).
- **AC-CAM-61** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `InputManager.enabled` passe `false → true`, **WHEN** premier motion reçu post-transition, **THEN** rotation appliquée normalement sans saut visuel cumulé (pas de buffer d'events disabled).
- **AC-CAM-62** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** `InputManager.is_mouse_captured() == false` (MouseFree, menu open), **WHEN** `mouse_motion` émis, **THEN** Camera ignore silencieusement — aucune rotation (Rule 15 gate).
- **AC-CAM-63** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** scene reload (Player node free + reconstruit), **WHEN** Camera `_exit_tree()` s'exécute, **THEN** tous signals Input/Movement connectés dans `_ready()` sont explicitement disconnectés ; aucun log `"Signal target was freed"` ne doit apparaître au next spawn (Rule 16).
- **AC-CAM-64** `[Integration — ADVISORY] [Owner: qa-tester]` — **GIVEN** app perd le focus pendant un tilt wall-run actif (alt-tab), **WHEN** focus restauré et `_is_wall_running == true` (aucun `wall_run_exited` reçu pendant la perte de focus), **THEN** tilt reprend sa convergence vers `WALL_RUN_TILT_ANGLE * _wall_side_cached` sans glitch visible > 1 frame.

### Reduce motion (accessibility floor MVP)

- **AC-CAM-70** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `reduce_motion == true`, **WHEN** Player entre en WallRunning, **THEN** target_roll effectif = `WALL_RUN_TILT_ANGLE * wall_side * 0.25` (= 0.0875 rad au lieu de 0.35).
- **AC-CAM-71** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `reduce_motion == true`, **WHEN** Player dashe, **THEN** `camera3d.fov` converge vers `BASE_FOV + DASH_FOV_KICK * 0.5 = 95°` (peak) au lieu de 100°.
- **AC-CAM-72** `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** `reduce_motion == true`, **WHEN** `add_shake_roll(0.05)` appelé, **THEN** `shake_offset` reste à `Vector3.ZERO` (shake désactivé, multiplier = 0).

### Performance (p50/p99)

- **AC-CAM-80** `[Perf — BLOCKING] [Owner: performance-analyst]` — **GIVEN** session 60 s scène test `tests/perf/camera-stress.tscn` (Player + 3 enemies + wall-run actif cycle + dash cycle), 60 Hz physique / 60 fps affichage (ADR-0001), **THEN** coût CPU `_process` Camera (pitch/yaw + shake + tilt + fov + aim_forward) : **`p50 ≤ 0.2 ms`, `p99 ≤ 0.4 ms`**, mesuré via ring buffer 240 samples. Evidence : `production/qa/evidence/camera-perf-[date].json` + script GUT.
- **AC-CAM-81** `[Perf — BLOCKING] [Owner: performance-analyst]` — **GIVEN** application d'un `mouse_motion`, **WHEN** instrumentation ring buffer active, **THEN** latence `t_event → t_applied_rendered` ≤ 16 ms en p99 sur 1000 samples (à 60 fps, = 1 frame max).

### Intégration cross-system

- **AC-CAM-90** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Player dash pendant WallRunning (tilt actif, `camera_effects.rotation.z != 0`), **THEN** Combat consommateur de `CameraSystem.aim_forward` oriente le swept katana parallèle au sol (direction horizontale ignore le roll), vérifié via `|aim_forward.y - (-sin(pitch))| < 1e-4`.
- **AC-CAM-91** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Menu modifie `InputManager.mouse_sensitivity` 0.0022 → 0.0040 en pause, **WHEN** jeu reprend et motion `Vector2(100, 0)` émis, **THEN** rotation appliquée utilise 0.0040 (`|yaw_delta| = 0.4 rad`, pas 0.22).
- **AC-CAM-92** `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** Movement émet `wall_jumped(wall_normal, launch_velocity)`, **THEN** Camera reçoit le signal et applique shake dans le même tick que VFX reçoit le signal (ADR-0005 D-6 ordre intra-tick) — aucun conflit temporel.

## Open Questions

| Question | Owner | Deadline | Résolution attendue |
|---|---|---|---|
| Conflit tilt wall-run : 12° (Movement GDD initial) vs 20° (Camera GDD, validation playtest 2026-04-21) | consistency-check | **Résolu r2 post-review** | Movement GDD lignes 70, 371, 373, 386, 420 patchées pour référencer `WALL_RUN_TILT_ANGLE` / `WALL_JUMP_KICK_MAGNITUDE` Camera-owned + nœud `CameraEffects.rotation.z` canonique. Valeurs numériques retirées de Movement GDD. |
| Option "reduce motion" pour accessibility : MVP ou Full Vision ? | accessibility-specialist | **Résolu r1 post-review** | **MVP obligatoire** (floor accessibility — évite exclusion 15-25% public motion-sensitive). Toggle binaire unique : tilt ×0.25, FOV kick ×0.5, shake ×0. Coût impl ~2h. Décision creative-director post-review r1 2026-04-21. |
| Auto-correction pitch au respawn (remettre à 0) vs préserver ? | ux-designer | **Résolu r1 post-review** | **Préserver pitch ET yaw** (Ghostrunner approach). Aligné Pillar 3 (die-retry sous 2s, pas de réorientation). L'hybride précédent (yaw préservé, pitch reset=0) abandonné. Décision creative-director post-review r1 2026-04-21. |
| Exposer FOV slider dans les settings ? | ux-designer | Avant Menu System GDD | **Recommandé MVP** (post-review r1) — public hardcore Ghostrunner attend ce toggle, exclusion communautaire si absent. Range [80°, 100°]. Coût ~1h. À acter Menu GDD. |
| ADR-0002 Camera Scene Tree 3-tier (CameraArm → CameraEffects → Camera3D) | technical-director | Avant Sprint 1 | **Créé 2026-04-21 (Proposed)** — `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md`. Doit passer Accepted avant first Camera story. |
| Formule 5 aim_forward algèbre fausse (version r1) | systems-designer | **Résolu r1 post-review** | Remplacée par forme close trigonométrique. Version r1 (Basis manipulation) archivée. AC analytiquement vérifiable. |
| Clamp yaw_delta/pitch_delta magnitude par frame (anti-flick dégénéré) | gameplay-programmer | **Résolu r1 post-review** | `MAX_ROT_PER_FRAME = PI rad`. Ajouté Rule 2 + 3 + Tuning Knobs. |
| Cap shake_offset accumulation | systems-designer | **Résolu r1 post-review** | `MAX_SHAKE_MAGNITUDE = 0.2 rad` via `limit_length` post-injection. Ajouté Tuning Knobs. Rule 8 + Formula 4 à synchroniser en session séparée (concurrent process). |
| Cleanup signals au scene reload (éviter "Signal target was freed") | gameplay-programmer | **Résolu r2 post-review** | Rule 16 ajoutée : pattern `_exit_tree()` disconnect explicite. AC-CAM-63 (scene reload) + AC-CAM-64 (focus-loss) atomisés. |
| AC classification (Logic/Integration/Visual-Feel/Perf) + evidence paths + atomisation respawn | qa-lead | **Résolu r2 post-review** | Section Acceptance Criteria refondue sur standard Movement r3 — IDs `AC-CAM-NN`, tags `[Type — BLOCKING/ADVISORY] [Owner]`, evidence paths pour Visual/Feel, respawn atomisé en AC-CAM-40/41/42/43. |
| Lerp tilt/FOV framerate-aware vs exp damping framerate-indep | systems-designer | Sprint 1 polish | Variance ±20% sur 30→144 fps acceptée MVP (t_95 calculé exact 60 fps = 224 ms). Si dérive perçue à 144 fps, refactor `1 - exp(-k_τ * delta)`. Dette technique. |
| Instrumentation ring buffer latence Camera (pattern Input GDD) | gameplay-programmer | Sprint 1 impl | Spec AC-CAM-80 + AC-CAM-81 ajoutés r2 (ring buffer 240 / 1000 samples). Impl reste à faire dès Camera story Sprint 1. |
| Crosshair vs aim_forward roll-corrigé pendant wall-run tilt | hud-system + ux-designer | Avant HUD GDD | **Reporté HUD GDD** — découplage documenté (crosshair centre écran HUD-owned, aim_forward Camera-owned). Trois options (projeter / décoratif / repenser) à trancher au HUD. |
| Head-bob optionnel au gameplay : à reconsidérer post-MVP ? | game-designer | Playtest MVP | Attendre feedback playtest. Si aucun joueur ne le demande, laisser `false` forever. |
| Weapon sway (katana viewmodel) : même question | game-designer | Playtest MVP | Idem head-bob. Probablement jamais activé. |
| Mouse smoothing comme option accessibility : séparé ou avec "reduce motion" ? | accessibility-specialist | Tier 3 | Recommandation : option séparée, default OFF, avertissement UX "ajoute latence". |
| Shake système : s'étend à hit katana (post-MVP) ? | systems-designer | Player Combat GDD | L'infrastructure est prête (`add_shake`). Décision au GDD Combat. |
| Support gamepad right-stick : mappé vers `mouse_motion` simulé ou distinct ? | gameplay-programmer | Tier 2 | Recommandation : convertir right-stick en delta simulé, sensitivity séparée (`gamepad_look_sensitivity`). Pas MVP. |
| Camera3D.fov assignation frame-per-frame stable sur Godot 4.6 autres plateformes ? | godot-specialist | Sprint 1 | Prototype macOS Metal OK. À re-vérifier sur Windows DX12 + Linux Vulkan. Flag MEDIUM risk. |
