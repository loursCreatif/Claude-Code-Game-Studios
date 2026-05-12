# Audio System

> **Status**: Draft r2.3 — Phase A+B+C+D + `/design-review` Phase C+D 8 BLOCKING fixes appliqués 2026-05-03 (audio-director + qa-lead + godot-specialist + game-designer 4 specialists adversariaux, convergence forte sur 5 BLOCKING actionnables). r2.2 → r2.3 : (1) Phase D.3 orphan tracker fix (erase `_active_clac_players[slot_idx]` AVANT stop() round-robin + cleanup pré-connect si slot recyclé + `Dictionary[int, bool]` typed + defensive disconnect) ; (2) AC-AUD-01 (d) enrichi `compressor.attack_us == 5000` + `release_ms == 200.0` API verification (gotcha nommage asymétrique long-standing Godot — pas breaking 4.x — engine-ref dump 2026-05-03 résolution Phase D.5) ; (3) AC-AUD-04 (e/f) + AC-AUD-06 (e/f) boundary cases `D=0`/`D=-1`/`R=0`/`R=-1` Formula 1/2 guards Phase C ; (4) **AC-AUD-20 nouveau** Phase D.2 double-boot idempotent guard formal coverage ; (5) **AC-AUD-21 nouveau** F-04 linear-amplitude midpoint anti-regression Phase C ; (6) AC-AUD-15 split en 15-a BLOCKING headless-testable + 15-b ADVISORY `AudioEffectRecord` headless-conditional ; (7) F-04 EQUAL_POWER compromis : LINEAR default mais Sprint Audio Day 1 test A/B BLOCKING (escalade explicite, pas "plus tard") ; (8) AC-AUD-13 (e/f/g) sub-budgets handler/play_3d_at/sidechain CPU isolés Phase D.4. Précédentes phases : r2.2 Phase A+B+C+D complete (2026-05-03) + `/consistency-check audio-system` PASS (1 stale prose fix ligne 422 `100 ms → 50 ms` SLOW_MO_DURATION) ; Amendement éditorial 2026-04-28 (NB-CRD-6 Option A — secret collect clac pitch +5 semitones bus `SFX`) ; Phase A vision + Phase B spec + 14 BLOCKING re-review r2.1 fixes appliqués 2026-04-27.
>
> **Phase A vision (vision call CD adjudications + Martin D3)** :
> - **D3 Martin REOPEN tranchée Option A** : pitch-shift -2..-4 semitones autorisé sur `COMBAT_KILL` + `AMBIENCE` sous slow-mo via allowlist bus-level. `MUSIC` + `SWING_ACTIVE` invariants. Rule 11 réécrite, Formula 5 ajoutée, AC-AUD-15 reformulée. ADR-0009 D-3 amendé (allowlist `pitch_scale_follows_time_scale` per bus).
> - **Couche 1 vs Couche 3 mix contradiction résolue par mécanisme** (CD reco) : sidechain compressor sur bus `MUSIC` feed depuis `COMBAT_KILL` 0 dB → -3 dB attaque 5 ms / release 200 ms. Plus de prose contradictoire — un fichier `default_bus_layout.tres` opérationnel. Nouvelle Rule 16 + Formula 6, ADR-0009 D-1 amendé.
> - **Multi-kill noop comblé** (CD reco) : pitch-shift +2 semitones existing clac sur 2e/3e kill du même swing (pas asset nouveau). Rule 13 réécrite, AC-AUD-05 reformulée.
> - **death.wav 60-80 ms + overlap** (CD reco) : raise 40 → 60-80 ms + overlap on first respawn frame autorisé (ne PAS extend RESPAWN_DELAY). Rule 14 réécrite, knob updated, AC-AUD-07 reformulée.
> - **Pool sizing** (CD reco) : 2D 4→5, 3D 8→12 — Rule 2 + Tuning Knobs updated.
> - **Bus naming UPPER_SNAKE_CASE** (CD reco) : `SWING_ACTIVE`, `COMBAT_KILL`, `MUSIC`, `AMBIENCE`, `UI`, `SFX`, `MASTER` — déjà appliqué r1 partiellement, propagé partout r2.
>
> **Phase A signal contract** : Level Open Question #1 RESOLVED Option C (Audio consume `level_active` + lookup `get_etage_audio_streams`). Pas de signal `etage_loaded` créé.
>
> **Phase B spec** : Open Questions #6 (UI mute exclusion MVP : oui mute coupe tout), #7 (room tone Chrome Zen `-12 dB` sub-bass synthwave sustain provisional), #9 (Callable injection `_set_time_provider` debug-guarded `if OS.is_debug_build()` test-only) — tous RÉSOLUS.
>
> **Phase C (formules+ACs) + Phase D (impl)** : ✅ COMPLETE 2026-05-03 (auto-mode chain). Détails dans Section "Implementation Details (Phase D)" + hardening blocks F-01/F-02/F-04 inline dans `## Formulas`. Consistency-check pass 2026-05-03 (registry r17 constants × 18 GDDs scanned, 1 stale prose ligne 422 fixée).
>
> **Author**: Martin + design-system skill r2 Phase A+B (auto mode, solo) — r1 → r2 surgical OQ#1 + Phase A vision + Phase B spec, r2 → r2.1 design-review fresh session 14 BLOCKING fixes (editorial coherence + spec gaps + AC testability + ADR-0002/0009 D-6 reconciliation), r2.1 → r2.2 amendement éditorial NB-CRD-6 Option A (CD adjudication 2026-04-28 — secret collect clac différencié, audio-director Mécanisme α validé)
> **Last Updated**: 2026-05-03 (r2.3 design-review Phase C+D APPROVED — 8 BLOCKING fixes appliqués surgicaux)
> **Last Verified**: 2026-05-03
> **Implements Pillar**: Pillar 1 (FLOW AVANT TOUT — wall-clock fades, zéro hitching), Pillar 3 (UNE SECONDE CHANCE N'EST JAMAIS LOIN — death feedback 60-80 ms wall-clock, overlap respawn frame intentionnel — RESPAWN_DELAY 50 ms figé, queue audio Godot survit scene reload — Rule 14 r2)

## Summary

L'Audio System est l'infrastructure middleware qui livre tous les sons du jeu : SFX combat (swoosh swing, clac kill, blood ambiance), SFX movement (dash, wall-run, jump, death), musique d'étage, ambiance positionnelle, et UI (clicks menu). Il expose une API simple (`play_2d`, `play_3d_at`, `play_music`, `duck_bus`) qui découple les producteurs (Combat/Movement/Level/GSM) de l'implémentation Godot (`AudioStreamPlayer*`, `AudioServer`, bus layout). Toutes les opérations passent par un pool pré-instancié 15 nodes (zéro alloc runtime), tous les fades sont wall-clock dans `_physics_process` (jamais Tween scaled par `Engine.time_scale`), et toutes les connexions consumer sont `CONNECT_DEFERRED` par défaut. Le système préserve la Fantasy staccato Combat sous slow-mo et garantit la latence audio déterministe ≤ 0.5 ms / frame.

> **Quick reference** — Layer: `Core` · Priority: `MVP` · Key deps: `Game State Manager (pause/resume), Camera System (AudioListener3D = Camera3D actif), Level System (music swap par etage), Player Combat (swoosh/clac/blood/ducking), Player Movement (dash/wall-run/jump/death SFX)`

## Overview

L'Audio System est un autoload Godot (`AudioSystem`) qui orchestre la lecture, le mix, le ducking et les fades de tous les sons du jeu. Les autres systèmes (Combat, Movement, Level, GSM) ne connaissent pas l'API Godot audio bas niveau — ils émettent des signals (`enemy_killed`, `dash_started`, `level_active`, `state_changed`) que l'Audio System consomme en `CONNECT_DEFERRED` (Audio lookup `LevelSystem.get_etage_audio_streams` synchrone côté handler `_on_level_active` per Level r4 Option C), et appellent au besoin des verbes haut niveau (`AudioSystem.play_music(...)`, `AudioSystem.duck_bus(...)`). Le découplage est total : aucun consumer ne crée de `AudioStreamPlayer.new()`, ne touche `AudioServer.set_bus_volume_db()`, ni n'instancie `AudioListener3D`. Le joueur expérimente l'Audio System indirectement (il ne pense jamais "le bus SFX est ducked") mais directement aussi : la qualité du mix EST la sensation rythmique Combat (clac net post-silence) et la sensation proprioceptive Movement (swoosh head-locked du katana). L'architecture complète est figée par **ADR-0009 Accepted 2026-04-27** (6 décisions D-1..D-6, hiérarchie 7 buses, pool 15 nodes, fades wall-clock `_get_time_msec` Callable injection, spatialisation 2D head-locked vs 3D positional, AudioListener3D = Camera3D actif).

## Player Fantasy

Le joueur ne pense jamais à l'Audio System — il **sent** ses effets. La Fantasy se décompose en trois couches superposées :

**Couche 1 — Le silence rythmique post-clac.** À chaque kill, l'image se fige micro-pause, le clac sec (transitoire 800Hz-4kHz, attack < 5 ms) tombe au centre du mix, puis presque rien — juste la blood ambiance qui gicle 50 ms wall-clock plus tard, comme une note tenue dans une mesure courte. Le swoosh swing est déjà coupé (fade-out 30 ms wall-clock indépendant du slow-mo), l'ambient room est ducked -3 dB, le bus `SWING_ACTIVE` est ducked -6 dB. Le joueur perçoit une **clarté rythmique** — pas une accumulation additive de sons. C'est la même sensation que la chambre d'écho post-coup dans Sekiro ou Hotline Miami : silence devient instrument.

**Couche 2 — Le swoosh proprioceptif sans viewmodel.** Au MVP, il n'y a pas de katana 3D visible (Tier 2). Le swoosh swing 2D head-locked (`AudioStreamPlayer` ego-positioned) est l'**unique feedback proprioceptif** que la lame existe. Le son joue toujours à hauteur d'oreille, jamais positionnel — comme si le katana était une extension du corps cybernétique du joueur. Référence : le whoosh d'Akira ou de Ghost in the Shell sur les coups au sabre. Sans ce son, le joueur ne saurait pas qu'il a swingé.

**Couche 3 — La continuité musicale invisible (mécanisme : sidechain compressor)**. La musique d'étage traverse les checkpoints, les morts, les pauses (avec fade -∞ dB sur pause, restore au resume), et crossfade sur `level_active` du Level System (Audio handler lookup `get_etage_audio_streams(etage_id)`, r2 Option C). Le joueur n'entend jamais la musique se couper brutalement. **Mais** la continuité Couche 3 entre en tension directe avec Couche 1 (silence rythmique post-clac) — si la `MUSIC` joue à -3 dB pendant qu'un clac `COMBAT_KILL` tombe à 0 dB, la musique masque le silence rythmique et la Fantasy se brise. Le fix r2 (CD reco Phase A) est **mécaniste, pas verbal** : un **sidechain compressor** sur bus `MUSIC` feed depuis bus `COMBAT_KILL` (Rule 16, Formula 6) — au moment du clac, `MUSIC` ducked instantanément 0 dB → -3 dB attaque 5 ms, release 200 ms. La continuité Couche 3 est préservée (la musique ne s'arrête jamais), Couche 1 est préservée (le clac perce un trou ducked pendant ~250 ms — silence rythmique audible). Le `default_bus_layout.tres` Godot porte cette logique, pas la prose. Ambient room (sub-bass continu Chrome Zen `-12 dB` synthwave sustain — OQ#7 résolu r2) maintient un tapis sonore minimaliste qui survit à 30 morts dans la même salle.

**Couche 4 — Le drone HLM en slow-mo (r2 Phase A — Martin D3 Option A)**. Pendant `Engine.time_scale = 0.3` (slow-mo Combat sur kill), les bus `COMBAT_KILL` (queue blood ambiance) et `AMBIENCE` (sub-bass room tone) descendent de **-2 à -4 semitones** (allowlist bus-level `pitch_scale_follows_time_scale = true`). Le clac sec lui-même reste invariant (attack < 5 ms n'a pas le temps de se pitcher — c'est la **decay/queue** qui drone-down). Cette signature pitch-shift recrée l'identité Hotline Miami sans casser la lisibilité rythmique : `MUSIC` invariant (pas de pitch musical perturbé), `SWING_ACTIVE` invariant (swoosh head-locked proprioceptif stable). Référence : la mort dans HLM 1, où le synthwave drone descend en spirale pendant que tout ralentit. Audio dB chiffres + bus allowlist dans Rule 11 réécrite + Formula 5 nouvelle.

**Anti-fantasy** : Aucun son redondant, aucune queue de réverb longue (incompatible Pillar 1), aucun pitch shift sur `MUSIC` ni `SWING_ACTIVE` (préservation Couche 2 + Couche 3), aucun ducking continu prolongé (release ≤ 250 ms wall-clock pour ne pas fatiguer auditivement).

## Detailed Rules

### Core Rules

1. **API publique exclusive — accès interdit aux APIs Godot brutes**. Tout système consumer DOIT passer par les verbes `AudioSystem.play_2d(stream, bus)`, `AudioSystem.play_3d_at(stream, position, bus)`, `AudioSystem.play_music(stream, fade_seconds)`, `AudioSystem.stop_music(fade_seconds)`, `AudioSystem.duck_bus(bus, delta_db, release_ms)`, `AudioSystem.set_paused(paused)`. **Forbidden** : `AudioStreamPlayer.new()` runtime, `AudioServer.set_bus_volume_db()` direct, `AudioListener3D.new()` instanciation. Lint CI vérifie l'absence de ces patterns hors `src/core/audio_system.gd` lui-même.

2. **Pool pré-alloué 20 nodes au boot, jamais étendu runtime** (r2 Phase A CD reco — pools augmentés vs r1 4+8 → 5+12 pour absorber MVP scenarios stress + multi-kill blood ambiance overlaps) :
   - **5×** `AudioStreamPlayer` 2D head-locked (swoosh, UI clicks, dash_reject, walljump, death — MVP scenario : 1 swoosh + 1 dash + 1 walljump + 1 death + 1 UI overlap = 5 simultanés possible)
   - **12×** `AudioStreamPlayer3D` positional (clac kill + blood ambiance × jusqu'à `MAX_KILLS_PER_SWING=3` simultanés + footsteps ennemis Tier 2 + environmental SFX + headroom)
   - 1× `AudioStreamPlayer` Music (single instance — fades wall-clock)
   - 2× `AudioStreamPlayer` Ambience (crossfade entre rooms / level_active)

   Total pool **20 nodes** (5+12+1+2). Round-robin via index `_2d_index`, `_3d_index`. Si pool saturé : `push_warning` + `stop()` → `play()` interrompt le sample en cours (cf. ADR-0009 D-2 Note pool saturation R-1). Tuning knobs `pool_2d_size` safe range `[5, 8]`, `pool_3d_size` safe range `[12, 16]`. Mémoire static : ~20 KB Nodes au boot (pas runtime alloc).

3. **Bus hierarchy fixée — 7 buses immutables au MVP**. Définis dans `res://default_bus_layout.tres` chargé par `project.godot audio/buses/default_bus_layout`. Hiérarchie (UPPER_SNAKE_CASE canonique r2 CD reco #5) :
   ```
   MASTER (idx 0)
   ├── MUSIC (idx 1)
   ├── SFX (idx 2)
   │   ├── SWING_ACTIVE (idx 3) — bus swoosh swing en cours
   │   └── COMBAT_KILL (idx 4) — bus clac kill + blood ambiance
   ├── AMBIENCE (idx 5)
   └── UI (idx 6)
   ```
   Helper static `AudioBuses` expose les noms en constantes `StringName` (PAS un autoload — collision identifiant `class_name` ↔ autoload évitée per mémoire `feedback_godot_class_name_autoload_collision.md`). Voice/VO bus différé Tier 2+. **Naming canonique** : tous les noms de bus en UPPER_SNAKE_CASE partout dans le doc + `default_bus_layout.tres`. Aucun lowercase legacy r1.

4. **Wall-clock fades dans `_physics_process` exclusivement — Tween interdit sur `volume_db` time-critical**. Tout fade audio sensible à la slow-mo (fade-out swoosh 30 ms, ducking release 30 ms) DOIT être interpolé via `_get_time_msec: Callable = Time.get_ticks_msec` dans `_physics_process` (autorité simulation ADR-0001 60 Hz). **Forbidden** : `Tween.tween_property(player, "volume_db", ...)` pour fades sensibles — Tween tourne dans `_process` qui scale par `Engine.time_scale`, un fade 30 ms wall-clock devient 100 ms perçus à `time_scale=0.3` → casse Fantasy staccato (Combat AC-CMB-51 vérifie). Tween reste autorisé pour music crossfade entre rooms quand `time_scale == 1.0` est garanti (e.g. transitions Level non-combat).

5. **Mode connexion `CONNECT_DEFERRED` par défaut sur tous les signals consumer**. Chaque handler audio (Combat, Movement, Level, GSM) connecte avec flag `CONNECT_DEFERRED` — cohérent ADR-0005 D-5 (instanciation Node + `play()` = opérations lourdes > 256 B alloc + > 0.5 ms). Aucune exemption SYNC pour Audio au MVP. Forbidden grep CI : `\.connect\(.*\)(?!.*CONNECT_DEFERRED)` dans `src/gameplay/audio/` ou `src/core/audio_system.gd` handlers — fail si match.

6. **Spatialisation 2D vs 3D figée par event-type**. Décision matrix (Section D.5 ADR-0009) :
   - **2D head-locked** (`AudioStreamPlayer`) : swoosh swing (proprioceptif joueur), UI clicks, music, ambience non-positionnelle, dash, wall-run loop, wall-jump, death.wav, dash_reject.wav.
   - **3D positional** (`AudioStreamPlayer3D`) : clac kill impact, blood ambiance, footsteps ennemis (futur), environmental SFX (door, trigger, hazard).
   - **Décision tranchée par event** dans Section "Visual/Audio Requirements" du présent GDD — pas de ré-arbitrage par sound-designer Sprint Audio.

7. **Position payload pour signals 3D — capture au tick d'émission, pas de read au tick de réception**. Pour signals comme `enemy_killed(enemy: Node, position: Vector3)`, l'Audio handler DOIT utiliser le champ `position` du payload (capturé par Combat au tick d'émission), JAMAIS `enemy.global_position` au moment de la réception DEFERRED — l'ennemi peut être `queue_freed` entre l'émission frame N et la réception frame N+1 → crash null reference (Combat AC-CMB-audio r4 A-03 fix).

8. **Ownership AudioStreamPlayer3D — pool ou scene root, JAMAIS attaché au noeud émetteur**. Tous les `AudioStreamPlayer3D` du pool vivent dans le node `AudioSystem` autoload, OU dans le scene root de la salle Level active. **Forbidden** : `add_child(audio_player_3d)` sur un ennemi `CharacterBody3D` — le `queue_free()` de l'ennemi avant la fin du sample produit un pop sonore (sample tronqué) ou un crash si l'ennemi est freed mid-`play()`.

9. **AudioListener3D enfant explicite Camera3D (per ADR-0002 chain) — pas de second listener côté Audio** (r2 alignment ADR-0009 D-6 amendement Phase A re-review). Audio System ne doit JAMAIS appeler `AudioListener3D.new()` ni instancier un listener supplémentaire — exactement 1 listener doit exister dans la scene tree, celui prescrit par ADR-0002 chain `... → CameraEffects → Camera3D → AudioListener3D` (VC-5 ADR-0002). Avec un seul listener présent, Godot 4.6 l'utilise automatiquement comme listener actif (pas besoin de `make_current()` explicite). Si Audio System créait un second listener : conflit `current=true` invariant et casse spatialisation. AC-AUD-14 (c) vérifie `size() == 1` (pas zéro — un listener explicite ADR-0002 est attendu). **Vérification empirique requise** Sprint Audio : confirmer comportement avec SubViewport edge case Camera3D (R-2 ADR-0009).

10. **Pause/resume — silence total via `Master` bus mute**. Sur `state_changed(PAUSED)` GSM, l'Audio System mute le bus Master (`AudioServer.set_bus_mute(0, true)`). Sur `state_changed(PLAYING)` (resume), unmute. Aucun `AudioStreamPlayer.stream_paused = true` individuel — trop fragile, oublis garantis. Le mute Master coupe TOUT (musique, SFX, ambient) en 1 frame. Au resume, les sons en cours reprennent où ils étaient (la queue audio Godot survit au mute).

11. **Pitch shift bus-level allowlist sous slow-mo (r2 Phase A — Martin D3 REOPEN Option A)**. Comportement par défaut Godot 4.6 (`AudioStreamPlayer.pitch_scale` ne suit PAS `Engine.time_scale`) est conservé. **MAIS** Audio System applique manuellement un pitch shift bus-level pendant slow-mo via allowlist :
    - **Bus avec `pitch_scale_follows_time_scale = true`** : `COMBAT_KILL` (queue blood ambiance UNIQUEMENT — voir exclusion clac ci-dessous), `AMBIENCE` (room tone). Pitch descendu selon Formula 5 (`pitch_semitones = lerpf(0.0, -3.0, 1.0 - time_scale)` borné `[-4.0, 0.0]` → à `time_scale=0.3` → ≈ -2.1 semitones).
    - **Bus avec `pitch_scale_follows_time_scale = false`** : `MUSIC`, `SWING_ACTIVE`, `UI`, `SFX`, `MASTER`. Invariants — préservent Couche 2 (swoosh proprioceptif), Couche 3 (continuité music), feedback UI clarity.
    - **Exclusion explicite clac sur `COMBAT_KILL`** : le slot `AudioStreamPlayer3D` jouant `clac.wav` (transient < 5 ms attack) est EXCLU du pitch shift bus-level. Seuls les slots jouant `blood_ambiance.wav` (delay 50 ms post-clac) reçoivent `pitch_scale` modifié. Identification slot : Audio System tracke `_active_clac_players: Dictionary[int, bool]` (key = pool index 3D, value = `true` si slot joue actuellement le `clac_stream`). La boucle pitch-shift skip ces indexes. Cette exclusion préserve Fantasy Couche 1 (clac sec invariant pour lisibilité rythmique) tout en livrant Fantasy Couche 4 (blood ambiance drone-down identité HLM).
    - **Mécanisme application** : Audio handler `_on_state_changed` (PAUSED/PLAYING transitions) ou tick `_physics_process` détecte `Engine.time_scale != 1.0` et itère `AudioStreamPlayer*` pool actifs (`playing == true`) appartenant aux bus allowlisted. Pour chaque player éligible (hors `_active_clac_players`), set `player.pitch_scale = 2.0 ** (semitones / 12.0)`.
    - **Sons démarrés pendant slow-mo** : le handler dispatch (`_on_enemy_killed`, `_on_level_active`, etc.) détecte `Engine.time_scale != 1.0` AVANT `play()` et set `player.pitch_scale` à la valeur Formula 5 sur les bus allowlisted (hors clac). Le pitch est donc appliqué *avant* `play()`, pas après — pas de latence 1 tick. Code path normal (`time_scale == 1.0`) skip cette branche pour zéro overhead.
    - **Fantasy alignment** : recrée l'identité Hotline Miami (drone bass descendant en slow-mo) sans casser lisibilité rythmique du clac (attack < 5 ms invariant via exclusion explicite). Référence sonique HLM préservée — voir Player Fantasy Couche 4.
    - **Forbidden au MVP** : pitch shift sur transitoires hard (`COMBAT_KILL` clac attack via `_active_clac_players` exclusion, `SWING_ACTIVE` swoosh impact via allowlist=false). Le `pitch_scale_follows_time_scale = true` sur `COMBAT_KILL` n'affecte que les slots blood ambiance (delay 50 ms wall-clock post-clac, en territoire slow-mo perçu).
    - **R-3 ADR-0009 vérification empirique** Sprint Audio : confirmer que `pitch_scale` runtime mid-`play()` n'introduit pas de pop sonore (tester transition `1.0 → 0.7935 → 1.0`). AC-AUD-15 (c) protocole : waveform analysis post-render (FFT) — seuil discontinuité ≤ 3 dB peak entre frames adjacents acceptable.

12. **Ducking event-driven, pas Tween-driven**. Sur `enemy_killed`, l'Audio handler appelle `AudioSystem.duck_bus(AudioBuses.SWING_ACTIVE, -6.0, 30.0)` qui :
    - Applique instantanément `set_bus_volume_db(swing_active_idx, ducked_volume = nominal - 6)`
    - Démarre une release wall-clock 30 ms dans `_physics_process` avec `_get_time_msec()` exponentielle (cohérente comportement Godot AudioBusLayout compressor + perception psychoacoustique exponentielle dB) — courbe : `linear_to_db(lerpf(db_to_linear(ducked_volume), db_to_linear(nominal_volume), t))` où `t = elapsed / 30 ms`.
    - Termine au plein volume nominal après 30 ms wall-clock.
    
    **Note dB linear vs perceptual** (ADR-0009 D-3) : pour fade ≤ 30 ms, `lerpf(0.0, -80.0, t)` linéaire dB est acceptable (non-linéarité perceptuelle imperceptible). Pour music crossfade ≥ 1 s : utiliser conversion perceptuelle (futur Music ADR Tier 2).

13. **Multi-kill clac avec pitch-shift +N semitones (r2 Phase A CD reco — comble trou Fantasy MVP)**. Counter `_kill_count_this_swing: int` côté Audio handler — owned by Audio System, pas Combat. Reset à `0` sur `swing_started`. Sur chaque `enemy_killed` reçu pendant un swing actif :
    - **1er kill** : `_kill_count_this_swing = 1`, clac joué `pitch_scale = 1.0` nominal.
    - **2e kill (même swing)** : `_kill_count_this_swing = 2`, clac rejoué avec `pitch_scale = 2.0 ** (+2/12) ≈ 1.122` (+2 semitones) — climax sonique du multi-kill.
    - **3e kill (même swing)** : `_kill_count_this_swing = 3`, clac rejoué `pitch_scale = 2.0 ** (+4/12) ≈ 1.260` (+4 semitones) — apex.
    - **4e+ kill** (cas pathologique au MVP — `MAX_KILLS_PER_SWING = 3` Combat) : pitch capé à +4 semitones, blood ambiance joue normalement.
    - **Asset reuse** : pas de stream nouveau, `clac.wav` est rejoué à pitch supérieur via `pitch_scale` natif Godot.
    - **Blood ambiance** joue indépendamment pour chaque `enemy_killed` (sang gicle perceptible N fois) — aucun pitch-shift sur blood (préserve cohérence stéréo positional 3D).
    - **Saturation guard** : si `pool_3d` saturé, blood la plus ancienne interrompue (round-robin). Au MVP `MAX_KILLS_PER_SWING = 3` → 3 blood max sur pool 12 = pas de saturation.
    - **Tuning knob** `multi_kill_pitch_shift_semitones` default `+2` per kill rank (`+0/+2/+4`), safe range `[+1, +4]` per rank.
    - Contrat **mis à jour** Combat AC-CMB-audio-01 : multi-kill noop → pitch-shift climax sonique. Audio System owns flag `_kill_count_this_swing` (pas Combat).

14. **Death feedback 60-80 ms + overlap on first respawn frame (r2 Phase A CD reco — perceptual constraint physical 60-100 ms)**. `death.wav` joué sur signal Movement `died` DOIT être dans `[60, 80]` ms wall-clock — durée sub-`60ms` est perceptuellement insuffisante pour reconnaître le timbre (seuil reconnaissance 60-100 ms). RESPAWN_DELAY = 50 ms reste figé Movement (Pillar 3 absolu — 50 ms de chute noire entre death et respawn). Le surplus 10-30 ms du `death.wav` overlap sur la première frame du respawn — comportement intentionnel (queue audio Godot survit au scene reload). **Forbidden** : extend RESPAWN_DELAY au-delà de 50 ms pour accommoder le son (Pillar 3 figé Movement ADR-0005 D-9).
    - **Tuning knob** `death_audio_duration_ms` default `70` (mid-range), safe range `[60, 80]`.
    - Asset `death.wav` 60-80 ms validé pré-Sprint Audio par sound-designer.
    - Edge case : si Master mute (PAUSED) au moment du `died`, le sample joue silencieusement et le mute coupe l'overlap respawn — pas de fuite audio. Au resume PLAYING, le sample est déjà fini.

15. **Ambient loop par etage — single AudioStreamPlayer Ambience #1 + crossfade Ambience #2 sur `level_active`** (r2 Option C). Level System émet `level_active(etage_id, player_start)` (signal existant Level GDD r3+) — Audio handler `_on_level_active(etage_id, _player_start)` lookup synchrone `streams := LevelSystem.get_etage_audio_streams(etage_id) -> Dictionary{music, ambient}` puis :
    - Si `streams.is_empty()` : `push_warning("AudioSystem: no audio mapping for etage_id={etage_id}, fallback silence")` + return early (gracieusement dégradé). Lint authoring Level CI gate ce cas.
    - Sinon : `play_music(streams.music)` (fade-in 1 s) + `Ambience #1 → streams.ambient` crossfade 1 s wall-clock (Formula 4).
    - `Ambience #1` joue le précédent ambient stream avec `volume_db = 0`.
    - `Ambience #2` charge le nouveau stream et `play()` à `volume_db = -80`.
    - Crossfade `_physics_process` 1 s wall-clock (autorisé Tween si `time_scale == 1.0` garanti — Level transitions hors combat).
    - À fin crossfade : `Ambience #1` swap stream pour le suivant, `volume_db = 0` ; `Ambience #2` `volume_db = -80` (idle).
    - Sur `level_unloading(etage_id)` : `stop_music(0.5)` + `Ambience #1.volume_db → -80 dB` 0.5 s wall-clock.

16. **Sidechain compressor sur `MUSIC` feed depuis `COMBAT_KILL` (r2 Phase A CD vision call — résout Couche 1 vs Couche 3)**. Le bus `MUSIC` reçoit un effet `AudioEffectCompressor` configuré en sidechain sur le bus `COMBAT_KILL`. Quand `COMBAT_KILL` joue (clac à 0 dB), le compressor amorce l'atténuation à l'onset du clac et atteint le ducking peak en ~5 ms (durée attack) :
    - **Threshold** : -24 dB (sensible aux clacs même à -12 dB nominal)
    - **Ratio** : 4:1 (réduction modérée — ne crashe pas la musique)
    - **Attack** : 5 ms (peak ducking atteint à t=5 ms post-onset clac — le transient pur < 5 ms n'est PAS ducked, par construction. Le silence rythmique audible Couche 1 concerne la queue post-transient + blood ambiance ~250 ms, pas le transient lui-même qui perce à 0 dB)
    - **Release** : 200 ms (laisse le silence rythmique respirer ~250 ms total inclus la queue blood)
    - **Effective ducking peak** : `MUSIC` volume effectif descend à `-6 dB` (peak instantané au fond du ducking ~5-30 ms post-onset), puis remonte exponentiellement vers `-3 dB` nominal sur 200 ms release. Atténuation perçue *moyenne* sur fenêtre 250 ms ≈ `-3 dB` (Tuning Knob `sidechain_music_attenuation_db`). Distinction : -6 dB = peak instantané, -3 dB = atténuation moyenne perceptuelle.
    - **Mécanisme Godot** : `AudioServer.add_bus_effect(MUSIC_idx, AudioEffectCompressor.new())` au boot, configuré avec `sidechain = "COMBAT_KILL"` (`AudioEffectCompressor.sidechain` propriété de type `String`, nom du bus de feed — coercion auto depuis `StringName` `AudioBuses.COMBAT_KILL` par GDScript). API présumée d'après docs Godot officielles 4.x — vérifier empiriquement pré-Sprint Audio. **Update `audio.md` Phase D** : ajouter section `AudioEffectCompressor` documentant `.threshold`, `.ratio`, `.attack_us` (microsecondes), `.release_ms`, `.sidechain` (String) — non encore couvert dans engine reference au moment du r2.
    - **Guard double-effect (Phase D impl)** : si `default_bus_layout.tres` porte déjà le compressor sidechain (idéal — persistence Editor), ne PAS rajouter au `_ready()`. Vérifier via `AudioServer.get_bus_effect_count(MUSIC_idx) == 0` avant `add_bus_effect`.
    - **Fantasy alignment** : Couche 1 (silence rythmique post-clac) coexiste avec Couche 3 (continuité musicale) — la musique ne s'arrête JAMAIS, mais elle ducked pour laisser le clac percer. Mécanisme dans le `default_bus_layout.tres`, pas verbal.
    - **Tuning knob** `sidechain_music_attenuation_db` default `-3.0`, safe range `[-6.0, -1.0]` (au-delà = audible breathing artifact).
    - **Edge case multi-kill** : si `_kill_count_this_swing >= 2` (multi-kill), les clacs successifs prolongent le sidechain ducking (release reset à chaque clac). Cohérent Couche 4 climax sonique multi-kill.
    - **Edge case swings rapides** : deux swings successifs séparés de `SWING_DURATION_MS (120) + cooldown (50) = 170 ms` — release sidechain non terminée (200 ms). Le 2e clac arrive en pleine release, le ducking est cumulatif → ~350-400 ms total. Perceptuellement acceptable (renforce urgence rythmique combat) — valider playtest Sprint Audio. Si pumping indésirable : abaisser `sidechain_release_ms` à ≤ 150 ms via Tuning Knob.

17. **Secret collect clac — pitch +5 semitones sur bus `SFX`, positionnel 3D depuis `secret_node` (r2.2 — NB-CRD-6 Option A creative-director adjudication, audio-director Mécanisme α)**. Sur `Secret.secret_collected(secret_node: Node, tier: int)` reçu en `CONNECT_DEFERRED`, l'Audio handler `_on_secret_collected` :
    - Capture `position := secret_node.global_position` immédiatement au tick de réception (même règle Rule 7 — évite null ref si secret `queue_free` après collect).
    - Joue `play_3d_at(clac_stream, position, AudioBuses.SFX)` avec `pitch_scale = SECRET_PITCH_SCALE` (Formula 7 = `2.0 ** (5.0 / 12.0) ≈ 1.335`).
    - **Bus `SFX`, PAS `COMBAT_KILL`** : le sidechain compressor Rule 16 (`MUSIC ← COMBAT_KILL`) ne s'arme PAS sur un secret — une découverte n'écrase pas la continuité musicale. Le joueur entend le clac aigu sans silence rythmique Couche 1 associé, ce qui différencie sémantiquement kill (rupture) vs secret (découverte). Pillar 4 viscéralité MVP minimum livrée par contraste de timbre + bus + ducking absent (vs présent côté kill).
    - **Pas de ducking `SWING_ACTIVE`** : aucun appel `duck_bus()` — le secret n'est pas un event combat, il ne coupe pas le swoosh en cours.
    - **Pas d'incrément `_kill_count_this_swing`** : le compteur multi-kill est exclusif au combat (Rule 13 r2). Un secret collecté pendant un swing actif ne contamine pas la progression pitch +0/+2/+4 de la Rule 13.
    - **Pas de blood ambiance** : aucun `blood_stream` associé.
    - **Tier indifférent au MVP** : `tier ∈ {1, 2, 3}` reçu mais ignoré — `pitch_scale` identique pour tous les tiers. Extension Tier 2+ : `pitch_scale` variable par tier via tuning knob `secret_tier_pitch_offsets: Array[float]` (réservé contrat futur).
    - **Signal canonique** : `Secret.secret_collected` (upstream, porte `secret_node` avec position 3D). Signal `Credit.credits_changed(source=SECRET)` **non utilisé** côté Audio — pas de position 3D, SYNC, trop downstream.
    - **Collision pitch Rule 13 évitée** : +5 semitones est délibérément hors plage `[+0, +4]` de la Rule 13 multi-kill sur `COMBAT_KILL`. Les deux signaux jouent sur des bus distincts (`COMBAT_KILL` vs `SFX`) — ambiguïté perceptive nulle même si les deux events coïncident dans le même tick (kill + secret collect simultanés).
    - **Asset pipeline** : aucun nouveau asset requis. `clac_stream` existant est réutilisé avec pitch shift paramétrique. Décision audio-director Mécanisme α (vs Mécanisme β bus dédié `SECRET_COLLECT` + asset distinct) — minimalisme palette Chrome Zen synthwave + livraison <2h éditorial validation criteria CD.

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|
| `IDLE` | Boot `_ready()` complete, pool 20 nodes prêts (5+12+1+2 — r2 sizing) | Premier `play_*()` appelé | Pas de son. Bus Master `volume_db = 0` (default). Sidechain compressor `MUSIC ← COMBAT_KILL` armed (Rule 16). |
| `PLAYING` | Au moins un AudioStreamPlayer du pool en `playing == true` | Tous les players idle (queue vide) | Lecture normale. Handlers signals actifs. Fades `_physics_process` actifs si en cours. |
| `MUTED_PAUSED` | GSM `state_changed(PAUSED)` reçu | GSM `state_changed(PLAYING)` reçu (resume) | `AudioServer.set_bus_mute(MASTER, true)`. Aucun nouveau `play_*()` accepté pendant cet état (push_warning + return early). Fades en cours pausés (state preserved : `_swoosh_fade_active`, `_ducking_release_active` maintenus, `_fade_pause_msec` enregistré pour offset `_get_time_msec` au resume). |
| `MUTED_TRANSITION` | GSM `state_changed(SCENE_TRANSITION)` (futur) | Scene loaded, GSM `state_changed(PLAYING)` | Music fade out 0.5 s wall-clock, SFX et ambient mutés instantanément. Au reload scene : pool reset (tous les AudioStreamPlayer en `stop()`, fades reset). |

**Forbidden state transition** : `IDLE → MUTED_*` direct (sans passer par `PLAYING`). Le Master bus mute est un signal externe (GSM), jamais un état interne déclenché par Audio.

### Interactions with Other Systems

| System | Interaction | Owner |
|---|---|---|
| **Game State Manager** (amont) | Signal `state_changed(new_state: State)` consommé en `CONNECT_DEFERRED`. Audio handler `_on_state_changed` mute/unmute Master bus. État `MUTED_PAUSED` ou `MUTED_TRANSITION` activé selon. | GSM owns signal, Audio owns handler. |
| **Camera System** (amont, soft) | Audio System lit le `Camera3D` actif comme `AudioListener3D` (default Godot 4.6). Aucune API call directe. ADR-0002 chain Camera3D scene tree garantit l'invariant `current=true` single-listener. | Camera owns the active Camera3D, Audio reads default behavior. |
| **Level System** (amont) | Signal `level_active(etage_id, player_start)` (Level GDD r3+, formalisé Level r4 §Interactions row Audio) consommé en `CONNECT_DEFERRED`. Handler `_on_level_active(etage_id, _player_start)` lookup synchrone `LevelSystem.get_etage_audio_streams(etage_id) -> Dictionary{music, ambient}` puis `play_music(streams.music)` + crossfade ambient (Formula 4). Signal `level_unloading(etage_id)` → `stop_music(0.5)` + ambient fade-out. Signal `room_entered(room_index, total_rooms)` consommé pour ambient layer swap intra-étage éventuel (optionnel MVP). | Level owns signals + lookup API, Audio owns playback. r2 Option C — pas de signal `etage_loaded` dédié. |
| **Player Combat** (amont) | Signals consommés en `CONNECT_DEFERRED` : `swing_started` → `play_2d(swoosh_stream, AudioBuses.SWING_ACTIVE)` + reset `_kill_count_this_swing = 0`. `swing_ended` → `_start_swoosh_fade()` (30 ms wall-clock) + reset `_kill_count_this_swing = 0`. `enemy_killed(enemy, position)` → counter `_kill_count_this_swing += 1` puis pitch_scale rang (1.0/1.122/1.260 cap), `play_3d_at(clac_stream, position, AudioBuses.COMBAT_KILL)` + tracker `_active_clac_players[slot_idx] = true` (exclusion pitch shift slow-mo Rule 11) + `duck_bus(SWING_ACTIVE, -6, 30)` + `play_3d_at(blood_stream, position, AudioBuses.COMBAT_KILL)` after 50 ms delay wall-clock (slot blood, pitch_scale=Formula5 si time_scale!=1.0). `multi_kill(count)` → **NON connecté côté Audio** (signal Combat ignoré — la logique multi-kill climax est intégralement dans les rangs `enemy_killed` via `_kill_count_this_swing` r2 Rule 13, pas dans `multi_kill` handler). | Combat owns signals, Audio owns dispatch. Contracts AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02 vérifiables côté Audio via mocks. |
| **Player Movement** (amont) | Signals consommés en `CONNECT_DEFERRED` : `dash_started` → `play_2d(dash_stream)`. `dash_rejected` (futur — Movement Open Question) → `play_2d(dash_reject_stream, AudioBuses.UI)` -12 dB. `wall_run_entered` → `play_2d(wallrun_loop_stream)` ; `wall_run_exited` → fade out 100 ms wall-clock. `wall_jumped` → `play_2d(walljump_stream)`. `died` → `play_2d(death_stream)` 60-80 ms duration (Rule 14 r2 — overlap respawn frame intentionnel). `respawned` → noop MVP (silence intentionnel post-respawn pour clarté). | Movement owns signals, Audio owns dispatch. |
| **Secret System** (amont, r2.2) | Signal `secret_collected(secret_node: Node, tier: int)` consommé en `CONNECT_DEFERRED`. Handler `_on_secret_collected` → `play_3d_at(clac_stream, secret_node.global_position, AudioBuses.SFX)` avec `pitch_scale = SECRET_PITCH_SCALE` (Formula 7, default `+5 semitones ≈ 1.335`). Rule 17 — bus `SFX`, PAS `COMBAT_KILL` (sidechain ne s'arme pas — découverte vs rupture). Tier indifférent MVP (extension Tier 2+). NB-CRD-6 Option A creative-director adjudication 2026-04-28 — Pillar 4 viscéralité différenciée par contraste timbre + bus + ducking absent. Résout OQ-SEC-4 (bus dédié `SECRET_COLLECT` rejeté Mécanisme β au profit Mécanisme α paramétrage). | Secret owns signal, Audio owns dispatch. |
| **Input System** (amont, soft) | Pas de connexion directe. UI clicks (menu navigation) via Menu System future, route `play_2d(click_stream, AudioBuses.UI)`. | Input → Menu → Audio (chain indirect). |
| **Accessibility System** (aval, Tier 3) | Audio System expose API `set_bus_volume_db_user(bus, db)` qui persiste dans `audio_settings.tres` (Save/Load Tier 2+). Sliders UI : `master_volume`, `music_volume`, `sfx_volume`. Toggle `subtitles_enabled` (post-MVP, Voice/VO ADR Tier 3). | Accessibility owns UI sliders, Audio owns persistence + AudioServer wiring. |
| **VFX & Feedback** (aval, peer) | Pas d'interaction directe. VFX et Audio sont peers consumers des mêmes signals Combat (`swing_started`, `enemy_killed`, `multi_kill`) — chacun connecte indépendamment. VFX est SYNC pour flash blanc (exemption ADR-0005 D-5 amendment), Audio est DEFERRED. Les deux émettent leurs effets en parallèle frame N+1 par rapport au tick kill. | Combat owns signals, VFX et Audio sont consumers parallèles indépendants. |
| **HUD System** (aval, future MVP) | Aucune interaction. HUD update (credit count, etc.) ne déclenche pas de SFX au MVP — Tier 2+ pour audio feedback HUD (pickup chime, etc.). | — |

### Implementation Details (Phase D)

Cette section codifie les patterns d'implémentation que les stories AudioSystem implémenteront. Tirée des résolutions Phase D issues du re-review r2 — pas de nouvelle décision design, formalisation de patterns déjà implicites dans les Rules.

#### Phase D.1 — `play_3d_at` doit utiliser `global_position` (pas `position`)

`play_3d_at(stream, position, bus)` reçoit en paramètre une **`Vector3` en world space** (`global_position`), jamais une position locale (`position`). Source du payload :

- `enemy_killed(enemy: Node3D, position: Vector3)` — Combat émet `enemy.global_position` capturé au tick N (ADR-0006 D-3). Audio handler passe directement à `play_3d_at`.
- `secret_collected(secret_node: Node, tier: int)` — Audio handler lit `secret_node.global_position` (Rule 17 r2.2).

**Pourquoi** : `AudioStreamPlayer3D.global_position` est utilisé par Godot pour calculer le panning et l'atténuation distance. Passer une position locale produirait un panning relatif au parent du player 3D, soit au mieux faux, au pire `(0,0,0)` head-locked silencieux.

**Implementation contract** (pseudo-code) :

```gdscript
func play_3d_at(stream: AudioStream, world_pos: Vector3, bus: StringName) -> void:
    assert(world_pos.is_finite(), "AudioSystem: world_pos must be finite (got %s)" % world_pos)
    var slot_idx: int = _3d_index
    var player_3d: AudioStreamPlayer3D = _3d_pool[slot_idx]
    _3d_index = (_3d_index + 1) % _3d_pool.size()
    if player_3d.playing:
        # r2.3 — erase tracker AVANT stop() pour éviter orphan slot=true (Phase D.3 fix)
        _active_clac_players.erase(slot_idx)
        player_3d.stop()
        push_warning("AudioPool 3D saturé — interruption slot %d" % slot_idx)
    player_3d.stream = stream
    player_3d.bus = bus     # r2.3 — StringName direct, pas String(bus) cast (no-alloc)
    player_3d.global_position = world_pos     # Phase D.1 — world space, pas position locale
    player_3d.pitch_scale = _resolve_pitch_scale_for_bus(bus)   # avant play (Phase A clarification)
    player_3d.play()
```

**AC-AUD-01 (b) updated** : verify `_3d_pool[i].global_position == enemy_killed_position` post-dispatch (au lieu de `position`).

#### Phase D.2 — Boot guard contre double `add_bus_effect`

Le sidechain compressor `MUSIC ← COMBAT_KILL` (Formula 6) est ajouté via `AudioServer.add_bus_effect(MUSIC_idx, AudioEffectCompressor.new())` au `_ready()` AudioSystem. Si `AudioSystem._ready()` est appelé deux fois (cas pathologique : autoload re-instantiation, scene reload mid-game, test fixture réutilisé), le compressor est ajouté **deux fois**, produisant un ducking exagéré (compression série 16:1 effective) et CPU overhead.

**Guard idempotent** :

```gdscript
func _setup_sidechain_compressor() -> void:
    var music_idx: int = AudioServer.get_bus_index("MUSIC")
    var existing_count: int = AudioServer.get_bus_effect_count(music_idx)
    for i in existing_count:
        var fx: AudioEffect = AudioServer.get_bus_effect(music_idx, i)
        if fx is AudioEffectCompressor:
            push_warning("AudioSystem: AudioEffectCompressor déjà présent sur MUSIC bus, skip add (idempotent)")
            return
    var compressor: AudioEffectCompressor = AudioEffectCompressor.new()
    compressor.threshold = -24.0
    compressor.ratio = 4.0
    compressor.attack_us = 5000     # 5 ms en microseconds (API Godot 4.6)
    compressor.release_ms = 200.0
    compressor.sidechain = "COMBAT_KILL"
    AudioServer.add_bus_effect(music_idx, compressor)
```

**AC-AUD-Sidechain (VC-9) updated** : test scenario "double boot" — appeler `AudioSystem._ready()` 2× en test, vérifier `AudioServer.get_bus_effect_count("MUSIC") == 1` (pas 2).

#### Phase D.3 — `_active_clac_players` tracker (clac slot exclusion pitch shift slow-mo)

Rule 11 (Phase A) exige que les **clacs en cours de play()** ne soient PAS retargetés par Formula 5 pitch shift slow-mo (le clac est un transient < 50 ms, tout pitch shift mid-play produit un click audible). Le tracker `_active_clac_players: Dictionary[int, bool]` (clé = slot index pool 3D, valeur = true si clac actif sur ce slot) permet d'exclure les slots actifs.

**Implementation pattern** :

```gdscript
var _active_clac_players: Dictionary[int, bool] = {}   # slot_idx -> true (Phase D.3 exclusion, typed Godot 4.4+)

func _on_enemy_killed(enemy: Node3D, position: Vector3) -> void:
    # ... compute pitch_scale Rule 13 ...
    var slot_idx: int = _3d_index
    var player_3d: AudioStreamPlayer3D = _3d_pool[slot_idx]
    # r2.3 orphan-prevention: si slot recyclé alors qu'un clac précédent est encore tracké
    # (round-robin a interrompu via stop() avant que `finished` ait fire), cleanup manuel
    # avant nouveau connect — empêche le tracker de croître orphelin et casser pitch shift.
    if _active_clac_players.has(slot_idx):
        _on_clac_finished(slot_idx)   # erase entry + disconnect any leftover one-shot
    player_3d.pitch_scale = clac_pitch_scale    # avant play
    player_3d.play()
    _active_clac_players[slot_idx] = true
    # callback signal finished pour clear le tracker (CONNECT_ONE_SHOT — auto-disconnect après tir)
    player_3d.finished.connect(_on_clac_finished.bind(slot_idx), CONNECT_ONE_SHOT)

func _on_clac_finished(slot_idx: int) -> void:
    _active_clac_players.erase(slot_idx)
    # r2.3 — defensive disconnect au cas où la version one-shot n'a pas encore tiré
    # (cas appelé manuellement depuis _on_enemy_killed sur slot recyclé).
    var player_3d: AudioStreamPlayer3D = _3d_pool[slot_idx]
    for c in player_3d.finished.get_connections():
        if c["callable"].get_method() == "_on_clac_finished":
            player_3d.finished.disconnect(c["callable"])

func _apply_pitch_shift_slow_mo(time_scale: float) -> void:
    # Formula 5 — itere sur pool 3D, skip slots actifs clac
    var pitch_factor: float = pow(2.0, _compute_pitch_semitones(time_scale) / 12.0)
    for slot_idx in _3d_pool.size():
        if slot_idx in _active_clac_players:
            continue   # Phase D.3 — clac actif, pas de retarget pitch
        var p: AudioStreamPlayer3D = _3d_pool[slot_idx]
        if p.playing and _bus_in_pitch_allowlist(p.bus):
            p.pitch_scale = pitch_factor
```

**AC-AUD-04 (b) updated** : verify clac actif au moment de `time_scale = 0.3` garde `pitch_scale = 1.0` (ou rang multi-kill `1.122`/`1.260` selon r2 Rule 13), pas pitch_scale Formula 5.

#### Phase D.4 — Performance split handler / mixer thread

Audio System runs sur le **main thread** uniquement (signaux DEFERRED + AudioServer thread interne Godot). Pas de thread-pool custom. Cohérent ADR-0009 D-9 (no custom threads — AudioServer gère son propre mixing thread en interne).

**Budget perf** (Sprint Audio bench cible) :

| Op | Budget | Mesure |
|----|--------|--------|
| `_on_enemy_killed` handler | < 0.1 ms (16.6 ms / 60 fps frame budget = ~0.6%) | Profile via `Performance.get_monitor(TIME_PROCESS)` |
| `play_3d_at` (pool reuse) | < 0.05 ms | Pas d'allocation hot path |
| `_setup_sidechain_compressor` (boot) | < 5 ms one-shot | `_ready()` perf budget |
| Sidechain compressor CPU runtime | < 0.5% CPU | Mesure post-implémentation, fallback rectangular ducking si > 1% |

**Pourquoi pas de thread split** : la latence input → audio est critique (Pillar 1 FLOW). Un thread split handler/mixer ajouterait une frame de latence (signal DEFERRED frame N+1 → thread queue → mixer thread frame N+2). Inacceptable. Godot AudioServer thread mixing interne est suffisant.

**Si future profiling révèle hotspot dans handler** (Tier 2+, après bench Sprint Audio) : optimiser via :
- Cache `AudioServer.get_bus_index(name)` au boot dans `Dictionary[StringName, int]` (1 lookup vs N).
- Précompute `pitch_scale` array pour `_kill_count_this_swing ∈ [1, 4]` au boot (4 floats constants vs 4 `pow()` per swing).

#### Phase D.5 — `audio.md` engine-reference AudioEffectCompressor section ✅ RESOLVED 2026-05-03

L'engine-reference `docs/engine-reference/godot/modules/audio.md` contient désormais une section **AudioEffectCompressor (Sidechain Ducking)** avec :

- Table des props Godot 4.6 : `threshold` dB, `ratio`, `gain` dB, `attack_us` **microseconds**, `release_ms` **milliseconds**, `mix`, `sidechain` StringName.
- Note critique gotcha : `attack_us` µs vs `release_ms` ms (asymétrie nommage long-standing depuis 3.x — pas un breaking change 4.3→4.6 contrairement à l'hypothèse review r2.3 ; setter sur `compressor.attack` ou `compressor.release` no-op silencieusement).
- Pattern boot guard idempotent (Phase D.2) avec scan `get_bus_effect_count` + type check `is AudioEffectCompressor` avant `add_bus_effect`.
- Bloc verification AC-AUD-01 (d) : assertions `attack_us == 5000.0`, `release_ms == 200.0`, `threshold == -24.0`, `ratio == 4.0`, `sidechain == &"COMBAT_KILL"`.
- Common Pitfalls list (cascade 16:1 si double `add_bus_effect`, `sidechain = &""` = self-sidechain pas no-sidechain).

**Status** : pré-requis Sprint Audio implementation **levé**. Tests `tests/integration/audio/audio_boot_test.gd` peuvent désormais coder AC-AUD-01 (d) sans bloqueur engine-ref.

## Formulas

### Formula 1 — Wall-clock fade-out swoosh (Combat AC-CMB-51 contract)

```
if SWOOSH_FADE_DURATION_MS <= 0.0:
    return SILENCE_DB                                  # F-01 HARDEN — D ≤ 0 = instant silence
t = (current_time_msec - fade_start_msec) / SWOOSH_FADE_DURATION_MS
volume_db(t) = lerpf(NOMINAL_DB, SILENCE_DB, clampf(t, 0.0, 1.0))
```

**Note dB-domain lerp acceptable ici** : F-01 lerp `volume_db` directement (pas db→linear→lerp→linear→db) parce que le swoosh est **mono-source** (pas de mix avec autre signal sur même bus pendant le fade) — pas de risque de dip d'énergie au midpoint comme F-04. La courbe dB-linéaire est suffisamment naturelle pour un fade-out percussif 30 ms (l'oreille entend "rapide → silence", pas une rampe perceptuelle).

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `NOMINAL_DB` | `n` | float | -80.0 to 0.0 | Volume nominal du swoosh sur bus `SWING_ACTIVE`. Default `-6.0` dB (cf. ADR-0009 D-3 Note ducking psychoacoustique). |
| `SILENCE_DB` | `s` | float | -80.0 only | Silence pratique. `-80 dB` = `≤ 0.01% amplitude`. |
| `current_time_msec` | `t_now` | int | `[0, INT64_MAX]` ms | Wall-clock millisecond timestamp via `_get_time_msec.call()` (substituable test, default `Time.get_ticks_msec`). |
| `fade_start_msec` | `t_0` | int | `[0, INT64_MAX]` ms | Timestamp wall-clock au moment où `swing_ended` ou `enemy_killed` a été reçu DEFERRED frame N+1. |
| `SWOOSH_FADE_DURATION_MS` | `D` | float | 30.0 only MVP | Durée fade wall-clock. Tuning knob `swoosh_fade_duration_ms` safe range `[20, 50]`. **Guard** : `D ≤ 0` short-circuite à `SILENCE_DB` (silence instantané, voir Edge Case `D-zero-or-negative`). |

**Output Range** : `volume_db` ∈ `[-80.0, NOMINAL_DB]` borné par `clampf(t, 0.0, 1.0)`. Si `D ≤ 0` → `volume_db = -80.0` immédiat.

**Example** : `NOMINAL_DB = -6.0`, `SWOOSH_FADE_DURATION_MS = 30.0`, `t_0 = 1000 ms`. À `t_now = 1015 ms`, `t = 15/30 = 0.5`, `volume_db = lerpf(-6, -80, 0.5) = -43 dB`. À `t_now = 1030 ms`, `t = 1.0`, `volume_db = -80 dB` (silence). À `t_now = 1050 ms` (au-delà), `t = clampf(20/30, 0, 1) = 1.0`, `volume_db = -80 dB` (fade terminé, idempotent).

**Hardening Edge Case `D-zero-or-negative`** : si tuning knob set à `0.0` ou valeur négative (corruption save, test fixture mal configuré), short-circuit `return SILENCE_DB` — évite division par zéro produisant `+inf` ou `NaN` dans `t = elapsed/D` qui propagerait à `lerpf` et à `set_bus_volume_db` (Godot accepte `NaN` silencieusement → mute permanent inaudible). `push_warning("AudioSystem F-01: SWOOSH_FADE_DURATION_MS={D} ≤ 0, fallback instant silence")` émis 1× au boot si knob invalide.

### Formula 2 — Ducking release perceptuel (linear-amplitude lerp, ADR-0009 D-3)

```
if DUCKING_RELEASE_MS <= 0.0:
    return NOMINAL_DB                                  # F-02 HARDEN — R ≤ 0 = restore nominal instant
t = clampf((current_time_msec - duck_start_msec) / DUCKING_RELEASE_MS, 0.0, 1.0)
amp_lin(t) = lerpf(db_to_linear(DUCKED_DB), db_to_linear(NOMINAL_DB), t)
volume_db(t) = linear_to_db(maxf(amp_lin(t), 1e-9))    # F-02 HARDEN — guard log(0)
```

**Note "exponentielle" (renommé)** : la formule était nommée "exponentielle" en r1, mais elle est techniquement un **lerp linéaire en domaine d'amplitude** (`db_to_linear → lerpf → linear_to_db`). Cette opération produit une **courbe perçue exponentielle en dB** par l'oreille humaine (parce que dB est une échelle logarithmique, et lerper en linéaire = courbe log inversée en dB). C'est l'**équivalent perceptuel correct** pour un release ducking — l'oreille perçoit un retour "doux" sans plateau au midpoint. Renommage Phase C : "perceptuel (linear-amplitude lerp)" pour précision technique. Pas de changement de comportement runtime, seulement de spec.

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `DUCKED_DB` | `d` | float | `[-30, 0]` dB | Volume bus pendant attaque ducking (instantané au tick `enemy_killed` DEFERRED frame N+1). Default `NOMINAL_DB - 6 = -12 dB`. |
| `NOMINAL_DB` | `n` | float | `[-30, 0]` dB | Volume bus en régime normal (avant ducking). `SWING_ACTIVE` nominal `-6 dB` per ADR-0009 D-3 note. |
| `current_time_msec` | `t_now` | int | `[0, INT64_MAX]` ms | Wall-clock via `_get_time_msec.call()`. |
| `duck_start_msec` | `t_0` | int | `[0, INT64_MAX]` ms | Timestamp wall-clock du tick `enemy_killed` réceptionné DEFERRED. |
| `DUCKING_RELEASE_MS` | `R` | float | 30.0 MVP | Durée release wall-clock. Tuning `ducking_release_ms` safe `[20, 50]`. Aligné Combat AC-CMB-audio-02. **Guard** : `R ≤ 0` short-circuite à `NOMINAL_DB` (restore instantané). |

**Conversion functions** (Godot 4.6 builtin) : `db_to_linear(x) = pow(10.0, x / 20.0)`, `linear_to_db(x) = 20.0 * log(x) / log(10.0)`.

**Output Range** : `volume_db` ∈ `[DUCKED_DB, NOMINAL_DB]`. Si `R ≤ 0` → `volume_db = NOMINAL_DB` immédiat.

**Example** : `NOMINAL_DB = -6`, `DUCKED_DB = -12`, `R = 30 ms`, `t_0 = 1000`. À `t_now = 1000` (instantané) : `volume_db = -12 dB`. À `t_now = 1015` (50% release) : `db_to_linear(-12) = 0.251`, `db_to_linear(-6) = 0.501`, `lerpf(0.251, 0.501, 0.5) = 0.376`, `linear_to_db(0.376) = -8.5 dB`. À `t_now = 1030` (100% release) : `volume_db = -6 dB` nominal restauré.

**Hardening Edge Case `R-zero-or-negative`** : si knob set à `0.0` ou négatif → short-circuit `return NOMINAL_DB` (restore bus immédiat). Évite `+inf` dans `t` propagé à lerp (donnerait `db_to_linear(NOMINAL_DB)` = nominal direct par clamp à 1.0, mais defensive guard explicite). `push_warning("AudioSystem F-02: DUCKING_RELEASE_MS={R} ≤ 0, fallback instant restore")` 1× boot.

**Hardening Edge Case `amp-near-zero log-guard`** : `linear_to_db(0)` = `-inf` (log 0 indéfini, Godot retourne `-inf` qui propage à `set_bus_volume_db` produisant mute permanent). Si `DUCKED_DB ≤ -180 dB` (pathologique config), `db_to_linear(-180) ≈ 1e-9` lerp peut clamp en dessous du seuil flottant. Guard `maxf(amp_lin, 1e-9)` borne la log à `-180 dB` au minimum (suffisant — bien sous seuil audible `-80 dB`). N/A dans plages MVP `DUCKED_DB ∈ [-30, 0]`.

### Formula 3 — Pool round-robin index advance

```
next_index = (current_index + 1) % pool_size
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `current_index` | int | `[0, pool_size - 1]` | Index courant (tracker `_2d_index` ou `_3d_index`). |
| `pool_size` | int | 5 (2D) ou 12 (3D) | Taille pool fixée boot (r2 sizing). Tuning knobs `pool_2d_size` / `pool_3d_size`. |

**Edge case** : si `pool[next_index].playing == true` (saturation), le slot est interrompu via `stop()` puis réutilisé. `push_warning("AudioPool 2D saturé")` émis. Pas de fallback alloc dynamique (forbidden).

### Formula 4 — Crossfade ambient duration (Level level_active + get_etage_audio_streams)

**r2.1 Phase C — equal-power-style crossfade (linear-amplitude lerp)** : la version r2 dB-domain lerp produisait une **double atténuation au midpoint** (à `t=0.5`, vieux et nouveau bus tous deux à `-40 dB` → puissance combinée perçue ≈ `-37 dB`, dip audible de ~3 dB). Phase C corrige en lerpant l'amplitude linéaire (équivalent perceptuel correct, énergie sommée plus stable au milieu pour deux signaux décorrélés comme music tracks différentes).

```
if CROSSFADE_DURATION_MS <= 0.0:
    set_old_to(SILENCE_DB); set_new_to(0.0)            # F-04 HARDEN — D ≤ 0 = swap instantané
    return
t = clampf((current_time_msec - crossfade_start_msec) / CROSSFADE_DURATION_MS, 0.0, 1.0)
amp_old(t) = lerpf(1.0, 0.0, t)                        # 0 dB → silence en domaine linéaire
amp_new(t) = lerpf(0.0, 1.0, t)                        # silence → 0 dB en domaine linéaire
volume_db_old(t) = linear_to_db(maxf(amp_old(t), 1e-4))   # clamp à -80 dB
volume_db_new(t) = linear_to_db(maxf(amp_new(t), 1e-4))   # clamp à -80 dB
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `CROSSFADE_DURATION_MS` | float | 1000.0 default | Durée crossfade ambient. Tuning `ambient_crossfade_ms` safe `[500, 2000]`. **Guard** : `D ≤ 0` short-circuite à swap instantané. |
| `current_time_msec` | int | `[0, INT64_MAX]` | Wall-clock. |

**Output Range** : `volume_db_old ∈ [-80, 0]` décroissant, `volume_db_new ∈ [-80, 0]` croissant. Au midpoint `t=0.5` : `amp_old = amp_new = 0.5` → `volume_db_old = volume_db_new ≈ -6 dB` (au lieu de `-40 dB` en lerp dB-domain). Énergie combinée perçue ≈ `0 dB` (signaux décorrélés se somment ≈ `√2`× = +3 dB, soit ~+3 dB perçus mais sans dip — résultat équivalent-power acceptable pour music crossfade ambient).

**Note** : ce fade peut utiliser `Tween.tween_property` (sur `volume_db` de chaque AudioStreamPlayer) si on précompute la courbe linear→dB chaque tick, OU implémenter directement en `_physics_process` wall-clock. La r2.1 Phase D recommande l'implémentation `_physics_process` (cohérence avec F-01/F-02, élimine dépendance Tween scaled par `time_scale` même si garanti `1.0` par contrat Level T-2 — defense in depth). Si futur Level autorise slow-mo en transition, le `_physics_process` wall-clock est déjà robuste.

**Hardening Edge Case `D-zero-or-negative`** : si knob set à `0.0` ou négatif → swap instantané (`amp_old=0`, `amp_new=1`). Évite division par zéro propagée à l'interpolateur. `push_warning("AudioSystem F-04: CROSSFADE_DURATION_MS={D} ≤ 0, fallback instant swap")` 1× boot.

**Hardening Note — equal-power vs linear-amplitude (r2.3 audio-director re-review feedback)** : un crossfade equal-power strict utiliserait des courbes en sinus/cosinus (`amp_old = cos(t·π/2)`, `amp_new = sin(t·π/2)`) qui maintiennent `amp_old² + amp_new² = 1` exactement (puissance constante). MVP utilise lerp linéaire (`amp_old + amp_new = 1` mais puissance sommée varie ~3 dB sur [0, 0.5, 1]) — c'est un **swell perceptible** au midpoint pour ambient à `-12 dB` Chrome Zen avec sub-bass corrélé entre tracks synthwave. Le tuning knob `ambient_crossfade_curve` enum `LINEAR | EQUAL_POWER` permet l'escalade. **R2.3 décision compromise** : default reste `LINEAR` (impl plus simple Phase D), MAIS test A/B Sprint Audio Day 1 **BLOCKING** : sound-designer compare `LINEAR` vs `EQUAL_POWER` cosinus sur tracks synthwave réelles à -12 dB ambient ; si swell midpoint détecté (différence A/B audible), bascule du default `EQUAL_POWER` AVANT release candidate. Pas de "escalader plus tard" — la décision est gate-checked Sprint Audio. Évite shipper un default LINEAR connu défectueux par défaut d'attention.

### Formula 5 — Pitch shift bus-level sous slow-mo (r2 Phase A — Martin D3 Option A)

```
pitch_semitones(time_scale) = clampf(lerpf(0.0, -3.0, 1.0 - time_scale), -4.0, 0.0)
pitch_scale(time_scale) = 2.0 ** (pitch_semitones(time_scale) / 12.0)
```

Appliqué SEULEMENT sur les bus avec `pitch_scale_follows_time_scale = true` (allowlist Rule 11) : `COMBAT_KILL`, `AMBIENCE`. Bus invariants (`MUSIC`, `SWING_ACTIVE`, `UI`, `SFX`, `MASTER`) gardent `pitch_scale = 1.0`.

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `time_scale` | float | `[0.1, 1.0]` | Engine.time_scale courant. Combat slow-mo MVP = 0.3 (registry après alignement r1). |
| `pitch_semitones` | float | `[-4.0, 0.0]` | Pitch shift en demi-tons. Mapping linéaire dans `time_scale ∈ [1.0, 0.0]` borné à -4 semitones max (clamp éviter pitch trop grave inintelligible). |
| `pitch_scale` | float | `[~0.7937, 1.0]` | Multiplicateur Godot `AudioStreamPlayer.pitch_scale`. À time_scale=0.3 → semitones≈-2.1 → pitch_scale≈0.8821. |

**Output Range** : à `time_scale=1.0` → `pitch_scale=1.0` (no-op). À `time_scale=0.3` (Combat slow-mo) → `pitch_scale ≈ 0.8821` (≈ -2.1 semitones, "drone-down" subtil HLM-style). À `time_scale=0.1` (extreme) → clamp `pitch_scale ≈ 0.7937` (≈ -4 semitones).

**Example (Combat slow-mo MVP)** : kill ennemi → `Engine.time_scale = 0.3` pendant `SLOW_MO_DURATION_MS = 50` ms wall-clock (≈ 167 ms perçus) → blood ambiance (delay 50 ms wall-clock post-clac, soit ~170 ms perçus à 0.3×, tombe en plein dans la fenêtre slow-mo) joue avec `pitch_scale ≈ 0.8821` ≈ -2.1 semitones — l'oreille perçoit la queue blood drone-down quand le temps se dilate, signature HLM. À `time_scale = 1.0` retour, `pitch_scale = 1.0` restauré graduellement (pas de pop : transition mid-`play()` prouvée pas de glitch via R-3 ADR-0009 vérification empirique).

**Edge case** : si `time_scale = 0.0` (pause logique stricte — actuellement non utilisé MVP, mute Master prioritaire), formula clampe à `pitch_scale = 0.7937`. Acceptable (sons en cours seraient déjà mutés).

### Formula 6 — Sidechain compressor MUSIC ← COMBAT_KILL (r2 Phase A CD vision call)

Le ducking `MUSIC` est délégué à `AudioEffectCompressor` Godot natif. La courbe perceptuelle est l'output natif de l'effet ; cette formule documente les paramètres :

```
threshold = -24.0 dB
ratio = 4.0 (compression 4:1)
attack = 5.0 ms
release = 200.0 ms
sidechain_bus = "COMBAT_KILL"
```

**Computed effective ducking** (signal-dependent, non-deterministic en formule pure — Godot compressor gère la math interne) :

```
clac peak = 0 dB (COMBAT_KILL nominal)
input over threshold = 0 - (-24) = 24 dB
gain reduction = (1 - 1/ratio) × input_over_threshold = 0.75 × 24 = 18 dB max instant
applied to MUSIC bus = MUSIC nominal -3 dB → ducked peak ≈ -3 + (-18 × envelope) → bottom ≈ -6 dB
release window = 200 ms expo decay
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| `threshold` | float | `[-40, -12]` dB | Niveau d'activation. Tuning si ajustement nécessaire. |
| `ratio` | float | `[2.0, 8.0]` | Force de compression. 4.0 = "modéré", 8.0 = "ducking sec". |
| `attack_us` | int | `[1000, 20000]` µs | Temps de réaction à un transitoire en **microsecondes** (Godot 4.4+ — différence breaking vs 4.3 où prop = `attack` ms). < 5000 µs requis pour suivre clac (attack < 5 ms). Default Phase D.2 : `5000` (5 ms). |
| `release_ms` | float | `[50, 500]` ms | Temps de retour à 0 dB après cessation du sidechain. 200 ms = laisse silence rythmique audible. **API Godot 4.6** : prop `AudioEffectCompressor.release_ms` (millisecondes). |

**Output Range** : `MUSIC` effective ducked entre `-3 dB` (nominal) et `-6 dB` (peak ducked) pendant ~250 ms post-clac. Imperceptible breathing artifact tant que clacs espacés > 250 ms (cohérent SWING_DURATION 120 ms + cooldown 50 ms = ~170 ms minimum entre swings ; multi-kill 2e/3e clac dans même swing prolonge le ducking sans artifact car déjà actif).

**Tuning knob** `sidechain_music_attenuation_db` ajuste `threshold` indirectement (moins lié à threshold que ratio — augmenter ratio rend le ducking plus prononcé). Default `-3.0` dB d'attenuation effective.

**Mécanisme Godot** : configuré au `_ready()` AudioSystem via `AudioServer.add_bus_effect(MUSIC_idx, AudioEffectCompressor.new())`, paramètres set via `AudioEffectCompressor.threshold/ratio/attack_us/release_ms/sidechain`. Cohérent `audio.md` engine reference.

### Formula 7 — Pitch shift secret collect (r2.2 — NB-CRD-6 Option A)

```
SECRET_PITCH_SCALE = 2.0 ** (SECRET_PITCH_SEMITONES / 12.0)
```

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `SECRET_PITCH_SEMITONES` | `s` | float | `[4.0, 7.0]` | Décalage pitch du clac secret en demi-tons. Default `5.0` (`pitch_scale ≈ 1.335`, intervalle de quarte juste au-dessus du nominal). Hors plage Rule 13 `[0, 4]` pour éviter collision perceptive multi-kill. Tuning knob `secret_pitch_semitones`. |
| `SECRET_PITCH_SCALE` | `p` | float | `[1.260, 1.498]` | Output `pitch_scale` passé à `AudioStreamPlayer3D.pitch_scale`. Borne basse `1.260` = +4 semitones (cap Rule 13, exclusif), borne haute `1.498` = +7 semitones (limite avant timbre méconnaissable). |

**Output Range** : `pitch_scale ∈ [1.260, 1.498]` borné par `safe_range` semitones `[4, 7]`.

**Example** : `SECRET_PITCH_SEMITONES = 5.0` → `pitch_scale = 2.0 ** (5/12) = 1.3348...`. Clac joué à `pitch_scale = 1.335` sur bus `SFX`. Si comparé au 3e kill multi-kill Rule 13 (`pitch_scale = 1.260`), différence audible immédiate (+1 semitone perceptuel, +0.075 absolu).

**Invariance time_scale** : Formula 7 NE composite PAS avec Formula 5 (pitch shift slow-mo). Le bus `SFX` n'est PAS dans la pitch allowlist Rule 11 (`PITCH_SCALE_FOLLOWS_TIME_SCALE_PER_BUS[SFX] = false`) — le pitch secret reste invariant à `SECRET_PITCH_SCALE` même sous `time_scale != 1.0`. Comportement intentionnel : la découverte d'un secret n'est pas colorée par le drone HLM combat.

## Edge Cases

- **If pool 2D saturé (5 sons 2D simultanés — r2 sizing)** : le 6e `play_2d` interrompt le slot le plus ancien via `stop()` (round-robin). `push_warning("AudioPool 2D saturé — interruption son 2D actif")`. Au MVP scenario stress (1 swoosh + 1 dash + 1 walljump + 1 death + 1 UI = 5 simultanés), ce cas n'apparaît pas. Si combo system Tier 2 ou stress audio additionnel : augmenter pool à 6-8× (Tuning Knob safe range `[5, 8]`, R-1 ADR-0009).
- **If `enemy_killed` reçu pendant `MUTED_PAUSED`** : le handler ne joue PAS le clac (Master bus muted = inaudible de toute façon). Le flag `_kill_sound_played_this_swing` est tout de même mis à `true` pour préserver le contrat dedup multi-kill. Au resume, le swing en cours peut continuer normalement (état pré-pause restauré).
- **If `enemy.position` invalide (NaN, +Inf)** au moment du payload `enemy_killed` : Audio handler lit le `position` payload (capturé Combat). Si `position.is_finite() == false`, fallback `play_2d(clac_stream)` head-locked au lieu de `play_3d_at` (graceful degradation, log `push_warning`). Cas pathologique uniquement (Combat émet toujours position valide).
- **If `level_active` reçu pendant que music précédent crossfade pas terminé** : le crossfade en cours est interrompu, `Ambience #1` swap stream immédiatement à new stream avec `volume_db = -80`, nouveau crossfade démarre. Pas de queue de crossfades. (Cas pathologique au MVP — Level garantit unload→load séquentiel, pas de double `level_active` sans `level_unloading` entre les deux.)
- **If `LevelSystem.get_etage_audio_streams(etage_id)` retourne `{}`** (etage_id absent du mapping `ETAGE_AUDIO_MAPPING` knob Level) : Audio handler `push_warning("AudioSystem: no audio mapping for etage_id={etage_id}")` + return early. Music précédente continue (pas de stop), ambient reste tel quel. Lint authoring Level CI fail si un `etage_id` chargeable n'a pas d'entrée mapping (gate côté Level GDD r4).
- **If GSM `state_changed(PAUSED)` reçu pendant `MUTED_TRANSITION`** : transition mute prioritaire (TRANSITION > PAUSED). Master reste muted. Au scene loaded, état devient `MUTED_PAUSED` si GSM toujours en pause (rare — pause pendant scene transition).
- **If `play_music(null)` ou `play_2d(null, bus)`** : `push_error("Audio stream is null")`, return early. Pas de crash. Test unitaire couvre.
- **If bus name invalid (e.g. typo `"swing_actve"`)** : `AudioServer.get_bus_index(invalid_name)` retourne `-1`. Le `set_bus_volume_db(-1, x)` push une erreur Godot interne. Mitigation : usage exclusif des constantes `AudioBuses.SWING_ACTIVE` (StringName), pas de strings raw. Lint CI vérifie absence de `String` litéraux passés à `play_*()` `bus` parameter.
- **If wall-clock fade tick `delta` énorme (lag spike, 200 ms entre frames)** : la formule `t = elapsed / D` clampe à `1.0` au-delà — le fade saute à 100% direct (silence). Pas de surshoot, pas de NaN. Comportement correct.
- **If `_get_time_msec()` mocké retourne valeur décroissante** (test `t_now < t_0`) : `t < 0`, `clamp` à `0.0`, `volume_db = NOMINAL_DB` (fade pas démarré). Pas de comportement indéfini. Test unitaire couvre.
- **If pool 3D saturé pendant multi-kill** (12+ ennemis tués au même tick — édge case Tier 2+) : round-robin interrompt les blood ambiance les plus anciennes. Au MVP, `MAX_KILLS_PER_SWING = 3` (Combat) → max 3 blood ambiance simultanées sur pool 12 → pas de saturation possible (r2 sizing).
- **If `Ambience #1` et `Ambience #2` jouent simultanément crossfade en cours quand `state_changed(PAUSED)` arrive** : Master mute coupe les deux. Au resume, le crossfade reprend où il était (état préservé via `_crossfade_pause_msec` offset, comme fades wall-clock). Sound-designer Sprint Audio valide UX.
- **If `AudioListener3D` Camera3D actif est freed mid-frame** (e.g. Camera switch lourd, scene reload) : Godot 4.6 default behavior fallback à 0,0,0 listener (origin). Sons 3D positional vont jouer atténués au origin pendant 1 frame. Acceptable (cas transitoire). Coordination ADR-0002 garantit Camera3D toujours présent en runtime stable.
- **If `Secret.secret_collected` reçu pendant slow-mo (`time_scale != 1.0`)** : Rule 17 + Formula 7 — bus `SFX` n'est PAS dans la pitch allowlist Rule 11, donc `pitch_scale = SECRET_PITCH_SCALE` (Formula 7) reste invariant. Le clac secret n'est PAS pitch-shifted vers le drone HLM même si le slow-mo combat est actif. Cas pratique : kill multi → slow-mo → secret collecté pendant slow-mo → clac secret aigu identifiable malgré le drone combat. Comportement intentionnel — le secret transcende le système combat.
- **If `Secret.secret_collected` reçu pendant `MUTED_PAUSED`** : le handler ne joue PAS le clac (Master bus muted). Pas de tracking d'état persistant nécessaire (contrairement à `_kill_sound_played_this_swing` Rule 13) — le secret est un event one-shot, pas multi-step. Au resume PLAYING, prochain `secret_collected` reçoit le traitement normal.
- **If `secret_node.global_position` est `(NaN, +Inf)`** au moment du payload `secret_collected` : fallback `play_2d(clac_stream, AudioBuses.SFX, pitch_scale=SECRET_PITCH_SCALE)` head-locked. `push_warning("AudioSystem: secret_node.global_position invalid, fallback 2D")`. Cas pathologique (Secret System émet position valide en pratique).
- **If kill simultané + secret collect dans le même tick** (ennemi tué pendant qu'on collecte un secret) : les deux Audio handlers tirent indépendamment. Combat clac sur `COMBAT_KILL` à `pitch_scale ∈ [1.0, 1.260]`, secret clac sur `SFX` à `pitch_scale ≈ 1.335`. Les deux clacs jouent en parallèle, bus distincts, ducking sidechain MUSIC armed par COMBAT_KILL seulement. Lisibilité garantie par séparation de bus.

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| **Game State Manager** | This depends on GSM | Hard. Consume `state_changed(new_state)` pour mute/unmute Master bus sur PAUSED/PLAYING/SCENE_TRANSITION. CONNECT_DEFERRED. Sans GSM : pas de pause audio cohérente. |
| **Camera System** | This depends on Camera | Soft. Lit `Camera3D` actif comme `AudioListener3D` (default Godot 4.6, pas d'API call). ADR-0002 garantit chain Camera3D scene tree single-listener. Sans Camera : sons 3D atténués au origin (degraded). |
| **Level System** | This depends on Level | Hard pour music/ambient. Consume `level_active(etage_id, player_start)` (Level r3+) en CONNECT_DEFERRED + lookup synchrone `LevelSystem.get_etage_audio_streams(etage_id) -> Dictionary{music, ambient}` (Level r4 amendment Option C). Consume aussi `level_unloading(etage_id)` pour fade-out music + `room_entered(room_index, total_rooms)` pour ambient layer swap intra-étage (optionnel MVP). Sans Level : music statique du menu uniquement. |
| **Player Combat** | This depends on Combat (signals) | Hard pour audio combat. Consume `swing_started`, `swing_ended`, `enemy_killed(enemy, position)`, `multi_kill(count)` en CONNECT_DEFERRED. Contrats AC-CMB-51 (fade-out swoosh wall-clock 25-50 ms), AC-CMB-audio-01 (multi-kill clac dedup), AC-CMB-audio-02 (ducking event ordering). Sans Combat : pas de SFX combat. |
| **Player Movement** | This depends on Movement (signals) | Hard pour audio movement. Consume `dash_started`, `dash_rejected` (futur), `wall_run_entered`, `wall_run_exited`, `wall_jumped`, `died`, `respawned` en CONNECT_DEFERRED. Sans Movement : pas de SFX déplacement. |
| **Secret System** | This depends on Secret (signal, r2.2) | Hard pour audio secret. Consume `secret_collected(secret_node, tier)` en CONNECT_DEFERRED (Rule 17 r2.2). Sans Secret : pas de clac différencié, Pillar 4 viscéralité MVP minimum non livrée. |
| **Input System** | This depends on Input (indirect) | Soft via Menu System. UI clicks routés indirectement (Input → Menu Widget → Audio.play_2d). Pas de connexion directe Input → Audio. |
| **Accessibility System** | Accessibility depends on this | Soft, future Tier 3. Accessibility expose UI sliders volume per bus, persiste via Audio System API `set_bus_volume_db_user`. |
| **VFX & Feedback** | Peers (no dependency) | Aucun. VFX et Audio sont consumers parallèles indépendants des mêmes signals Combat. Aucun appel direct entre les deux. |
| **HUD System** | Peers (no dependency MVP) | Aucun MVP. Tier 2+ : HUD pourrait consommer SFX pour pickup/credit chime, route via Audio.play_2d. |
| **Save/Load System** | Save/Load depends on this | Soft, future Tier 2. Audio settings (volume per bus) sérialisés dans `audio_settings.tres` géré par Save/Load. |

**Dépendances bidirectionnelles à corriger dans GDDs amont** :
- `game-state-manager.md` : ajouter Audio System dans table `Interactions with Other Systems` aval (mute/unmute Master).
- `camera-system.md` : ajouter Audio System dans Cross-References (Camera3D actif = AudioListener3D, ADR-0002 chain).
- `level-system.md` : ✅ **RÉSOLU r2** par Level GDD r4 amendement (2026-04-27 Option C). Audio consume `level_active` existant + lookup `LevelSystem.get_etage_audio_streams(etage_id)` ; pas de signal `etage_loaded` créé. Bidirectionalité Level r4 §Interactions row Audio + §Tuning Knobs `ETAGE_AUDIO_MAPPING` + §Dependencies Downstream Audio = présentes.
- `player-combat-system.md` : déjà documenté §Audio Requirements (APPROVED r6). Ajouter ref vers ce GDD comme "Audio System (aval)" pour bidirectionalité explicite (mineur, déjà couvert par Cross-References Combat).
- `player-movement-system.md` : déjà documenté §Visual/Audio Requirements. Ajouter ref vers ce GDD (mineur).
- `secret-system.md` (r2.2) : ajouter Audio System dans Dependencies + Interactions table aval (consume `secret_collected`). Mention Rule 17 + Formula 7 différenciation pitch +5 semitones bus `SFX`. Bidirectionalité confirme cascade NB-CRD-6 Option A.

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|
| `master_volume_db` | 0.0 | `[-80, 6]` dB | Saturation clipping > 0 dB | Inaudible < -60 dB |
| `music_volume_db` | -3.0 | `[-80, 6]` dB | Music masque SFX combat | Music inaudible |
| `sfx_volume_db` | 0.0 | `[-80, 6]` dB | SFX combat domine, fatigue auditive | SFX inaudible, kill perd impact |
| `ambience_volume_db` | -6.0 | `[-80, 0]` dB | Ambient masque dialogue futur Tier 3 | Ambient inaudible, room dead |
| `ui_volume_db` | -6.0 | `[-80, 6]` dB | UI clicks dominent flow | UI feedback perdu |
| `swoosh_nominal_db` | -6.0 | `[-12, 0]` dB | Swoosh masque clac kill | Swoosh inaudible, perte proprioception |
| `swoosh_fade_duration_ms` | 30.0 | `[20, 50]` ms | Fade trop lent → overlap clac perçu | Fade trop rapide → cut audible inverse |
| `ducking_release_ms` | 30.0 | `[20, 50]` ms | Release lente → silence post-clac trop long | Release rapide → overlap masquage |
| `ducking_db_attenuation` | -6.0 | `[-12, -3]` dB | Ducking trop fort → `SWING_ACTIVE` inaudible pendant kill | Ducking insuffisant → masquage clac |
| `ambient_crossfade_ms` | 1000.0 | `[500, 2000]` ms | Crossfade lent → ambient mou transitions | Crossfade rapide → cut audible |
| `blood_ambiance_delay_ms` | 50.0 | `[20, 100]` ms | Blood trop tard → décorrélé du clac | Blood trop tôt → masque clac |
| `death_audio_duration_ms` (r2) | 70.0 | `[60, 80]` ms | > 80 ms = overlap respawn frame trop long, queue audible alors que le respawn est déjà en cours (immersion brisée) | < 60 ms = perceptuellement insuffisant (seuil reconnaissance timbre 60-100 ms, fix Phase A CD) |
| `pool_2d_size` (r2) | 5 | `[5, 8]` count | Plus de RAM (~15 KB/Player) | < 5 = saturation MVP scenario (1 swoosh+1 dash+1 walljump+1 death+1 UI=5), interruptions audibles |
| `pool_3d_size` (r2) | 12 | `[12, 16]` count | Plus de RAM | < 12 = multi-kill 3 ennemis + footsteps Tier 2 + environmental SFX peut saturer |
| `multi_kill_pitch_shift_semitones` (r2) | +2.0 per rank | `[+1.0, +4.0]` per rank | Climax sonique trop excessive, kills 3+ deviennent comiques | Climax sonique imperceptible, multi-kill perd l'impact Fantasy |
| `pitch_shift_max_semitones_slow_mo` (r2) | -4.0 | `[-6.0, -2.0]` | Drone-down trop grave, ambient inintelligible | Drone-down imperceptible, identité HLM perdue |
| `sidechain_music_attenuation_db` (r2) | -3.0 dB | `[-6.0, -1.0]` dB | Music ducked trop fort, breathing artifact audible (pumping) | Music pas assez ducked, masque silence rythmique Couche 1 |
| `sidechain_release_ms` (r2) | 200.0 | `[100, 400]` ms | Release lente → music reste ducked longtemps après clac (sensation lourde) | Release rapide → music pop-up audible immédiatement après clac |
| `secret_pitch_semitones` (r2.2) | +5.0 | `[+4.0, +7.0]` | Trop aigu → timbre clac méconnaissable, secret perd la signature partagée avec kill | Trop bas → collision Rule 13 multi-kill `[+0, +4]`, ambiguïté perceptive kill 3+ vs secret |
| `music_default_fade_seconds` | 1.0 | `[0.3, 3.0]` s | Music transitions molles | Music cuts brutaux |

**Knobs non-tuneable (invariants)** :
- `MAX_AUDIO_BUSES = 7` (figé ADR-0009 D-1, modification = ADR amendment).
- `AUDIO_LISTENER_DEDIE = false` (figé ADR-0009 D-6).
- `PITCH_SCALE_FOLLOWS_TIME_SCALE_PER_BUS` (r2 amendement ADR-0009 D-3 — allowlist) : `COMBAT_KILL = true`, `AMBIENCE = true`, `MUSIC = false`, `SWING_ACTIVE = false`, `UI = false`, `SFX = false`, `MASTER = false`. Figé Rule 11. Modification = ADR amendment.
- `MUSIC_SIDECHAIN_FROM = "COMBAT_KILL"` (r2 figé Rule 16, figé ADR-0009 D-1 amendement). Bus de feed sidechain — modification = ADR amendment.
- `CONNECT_MODE_DEFAULT = CONNECT_DEFERRED` (figé ADR-0009 D-4, exemption SYNC interdite MVP).

## Visual/Audio Requirements

> Note : ce système EST l'audio, donc cette section spécifie les **événements audio par signal** (le contrat asset → event mapping). Les détails waveform/mixing sont délégués au sound-designer Sprint Audio via `/team-audio`.

| Event source | Stream asset | Bus | Spatial | Duration | Connection | Notes |
|---|---|---|---|---|---|---|
| Combat `swing_started` | `swoosh.wav` | `SWING_ACTIVE` | 2D head-locked | ≤ 120 ms wall-clock (≤ SWING_DURATION_MS) | DEFERRED | Hard, sec, pas de réverb. 800Hz-4kHz. Volume nominal `-6 dB` (cf. ADR-0009 D-3 Note). Owned by Audio System pool 2D. |
| Combat `swing_ended` (sans kill) | — | — | — | — | DEFERRED | Pas de son miss (r1 audio-director — silence = signal). Le swoosh termine naturellement à 120 ms. |
| Combat `swing_ended` (avec kill via `enemy_killed`) | — | `SWING_ACTIVE` | — | Fade-out 30 ms wall-clock | DEFERRED | Pas de stream — fade du swoosh via Formula 1. AC-CMB-51. |
| Combat `enemy_killed(enemy, position)` (1er kill du swing, `_kill_count_this_swing = 1`) | `clac.wav` | `COMBAT_KILL` | 3D positional, owned pool/scene root | < 80 ms (attack < 5 ms, decay rapide) | DEFERRED | Transitoire 800Hz-4kHz, attack < 5 ms. Position = payload `position` Vector3. `pitch_scale = 1.0` nominal. Trigger sidechain `MUSIC` (Rule 16, Formula 6). |
| Combat `enemy_killed` (2e kill même swing, `_kill_count_this_swing = 2`) — r2 | `clac.wav` (réutilisé) | `COMBAT_KILL` | 3D positional | < 80 ms | DEFERRED | **Pitch-shift +2 semitones** `pitch_scale ≈ 1.122` (r2 Phase A CD). Climax sonique. Sidechain `MUSIC` re-trigger (release reset). Blood ambiance jouée indépendamment. |
| Combat `enemy_killed` (3e+ kill même swing) — r2 | `clac.wav` (réutilisé) | `COMBAT_KILL` | 3D positional | < 80 ms | DEFERRED | **Pitch-shift +4 semitones** `pitch_scale ≈ 1.260` (apex r2). 4e+ : capé +4 semitones. Blood ambiance toujours jouée. |
| Combat `enemy_killed` (ducking) | — | `SWING_ACTIVE` | — | Release 30 ms wall-clock (Formula 2) | DEFERRED | -6 dB instantané + release expo. AC-CMB-audio-02. |
| Combat `enemy_killed` (blood) | `blood.wav` | `COMBAT_KILL` | 3D positional | ≤ 500 ms total, delay 50 ms wall-clock post-impact | DEFERRED | Délai 50 ms = ~170 ms perçus à `time_scale=0.3`, tombe dans silence post-clac. N instances independent multi-kill. Allowlist pitch_scale_follows_time_scale=true (Rule 11) — drone-down -2.1 semitones à time_scale=0.3 (Couche 4 HLM). Slot blood ≠ slot clac (clac exclu de pitch shift via `_active_clac_players` tracker). |
| Combat `multi_kill(count)` | — | — | — | — | DEFERRED | Noop côté Audio handler — Audio System ne consume PAS `multi_kill` (signal Combat). La logique multi-kill climax sonique est gérée par les rangs `enemy_killed` 1/2/3+ via `_kill_count_this_swing` counter (Rule 13 r2 — pitch-shift +2/+4 semitones). |
| Movement `dash_started` | `dash.wav` | `SFX` | 2D head-locked | ≤ 100 ms (DASH_DURATION) | DEFERRED | Whoosh court, energy burst. |
| Movement `dash_rejected` (futur) | `dash_reject.wav` | `UI` | 2D head-locked | 30 ms | DEFERRED | -12 dB, sec, court. Affordance accessibilité (Movement Visual/Audio §accessibility). |
| Movement `wall_run_entered` | `wallrun_loop.wav` | `SFX` | 2D head-locked | Loop pendant wall-run | DEFERRED | Subtle wind, low frequency. Loop infinie tant que wall-running. |
| Movement `wall_run_exited` | — | `SFX` | — | Fade out 100 ms wall-clock | DEFERRED | Fade `_physics_process`. |
| Movement `wall_jumped` | `walljump.wav` | `SFX` | 2D head-locked | ≤ 200 ms | DEFERRED | Burst énergie + push-off. |
| Level `room_tone_chrome_zen.wav` (boot étage 1, OQ#7 résolu Phase B) | `room_tone_chrome_zen.wav` | `AMBIENCE` | 2D | Loop 30-60 s seamless | DEFERRED via `level_active` | Sub-bass synthwave sustain, fréquence dominante 40-80 Hz, `volume_db = -12 dB` nominal. Sous slow-mo : drone-down via Formula 5 (allowlist=true) vers ~36 Hz dominante. Tier 3 Accessibility : toggle `Reduce Ambient Intensity` peut désactiver. |
| Movement `died` (r2) | `death.wav` | `SFX` | 2D head-locked | **60-80 ms wall-clock** (default 70 ms — overlap respawn frame autorisé per Rule 14 r2 Phase A CD) | DEFERRED | Pillar 3 absolu. Sec, réverb interdite. Seuil reconnaissance timbre 60-100 ms — sub-60ms perceptuellement insuffisant. RESPAWN_DELAY 50 ms reste figé Movement (Pillar 3) ; surplus 10-30 ms overlap première frame respawn (queue audio Godot survit scene reload). |
| Movement `respawned` | — | — | — | — | DEFERRED | Silence intentionnel post-respawn. Permet clarté rythmique. |
| GSM `state_changed(PAUSED)` | — | `MASTER` mute | — | Instantané (1 frame) | DEFERRED | `AudioServer.set_bus_mute(0, true)`. |
| GSM `state_changed(PLAYING)` (resume) | — | `MASTER` unmute | — | Instantané | DEFERRED | `AudioServer.set_bus_mute(0, false)`. État audio préservé pré-pause. |
| GSM `state_changed(SCENE_TRANSITION)` (futur) | — | `MUSIC` fade out 0.5 s, SFX/ambient mute | — | 0.5 s wall-clock | DEFERRED | Pool reset au scene loaded. |
| Level `level_active(etage_id, player_start)` + lookup `get_etage_audio_streams(etage_id)` (r2 Option C) | `music_etage_NN.ogg`, `ambient_etage_NN.ogg` (résolus via `ETAGE_AUDIO_MAPPING` knob Level) | `MUSIC`, `AMBIENCE` | 2D | Crossfade 1 s | DEFERRED | Formula 4. Music play() + fade-in. Ambient crossfade #1↔#2. Si lookup retourne `{}` : push_warning + fallback silence. |
| Level `level_unloading(etage_id)` | — | `MUSIC` fade out, `AMBIENCE` mute | — | 0.5 s | DEFERRED | Avant scene transition. |
| UI Menu navigate (futur) | `ui_click.wav` | `UI` | 2D | ≤ 50 ms | DEFERRED via Menu | Léger, neutre. |
| UI Shop transaction (futur) | `purchase.wav` | `UI` | 2D | ≤ 200 ms | DEFERRED via Shop | Confirmation chime. |
| Pickup credit (futur) | `credit_pickup.wav` | `SFX` | 3D positional | ≤ 100 ms | DEFERRED via Credit Economy | Tier 2 — chime distinctif. |
| Secret atteint (futur) | `secret_reveal.wav` | `SFX` | 2D head-locked | ≤ 500 ms | DEFERRED via Secret System | Tier 2 — chime mémorable, distinct du credit. |

**Mix hierarchy globale** (cohérent Combat r6 §Mix hierarchy règles 1-4, r2 UPPER_SNAKE_CASE) :

1. **Bus `COMBAT_KILL`** (clac + blood) : 0 dB, jamais ducked directement. Frequence transitoire dominante 800Hz-4kHz. Source du sidechain feed vers `MUSIC` (Rule 16).
2. **Bus `SWING_ACTIVE`** (swoosh) : nominal `-6 dB`, ducked `-12 dB` sur `enemy_killed` event, release 30 ms expo (Formula 2).
3. **Bus `AMBIENCE`** : ducked `-3 dB` pendant fenêtre kill `[swoosh_start, kill_impact + 500 ms]` pour clarté rythmique. Allowlist pitch_scale_follows_time_scale=true (Rule 11).
4. **Bus `MUSIC`** : -3 dB nominal default. **Ducking automatique combat via sidechain compressor** `AudioEffectCompressor` feed `COMBAT_KILL` (Rule 16, Formula 6) — peak ducked `-6 dB` à t≈5 ms post-clac, release 200 ms expo retour `-3 dB` nominal, atténuation perçue moyenne `-3 dB` sur fenêtre 250 ms. La musique ne s'arrête JAMAIS (continuité Couche 3 préservée). Fade out -∞ sur `state_changed(SCENE_TRANSITION)`.
5. **Bus `UI`** : -6 dB nominal. **Coupé par mute MASTER MVP** (mute total Master coupe tout y compris `UI` — OQ#6 résolu Phase B, simplicité d'implémentation, joueur navigue silencieusement dans pause menu ~1-2 s acceptable UX). Tier 2 reconsidéré si playtest pause menu révèle UX dégradée (mute sélectif `MUSIC + SFX + AMBIENCE + SWING_ACTIVE + COMBAT_KILL`, exclure `UI`).

**Asset Spec Flag** :

> 📌 **Asset Spec** — Visual/Audio requirements définies. Après art bible approuvée, lancer `/asset-spec system:audio-system` pour produire les specs per-asset (waveform target, frequency profile, spatialisation params, format Godot — `.wav` 44.1 kHz mono SFX, `.ogg` 44.1 kHz stereo music).

## UI Requirements

L'Audio System a une UI minimale au MVP (sliders volume dans menu Pause / Settings, future Menu System). Au Tier 3 (Accessibility), l'UI s'enrichit (subtitles toggle, audio cues for visual events).

| Information | Display Location | Update Frequency | Condition |
|-------------|-----------------|-----------------|-----------|
| Slider `Master Volume` (-80 → +6 dB) | Settings menu | OnChange (debounce 100 ms) | Toujours disponible. Persiste `audio_settings.tres` (Tier 2 Save/Load). |
| Slider `Music Volume` | Settings menu | OnChange (debounce 100 ms) | Toujours disponible. |
| Slider `SFX Volume` | Settings menu | OnChange (debounce 100 ms) | Toujours disponible. |
| Slider `UI Volume` | Settings menu | OnChange (debounce 100 ms) | Toujours disponible. |
| Toggle `Subtitles` | Settings menu (Accessibility tab) | OnChange | Tier 3 only. Active overlay textuel pour sons critiques (kill, hazard) — coordination Accessibility System. |
| Toggle `Reduce Audio Intensity` | Settings menu (Accessibility tab) | OnChange | Tier 3. Atténue blood ambiance + slow-mo audio mix pour photosensibilité auditive. |

> 📌 **UX Flag — Audio System** : Au MVP, settings menu = scope du Menu System GDD futur (#18 systems-index, MVP Not Started). Audio System expose API `set_bus_volume_db_user(bus, db)` que le Menu UI consomme — pas de UX spec dédiée Audio System. En Phase 4 (Pre-Production), `/ux-design design/ux/settings-menu.md` couvrira les sliders volume avant création epic UI.

## Cross-References

| This Document References | Target GDD | Specific Element Referenced | Nature |
|--------------------------|-----------|----------------------------|--------|
| GSM `state_changed(new_state)` signal pour pause/resume mute | `design/gdd/game-state-manager.md` | API publique signal `state_changed(new_state)` figé ADR-0007 D-10 | State trigger |
| `RESPAWN_DELAY` constant (death.wav 60-80 ms wall-clock — Rule 14 r2 ; surplus 10-30 ms overlap première frame respawn intentionnel — queue audio Godot survit scene reload ; `RESPAWN_DELAY = 0.05 s` figé Pillar 3 Movement, n'allonge PAS le respawn) | `design/gdd/player-movement-system.md` | Tuning Knob `RESPAWN_DELAY = 0.05 s` (registry-aligned) | Data dependency |
| `Camera3D` actif = `AudioListener3D` (default Godot 4.6) | `design/gdd/camera-system.md` | ADR-0002 chain Camera3D scene tree, single-listener invariant | Rule dependency |
| Combat signals `swing_started`, `swing_ended`, `enemy_killed(enemy, position)`, `multi_kill(count)` | `design/gdd/player-combat-system.md` | Published API signals (APPROVED r6) | State trigger |
| Combat AC-CMB-51 fade-out swoosh wall-clock 25-50 ms | `design/gdd/player-combat-system.md` | AC-CMB-51 contract verifiable côté Audio handler via `_get_time_msec` mock | Rule dependency |
| Combat AC-CMB-audio-01 multi-kill clac dedup `_kill_sound_played_this_swing` | `design/gdd/player-combat-system.md` | AC-CMB-audio-01 contract owned by Audio System (flag flag côté Audio) | Ownership handoff |
| Combat AC-CMB-audio-02 ducking event ordering `SWING_ACTIVE` | `design/gdd/player-combat-system.md` | AC-CMB-audio-02 contract verifiable via MockAudioBus | Rule dependency |
| Combat Mix hierarchy règles ducking 1-4 (bus naming canonisé r2) | `design/gdd/player-combat-system.md` §Mix hierarchy | Bus names `SWING_ACTIVE`, `COMBAT_KILL`, `AMBIENCE`, `MUSIC` (UPPER_SNAKE_CASE r2 CD reco #5) | Ownership handoff (Audio canonise les noms ici) |
| Combat `SLOW_MO_DURATION_MS = 50`, `SLOW_MO_SCALE = 0.3` (registry sync 2026-04-27 — was 100 / 0.15 stale draft pré-Combat r1, retunée Martin D3 ; safe ranges registry r1 [30,150] ms / [0.10,0.50] alignés Combat Tuning Knobs Section G) | `design/registry/entities.yaml` | Constants registry | Data dependency |
| Movement signals `dash_started`, `wall_run_entered`, `wall_run_exited`, `wall_jumped`, `died`, `respawned` | `design/gdd/player-movement-system.md` | Published API signals | State trigger |
| Movement `dash_reject.wav` (-12 dB, 30 ms) | `design/gdd/player-movement-system.md` | §Visual/Audio Requirements + accessibility option | Data dependency |
| Level `level_active(etage_id, player_start)` (signal existant Level r3+) + lookup `LevelSystem.get_etage_audio_streams(etage_id) -> Dictionary{music, ambient}` (Level r4 amendment Option C, 2026-04-27) | `design/gdd/level-system.md` | §Interactions Audio row + §Dependencies pseudocode + Tuning Knob `ETAGE_AUDIO_MAPPING` | State trigger + lookup API |
| Level `level_unloading(etage_id)` (signal existant Level r3+) | `design/gdd/level-system.md` | §States and Transitions T-3 | State trigger |
| Level `room_entered(room_index, total_rooms)` (signal existant Level r3+, ambient layer swap optional MVP) | `design/gdd/level-system.md` | §Interactions Audio row | State trigger (optional) |
| ADR-0009 6 décisions D-1..D-6 + 8 VC | `docs/architecture/adr-0009-audio-system-architecture.md` | Status Accepted 2026-04-27 | Rule dependency |
| ADR-0001 Physics Rate 60 Hz | `docs/architecture/adr-0001-physics-rate-60hz.md` | Wall-clock fades dans `_physics_process` | Rule dependency |
| ADR-0005 Movement Signals CONNECT_DEFERRED | `docs/architecture/adr-0005-movement-signals-architecture.md` | Mode connection D-4 default DEFERRED | Rule dependency |
| ADR-0006 Combat Tick Model `_get_time_msec` Callable injection | `docs/architecture/adr-0006-combat-tick-model.md` | Pattern injection partagé Combat ↔ Audio (mocks `MockAudioHandler` / `MockAudioBus`) | Rule dependency |
| Mémoire projet `feedback_godot_class_name_autoload_collision.md` | `~/.claude/projects/.../memory/` | `AudioBuses` classe statique pure (PAS autoload), `AudioSystem` autoload sans `class_name` | Rule dependency |

## Acceptance Criteria

### Boot & Pool

- **AC-AUD-01** (r2.3 — attack_us/release_ms verification) `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** project boot avec `default_bus_layout.tres` configuré dans `project.godot`. **WHEN** AudioSystem autoload `_ready()` complète. **THEN** : (a) `AudioServer.bus_count == 7` ; (b) noms bus dans l'ordre `MASTER / MUSIC / SFX / SWING_ACTIVE / COMBAT_KILL / AMBIENCE / UI` (vérifier `AudioServer.get_bus_name(0..6)` — UPPER_SNAKE_CASE r2 CD reco #5 canonique) ; (c) parents : `MUSIC`/`SFX`/`AMBIENCE`/`UI` parent = `MASTER`, `SWING_ACTIVE`/`COMBAT_KILL` parent = `SFX` (vérifier via `AudioServer.get_bus_send(idx) == parent_name`) ; (d) bus `MUSIC` porte exactement 1 `AudioEffectCompressor` (`AudioServer.get_bus_effect_count(MUSIC_idx) == 1`) configuré avec : `compressor.sidechain == "COMBAT_KILL"`, `compressor.attack_us == 5000` (5 ms en microsecondes — Godot 4.4+ API), `compressor.release_ms == 200.0`, `compressor.threshold == -24.0`, `compressor.ratio == 4.0` (Rule 16 + Formula 6). Si `attack_us` n'est pas une property accessible → FAIL avec message "Godot 4.6 AudioEffectCompressor API mismatch — engine-reference Phase D.5 required, see `docs/engine-reference/godot/audio.md` AudioEffectCompressor section". Test : `tests/integration/audio/audio_boot_test.gd`.

- **AC-AUD-02** (r2 — pool sizing CD reco) `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** boot complet. **WHEN** AudioSystem `_ready()` retourne. **THEN** : (a) pool 2D = **5** `AudioStreamPlayer` enfants AudioSystem (vérifier `_2d_pool.size() == 5`) ; (b) pool 3D = **12** `AudioStreamPlayer3D` enfants AudioSystem (`_3d_pool.size() == 12`) ; (c) Music player single instance ; (d) Ambience players = 2 ; (e) `AudioSystem.get_child_count() == 20` (assertion structurale directe — count exact des nodes audio enfants AudioSystem autoload, déterministe contrairement à `Performance.OBJECT_COUNT` delta multi-autoload boot). VC-2 ADR-0009.

- **AC-AUD-03** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** AudioSystem prêt. **WHEN** `play_2d(stream, AudioBuses.SFX)` appelé 1000 fois en boucle. **THEN** : (a) aucun nouveau `AudioStreamPlayer` créé (`AudioSystem.get_child_count() == 20` constant avant/après) ; (b) `Performance.MEMORY_STATIC` delta ≤ +100 KB après 1000 cycles (tolérance GDScript GC) ; (c) round-robin index avance correctement (`_2d_index` cycle `0 → 1 → 2 → 3 → 4 → 0` — pool 5 r2 sizing). VC-7 ADR-0009.

### Combat audio contracts (cross-system)

- **AC-AUD-04** (r2.3 — F-01 boundary D ≤ 0 guard coverage) `[Integration — BLOCKING] [Owner: qa-tester + lead-programmer]` (équivalent AC-CMB-51 côté Audio) — **GIVEN** AudioSystem actif, swing en cours sur bus `SWING_ACTIVE` `volume_db = -6.0`, `Engine.time_scale = 0.3` (slow-mo Combat), `_get_time_msec: Callable` mocké. **WHEN** `swing_ended` ou `enemy_killed` reçu DEFERRED frame N+1, fade-out swoosh démarre avec `_get_time_msec()` retournant successivement `1000, 1015, 1025, 1030, 1050`. **THEN** : (a) à `t = 1015` (15 ms wall-clock, 50% fade), `volume_db ≈ -43 dB ± 2 dB` (Formula 1) ; (b) à `t = 1030` (30 ms, 100%), `volume_db ≤ -60 dB` (silence pratique) ; (c) résolution complète dans `[25, 50] ms wall-clock` ; (d) si test observe résolution 75-100 ms : FAIL avec message "swoosh fade-out scaled by time_scale — Tween used in `_process` instead of wall-clock `_physics_process` — violation Rule 4 ADR-0009 D-3 + Combat AC-CMB-51" ; (e) **boundary case `D = 0.0`** : si tuning knob `swoosh_fade_duration_ms = 0.0` (corruption save / fixture mal configuré), `volume_db == -80.0` immédiat (Formula 1 short-circuit `D ≤ 0 → SILENCE_DB`) + `push_warning` capturé 1× au boot (vérifier via mock logger ou `OS.is_debug_build()` debug-guarded `_warning_handler: Callable` injection) ; (f) **boundary case `D = -1.0`** : même comportement que (e) — guard symétrique négatif. Evidence : `tests/integration/audio/swoosh_fade_wall_clock_test.gd`. VC-3 ADR-0009.

- **AC-AUD-05** (r2 — multi_kill pitch-shift) `[Integration — BLOCKING] [Owner: qa-tester]` (équivalent AC-CMB-audio-01 côté Audio, contract Combat **mis à jour** noop → pitch-shift) — **GIVEN** swing actif, counter `_kill_count_this_swing == 0`. **WHEN** 4 `enemy_killed` émis dans le même swing (multi-kill MockEnemy1..4 — testant cap pathologique 4e+ kill au-delà de Combat MAX_KILLS_PER_SWING=3). **THEN** : (a) au 1er `enemy_killed` reçu, counter passe `0 → 1`, clac joué via `play_3d_at(clac_stream, pos1, AudioBuses.COMBAT_KILL)` avec `pitch_scale ≈ 1.0 ± 0.001` ; (b) au 2e `enemy_killed` même swing, counter `1 → 2`, clac rejoué `pitch_scale ≈ 1.122 ± 0.005` (+2 semitones) ; (c) au 3e `enemy_killed`, counter `2 → 3`, clac rejoué `pitch_scale ≈ 1.260 ± 0.01` (+4 semitones) ; (d) **au 4e `enemy_killed`** (pathologique), counter `3 → 4`, clac rejoué `pitch_scale ≈ 1.260 ± 0.01` (cap +4 semitones — pas +6 carry-over, Rule 13 r2) ; (e) blood ambiance jouée 4× (1 par `enemy_killed`) avec délai 50 ms wall-clock chacune, `pitch_scale = 1.0` (blood pas pitch-shifted en time_scale=1.0 ; allowlist activée seulement sous slow-mo) ; (f) à `swing_ended` (tick ACTIVE_TICKS+1), counter reset à `0`. Test : `tests/integration/audio/multi_kill_pitch_shift_test.gd`. VC-4 ADR-0009 amendée r2.

- **AC-AUD-06** (r2.3 — F-02 boundary R ≤ 0 guard coverage) `[Integration — BLOCKING] [Owner: qa-tester + lead-programmer]` (équivalent AC-CMB-audio-02 côté Audio) — **GIVEN** swoosh joue sur `SWING_ACTIVE` `volume_db = -6.0`. **WHEN** `enemy_killed` reçu DEFERRED frame N+1. **THEN** : (a) `AudioServer.get_bus_volume_db(swing_active_idx)` passe à `-12.0 dB` instantanément (1 frame) ; (b) release 30 ms wall-clock démarre dans `_physics_process` ; (c) à `t = 1015` (50% release perceptuel), bus volume ≈ `-8.5 dB ± 1 dB` (Formula 2) ; (d) à `t = 1030` (100%), bus volume `= -6.0 dB` nominal ; (e) **boundary case `R = 0.0`** : si tuning knob `ducking_release_ms = 0.0`, `get_bus_volume_db(swing_active_idx) == NOMINAL_DB` (restore instantané — Formula 2 short-circuit `R ≤ 0 → NOMINAL_DB`) + `push_warning` capturé 1× au boot ; (f) **boundary case `R = -1.0`** : même comportement que (e). Evidence : MockAudioBus log timestamp wall-clock + volume_db par frame. Test : `tests/integration/audio/ducking_release_wall_clock_test.gd`. VC-5 ADR-0009.

### Movement audio

- **AC-AUD-07** (r2 — death duration 60-80 ms + overlap) `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** AudioSystem prêt + asset `res://assets/audio/sfx/death.wav` existe. **WHEN** Movement `died` émis. **THEN** : (a) **Precheck** : `ResourceLoader.exists("res://assets/audio/sfx/death.wav")` retourne `true` — sinon FAIL avec message "death.wav asset manquant — bloquer Sprint Audio asset pipeline gate" ; (b) `play_2d(death_stream, AudioBuses.SFX)` appelé via DEFERRED frame N+1 ; (c) `death_stream.get_length() ∈ [0.060, 0.080] s` (60-80 ms — default 70 ms) — assertion automatique CI ; (d) si `death_stream.get_length() < 0.060 s` : FAIL avec message "death.wav < 60 ms — perceptuellement insuffisant pour reconnaissance timbre (seuil 60-100 ms) — fix Phase A CD r2" ; (e) si `death_stream.get_length() > 0.080 s` : FAIL avec message "death.wav > 80 ms — overlap respawn frame trop long, immersion brisée". (f) **Overlap respawn frame** : assertion **non automatisable headless** — le sample peut overlap sur la première frame du respawn (RESPAWN_DELAY = 0.05 s figé Movement, surplus 10-30 ms intentionnel — queue audio Godot survit au scene reload). Vérification empirique Sprint Audio par sound-designer (playtest manuel : son perceptible immédiatement après respawn ~1 frame, pas de coupure brutale). Test automatique couvre (a)-(e) ; (f) en evidence playtest dossier `production/qa/evidence/audio-death-overlap-{date}.md`. Test : `tests/integration/audio/death_audio_duration_test.gd`. Pillar 3.

### Pause/resume

- **AC-AUD-08** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** musique + 3 SFX en cours. **WHEN** GSM `state_changed(PAUSED)` émis. **THEN** : (a) `AudioServer.is_bus_mute(0)` (Master) `== true` dans la frame suivante (DEFERRED N+1) ; (b) `AudioStreamPlayer.playing` reste `true` pour music (queue audio préservée) ; (c) état `_swoosh_fade_active` ou `_ducking_release_active` est marqué `paused` avec `_fade_pause_msec` enregistré pour offset au resume.

- **AC-AUD-09** `[Logic — BLOCKING] [Owner: gameplay-programmer]` — **GIVEN** GSM en `PAUSED`. **WHEN** GSM `state_changed(PLAYING)` (resume). **THEN** : (a) `AudioServer.is_bus_mute(0) == false` ; (b) fade en cours pré-pause reprend où il était (offset wall-clock appliqué) ; (c) musique audible immédiatement (queue préservée).

### Performance & lint

- **AC-AUD-10** `[Logic — BLOCKING] [Owner: lead-programmer]` — **GIVEN** code AudioSystem complet. **WHEN** lint CI `lint-audio-tween` exécuté. **THEN** : aucun match de `Tween.tween_property.*volume_db` ou `tween.*audio.*volume_db` dans `src/core/audio_system.gd` ou `src/gameplay/audio/`. Exception autorisée : crossfade ambient (Formula 4) explicitement annoté `# lint-audio-tween-ok: ambient crossfade time_scale==1.0 garanti`. VC-6 ADR-0009.

- **AC-AUD-11** `[Logic — BLOCKING] [Owner: lead-programmer]` — **GIVEN** code AudioSystem complet. **WHEN** lint CI `lint-audio-deferred` exécuté. **THEN** : tous les `connect()` dans handlers `src/gameplay/audio/` ou `_on_*` methods AudioSystem incluent flag `CONNECT_DEFERRED`. Forbidden grep : `\.connect\([^,)]+\)\s*$` (connect sans flag explicite) → fail.

- **AC-AUD-12** `[Logic — BLOCKING] [Owner: lead-programmer]` — **GIVEN** code AudioSystem complet. **WHEN** lint CI `lint-audio-pool` exécuté. **THEN** : aucun match de `AudioStreamPlayer.new()` ou `AudioStreamPlayer3D.new()` ou `AudioListener3D.new()` dans `src/` HORS `src/core/audio_system.gd` (exception unique pour pool boot `_ready()`).

- **AC-AUD-13** (r2.3 — Phase D.4 sub-budgets handler isolés) `[Performance — BLOCKING] [Owner: performance-analyst]` — **GIVEN** scène test 5 swings overlappés simultanés (3 swings actifs + 2 kills + 5 blood ambiance). **WHEN** mesure 1000 frames consécutifs via `Time.get_ticks_usec()`. **THEN** : (a) `frame_time p99 ≤ 16.6 ms` (60 fps locked) ; (b) audio CPU contribution `p99 ≤ 0.5 ms` (mesure isolée AudioSystem `_physics_process`) ; (c) `Performance.MEMORY_STATIC` delta après 1000 frames ≤ +100 KB ; (d) `Performance.OBJECT_COUNT` delta ≤ +0 (pas de fuite Nodes) ; (e) **`_on_enemy_killed` handler isolé** : wrap `Time.get_ticks_usec()` avant/après le call, `p99 < 100 µs` (0.1 ms — Phase D.4 budget) — sub-cascade silencieuse vs AC global frame ; (f) **`play_3d_at` isolé** : `p99 < 50 µs` (0.05 ms — pool reuse pas d'alloc, Phase D.4 budget) ; (g) **sidechain compressor CPU runtime** : si Godot 4.6 expose `Performance.AUDIO_OUTPUT_LATENCY` ou équivalent monitor → `< 0.5%` total CPU. Sinon ADVISORY evidence Sprint Audio (Godot Profiler tab `Audio` mesure manuelle). Test : `tests/perf/audio_5_swings_stress_test.gd`. VC-8 ADR-0009.

### AudioListener3D verification (R-2 ADR-0009)

- **AC-AUD-14** `[Integration — ADVISORY] [Owner: sound-designer + godot-specialist]` — **GIVEN** scene runtime avec Player + Camera3D actif + AudioListener3D enfant Camera3D (per ADR-0002 chain `... → Camera3D → AudioListener3D`). **WHEN** `play_3d_at(clac_stream, position = (10, 0, 0), AudioBuses.COMBAT_KILL)` joué et joueur tourné de 90° autour de l'axe Y. **THEN** : (a) panning stereo audible côté gauche (position 3D relative à AudioListener3D enfant Camera3D actif) ; (b) atténuation distance fonctionnelle (volume décroît avec distance Player ↔ position) ; (c) **EXACTEMENT 1** `AudioListener3D` instancié dans la scene tree (vérifier `get_tree().get_nodes_in_group("listener_3d").size() == 1` OU search via `find_children("*", "AudioListener3D", true).size() == 1`) — ce listener est l'enfant explicite Camera3D per ADR-0002 VC-5. Pas de second listener fallback. Documenter résultats dans `docs/engine-reference/godot/modules/audio.md` section "Empirical verifications". R-2 ADR-0009 + ADR-0002 chain validation.

### pitch_scale invariance (R-3 ADR-0009)

- **AC-AUD-15-a** (r2.3 — pitch shift bus-level allowlist, split BLOCKING headless-testable) `[Integration — BLOCKING] [Owner: qa-tester]` — **GIVEN** AudioSystem prêt, swoosh joue sur `SWING_ACTIVE` (allowlist=false), blood ambiance joue sur `COMBAT_KILL` (allowlist=true MAIS slot clac exclu via `_active_clac_players`), music joue sur `MUSIC` (allowlist=false), ambient joue sur `AMBIENCE` (allowlist=true). **WHEN** `Engine.time_scale = 0.3` (slow-mo Combat). **THEN** :
    - (a) **Bus invariants** : swoosh `AudioStreamPlayer.pitch_scale == 1.0 ± 0.001` (`SWING_ACTIVE`), music `pitch_scale == 1.0 ± 0.001` (`MUSIC`).
    - (b) **Bus pitch-shifted (slots blood ambiance UNIQUEMENT sur COMBAT_KILL)** : blood ambiance `pitch_scale ≈ 0.8821 ± 0.005` (≈ -2.1 semitones, Formula 5 à `time_scale=0.3`), ambient `pitch_scale ≈ 0.8821 ± 0.005`.
    - (b') **Slot clac exclu** (r2.3 — tolérance multi-kill correcte) : si un clac `clac.wav` joue sur `COMBAT_KILL` au moment du slow-mo, son slot pool 3D est tracké dans `_active_clac_players` et son `pitch_scale ∈ {1.0, 1.122, 1.260} ± 0.005` (valeur Rule 13 rang multi-kill actif au moment du `play()`, PAS unconditionally `1.0` — un slot multi-kill rang 2+ doit garder son pitch Rule 13 pendant le slow-mo, pas être ramené à 1.0). L'invariant testé est : pitch_scale du slot clac == valeur Rule 13 au moment du play, et NE PAS multipliée par Formula 5 slow-mo (exclusion explicite Rule 11 r2 préserve Couche 1 lisibilité rythmique).
    - (d) **Duration sample** : duration native du sample inchangée (Godot pitch_scale impacte la lecture, pas le fichier source).
    - (e) **Sons démarrés pendant slow-mo** : `enemy_killed` reçu pendant `time_scale=0.3` → blood ambiance démarrée 50 ms post-clac sur `COMBAT_KILL` (slot blood, pas slot clac) → assertion : `pitch_scale ≈ 0.8821 ± 0.005` AU MOMENT DU `play()` (handler set pitch avant play, pas après — Rule 11 r2 mécanisme). Pas de latence 1 tick visible.
    Test : `tests/integration/audio/pitch_shift_bus_allowlist_test.gd`. R-3 ADR-0009 amendée r2.

- **AC-AUD-15-b** (r2.3 — anti-pop waveform, ADVISORY headless-conditional) `[Visual/Feel — ADVISORY] [Owner: sound-designer + qa-tester]` — **GIVEN** GIVEN identique AC-AUD-15-a. **WHEN** transition `time_scale: 1.0 → 0.3 → 1.0` complète. **THEN** : (c) **Protocole anti-pop** : enregistrer waveform output via `AudioEffectRecord` sur bus `COMBAT_KILL` pendant transition, FFT post-render — discontinuité peak-to-peak entre frames adjacents `≤ 3 dB` (seuil empirique). Si `> 3 dB peak` : FAIL avec message "pitch_scale transition produces audible pop — R-3 ADR-0009 violation". **Headless CI** (driver Dummy ne supporte pas `AudioEffectRecord` post-effects) : test SKIPPED + evidence requirement `production/qa/evidence/audio-pitch-transition-{date}.md` (sound-designer écoute manuelle Sprint Audio + waveform analysis Audacity/REAPER). Documenter résultats dans `docs/engine-reference/godot/audio.md` section "Empirical verifications". Si playtest sound-designer révèle pop audible → escalade BLOCKING amendement Rule 11.

### Sidechain compressor MUSIC (r2 Phase A — VC-9)

- **AC-AUD-16** (r2 — sidechain MUSIC ducking) `[Integration — BLOCKING] [Owner: qa-tester + sound-designer]` — **GIVEN** music playing sur `MUSIC` bus à fader nominal `volume_db = -3.0`, sidechain compressor configuré (Rule 16). **WHEN** clac `COMBAT_KILL` joué à `volume_db = 0.0`. **THEN** :
    - (a) **Mesure peak post-compressor** : utiliser `AudioServer.get_bus_peak_volume_left_db(MUSIC_idx, 0)` (peak meter post-effects, pas `get_bus_volume_db()` qui retourne le fader nominal). À t≈5-30 ms post-clac onset : peak ≈ `-6 dB ± 1.5 dB` (ducked peak, fader -3 dB + sidechain reduction ≈ -3 dB).
    - (b) **Release exponentielle** : `get_bus_peak_volume_left_db(MUSIC_idx, 0)` remonte vers `-3 dB ± 1 dB` (nominal) sur ~200 ms wall-clock release.
    - (c) **Reset multi-kill** : si 2e clac arrive avant fin release (e.g. multi-kill 50 ms apart), peak meter retombe à -6 dB et release redémarre depuis zéro.
    - (d) **Continuité music** : `music_player.playing == true` constant pendant tout le ducking (la musique ne s'arrête JAMAIS — continuité Couche 3).
    - (e) **Headless fallback** : si CI headless (`--audio-driver Dummy`) ne supporte pas peak meter post-effects (à vérifier empiriquement Sprint Audio), basculer (a)+(b) en ADVISORY avec evidence playtest sound-designer + waveform analysis (`AudioEffectRecord` post-render). Assertions (c)+(d) restent BLOCKING (testables sans peak meter — flags d'état + `playing` boolean).
    Test : `tests/integration/audio/sidechain_music_ducking_test.gd`. Cohérent ADR-0009 D-1 amendement r2 + Rule 16 + Formula 6.

### Multi-kill counter reset (r2 Phase A — VC-10)

- **AC-AUD-17** (r2) `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** swing actif, `_kill_count_this_swing` after 3 kills = 3. **WHEN** swing termine (`swing_ended` reçu). **THEN** : (a) `_kill_count_this_swing` reset à `0` au tick `swing_ended` reception (DEFERRED frame N+1) ; (b) prochain swing commencé (`swing_started` reçu) confirme counter `0` ; (c) prochain `enemy_killed` premier kill nouveau swing : clac joué `pitch_scale = 1.0` (pas +6 semitones bug carry-over). Test inclus dans `tests/integration/audio/multi_kill_pitch_shift_test.gd` (extension AC-AUD-05).

### Secret collect différenciation (r2.2 — NB-CRD-6 Option A)

- **AC-AUD-18** (r2.2 — secret collect clac aigu bus SFX) `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** AudioSystem prêt, AudioBuses configurés (Rule 16 sidechain armed sur `COMBAT_KILL`), spy injecté sur `play_3d_at` et `play_2d`, mock Secret node `secret_node_mock` avec `global_position = Vector3(5, 1, 3)`. **WHEN** `Secret.secret_collected.emit(secret_node_mock, 1)` émis (tier 1) depuis le main thread, propagation DEFERRED frame N+1. **THEN** :
    - (a) **Dispatch correct** : `play_3d_at` est appelé exactement 1 fois avec `stream == clac_stream`, `bus == AudioBuses.SFX`, `pitch_scale ≈ 1.335 ± 0.001` (`SECRET_PITCH_SCALE = 2.0 ** (5/12)`, Formula 7).
    - (b) **Bus exclusif `SFX`** : `play_3d_at` n'est PAS appelé avec `bus == AudioBuses.COMBAT_KILL` ni `bus == AudioBuses.SWING_ACTIVE`. Vérifier via spy assert `bus_arg != AudioBuses.COMBAT_KILL`.
    - (c) **Pas de ducking SWING_ACTIVE** : `duck_bus` n'est PAS appelé suite à ce signal (vs Rule 13 kill qui appelle `duck_bus(SWING_ACTIVE, -6, 30)`).
    - (d) **Compteur multi-kill intact** : `_kill_count_this_swing` reste inchangé après réception `secret_collected`. Le secret n'incrémente PAS le compteur combat.
    - (e) **Position 3D capturée** : la position passée à `play_3d_at` `== secret_node_mock.global_position` (`Vector3(5, 1, 3) ± 0.001`) capturée au tick de réception (pas une ref live au node — pour cohérence avec Rule 7 et défense queue_free post-collect).
    - (f) **Pas de blood ambiance** : `play_3d_at` n'est PAS appelé avec `stream == blood_stream` suite à ce signal (vs kill Rule 13 qui chain blood ambiance 50 ms après clac).
    - (g) **Tier indifférent** : ré-émission `Secret.secret_collected.emit(secret_node_mock, 3)` (tier 3) → mêmes assertions (a)-(f), `pitch_scale` identique. MVP ne différencie pas les tiers.
    - (h) **Position invalide fallback** : si `secret_node_mock.global_position = Vector3(NAN, NAN, NAN)`, alors `play_2d` est appelé (head-locked fallback) avec `bus == AudioBuses.SFX` et `pitch_scale ≈ 1.335` ; `play_3d_at` n'est PAS appelé. `push_warning` capturé.
    Test : `tests/integration/audio/secret_collect_pitch_shift_test.gd`. Cohérent Rule 17 + Formula 7 r2.2. Pillar 4 viscéralité MVP minimum.

- **AC-AUD-19** (r2.2 — secret pitch invariant slow-mo) `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** AudioSystem prêt, `Engine.time_scale = 0.3` (slow-mo Combat actif). **WHEN** `Secret.secret_collected.emit(secret_node_mock, 1)` reçu DEFERRED. **THEN** : (a) `play_3d_at` appelé avec `pitch_scale ≈ 1.335 ± 0.001` (`SECRET_PITCH_SCALE` invariant — bus `SFX` PAS dans pitch allowlist Rule 11) ; (b) le `pitch_scale` n'est PAS composite avec Formula 5 slow-mo (`pitch_scale != 1.335 × 0.8821`) ; (c) à `time_scale = 1.0` retour, prochain `secret_collected` produit toujours `pitch_scale ≈ 1.335`. Test inclus dans `tests/integration/audio/secret_collect_pitch_shift_test.gd`.

### Sidechain idempotency double-boot (r2.3 — Phase D.2 guard formal coverage)

- **AC-AUD-20** (r2.3 — Phase D.2 idempotent guard) `[Logic — BLOCKING] [Owner: qa-tester + gameplay-programmer]` — **GIVEN** AudioSystem instancié et `_setup_sidechain_compressor()` déjà appelé une fois au boot normal (compressor `AudioEffectCompressor` ajouté sur bus `MUSIC`, `AudioServer.get_bus_effect_count(MUSIC_idx) == 1`). **WHEN** `_setup_sidechain_compressor()` appelé une seconde fois (cas pathologique : autoload re-instantiation, scene reload mid-game, test fixture réutilisé). **THEN** : (a) `AudioServer.get_bus_effect_count(MUSIC_idx) == 1` (PAS 2 — guard idempotent Phase D.2 ligne 218) ; (b) `push_warning("AudioSystem: AudioEffectCompressor déjà présent sur MUSIC bus, skip add (idempotent)")` capturé via mock logger ou `OS.is_debug_build()` debug-guarded `_warning_handler: Callable` ; (c) **propriétés intactes** : `compressor.attack_us == 5000`, `compressor.release_ms == 200.0`, `compressor.sidechain == "COMBAT_KILL"` (l'effet original n'est pas écrasé) ; (d) **failure mode protection** : si guard absent (régression), test détecte `effect_count == 2` → FAIL avec message "Phase D.2 idempotent guard regression — double sidechain compressor produit -6 dB ducking effective au lieu de -3 dB, casse Couche 3 continuité musicale". Test : `tests/unit/audio/sidechain_idempotent_test.gd`. Cohérent ADR-0009 D-1 amendement r2 + Phase D.2.

### F-04 crossfade midpoint (r2.3 — Phase C linear-amplitude fix coverage)

- **AC-AUD-21** (r2.3 — F-04 linear-amplitude midpoint, prouve fix Phase C) `[Logic — BLOCKING] [Owner: qa-tester]` — **GIVEN** AudioSystem prêt, `Ambience #1` joue stream A à `volume_db = 0.0`, `Ambience #2` charge stream B à `volume_db = -80.0` (idle), crossfade démarre via `level_active(etage_id_2, ...)` avec `CROSSFADE_DURATION_MS = 1000.0`, `_get_time_msec` mocké séquence `[0, 250, 500, 750, 1000]`. **WHEN** crossfade `_physics_process` exécuté à chaque tick mocké. **THEN** : (a) à `t = 0` : `volume_db_old ≈ 0 dB ± 0.1`, `volume_db_new ≤ -60 dB` ; (b) **midpoint `t = 500` (50%)** : `volume_db_old ≈ -6 dB ± 1 dB` ET `volume_db_new ≈ -6 dB ± 1 dB` (linear-amplitude lerp Phase C — F-04 hardened) ; (c) **fix Phase C anti-regression** : si test observe `volume_db_old ≈ -40 dB` ET `volume_db_new ≈ -40 dB` au midpoint → FAIL avec message "F-04 dB-domain lerp détecté (ancien comportement r2 dip ~3 dB midpoint), Phase C linear-amplitude lerp non appliqué — vérifier `linear_to_db(maxf(amp_old, 1e-4))` impl" ; (d) à `t = 1000` (100%) : `volume_db_old ≤ -60 dB`, `volume_db_new ≈ 0 dB ± 0.1` ; (e) **boundary case `D = 0.0`** : si tuning knob `ambient_crossfade_ms = 0.0` → swap instantané (`volume_db_old = -80`, `volume_db_new = 0`) + `push_warning` capturé. Test : `tests/unit/audio/formula4_crossfade_midpoint_test.gd`. Cohérent F-04 hardening Phase C (anti-dip dB-domain).

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| ~~Level signal `etage_loaded(etage_id, music_stream, ambient_stream)` n'existe pas encore~~ ✅ **RÉSOLU r2 (2026-04-27)** Option C : Audio consume `level_active` existant + lookup synchrone `LevelSystem.get_etage_audio_streams(etage_id)`. Level GDD r4 amendé (§Interactions Audio row + pseudocode `get_etage_audio_streams` + Tuning Knob `ETAGE_AUDIO_MAPPING`). Pas de nouveau signal créé. | level-designer + Martin | ✅ 2026-04-27 | Décision Martin "oui" Option C — Level r4 amendement chirurgical 4 lignes. Zero churn pour autres consumers de `level_active` (Checkpoint/Enemy/Hazard/Secret/HUD/Tutorial). |
| ~~`SLOW_MO_SCALE` registry = `0.15` mais Combat r6 utilise `0.3` dans formules audio (AC-CMB-51, ducking). Lequel est actuel ?~~ ✅ **RÉSOLU r2.2 (2026-04-27)** : valeur canonique = **`SLOW_MO_SCALE = 0.3`** + **`SLOW_MO_DURATION_MS = 50 ms`** (retune Martin D3 lors de Combat r1 — micro-pause rythmique 167 ms percus, pas climax cinématique). Registry était stale (draft initial Combat pré-r1 jamais répercuté) — sync exécuté 2026-04-27 via `/consistency-check audio-system` : entries SLOW_MO_SCALE et SLOW_MO_DURATION_MS mises à jour avec `was:` annotations, safe_ranges élargis ([0.10,0.50] / [30,150] alignés Combat Tuning Knobs Section G), `audio-system.md` ajouté en `referenced_by`. Audio GDD r2 corps (Couche 4, Rule 11, Formula 5, AC-AUD-04/05/15, mix hierarchy fenêtre 200 ms) déjà aligné sur 0.3/50 ms — seuls la table Dependencies (ligne 440) et cette OQ étaient stales, fixées dans la même passe. Pré-Sprint Audio gate fermé. | systems-designer + Martin | ✅ 2026-04-27 | Registry est l'autorité numérique post-sync. Combat GDD = autorité de tuning (retune Martin D3 r1). Audio System aligné. Aucun changement de spec/formule requis. |
| Movement `dash_rejected` signal n'existe pas formellement (Movement GDD §Open Questions). Audio System assume sa présence pour `dash_reject.wav`. | systems-designer (Movement) + Martin | Avant Sprint Audio | Coordination Movement GDD r4 — soit signal explicite, soit Audio observe `dash` action input + `_dash_cooldown_active` polling. |
| Voice/VO bus Tier 3 — accessibility subtitles + narrative voice acting. Inclus dans bus hierarchy r1 ou amendement post-MVP ? | audio-director + accessibility-specialist | Tier 3 (Full Vision) | Différé. ADR-0009 D-1 prévoit ajout post-MVP via `default_bus_layout.tres` migration + `AudioBuses.VOICE` constante. Pas d'impact MVP. |
| Pool size 4 (2D) suffit-il pour Tier 2 combo system étendu ? Si combo > 4 swings overlappés, saturation audible. | sound-designer + game-designer | Tier 2 playtest | Mitigation R-1 ADR-0009 : augmenter pool 4 → 6 si playtest révèle. Tuning knob `pool_2d_size` ajustable. |
| ~~Master bus mute coupe-t-il aussi les UI clicks pendant pause menu ?~~ ✅ **OQ#6 RÉSOLU r2 (2026-04-27 Phase B)** : MVP = oui, mute Master coupe tout incluant `UI` bus (simplicité d'implémentation, pas de surface API supplémentaire, joueur navigue silencieusement dans pause menu pendant ~1-2 s — acceptable UX). Tier 2 amendement ADR-0009 D-1 : si playtest pause menu révèle UX dégradée, basculer en mute sélectif (mute `Music + SFX + Ambience + SWING_ACTIVE + COMBAT_KILL`, exclure `UI`) — décision Martin Tier 2. | ux-designer + Martin | ✅ 2026-04-27 | Décision MVP : mute total Master, simple et défensif. Tier 2 reconsidéré sur retour playtest. |
| ~~Sub-bass continuous ambient (Chrome Zen room tone) — asset spec et niveau dB ?~~ ✅ **OQ#7 RÉSOLU r2 (2026-04-27 Phase B)** : `room_tone_chrome_zen.wav` (asset à produire pré-Sprint Audio par sound-designer) — sub-bass synthwave sustain, **fréquence dominante 40-80 Hz**, `volume_db = -12 dB` nominal sur bus `AMBIENCE`, durée loop 30-60 s seamless (pas de discontinuité sample boundary). Joue en continu sur `Ambience #1` au boot Level (premier `level_active` étage 1). Tuning knob `room_tone_volume_db` exposé. Sous slow-mo : suit Formula 5 pitch shift bus-level (`AMBIENCE` allowlist=true) — drone-down vers ~36 Hz dominante au plancher, identité HLM. À Tier 3 Accessibility : toggle `Reduce Ambient Intensity` peut désactiver le room tone pour photosensitivité auditive. | sound-designer + audio-director | ✅ 2026-04-27 | Spec validée Phase B. `/asset-spec system:audio-system` produira la fiche détaillée (waveform target, format `.wav` 44.1 kHz mono, loop boundaries) post-art-bible. |
| Music asset format — `.ogg` 44.1 kHz stereo (~5 MB compression) vs `.wav` (~50 MB uncompressed). Compromise budget memory 50 MB MVP. | audio-director | Sprint Audio asset spec | Recommandation : `.ogg` Vorbis quality 6 (≈ 192 kbps) — ratio compression ~10:1, qualité indistinguible WAV pour music synthwave. SFX courts en `.wav` 16-bit mono pour latence minimale. |
| Latency `AudioStreamPlayer.play()` sur pool pré-instancié — confirmer pas de hitch ≥ 1 frame (R ADR-0009). | godot-specialist + performance-analyst | Sprint Audio bench | Test empirique pré-Sprint. Si hitch détecté, mitigation : pré-charger `stream` au boot pour assets fréquents (swoosh, clac). |
| ~~AC-AUD-04 `_get_time_msec` Callable injection — API stable ou pattern test-only ?~~ ✅ **OQ#9 RÉSOLU r2 (2026-04-27 Phase B)** : pattern **test-only** via méthode `_set_time_provider(callable: Callable)` debug-guarded `if OS.is_debug_build(): _get_time_msec = callable` (no-op en release build). Cohérent ADR-0006 D-4 (Combat mocks). API publique production reste opaque (`_get_time_msec` initialisé à `Time.get_ticks_msec` au `_ready()`). Tests injectent via `AudioSystem._set_time_provider(mock_callable)` puis désinjectent via `AudioSystem._set_time_provider(Time.get_ticks_msec)`. Forbidden : appeler `_set_time_provider` en gameplay code (lint CI grep `_set_time_provider` autorise uniquement `tests/**`). | godot-gdscript-specialist + lead-programmer | ✅ 2026-04-27 | Pattern test-only debug-guarded, cohérent Combat ADR-0006 D-4. AudioSystem expose `_set_time_provider` mais n'est appelable qu'en debug build (pas dans release). |

---

**Status** : Draft **r2.2 Phase A+B+C+D** complete (2026-05-03) — Phase C+D auto-approuvées en exécution autonome chain post-Combat audit, formalisent les patterns implémentation déjà implicites Phase A. Précédentes phases : Phase A vision (Martin D3 Option A pitch shift bus allowlist + clac slot exclusion explicite, sidechain MUSIC ← COMBAT_KILL, multi_kill pitch +N + cap test, death 60-80 ms + overlap clarifié non-automatisable) + Phase B spec (pools 5+12, OQ#6/7/9 résolus) + 14 BLOCKING re-review fixes (2026-04-27).
> - Éditorial r1 résidu : header "≤ 40 ms" → 60-80 ms ; Cross-Refs death.wav corrigé ; bus naming UPPER_SNAKE_CASE propagé partout (Rule 3, Mix hierarchy §1-5, Visual/Audio table, ACs, Cross-Refs) ; Mix hierarchy §4 contradiction sidechain corrigée ; §5 UI mute phrase auto-contradictoire nettoyée ; Formula 3 pool_size 5/12 (r2 sizing) ; Edge Cases pool 12 cohérence.
> - Spec gaps Phase A : Rule 11 clac slot exclusion explicite via `_active_clac_players` tracker ; pitch_scale appliqué AVANT `play()` (zero latency 1 tick) ; Rule 16 prose attack 5 ms perceptuelle correcte ; ADR-0009 D-6 amendé pour reconnaître ADR-0002 chain (1 listener explicite) ; Rule 9 alignée.
> - AC testability : AC-AUD-01 ajout sidechain effect verification ; AC-AUD-02 (e) `get_child_count() == 20` (déterministe) ; AC-AUD-03 (c) cycle pool 5 ; AC-AUD-05 cap 4e kill testé ; AC-AUD-07 ResourceLoader precheck + overlap evidence playtest ; AC-AUD-14 (c) `size() == 1` per ADR-0002 ; AC-AUD-15 (c) protocole anti-pop concret + (e) sons démarrés slow-mo ; AC-AUD-16 mesure `get_bus_peak_volume_left_db` post-effects + headless fallback.
> - ADR-0009 D-6 amendement r2 (reconciliation ADR-0002 chain Camera3D → AudioListener3D explicite).
> - **Phase C (formules hardening — 2026-05-03)** : ✅ F-01 div-par-zéro guard (`SWOOSH_FADE_DURATION_MS ≤ 0` short-circuit `SILENCE_DB`), ✅ F-02 renommé "perceptuel (linear-amplitude lerp)" + clarification courbe perçue exponentielle + `linear_to_db` log-guard `maxf(amp, 1e-9)`, ✅ F-04 equal-power-style crossfade (linear-amplitude lerp pour éviter dip ~3 dB midpoint dB-domain) + div-par-zéro guard.
> - **Phase D (impl details — 2026-05-03)** : ✅ D.1 `play_3d_at` world space `global_position` contract + `Vector3.is_finite` assert ; ✅ D.2 boot guard idempotent `add_bus_effect` (skip si AudioEffectCompressor déjà présent sur MUSIC bus, évite double compressor 16:1 effective) ; ✅ D.3 `_active_clac_players` tracker concrétisé (impl pseudo-code Dictionary slot_idx → true, callback `finished` CONNECT_ONE_SHOT pour erase) ; ✅ D.4 perf split handler/mixer thread documenté (AudioServer interne, pas de custom thread — Pillar 1 FLOW latency budget) ; ✅ **D.5 RESOLVED 2026-05-03** — `docs/engine-reference/godot/modules/audio.md` reçoit section AudioEffectCompressor complète (props Godot 4.6 + gotcha `attack_us` µs vs `release_ms` ms + boot guard pattern + AC-AUD-01 (d) verification block + Common Pitfalls). Pré-requis Sprint Audio levé.

**Registry candidates pour update** : aucun nouveau cross-system fact (toutes constantes Audio sont system-internal MVP). Seul `RESPAWN_DELAY` referenced_by mis à jour si non déjà présent.

**Next steps** :
1. `/consistency-check audio-system` — vérifier alignement avec Combat r6 (Mix hierarchy, AC-CMB-51, AC-CMB-audio-01/02), GSM r1 (state_changed signal), Camera r2 (AudioListener3D = Camera3D), Movement (dash/wallrun/death signals), Level r4 (level_active + get_etage_audio_streams Option C).
2. `/design-review design/gdd/audio-system.md` (fresh session) — verdict APPROVED / NEEDS REVISION sur r2.2 Phase A+B+C+D complète.
3. ~~Coordination Level GDD r4 (signal `etage_loaded` formalisation)~~ ✅ **DONE 2026-04-27** — Level r4 amendement Option C appliqué (`get_etage_audio_streams` lookup API + `ETAGE_AUDIO_MAPPING` knob).
4. `/create-epics audio-system` post-APPROVED.
5. **Combat 020 unblock partiel** : avec Phase C+D complète (formules hardened + impl patterns concrets), un `MockAudioHandler` côté Combat peut implémenter le contract AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02 sans attendre AudioSystem implémentation pleine. Le mock vérifie : (a) `_get_time_msec()` Callable injection (Phase A r2 OQ#9 résolu) ; (b) flag `_kill_sound_played_this_swing` reset à `swing_ended` (AC-CMB-audio-01 contract) ; (c) bus `swing_active` ducking -6 dB DEFERRED frame N+1 + release 30 ms (Formula 2 hardened). Story 020 Status peut passer `Blocked → Ready` après `/consistency-check`.

---

**Phase D.5 Tracker (Open Question) — ✅ RESOLVED 2026-05-03** : `docs/engine-reference/godot/modules/audio.md` reçoit section `AudioEffectCompressor (Sidechain Ducking)` complète. Note de réconciliation : la review r2.3 émettait l'hypothèse d'un breaking change `attack` ms (Godot 4.3) → `attack_us` µs (Godot 4.6). En réalité **les noms `attack_us` / `release_ms` existent depuis Godot 3.x — c'est un gotcha de nommage asymétrique long-standing, pas un breaking change 4.x**. AC-AUD-01 (d) reste valide tel quel (assertions `attack_us == 5000.0`, `release_ms == 200.0`). Engine-ref dump débloque `tests/integration/audio/audio_boot_test.gd` Sprint Audio.
