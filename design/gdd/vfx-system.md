# VFX System

> **Status**: In Design (r1 — solo auto-approve 2026-05-04)
> **Author**: Martin + game-designer + art-director + technical-artist
> **Last Updated**: 2026-05-04
> **Implements Pillar**: Pillar 2 (LA PROGRESSION SE VOIT) primaire — les decals racontent l'histoire de chaque run ; Pillar 1 (FLOW AVANT TOUT) garde-fou — zéro frame drop VFX, zéro flash > 3 Hz, zéro alloc runtime hot path
> **Depends on**: Player Combat (signals `swing_started`, `swing_ended`, `multi_kill`), Enemy System (`enemy_killed(enemy, position)` SYNC), Camera System (`died`/`respawned` signals, `reduce_motion` mult via AccessibilityService), AccessibilityService (`reduce_flash`, `reduce_motion` pull — ADR-0015), Game State Manager (visibility gating — ADR-0007)
> **Depended on by**: aucun (couche présentation pure — terminal aval)
> **Governing ADRs**: ADR-0001 (Physics Rate 60 Hz + Jolt), ADR-0007 (GSM autorité pause/time_scale), ADR-0009 (Audio System pool exclusive — pattern référence), ADR-0015 (AccessibilityService — reduce_flash/reduce_motion)
> **Migration note (AC-CMB-42)**: Le plafond de decals par room (`MAX_DECALS_PER_ROOM`) était réservé par Combat GDD (AC-CMB-42 "décal cap à définir par le VFX System GDD"). Ce GDD est la résolution : l'ownership est ici, la valeur est `32` (R-VFX-4), et les Acceptance Criteria AC-VFX-13/AC-VFX-14 remplacent AC-CMB-42 comme source de vérité. Combat GDD peut retirer AC-CMB-42 lors de sa prochaine révision.

---

## Overview

Le VFX System est un autoload Godot 4.6 (`VFXSystem`) qui orchestre toutes les effets visuels non-UI du jeu : flash de kill, splash sang, decals de sang sur les surfaces, trail katana, overlay de mort, et flash respawn. Il est exclusivement consommateur — il ne mute aucun état gameplay, n'émet aucun signal, et ne connaît pas l'existence des systèmes qu'il sert. Il consomme les signals Combat (`swing_started`, `swing_ended`, `multi_kill`), Enemy (`enemy_killed(enemy, position)`), Camera (`died`, `respawned`), et Game State Manager (`state_changed`). Toutes les ressources particle sont pré-allouées au boot (pool zero-alloc) — aucun `GPUParticles3D.new()` ni `Decal.new()` à runtime. La palette respecte Chrome Zen : rouge sang désaturé `#C8232C` sur fond achromatique, shaders flat sans PBR. `reduce_flash` et `reduce_motion` sont pullés depuis `AccessibilityService` (ADR-0015) au boot et mis à jour live via signal `settings_changed`. La visibilité du système est gouvernée par `GameStateManager` — VFX est actif en `PLAYING` et `RESPAWNING`, gelé en `MENU` et `PAUSED`.

> **Quick reference** — Layer: `Presentation` · Priority: `MVP` · Key deps: `Enemy System (enemy_killed SYNC), Player Combat (swing_started/ended/multi_kill), Camera System (died/respawned, reduce_motion), Game State Manager (state_changed), AccessibilityService (reduce_flash/reduce_motion pull)` · Consumed by: aucun (terminal aval).

---

## Player Fantasy

> **North Star** : *"Le sang gicle court, sec, désaturé. La salle se ride à peine — c'est le mouvement du joueur qui peint, pas l'effet qui s'étale."*

Le VFX System sert **Pillar 2 — La progression se voit** par accumulation : les decals de sang qui restent sur les murs et le sol sont la mémoire physique de chaque run. Quand le joueur revient dans une salle après un respawn, il voit les traces du combat précédent — la salle lui rappelle silencieusement qu'il a déjà été là, qu'il a déjà failli. La progression est écrite dans la géométrie.

Il sert **Pillar 1 — Flow avant tout** par soustraction radicale : pas de slow-motion VFX additionnel au kill (le slow-mo est owned par Combat seul), pas d'effet persistant à l'écran pendant la course, pas de particules qui subsistent plus de 400 ms. Le kill flash blanc est bref (80 ms max) et précis — une note, pas un accord. L'anti-référence est Shadow Warrior 3 ou DOOM Eternal avec leurs glory kills plein-écran qui brisent le flow pour célébrer le kill. Ici, le kill n'est pas célébré — il est constaté.

**Références positives** :
- *Mirror's Edge* — économie de couleur stricte, le rouge n'apparaît que quand c'est mécanique
- *Hotline Miami* — le sang est décoration staccato, jamais spectacle (désaturé, plat, sans glow)
- *Ghostrunner* — trail lame discret, vitesse lisible sans persistance longue

**Mots attendus dans les verbatims playtest** : "court", "sec", "désaturé", "percussif", "propre"

**Mots BANNIS dans les verbatims playtest** : "spectaculaire", "satisfaisant", "juteux", "gore", "flashy", "impressionnant"

Si un playtester décrit les effets de kill avec des adjectifs de récompense cathartique (satisfaction, gore, satisfying) plutôt que des adjectifs rythmiques (staccato, net, sec), le calibrage doit être atténué.

---

## Detailed Design

### Core Rules

**R-VFX-1 — Autoload pool exclusive, instanciation interdite hors VFXSystem**

`VFXSystem` est le seul propriétaire de tous les nodes VFX runtime (`GPUParticles3D`, `Decal`, `MeshInstance3D` trail, `CanvasLayer` flash overlay). Aucun système consumer ne crée de node VFX directement. L'API publique expose des verbes haut niveau (`VFXSystem.play_kill_at(position)`, `VFXSystem.start_katana_trail()`, `VFXSystem.stop_katana_trail()`, `VFXSystem.flash_kill()`, `VFXSystem.flash_death()`, `VFXSystem.flash_respawn()`). **Forbidden pattern (lint CI)** : `GPUParticles3D.new()`, `Decal.new()`, `MeshInstance3D.new()` hors `src/core/vfx_system.gd`.

**R-VFX-2 — Pool pré-allouée au boot, zéro alloc runtime hot path**

Au `_ready()`, VFXSystem pré-alloue et ajoute à la scene tree :
- `BLOOD_PARTICLE_POOL_SIZE = 8` nodes `GPUParticles3D` sang (round-robin par index `_blood_idx`)
- `DECAL_POOL_SIZE = MAX_DECALS_PER_ROOM × 2 = 64` nodes `Decal` (LRU ring buffer — voir Formula 1)
- `KATANA_TRAIL_MESH = 1` node `MeshInstance3D` trail katana (activé/désactivé)
- `1` node `CanvasLayer` flash overlay avec `ColorRect` enfant

Toutes les dimensions et couleurs sont pré-configurées au boot depuis `vfx_config.tres`. Aucun `*.new()` dans `_physics_process`, `_process`, ni les handlers signal. **Exception lint** : `# lint-vfx-pool-ok: <raison>` accepté sur ligne pour cas pathologique audité.

**R-VFX-3 — Signal consumer CONNECT_DEFERRED par défaut**

Tous les handlers VFX sur signaux amont (`_on_enemy_killed`, `_on_swing_started`, `_on_swing_ended`, `_on_multi_kill`, `_on_state_changed`) connectent avec `CONNECT_DEFERRED` — cohérent ADR-0009 D-4 (instanciation GPUParticles + Decal = opérations lourdes > 256 B alloc, > 0.5 ms). **Exception** : `_on_enemy_killed` peut garder SYNC si le flash blanc frame-precise est requis (à valider playtest — si le retard d'une frame ~16 ms est imperceptible, CONNECT_DEFERRED préféré par défaut).

**R-VFX-4 — Decal cap par room : MAX_DECALS_PER_ROOM = 32 (LRU)**

Le pool de Decals décrit en R-VFX-2 est divisé en deux sous-pools de 32 : un slot actif courant, un buffer en attente. Quand le nombre de decals actifs dans la room courante atteint `MAX_DECALS_PER_ROOM = 32`, le decal le plus ancien (index ring buffer le plus vieux — LRU) est recyclé pour le nouveau. Aucun decal n'est jamais détruit et recréé (`Decal.new()` interdit R-VFX-1) — le node existe en permanence dans la pool, repositionné et réactivé. **Résolution de AC-CMB-42** : Combat GDD réservait ce plafond comme TBD ; il est ici figé à 32 (voir Formulas Section, Formula 1).

**R-VFX-5 — Flash blanc kill : durée courte, reset au respawn**

Au `enemy_killed`, un flash blanc 2D (`ColorRect` full-screen blanc sur `CanvasLayer`) s'affiche pendant `FLASH_KILL_DURATION_MS = 80 ms` wall-clock exact. La durée est comptée via `Time.get_ticks_msec()` dans `_process` (pas Tween — cohérent ADR-0009 D-3 pattern wall-clock). Si `reduce_flash == true` (ADR-0015), le flash blanc est remplacé par un fondu gris neutre `#A0A0A0` à `FLASH_BRIGHTNESS = DEFAULT × flash_mult` (voir Formulas Section, Formula 2) — compliance WCAG 2.3.1.

**R-VFX-6 — Flash mort : overlay rouge, résolu par Camera System**

L'overlay rouge de mort (fondu rouge plein-écran `Color(0.4, 0, 0, 0.6)`) est **owned par Camera System** (Camera GDD Section UI Requirements, overlay `CanvasLayer` child Camera). VFX System ne re-implémente pas cet overlay. Il peut émettre une notification interne via `play_death_vfx_at(position)` pour des particules positionnelles de mort (version Tier 2+), mais le full-screen rouge reste Camera territory. **Interdit** : VFX System ne crée pas de `CanvasLayer` rouge concurrent.

**R-VFX-7 — Trail katana : activé pendant swing_started → swing_ended uniquement**

Le trail katana est un `MeshInstance3D` (trail mesh dynamique ou `ImmediateMesh` mis à jour chaque frame) activé au signal `swing_started(direction)` et désactivé au signal `swing_ended()`. La géométrie du trail suit `CameraSystem.aim_forward` via référence passée dans `swing_started`. Le trail n'est PAS un `GPUParticles3D` (trop coûteux en draw calls pour un usage 2.5 swings/s — un mesh dynamique direct est préférable). Couleur : blanc cassé `#E8E8E0`, opacity max `0.7`, fade-out exponentiel 100 ms.

**R-VFX-8 — Splash sang : cone 30°, 6 particles, désaturé**

Au `enemy_killed(enemy, position)`, VFXSystem prend le prochain slot `GPUParticles3D` du pool (round-robin R-VFX-2) et le repositionne à `position`. Le node lance un burst d'émission one-shot : `BLOOD_SPURT_PARTICLE_COUNT = 6` particules en cone 30° depuis `position` dirigé vers le joueur. Chaque particule : couleur `#C8232C` (rouge sang désaturé 60%), taille 0.015 m², lifetime `PARTICLE_LIFETIME_MS = 400 ms`, fade-out linéaire opacité 1.0 → 0.0. Flat shader, zéro normal map, zéro PBR.

**R-VFX-9 — Decal sang : projeté sur surface après kill**

Simultanément au splash (R-VFX-8), un `Decal` est sorti du pool ring buffer (LRU R-VFX-4), repositionné à `position`, et orienté vers la surface la plus proche via `PhysicsDirectSpaceState3D.intersect_ray` depuis `position` vers le sol/mur le plus proche (ray distance max `DECAL_RAYCAST_MAX_DISTANCE = 3.0 m`). Si aucune surface trouvée, skip decal (pas de crash). Decal texture : quad plat `#C8232C` opacité `0.7 max`, radius `DECAL_SIZE = 0.6 m`. Flat shader, zéro normal projection.

**R-VFX-10 — Multi-kill : burst VFX additif, pas multiplicatif**

Au signal `multi_kill(count)` (Combat GDD Rule 13 — émis après chaque ensemble de kills du même swing), VFX ajoute `(count - 1)` particules supplémentaires sur chaque position kill enregistrée dans le swing courant. Le flash blanc n'est pas répété (déjà déclenché au premier `enemy_killed`). Le decal est placé à chaque position kill individuellement (count decals distincts). Le trail katana reste actif jusqu'à `swing_ended`.

**R-VFX-11 — reduce_motion : atténuation des effets de mouvement caméra**

Si `AccessibilityService.reduce_motion == true` (ADR-0015), les multiplicateurs suivants s'appliquent (cohérents Camera GDD Rule 14 — tilt × 0.25, FOV pulse × 0.5, shake × 0) :
- Trail katana opacity max : `× REDUCE_MOTION_TRAIL_MULT` (défaut knob `0.5`)
- Splash sang cone amplitude : `× REDUCE_MOTION_PARTICLE_ANGLE_MULT` (défaut knob `0.5`)
- Les effets 2D (flash kill, flash respawn) sont inchangés par `reduce_motion` (ils ne génèrent pas de motion perçue)

**R-VFX-12 — GSM visibility gating**

VFXSystem observe `GameStateManager.state_changed` (CONNECT_DEFERRED) :
- États `PLAYING`, `RESPAWNING` : VFX actif (particles, flash, trail)
- États `MENU`, `PAUSED`, `BOSS_DEFEATED` : particles en cours freeze (via `GPUParticles3D.emitting = false` + `process_mode = PROCESS_MODE_DISABLED`) ; flash overlay masqué immédiatement ; trail désactivé
- Au retour à `PLAYING` depuis `PAUSED` : particles remis à `PROCESS_MODE_INHERIT`, trail reprend en Idle (pas de trail orphelin au résumé)

**R-VFX-13 — Zéro VFX full-screen flash > 3 Hz (WCAG 2.3.1 compliance)**

La fréquence maximale de flash plein-écran (flash blanc kill + flash respawn) est limitée structurellement par `ATTACK_COOLDOWN_MS = 400 ms` (Combat GDD Rule 3) et `RESPAWN_DELAY_MS = 50 ms` (Movement). En scénario de kills multiples consécutifs maximal : 2.5 swings/s × 1 flash/swing = 2.5 Hz < 3 Hz limite WCAG 2.3.1. **Garde-code** : VFXSystem maintient `_flash_last_msec: int` et refuse les flashs supplémentaires si `Time.get_ticks_msec() - _flash_last_msec < FLASH_MIN_INTERVAL_MS = 333 ms` (3 Hz plancher). Aucun contournement possible via burst multi-kill (R-VFX-10 ne génère pas de flash supplémentaire).

**R-VFX-14 — Outbound-zero : VFX ne mute aucun état amont**

VFX System ne modifie jamais `enemy` ni `player` via ses handlers. Il ne stocke pas de référence Node aux enemies ou au player (seulement les positions `Vector3` issues des signaux). Il n'émet aucun signal observable par d'autres systèmes. C'est un terminal pur.

**R-VFX-15 — Flash respawn : bref, non-rouge**

Au signal `respawned(position)` (Camera GDD, relay depuis Movement), VFX émet un flash blanc 2D `FLASH_RESPAWN_DURATION_MS = 50 ms` via le même `CanvasLayer` overlay. La couleur est blanc pur `#FFFFFF` (distinct du rouge mort Camera). Si `reduce_flash == true`, le flash respawn est supprimé entièrement (pas de substitut gris — le respawn est assez court pour être safe sans feedback flash). L'overlay rouge mort Camera s'éteint simultanément (owned Camera, pas VFX).

**R-VFX-16 — Draw calls VFX < 50 par frame**

Budget explicite : tous les nodes VFX actifs simultanément (trail mesh 1 draw call, particles 8 × 1 draw call, decals 32 × 1 draw call, flash overlay 1 draw call) = max 42 draw calls. Sous le sous-budget VFX 50. Le budget total projet est < 500 draw calls/frame (technical-preferences.md). Les particules sang partagent un `ShaderMaterial` instance unique (pas N matériaux distincts).

---

### États et Transitions

| Flag | Valeur | Déclencheur | Effet |
|---|---|---|---|
| `_reduce_flash` | `bool` | `AccessibilityService.settings_changed` | Flash blanc → gris neutre (R-VFX-5) ou supprimé (R-VFX-15) |
| `_reduce_motion` | `bool` | `AccessibilityService.settings_changed` | Trail + particle angle atténués (R-VFX-11) |
| `_is_active` | `bool` | `GameStateManager.state_changed` | Toutes opérations VFX gated (R-VFX-12) |
| `_trail_active` | `bool` | `swing_started` / `swing_ended` | Trail mesh activé/désactivé |
| `_flash_kill_active` | `bool` | `enemy_killed` + `_flash_last_msec` garde | Flash blanc 80 ms actif |
| `_flash_respawn_active` | `bool` | `respawned` signal | Flash blanc 50 ms actif |

---

### Interactions avec les autres systèmes

| Système | Direction | Nature | Interface consommée |
|---|---|---|---|
| **Enemy System** | Upstream → VFX | Hard (source kill) | Signal `enemy_killed(enemy: Node, position: Vector3)` SYNC (ADR-0005 r7 OQ-ENM-1 — Enemy émet, VFX consume) |
| **Player Combat** | Upstream → VFX | Soft | Signals `swing_started(direction: Vector3)`, `swing_ended()`, `multi_kill(count: int)` |
| **Camera System** | Upstream → VFX (soft) | Soft | Signals `died()`, `respawned(position)` ; overlay rouge mort **owned par Camera**, pas VFX |
| **AccessibilityService** | Upstream → VFX | Soft pull | `AccessibilityService.reduce_flash: bool`, `AccessibilityService.reduce_motion: bool` (pull au `_ready()`, live via `settings_changed`) |
| **Game State Manager** | Upstream → VFX | Soft | Signal `state_changed(new_state)` pour visibility gating |
| **Audio System** | Coordination (zero code coupling) | Passif | Synchronisation rythmique kill staccato par proximité temporelle des events — zéro API directe VFX↔Audio |
| **Downstream** | — | — | Aucun — terminal |

---

## Formulas

### Formula 1 — Decal cap par room (LRU ring buffer)

```
Soit D = nombre de decals actifs dans la room courante
     MAX = MAX_DECALS_PER_ROOM = 32
     POOL = DECAL_POOL_SIZE = 64

Si D < MAX :
    slot = _decal_ring_buffer[(_decal_write_head) mod POOL]
    _decal_write_head += 1
    D += 1

Si D >= MAX (cap atteint) :
    slot = _decal_ring_buffer[(_decal_write_head) mod POOL]
    # slot recyclé : ancien decal le plus vieux (LRU par construction ring buffer)
    _decal_write_head += 1
    # D reste constant = MAX (un ancien sort, un nouveau entre)
```

**Variables** :

| Variable | Type | Range | Description |
|---|---|---|---|
| `MAX_DECALS_PER_ROOM` | int | [8, 64] | Plafond actif par room (défaut 32) |
| `DECAL_POOL_SIZE` | int | 2 × MAX | Total nodes Decal pré-alloués (toujours 2×MAX pour double-buffer) |
| `_decal_write_head` | int | [0, +∞) mod POOL | Index ring buffer, croissant — LRU par construction |
| `_room_decal_count` | int | [0, MAX] | Decals actifs room courante (reset à 0 sur `room_changed` event) |

**Output** : un slot `Decal` node réutilisé (jamais `Decal.new()`), repositionné à la position kill.

**Example** : 32 kills dans la salle S1 → 32 decals actifs (MAX atteint). 33ème kill → decal index 0 recyclé (le premier de la salle) → still 32 decals actifs.

**Reset sur room change** : à `level_room_changed` (Level System Tier 2+) ou `respawned` (si la room reset au respawn — MVP : pas de cross-room persistence, decals visibles uniquement pendant la run en cours dans la room). Open Question OQ-VFX-2 (voir fin du document).

---

### Formula 2 — Flash brightness reduce_flash

```
FLASH_BRIGHTNESS_R = DEFAULT_FLASH_BRIGHTNESS × flash_mult
FLASH_BRIGHTNESS_G = DEFAULT_FLASH_BRIGHTNESS × flash_mult
FLASH_BRIGHTNESS_B = DEFAULT_FLASH_BRIGHTNESS × flash_mult
```

Où :
- `DEFAULT_FLASH_BRIGHTNESS = 1.0` (blanc pur #FFFFFF, valeur RGB 1.0)
- `flash_mult = AccessibilityService.flash_mult` ∈ [0.0, 1.0]
  - `flash_mult = 1.0` : flash blanc standard (reduce_flash OFF)
  - `flash_mult = 0.0` : flash supprimé (reduce_flash max)
  - `flash_mult = 0.625` : flash gris neutre `#A0A0A0` (reduce_flash ON, défaut recommandé)

**Variables** :

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `DEFAULT_FLASH_BRIGHTNESS` | `B₀` | float | [0.5, 1.0] (tuning knob) | Luminosité flash standard |
| `flash_mult` | `m_f` | float | [0.0, 1.0] | Pull AccessibilityService — 1.0 = plein, 0.0 = supprimé |
| `FLASH_BRIGHTNESS` | `B_eff` | float | [0.0, B₀] | Luminosité effective du flash kill |

**Output** : `Color(B_eff, B_eff, B_eff, 1.0)` appliquée sur `ColorRect` overlay kill.

**WCAG 2.3.1** : avec `flash_mult ≤ 0.625`, le flash est en dessous du seuil photosensitif (luminosité ≤ 10 cd/m² sur écran standard 300 nit). Ref : WCAG 2.3.1 "No general flash and red flash thresholds".

**Example** : reduce_flash ON, `flash_mult = 0.625` → `Color(0.625, 0.625, 0.625, 1.0)` = gris neutre #A0A0A0.

---

### Formula 3 — Lifetime particule sang et fade-out linéaire

```
opacity(t) = 1.0 - (t / PARTICLE_LIFETIME_S)
             pour t ∈ [0, PARTICLE_LIFETIME_S]

PARTICLE_LIFETIME_S = PARTICLE_LIFETIME_MS / 1000.0
```

**Variables** :

| Variable | Symbole | Type | Range | Description |
|---|---|---|---|---|
| `PARTICLE_LIFETIME_MS` | `T_p` | int | [200, 800] ms | Lifetime total d'une particule sang |
| `t` | — | float | [0, T_p/1000] s | Temps écoulé depuis émission |
| `opacity(t)` | — | float | [0.0, 1.0] | Opacité linéaire décroissante |

**Output range** : `opacity ∈ [1.0, 0.0]`, linéaire — courbe volontairement non easing (caractère brut/staccato Chrome Zen).

**Example** : `PARTICLE_LIFETIME_MS = 400` → particule disparaît en 400 ms. À t=200 ms : `opacity = 1 - (0.2 / 0.4) = 0.5`.

**reduce_motion note** : `PARTICLE_LIFETIME_MS` non réduit par reduce_motion (c'est la durée, pas la magnitude du mouvement). Si un futur playtest révèle que les particules sont perçues comme du mouvement perturbateur, introduire `PARTICLE_LIFETIME_REDUCE_MOTION_MULT ∈ [0.25, 1.0]` via tuning knob. Non implémenté r1.

---

## Edge Cases

**EC-VFX-1 — MAX_DECALS_PER_ROOM atteint pendant burst kill multi-enemy**

Scénario : 3 enemies tués dans le même swing (`multi_kill(3)`) alors que `_room_decal_count == 30` (MAX=32). VFX place 2 decals (slots 31 et 32), puis le 3ème déclenche LRU : le decal le plus ancien de la salle est recyclé. Les 3 decals kill apparaissent tous (2 nouveaux + 1 recyclé repositionné). `_room_decal_count` reste à 32. Aucun crash, aucun skip decal.

**EC-VFX-2 — reduce_flash ON pendant slow-mo Combat (AC-CMB-19)**

Scénario : `reduce_flash == true` + `enemy_killed` déclenche simultanément `Engine.time_scale = 0.3` (Combat Rule 13). Le flash gris neutre `FLASH_BRIGHTNESS × flash_mult = 0.625` s'affiche pendant `FLASH_KILL_DURATION_MS` wall-clock (pas Time.scale-dépendant — mesuré via `Time.get_ticks_msec()` identique à ADR-0009 D-3 pattern). Le slow-mo n'allonge pas le flash. Compliance WCAG 2.3.1 maintenue.

**EC-VFX-3 — Mort pendant decal raycast en cours**

Scénario : `enemy_killed` déclenche un `intersect_ray` depuis la position kill vers la surface, puis `died()` arrive au tick suivant. L'`intersect_ray` est synchrone dans `_physics_process` (pas async) — il complète dans le même tick. Si le résultat arrive après le `died()` (impossible en Godot synchronous physics), la garde `_is_active == false` après `state_changed(RESPAWNING)` skip le placement decal silencieusement.

**EC-VFX-4 — Respawn pendant blood spurt actif**

Scénario : `enemy_killed` lance un burst particule, puis `respawned(position)` arrive 200 ms après (pendant le lifetime 400 ms). Au `respawned` : toutes les `GPUParticles3D` du pool ont `emitting = false` + `restart()` appelé (reset one-shot). Les particules en cours disparaissent immédiatement. Aucune particule orpheline post-respawn. Le pool est propre pour le prochain kill.

**EC-VFX-5 — GSM transition vers MENU pendant trail katana actif**

Scénario : joueur ouvre le menu (`state_changed(MENU)`) pendant `swing_started` → `swing_ended` window. Garde R-VFX-12 : `_trail_active = false` immédiatement, `MeshInstance3D.visible = false`. Si `swing_ended` arrive après la transition menu (signal CONNECT_DEFERRED), il est ignoré (guard `_is_active == false`). Pas de trail orphelin à la réouverture du jeu.

**EC-VFX-6 — Flash kill déclenché plus de 3 fois en 1 seconde (theoretical burst)**

Scénario : 4 kills en 1 seconde (impossible avec `ATTACK_COOLDOWN_MS = 400 ms` standard, mais théoriquement possible en debug ou futur upgrade système). Garde R-VFX-13 : `_flash_last_msec` vérifié → si `< FLASH_MIN_INTERVAL_MS = 333 ms`, flash skip. Log `push_warning("VFX: flash rate guard triggered — skip flash kill")`. Aucun crash, conformité WCAG 2.3.1 maintenue.

**EC-VFX-7 — Decal raycast ne trouve aucune surface (kill dans le vide)**

Scénario : ennemi tué sur un étage partiellement ouvert (geometry gap), l'`intersect_ray` vers le sol ne retourne rien dans `DECAL_RAYCAST_MAX_DISTANCE = 3.0 m`. Comportement : skip decal silencieusement. Particules splash restent (elles ne nécessitent pas de surface). Log debug : `push_warning("VFX: no surface found for decal at %s" % position)`.

**EC-VFX-8 — AccessibilityService non initialisé au boot (race condition)**

Scénario : `VFXSystem._ready()` est appelé avant `AccessibilityService._ready()` (ordering autoload incorrect). Garde : VFX pull `AccessibilityService.reduce_flash` avec guard `if is_instance_valid(AccessibilityService)`. Si invalide, apply defaults (`reduce_flash = false`, `flash_mult = 1.0`). Au signal `settings_changed` suivant, les valeurs sont mises à jour live. Note : ADR-0015 impose l'ordering `AccessibilityService` avant les consumers gameplay — ce cas ne devrait pas survenir en production (ordering Project Settings). La garde est défensive.

**EC-VFX-9 — Multi-kill (count=3) avec only 2 slots pool disponibles**

Scénario : pool sang (`BLOOD_PARTICLE_POOL_SIZE = 8`) saturé — 6 slots en cours de playback, 2 slots libres, 3 kills simultanés. VFX place particles sur les 2 slots libres, puis round-robin `stop()` → `restart()` sur le slot le plus ancien actif pour le 3ème. Le sample en cours est interrompu — comportement acceptable (le burst le plus récent prime). Log `push_warning` si saturation détectée.

**EC-VFX-10 — Flash respawn si reduce_flash ON**

Scénario : `reduce_flash == true` + `respawned` signal reçu. Per R-VFX-15 : flash respawn supprimé entièrement (aucun substitut gris — durée 50 ms trop courte pour être perceptible comme flash). L'overlay rouge mort Camera s'éteint normalement (owned Camera, pas VFX). Aucun feedback flash VFX. Comportement documenté et safe.

---

## Dependencies

### Upstream (VFX consomme)

| Système | Direction | Nature | Interface consommée | Bidirectionnel vérifié |
|---|---|---|---|---|
| **Enemy System** (APPROVED r2) | Hard upstream | Hard | Signal `enemy_killed(enemy: Node, position: Vector3)` SYNC — source autoritative kill (ADR-0005 r7 OQ-ENM-1) | Enemy GDD r2 Rule 11.c liste VFX comme consumer. ✅ |
| **Player Combat System** (APPROVED r7) | Soft upstream | Soft | Signals `swing_started(direction: Vector3)`, `swing_ended()`, `multi_kill(count: int)` (Combat GDD Published API) | Combat GDD Dependencies table liste VFX GDD DOIT connecter ces signals. ✅ |
| **Camera System** | Soft upstream | Soft | Signals `died()`, `respawned(position)` — relay depuis Movement. Note : l'overlay rouge mort reste **owned Camera** (R-VFX-6) | Camera GDD Dependencies liste VFX comme consumer signals Camera. ✅ |
| **AccessibilityService** (ADR-0015) | Soft upstream | Soft pull | `reduce_flash: bool`, `flash_mult: float`, `reduce_motion: bool` — pull boot + live via `settings_changed` | ADR-0015 "Enables" liste "Future VFX flash mult". ✅ |
| **Game State Manager** (APPROVED) | Soft upstream | Soft | Signal `state_changed(new_state: GameState)`, getter `get_current_state()` (pull au boot) | GSM GDD liste VFX comme consumer downstream. ✅ |
| **Level System** (Tier 2+) | Optional soft | Future | Signal `room_changed(room_id)` pour reset `_room_decal_count` cross-room. MVP : respawn reset. OQ-VFX-2. | Non designé encore — dépendance future documentée. |

### Downstream (aucun)

VFX System est terminal. Il ne fournit aucune interface à d'autres systèmes. Aucun signal émis, aucune propriété exposée, aucun getter consommé par un amont.

### Dépendances ADR

| ADR | Contrainte sur VFX |
|---|---|
| **ADR-0001** (Physics Rate 60 Hz + Jolt) | Wall-clock flash timer via `Time.get_ticks_msec()` dans `_physics_process` — pas Tween scaled. |
| **ADR-0007** (GSM autorité) | VFX observe `state_changed` CONNECT_DEFERRED pour visibility gating (R-VFX-12). |
| **ADR-0009** (Audio System — pattern pool) | Pattern pool pre-alloc + API publique exclusive est le même pattern que Audio System. VFX applique D-2 (pool exclusive) + D-3 (wall-clock fades) en analog. |
| **ADR-0015** (AccessibilityService) | VFX pull `reduce_flash` / `reduce_motion` via `AccessibilityService` (single source of truth). Pas de lecture directe `OS.is_reduce_motion_enabled()` dans VFX — délégué au Service. |

### Exclusions explicites

- VFX ne dépend pas du **Save/Load System** — aucun état VFX persisté
- VFX ne dépend pas du **Credit Economy** — les kills sont source Enemy, pas Credit
- VFX ne dépend pas du **Audio System** (synchronisation par proximité temporelle, zéro API directe)
- VFX ne dépend pas du **HUD System** — aucun UI direct

---

## Tuning Knobs

Tous les knobs vivent dans `assets/data/vfx_config.tres` (Resource typé). Aucune valeur hardcodée en code. Chargés à `_ready()` de VFXSystem.

| Knob | Catégorie | Défaut | Safe Range | Effet si augmenté | Effet si diminué |
|---|---|---|---|---|---|
| `MAX_DECALS_PER_ROOM` | Gate | `32` | [8, 64] | Plus de traces visuelles, plus de draw calls | Decals LRU recycling plus agressif, mémoire visuelle plus courte |
| `BLOOD_SPURT_PARTICLE_COUNT` | Feel | `6` | [0, 16] | Plus de particules, effet plus spectaculaire (risque "juteux") | Moins de particles, effet plus minimaliste |
| `BLOOD_PARTICLE_POOL_SIZE` | Curve | `8` | [4, 16] | Moins de saturation pool (plus de kills simultanés sans drop) | Pool sature plus vite (arrêt prématuré blood ambiance) |
| `FLASH_KILL_DURATION_MS` | Feel | `80` | [40, 150] ms | Flash plus long, plus visible mais risque motion sickness | Flash plus bref, risque d'être imperceptible |
| `FLASH_RESPAWN_DURATION_MS` | Feel | `50` | [30, 80] ms | Flash respawn plus long | Flash trop court = invisible |
| `FLASH_MIN_INTERVAL_MS` | Gate | `333` | [333, 500] ms | Fréquence flash max plus basse (plus safe WCAG) | **Ne pas descendre sous 333 ms — limite WCAG 2.3.1 3 Hz** |
| `DEFAULT_FLASH_BRIGHTNESS` | Feel | `1.0` | [0.5, 1.0] | Flash plus blanc/intense | Flash atténué baseline |
| `PARTICLE_LIFETIME_MS` | Feel | `400` | [200, 800] ms | Particules plus longues à disparaître (risque "spectaculaire") | Particules plus brèves (effet plus staccato) |
| `DECAL_SIZE` | Feel | `0.6 m` | [0.3, 1.2] m | Taches de sang plus grandes | Taches discrètes |
| `DECAL_RAYCAST_MAX_DISTANCE` | Gate | `3.0 m` | [1.0, 5.0] m | Raycast plus long (trouve des surfaces plus éloignées) | Raycast court (manque surfaces inclinées) |
| `KATANA_TRAIL_OPACITY_MAX` | Feel | `0.7` | [0.3, 1.0] | Trail plus visible | Trail discret |
| `BLOOD_CONE_ANGLE_DEG` | Feel | `30°` | [15°, 60°] | Cone élargi, splash plus diffus | Cone serré, jet directionnel |
| `REDUCE_MOTION_TRAIL_MULT` | Curve | `0.5` | [0.0, 1.0] | Trail moins atténué en reduce_motion | Trail quasiment invisible en reduce_motion |
| `REDUCE_MOTION_PARTICLE_ANGLE_MULT` | Curve | `0.5` | [0.0, 1.0] | Angle cone moins réduit en reduce_motion | Cone minimal en reduce_motion |
| `SLOW_MO_VFX_INTENSITY_MULT` | Curve | `1.5` | [1.0, 2.5] | Particules plus intenses sous slow-mo (accentue le beat) | Particules identiques hors/sous slow-mo |

---

## Acceptance Criteria

Format Given-When-Then. AC BLOCKING = gate implémentation. AC ADVISORY = gate playtest.

### Decal Cap (migration AC-CMB-42)

**AC-VFX-01** — BLOCKING
Given: La room courante a exactement `MAX_DECALS_PER_ROOM = 32` decals actifs
When: Un 33ème `enemy_killed` est reçu
Then: Le decal le plus ancien (ring buffer LRU) est recyclé et repositionné à la nouvelle position ; `_room_decal_count` reste à 32 ; aucun `Decal.new()` n'est appelé

**AC-VFX-02** — BLOCKING
Given: Un `enemy_killed` est reçu dans une room avec < 32 decals actifs
When: Le raycast vers la surface réussit
Then: Un decal `#C8232C` opacity 0.7, radius 0.6 m apparaît sur la surface ; `_room_decal_count` s'incrémente de 1

**AC-VFX-03** — BLOCKING
Given: Le raycast decal ne trouve aucune surface dans `DECAL_RAYCAST_MAX_DISTANCE = 3.0 m`
When: `enemy_killed` est reçu
Then: Le decal est skip silencieusement ; le blood spurt particule se joue normalement ; aucun crash

### Zero-Alloc Hot Path

**AC-VFX-04** — BLOCKING
Given: Un profile mémoire GdUnit4 headless est exécuté sur 60 secondes de gameplay simulé avec 30 kills
When: Le système VFX est actif
Then: `MEMORY_STATIC` delta sur 60 s < 16 KB (pas de `Decal.new()`, `GPUParticles3D.new()`, `MeshInstance3D.new()` dans les hot paths post-boot)

**AC-VFX-05** — BLOCKING
Given: Le code VFX est scanné par le lint statique CI
When: `grep -rE "GPUParticles3D\.new\(\)|Decal\.new\(\)|MeshInstance3D\.new\(\)" src/ | grep -v src/core/vfx_system.gd`
Then: Zéro match (aucune instanciation VFX hors `vfx_system.gd`)

### Flash Accessibility (WCAG 2.3.1)

**AC-VFX-06** — BLOCKING
Given: `AccessibilityService.reduce_flash == false` (défaut)
When: `enemy_killed` est reçu
Then: Un flash blanc `#FFFFFF` plein-écran de durée `FLASH_KILL_DURATION_MS = 80 ms` wall-clock s'affiche ; la durée ne varie pas avec `Engine.time_scale`

**AC-VFX-07** — BLOCKING (cite WCAG 2.3.1)
Given: `AccessibilityService.reduce_flash == true` (reduce_flash activé)
When: `enemy_killed` est reçu
Then: Le flash blanc est remplacé par un fondu gris neutre `Color(0.625, 0.625, 0.625, 1.0)` (#A0A0A0) de durée 80 ms ; jamais de blanc pur (#FFFFFF) ni de rouge en mode reduce_flash

**AC-VFX-08** — BLOCKING (cite WCAG 2.3.1 "3 Hz flash threshold")
Given: `FLASH_MIN_INTERVAL_MS = 333 ms` est configuré
When: VFXSystem reçoit 10 `enemy_killed` events en 1 seconde (via test unitaire inject)
Then: Le nombre de flashs rendus est ≤ 3 ; chaque flash supplémentaire dans la fenêtre 333 ms est skip silencieusement ; `push_warning` logué pour chaque skip

**AC-VFX-09** — BLOCKING
Given: `AccessibilityService.reduce_flash == true`
When: `respawned` signal reçu
Then: Zéro flash de tout type au respawn (ni blanc ni gris neutre) ; l'overlay rouge mort Camera s'éteint normalement (géré Camera, pas VFX)

### Draw Calls Budget

**AC-VFX-10** — BLOCKING
Given: Le jeu tourne avec 32 decals actifs + 8 blood particles actives + trail actif + flash overlay actif simultanément
When: Un frame est rendu
Then: Le nombre de draw calls VFX (mesuré via Godot Remote Debugger) est ≤ 50 ; le budget global frame est ≤ 500 draw calls

### Blood Spurt Particles

**AC-VFX-11** — BLOCKING
Given: `reduce_motion == false`
When: `enemy_killed(enemy, position)` reçu
Then: `BLOOD_SPURT_PARTICLE_COUNT = 6` particules couleur `#C8232C` en cone 30° depuis `position` s'émettent en one-shot ; lifetime 400 ms ; fade-out linéaire opacité 1.0 → 0.0 ; flat shader sans PBR

**AC-VFX-12** — BLOCKING
Given: `reduce_motion == true`
When: `enemy_killed` reçu
Then: Les particules s'émettent mais le cone angle est `30° × REDUCE_MOTION_PARTICLE_ANGLE_MULT = 15°` ; le count reste identique (6 particles) ; aucun mouvement camera VFX généré

### Trail Katana

**AC-VFX-13** — BLOCKING
Given: `swing_started(direction)` signal reçu
When: La fenêtre swing est active
Then: Le trail `MeshInstance3D` est visible, couleur `#E8E8E0`, opacity max 0.7 ; le trail suit `aim_forward` fourni par le signal

**AC-VFX-14** — BLOCKING
Given: `swing_ended()` signal reçu
When: La fenêtre swing se ferme
Then: Le trail opacity fade-out exponentiel 100 ms puis `visible = false` ; aucun trail persistant après swing_ended

**AC-VFX-15** — BLOCKING
Given: `state_changed(MENU)` reçu pendant swing_started → swing_ended window
When: GSM bascule en MENU
Then: Trail désactivé immédiatement (`visible = false`) ; `swing_ended` ultérieur ignoré (guard `_is_active == false`)

### GSM Visibility Gating

**AC-VFX-16** — BLOCKING
Given: `state_changed(PAUSED)` reçu pendant blood particles actives
When: GSM bascule en PAUSED
Then: `GPUParticles3D.emitting = false` + `process_mode = PROCESS_MODE_DISABLED` sur tous les slots pool actifs ; flash overlay masqué ; trail désactivé

**AC-VFX-17** — BLOCKING
Given: `state_changed(PLAYING)` reçu après PAUSED
When: GSM retour en PLAYING
Then: `GPUParticles3D.process_mode = PROCESS_MODE_INHERIT` restauré ; trail en Idle (pas de trail orphelin) ; flash overlay prêt pour prochain kill

### Multi-Kill

**AC-VFX-18** — BLOCKING
Given: `multi_kill(3)` reçu après 3 `enemy_killed` du même swing
When: Les positions de chaque kill sont enregistrées dans `_pending_kill_positions`
Then: 3 decals distincts placés (un par position) ; 3 blood spurts émis (round-robin pool) ; flash blanc unique (1 seul flash pour tout le swing, R-VFX-13 fréquence guard)

### Pool Saturation

**AC-VFX-19** — BLOCKING
Given: `BLOOD_PARTICLE_POOL_SIZE = 8` et 8 slots en cours de playback
When: Un 9ème `enemy_killed` arrive
Then: Le slot le plus ancien reçoit `stop()` puis `restart()` pour le nouveau kill ; `push_warning` logué ; aucun crash ; blood spurt visible sur le 9ème kill

### AccessibilityService Live Update

**AC-VFX-20** — BLOCKING
Given: Le jeu tourne avec `reduce_flash == false` (flash blanc actif)
When: `AccessibilityService.settings_changed` est émis avec `reduce_flash = true` mid-game
Then: Le prochain `enemy_killed` produit un flash gris `#A0A0A0` (pas blanc) ; la mise à jour est live (pas de redémarrage requis)

**AC-VFX-21** — BLOCKING
Given: `AccessibilityService` n'est pas encore initialisé quand `VFXSystem._ready()` s'exécute
When: VFX tente le pull initial `AccessibilityService.reduce_flash`
Then: Guard `is_instance_valid(AccessibilityService)` appliqué → defaults `reduce_flash = false`, `flash_mult = 1.0` ; pas de crash ; correction via `settings_changed` dès qu'AccessibilityService est prêt

### Respawn Reset

**AC-VFX-22** — BLOCKING
Given: Blood spurt particles actives (lifetime en cours)
When: `respawned(position)` signal reçu
Then: Tous les slots `GPUParticles3D` ont `emitting = false` + `restart()` appelé dans le même frame ; aucune particule orpheline post-respawn

### Outbound-Zero

**AC-VFX-23** — BLOCKING (lint statique)
Given: Le code `src/core/vfx_system.gd` et `src/gameplay/vfx/` est scanné
When: `grep -rE "emit_signal|\.emit\(" src/core/vfx_system.gd src/gameplay/vfx/`
Then: Zéro match (VFX n'émet aucun signal)

**AC-VFX-24** — BLOCKING
Given: Les handlers `_on_enemy_killed`, `_on_swing_started`, etc. sont exécutés
When: Inspection post-handler via unit test
Then: `enemy.position` et `player.global_position` ne sont pas mutés par VFX ; aucune propriété Enemy/Player/Combat n'est modifiée

### Slow-Mo Compatibility

**AC-VFX-25** — BLOCKING
Given: `Engine.time_scale = 0.3` (slow-mo Combat Rule 13) est actif
When: Flash kill VFX est déclenché
Then: La durée du flash est `FLASH_KILL_DURATION_MS = 80 ms` wall-clock (`Time.get_ticks_msec()`) — pas 80 ms × 0.3 = 24 ms ; le flash n'est pas allongé ni raccourci par time_scale

**AC-VFX-26** — BLOCKING
Given: `Engine.time_scale = 0.3` actif + `reduce_flash == true`
When: `enemy_killed` reçu
Then: Flash gris neutre `#A0A0A0` durée 80 ms wall-clock (identique reduce_flash OFF mais couleur atténuée) ; WCAG 2.3.1 compliance maintenue sous slow-mo

### Acceptance Criteria — Chrome Zen Palette

**AC-VFX-27** — BLOCKING (lint statique couleur)
Given: Les assets VFX `vfx_config.tres` sont inspectés
When: Les couleurs blood spurt et decal sont lues
Then: Blood spurt color = `#C8232C` (rouge sang désaturé 60%) ; decal color = `#C8232C` opacity ≤ 0.7 ; trail color = `#E8E8E0` (blanc cassé) ; aucun gradient, aucun shader PBR

### Acceptance Criteria — Visual/Feel Playtest

**AC-VFX-28** — ADVISORY (playtest panel ≥ 5 testeurs)
Given: Un panel de 5 testeurs joue 10 minutes de gameplay actif (combat room focus)
When: Ils sont interrogés sur les effets de kill avec des mots ouverts
Then: Le lexique attendu inclut : "court", "sec", "désaturé", "percussif" ; les mots BANNIS absents des verbatims : "spectaculaire", "satisfaisant", "juteux", "gore", "impressionnant"

**AC-VFX-29** — ADVISORY
Given: Un testeur termine une salle de 10 enemies
When: Il revient dans la salle après respawn
Then: Il reconnaît visuellement les traces de combat précédent (decals) et peut décrire la salle comme "marquée" ou "parcourue" sans tutoriel

### Acceptance Criteria — Combat-021 Coverage

**AC-VFX-30** — BLOCKING (résolution story combat-021 blocker)
Given: Le contrat VFX GDD pour Combat (Combat GDD Dependencies row "VFX & Feedback System") est vérifié
When: Le VFX GDD est reviewé contre les 4 obligations Combat GDD :
  1. Connecter en CONNECT_DEFERRED pour GPUParticles/décalques/flash
  2. Ne jamais muter `enemy` ou `player` via handlers
  3. Spawner le trail pendant `swing_started` → `swing_ended`
  4. Gérer flash blanc 50 ms + splash sang au `Enemy.enemy_killed`
Then: Chaque obligation est couverte par un AC numéroté : (1) R-VFX-3 + AC-VFX-23, (2) AC-VFX-24, (3) AC-VFX-13/14, (4) AC-VFX-06 + AC-VFX-11 — ownership clair, contrat rempli

---

## Visual / Audio Requirements

### Palette Chrome Zen (VFX)

| Élément | Couleur Hex | Usage | Contrainte |
|---|---|---|---|
| Blood spurt particles | `#C8232C` | Rouge sang désaturé 60% | Seule couleur warm dans la scène — ne pas saturer davantage |
| Decal sang | `#C8232C` opacity ≤ 0.7 | Tache sur surface | Opacity max 0.7 — au-dessus casse le minimalisme |
| Trail katana | `#E8E8E0` opacity ≤ 0.7 | Blanc cassé — appartient à Chrome | Pas de glow, pas de bloom additionnel |
| Flash kill | `#FFFFFF` (reduce_flash OFF) / `#A0A0A0` (ON) | Full-screen 2D | Blanc pur ou gris neutre uniquement — jamais de rouge |
| Flash respawn | `#FFFFFF` opacity 1.0 | Full-screen 2D 50 ms | Pop binaire — pas de lerp |

### Matériaux et Shaders

- **Flat unshaded shader** sur toutes les particules et decals (pas de `BaseMaterial3D` PBR)
- **Zéro normal map** sur les decals
- **Zéro gradient** dans les textures VFX (primitives flat + opacité uniquement)
- **Un seul `ShaderMaterial` instancié partagé** pour toutes les particules sang (pas N matériaux distincts — draw call budget R-VFX-16)
- **Decal geometry** : `Decal` node Godot 4.6 — texture projetée sur la surface, pas un quad world-space (évite la complexité d'orientation manuelle)

### Coordination art-director (à confirmer post-art-bible)

- Decal opacity max `0.7` : validé par règle Chrome Zen "le sang est la seule tache warm"
- Blood spurt 6 particles cone 30° : économique, identifiable, non-spectaculaire
- Lifetime 400 ms fade linéaire : staccato = pas de ease-out (ease-out donnerait une "résonance" qui prolonge émotionnellement le kill)
- Flash blanc 80 ms wall-clock : calibré pour passer sous le seuil perceptif de "récompense séparée" (études : < 100 ms = beat rythmique, > 200 ms = moment célébré)

### UI Requirements

N/A — VFX System n'a aucun élément UI direct. Les overlays 2D (flash kill, flash respawn) sont des `ColorRect` flat sur `CanvasLayer`, pas des elements UI interactifs. Le HUD System est un système séparé (`HUDSystem`). L'overlay rouge mort est owned par Camera System (R-VFX-6).

---

## Open Questions

**OQ-VFX-1 — Decal persistence cross-rooms via frame ou reset on room change ?**
MVP : decals visibles uniquement pendant la run en cours dans la room active. Quand `respawned` est reçu (reset checkpoint), `_room_decal_count = 0` et tous les decals du pool sont `visible = false`. Tier 2+ avec Level System signal `room_changed` : décider si les decals persistent cross-rooms (mémoire run longue) ou s'effacent à chaque transition. À trancher par Level System GDD lors de son design.

**OQ-VFX-2 — Multi-enemy kill : un blood spurt par ennemi ou un groupe poolé ?**
Implémentation actuelle (r1) : un blood spurt par ennemi (positions distinctes). En cas de 3 kills simultanés très proches, 3 spurts peuvent se superposer visuellement → effet "blob". Alternative : un seul spurt "groupe" à la position médiane des kills. Décision recommandée post-playtest : si le blob est perçu comme "spectaculaire", migrer vers spurt groupé Tier 2.

**OQ-VFX-3 — Trail katana : ImmediateMesh vs Trail3D (Godot 4.6) ?**
`Trail3D` est un node Godot 4.6 natif (post-cutoff LLM). À vérifier à l'implémentation : si `Trail3D` (ou `GpuParticles3D` avec trail shader) permet un rendu flat sans PBR, préférer l'API native. Sinon, `ImmediateMesh` mis à jour chaque frame. Impact : draw calls + complexité code. À décider par `lead-programmer` lors de Sprint 1 VFX.

**OQ-VFX-4 — Flash kill SYNC ou CONNECT_DEFERRED ?**
R-VFX-3 laisse ouverte la question : si le flash blanc doit être frame-precise avec le kill (même tick que `enemy_killed`), il faut SYNC. Si le retard d'un frame (~16 ms) est imperceptible, CONNECT_DEFERRED est préféré (cohérence ADR-0009 D-4). À valider par playtest : panel de testeurs avec `reduce_motion == false` — notent-ils un décalage perçu flash vs kill audio ?

**OQ-VFX-5 — Lentille VFX pour le boss final (Tier 3) ?**
Le boss final (Combat GDD Anti-Pillar note) a une barre de vie multi-hits. Le flash blanc sur chaque hit boss devrait probablement être atténué (pas 80 ms blanc pur × 5 hits = 400 ms de flash répété). À designer dans le Boss System GDD quand créé. VFX System n'anticipe pas ce cas r1 — `reduce_flash` WCAG guard `FLASH_MIN_INTERVAL_MS = 333 ms` protège structurellement contre le burst.

---

*VFX System r1 — 2026-05-04 — solo auto-approve. Décisions non-obviates : (1) ownership decal cap résolu ici (migration AC-CMB-42) ; (2) trail = MeshInstance3D pas GPUParticles (budget draw calls) ; (3) flash wall-clock via Time.get_ticks_msec() pas Tween (ADR-0009 D-3 pattern) ; (4) WCAG 2.3.1 3 Hz guard structurel via FLASH_MIN_INTERVAL_MS ; (5) AccessibilityService pull défensif avec is_instance_valid guard.*
