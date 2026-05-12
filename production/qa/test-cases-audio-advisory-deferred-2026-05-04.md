# Test Cases — Audio System ADVISORY DEFERRED — Sprint Audio Playtest
**Date** : 2026-05-04
**Epic** : Audio System (12/12 stories Complete, commit `6e5cf2b`)
**Stage** : Pre-Production — Solo MVP
**Scope** : 4 groupes ADVISORY DEFERRED — session playtest sound-designer post-assets finaux
**Sound-designer** : @TBD (Sprint Audio dédiée post-MVP)
**Godot-specialist** : @TBD (sign-off D-1 et D-3)

**Contexte** : 166/166 tests automatisés PASS. Les ACs ci-dessous nécessitent
un driver audio natif (Core Audio macOS / WASAPI Windows / ALSA Linux) et une
écoute humaine sur casque stéréo. Ils ne peuvent pas être couverts en headless
(driver Dummy, pas de peak meter, pas de spatialisation perçue).

---

## Setup Prérequis Commun

Ces prérequis s'appliquent à tous les test cases de ce document.

**Matériel** :
- Casque stéréo filaire (pas de Bluetooth — latence DSP variable)
- Machine avec driver natif actif (pas de `--headless`)

**Logiciels** :
- Godot 4.6 Editor (mode Edit, pas export)
- Audacity ou REAPER (capture loopback)
- `AudioEffectRecord` sur bus `Music` (inséré temporairement en post-compressor pour captures D-4)

**Scène de référence** : `src/gameplay/player/Player.tscn`
- Arbre attendu : `Player > CameraArm > CameraEffects > Camera3D > AudioListener3D`
- Vérifier que `AudioListener3D` est l'unique listener actif (AC-AUD-14 c confirmée headless)

**Assets audio requis** (Sprint Audio — à fournir avant session) :
- `clac.wav` — SFX impact katana mixé à -6 dB RMS
- `music_synthwave.ogg` — loop synthwave 120 BPM, -3 dB nominal sur bus `Music`

**Réglages AudioServer à vérifier avant la session** :
- Bus `Music` : fader -3 dB, `AudioEffectCompressor` présent (threshold -24 dB, ratio 4.0, attack 5 ms, release 200 ms, sidechain `combat_kill`)
- Bus `combat_kill` : fader 0 dB, pas d'effet
- Pool 3D : 12 slots (`audio._3d_pool.size() == 12`)

---

## D-1 — AudioListener3D : Panning et Atténuation Distance

**Story** : `production/epics/audio-system/story-010-audiolistener3d-verification-adr-0002-chain.md`
**AC source** : AC-AUD-14 a + b
**Gate** : ADVISORY

---

### Test Case TC-AUD-01 — Panning stéréo Camera3D

**AC couverte** : AC-AUD-14 (a) — Panning stéréo via AudioListener3D enfant Camera3D
**Story** : story-010
**Type** : Manual playtest sound-designer
**Setup requis** :
- Godot Editor, Player.tscn ouverte, driver natif actif
- Casque stéréo branché, volume modéré

**Préconditions** :
1. `Player.tscn` chargée en mode Play (F5 depuis Editor ou Run Scene)
2. AudioSystem autoload actif, pool 3D initialisé
3. AudioListener3D est l'enfant direct de Camera3D (position locale Vector3.ZERO)
4. Player.rotation.y = 0 (orientation initiale — source sera à droite)

**Steps** :
1. Via GDScript console ou script debug temporaire, appeler :
   `AudioSystem.play_3d_at(clac_stream, Vector3(10, 0, 0), &"combat_kill")`
   (source à 10 unités sur l'axe +X — droite world space)
2. Écouter le son résultant sur casque stéréo
3. Confirmer côté perçu (droite attendu, Player face +Z, source à +X)
4. Appeler `player.rotation.y = PI / 2` (rotation 90° antihoraire — joueur face +X)
5. Rejouer : `AudioSystem.play_3d_at(clac_stream, Vector3(10, 0, 0), &"combat_kill")`
6. Écouter : après rotation, la source est maintenant derrière le joueur (pas de panning fort attendu)
7. Appeler `player.rotation.y = -PI / 2` (rotation 90° horaire — joueur face -X)
8. Rejouer le clac sur Vector3(10, 0, 0)
9. Écouter : source maintenant à gauche — panning gauche attendu

**Expected Result** :
- Step 2 : son perçu nettement à droite dans le casque
- Step 6 : son perçu centré ou légèrement à droite (source derrière, atténuation)
- Step 9 : son perçu nettement à gauche dans le casque
- Godot 4.6 gère le panning automatiquement via l'unique AudioListener3D enfant de Camera3D (ADR-0009 D-6)

**Actual Result** : _(à remplir post-playtest)_
**Pass/Fail** : _(à remplir post-playtest)_
**Sign-off** : sound-designer @TBD / godot-specialist @TBD / date _(à remplir)_

---

### Test Case TC-AUD-02 — Atténuation distance (Inverse Distance model)

**AC couverte** : AC-AUD-14 (b) — Volume décroît avec distance (perceptuel)
**Story** : story-010
**Type** : Manual playtest sound-designer
**Setup requis** :
- Même setup que TC-AUD-01
- Optionnel : Audacity loopback pour mesurer delta dB entre les deux lectures

**Préconditions** :
1. `Player.tscn` en mode Play, Player.rotation.y = 0 (axe +X = droite devant)
2. AudioSystem actif, `unit_size` Godot 4.6 default (Inverse Distance model)
3. Aucune modification du falloff curve AudioStreamPlayer3D

**Steps** :
1. Appeler : `AudioSystem.play_3d_at(clac_stream, Vector3(1, 0, 0), &"combat_kill")`
   (source à 1 unité — proche)
2. Écouter et noter le niveau perçu (ou capturer via Audacity loopback)
3. Attendre 2 secondes (silence)
4. Appeler : `AudioSystem.play_3d_at(clac_stream, Vector3(10, 0, 0), &"combat_kill")`
   (source à 10 unités — loin)
5. Écouter et noter le niveau perçu (ou comparer forme d'onde Audacity)
6. Comparer les deux niveaux — différence attendue ~-20 dB (Inverse Distance : 20 × log10(10/1))

**Expected Result** :
- La source proche (1 u) est nettement plus forte que la source lointaine (10 u)
- Différence perceptuelle claire sur casque, estimée ~-20 dB (Inverse Distance Godot default)
- Aucun clipping sur la source proche

**Actual Result** : _(à remplir post-playtest)_
**Pass/Fail** : _(à remplir post-playtest)_
**Sign-off** : sound-designer @TBD / date _(à remplir)_

---

## D-2 — Validation Auditive Lint ADVISORY

**Story** : `production/epics/audio-system/story-009-anti-patterns-lint-static-pool-tween-deferred.md`
**AC source** : AC-AUD-10 / AC-AUD-11 / AC-AUD-12 (lint statique PASS 0 violation)
**Gate** : ADVISORY (lint statique = BLOCKING PASS ; validation auditive = confirmation qualitative)

---

### Test Case TC-AUD-03 — Absence d'artefacts liés aux fades wall-clock

**AC couverte** : AC-AUD-10 (wall-clock fades `_physics_process` — zéro Tween volume_db)
**Story** : story-009
**Type** : Manual playtest sound-designer
**Setup requis** :
- Godot Editor, Player.tscn + scène de combat de référence
- Casque stéréo, variable `Engine.time_scale` accessible via console debug

**Préconditions** :
1. Lint statique AC-AUD-10/11/12 confirmé PASS 0 violation (log `audio-anti-patterns-lint-2026-05-04.log`)
2. Scène active avec AudioSystem, bus `combat_kill` et swoosh fade opérationnels
3. `Engine.time_scale = 1.0` (normal)

**Steps** :
1. Déclencher un swing katana (ou appeler `AudioSystem._on_swing_started()` via console)
2. Écouter le swoosh fade : volume doit descendre progressivement pendant le swing
3. Confirmer : pas de glitch, pas de coupure abrupte, fade fluide
4. Changer `Engine.time_scale = 0.5` (slow-motion)
5. Déclencher un second swing
6. Écouter : le fade doit s'exécuter à la même vitesse wall-clock (indépendant de time_scale)
7. Remettre `Engine.time_scale = 1.0`
8. Déclencher un third swing — confirmer retour comportement normal

**Expected Result** :
- Steps 2-3 : fade swoosh fluide sans artefact, durée conforme à `SWOOSH_FADE_DURATION_MS`
- Steps 5-6 : fade identique en durée réelle même avec time_scale = 0.5 (wall-clock garanti par `_physics_process` + `_get_time_msec.call()`)
- Zéro glitch, zéro pop, zéro coupure abrupte à aucune étape

**Actual Result** : _(à remplir post-playtest)_
**Pass/Fail** : _(à remplir post-playtest)_
**Sign-off** : sound-designer @TBD / date _(à remplir)_

---

## D-3 — Sidechain Compressor CPU (Godot Profiler)

**Story** : `production/epics/audio-system/story-011-performance-budget-5-swings-stress-sub-budgets-phase-d4.md`
**AC source** : AC-AUD-13 (g) — Δ CPU sidechain compressor < 0.5% total CPU
**Gate** : ADVISORY

---

### Test Case TC-AUD-04 — Sidechain CPU profiler Godot Editor

**AC couverte** : AC-AUD-13 (g) — CPU consommé par `AudioEffectCompressor` sidechain MUSIC < 0.5% total CPU
**Story** : story-011
**Type** : Manual playtest godot-specialist + sound-designer
**Setup requis** :
- Godot 4.6 Editor (pas headless — profiler Audio uniquement accessible en Editor)
- Scène active avec AudioSystem + bus Music + sidechain compressor configuré
- Onglet Profiler ouvert dans Godot Editor (Debug > Profiler)

**Préconditions** :
1. `AudioEffectCompressor` présent sur bus `Music` (vérifié story-001 boot idempotent)
2. Configuration : threshold -24 dB, ratio 4.0, attack 5 ms, release 200 ms, sidechain `combat_kill`
3. Music stream jouant en boucle (music_synthwave.ogg ou équivalent)
4. Profiler Editor ouvert, mesure CPU en cours

**Steps** :
1. Lancer la scène (Play Scene F6 depuis Editor)
2. Ouvrir l'onglet Profiler dans le bas de l'écran Godot Editor
3. Dans Profiler, activer la catégorie `Audio` et démarrer la capture
4. Laisser tourner 30 secondes sans interaction — noter CPU audio baseline avec sidechain ON
5. Via console debug, désactiver le compressor : `AudioServer.set_bus_effect_enabled(music_idx, 0, false)`
   (où `music_idx = AudioServer.get_bus_index(&"Music")`, effect index 0)
6. Laisser tourner 30 secondes — noter CPU audio baseline avec sidechain OFF (bypass)
7. Calculer Δ CPU = (sidechain ON) − (sidechain OFF)
8. Réactiver le compressor : `AudioServer.set_bus_effect_enabled(music_idx, 0, true)`

**Expected Result** :
- Δ CPU sidechain compressor < 0.5% du CPU total sur target hardware (entry-level gaming laptop)
- Valeur de référence headless (non-compressor path) : audio CPU p99 = 9 µs (×55 sous budget 0.5 ms)
- Le compressor sidechain ne doit pas dégrader le budget frame global de manière perceptible

**Actual Result** : _(CPU ON: ___ % / CPU OFF: ___ % / Δ: ___ %)_
**Pass/Fail** : _(à remplir post-playtest)_
**Sign-off** : godot-specialist @TBD / sound-designer @TBD / date _(à remplir)_

---

## D-4 — Sidechain MUSIC : Peak, Release et Multi-Kill

**Story** : `production/epics/audio-system/story-012-sidechain-music-peak-meter-verification-headless-fallback.md`
**AC source** : AC-AUD-16 a + b + c
**Gate** : ADVISORY
**Note** : AC-AUD-16 (d) continuité musicale et (e) fallback headless sont BLOCKING PASS (3/3 automatisés).
Ces 3 test cases couvrent les ACs qui nécessitent le driver audio natif + peak meter.

**Setup commun D-4** :
- `AudioEffectRecord` inséré sur bus `Music` **en post-compressor** (après `AudioEffectCompressor` dans la chaîne)
- OU Audacity/REAPER en capture loopback système
- Référence peak meter : `AudioServer.get_bus_peak_volume_left_db(music_idx, 0)` lu depuis console debug
- Pitfall documenté : `get_bus_volume_db()` retourne le fader nominal (-3 dB), PAS le peak post-effects — utiliser `get_bus_peak_volume_left_db()`

---

### Test Case TC-AUD-05 — Peak music ducked post-clac (-6 dB ± 1.5)

**AC couverte** : AC-AUD-16 (a) — Peak post-compressor MUSIC ducked à -6 dB ± 1.5 lors d'un kill
**Story** : story-012
**Type** : Manual playtest sound-designer
**Setup requis** :
- Driver natif actif (Core Audio / WASAPI / ALSA)
- `AudioEffectRecord` sur bus `Music` post-compressor OU loopback Audacity
- Console debug accessible en cours de jeu

**Préconditions** :
1. Music stream en lecture continue sur bus `Music` (fader -3 dB nominal)
2. Peak idle attendu : -3 dB ± 0.5 (confirmer avant test)
3. `AudioEffectRecord.recording = true` (ou Audacity loopback démarré)

**Steps** :
1. Confirmer peak idle = -3 dB ± 0.5 via `AudioServer.get_bus_peak_volume_left_db(music_idx, 0)`
2. Appeler : `AudioSystem.play_3d_at(clac_stream, Vector3.ZERO, &"combat_kill")` à t=0
3. À t≈20 ms (après attack 5 ms + marge) : lire `get_bus_peak_volume_left_db(music_idx, 0)`
4. Comparer la valeur lue à -6 dB ± 1.5

**Expected Result** :
- Peak post-compressor à t≈20 ms = **-6 dB ± 1.5** (sidechain actif, compressor duck -3 dB sur fond -3 dB nominal)
- Valeur hors fenêtre [-7.5, -4.5] = FAIL

**Actual Result** : _(peak mesuré à t≈20 ms : ___ dB)_
**Pass/Fail** : _(à remplir post-playtest)_
**Sign-off** : sound-designer @TBD / date _(à remplir)_

---

### Test Case TC-AUD-06 — Release exponentielle retour nominal (~200 ms)

**AC couverte** : AC-AUD-16 (b) — Release exponentielle ~200 ms, retour -3 dB ± 1 post-clac
**Story** : story-012
**Type** : Manual playtest sound-designer
**Setup requis** :
- Même setup que TC-AUD-05
- Chronomètre ou timestamp console (mesure du délai release)

**Préconditions** :
1. TC-AUD-05 exécuté avec succès (peak ducked confirmé)
2. Music stream en lecture continue
3. Enregistrement loopback actif pour analyse forme d'onde post-test

**Steps** :
1. Appeler : `AudioSystem.play_3d_at(clac_stream, Vector3.ZERO, &"combat_kill")` à t=0
2. À t≈20 ms : confirmer peak ducked (TC-AUD-05 — step de validation intermédiaire)
3. À t=240 ms : lire `AudioServer.get_bus_peak_volume_left_db(music_idx, 0)`
4. Comparer la valeur lue à -3 dB ± 1 (retour nominal attendu après release 200 ms)
5. Optionnel : analyser forme d'onde dans Audacity — vérifier courbe exponentielle visible (pas de retour linéaire, pas de plateau)

**Expected Result** :
- Peak à t=240 ms = **-3 dB ± 1** (retour au nominal après release `release_ms = 200.0`)
- Courbe de release exponentielle visible (τ ≈ 67 ms, 5τ ≈ 335 ms, 3τ ≈ 200 ms → ~95% release vers nominal)
- Valeur hors fenêtre [-4, -2] à t=240 ms = FAIL

**Actual Result** : _(peak mesuré à t=240 ms : ___ dB)_
**Pass/Fail** : _(à remplir post-playtest)_
**Sign-off** : sound-designer @TBD / date _(à remplir)_

---

### Test Case TC-AUD-07 — Multi-kill reset : re-duck sur 2e clac

**AC couverte** : AC-AUD-16 (c) — Multi-kill : 2e clac à t=50 ms re-duckle compressor depuis zéro
**Story** : story-012
**Type** : Manual playtest sound-designer
**Setup requis** :
- Même setup que TC-AUD-05
- Précision timing : utiliser script GDScript pour déclencher les 2 clacs à intervalles précis

**Préconditions** :
1. Music stream en lecture continue
2. Enregistrement loopback actif
3. Script debug prêt à exécuter 2 appels `play_3d_at` à t=0 et t=50 ms (un seul call `await get_tree().create_timer(0.050).timeout` entre les deux)

**Steps** :
1. Exécuter script : `AudioSystem.play_3d_at(clac, Vector3.ZERO, &"combat_kill")` à t=0
2. Attendre 50 ms (release partiellement avancé — peak vers -4 dB environ)
3. À t=50 ms : `AudioSystem.play_3d_at(clac, Vector3.ZERO, &"combat_kill")` (2e kill)
4. À t=70 ms (2e clac + 20 ms attack) : lire `get_bus_peak_volume_left_db(music_idx, 0)`
5. Comparer la valeur lue à -6 dB ± 1.5 (re-ducked depuis zéro, pas continuation release partielle)

**Expected Result** :
- Peak à t=70 ms = **-6 dB ± 1.5** (sidechain re-triggered, compressor repart depuis seuil plein)
- Si peak stagne à -3 dB (ou entre -4 et -3) = FAIL "sidechain re-trigger non fonctionnel sur 2e clac — vérifier `attack_us = 5000` config et que bus `combat_kill` reçoit le 2e signal"
- Valeur hors fenêtre [-7.5, -4.5] = FAIL

**Actual Result** : _(peak mesuré à t=70 ms : ___ dB)_
**Pass/Fail** : _(à remplir post-playtest)_
**Sign-off** : sound-designer @TBD / date _(à remplir)_

---

## Récapitulatif Session Playtest

| ID | AC | Groupe | Durée estimée | Résultat |
|----|----|--------|---------------|----------|
| TC-AUD-01 | AC-AUD-14 (a) | D-1 Panning | 15 min | _(à remplir)_ |
| TC-AUD-02 | AC-AUD-14 (b) | D-1 Distance | 10 min | _(à remplir)_ |
| TC-AUD-03 | AC-AUD-10 | D-2 Lint ADVISORY | 15 min | _(à remplir)_ |
| TC-AUD-04 | AC-AUD-13 (g) | D-3 CPU Profiler | 20 min | _(à remplir)_ |
| TC-AUD-05 | AC-AUD-16 (a) | D-4 Peak ducked | 10 min | _(à remplir)_ |
| TC-AUD-06 | AC-AUD-16 (b) | D-4 Release | 10 min | _(à remplir)_ |
| TC-AUD-07 | AC-AUD-16 (c) | D-4 Multi-kill | 10 min | _(à remplir)_ |

**Total** : 7 test cases — session estimée **~90 min** (setup inclus ~15 min)

**Verdict global session** : _(à remplir par sound-designer @TBD — date session)_

**Pitfalls à retenir avant la session** (documentés `audio-sidechain-music-2026-05-04.md`) :
- `get_bus_volume_db()` retourne le fader nominal, PAS le peak post-effects — toujours `get_bus_peak_volume_left_db()`
- `compressor.sidechain` est un String, pas un StringName — cast explicite requis
- `attack_us = 5000` = 5 ms (microsecondes, pas millisecondes)
- Driver Dummy headless : peak toujours ≤ -90 dB — les test cases D-4 requièrent un driver natif
