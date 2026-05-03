# Godot Audio — Quick Reference

Last verified: 2026-05-03 | Engine: Godot 4.6

## What Changed Since ~4.3 (LLM Cutoff)

No major breaking changes to the audio API in 4.4–4.6. The core audio system
remains stable. Key updates are workflow improvements:

### 4.6 Changes
- **No audio-specific breaking changes** in this release
- See **AudioEffectCompressor (Sidechain Ducking)** section below — long-standing
  property naming gotcha (`attack_us` µs vs `release_ms` ms) trips up new code
  that imports patterns from generic audio docs

### 4.5 Changes
- **No audio-specific breaking changes** in this release

## Current API Patterns

### Playing Audio
```gdscript
@onready var sfx_player: AudioStreamPlayer = %SFXPlayer
@onready var music_player: AudioStreamPlayer = %MusicPlayer

func play_sfx(stream: AudioStream) -> void:
    sfx_player.stream = stream
    sfx_player.play()

func play_music(stream: AudioStream, fade_time: float = 1.0) -> void:
    var tween: Tween = create_tween()
    tween.tween_property(music_player, "volume_db", -80.0, fade_time)
    await tween.finished
    music_player.stream = stream
    music_player.volume_db = 0.0
    music_player.play()
```

### 3D Spatial Audio
```gdscript
@onready var audio_3d: AudioStreamPlayer3D = %AudioPlayer3D

func _ready() -> void:
    audio_3d.max_distance = 50.0
    audio_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
    audio_3d.unit_size = 10.0
```

### Audio Buses
```gdscript
# Set bus volumes
AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Music"), volume_db)
AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), volume_db)

# Mute a bus
AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), true)
```

### Object Pooling for SFX
```gdscript
# Pre-create multiple AudioStreamPlayer nodes for concurrent sounds
var _sfx_pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
    for i in range(8):
        var player := AudioStreamPlayer.new()
        player.bus = &"SFX"
        add_child(player)
        _sfx_pool.append(player)

func play_pooled(stream: AudioStream) -> void:
    for player in _sfx_pool:
        if not player.playing:
            player.stream = stream
            player.play()
            return
```

## AudioEffectCompressor (Sidechain Ducking)

**Verified against Godot 4.6.** Required by audio-system GDD r2.3 Phase D.2
(MUSIC ← COMBAT_KILL sidechain) and AC-AUD-01 (d) verification.

### Class Reference

`AudioEffectCompressor` extends `AudioEffect`. Add to a bus via
`AudioServer.add_bus_effect(bus_idx, effect)`.

### Properties

| Property | Type | Range | Default | Unit | Notes |
|----------|------|-------|---------|------|-------|
| `threshold` | `float` | `[-60.0, 0.0]` | `0.0` | dB | Level above which compression kicks in |
| `ratio` | `float` | `[1.0, 48.0]` | `4.0` | x:1 | Compression ratio above threshold |
| `gain` | `float` | `[-20.0, 20.0]` | `0.0` | dB | Makeup gain post-compression |
| `attack_us` | `float` | `[20.0, 2000.0]` | `20.0` | **microseconds** | Time to reach full compression |
| `release_ms` | `float` | `[20.0, 2000.0]` | `250.0` | **milliseconds** | Time to release compression |
| `mix` | `float` | `[0.0, 1.0]` | `1.0` | ratio | Wet/dry mix (1.0 = fully compressed) |
| `sidechain` | `StringName` | bus name | `&""` | — | Source bus that triggers compression on this bus |

### Critical Naming Gotcha

**`attack_us` is microseconds, `release_ms` is milliseconds.** The asymmetric
unit naming is a long-standing Godot quirk (since 3.x). Reading docs that say
"attack: 5 ms" and writing `compressor.attack_us = 5` produces a 5 µs attack
(1000× too fast). Correct conversion: `5 ms = 5000 µs → attack_us = 5000`.

The properties have always been named this way — there is no breaking change
between 4.3 and 4.6. Code that uses `compressor.attack` or `compressor.release`
silently no-ops (sets a non-existent property without error).

### Sidechain Ducking Pattern (audio-system GDD Phase D.2)

```gdscript
# Boot guard idempotent — skip si AudioEffectCompressor déjà présent sur MUSIC
func _setup_sidechain_compressor() -> void:
    var music_idx: int = AudioServer.get_bus_index(&"MUSIC")
    if music_idx == -1:
        push_error("MUSIC bus missing from default_bus_layout.tres")
        return

    var effect_count: int = AudioServer.get_bus_effect_count(music_idx)
    for i in effect_count:
        if AudioServer.get_bus_effect(music_idx, i) is AudioEffectCompressor:
            push_warning("Sidechain compressor already present on MUSIC — skip add")
            return

    var compressor := AudioEffectCompressor.new()
    compressor.threshold = -24.0    # dB — kill SFX peaks duck music when loud
    compressor.ratio = 4.0          # 4:1 ratio
    compressor.attack_us = 5000.0   # 5 ms — quick duck on impact
    compressor.release_ms = 200.0   # 200 ms — natural recovery
    compressor.sidechain = &"COMBAT_KILL"  # source bus triggers compression
    AudioServer.add_bus_effect(music_idx, compressor)
```

### Verification (AC-AUD-01 (d))

After boot, fetch the effect and assert properties match:

```gdscript
var music_idx := AudioServer.get_bus_index(&"MUSIC")
var compressor := AudioServer.get_bus_effect(music_idx, 0) as AudioEffectCompressor
assert(compressor != null, "Compressor missing on MUSIC bus")
assert(compressor.attack_us == 5000.0, "attack_us mismatch — Godot 4.6 API gotcha")
assert(compressor.release_ms == 200.0, "release_ms mismatch")
assert(compressor.threshold == -24.0)
assert(compressor.ratio == 4.0)
assert(compressor.sidechain == &"COMBAT_KILL")
```

### Common Pitfalls

- Writing `compressor.attack = 5` or `compressor.release = 200` — sets nothing,
  no error raised. Always use `attack_us` / `release_ms`.
- Forgetting `attack_us` is **microseconds**, not milliseconds. 5 ms = 5000.
- Calling `add_bus_effect` twice on `_ready()` re-entry produces a 2-stage
  cascade (effective ratio 16:1 instead of 4:1). Always guard with
  `get_bus_effect_count` + type check.
- `sidechain = &""` (empty StringName) means self-sidechain, not "no sidechain".
  Use a real bus name or omit the property entirely.

## Common Mistakes
- Creating new AudioStreamPlayer nodes at runtime instead of pooling
- Not using audio buses for volume categories (Music, SFX, UI, Voice)
- Using `_process()` for audio timing instead of signals (`finished`)
- Confusing `attack_us` (µs) with `release_ms` (ms) on `AudioEffectCompressor`
