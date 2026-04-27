# ADR-0003: Rendering & Display Latency Strategy (tiered, Pillar 1 + Pillar 4)

*Note numérotation : initialement rédigée comme ADR-0002 ; renumérotée en ADR-0003 le 2026-04-21 pour préserver le slot ADR-0002 réservé à « Input API & Focus Handling » (review r4 input-system MAJOR REVISION NEEDED, ADR-first path acté par Martin).*

## Status
Accepted

## Date
2026-04-21 (Proposed) → 2026-04-21 (Accepted via fresh-session `/architecture-review` — 4 stale refs ADR-0002 nettoyées, cohérence engine Godot 4.6 confirmée, coverage TR-INP-001/002/003 + TR-GC-001/002 validée)

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Rendering |
| **Knowledge Risk** | HIGH (4.6 rendering backend defaults changed) |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/modules/rendering.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | D3D12 backend par défaut Windows (4.6), SMAA 1x (4.5+), Shader Baker (4.5+), Compositor (4.3+), glow pré-tonemapping (4.6) |
| **Verification Required** | (1) Confirmer les noms canoniques des ProjectSettings Shader Baker dans l'éditeur Godot 4.6 avant d'écrire les clés dans `project.godot` (cf. Note technique ci-dessous). (2) VSync mode switching via `DisplayServer.window_set_vsync_mode()` runtime sans restart. (3) Mesure E2E latency hardware→pixel en phase Polish (caméra haute vitesse). (4) Cold start < 3 s avec Shader Baker activé. (5) Fallback `screen_get_refresh_rate() == -1` → 60 Hz correctement implémenté. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (fixe le tick physics 60 Hz + budget frame 16.6 ms — cette ADR claim un slot rendering dans ce budget) |
| **Enables** | Implémentation Sprint 1 first story Movement (dépend d'une config render stable mesurable) ; Settings/Options menu UX spec (expose VSync mode + frame cap + AA toggles) ; test E2E latency en Polish |
| **Blocks** | UX spec Settings menu (attend ce ADR pour connaître la liste des toggles) ; mesure AC Pillar 1 FLOW end-to-end |
| **Ordering Note** | ADR-0001 doit être Accepted avant celui-ci, car le budget 16.6 ms total est sa création. Cet ADR s'inscrit dedans (rendering ≤ 8 ms). |

## Context

### Problem Statement

La cible de feel du projet (game-concept Pillar 1 « FLOW AVANT TOUT ») exige une latence input → réponse minimale ; la cible de performance (Pillar 4 « PERFORMANCE CONSTANTE ») exige un framerate stable et « vsync locked ». Ces deux cibles sont en **tension directe** : VSync on stabilise le framerate mais ajoute 8-32 ms de latence display (selon le refresh rate) ; VSync off minimise la latence mais introduit tearing et peut laisser le GPU spin (thermal throttle sur laptop entry-level). L'Input System GDD (ligne 373) recommande explicitement « 144 Hz VSync off ou G-Sync » pour satisfaire Pillar 1, et considère « VSync 60 Hz = Pillar 1 compromis assumé ». La tension n'est pas résolue.

Parallèlement, Godot 4.6 introduit plusieurs changements rendering post-LLM-cutoff qui impactent la stratégie :
- D3D12 est le backend par défaut sur Windows (au lieu de Vulkan), avec une meilleure compat drivers mais un comportement pas complètement stable sur tout le parc.
- SMAA 1x (4.5+) : nouvelle option AA plus nette que FXAA et moins coûteuse que TAA — pertinent pour un FPS fast-motion.
- Shader Baker (4.5+) : pré-compile les shaders à l'export → élimine le hitching cold start.
- Compositor (4.3+) : remplace les manual viewport chains pour post-processing.
- Glow avant tonemapping (4.6) : change visuel (non-latency).

L'ADR doit fixer une **baseline safe** (honore Pillar 4 « vsync locked ») et exposer un **opt-in low-latency** en Settings menu (honore Pillar 1), en tirant parti des features 4.5/4.6 pertinentes, et en excluant les patterns qui augmentent visiblement la latence (TAA ghosting).

### Constraints

- **ADR-0001 déjà acté** : budget frame 16.6 ms (target 60 fps PC), physics 4 ms stub → rendering claim ≤ 8 ms laisse ~4.6 ms Audio/IA/UI.
- **Platform target** (technical-preferences.md) : PC Windows primaire (Steam, itch.io), Linux secondaire. Entry-level gaming laptop (2 Go RAM / 1 Go VRAM). 60+ fps locked vsync baseline. 120+ fps desirable sur hardware moderne.
- **Pillar 1 FLOW** : latence input → réponse ≤ 1 frame. E2E cible ≤ 50 ms p99 (Input GDD ligne 269).
- **Pillar 4 PERFORMANCE CONSTANTE** : framerate stable, vsync locked, pas de jitter.
- **Renderer** (technical-preferences.md) : Forward+ (défaut Godot 4.6, best for PC desktop 3D).
- **Style visuel** (Chrome Zen, game-concept.md) : primitives + flat shaders → < 500 draw calls par frame (budget technical-preferences). Allège la charge GPU, ce qui rend le rendering budget ≤ 8 ms atteignable.
- **Aucun code dans `src/`** — greenfield.

### Requirements

- **REQ-1** : Baseline par défaut = framerate stable, honore Pillar 4 « vsync locked » et la config technical-preferences.md.
- **REQ-2** : Opt-in low-latency disponible en Settings menu MVP (VSync mode, frame cap, AA mode) — honore Pillar 1 pour joueurs sur hardware premium (144 Hz / G-Sync / FreeSync).
- **REQ-3** : Rendering budget ≤ 8 ms p99 sur entry-level laptop avec scène MVP (après physics 4 ms, reste pour Audio/IA/UI).
- **REQ-4** : Cold start < 3 s sans hitching shader compile visible (exploite Shader Baker 4.5+).
- **REQ-5** : Aucun post-processing qui cause ghosting sur fast motion (bannir TAA).
- **REQ-6** : E2E latency mesurable en Polish, p99 ≤ 50 ms default, ≤ 30 ms low-latency opt-in.
- **REQ-7** : Fallback robuste sur hardware dégradé (driver issue D3D12, laptop Optimus refresh rate -1, VRR faux-positif).

## Decision

Adopter une stratégie **tier + opt-in runtime** : baseline safe vsync-locked 60 fps, options menu MVP qui expose VSync mode / frame cap / AA pour low-latency opt-in. Exclusions fermes : TAA bannie, heavy post-processing hors-MVP, VRS off au MVP.

### Project Settings (project.godot)

```ini
[rendering]
renderer/rendering_method = "forward_plus"
anti_aliasing/quality/msaa_3d = 0
anti_aliasing/quality/screen_space_aa = 2    # SMAA 1x (Godot 4.5+)
anti_aliasing/quality/use_taa = false        # BANNIE — ghosting anti-Pillar-1
vrs/mode = 0                                 # VRS off (MVP)

[display]
window/vsync/vsync_mode = 1                  # Enabled (baseline safe)
```

> **Note technique** (godot-specialist) : Shader Baker (4.5+) doit être activé via l'éditeur. Les clés exactes de `project.godot` pour Shader Baker ne sont pas documentées dans `rendering.md` de notre engine-reference et ne sont pas écrites ici pour éviter d'hallucination. **Action pré-Sprint-1** : un dev active Shader Baker dans l'éditeur (Project Settings → Rendering → Shader Compiler — à confirmer), et commit les clés réelles dans un patch ADR-0003 Accepted. VC-2 vérifie l'effet (cold start < 3 s).

### Runtime Options (Settings menu MVP)

Le menu Settings (MVP obligatoire, cf. Input GDD overlay Controls pause menu r2) expose ces toggles, persistés dans `user://graphics_settings.tres` :

| Option | Valeurs | Default | Mapped vers |
|--------|---------|---------|-------------|
| VSync mode | Enabled / Disabled / Adaptive / Mailbox | Enabled | `DisplayServer.window_set_vsync_mode(mode)` — runtime switch, pas restart |
| Frame rate cap | 60 / 120 / 144 / Uncapped | 60 | `Engine.max_fps = cap` |
| Screen-space AA | SMAA 1x / FXAA / Off | SMAA 1x | `get_viewport().screen_space_aa = mode` |
| MSAA 3D | Off / 2x / 4x | Off | `get_viewport().msaa_3d = mode` |

**UI note** : le toggle « Uncapped » affiche un warning inline : « Peut causer thermal throttle sur laptop. Préférez Cap = 144 + VRR. »

### Auto-detect logic

Au lancement, `RenderingSettingsManager` autoload :
1. Lit `DisplayServer.screen_get_refresh_rate(get_window().current_screen)`.
2. Si valeur `> 0` et refresh natif ≥ 120 Hz : suggestion visible au premier lancement (one-shot popup) « Votre écran supporte 144 Hz. Activer low-latency opt-in ? » (mode Adaptive + Cap 144).
3. Si valeur `-1` (cas Optimus, Wayland, driver edge) : fallback silencieux sur 60 Hz baseline, log `push_warning("refresh_rate auto-detect failed, fallback 60 Hz")`.

### Patterns prescrits

- **Post-processing** : via Compositor (Godot 4.3+) uniquement. Aucun manual viewport chain. Au MVP : glow + tonemap (AgX) seuls. Bloom / DoF / motion-blur hors-MVP.
- **Shaders** : texture types `Texture` (pas `Texture2D`, changé 4.4).
- **SubViewport** (si introduit plus tard) : `render_target_update_mode = ALWAYS` explicite. Sinon défaut `ONCE` ajoute 1 frame de latence. (Cf. Control Manifest futur.)
- **Backend rendering switch** : launch-time uniquement via CLI `--rendering-driver vulkan|d3d12|opengl3`. Aucune API runtime (`DisplayServer.switch_backend()` n'existe pas). Si l'utilisateur change via UI, **restart requis** avec instructions.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ USER INPUT (OS polling 1-8 ms USB + 1-3 ms dispatch = 4-11 ms)      │
└───────────────────┬─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│ ENGINE (per ADR-0001)                                               │
│   _unhandled_input → flag → _physics_process mutation               │
│   Intra-engine p99 ≤ 16 ms                                          │
└───────────────────┬─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│ RENDERING (ce ADR, ≤ 8 ms budget)                                   │
│   Forward+ / D3D12 Windows / Vulkan Linux                           │
│   SMAA 1x, pas de TAA, glow + AgX tonemap seuls                     │
│   Compositor pour post, Shader Baker pour cold start                │
└───────────────────┬─────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│ DISPLAY (hardware + driver + VSync)                                 │
│                                                                     │
│   Default (baseline) : VSync on @ 60 fps → ~16-32 ms worst case     │
│   Opt-in : VSync Adaptive / off @ 144 fps → ~7-10 ms                │
│   Opt-in : VRR (G-Sync / FreeSync) @ native → ~8 ms                 │
└─────────────────────────────────────────────────────────────────────┘

E2E latency p99 attendu :
  Default : (11 OS) + (16 engine) + (8 render) + (16-32 display) = 51-67 ms  ⚠️ over 50
  Opt-in  : (11 OS) + (16 engine) + (8 render) + (7-10 display) = 42-45 ms   ✅ sous 50

Conclusion : la cible E2E ≤ 50 ms p99 Input GDD n'est atteignable qu'en opt-in.
Le default (Pillar 4 vsync-locked) est un compromis assumé, documenté dans Input GDD ligne 373.
```

### Key Interfaces

| Interface | Contrat |
|-----------|---------|
| `DisplayServer.window_set_vsync_mode(mode: int)` | 0=Disabled, 1=Enabled, 2=Adaptive, 3=Mailbox. Runtime switch, pas de restart. Adaptive/Mailbox fall back silencieusement sur Enabled si driver ne supporte pas. |
| `Engine.max_fps: int` | 0 = uncapped ; sinon cap (60/120/144). Modifiable runtime. |
| `get_viewport().screen_space_aa: int` / `msaa_3d: int` | Runtime AA switching. |
| `DisplayServer.screen_get_refresh_rate(screen: int) -> int` | Retourne Hz natif ou -1 si inconnu. Fallback 60 Hz obligatoire si -1. |
| `RenderingSettingsManager` (autoload) | Charge `user://graphics_settings.tres`, applique au boot, expose API `apply_settings(GraphicsSettings)` pour le menu. |
| CLI `--rendering-driver {vulkan\|d3d12\|opengl3}` | Launch-time backend override. Pas de hot-switch. |
| **Interdit** : TAA (`use_taa = true`) | Ghosting sur fast motion = anti-Pillar-1. Ban ferme au MVP. |
| **Interdit** : Manual viewport post-process chains | Utiliser Compositor (4.3+). |

## Alternatives Considered

### Alternative 1: 144 Hz VSync off + frame cap comme DEFAULT (pro-Pillar-1 agressif)

- **Description** : `vsync_mode = 0` (Disabled) + `Engine.max_fps = 144` par défaut. Aucune option « safe » au démarrage. Le joueur peut ré-activer VSync via Settings.
- **Pros** : latence display minimale out-of-the-box (~7 ms). Cible E2E ≤ 50 ms atteinte en default. Pillar 1 maximisé.
- **Cons** :
  - **Tearing visible** sur écrans non-VRR (la majorité des entry-level laptop n'ont pas de VRR).
  - **Désaligne technical-preferences.md** (« 60+ fps locked vsync » explicitement demandé).
  - **Désaligne game-concept.md Pillar 4** (« performances constantes, vsync locked »).
  - Thermal throttle risqué sur laptop faible si pas de frame cap effective sur hardware qui peut faire 300+ fps en menu.
  - Première impression potentiellement mauvaise (screen tearing visible dès le boot).
- **Rejection Reason** : Trade-off trop agressif vs baseline conservateur. Pillar 4 est un pillar au même titre que Pillar 1 — le tearing visible au boot dégrade l'expérience moyenne du joueur. Opt-in via Settings respecte les deux pillars.

### Alternative 2: 60 fps VSync on uniforme (no options menu)

- **Description** : `vsync_mode = 1` + cap 60 fps. Aucun toggle Settings menu. Le joueur ne peut pas aller au-delà.
- **Pros** : simplicité absolue. Aucun support player à gérer. Config 100 % prévisible, testable déterministiquement.
- **Cons** :
  - **Viole Pillar 1** pour joueurs sur hardware 144 Hz / G-Sync — ils paient ~16-32 ms de display pour rien.
  - Pas d'échappatoire à la tension Pillar 1 vs Pillar 4.
  - Input GDD ligne 373 recommande explicitement un opt-in 144 Hz / G-Sync → cet alternative contredirait la doc déjà actée.
- **Rejection Reason** : Pas d'échappatoire pour power users. L'overhead de dev du Settings menu est faible (4 toggles mappés à des APIs standards Godot).

### Alternative 3: G-Sync/FreeSync auto-detect + default Adaptive

- **Description** : Au premier lancement, détecter VRR capability via `DisplayServer.screen_get_refresh_rate()` + heuristique, et passer en `vsync_mode = 2` (Adaptive) par défaut si détecté.
- **Pros** : latence optimale sans intervention utilisateur sur hardware premium. Meilleure « default experience » pour joueurs bien équipés.
- **Cons** :
  - **Détection de VRR pas fiable** en Godot 4.6 (pas d'API `is_vrr_supported()` documentée). Heuristique basée sur refresh rate ≥ 120 Hz est imprécise.
  - **Cas laptop Optimus** : `screen_get_refresh_rate()` peut retourner le rate de l'écran interne même si un moniteur externe VRR est branché.
  - **Adaptive sans VRR driver** : fall back silencieux sur Enabled — l'utilisateur ne sait pas quel mode est réellement actif.
  - Complexifie le boot pour un gain marginal vs le suggestion popup proposé (Décision).
- **Rejection Reason** : Trop fragile sans API fiable pour VRR detection. La Décision adopte une variante plus conservatrice : popup de suggestion au premier lancement si refresh ≥ 120 Hz, sans auto-apply.

## Consequences

### Positive

- **Pillar 1 + Pillar 4 conciliés** : baseline safe vsync-locked pour majorité ; opt-in low-latency pour joueurs compétitifs.
- **Aligne technical-preferences.md + game-concept.md** : « 60+ fps locked vsync » respecté en default.
- **E2E latency ≤ 50 ms atteignable** en opt-in, documenté dans l'Input GDD.
- **Cold start propre** grâce à Shader Baker 4.5+ (VC-2).
- **TAA banni** : pas de ghosting sur dash/wall-run — critique pour Pillar 1 feel.
- **SMAA 1x nouveau 4.5** : AA sharp + cheap — exploite bien Godot 4.6.
- **D3D12 default 4.6** : meilleure compat drivers Windows.

### Negative

- **Complexité Settings menu** : 4 toggles mappés à 4 APIs runtime. Tests QA multipliés par 4 (combinaisons à couvrir).
- **Support cases** : joueur qui active « Uncapped » sur laptop entry-level = hausse thermique. Warning UI nécessaire.
- **Default E2E ~51-67 ms** au-dessus de la cible 50 ms — compromis assumé. Cible 50 ms documentée comme **opt-in only**, pas default.
- **Pas de runtime backend switch** : si D3D12 plante, restart requis avec CLI `--rendering-driver vulkan`. Mauvaise UX sur first-time issues.

### Risks

- **Risk 1 — D3D12 driver issue sur parc Windows** : D3D12 default 4.6 peut crasher sur certains GPU/driver combos. → Mitigation : launcher option « Use Vulkan backend » (passe `--rendering-driver vulkan` au process Godot). Documenter dans README / troubleshooting guide. Steam config peut aussi passer l'argument.
- **Risk 2 — Shader Baker cache incompat cross-update** : après un patch Godot ou un rebuild de shaders, le cache est invalidé → cold start long (recompilation visible). → Mitigation : communiqué lors de patches majeurs (« Premier lancement peut prendre 30 s »). Cache stocké `user://shader_cache/`, reconstruit silencieusement.
- **Risk 3 — G-Sync/FreeSync flaky sur laptop Optimus** : `vsync_mode = 2` (Adaptive) fall back silencieusement sur Enabled sur driver hybride. → Mitigation : indicateur runtime dans HUD debug F3 (mode VSync effectif mesuré via framerate pattern). Settings menu affiche « Mode actuel : Adaptive (fallback Enabled) » si fallback détecté (heuristique variance frame time).
- **Risk 4 — User « Uncapped » + thermal throttle** : GPU tourne 300+ fps en menu/scène simple → chauffe → throttle → stutter en gameplay. → Mitigation : default cap = 60 ; option Uncapped affiche warning ; cap forcé à 144 en menu pause / inactif (économie énergie).
- **Risk 5 — `screen_get_refresh_rate() == -1`** : cas Optimus / Wayland / Steam Deck edge. → Mitigation : fallback déterministe 60 Hz + log `push_warning`. Le VC-3 couvre ce cas edge.
- **Risk 6 — Shader Baker properties mal configurées** : les noms de clés utilisés dans cet ADR sont conservateurs (on ne hallucine pas les noms). Un dev doit activer Shader Baker via l'éditeur avant Sprint 1 et commit les clés réelles. → Mitigation : VC-2 mesure l'effet (cold start < 3 s), peu importe les clés exactes.
- **Risk 7 — SubViewport ajouté plus tard avec default `ONCE`** : scope creep (minimap, UI worldspace) ajoute 1 frame de latency invisible. → Mitigation : entrée Control Manifest futur « Tout SubViewport doit déclarer `render_target_update_mode` explicitement ». Noté pour inclusion quand `/create-control-manifest` sera lancé.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `design/gdd/input-system.md` (ligne 266) | « Cible ≤ 16 ms p99 **intra-engine** » | Inchangé — cet ADR s'occupe du reste de la chaîne (render + display) pour atteindre E2E ≤ 50 ms. |
| `design/gdd/input-system.md` (ligne 269, 374) | « Total perçu joueur p99 ~25-50 ms » + « cible end-to-end ≤ 50 ms p99 » | Décomposition E2E budgétée explicitement dans Decision → Architecture Diagram. Atteinte conditionnelle (low-latency opt-in). |
| `design/gdd/input-system.md` (ligne 373) | « Recommandation Pillar 1 : 144 Hz VSync off ou G-Sync. VSync 60 Hz = Pillar 1 compromis assumé » | Adopté intégralement : default = compromis assumé Pillar 4, opt-in = Pillar 1 aggressif via VSync off / Adaptive / Mailbox. |
| `design/gdd/input-system.md` (ligne 517, Open Question) | « ADR à créer (adr-rendering-latency.md) coordonné avec Input System » | **CET ADR (ADR-0003) résout cette Open Question.** |
| `design/gdd/game-concept.md` Pillar 1 FLOW | Latence input → réponse ≤ 1 frame | Opt-in VSync off / VRR + cap 144 atteint ~7-10 ms display = ≤ 1 frame de 144 Hz render. |
| `design/gdd/game-concept.md` Pillar 4 PERFORMANCE | « Performances constantes, vsync locked » | Default vsync-locked 60 fps — baseline honoré. |
| `design/gdd/game-concept.md` (ligne 218) | « Performances constantes (vsync locked) » Key Technical Challenges | Default respecte. Opt-in documenté comme opt-in, pas default. |
| `design/gdd/player-movement-system.md` AC Latency | « P99 de (timestamp velocity-set - timestamp input event) ≤ 16 ms » | Inchangé — intra-engine, indépendant de cet ADR. Cet ADR rend la mesure E2E (key → pixel) faisable en Polish. |
| `design/gdd/camera-system.md` | Caméra en `_process` @ 60+ fps | Compatible — default 60 fps, opt-in 144 fps respecte autorité `_process` cosmetic only (ADR-0001). |
| `technical-preferences.md` | Forward+, 60+ fps locked vsync baseline, 120+ fps desirable, draw calls < 500/frame, 16.6 ms budget | Forward+ = décision. 60 fps vsync baseline = default. 120+ fps = opt-in explicite. Chrome Zen style soutient budget draw calls. Rendering ≤ 8 ms respecte 16.6 ms total. |

## Performance Implications

- **CPU** :
  - Forward+ baseline : scène MVP estimée ~1-2 ms CPU render loop.
  - SMAA 1x : ~0.3 ms fullscreen. FXAA : ~0.15 ms. TAA évité (~0.5 ms + ghosting).
  - Compositor : négligeable au MVP (glow + tonemap seuls).
  - Total CPU render estimé : ~2-3 ms / 8 ms budget → large marge.
- **GPU** :
  - Chrome Zen flat shaders + primitives + < 500 draw calls → GPU utilisation faible sur integrated GPU entry-level.
  - Shader Baker élimine hitching cold start (~500-2000 ms économisés first load).
  - Forward+ + D3D12 sur Windows : meilleur throughput que Vulkan+Forward sur certains drivers 4.6.
- **Memory** :
  - Compositor resources : négligeable.
  - Shader cache `user://shader_cache/` : ~50-200 MB selon parc shaders MVP.
- **Load Time** :
  - **Cold start** (post-install) : 5-30 s avec Shader Baker compile shaders first launch. Communiqué.
  - **Warm start** (shader cache valide) : < 3 s (VC-2).
  - Level load : dépend du level-system (hors scope).
- **Network** : N/A (jeu solo MVP).

**Performance budget claim (registry)** :
```
- system: rendering
  budget_ms: 8.0
  platform: PC entry-level laptop
```

## Migration Plan

- **Aucun code dans `src/`** — greenfield.
- **Pré-Sprint-1 tasks** :
  1. Dev activateur Shader Baker dans l'éditeur Godot, commit clés réelles dans `project.godot` (patch ADR-0003 pour documentation).
  2. Implémenter `RenderingSettingsManager` autoload + resource `GraphicsSettings.tres`.
  3. Implémenter Settings menu MVP (4 toggles VSync/Cap/AA/MSAA).
  4. Documenter launcher CLI `--rendering-driver vulkan` fallback dans troubleshooting README.
- **Prototype `prototypes/movement-katana/`** : pas impacté directement (prototype n'a pas de Settings menu). Les mesures de feel du prototype restent valides.
- **GDD updates** : marquer Open Questions lignes 517-518 du Input GDD comme **RÉSOLUES** avec référence ADR-0003 / ADR-0001.
- **Registry updates** : 5 entrées (2 api_decisions, 2 forbidden_patterns, 1 performance_budgets).

## Validation Criteria

- **VC-1 (Rendering frame budget)** : test perf `tests/performance/rendering_frame_budget_test.gd`. GIVEN scène MVP + 10 ennemis + VFX minimal. WHEN 60 s de gameplay. THEN `Performance.get_monitor(Performance.TIME_PROCESS)` rendering portion ≤ 8 ms p99 sur référence hardware entry-level laptop. **Note** : décomposer la mesure via `Performance.TIME_PROCESS` total moins physics reported, ou via debug profiler.
- **VC-2 (Cold start avec Shader Baker)** : protocole QA manuel. GIVEN build release, fresh install (pas de `user://shader_cache/`). WHEN lancement premier run. THEN temps titre → menu jouable ≤ 30 s premier lancement, < 3 s subséquents. Zero hitching visible en gameplay post-boot.
- **VC-3 (VSync runtime switch)** : test GUT `tests/integration/rendering_settings_test.gd`. GIVEN scène test. WHEN `DisplayServer.window_set_vsync_mode(0)` puis `(1)`. THEN aucun restart requis, framerate pattern observable change (uncapped vs capped monitor refresh). Measure via `Engine.get_frames_drawn()` delta sur 1 s.
- **VC-4 (No TAA ghosting)** : protocole QA manuel + screenshot compare. GIVEN scène avec texture contrastée. WHEN translate caméra à 5 m/s horizontal. THEN screenshot à t=0.1 s et t=0.2 s montre trail ghost < 1 pixel (SMAA 1x) vs > 3 pixels si TAA activé. Evidence : `production/qa/evidence/rendering-aa-compare-[date]/`.
- **VC-5 (E2E latency, Polish phase)** : protocole externe, caméra haute vitesse (240 fps) ou LED-based input timing. GIVEN setup hardware mesure (Steam Hardware Survey-style). WHEN 50 appuis `jump` key. THEN p99 `key_down_hardware` → `first_pixel_change_on_screen` ≤ 50 ms default VSync on 60 fps, ≤ 30 ms low-latency opt-in (VSync off + 144 Hz + G-Sync). Hors scope MVP, à exécuter en Polish.
- **VC-6 (Refresh rate fallback)** : test GUT. GIVEN mock `DisplayServer.screen_get_refresh_rate` returns `-1`. WHEN `RenderingSettingsManager` boot. THEN default cap = 60 appliqué, `push_warning` émis.
- **VC-7 (D3D12 → Vulkan fallback launcher)** : protocole QA manuel. GIVEN build release. WHEN lancement avec CLI `--rendering-driver vulkan`. THEN backend effectif == Vulkan (visible via `RenderingServer.get_video_adapter_driver_info()` ou équivalent). Screenshot menu + 30 s gameplay sans crash.

Si une des VCs échoue, l'ADR est re-ouvert (pas auto-superseded — ajustements possibles). VC-5 est la seule validation cross-cutting critique pour prouver Pillar 1 réalité vs théorie.

## Related Decisions

- **ADR-0001** (`docs/architecture/adr-0001-physics-rate-60hz.md`) : fixe physics 60 Hz + budget frame 16.6 ms — cet ADR s'y inscrit (rendering ≤ 8 ms claim).
- **design/gdd/input-system.md** : ligne 373 (décomposition E2E) et ligne 517 (Open Question) — **résolue par cet ADR**.
- **design/gdd/game-concept.md** : Pillar 1 FLOW + Pillar 4 PERFORMANCE — concilié via tier default/opt-in.
- **technical-preferences.md** : Forward+ + vsync baseline — respecté.
- **ADR-0004** (`docs/architecture/adr-0004-input-api-focus-handling.md`) — « Input API & Focus Handling ». Scope : `was_pressed_this_tick()` API canonique, reset sync dans `_physics_process`, `request_disable/enable(owner)` refcount pattern, `application_focus_lost` signal, ring buffer pré-alloué PackedFloat32Array, focus cross-OS Wayland/Windows/macOS. Status Proposed au 2026-04-21. Coexiste avec cet ADR sans conflit (domaines disjoints : Input vs Rendering).
- **Futur Control Manifest** (via `/create-control-manifest` post-ADRs) : inclure « Tout SubViewport déclare `render_target_update_mode` explicitement » + « Backend rendering launch-time only, pas de hot-switch » + « TAA et manual viewport chains forbidden ».
- **Futur UX Settings spec** : run `/ux-design settings-menu-graphics` après cet ADR Accepted — 4 toggles + tooltips + warning Uncapped + popup first-launch 120 Hz suggestion.

---

*Auteur : Architecture Decision skill, 2026-04-21*
*Validation engine : `godot-specialist` — verdict MINOR NOTES (4 corrections intégrées : Shader Baker clés conservateur, fallback D3D12→Vulkan launch-time only, refresh_rate -1 fallback, SubViewport update_mode pour Control Manifest).*
*Mode review : solo (TD-ADR gate skipped)*
