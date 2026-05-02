# ADR-0002: Camera Scene Tree — CameraArm Intermédiaire

## Status

Accepted

## Date

2026-04-21 (Proposed) → 2026-04-21 (Accepted via fresh-session `/architecture-review single-gdd camera` — verdict PASS sur périmètre ADR : couverture TR-cam-001/002/005 + TR-mov-004 validée, cohérence ADR-0001/0003/0004 confirmée, engine-compat Godot 4.6 clean LOW risk. 4 incohérences Camera GDD détectées (F-1 signal name, F-2 stale `camera.rotation.*` refs massifs, F-3 Open Question #17 stale, F-4 timing 200 vs 250 ms) sont GDD-side, non bloquantes pour Accept ADR — à traiter via `/consistency-check` avant first Camera story Sprint 1.) → 2026-04-23 (Amendment A-1 — voir Amendment History).

## Last Verified

2026-04-23

## Amendment History

### A-1 — 2026-04-23 — Signal-driven consumption of Movement state transitions

**Scope** : aligner Key Interfaces sur ADR-0005 (Movement Signals Architecture, Accepted 2026-04-21 après cet ADR). Le draft initial de Key Interfaces prescrivait du polling (`player.state == WALL_RUNNING`, `player.is_dashing`) pour piloter tilt et FOV. ADR-0005 a depuis figé la convention canonique : Camera **consomme les transitions Movement via signaux typés directs** (`wall_run_entered` / `wall_run_exited` / `dash_started` / `dash_ended` / `died` / `respawned`), jamais par polling d'état. Le pattern signal-driven est déjà reflété dans le registry (`docs/registry/architecture.yaml` l.51 state ownership read-only + l.167 8 signaux Movement + l.423 convention sync vs deferred + l.527 emit-only-from-\_physics\_process).

**Changes** :
- Section **ADR Dependencies** : ajout `ADR-0005` en `Depends On`.
- Section **Decision → Key Interfaces** : tilt wall-run + FOV dash migrés de polling vers cache-via-signal (flags privés `_is_wall_running`, `_wall_side_cached`, `_is_dashing` mutés dans handlers `_on_wall_run_entered/_exited/_dash_started/_dash_ended`). `aim_forward` inchangé (toujours forme close trigonométrique).
- Section **Decision → Implementation Guidelines** : ajout règle explicite « Camera ne polle JAMAIS les transitions d'état Movement ».
- Section **Validation Criteria** : ajout VC-7 (grep CI `player.state ==` interdit dans `src/gameplay/camera/`) + VC-8 (les 6 handlers signaux Movement sont connectés au `_ready` de Camera System).
- Section **GDD Requirements Addressed** : ajout ligne Camera GDD « consomme signaux Movement pour wall-run tilt et dash FOV kick ».
- Registry : ajout forbidden_pattern `camera_polls_movement_state_transitions` référencé par cet ADR + ADR-0005.

**Hiérarchie scene tree, formule `aim_forward`, répartition pitch/tilt/fov/shake, Performance budget, Rollback plan : INCHANGÉS.**

**Reason** : sans cette amendment, la 1ère story Camera Sprint 1 embarque un pattern (polling) qui viole une ADR postérieure (ADR-0005) — traçabilité cassée, review future bloquante. Amendment chirurgicale, scope isolé, zéro impact sur VCs 1–6 et sur les formules clés.

## Decision Makers

Martin (creative authority), creative-director (synthèse design-review camera-system r1), godot-specialist + gameplay-programmer (recommandation technique convergente).

## Summary

Le Camera System de CHROME://ASCENT utilisera la hiérarchie **à trois étages** `CharacterBody3D → CameraArm: Node3D → CameraEffects: Node3D → Camera3D → AudioListener3D` plutôt que `CharacterBody3D → Camera3D` direct. Le CameraArm porte le pitch (rotation X) et les offsets locaux (head-bob futur) ; le CameraEffects porte le tilt wall-run (rotation Z) ; la Camera3D ne porte que le FOV et le shake additif, avec l'AudioListener3D enfant. Cette séparation en trois noeuds découple les transformations visuelles d'état de la matrice de projection, évite les conflits Tween entre head-bob et tilt (qui partageraient sinon le même nœud), et résout un conflit cross-doc préexistant entre le Player Movement GDD (qui assumait CameraArm) et la version r1 du Camera GDD (qui assumait Camera3D direct).

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Scripting / Scene composition |
| **Knowledge Risk** | LOW |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/current-best-practices.md`, `design/gdd/camera-system.md` (r1), `design/gdd/player-movement-system.md` |
| **Post-Cutoff APIs Used** | None — Node3D + Camera3D + rotation Euler YXZ stables depuis 4.0 |
| **Verification Required** | (1) Vérifier qu'un `Camera3D` enfant d'un `Node3D` lui-même enfant d'un `CharacterBody3D` rend correctement la projection à fov dynamique sur Forward+ + Jolt. (2) Vérifier que `AudioListener3D` enfant de `Camera3D` reste actif sans `make_current()` explicite quand la scène ne contient qu'un seul listener. |

> **Note** : Knowledge Risk LOW — patterns fondamentaux Godot inchangés entre 4.3 et 4.6. Pas besoin de re-validation à upgrade engine.

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | **ADR-0005** (ajouté par Amendment A-1 2026-04-23) — Camera consomme les 8 signaux typés Movement (`wall_run_entered/exited`, `dash_started/ended`, `died/respawned`) pour piloter tilt + FOV + overlays ; contrat signal doit être Accepted avant que Camera puisse se connecter. ADR-0005 Accepted 2026-04-21 — contrainte satisfaite a posteriori. |
| **Enables** | Player Combat System (peut consommer `aim_forward` roll-corrigé sans race condition) ; VFX & Feedback System (peut composer shake additif sans muter pitch/tilt) ; Accessibility System (toggle reduce_motion peut moduler tilt sur CameraArm sans toucher Camera3D) |
| **Blocks** | Story Camera System Sprint 1 (ne peut pas démarrer sans tree formel ni contrat signal-driven) |
| **Ordering Note** | Cet ADR doit être Accepted avant la première story Camera ou Combat. Pas bloquant pour Movement (Movement GDD assume déjà CameraArm via sa table Interactions). Depuis Amendment A-1 : ADR-0005 doit l'être aussi — OK (Accepted 2026-04-21). |

## Context

### Problem Statement

Deux GDDs Sprint 1 portent des hiérarchies scene tree contradictoires pour le couple Player+Camera :

- **Player Movement GDD** (Interactions table) : `CharacterBody3D (rotation Y) → CameraArm: Node3D (rotation X) → Camera3D`. Tilt wall-run appliqué sur `CameraArm.rotation.z`.
- **Camera System GDD r1** (Rule 1) : `Camera3D` enfant direct de `CharacterBody3D`. Pitch sur `camera.rotation.x`, tilt sur `camera.rotation.z`.

Tant que ce conflit n'est pas tranché formellement, toute story Camera embarquera une hypothèse fausse au moins sur l'un des deux GDDs. Toutes les formules Camera référençant `camera.rotation.x` ou `camera.rotation.z` cibleraient le mauvais noeud si le pattern Movement gagne sans correction. Le pattern direct gagne plus de simplicité mais oblige Camera à corriger à la main les compositions d'effets (cf. Formula 5 `aim_forward` r1 qui nécessite une décomposition Basis sujette à erreur algébrique).

### Current State

Aucun code dans `src/`. Le prototype `prototypes/movement-katana/` (statut à confirmer) implémente vraisemblablement un pattern direct (Camera3D enfant Player). Les deux GDDs sont en review, le moment est idéal pour figer.

### Constraints

- **Engine** : Godot 4.6 + Jolt + Forward+. Les rotations Euler YXZ sont la convention par défaut sur Camera3D.
- **Pillar 1 (FLOW AVANT TOUT)** : aucun coût CPU rédhibitoire. Un Node3D intermédiaire = ~zéro coût (pas de rendu, pas de physique, juste une transform supplémentaire dans la hiérarchie — calcul de matrice trivial, mis en cache par Godot).
- **Solo dev** : la complexité d'architecture doit rester gérable. Le pattern doit être expressible en une phrase.
- **Conflit cross-doc à résoudre** : la décision doit unifier Movement + Camera et leur registry partagé.

### Requirements

- **REQ-1** : Pitch (regard vertical via souris) doit être appliqué à un noeud distinct du body Player pour que le forward du Player (utilisé par Movement pour `wish_dir`) ne soit pas affecté par le pitch.
- **REQ-2** : Tilt wall-run (roll Z) doit être appliqué sans déformer la matrice de projection de la Camera3D (qui doit rester orientée pour rendre correctement le FOV pulse dash).
- **REQ-3** : `aim_forward` (vecteur de direction katana) doit être calculable sans manipulation Basis manuelle sujette à erreur (cf. Formula 5 r1, algébriquement incorrecte).
- **REQ-4** : Le shake additif (kick wall-jump, futurs hits katana) doit pouvoir s'ajouter à la rotation finale sans interférer avec le tilt ou le pitch propres.
- **REQ-5** : `AudioListener3D` doit rester en convention Godot (enfant de Camera3D, auto-actif si single listener).

## Decision

Adopter la hiérarchie à trois étages **`CharacterBody3D → CameraArm: Node3D → CameraEffects: Node3D → Camera3D → AudioListener3D`**.

### Architecture

```
CharacterBody3D (Player)              # rotation.y = yaw (mouvement souris X)
└── CameraArm: Node3D                  # rotation.x = pitch (mouvement souris Y, clampé)
                                       # position.y = head-bob vertical (Tier 2 — OFF au MVP)
    └── CameraEffects: Node3D          # rotation.z = tilt (wall-run, lerp vers WALL_RUN_TILT_ANGLE * wall_side)
                                       # dédié aux effets composables qui ne doivent pas interférer
                                       # avec pitch ni head-bob (évite conflits Tween/lerp même-propriété)
        └── Camera3D                   # fov = lerp(BASE_FOV, BASE_FOV + DASH_FOV_KICK, ...)
                                       # rotation = identity en steady-state
                                       # rotation += shake_offset (additif final, decay exp)
            └── AudioListener3D        # auto-current (single listener)
```

### Key Interfaces

> **Amendment A-1 (2026-04-23)** : la consommation d'état Movement est **signal-driven**, pas polling. Camera n'évalue JAMAIS `player.state == X` ni `player.is_dashing` dans `_process` / `_physics_process`. Elle cache l'état courant via handlers connectés aux signaux ADR-0005 et lit ses propres flags privés. Voir Implementation Guidelines ci-dessous pour les garde-fous et VC-7/VC-8 pour la validation CI.

```gdscript
# Sur le script de Camera System (attaché à CameraArm, pilote CameraArm + CameraEffects + Camera3D)

# --- Cache signal-driven Movement state (ADR-0005 consumption) ---
var _is_wall_running: bool = false
var _wall_side_cached: int = 0          # -1, 0, +1 — frozen à wall_run_entered
var _is_dashing: bool = false

func _ready() -> void:
    # Connexion sync (light handlers : toggle bool + cache Vector3.dot — pas d'alloc, < 0.01 ms)
    # ADR-0005 D-4 critère : sync OK car aucune instanciation Node, aucun AudioStream.play.
    player.wall_run_entered.connect(_on_wall_run_entered)
    player.wall_run_exited.connect(_on_wall_run_exited)
    player.dash_started.connect(_on_dash_started)
    player.dash_ended.connect(_on_dash_ended)
    player.died.connect(_on_died)
    player.respawned.connect(_on_respawned)

func _on_wall_run_entered(wall_normal: Vector3) -> void:
    # wall_side calculé UNE FOIS à l'entrée (wall_normal frozen par le payload signal).
    # Réévaluer chaque frame serait du polling déguisé + inutile (le mur ne bouge pas).
    _is_wall_running = true
    _wall_side_cached = sign(wall_normal.dot(-camera_arm.global_transform.basis.x))

func _on_wall_run_exited() -> void:
    _is_wall_running = false
    _wall_side_cached = 0

func _on_dash_started(_dash_dir: Vector3, _dash_speed: float) -> void:
    _is_dashing = true

func _on_dash_ended() -> void:
    _is_dashing = false

# --- Mutations visuelles ---

# Mutation pitch (signal mouse_motion InputManager — ADR-0004 D-4) :
# Handler _on_mouse_motion(delta: Vector2) appelé depuis _physics_process indirect via polling buffer.
camera_arm.rotation.x = clamp(camera_arm.rotation.x + pitch_delta, -PITCH_LIMIT, PITCH_LIMIT)

# Mutation tilt (chaque _process) — lit flags cachés, PAS player.state :
var target_roll: float = WALL_RUN_TILT_ANGLE * _wall_side_cached if _is_wall_running else 0.0
camera_effects.rotation.z = lerp(camera_effects.rotation.z, target_roll, min(TILT_LERP_SPEED * delta, 1.0))

# Mutation FOV (chaque _process) — lit flag caché, PAS player.is_dashing :
var target_fov: float = BASE_FOV + (DASH_FOV_KICK if _is_dashing else 0.0)
camera3d.fov = lerp(camera3d.fov, target_fov, min(DASH_FOV_LERP_SPEED * delta, 1.0))

# Shake additif appliqué sur Camera3D rotation finale :
shake_offset *= exp(-SHAKE_DECAY * delta)
shake_offset = shake_offset.limit_length(MAX_SHAKE_MAGNITUDE)
camera3d.rotation = shake_offset  # rotation locale par-dessus la transform du CameraArm

# aim_forward (forme close, pas de manipulation Basis, ignore tilt par construction) :
var yaw: float = player.rotation.y
var pitch: float = camera_arm.rotation.x
# Note : le tilt vit sur camera_effects.rotation.z ; il n'entre PAS dans aim_forward
# (la hitbox katana doit rester horizontalement stable même en wall-run).
aim_forward = Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
```

**Lecture read-only autorisée** : Camera peut lire `player.rotation.y` (yaw — utilisé par `aim_forward`), `player.global_position` (future orbit cam death, Tier 2), `player.wall_normal` **uniquement via payload `wall_run_entered`** (pas via polling getter). Toute autre lecture de `player.*` est interdite par garde-fou ci-dessous.

### Implementation Guidelines

- **CameraArm position locale** : à la hauteur des yeux du Player (par exemple `Vector3(0, 1.6, 0)` pour un body 1.8 m). Réglable via `camera_tuning.tres`.
- **CameraEffects position locale** : `Vector3.ZERO` (empilé sur CameraArm).
- **Camera3D position locale** : `Vector3.ZERO` (la chaîne CameraArm→CameraEffects la place déjà aux yeux).
- **Yaw** : reste mutated par Camera System mais sur `player.rotation.y` (le body), PAS sur CameraArm. Le body pivote, CameraArm hérite.
- **Pitch** : mutated par Camera System sur `camera_arm.rotation.x` exclusivement. Clamp `[-PITCH_LIMIT, +PITCH_LIMIT]` chaque frame.
- **Tilt (roll)** : mutated par Camera System sur `camera_effects.rotation.z` exclusivement — **jamais sur CameraArm ni Camera3D**. Cette séparation isole le tilt wall-run du head-bob futur (qui sera sur `camera_arm.position.y`) et du shake (qui sera sur `camera3d.rotation`) → zéro conflit Tween/lerp même-propriété.
- **Shake** : mutated par Camera System sur `camera3d.rotation` (Vector3 cumulant pitch/yaw/roll offsets temporaires). Décroissance exponentielle vers `Vector3.ZERO`.
- **FOV** : mutated par Camera System sur `camera3d.fov` (BASE_FOV + DASH_FOV_KICK lerp).
- **Head-bob (Tier 2, OFF au MVP)** : si ré-introduit, sur `camera_arm.position.y` exclusivement — pas sur rotation.
- **Pas de mutation simultanée** sur le même noeud par deux systèmes — Movement n'écrit jamais sur CameraArm, CameraEffects ni Camera3D ; Camera n'écrit jamais sur Player sauf `rotation.y`.
- **Consommation Movement signal-driven (Amendment A-1, renvoi ADR-0005)** : Camera infère les transitions d'état Movement UNIQUEMENT via les 8 signaux typés (`wall_run_entered`, `wall_run_exited`, `dash_started`, `dash_ended`, `died`, `respawned`, + `wall_jumped` et `attacked` si pertinent pour un effet visuel futur). **Interdiction stricte** de polling dans `_process` ou `_physics_process` Camera : pas de `if player.state == WALL_RUNNING:`, pas de `if player.is_dashing:`, pas de `if player.state == DEAD:`. Le pattern est : handler `_on_X()` → mutation d'un flag privé Camera (`_is_wall_running`, `_is_dashing`, etc.) → lecture du flag privé dans le lerp `_process`. Raison : (a) cohérence avec ADR-0005 D-2 typed signals canoniques ; (b) évite un couplage déguisé au enum interne `State` de MovementController (qui peut évoluer sans casser Camera) ; (c) zéro coût polling par frame (flag local = 1 load bool).
- **Handlers signaux Movement = sync connection** (pas `CONNECT_DEFERRED`). Raison ADR-0005 D-4 critère (a)(b)(c)(d) : toggle bool + cache Vector3.dot = light (no alloc, no Node instantiation, < 0.5 ms, no AudioStream.play). FOV kick et tilt doivent réagir dans le même tick que la transition pour que le player perçoive le feedback comme synchrone à son input — CONNECT_DEFERRED ajouterait 1 frame de retard visuel perceptible.

## Alternatives Considered

### Alternative 1 : Camera3D enfant direct de CharacterBody3D (ce que faisait Camera GDD r1)

- **Description** : `CharacterBody3D → Camera3D`. Pitch + tilt + shake + fov tous appliqués sur Camera3D directement.
- **Pros** : Hiérarchie minimale, un noeud de moins, moins de wiring scene.
- **Cons** : (a) Composition pitch + tilt + shake sur le même noeud pose un problème d'ordre Euler (YXZ Godot par défaut) — le shake additif rotationnel peut produire des artefacts gimbal si combiné à un tilt fort + pitch fort ; (b) `aim_forward` doit reconstruire une basis sans roll à la main — la formule r1 (`Basis(UP, -roll) * basis_globale`) est algébriquement incorrecte selon analyse systems-designer ; (c) Movement GDD recommandait déjà CameraArm — adopter Camera3D direct créerait une dette de cohérence à corriger ailleurs.
- **Estimated Effort** : Identique à l'alternative retenue côté implémentation initiale, mais coût caché en debug et en composabilité future (head-bob, recoil, etc.).
- **Rejection Reason** : L'erreur algébrique de Formula 5 r1 démontre que la composition manuelle est fragile. Le coût d'un Node3D supplémentaire est nul. Le pattern CameraArm est l'idiom Godot standard pour les FPS.

### Alternative 2 : SpringArm3D + Camera3D (3rd-person camera arm)

- **Description** : `CharacterBody3D → SpringArm3D → Camera3D`. SpringArm3D gère collision avec le monde et offset.
- **Pros** : Utile pour vues 3rd-person avec collision.
- **Cons** : SpringArm3D applique un offset négatif local (recule la caméra), ajoute logique collision inutile pour FPS.
- **Estimated Effort** : Plus de code à désactiver qu'à activer.
- **Rejection Reason** : CHROME://ASCENT est strictement FPS. SpringArm3D est sur-dimensionné.

### Alternative 3 : Trois noeuds dédiés (PitchPivot, TiltPivot, Camera3D)

- **Description** : `CharacterBody3D → PitchPivot: Node3D (rotation.x) → TiltPivot: Node3D (rotation.z) → Camera3D`. Sépare pitch et tilt sur deux noeuds distincts.
- **Pros** : Découplage pitch/tilt total, encore plus de clarté.
- **Cons** : Un noeud supplémentaire pour bénéfice marginal. Le pattern CameraArm avec rotation.x ET rotation.z sur le même Node3D fonctionne (Godot applique la rotation Euler YXZ propre).
- **Rejection Reason** : Sur-engineering. CameraArm seul suffit.

## Consequences

### Positive

- **Conflit cross-doc Movement ↔ Camera résolu**. Une seule source de vérité.
- **Formula 5 (`aim_forward`) simplifiée** : forme trigonométrique close, pas de manipulation Basis sujette à erreur. AC vérifiable analytiquement.
- **Composabilité future** : ajout d'un head-bob (par exemple sur un bob_offset Vector3 appliqué à CameraArm.position locale) ne touche pas la rotation. Recoil katana future = additif sur shake_offset Camera3D, isolé du tilt.
- **Pillar 1 préservé** : aucun coût CPU mesurable (transform Node3D = quelques multiplications float, mis en cache par Godot scene graph).
- **Audio convention Godot respectée** : AudioListener3D enfant de Camera3D, auto-current sans `make_current()` requis pour le solo player.

### Negative

- **Camera System doit muter trois noeuds différents** (CameraArm pour pitch+tilt, Camera3D pour fov+shake, Player pour yaw). Plus de surface API interne. Mitigé par : la mutation est centralisée dans un script unique, les noeuds sont children directs.
- **Ressource scene complexité +1 noeud** : impact mémoire ~64 octets par instance Player. Négligeable.

### Neutral

- Le tilt est toujours en local Z mais maintenant sur CameraArm. Behavior visuel identique à l'alternative directe.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Implémentation oublie de mettre AudioListener3D enfant de Camera3D | LOW | MEDIUM (audio mute) | Vérification visuelle scene tree au premier prototype + AC dédié |
| Camera Sytem mute par erreur `camera3d.rotation.x` au lieu de `camera_arm.rotation.x` | LOW | HIGH (pitch n'apparaît pas) | Code review godot-gdscript-specialist + lint pattern matching `camera3d.rotation` interdit hors shake |
| Conflit transform Camera3D entre fov+shake (rotation cumulée non reset) | LOW | MEDIUM (drift visuel) | Convention : `camera3d.rotation = shake_offset` (assignation, pas `+=`) chaque frame, garantit reset implicite |

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (frame time Camera) | N/A (pas de code) | < 0.2 ms p99 | 0.5 ms |
| Memory | N/A | +64 B / Player instance | < 1 KB |
| Load Time | N/A | +0 ms (instantiation Node3D triviale) | — |

Le coût d'un Node3D supplémentaire dans la hiérarchie est négligeable. Aucun impact mesurable sur les budgets globaux.

## Migration Plan

1. **Camera System GDD** : réécrire Rule 1 (scene tree) + Formula 5 (closed-form) + toutes les références à `camera.rotation.x` et `camera.rotation.z` pour cibler `camera_arm.rotation.*`. **Done en cette session.**
2. **Player Movement GDD** : la Interactions table mentionne déjà la hiérarchie correcte — vérifier qu'aucune autre section ne contredit (en particulier les ACs et la section Visual/Audio Requirements). Patches mineurs en session séparée si concurrent processes ne bloquent pas.
3. **Prototype `prototypes/movement-katana/`** : si le proto utilise un pattern direct, le refactor est trivial — ajouter un Node3D intermédiaire, déplacer la rotation X de Camera3D vers CameraArm. Estimation : 1 h.
4. **Première story Camera** (Sprint 1) : embarque cet ADR-0002 dans son header.

**Rollback plan** : Si benchmark Sprint 1 révèle un problème inattendu (improbable), revenir au pattern direct demande de réécrire Rule 1 + retirer un Node3D. Coût : < 1 h. La forme close de Formula 5 reste valide sans CameraArm (elle utilise `player.rotation.y` et `camera_arm.rotation.x` que l'on remplace par `camera.rotation.x`).

## Validation Criteria

- [ ] **VC-1** : Scene tree `Player.tscn` instanciée contient bien `CharacterBody3D → CameraArm: Node3D → CameraEffects: Node3D → Camera3D → AudioListener3D` (vérification visuelle éditeur + GUT `assert(player.get_node("CameraArm/CameraEffects/Camera3D") != null)`).
- [ ] **VC-2** : Pitch (rotation X) ne s'applique JAMAIS sur Camera3D ni sur CameraEffects — grep CI sur `camera3d.rotation.x`, `$Camera3D.rotation.x`, `camera_effects.rotation.x` ou `$CameraEffects.rotation.x` dans `src/` doit retourner 0 occurrence (whitelist : assignation `camera3d.rotation = shake_offset`).
- [ ] **VC-3** : Tilt (rotation Z) ne s'applique JAMAIS sur Camera3D ni sur CameraArm — grep CI sur `camera3d.rotation.z`, `camera_arm.rotation.z`, `$Camera3D.rotation.z`, `$CameraArm.rotation.z` dans `src/` doit retourner 0 occurrence (whitelist : assignation `camera3d.rotation = shake_offset`).
- [ ] **VC-4** : `aim_forward` calculé via la forme close trigonométrique correspond à `Basis.from_euler(Vector3(camera_arm.rotation.x, player.rotation.y, 0)).z` à `is_equal_approx()` près sur 100 cas randomisés (yaw, pitch dans leur safe range).
- [ ] **VC-5** : AudioListener3D actif sans appel `make_current()` — vérifié via test lecteur sound 3D positionné en jeu, son entendu correct selon position Camera3D.
- [ ] **VC-6** : Coût `_process` Camera ≤ 0.2 ms p99 sur 1000 frames de scène test (perf-analyst budget Camera GDD).
- [ ] **VC-7** *(Amendment A-1)* : grep CI sur `src/gameplay/camera/` — les patterns `player.state ==`, `player.is_dashing`, `player.state !=`, `match player.state` doivent retourner **0 occurrence**. Whitelist : handlers de signaux (fonctions préfixées `_on_`) peuvent lire leurs payloads typés. Raison : Camera consomme les transitions Movement exclusivement via signaux ADR-0005, jamais par polling d'état. Test : script CI bash `grep -rE '(player\.state\s*[!=]=|player\.is_dashing|match\s+player\.state)' src/gameplay/camera/ | grep -v '_on_' ; assert exit 1 (nothing found)`.
- [ ] **VC-8** *(Amendment A-1)* : dans `_ready()` de Camera System, les 6 connexions signal Movement requises sont présentes : `player.wall_run_entered.connect(_on_wall_run_entered)`, `player.wall_run_exited.connect(_on_wall_run_exited)`, `player.dash_started.connect(_on_dash_started)`, `player.dash_ended.connect(_on_dash_ended)`, `player.died.connect(_on_died)`, `player.respawned.connect(_on_respawned)`. Test GUT : `assert(player.wall_run_entered.get_connections().size() >= 1)` + vérif chaque Callable cible un handler existant sur Camera. Flag mode sync (pas de `CONNECT_DEFERRED`) — assert `connection.flags == 0`.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| `design/gdd/camera-system.md` | Camera System | "Le yaw horizontal est délégué au Player node ; la caméra ne fait que pitcher" (Overview) | CameraArm porte pitch + tilt, Camera3D porte fov + shake — yaw reste sur Player.rotation.y |
| `design/gdd/camera-system.md` | Camera System | "Le tilt wall-run … doit être visible à 95% de sa valeur cible dans ≤ 250 ms" (Rule 4) | Tilt sur `camera_arm.rotation.z` lerpé vers WALL_RUN_TILT_ANGLE * wall_side (formule conservée, target node corrigé) |
| `design/gdd/camera-system.md` | Camera System | "`CameraSystem.aim_forward` retourne un Vector3 sans roll" (Rule 14) | Formule close trigonométrique avec `camera_arm.rotation.x` + `player.rotation.y`, pas de manipulation Basis, AC analytiquement vérifiable |
| `design/gdd/player-movement-system.md` | Player Movement | "Hiérarchie recommandée (revised r3 godot-specialist F3) : CharacterBody3D → CameraArm → CameraEffects → Camera3D" (section Animation, ligne ~424) | Adopté formellement — trois étages retenus pour éviter les conflits Tween head-bob ↔ tilt |
| `design/gdd/camera-system.md` | Camera System | *(Amendment A-1)* "Camera consomme les signaux `wall_run_entered/exited` et `dash_started/ended` émis par MovementController" (cross-ref ADR-0005 D-2) | Key Interfaces A-1 : 6 handlers `_on_*` connectés au `_ready` de Camera System, flags privés cachés, `_process` lit les flags et jamais `player.state`. VC-7 + VC-8 valident CI + runtime. |
| `design/gdd/player-movement-system.md` | Player Movement | *(Amendment A-1)* "Les transitions d'état Movement sont publiées via signaux typés directs, pas via getter `state` polling-ready" (cross-ref ADR-0005 D-1/D-2) | Camera (1er consumer non-Movement) applique strictement le pattern ; sert de référence canonique pour Combat, VFX, Audio, HUD. |

## Related

- ADR-0001 — Physics Tick Rate 60 Hz (n'impacte pas ce choix mais coexiste dans le scope Sprint 1).
- **ADR-0005** — Movement Signals Architecture *(dépendance formalisée par Amendment A-1)* : pose les 8 signaux typés Movement consommés par Camera pour tilt et FOV.
- ADR-0003 — Rendering & Display Latency Strategy : cible Camera3D fov dynamique sans changement de tree.
- ADR-0004 — Input API & Focus Handling : source du signal `mouse_motion(delta: Vector2)` consommé par Camera pour pitch.
- `design/gdd/camera-system.md` — réécrit en r2 pour intégrer cet ADR ; à synchroniser sur Amendment A-1 si des sections prescrivent encore un polling `player.state`.
- `design/gdd/player-movement-system.md` — déjà aligné via la Interactions table, patches mineurs Visual/Audio en session séparée.
