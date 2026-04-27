# ADR-0009: Audio System Architecture

## Status
Accepted 2026-04-27 + **r2 amendements 2026-04-27 Phase A audio GDD** (in scope sans nouveau cycle review — modifications surgical conformes mécanisme `audio.md` et patterns Godot natifs) :

- **D-1 amendement r2** : ajout sidechain compressor `AudioEffectCompressor` sur bus `MUSIC` feed depuis bus `COMBAT_KILL` (résout Couche 1 vs Couche 3 contradiction Audio GDD Player Fantasy via mécanisme, pas verbal). Configuration boot dans Migration Plan §3.
- **D-3 amendement r2** : ajout allowlist bus-level `pitch_scale_follows_time_scale: bool` per bus appliquée pendant `Engine.time_scale != 1.0` — `COMBAT_KILL=true`, `AMBIENCE=true`, autres `false` (préserve `MUSIC`/`SWING_ACTIVE`/`UI` invariants). Mapping pitch via Formula 5 Audio GDD r2 (`-2..-4 semitones` selon `time_scale`). Décision Martin D3 REOPEN tranchée 2026-04-27 — autoriser pitch shift identitaire HLM sur queue `COMBAT_KILL` + `AMBIENCE` sous slow-mo.

**Promotion 2026-04-27 r1 (historique)** : `/architecture-review` fresh session focused — verdict PASS pour promotion : 0 cross-ADR conflict vs ADR-0001/0002/0003/0005/0006/0007/0008/0011 (tous Accepted), Engine LOW risk (APIs `AudioStreamPlayer*`, `AudioServer.set_bus_volume_db`, `AudioListener3D` stables Godot 4.0+, 0 post-cutoff, 0 deprecated, 0 breaking 4.4-4.6 per `audio.md`), godot-specialist APPROVE WITH SUGGESTIONS r1 (4 LOW findings, 0 blocker — tous appliqués : (1) D-1 `AudioBuses` reformulé classe statique pure (PAS autoload) per mémoire `feedback_godot_class_name_autoload_collision.md`, (2) D-2 `play_2d` ajoute `push_warning` sur `is_playing()` saturation pool + note R-1, (3) D-3 ajoute note courbe perceptuelle dB acceptable swoosh ≤ 30 ms / switch obligatoire pour music crossfade futur, (4) Key Interface `AudioSystem` retire `class_name` collision + documente `process_priority=0`). Gap **G-7 RÉSOLU** — débloque story-020 Combat (BLOCKED) + Audio System GDD authoring (`/design-system audio-system`). 3 Verification Required (R-2 Camera3D listener auto, R-3 `pitch_scale` time_scale invariance, pool latency) déférés Sprint Audio per Migration Plan §4 (pattern précédent ADR-0006 Gaps 2/7/8 + ADR-0011 5 VC-LVL).

## Date
2026-04-27

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Audio |
| **Knowledge Risk** | LOW |
| **References Consulted** | `docs/engine-reference/godot/modules/audio.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None — `AudioStreamPlayer`, `AudioStreamPlayer3D`, `AudioServer.set_bus_volume_db()`, `AudioServer.get_bus_index()` stables Godot 4.0+. No audio-specific breaking changes en 4.4-4.6. |
| **Verification Required** | (1) Comportement `AudioStreamPlayer.pitch_scale` non-affecté par `Engine.time_scale` confirmé Godot 4.6 (Combat GDD §Rule 13) — vérifier empiriquement avant Sprint Audio. (2) `AudioListener3D` par défaut sur `Camera3D` actif (pas de `AudioListener3D` dédié à instancier — confirmer empiriquement). (3) Pool latency : confirmer que `AudioStreamPlayer.play()` sur pool pré-instancié n'introduit pas de hitch ≥ 1 frame. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Physics Rate 60 Hz — autorité simulation pour fades wall-clock dans `_physics_process`), ADR-0002 (Camera Scene Tree — `AudioListener3D` enfant Camera3D auto-current), ADR-0005 (Movement Signals — Audio consume `dash_started`, `wall_run_entered`, `attacked`, `died`, etc. en `CONNECT_DEFERRED`), ADR-0006 (Combat Tick Model — Audio consume `enemy_killed`/`multi_kill`/`swing_started`/`swing_ended`, contract `_get_time_msec` Callable injection partagé), ADR-0007 (Game State Manager — Audio fade out menu/pause), ADR-0011 (Level Scene — Audio reset/load par etage) |
| **Enables** | Audio System GDD (à créer post-ADR), Audio epic, AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02 (Combat → Audio contracts), futur Music ADR (transitions musicales contextuelles), futur Voice/VO ADR (post-MVP) |
| **Blocks** | Story-020 Combat (swoosh fade-out + multi-kill clac + ducking) actuellement Blocked, Audio epic création |
| **Ordering Note** | Doit être Accepted avant `/design-system audio-system` (GDD) puis `/create-epics audio-system`. Sprint 0 Technical Setup CRÉERA `default_bus_layout.tres` + autoload `AudioSystem` + helper static `AudioBuses` pour wire au boot — **non encore implémentés** au moment de la promotion ADR (cf. Migration Plan §1). Pattern précédent : ADR-0011 promu Accepted avec Sprint 1 implémentation différée. |

## Context

### Problem Statement

Le projet n'a pas encore d'architecture audio formelle. Combat GDD fige déjà
plusieurs contracts inline (Section §Audio Requirements + Mix hierarchy +
règles de ducking 1-4 + AC-CMB-audio-01/02), Movement consume potentiellement
des sons pour dash/wall-run/jump, Camera/Level/GSM ont besoin de fades
musicaux, mais aucune décision architecturale ne fixe :

1. La **taxonomie des buses audio** (Master, Music, SFX, Combat, Ambience, UI, Voice) — qui définit ducking, persistence settings, bus parents/children
2. Le pattern de **pooling AudioStreamPlayer / AudioStreamPlayer3D** pour éviter alloc à `play()` runtime + concurrence des sons (≥3 swings overlappés possibles)
3. La **règle de timing wall-clock** pour les fades (swoosh fade-out 30 ms, music crossfade) — DOIT être indépendant de `Engine.time_scale` pour préserver Pillar 1 Fantasy staccato pendant slow-mo Combat
4. Le **mode connection** standard pour les consumers Audio (par défaut `CONNECT_DEFERRED` per ADR-0005 D-5 car instanciation/play sont opérations lourdes)
5. **Spatialisation** : règles 2D head-locked vs 3D positional + ownership node (jamais attaché à un ennemi pouvant être `queue_free`)
6. **AudioListener3D** : doit-on en instancier un dédié, ou `Camera3D` actif suffit-il (Godot 4.6 default behavior à confirmer)
7. Le **payload des signals** côté Audio handler : doit utiliser `position: Vector3` capturé au tick d'émission (pas `enemy.global_position` au moment de la réception DEFERRED — ennemi peut-être freed entre temps, AC-CMB-audio r4 A-03 fix)

Sans ADR Audio, l'epic Audio est bloqué et les stories Combat/Movement/Camera
qui consomment Audio ne peuvent pas être finalisées avec contract verifiable.
Le combat-system epic a 1 story BLOCKED (story-020) sur ce gap.

### Constraints

- **Engine** : Godot 4.6, API audio stable (LOW risk)
- **Performance** : ≤ 0.5 ms / frame audio CPU cumul (slot dans budget 16.6 ms — Camera 0.2 ms, Movement signals 0.1 ms, Audio 0.5 ms, reste rendering+physics)
- **Pillar 1 (FLOW AVANT TOUT)** : pas de hitching audio sur slow-mo, pas de fade Tween scaled par `time_scale`
- **Memory** : ≤ 50 MB audio assets MVP (~30 SFX + 3 musiques courtes + ambience)
- **Décision Combat GDD figée** : `AudioStreamPlayer.pitch` NON affecté par `Engine.time_scale` (no pitch shift pendant slow-mo, désiré per Martin D3)

### Requirements

- Doit supporter ≥ 3 swings overlappés (joueur enchaîne attacks 80 ms apart)
- Doit supporter ducking -6 dB sur bus `swing_active` à `enemy_killed` avec release 30 ms wall-clock
- Doit supporter pause complète (silence pendant pause, restore au resume — GSM)
- Doit supporter accessibility `master_volume_db`, `music_volume_db`, `sfx_volume_db` per-bus settings (post-MVP Save/Load)
- Doit fournir un pattern de mocking testable côté Combat (`MockAudioHandler`, `MockAudioBus` — déjà figés ADR-0006 D-4)

## Decision

**5 décisions principales** :

### D-1 — Bus hierarchy 7-bus + structure parent/child + sidechain compressor MUSIC ← COMBAT_KILL (r2 amendement)

Configuration `res://default_bus_layout.tres` avec hierarchy :

```
Master (idx 0)
├── Music (idx 1)
├── SFX (idx 2)
│   ├── swing_active (idx 3) — buse swoosh swing en cours
│   └── combat_kill (idx 4) — buse clac kill + blood ambiance
├── Ambience (idx 5)
└── UI (idx 6)
```

Voice/VO bus différé post-MVP (Tier 2+).

API helper `AudioBuses` — **classe statique pure** (PAS un autoload — toutes méthodes `static`, accès via `AudioBuses.SFX`, `AudioBuses.set_volume(...)`). Évite la collision identifiant `class_name` ↔ autoload (cf. mémoire projet `feedback_godot_class_name_autoload_collision.md`). Seul `AudioSystem` est autoload.

```gdscript
class_name AudioBuses
const MASTER := &"Master"
const MUSIC := &"Music"
const SFX := &"SFX"
const SWING_ACTIVE := &"swing_active"
const COMBAT_KILL := &"combat_kill"
const AMBIENCE := &"Ambience"
const UI := &"UI"

static func set_volume(bus: StringName, volume_db: float) -> void:
    AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), volume_db)
static func get_volume(bus: StringName) -> float:
    return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
```

**Sidechain compressor MUSIC ← COMBAT_KILL (r2 amendement Phase A — résout Couche 1 vs Couche 3)** :

Le bus `MUSIC` reçoit un `AudioEffectCompressor` configuré en sidechain. Quand `COMBAT_KILL` joue (clac à 0 dB), le compressor déclenche un ducking sur `MUSIC` (-3 dB attaque 5 ms / release 200 ms). Mécanisme dans `default_bus_layout.tres` puis configuré au boot AudioSystem `_ready()` :

```gdscript
func _ready() -> void:
    var music_idx := AudioServer.get_bus_index(AudioBuses.MUSIC)
    var compressor := AudioEffectCompressor.new()
    compressor.threshold = -24.0
    compressor.ratio = 4.0
    compressor.attack_us = 5000  # 5 ms en microsecondes
    compressor.release_ms = 200.0
    compressor.sidechain = AudioBuses.COMBAT_KILL  # StringName du bus de feed
    AudioServer.add_bus_effect(music_idx, compressor)
```

**Tuning runtime** : `sidechain_music_attenuation_db` (audio GDD §Tuning Knobs r2) ajuste effective ducking via `ratio` (augmenter pour ducking plus fort). `sidechain_release_ms` ajustable `[100, 400] ms`.

**Pourquoi mécanisme et pas prose** : Audio GDD r1 décrivait Couche 1 (silence rythmique) + Couche 3 (continuité musicale) comme couches parallèles, mais elles s'annulaient au mix actuel (Music -3 dB jamais auto-ducked). CD review verdict r1 : "spec le mix, pas la liste de couches — produire un fichier `default_bus_layout.tres` opérationnel avec effects, pas seulement une hiérarchie de noms". Le sidechain résout la contradiction au mix, pas en prose.

### D-2 — Pool pré-instancié AudioStreamPlayer + AudioStreamPlayer3D (r2 sizing : 5+12)

Au boot Audio System (`_ready()`), instancier un pool fixé (r2 sizing CD reco — augmentation pools pour MVP scenarios stress + multi-kill blood ambiance) :
- **5×** `AudioStreamPlayer` 2D (head-locked SFX : swoosh, UI clicks, dash_reject, walljump, death — MVP scenario : 1 swoosh + 1 dash + 1 walljump + 1 death + 1 UI = 5 simultanés possible)
- **12×** `AudioStreamPlayer3D` (positional SFX : clac kill + blood ambiance × `MAX_KILLS_PER_SWING=3` simultanés + footsteps ennemis Tier 2 + environmental SFX + headroom)
- 1× `AudioStreamPlayer` Music (fade gérée manuellement, pas de pool — single instance — sidechain compressor activé via D-1 r2)
- 2× `AudioStreamPlayer` Ambience (crossfade entre rooms)

Total = **20 nodes** pré-alloués au boot (r2 vs r1 15 nodes — +5 nodes, ~5 KB additional static memory). **Forbidden** : `AudioStreamPlayer.new()` runtime — toute lecture passe par le pool round-robin avec garde "is_playing()".

```gdscript
class_name AudioPool
var _2d_pool: Array[AudioStreamPlayer] = []
var _2d_index: int = 0

func play_2d(stream: AudioStream, bus: StringName) -> void:
    var p := _2d_pool[_2d_index]
    _2d_index = (_2d_index + 1) % _2d_pool.size()
    if p.playing:
        push_warning("AudioPool 2D saturé — interruption swoosh actif (cf. R-1 Risk)")
    p.stop()  # interrupt si déjà actif (peut produire un click bref si pool saturé)
    p.stream = stream
    p.bus = bus
    p.play()
```

**Note pool saturation** (godot-specialist review 2026-04-27 + r2 update) : `stop()` puis `play()` sur un slot encore actif peut produire un click bref (Godot coupe le sample en cours). Avec pool **5× 2D** (r2 sizing), ce click n'apparaît qu'au-delà de 5 SFX 2D overlappés simultanés — couvre MVP scenario stress (5 SFX 2D possibles) et multi-kill (clac 3D, blood 3D, pas dans pool 2D). Pool **12× 3D** absorbe `MAX_KILLS_PER_SWING=3` (3 clacs + 3 blood = 6 nodes pour multi-kill) + footsteps ennemis Tier 2 + environmental SFX. Mitigation R-1 : augmenter `pool_2d_size` 5 → 8 et `pool_3d_size` 12 → 16 post-MVP si playtest combo Tier 2 révèle saturation.

### D-3 — Wall-clock fades dans `_physics_process` via `_get_time_msec` Callable injection (réutilise pattern ADR-0006 D-5) + r2 amendement allowlist pitch_scale_follows_time_scale per bus

Tout fade audio (swoosh fade-out 30 ms, music crossfade 1 s, ducking release 30 ms) DOIT être interpolé wall-clock dans `_physics_process` (ADR-0001 autorité), JAMAIS via `Tween` ou `_process` (qui scalent par `Engine.time_scale`).

Audio System partage le pattern Callable injection avec Combat (même `_get_time_msec: Callable = Time.get_ticks_msec`) pour permettre tests CI déterministes — coordination avec Combat via fixture commune `MockAudioHandler` (ADR-0006 D-4).

```gdscript
var _swoosh_fade_active: bool = false
var _swoosh_fade_start_msec: int = 0
const SWOOSH_FADE_DURATION_MS: float = 30.0
var _get_time_msec: Callable = Time.get_ticks_msec

func _physics_process(delta: float) -> void:
    if _swoosh_fade_active:
        var elapsed := float(_get_time_msec.call() - _swoosh_fade_start_msec)
        var t := elapsed / SWOOSH_FADE_DURATION_MS
        if t >= 1.0:
            _swoosh_player.volume_db = -80.0
            _swoosh_fade_active = false
        else:
            _swoosh_player.volume_db = lerpf(0.0, -80.0, t)
```

**Forbidden** : `Tween.tween_property(audio_player, "volume_db", ...)` pour les fades sensibles à slow-mo. Tween reste autorisé pour fades non-time-critical (music crossfade entre rooms quand `time_scale == 1.0` garanti).

**Note courbe perceptuelle dB** (godot-specialist review 2026-04-27) : `lerpf(0.0, -80.0, t)` est une interpolation **linéaire sur échelle logarithmique** (dB). Pour un fade ≤ 30 ms (swoosh), la non-linéarité perceptuelle n'est pas audible — pattern simple acceptable au MVP. Pour un fade ≥ 1 s (music crossfade futur), utiliser plutôt `linear_to_db(lerpf(db_to_linear(start_db), db_to_linear(end_db), t))` pour préserver une courbe perceptuellement linéaire. Décision MVP : conserver `lerpf` pour swoosh ≤ 30 ms (D-3) ; switch perceptuel obligatoire pour music crossfade dans futur Music ADR.

**r2 amendement Phase A — Allowlist `pitch_scale_follows_time_scale` per bus (Martin D3 REOPEN Option A)** :

Comportement Godot 4.6 par défaut : `AudioStreamPlayer.pitch_scale` ne suit PAS `Engine.time_scale`. Conservé pour bus invariants. **Mais** Audio System applique manuellement un pitch shift bus-level pour les bus de l'allowlist pendant slow-mo, recréant l'identité Hotline Miami (drone bass descendant en slow-mo) sans casser la lisibilité rythmique du clac (attack < 5 ms invariant) ni la continuité musicale (`MUSIC` invariant).

**Allowlist** (figée au MVP) :
| Bus | `pitch_scale_follows_time_scale` | Rationale |
|-----|----------------------------------|-----------|
| `MASTER` | false | Préserve toute la chain. |
| `MUSIC` | **false** | Couche 3 continuité musicale invisible — pitch perturbé briserait l'immersion musicale. |
| `SFX` | false | Bus parent générique — pitch shift opère sur les enfants spécifiques. |
| `SWING_ACTIVE` | **false** | Couche 2 swoosh proprioceptif head-locked — pitch invariant pour stabilité corporelle. |
| `COMBAT_KILL` | **true** | Queue blood ambiance descend (drone-down post-clac, attack du clac < 5 ms invariant car n'a pas le temps de pitcher). |
| `AMBIENCE` | **true** | Room tone Chrome Zen sub-bass drone-down identité HLM. |
| `UI` | false | Feedback UI lisible quel que soit time_scale. |

**Mécanisme** :
```gdscript
# AudioSystem _physics_process ou _on_state_changed
var pitch_shift_factor: float = _compute_pitch_scale(Engine.time_scale)  # Formula 5
for player in _3d_pool:  # COMBAT_KILL bus
    if player.bus == AudioBuses.COMBAT_KILL and player.playing:
        player.pitch_scale = pitch_shift_factor
for player in _ambience_players:  # AMBIENCE bus
    if player.playing:
        player.pitch_scale = pitch_shift_factor
# Bus invariants : MUSIC, SWING_ACTIVE, etc. — pitch_scale=1.0 maintained
```

**Formula 5 (Audio GDD r2)** :
```
pitch_semitones(time_scale) = clampf(lerpf(0.0, -3.0, 1.0 - time_scale), -4.0, 0.0)
pitch_scale(time_scale) = 2.0 ** (pitch_semitones(time_scale) / 12.0)
```
À `time_scale=0.3` (Combat slow-mo MVP) → `pitch_scale ≈ 0.8821` (≈ -2.1 semitones).

**R-3 ADR-0009 vérification empirique mise à jour r2** : tester transition `pitch_scale 1.0 → 0.8821 → 1.0` mid-`play()` n'introduit pas de pop sonore (rendre output via Godot AudioServer recording, analyser waveform).

### D-4 — Mode connection `CONNECT_DEFERRED` par défaut + exemptions limitées

Tous les handlers Audio connectés à des signals Movement/Combat/Level/GSM
utilisent `CONNECT_DEFERRED` (cohérent ADR-0005 D-5 : instanciation Node,
`AudioStreamPlayer.play()` opération lourde > 256 B alloc + > 0.5 ms).

**Exemption explicite** : aucune exemption SYNC pour Audio au MVP. Le sound
designer NE DOIT PAS tenter un override SYNC pour le swoosh fade-out (Combat
GDD r5 BLOCK-r5-B fix). La perception d'immédiateté est assurée par le
**ducking -6 dB sur événement `enemy_killed`** avec release 30 ms — pas par le
timing du dispatch fade.

**Forbidden grep** :
```bash
grep -rE 'enemy_killed\.connect.*\b(?!CONNECT_DEFERRED)' src/gameplay/audio/
# Doit retourner zéro match — toutes connexions Audio doivent être DEFERRED
```

### D-5 — Spatialisation : 2D head-locked vs 3D positional + ownership

Règles :
- **2D head-locked (`AudioStreamPlayer`)** : swoosh swing (proprioceptif joueur), UI clicks, music, ambience non-positionnelle
- **3D positional (`AudioStreamPlayer3D`)** : kill impact, blood, footsteps ennemis, environmental SFX (door, trigger)
- **Ownership** : tous les `AudioStreamPlayer*` du pool vivent dans `AudioSystem` autoload OU dans le scene root de la salle active (Level System) — JAMAIS attachés à un ennemi (`queue_free` → AudioStreamPlayer3D freed avant fin sample → pop sonore)
- **Position payload** : pour signals comme `enemy_killed(enemy: Node, position: Vector3)`, utiliser `position` capturé au tick d'émission (NON `enemy.global_position` au moment de réception DEFERRED — AC-CMB-audio r4 A-03 fix)

**Decision Matrix par event-type** :

| Event source | Player-relative | Type | Bus |
|---|---|---|---|
| Combat `swing_started` | Yes (proprioceptif) | 2D head-locked | `swing_active` |
| Combat `enemy_killed` | No (positional) | 3D positional, owned by AudioPool | `combat_kill` |
| Combat `multi_kill` | No (cumul positional) | 3D positional layered | `combat_kill` |
| Movement `dash_started` | Yes | 2D head-locked | `SFX` |
| Movement `wall_run_entered` | Yes (subtle wind) | 2D head-locked | `SFX` |
| Movement `wall_jumped` | Yes | 2D head-locked | `SFX` |
| Movement `died` | Yes (one-shot) | 2D head-locked | `SFX` |
| GSM transition | UI | 2D | `UI` |
| Level music | Ambience | 2D | `Music` |
| Environmental SFX | Positional | 3D | `Ambience` |

### D-6 — `AudioListener3D` enfant explicite de Camera3D (per ADR-0002 chain) — pas de second listener côté Audio

**Amendement r2 (2026-04-27 Phase A re-review)** : reconnaissance explicite de la chain ADR-0002 `... → CameraEffects → Camera3D → AudioListener3D` (VC-5 ADR-0002). Le listener 3D existe déjà dans la scene tree comme enfant Camera3D — c'est lui qui sert de référence pour la spatialisation 3D Godot 4.6.

**Audio System NE doit PAS instancier de second `AudioListener3D`** — un seul listener doit exister dans la scene tree (l'enfant Camera3D per ADR-0002). Si Audio System créait un listener dédié supplémentaire, conflit avec `current=true` invariant et `make_current()` racing — casserait la spatialisation.

**Comportement Godot 4.6 attendu** : avec exactement 1 `AudioListener3D` dans la scene tree (celui d'ADR-0002), Godot l'utilise automatiquement comme listener actif (pas besoin d'appel `make_current()` explicite si c'est le seul présent).

**Fallback documenté** : si la chain ADR-0002 venait à être démontée transitoirement (e.g. scene reload mid-frame, Camera3D freed), Godot fallback à la position du Camera3D `current=true` puis à `(0,0,0)` — sons 3D atténués au origin pendant 1 frame transitoire (Edge Case Audio GDD).

**Vérification empirique requise** (R-2 ADR-0009) : confirmer comportement avec SubViewport edge case (Camera3D dans SubViewport peut ne pas auto-server). Audio GDD AC-AUD-14 (c) teste `find_children("*", "AudioListener3D", true).size() == 1` — exactement 1 listener (celui d'ADR-0002), pas zéro. Owner : sound-designer ou godot-specialist pré-Sprint Audio.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ AudioSystem (autoload, singleton process_priority normal)       │
│                                                                 │
│ ┌───────────────────────────────────────────────────────────┐   │
│ │ AudioPool                                                 │   │
│ │  4× AudioStreamPlayer (2D head-locked)                    │   │
│ │  8× AudioStreamPlayer3D (positional, scene root owned)    │   │
│ │  1× AudioStreamPlayer (Music — fade _physics_process)     │   │
│ │  2× AudioStreamPlayer (Ambience — crossfade)              │   │
│ └───────────────────────────────────────────────────────────┘   │
│                                                                 │
│ ┌───────────────────────────────────────────────────────────┐   │
│ │ AudioBuses (helper static)                                │   │
│ │  Master / Music / SFX / swing_active / combat_kill /     │   │
│ │  Ambience / UI                                            │   │
│ └───────────────────────────────────────────────────────────┘   │
│                                                                 │
│ ┌───────────────────────────────────────────────────────────┐   │
│ │ Signal handlers (CONNECT_DEFERRED par défaut) :           │   │
│ │  Combat.enemy_killed → _play_clac + _duck_swing_active    │   │
│ │  Combat.swing_started → _play_swoosh                      │   │
│ │  Combat.swing_ended → _start_swoosh_fade                  │   │
│ │  Movement.dash_started → _play_dash_sfx                   │   │
│ │  Movement.wall_run_entered → _play_wallrun_loop           │   │
│ │  GSM.state_changed → _on_state_changed (mute/restore)     │   │
│ │  Level.level_active → _on_level_active                    │   │
│ │    + lookup get_etage_audio_streams (music + ambient swap)│   │
│ │  Level.level_unloading → _on_level_unloading (fade-out)   │   │
│ └───────────────────────────────────────────────────────────┘   │
│                                                                 │
│ Wall-clock fades in _physics_process via _get_time_msec        │
│ Callable (substituable test).                                  │
└─────────────────────────────────────────────────────────────────┘

AudioListener3D = Camera3D actif (pas de listener dédié).
```

### Key Interfaces

```gdscript
# Autoload AudioSystem (singleton)
# IMPORTANT : pas de class_name (collision avec autoload — cf. AudioBuses doc D-1).
# process_priority = 0 (default) — handlers signals consommés en ordre par défaut, pas
# de spécificité timing requise (DEFERRED par défaut découple).
extends Node

signal audio_settings_changed(bus: StringName, volume_db: float)

var _get_time_msec: Callable = Time.get_ticks_msec  # injection point test

func play_2d(stream: AudioStream, bus: StringName = AudioBuses.SFX) -> void
func play_3d_at(stream: AudioStream, position: Vector3, bus: StringName = AudioBuses.SFX) -> void
func play_music(stream: AudioStream, fade_seconds: float = 1.0) -> void
func stop_music(fade_seconds: float = 1.0) -> void
func duck_bus(bus: StringName, delta_db: float, release_ms: float) -> void
func set_paused(paused: bool) -> void  # called by GSM state_changed
```

## Alternatives Considered

### Alternative 1 : `AudioStreamPlayer` instanciation à la demande (no pool)

- **Description** : Chaque `play_*()` crée un nouveau `AudioStreamPlayer.new()`, le `add_child(get_tree().root)`, joue, puis `queue_free()` à `finished` signal.
- **Pros** : Code simple, pas de gestion de pool, pas de limite hard sur concurrence.
- **Cons** : Alloc Node à chaque play (~ 1-2 ms). 3 swings 80 ms apart = 9 plays / 240 ms = 9 allocs = ~10 ms. Viole budget Audio 0.5 ms/frame. Garbage collection imprévisible.
- **Rejection Reason** : Coût alloc + GC pression incompatible Pillar 1 (FLOW AVANT TOUT). Pool pré-alloué supprime le hitch.

### Alternative 2 : Tween-based fades (status quo Godot intuitive)

- **Description** : `tween.tween_property(player, "volume_db", -80, 0.03)` pour fade swoosh.
- **Pros** : API standard Godot, code court.
- **Cons** : `Tween` actif dans `_process` est scaled par `Engine.time_scale`. Pendant slow-mo Combat (`time_scale = 0.3`), un fade 30 ms wall-clock devient 100 ms perçus → overlap swoosh + clac + blood ambiance casse Fantasy staccato (Combat GDD r4 A-01 fix).
- **Rejection Reason** : Viole Pillar 1 + Combat GDD §Rule 13 contract. Wall-clock interpolation in `_physics_process` est obligatoire pour fades sensibles.

### Alternative 3 : Pas d'autoload AudioSystem (Audio per-scene)

- **Description** : Chaque scene racine instancie ses propres AudioStreamPlayer. Pas de service global.
- **Pros** : Pas de dépendance autoload, scopage par scene.
- **Cons** : Music/Ambience ne traversent pas les transitions de scene (GSM). Dupliquer pool par scene = 15 × N scenes nodes. Ducking cross-scene impossible. Settings volume per-bus difficile à propager.
- **Rejection Reason** : Architecturalement incompatible avec Music continuity, GSM pause global, settings persistence cross-session.

### Alternative 4 : `AudioListener3D` dédié (override Camera3D)

- **Description** : Instancier un `AudioListener3D` enfant de Player CharacterBody3D, indépendant de Camera3D.
- **Pros** : Découplage Audio ↔ Camera, Pas de dépendance Camera scene tree.
- **Cons** : Conflits avec `Camera3D.current = true` default behavior. ADR-0002 fixe la chain Camera3D → AudioListener3D enfant déjà — Listener override briserait l'invariant. Maintenance complexité accrue sans bénéfice MVP.
- **Rejection Reason** : Default `Camera3D` listener Godot 4.6 suffit. Pas de scenarii MVP nécessitant override (Tier 3 Full Vision peut ré-évaluer).

### Alternative 5 : Bus structure plate (Master + 2-3 buses seulement)

- **Description** : Master + Music + SFX, sans `swing_active`/`combat_kill`/`Ambience`/`UI`.
- **Pros** : Plus simple à configurer.
- **Cons** : Combat GDD r4 D-r4-3 spécifie ducking -6 dB sur bus `swing_active` à l'événement `enemy_killed` — implémentable seulement avec bus dédié. Sans, le ducking affecte tous SFX (UI clicks, footsteps Movement) → audible coupure Pillar 1.
- **Rejection Reason** : Combat GDD ratifie déjà 4 règles ducking sur bus dédiés — alternative incompatible.

## Consequences

### Positive

- Combat GDD §Audio Requirements + Mix hierarchy implémentable directement (4 ducking rules + AC-CMB-51 + AC-CMB-audio-01/02)
- Story-020 Combat (BLOCKED) débloquée
- Audio System GDD peut être écrit (`/design-system audio-system`) avec architecture définie
- Pattern Callable injection partagé Combat ↔ Audio = mocks réutilisables (`MockAudioHandler` ADR-0006 D-4)
- Pillar 1 préservé : pas de Tween-scaled fade, pas de hitch alloc, deterministic latency
- AudioListener3D = Camera3D default = code minimal, alignement ADR-0002

### Negative

- 15 AudioStreamPlayer pré-instanciés au boot (~ 10-15 KB RAM) — coût mineur
- Pool round-robin peut interrompre un son en cours si pool saturé (3 swings très rapprochés) — atténuation : `AudioStreamPlayer.stop()` discret + transition propre
- `AudioListener3D` = Camera3D = couplage soft Audio ↔ Camera (ADR-0002) — déjà couvert par chain
- Ducking via `AudioServer.set_bus_volume_db()` est instantané, pas interpolé — release 30 ms wall-clock à implémenter dans `_physics_process` Audio handler

### Risks

- **R-1 Pool saturation** : 3 swings overlappés → 3 swooshes simultanés, pool 4× suffit ; si combo system Tier 2 > 4 swings → augmenter pool à 6× (post-MVP). Mitigation : pool size paramétré const, ajustable Sprint Audio.
- **R-2 AudioListener3D default behavior** : si Godot 4.6 a un edge case où Camera3D ne joue pas le rôle de listener (e.g. SubViewport), spatialisation 3D rate. Mitigation : test empirique pré-Sprint Audio (sound-designer / godot-specialist).
- **R-3 `pitch_scale` non-affecté par `time_scale`** : Combat GDD assume ce comportement (no pitch shift slow-mo, désiré). Si Godot 4.6 a un edge case régressé, slow-mo casse Fantasy. Mitigation : test empirique pré-Sprint Audio + fallback `pitch_scale` manuel si besoin (compense `time_scale` pour cancel l'effet).
- **R-4 Tween regression** : un développeur peut accidentellement écrire un Tween sur `volume_db` (intuitive). Mitigation : forbidden_pattern lint CI + revue code.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `player-combat-system.md` | §Visual/Audio Requirements §Audio Section + Mix hierarchy + 4 ducking rules + AC-CMB-51 swoosh fade-out wall-clock | D-1 (bus `swing_active` + `combat_kill`) + D-3 (wall-clock fade `_get_time_msec` Callable) + D-4 (CONNECT_DEFERRED) + D-5 (spatialization swoosh 2D / kill 3D) |
| `player-combat-system.md` | AC-CMB-audio-01 multi-kill clac dedup `_kill_sound_played_this_swing` | D-2 (pool dedup intra-swing via flag) + D-4 (DEFERRED) |
| `player-combat-system.md` | AC-CMB-audio-02 ducking event ordering | D-1 (bus dédié `swing_active`) + D-3 (release 30 ms wall-clock) |
| `player-movement-system.md` | Audio consume `dash_started`, `wall_run_entered`, `wall_jumped`, `died`, `respawned` | D-4 (CONNECT_DEFERRED) + D-5 (2D head-locked pour proprioceptif) |
| `camera-system.md` | AudioListener3D enfant Camera3D, current single-listener | D-6 (default Camera3D listener, pas d'AudioListener3D dédié) |
| `level-system.md` | Music/Ambience swap par etage via `level_active` + lookup `get_etage_audio_streams(etage_id)` (Level r4 Option C 2026-04-27, pas de signal `etage_loaded` dédié). Fade-out sur `level_unloading`. | D-1 (bus `Music`/`Ambience`) + D-2 (1× Music + 2× Ambience pool) + D-4 (CONNECT_DEFERRED `level_active`) |
| `game-state-manager.md` | Audio mute/restore on pause/resume | D-1 (Master bus) + Key Interface `set_paused(bool)` |
| `game-concept.md` Pillar 1 | FLOW AVANT TOUT — pas de hitching audio en slow-mo | D-3 (wall-clock fades) + D-4 (DEFERRED pour heavy ops, pre-alloc pool) |

## Performance Implications

- **CPU** : ≤ 0.5 ms / frame audio (mix Godot natif + handlers ≤ 0.1 ms / signal). Pool round-robin O(1).
- **Memory** : ~ 15 KB Nodes au boot (15 AudioStreamPlayer*). Audio assets MVP ~ 30 SFX × 50 KB + 3 musiques × 5 MB + ambience 2 MB ≈ 17-20 MB total — sous budget 50 MB.
- **Load Time** : pool init au `_ready()` AudioSystem ≤ 5 ms (15 Node.new() instanciations). Bus layout `default_bus_layout.tres` chargé au project start, pas runtime.
- **Network** : N/A (single-player MVP)

## Migration Plan

1. **Sprint 0 Technical Setup** :
   - Créer `default_bus_layout.tres` avec 7 buses (Master/Music/SFX/swing_active/combat_kill/Ambience/UI)
   - Configurer `project.godot` `audio/buses/default_bus_layout = "res://default_bus_layout.tres"`
   - Créer autoload `AudioSystem` (`src/core/audio_system.gd`) avec `AudioPool` interne
   - Créer `src/core/audio_buses.gd` helper static `class_name AudioBuses`
   - Lint CI `lint-audio-tween` : grep `Tween.*volume_db|tween_property.*volume_db` dans `src/gameplay/audio/` + `src/core/audio_system.gd` → fail si match (forbidden pattern fade Tween-scaled)

2. **Sprint Audio (post-ADR Accepted + Audio GDD)** :
   - Implémenter pool 15 AudioStreamPlayer
   - Wire signal handlers Combat/Movement/Level/GSM
   - Implémenter wall-clock fade in `_physics_process` avec `_get_time_msec` Callable
   - Tests : `MockAudioHandler` + `MockAudioBus` (ADR-0006 D-4 fixtures déjà figées) — AC-CMB-51 + AC-CMB-audio-01 + AC-CMB-audio-02 deviennent passants

3. **Coordination Combat story-020** : déblocage post-Audio System GDD écrit. Story-020 ACs deviennent testables.

4. **Vérification empiriques pré-Sprint** :
   - (R-2) AudioListener3D = Camera3D actif comportement Godot 4.6
   - (R-3) AudioStreamPlayer.pitch_scale non-affecté par Engine.time_scale
   - Documenter résultats dans `docs/engine-reference/godot/modules/audio.md` section "Empirical verifications"

## Validation Criteria

L'ADR est valide quand :

- VC-1 : `default_bus_layout.tres` charge sans warning au boot, 7 buses présents (`AudioServer.bus_count == 7`)
- VC-2 : Pool 15 AudioStreamPlayer instanciés au `_ready()` AudioSystem (vérifié via `Performance.OBJECT_COUNT` delta + 15 ± 0)
- VC-3 : AC-CMB-51 passe (swoosh fade-out résolu dans `[25, 50]` ms wall-clock pendant slow-mo `time_scale=0.3`)
- VC-4 : AC-CMB-audio-01 passe (clac dedup multi-kill, `_kill_sound_played_this_swing` flag respecté)
- VC-5 : AC-CMB-audio-02 passe (ducking -6 dB sur `swing_active` à `enemy_killed` frame N+1, release 30 ms wall-clock)
- VC-6 : Lint CI `lint-audio-tween` passe (zéro Tween sur `volume_db` dans `src/core/audio_system.gd` ou `src/gameplay/audio/`)
- VC-7 : Test cross-system : 1000 cycles play/stop pool round-robin → `Performance.MEMORY_STATIC` delta ≤ 100 KB, `Performance.OBJECT_COUNT` delta ≤ 0
- VC-8 : Performance bench : 5 swings overlappés simultanés → frame_time p99 ≤ 16.6 ms (audio cumul ≤ 0.5 ms / frame mesuré via `Time.get_ticks_usec()`)

## Related Decisions

- ADR-0001 (Physics Rate 60 Hz — autorité fades wall-clock dans `_physics_process`)
- ADR-0002 (Camera Scene Tree — AudioListener3D enfant Camera3D auto-current)
- ADR-0005 (Movement Signals — CONNECT_DEFERRED par défaut pour Audio consumers)
- ADR-0006 (Combat Tick Model — `_get_time_msec` Callable injection partagé, mocks `MockAudioHandler`/`MockAudioBus` figés D-4)
- ADR-0007 (Game State Manager — Audio mute/restore sur pause/resume)
- ADR-0011 (Level Scene — Music/Ambience swap par etage)
- Future Music ADR (Tier 2 — transitions musicales contextuelles, dynamic mixing)
- Future Voice/VO ADR (Tier 3 — narrative voice acting + accessibility subtitles)
