# Save/Load System

> **Status**: Designed r1 (pending fresh `/design-review`)
> **Author**: Martin + game-designer + systems-designer + qa-lead (subagents inline)
> **Last Updated**: 2026-04-27
> **Implements Pillar**: 2 (LA PROGRESSION SE VOIT) primaire — sans persistance, crédits et upgrades retombent à 0 chaque session, Pillar 2 cassé. Pillar 3 (UNE SECONDE CHANCE) garde-fou : save-on-quit garantit zéro perte de progression. Pillar 1 (FLOW) contrainte : I/O ne doit jamais provoquer un drop de frame perceptible (budget 16.6 ms à 60 fps).
> **Layer**: Foundation / Persistence
> **Solo gates** : CD-GDD-ALIGN skipped (Solo mode `production/review-mode.txt`).

---

## Overview

Save/Load System est un **autoload Foundation** fournissant des **verbes typés de persistance** (`load_int`, `save_int`, `load_string_array`, `save_string_array` MVP ; `load_int_array`, `save_int_array` Tier 2+) au-dessus de Godot `ConfigFile` stocké dans `user://savegame.cfg`. Il est **write-through synchrone** (chaque appel `save_*` écrit immédiatement le fichier — pas de batch, pas de file dirty), **stateless du point de vue gameplay** (il n'orchestre rien, ne décide jamais quand sauver), et **outbound-only zéro signal** (les consumers appellent les verbes ; il ne pousse jamais de notification). Le save-on-quit est **owned localement** par SaveLoadSystem via un handler `NOTIFICATION_WM_CLOSE_REQUEST` qui flush l'état (no-op MVP grâce au write-through). Le système est en `PROCESS_MODE_ALWAYS` (continue de fonctionner sous pause, requis par GSM r1 §Rule 5). L'ordre autoload est figé par ADR-0007 D-1 : `InputManager → GameStateManager → SaveLoadSystem → AudioSystem` — SaveLoad est en position 3, **avant tous les consumers gameplay** (Credit, Shop, Secret, Upgrade), garantissant que `SaveLoad.load_int(...)` est toujours résoluble dans le `_ready()` du premier consumer. Sa surface API publique compte 4 verbes MVP + 2 Tier 2+ + 1 getter de version, **aucun signal**, **aucun état mutable observable** au-delà du fichier sur disque. Au MVP : 1 fichier, 1 profil par installation, aucun chiffrement, aucune migration de schéma. Le scope MVP couvre exactement les contrats provisoires figés par les GDDs amont (Credit r1 OQ-CRD-2 dépendant, Shop r1 OQ-SHP-3, GSM r1 §11) ; la liste exhaustive des clés MVP tient en 2 entrées (`total_credits` int + `owned_upgrades` Array[StringName]).

---

## Player Fantasy

### B.1 — La non-fantaisie comme objectif

Save/Load est **infrastructure pure** : le joueur n'interagit jamais avec lui directement. Il n'y a pas de bouton "Sauvegarder", pas d'écran de slots, pas de dialogue "Voulez-vous sauvegarder ?". La règle visuelle Chrome Zen (« Le vide rend la lame visible. ») s'applique ici par soustraction maximale : **l'absence d'UI est l'UX**. La meilleure expérience de Save/Load est celle où le joueur n'y pense jamais. Référence d'inspiration : Hollow Knight (sauvegarde sur banc, le banc étant déjà un élément de level design Pillar — nous n'avons pas de banc MVP, donc pas même de proxy diégétique). Anti-référence : la majorité des AAA (UI verbeuse, "Cloud Sync" notifications, "Saving... do not turn off your console" overlays — toutes anti-Pillar 1).

### B.2 — Le pacte avec Pillar 2 (LA PROGRESSION SE VOIT)

Le moment où le joueur **sent** Save/Load, c'est au boot suivant : il rouvre le jeu, voit son compteur de crédits afficher la valeur où il l'avait laissé, voit que `double_jump` est toujours owned dans le shop. Cette continuité est le **prolongement direct du Player Fantasy de Credit Economy r1** (« le compteur permanent qui n'est jamais reset ») et du **Player Fantasy de Shop r1** (« les upgrades sont des promesses gravées »). Sans Save/Load, ces deux fantaisies sont des mensonges — le joueur travaille pour rien. Save/Load est donc **l'infrastructure qui rend Pillar 2 vraie**.

### B.3 — Le pacte avec Pillar 3 (UNE SECONDE CHANCE)

Pillar 3 dit « die-retry sous 2 s ». Save/Load étend ce contrat hors-session : **fermer le jeu accidentellement (alt-F4, crash OS, panne de courant) ne doit jamais coûter une session de progression**. Le write-through immédiat garantit qu'un crash entre deux purchases ne perd que le state RAM courant, jamais les achats déjà faits. Les achats sont écrits avant que `try_spend` ait débité (cf. Shop R-SHP-8) — Save/Load doit honorer cette atomicité côté disque pour ne pas créer un mensonge.

### B.4 — Anti-fantaisies (ce que Save/Load n'est PAS)

- **NOT** un système d'inventaire ou de stats persistantes — au MVP, 2 clés totales (`total_credits` + `owned_upgrades`). Pas de `player_position`, pas de `current_etage_index`, pas de `playtime_seconds`. La session est éphémère ; seules les **acquisitions permanentes** sont persistées.
- **NOT** un système de slots / multi-profile MVP — 1 installation = 1 save. Multi-profile = Tier 2+.
- **NOT** un système anti-cheat — le fichier `user://savegame.cfg` est lisible et éditable au notepad. Anti-cheat = Tier 3 leaderboards (chiffrement + checksum + serveur). MVP solo = aucun cheat à empêcher (le joueur peut s'auto-saboter, c'est son droit).
- **NOT** un système de cloud sync — Steam Cloud / itch sync = Tier 3 release platforms.
- **NOT** un système qui décide *quand* sauver — il **expose** des verbes ; les consumers les appellent. Le seul auto-trigger MVP est `NOTIFICATION_WM_CLOSE_REQUEST` (flush no-op write-through).

---

## Detailed Rules

### R-SAV-1 — SaveLoadSystem est un autoload Node singleton

`SaveLoadSystem extends Node` déclaré dans `project.godot` autoload section. Path : `*res://src/core/save_load_system.gd`. Position autoload **3 sur 4** Foundation : `InputManager → GameStateManager → SaveLoadSystem → AudioSystem` (ADR-0007 D-1 figée). Pas de class_name collision (pattern `-Script` suffix si requis Godot 4.6 cf. memory `feedback_godot_class_name_autoload_collision`) — le nom autoload `SaveLoadSystem` peut être réutilisé comme global, le fichier est `save_load_system.gd` sans `class_name` (autoload sans `class_name` évite la collision Godot 4.6).

### R-SAV-2 — Storage backend : ConfigFile sur `user://savegame.cfg`

Format MVP : Godot `ConfigFile` (https://docs.godotengine.org/en/stable/classes/class_configfile.html) — section unique `[data]`, clés string, valeurs typed primitive ou Array. Path canonique `user://savegame.cfg` (cross-platform : Windows `%APPDATA%/Godot/app_userdata/<projectName>/savegame.cfg`, macOS `~/Library/Application Support/Godot/...`, Linux `~/.local/share/godot/app_userdata/...`). **Rejet JSON** : verbeux, pas de typage natif, parsing manuel (overhead). **Rejet Resource (.tres)** : require schema class_name, casse migration MVP→Tier2+. **Rejet binary FileAccess** : attention Godot 4.4 breaking change `FileAccess.store_*` retourne `bool` (pas `void`) — ConfigFile abstrait l'API stable.

### R-SAV-3 — Single section `[data]`, flat key namespace MVP

Toutes les clés vivent dans `[data]`. Pas de sectionning par système MVP (ex : pas de `[credit]/total_credits` séparé de `[shop]/owned_upgrades`). Justification : 2 clés totales MVP, sectionning prématuré. Tier 2+ migration vers sections par système si > 10 clés. Liste exhaustive des clés MVP gérées :

| Key | Type | Default | Owner GDD | When written | When read |
|-----|------|---------|-----------|--------------|-----------|
| `total_credits` | `int` | `0` | Credit Economy r1 | `state_changed(MENU)` (Credit R-CRD-12) | `state_changed(PLAYING)` boot hydrate (Credit Rule 11) |
| `owned_upgrades` | `Array[StringName]` | `[]` | Shop System r1 | Immédiatement post-`try_spend` succès (Shop R-SHP-8) | `Shop._ready()` (Shop R-SHP-3) |
| `_save_version` | `int` | `1` | Save/Load (méta) | Premier write tout consumer | `SaveLoadSystem._ready()` (validation) |

Tier 2+ ajouts prévus : `collected_secret_ids` (Array[int], Secret r1 §J-2), `current_etage_id` (int, GSM extension), `playtime_seconds` (int, telemetry), settings audio (séparé fichier `user://settings.cfg` recommandé).

### R-SAV-4 — Surface API publique : 4 verbes MVP + 2 Tier 2+ + 1 getter

**MVP (4 verbes typed)** — couvrent intégralement les contrats Credit r1 + Shop r1 :

```gdscript
func load_int(key: String, default: int) -> int
func save_int(key: String, value: int) -> void
func load_string_array(key: String, default: Array[StringName]) -> Array[StringName]
func save_string_array(key: String, value: Array[StringName]) -> void
```

**Tier 2+ (2 verbes typed) — déférés** : `load_int_array(key, default) -> Array[int]` + `save_int_array(key, value)` pour Secret System persistance permanente (Secret r1 §J-2 confirme MVP = session-only via Checkpoint snapshot, persistance disque déférée Tier 2+).

**Getter méta (1)** : `get_save_version() -> int` (retourne `_save_version` lu à boot, défaut `1`). Utilisé par Tier 2+ migration logic.

**Rejet API generic** (`get(key, default)` / `set(key, value)`) : casse le typage statique GDScript Godot 4.6, force chaque consumer à `cast` au type voulu — anti-pattern. Préférence verbes typés à la signature.

### R-SAV-5 — Write-through synchrone, pas de batch

Chaque appel `save_*` exécute **immédiatement** : (1) `_config.set_value("data", key, value)` ; (2) `_config.save(SAVE_FILE_PATH)` (synchrone) ; (3) retour. Pas de queue dirty, pas de coalescing intra-frame, pas de write deferred. Justification : le pattern Shop R-SHP-8 (« persistance immédiate post-achat — perte de crédit + perte d'owned state au crash = pire scénario ») exige durabilité immédiate. Le coût I/O d'un `ConfigFile.save()` sur fichier ~1 KB MVP est < 1 ms sur SSD moderne (mesuré empiriquement Godot 4.6 sur Mac M1 : ~0.3 ms). Hors budget frame 16.6 ms : safe.

### R-SAV-6 — Load à la demande, retour `default` sur absent / corrompu / type mismatch

```gdscript
func load_int(key: String, default: int) -> int:
    if not _config_loaded or not _config.has_section_key("data", key):
        return default
    var raw: Variant = _config.get_value("data", key, default)
    if typeof(raw) != TYPE_INT:
        push_warning("SaveLoadSystem: key '%s' wrong type (got %d, expected int) — returning default" % [key, typeof(raw)])
        return default
    return raw
```

Sémantique : **silencieux pour l'absence, warning pour la corruption type, jamais de crash, jamais de prompt**. Couvre Credit EC-CRD-8 + Shop EC-SHP-6/7 explicitement. Le default est **toujours** retourné par le consumer (jamais hardcodé dans SaveLoad — c'est le consumer qui possède la sémantique du défaut).

### R-SAV-7 — Boot lifecycle : `_ready()` charge le fichier une fois

```gdscript
func _ready() -> void:
    process_mode = PROCESS_MODE_ALWAYS  # R-SAV-8
    _config = ConfigFile.new()
    var err: Error = _config.load(SAVE_FILE_PATH)
    if err == OK:
        _config_loaded = true
        var version: int = _config.get_value("data", "_save_version", 1)
        if version > _CURRENT_SAVE_VERSION:
            push_warning("SaveLoadSystem: save file version %d > supported %d — partial load possible" % [version, _CURRENT_SAVE_VERSION])
        # Tier 2+ : run migration if version < _CURRENT_SAVE_VERSION
    elif err == ERR_FILE_NOT_FOUND:
        # Première session : pas une erreur, tous les load_* retourneront default
        _config_loaded = true  # config vide est un état valide
    else:
        push_error("SaveLoadSystem: failed to load %s (err=%d) — running session in volatile mode" % [SAVE_FILE_PATH, err])
        _config_loaded = false
        # Tous les load_* retourneront default ; les save_* tenteront quand même d'écrire (peut succeed après failure transient)
```

**Garantie d'ordre** : `_ready()` SaveLoadSystem précède `_ready()` de tout consumer (Credit, Shop, Audio) par ordre autoload ADR-0007 D-1. Donc un consumer peut faire `SaveLoad.load_int(...)` dès son propre `_ready()` sans race.

### R-SAV-8 — `process_mode = PROCESS_MODE_ALWAYS`

SaveLoadSystem doit continuer de fonctionner sous `PAUSED` (GSM r1 Rule 5 ADR-0007 D-4 : « SaveLoadSystem en `PROCESS_MODE_ALWAYS` »). Justification : le menu pause peut déclencher une sauvegarde (futur Settings menu Tier 2+) ; le `NOTIFICATION_WM_CLOSE_REQUEST` peut survenir pendant `PAUSED` et doit être servi.

### R-SAV-9 — `NOTIFICATION_WM_CLOSE_REQUEST` handler — flush + dispose

```gdscript
func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _flush_pending()  # MVP : no-op grâce au write-through (R-SAV-5)
        # Tier 2+ : si batch mode activé, flush la queue dirty
```

MVP : `_flush_pending()` est volontairement no-op (write-through exhaustif R-SAV-5 garantit zéro état RAM dirty). Le hook existe pour absorber Tier 2+ async batch sans casser l'API. **Point critique GSM r1 §11** : le quit propre passe par le main menu qui appelle `get_tree().quit()` — `NOTIFICATION_WM_CLOSE_REQUEST` est délivré avant que SceneTree se ferme, dans la frame de quit. Toutes les saves doivent être déjà flushées (write-through) ; le hook est un filet de sécurité pour le futur.

### R-SAV-10 — Aucun signal sortant MVP

SaveLoadSystem n'émet aucun signal. Il n'a pas besoin de notifier qui que ce soit que la sauvegarde est terminée — write-through synchrone implique : si l'appelant a la main après `save_int(...)`, la write a réussi (ou un `push_error` a été émis). Tier 2+ async pourra ajouter `save_completed(key: String, success: bool)` mais c'est hors scope MVP.

### R-SAV-11 — Aucune orchestration de gameplay

SaveLoadSystem **ne consomme aucun signal des autres systèmes** MVP. Il **n'écoute pas** `state_changed(MENU)` pour déclencher une save automatique. Ce sont les consumers (Credit Economy R-CRD-12, Shop R-SHP-8) qui décident *quand* appeler `save_*`. Justification : éviter les double-écritures (si SaveLoad observait `state_changed(MENU)` ET Credit appelait `save_int` au même handler, double écriture). Pattern : **API verbe pur, pas d'orchestration**. Single-responsibility.

### R-SAV-12 — Type-safe load via Variant validation

`load_int` et `load_string_array` valident que la valeur lue est du type attendu. Si le fichier a été corrompu (édité au notepad, schema migration ratée), `typeof(raw) != TYPE_*` retourne `default` + `push_warning`. Spécifiquement pour `load_string_array` :

```gdscript
func load_string_array(key: String, default: Array[StringName]) -> Array[StringName]:
    if not _config_loaded or not _config.has_section_key("data", key):
        return default
    var raw: Variant = _config.get_value("data", key, default)
    if typeof(raw) != TYPE_ARRAY:
        push_warning("SaveLoadSystem: key '%s' not Array (got typeof=%d)" % [key, typeof(raw)])
        return default
    var validated: Array[StringName] = []
    for element in raw:
        if element is StringName:
            validated.append(element)
        elif element is String:
            validated.append(StringName(element))  # ConfigFile sérialise StringName comme String
        else:
            push_warning("SaveLoadSystem: key '%s' element type invalid (typeof=%d) — skipped" % [key, typeof(element)])
    return validated
```

Justification : ConfigFile ne préserve pas la distinction `StringName` vs `String` à la ronde-trip (sérialise les deux comme String entre quotes). Cette normalisation est explicite et couvre Shop EC-SHP-7 directement.

### R-SAV-13 — Idempotence

`save_int(key, value)` appelé deux fois consécutivement avec la même valeur : second appel = no-op effectif (le fichier est réécrit identique). Pas d'optimisation court-circuit MVP — la simplicité prime. Tier 2+ peut ajouter un cache RAM `_last_written_value` pour court-circuit si profilage le justifie.

### R-SAV-14 — Version key réservée mais pas de migration MVP

Le `_save_version` key est **toujours écrit** au premier write (cf. R-SAV-15 init), valeur `1` MVP, constante `_CURRENT_SAVE_VERSION = 1`. Aucune logique de migration MVP (1 seul schéma). Tier 2+ ajoute `_run_migration(from_version, to_version)` invoqué dans `_ready()` après load. **Règle d'or** : tout amendement de schéma (rename de clé, change de type, split section) **doit** incrémenter `_CURRENT_SAVE_VERSION` et fournir un migration step. Sans migration, l'ancienne save est traitée comme corrompue (defaults retournés) — perte silencieuse acceptable Tier 2+.

### R-SAV-15 — Initialisation lazy de `_save_version`

Le fichier `user://savegame.cfg` n'existe pas à la première session. Au premier appel `save_*` quelconque (premier kill du joueur déclenche save Credit `total_credits=1`, ou premier achat shop déclenche save Shop `owned_upgrades`), SaveLoadSystem écrit également `_save_version=1` dans la section `[data]`. Cela évite un fichier vide à `[data]` sans version. Pseudo-code :

```gdscript
func _ensure_version_written() -> void:
    if not _config.has_section_key("data", "_save_version"):
        _config.set_value("data", "_save_version", _CURRENT_SAVE_VERSION)

func save_int(key: String, value: int) -> void:
    _config.set_value("data", key, value)
    _ensure_version_written()
    var err: Error = _config.save(SAVE_FILE_PATH)
    if err != OK:
        push_error("SaveLoadSystem: save_int('%s', %d) failed (err=%d)" % [key, value, err])
```

### R-SAV-16 — États internes SaveLoadSystem

| État | Description | Entrée | Sortie |
|------|-------------|--------|--------|
| **UNINITIALIZED** | Pré-`_ready()`. Aucun appel valide. | Engine boot | `_ready()` exécuté |
| **READY_VOLATILE** | `_ready()` fini ; `_config.load()` a échoué pour cause non-recouvrable (permissions, disk). Tous les `load_*` retournent `default`, `save_*` retentent. | `_ready()` ERR != OK et != FILE_NOT_FOUND | Quit ou recovery I/O (Tier 2+) |
| **READY_FRESH** | `_ready()` fini ; fichier inexistant (FILE_NOT_FOUND). Première session. Toutes les clés absent, defaults retournés. | `_ready()` `_config.load()` ERR_FILE_NOT_FOUND | Premier `save_*` → READY_PERSISTED |
| **READY_PERSISTED** | `_ready()` fini ; fichier chargé, clés présentes. État nominal. | `_ready()` OK ou premier save | Quit |

États internes MVP, pas exposés à l'extérieur (pas de getter `get_state()`). Les consumers ne distinguent pas — l'API verbe est uniforme, l'état interne est invisible.

### R-SAV-17 — Outbound-only towards engine, inbound-only depuis consumers

Pattern de couplage :
- **Inbound API** : `load_*` / `save_*` appelés par Credit, Shop, Secret (Tier 2+), Upgrade (Tier 2+).
- **Outbound** : exclusivement vers `ConfigFile` API et FileAccess système (via ConfigFile en interne).
- **Aucun coupling cross-system** : SaveLoadSystem **n'importe pas** Credit / Shop / Secret / Upgrade. Il ne connaît pas leurs noms ni leurs clés ; les consumers les passent en paramètre.

### Interactions with Other Systems

| System | Direction | Interface | When | Owner | Status |
|--------|-----------|-----------|------|-------|--------|
| **GameStateManager** (autoload) | Soft listener (one-way silencieux) | GSM listed `process_mode` `PROCESS_MODE_ALWAYS` (ADR-0007 D-4). SaveLoad ne consume pas `state_changed` MVP (R-SAV-11). | N/A — coexistence | ADR-0007 D-1 figée | LOCKED |
| **Credit Economy** (autoload r1) | Inbound (Credit appelle Save) | `SaveLoad.load_int("total_credits", 0)` au boot PLAYING ; `SaveLoad.save_int("total_credits", n)` à `state_changed(MENU)`. | Credit R-CRD-11 + R-CRD-12 | Credit r1 | LOCKED — OQ-CRD-2 RESOLVED par ce GDD |
| **Shop System** (transitoire r1) | Inbound (Shop appelle Save) | `SaveLoad.load_string_array("owned_upgrades", [])` dans `Shop._ready()` ; `SaveLoad.save_string_array("owned_upgrades", arr)` immédiatement post-`try_spend` succès. | Shop R-SHP-3 + R-SHP-8 | Shop r1 | LOCKED — OQ-SHP-3 RESOLVED par ce GDD |
| **Secret System** (autoload r1) | Inbound MVP=N/A ; Tier 2+=Inbound | MVP : aucun appel SaveLoad (snapshot session-only via Checkpoint). Tier 2+ : `SaveLoad.save_int_array("collected_secret_ids", ids)` à `state_changed(MENU)`. | Secret r1 §J-2 + OQ-SEC-2 | Secret r1 | PROVISIONAL Tier 2+ — verbes int_array réservés R-SAV-4 |
| **Upgrade System** (Not Started) | Inbound présumé | Probablement aucun MVP (Shop persiste les owned ids ; Upgrade les applique en mémoire à boot via lecture Shop array). À confirmer Upgrade GDD. | Upgrade GDD #13 (à designer) | Upgrade Not Started | PROVISIONAL OQ-SAV-1 |
| **InputManager** (autoload) | Aucun MVP | Tier 2+ Settings : SaveLoad pourrait persister `mouse_sensitivity` etc. — mais recommandation forte : fichier séparé `user://settings.cfg` (pas mêler gameplay save & settings). | Tier 2+ Settings GDD | N/A MVP | OQ-SAV-2 |
| **AudioSystem** (autoload r2.1) | Aucun MVP | Tier 2+ Settings volume bus : même pattern `user://settings.cfg`. | Tier 2+ | N/A MVP | OQ-SAV-2 |
| **Engine OS / Window** | Outbound (silencieux) | `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` handler (R-SAV-9). | Quit | Engine | N/A |

---

## Formulas

### F-SAV-1 — Budget I/O par save (sanity check Pillar 1)

Save/Load n'a pas de formule de gameplay — c'est une couche I/O. La seule "formule" pertinente est un **garde-fou de budget I/O** pour valider que les écritures synchrones (R-SAV-5) ne cassent pas le budget frame Pillar 1 :

`budget_save_ms = ConfigFile.save() wall-clock time at file_size_kb`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `file_size_kb` | `S` | int | [0.1, 10] | Taille du fichier MVP (~0.1 KB pour 2 keys, ~1 KB Tier 2+ avec 10 keys) |
| `budget_save_ms` | `B` | float | [0.1, 5.0] | Wall-clock I/O sur SSD moderne |

**Output range MVP** : empirique Godot 4.6 sur SSD M1 : `B ≈ 0.3 ms` à `S = 0.1 KB`. À 60 fps, budget frame = 16.6 ms. **Marge ×55**. Headroom largement suffisant — write-through synchrone est safe MVP.

**Sanity check Tier 2+** : si `S` croît au-delà de 10 KB (10× Tier 2+ schema), `B` reste < 1 ms sur SSD. Sur HDD spinning (rare 2026), `B ≈ 5–20 ms` selon fragmentation. **Décision MVP** : assume SSD (target audience PC mid-core 18-35 ans, SSD ubiquitaire 2026). HDD = OQ-SAV-3 graceful degradation Tier 2+.

**Worked example MVP** :
- 2 keys (`total_credits` int + `owned_upgrades` array) + `_save_version`
- File content `~80 bytes` ASCII ConfigFile format
- `ConfigFile.save()` ≈ 0.3 ms
- Frame budget consumé : 0.3 / 16.6 = **1.8%** d'une frame à 60 fps
- Verdict : Pillar 1 préservé sans amendement.

### F-SAV-2 — N/A — Sémantique de gameplay

Save/Load n'expose pas de formule gameplay (pas de courbe, pas de scaling, pas de probabilité). Tous les calculs sémantiques (cost curve F-CRD-3, secret tier mapping F-CRD-2, sanity Pillar 2 F-SHP-3) sont **owned par leurs systèmes respectifs**. Save/Load est une **persistance brute** : `int → int`, `Array[StringName] → Array[StringName]`, round-trip identité.

**Justification documentée** : ne pas inventer des formules vides ("save success rate = 1.0") — anti-pattern. La table I/O budget F-SAV-1 est l'unique grandeur quantitative significative.

---

## Edge Cases

### Boot & file lifecycle

**EC-SAV-1 — Première session, fichier inexistant** : `user://savegame.cfg` n'existe pas. `_config.load()` retourne `ERR_FILE_NOT_FOUND`. R-SAV-7 traite ce cas comme nominal (`_config_loaded = true`, config vide). Tous les `load_*` retournent `default` (Credit `total_credits=0`, Shop `owned_upgrades=[]`). Premier `save_*` crée le fichier avec `_save_version=1` (R-SAV-15). Couvre Credit EC-CRD-8 + Shop EC-SHP-6 explicitement.

**EC-SAV-2 — Fichier corrompu (parse failure)** : `ConfigFile.load()` retourne ERR != OK et != FILE_NOT_FOUND (ex : ERR_FILE_CORRUPT, ERR_INVALID_DATA). R-SAV-7 logue `push_error`, set `_config_loaded = false`, état `READY_VOLATILE`. Tous les `load_*` retournent `default` (perte progression session). Les `save_*` retentent (peut succeed si la corruption était transient — partial write OS interruption). **Pas de prompt utilisateur MVP** — silent recovery (Pillar 1 + Pillar 3 anti-friction). Tier 2+ : optionnel popup "Save corrupted, start fresh?" via Menu.

**EC-SAV-3 — Permission denied au boot** : `_config.load()` retourne `ERR_FILE_NO_PERMISSION` (ex : install sandbox lockdown). R-SAV-7 → `READY_VOLATILE`. Save tente toujours mais échouera systématiquement. Logué chaque tentative. Session jouable mais zéro persistance — joueur perd progression au quit. Acceptable MVP (cas dégradé rare). Tier 2+ : telemetry remontée.

**EC-SAV-4 — Disk full au save** : `_config.save()` retourne `ERR_FILE_CANT_WRITE` ou `ERR_OUT_OF_MEMORY`. Couvre Shop EC-SHP-9 explicitement. R-SAV-15 logue `push_error` avec key + value + err code. Le consumer ne distingue pas l'échec (fonction `void`) — comportement défensif par couche : Credit débite RAM puis save (perte limitée à la session ; au prochain boot, total_credits revient à valeur pré-débit) ; Shop achète RAM puis save (MEC-SHP-9 EC-SHP-9 documenté : upgrade active session, perdue au reboot, crédit débité persistera au prochain quit Credit save). **MVP accepte cette inconsistance dégénérée — le cas "disk full" est extrêmement rare 2026 PC desktop**.

**EC-SAV-5 — Fichier supprimé en cours de session** : entre boot et premier save, `user://savegame.cfg` est manuellement supprimé (rare cas user). Au prochain `save_*`, `ConfigFile.save()` recrée le fichier ex-nihilo (write-through R-SAV-5). État RAM préservé en mémoire, écrit ; ré-hydratation au prochain boot reflète l'état RAM pré-suppression. **Comportement nominal — recreation transparent**.

**EC-SAV-6 — Fichier modifié manuellement durant la session** : utilisateur tech-savvy édite `savegame.cfg` au notepad pendant le jeu. Le `_config` RAM continue d'utiliser le snapshot loadé au boot. Le prochain `save_*` overwrite le fichier (sans warning) avec le state RAM. **Modifs externes en cours de session sont silencieusement écrasées MVP**. Acceptable solo. Tier 3 leaderboards : checksum + warning (anti-cheat scope).

### Type validation & corruption

**EC-SAV-7 — `load_int` sur clé Array** : utilisateur a édité savegame.cfg en mettant `total_credits = [1, 2, 3]`. `_config.get_value("data", "total_credits", 0)` retourne `Array`. `typeof(raw) != TYPE_INT` → `push_warning`, retourne `default=0`. Couvre Credit EC-CRD-8 type-mismatch. Session redémarre crédits=0 — perte mais pas crash.

**EC-SAV-8 — `load_string_array` sur clé int** : symétrique EC-SAV-7. R-SAV-12 retourne `default=[]` + warning. Couvre Shop EC-SHP-6. Toutes les upgrades apparaissent achetables (perte de progression upgrades).

**EC-SAV-9 — `load_string_array` éléments mixtes** : Array contient `["double_jump", 42, null, &"dash_horizontal"]`. R-SAV-12 boucle, conserve `["double_jump", "dash_horizontal"]` cast en StringName, ignore `42` et `null` avec warning par element. Couvre Shop EC-SHP-7. Owned set partiellement préservé.

**EC-SAV-10 — Clé `_save_version` manquante** : fichier valide ConfigFile ancien, sans version. `_config.get_value("data", "_save_version", 1)` retourne `default=1`. Comportement = "treated as v1" (MVP nominal). Tier 2+ : si schema actuel > 1, devrait déclencher migration ; absence = treat as v1.

**EC-SAV-11 — `_save_version` futur (> _CURRENT_SAVE_VERSION)** : utilisateur upgrade le jeu vers Tier 2 schema (v2) puis revient au binaire MVP (v1). `_save_version=2`. R-SAV-7 logue warning "save version 2 > supported 1 — partial load possible". MVP charge ce qu'il peut (clés v1 absentes en v2 = defaults). Pas de crash. Acceptable downgrade scenario rare. Tier 2+ : add explicit warning UI.

### Concurrency & lifecycle

**EC-SAV-12 — Multi-write même frame** : Credit `save_int("total_credits", 50)` puis Shop `save_string_array("owned_upgrades", ["double_jump"])` au même `_physics_process` tick (achat upgrade qui crédite immédiatement après — non-pattern MVP mais possible Tier 2+ refund). Write-through R-SAV-5 : 2 ConfigFile.save() séquentiels, 2 × 0.3 ms = 0.6 ms. F-SAV-1 budget : 3.6% frame consumé. Safe. Pas de race (single-threaded main loop Godot 4.6).

**EC-SAV-13 — Save pendant pause GSM PAUSED** : R-SAV-8 garantit `process_mode = ALWAYS`. SaveLoad continue de répondre. Hypothèse Tier 2+ : Settings menu (ouvert pendant PAUSED) modifie volume audio → `SaveLoad.save_int("audio_volume", 80)` exécuté pendant `get_tree().paused == true`. Comportement : nominal — write-through réussit, fichier flushé. Aucun handler de signal Save/Load en jeu, pas de coupling pause-sensitive.

**EC-SAV-14 — Quit pendant `save_int(...)` en cours** : write-through synchrone signifie que l'appel ne retourne pas avant que `ConfigFile.save()` ait fini. Si le user clique X de la fenêtre pendant `set_value` (ms-précis impossible mais théoriquement) : Godot délivre `NOTIFICATION_WM_CLOSE_REQUEST` au prochain idle. Le `save_int` en cours a la priorité (single-threaded) — il termine, retourne. PUIS R-SAV-9 handler s'exécute (no-op). Quit propre. **Pas de write half-finished** (ConfigFile.save() est atomique au niveau OS write système Godot 4.6).

**EC-SAV-15 — Crash OS pendant write** : OS panic / power loss pendant le `ConfigFile.save()` write système. ConfigFile **n'est pas atomique au niveau filesystem MVP** — un crash exact pendant le write peut laisser un fichier `savegame.cfg` partiel/tronqué. Au prochain boot, `_config.load()` peut retourner ERR_FILE_CORRUPT (EC-SAV-2). **Acceptable MVP** — case rare 2026 PC desktop avec UPS / laptop battery. Tier 2+ : write atomique via temp file + DirAccess.rename() (POSIX `rename()` atomique). OQ-SAV-4.

**EC-SAV-16 — `_ready()` SaveLoad échoue avant Credit `_ready()`** : impossibilité par ADR-0007 D-1 (autoload order figée). Si bug critique forçait Credit à appeler `SaveLoad.load_int` avant que SaveLoad `_ready()` soit fini : SaveLoad `_config_loaded = false` → toutes les `load_*` retournent `default`. Mais le moteur Godot 4.6 garantit l'ordre `_ready()` autoloads séquentiellement → ce cas ne se produit pas en pratique.

**EC-SAV-17 — Réentrance save dans handler save** : un consumer connecté à un signal qui appelle `save_int` qui (Tier 2+) trigger un autre signal qui rappelle `save_int`. Pas de protection MVP (pas de guard rentrant). Single-threaded → pas de deadlock, juste 2 writes séquentiels. Acceptable. Tier 2+ : si batch mode, guard avec flag `_writing` pour ignorer rentrance.

### Tier 2+ déférés

**EC-SAV-18 — Migration v1→v2** : à v2 schema add (ex : `current_etage_id`), `_save_version=1` détecté au boot, `_run_migration_1_to_2()` exécuté avant que tout consumer hydrate. Out of MVP scope. OQ-SAV-5.

**EC-SAV-19 — Multi-profile read** : MVP path fixe `user://savegame.cfg`. Tier 2+ : `set_active_profile(id: int)` switch path à `user://savegame_{id}.cfg`, recharge `_config`. Toutes les keys re-hydratées. Out of MVP scope. OQ-SAV-6.

**EC-SAV-20 — Save chiffré (Tier 3 anti-cheat)** : `ConfigFile.save_encrypted_pw(path, password)` Godot 4.6 supporté. Mais : MVP nul anti-cheat (pas de leaderboards Tier 1). Out of MVP scope. OQ-SAV-7.

---

## Dependencies

### Hard Dependencies (system cannot function)

**Aucune dépendance hard upstream**. Save/Load est un Foundation autoload pure — aucune dépendance gameplay, aucune dépendance API d'un autre autoload. Il dépend uniquement de :

- **Godot Engine 4.6 ConfigFile API** — stable depuis Godot 4.0 (`ConfigFile.load`, `set_value`, `get_value`, `save`, `has_section_key`)
- **Godot Engine 4.6 user:// path** — stable, cross-platform abstraction OS
- **Godot Engine 4.6 NOTIFICATION_WM_CLOSE_REQUEST** — stable, délivré au quit propre

### Soft Dependencies (coexistence)

| System | Direction | Nature | Status |
|--------|-----------|--------|--------|
| **Game State Manager** (autoload r1) | Coexistence | GSM r1 §11 référence SaveLoadSystem comme owner du save-on-quit (`NOTIFICATION_WM_CLOSE_REQUEST`). Pas d'appel d'API direct GSM ↔ SaveLoad. ADR-0007 D-4 process_mode_always partagé. | LOCKED |

### Hard Dependencies Downstream (consumers)

**Credit Economy r1** consume :
- `SaveLoad.load_int("total_credits", 0)` — ne peut hydrater Pillar 2 sans cet API
- `SaveLoad.save_int("total_credits", value)` — ne peut persister sans

**Shop System r1** consume :
- `SaveLoad.load_string_array("owned_upgrades", [])` — ne peut hydrater l'état owned sans
- `SaveLoad.save_string_array("owned_upgrades", arr)` — ne peut persister achats sans

### Soft Dependencies Downstream (Tier 2+)

**Secret System r1** : Tier 2+ persistance permanente via `save_int_array` / `load_int_array` (R-SAV-4 verbes réservés). MVP = N/A (snapshot Checkpoint session-only).

**Upgrade System** (Not Started) : probablement N/A direct (Shop persiste les ids ; Upgrade les lit indirectement). À confirmer Upgrade GDD.

### Bidirectional Check (Phase 2 cross-references)

| System GDD | Mentions SaveLoad ? | Verbes attendus matchent R-SAV-4 ? |
|------------|---------------------|--------------------------------------|
| **credit-economy-system.md** | ✅ Lines 57, 59, 82, 276, 302, 462, 595 | ✅ `load_int(key, default) -> int` + `save_int(key, value) -> void` matchent R-SAV-4 exactement |
| **shop-system.md** | ✅ Lines 11, 97, 120, 138, 230, 415, 417, 421, 447, 527, 554, 846, 878, 894, 960, 986, 993 | ✅ `load_string_array(key, default) -> Array[StringName]` + `save_string_array(key, value) -> void` matchent R-SAV-4 exactement |
| **secret-system.md** | ✅ Lines 133, 209, 714 | ✅ `load_int_array` + `save_int_array` Tier 2+ verbes réservés R-SAV-4 (déférés) |
| **game-state-manager.md** | ✅ Lines 48, 60, 110, 221, 270 | ✅ Pas d'API consumée (orchestration dispense) ; coexistence process_mode_always documentée R-SAV-8 |

**Verdict bidirectional** : 4/4 systèmes pré-existants ont contrats compatibles. Aucun amendement requis sur Credit / Shop / Secret / GSM. Save/Load r1 figure les 4 contrats provisoires en LOCKED.

### Anti-dependencies (explicitly forbidden)

| Anti-dep | Reason |
|----------|--------|
| **VFX System** | Save/Load n'a aucun visuel — anti-pattern de coupling. |
| **HUD System** | Save/Load n'a pas de display — pas d'éphémeride "Saving..." MVP (anti-Pillar 1). |
| **Audio System** | Aucun SFX MVP — anti-Pillar 1 (silent reliability). |
| **Input System** | Pas de raccourci F5/F9 quicksave MVP — pas de ce pattern dans le concept (Pillar 3 = die-retry permanent fluide, pas savescumming). |

---

## Tuning Knobs

### MVP Active Knobs

| Knob | Type | Default | Safe Range | Effect | Modifiable Without Code |
|------|------|---------|-----------|--------|------------------------|
| `SAVE_FILE_PATH` | const String | `"user://savegame.cfg"` | (immuable MVP) | Path du fichier savegame. **Modification = ADR + migration save existante**. | ❌ Code change |
| `_CURRENT_SAVE_VERSION` | const int | `1` | `[1, ∞]` (incremental) | Version du schema MVP. Incrémenter à chaque change schema + ajouter migration. | ❌ Code change |
| `SAVE_ON_QUIT_ENABLED` | const bool | `true` | `{true, false}` | Active le hook `NOTIFICATION_WM_CLOSE_REQUEST → _flush_pending()`. False = no-op (write-through suffit). MVP toujours true (défense en profondeur). | ❌ Code change |
| `LOG_LOAD_WARNINGS` | const bool | `true` | `{true, false}` | Active `push_warning` sur type mismatch / corruption. False = silent (release builds). MVP toujours true. | ❌ Code change |

### Tier 2+ Reserved Knobs (verbe inactifs MVP)

| Knob | Reserved For | Tier |
|------|--------------|------|
| `ENABLE_ENCRYPTION` | Tier 3 anti-cheat (leaderboards) | OQ-SAV-7 |
| `ENCRYPTION_PASSWORD` | Tier 3 (à derive de hardware ID + salt) | OQ-SAV-7 |
| `MULTI_PROFILE_ENABLED` | Tier 2+ (3 slots saves) | OQ-SAV-6 |
| `ATOMIC_WRITE_ENABLED` | Tier 2+ (temp file + rename) | OQ-SAV-4 |
| `BATCH_WRITE_DELAY_MS` | Tier 2+ async I/O | OQ-SAV-3 |
| `MIGRATION_TABLE` | Tier 2+ schema versioning | OQ-SAV-5 |

---

## Visual/Audio Requirements

**N/A — système Foundation pure data-layer.**

Justification explicite : Save/Load n'a **aucun élément visuel** (zéro overlay "Saving...", zéro icone disque, zéro animation), **aucun élément audio** (zéro SFX confirm save, zéro feedback chime). Cette absence est intentionnelle et **anti-pattern testable** (cf. Section H ACs anti-patterns) :

- Pas d'icone "Saving..." / "Saved" — viole Pillar 1 FLOW (UI invisible — game-concept ligne 96)
- Pas de SFX feedback — viole Audio r2.1 mix hierarchy (zero SFX MVP shop, par cohérence zero SFX save)
- Pas de pause / freeze visible pendant save (write-through < 1 ms — F-SAV-1 budget)
- Aucun asset visuel ou sonore à produire MVP — Asset Spec différé Tier 2+ (potentiel "Profile saved" toast Tier 2+ multi-profile)

**Anti-patterns observables MVP (testables AC) :**
1. AC-SAV-30 : Aucun Control / Sprite / Label dans la scène autoload pendant un `save_*`.
2. AC-SAV-31 : Aucun `play()` AudioStreamPlayer émis pendant un `save_*` ou `load_*`.
3. AC-SAV-32 : Frame budget consommé < 1 ms par `save_*` call (F-SAV-1).

---

## UI Requirements

**N/A — système Foundation backend uniquement.**

Pas de bouton Save/Load, pas de menu slots, pas de dialogue confirm. Le seul "écran" lié à Save/Load est :
- **Tier 2+** : main menu pourrait afficher "1 save | played 12h" — mais c'est owned par Menu System, pas Save/Load.
- **Tier 2+** : multi-profile = écran "Choose Profile" — owned Menu System.
- **MVP** : zéro UI propre. Pas d'UX flag.

**Aucun `/ux-design save-load.md` requis** — pas d'écran à spécifier.

---

## Acceptance Criteria

### A. Boot lifecycle (BLOCKING)

**AC-SAV-1 [Logic] [BLOCKING]** : GIVEN `user://savegame.cfg` n'existe pas (suppression manuelle préalable), WHEN engine boot et `SaveLoadSystem._ready()` exécuté, THEN `_config_loaded == true` ET `load_int("total_credits", 0) == 0` retourné. *Mécanisme* : unit GUT — supprimer fichier via DirAccess avant test, instancier SaveLoadSystem, assert getter helper `_is_ready()` ou direct `load_int` retour default.

**AC-SAV-2 [Logic] [BLOCKING]** : GIVEN `user://savegame.cfg` existe avec `[data]\ntotal_credits=42`, WHEN boot, THEN `load_int("total_credits", 0) == 42` (pas le default). *Mécanisme* : unit GUT — write fichier ConfigFile manuellement avant boot, assert load.

**AC-SAV-3 [Logic] [BLOCKING]** : GIVEN fichier corrompu (contenu binaire random non-ConfigFile), WHEN boot, THEN `_ready()` ne crash pas, `push_error` émis, tous les `load_*` suivants retournent default. *Mécanisme* : unit GUT — write bytes random avec FileAccess, instancier SaveLoad, assert `load_int("any", -1) == -1` + capture `push_error` via `Engine.get_singleton("ErrorCapture")` ou stub log.

**AC-SAV-4 [Integration] [BLOCKING]** : GIVEN engine boot avec project.godot autoload order InputManager → GSM → SaveLoadSystem → AudioSystem, WHEN tick 0 atteint, THEN `SaveLoadSystem._ready()` a déjà fini avant que `CreditEconomy._ready()` (Credit position 5+) appelle `load_int`. *Mécanisme* : integration test GUT — assert `SaveLoadSystem._is_ready() == true` dans `CreditEconomy._ready()` via signal `tree_entered` ordering.

### B. Roundtrip int (BLOCKING)

**AC-SAV-5 [Logic] [BLOCKING]** : GIVEN `_config_loaded == true`, WHEN `save_int("test_key", 123)` puis `load_int("test_key", 0)`, THEN retour `123`. *Mécanisme* : unit GUT roundtrip simple.

**AC-SAV-6 [Logic] [BLOCKING]** : GIVEN `save_int("k", 0)` exécuté, WHEN file content lu via FileAccess.open, THEN contient `[data]\n_save_version=1\nk=0\n` (version key auto-écrit R-SAV-15). *Mécanisme* : unit GUT — assert file content regex.

**AC-SAV-7 [Logic] [BLOCKING]** : GIVEN `save_int` appelé 1000 fois consécutifs avec valeurs croissantes, WHEN profilage `Time.get_ticks_msec()` deltas, THEN somme < 1000 ms (i.e. < 1 ms / call sur SSD). *Mécanisme* : perf test GUT F-SAV-1.

**AC-SAV-8 [Logic] [BLOCKING]** : GIVEN clé absente, WHEN `load_int("absent", 99)`, THEN retour `99`. *Mécanisme* : unit GUT default.

**AC-SAV-9 [Logic] [BLOCKING]** : GIVEN clé existe avec valeur Array (corruption manuelle), WHEN `load_int("k", -1)`, THEN retour `-1` ET `push_warning` émis. *Mécanisme* : unit GUT — set_value Array via _config direct, save, reload SaveLoad, capture warning.

### C. Roundtrip Array[StringName] (BLOCKING)

**AC-SAV-10 [Logic] [BLOCKING]** : GIVEN `save_string_array("upg", [&"double_jump", &"dash_horizontal"])`, WHEN `load_string_array("upg", [])`, THEN retour `Array[StringName]([&"double_jump", &"dash_horizontal"])` (taille=2, types StringName). *Mécanisme* : unit GUT roundtrip + assert chaque element `is StringName`.

**AC-SAV-11 [Logic] [BLOCKING]** : GIVEN array vide saved, WHEN reload, THEN `[]` retourné (pas null). *Mécanisme* : unit GUT.

**AC-SAV-12 [Logic] [BLOCKING]** : GIVEN clé existe avec int (corruption), WHEN `load_string_array("k", [])`, THEN retour `[]` + warning. *Mécanisme* : unit GUT type-mismatch.

**AC-SAV-13 [Logic] [BLOCKING]** : GIVEN array contient `[StringName, int, null, String]`, WHEN load, THEN retour `[StringName, StringName(String)]` (2 elements valides), 2 warnings émis. *Mécanisme* : unit GUT R-SAV-12 partial validation. Couvre Shop EC-SHP-7.

**AC-SAV-14 [Logic] [BLOCKING]** : GIVEN array de 100 StringName saved, WHEN load, THEN retour identique (taille=100, ordre préservé, tous StringName). *Mécanisme* : unit GUT large-set.

### D. Type safety & corruption resilience (BLOCKING)

**AC-SAV-15 [Logic] [BLOCKING]** : GIVEN `_save_version=99` (futur), WHEN boot, THEN `push_warning("save version 99 > supported 1")` émis ET load réussit pour clés présentes. *Mécanisme* : unit GUT — write fichier avec _save_version=99, capture warning.

**AC-SAV-16 [Logic] [BLOCKING]** : GIVEN `_save_version` absent, WHEN boot, THEN `get_save_version() == 1` (défaut MVP). *Mécanisme* : unit GUT.

**AC-SAV-17 [Logic] [BLOCKING]** : GIVEN fichier ConfigFile valide mais clés absent, WHEN `load_int("inexistant", 42)` puis `load_string_array("inexistant", [&"a"])`, THEN retours `42` et `[&"a"]`. *Mécanisme* : unit GUT defaults.

**AC-SAV-18 [Logic] [BLOCKING]** : GIVEN file inaccessible (permission revoquée mid-session, simulé via DirAccess.remove_absolute_path stub), WHEN `save_int`, THEN `push_error` émis avec err code, retour normal void (pas de crash). *Mécanisme* : unit GUT — mock ConfigFile.save retournant ERR_FILE_NO_PERMISSION.

### E. Process mode & lifecycle (BLOCKING)

**AC-SAV-19 [Integration] [BLOCKING]** : GIVEN GSM transitionné PAUSED (`get_tree().paused == true`), WHEN `save_int("k", 1)`, THEN write réussit sans erreur. *Mécanisme* : integration GUT — pause tree, call save, assert no error, file content updated.

**AC-SAV-20 [Logic] [BLOCKING]** : GIVEN SaveLoadSystem instancié, WHEN inspection `process_mode`, THEN `== PROCESS_MODE_ALWAYS` (R-SAV-8 ADR-0007 D-4). *Mécanisme* : unit GUT — assert `SaveLoadSystem.process_mode == Node.PROCESS_MODE_ALWAYS`.

**AC-SAV-21 [Integration] [BLOCKING]** : GIVEN session in-progress, WHEN simulation `NOTIFICATION_WM_CLOSE_REQUEST` envoyée, THEN handler exécuté sans crash, save state consistent. *Mécanisme* : integration GUT — `SaveLoadSystem.notification(NOTIFICATION_WM_CLOSE_REQUEST)` direct call, assert pas d'exception + état file inchangé (write-through suffit).

**AC-SAV-22 [Integration] [BLOCKING]** : GIVEN consumer (Credit) appelle `load_int` dans son `_ready()`, WHEN engine boot, THEN aucune assertion failure et valeur retournée. *Mécanisme* : integration GUT — instancier vraie scène avec Credit autoload, assert Credit `_total_credits` correctement hydraté.

### F. Cross-system integration (BLOCKING)

**AC-SAV-23 [Integration] [BLOCKING]** : GIVEN Credit Economy autoload avec saved `total_credits=50`, WHEN boot complet PLAYING, THEN `CreditEconomy.get_total() == 50` ET `credits_changed(50, 0, BOOT_HYDRATE)` émis. *Mécanisme* : integration GUT — pre-write savegame.cfg, instancier scène complète, assert Credit signal + value. Couvre Credit AC-CRD-25 + R-SAV-4 contract.

**AC-SAV-24 [Integration] [BLOCKING]** : GIVEN Shop achat `double_jump` réussi avec `try_spend(20) == true`, WHEN `Shop._on_purchase_button_pressed("double_jump")` finit, THEN `user://savegame.cfg` contient `owned_upgrades=Array[StringName]([&"double_jump"])`. *Mécanisme* : integration GUT — simuler full purchase flow, lire fichier post-action, assert content.

**AC-SAV-25 [Integration] [BLOCKING]** : GIVEN session 1 termine avec `total_credits=30` + `owned_upgrades=[&"double_jump"]`, WHEN session 2 boot, THEN Credit hydrate 30 + Shop init avec double_jump owned (BuyButton DISABLED OWNED). *Mécanisme* : integration GUT 2-session simulé — save session 1, simuler quit (NOTIFICATION_WM_CLOSE_REQUEST), reset autoloads, boot session 2, assert état combiné. **Test critique Pillar 2 end-to-end**.

### G. Performance budget (BLOCKING)

**AC-SAV-26 [Performance] [BLOCKING]** : GIVEN file MVP ~100 bytes, WHEN `save_int` 60 fois consécutifs (simulation 1 sec @ 60 fps avec save chaque frame), THEN durée totale < 60 ms (i.e. < 1 ms / call avg). *Mécanisme* : perf test GUT — Time.get_ticks_usec() deltas. F-SAV-1 budget verification.

**AC-SAV-27 [Performance] [ADVISORY]** : GIVEN file Tier 2+ schema simulé (10 keys, ~2 KB), WHEN save burst 10 saves consécutifs, THEN total < 50 ms. *Mécanisme* : perf scaling test. Advisory MVP, BLOCKING Tier 2+.

### H. Anti-patterns testables (ADVISORY)

**AC-SAV-28 [Logic] [ADVISORY]** : GIVEN SaveLoadSystem au runtime, WHEN tree node hierarchy inspection, THEN aucun child Control / Label / Sprite / AudioStreamPlayer présent. *Mécanisme* : unit GUT scene tree introspection.

**AC-SAV-29 [Logic] [ADVISORY]** : GIVEN inspection statique du fichier `save_load_system.gd`, WHEN grep `signal\s+`, THEN zero match (R-SAV-10 zero outbound signals MVP). *Mécanisme* : static check via Bash.

**AC-SAV-30 [Logic] [ADVISORY]** : GIVEN inspection statique, WHEN grep `signal_name.connect\|state_changed.connect\|enemy_killed.connect`, THEN zero match dans save_load_system.gd (R-SAV-11 no orchestration). *Mécanisme* : static check.

**AC-SAV-31 [Logic] [ADVISORY]** : GIVEN inspection, WHEN grep import / preload de `Credit\|Shop\|Secret\|Upgrade\|HUD\|Combat\|Movement\|Camera\|VFX\|Audio` dans save_load_system.gd, THEN zero match (R-SAV-17 zero coupling cross-system). *Mécanisme* : static check Bash.

### I. Open-question / chain-blocked (PROVISIONAL)

**AC-SAV-32 [Logic] [PROVISIONAL — chain-blocked OQ-SAV-1]** : GIVEN Upgrade System designé, WHEN contrats Save/Load consommés par Upgrade clarifiés (ou confirmés N/A), THEN amendement R-SAV-4 si verbes additionnels requis. *Mécanisme* : CHAIN-BLOCKED — re-valider à Upgrade r1.

**AC-SAV-33 [Logic] [PROVISIONAL — chain-blocked OQ-SAV-2]** : GIVEN Settings System (audio volumes / mouse_sensitivity) designé Tier 2+, WHEN décision split file `user://settings.cfg` ou même `user://savegame.cfg`, THEN amendement R-SAV-3 si single-file ou split confirmé. *Mécanisme* : CHAIN-BLOCKED Tier 2+.

### Sommaire ACs

- Total : **33 ACs**
- BLOCKING : **27** (A×4 + B×5 + C×5 + D×4 + E×4 + F×3 + G×1 + I×0 PROVISIONAL exclu)
- ADVISORY : **4** (G×1 + H×3 incl static checks)
- PROVISIONAL chain-blocked : **2** (I×2 — OQ-SAV-1 Upgrade, OQ-SAV-2 Settings Tier 2+)
- Auto-testable : **31** (94% — 33-2 PROVISIONAL chain-blocked attendant systèmes downstream)
- Couverture : Boot lifecycle ×4 + Roundtrip int ×5 + Roundtrip array ×5 + Type safety ×4 + Process mode ×4 + Cross-system ×3 + Performance ×2 + Anti-patterns ×4 + Provisional ×2

---

## Open Questions

| ID | Question | Status | Resolution Path | Owner | Tier Impact |
|----|----------|--------|-----------------|-------|-------------|
| **OQ-SAV-1** | Upgrade System (Not Started, position #13 systems-index) consume-t-il Save/Load directement ? Hypothèse Save/Load r1 : N/A — Shop persiste les owned ids, Upgrade les lit indirectement à boot via Shop. À confirmer Upgrade GDD. Si Upgrade veut son propre key (ex : `equipped_upgrade_id` runtime active), amendement R-SAV-3 + R-SAV-4 si verbes additionnels. | OPEN — bloquant impl Sprint 1 | À résoudre `/design-system upgrade-system`. Recommandation Save/Load r1 : Upgrade reste agnostique de Save/Load, lit `Shop.get_owned_upgrades()` au boot. | game-designer + Upgrade GDD author | MVP — bloquant si verbes additionnels |
| **OQ-SAV-2** | **Settings save fichier** : audio volumes (Audio r2.1 OQ-2 absent), mouse_sensitivity (Input GDD), gameplay options (reduce_motion_slow_mo_scale_mult Combat AC-CMB-46 réf, brightness Tier 2+) — un seul fichier `user://savegame.cfg` mêlé avec gameplay save, ou split `user://settings.cfg` séparé ? | OPEN — Tier 2+ | Recommandation Save/Load r1 : split en `user://settings.cfg` séparé (raisons : (1) corruption gameplay save n'efface pas settings ; (2) settings persiste cross-profile Tier 2+ multi-profile ; (3) reset settings standalone via Menu sans toucher gameplay save). Implémentation : ajouter constructor param `path` ou nœud autoload séparé `SettingsSaveSystem` (clone pattern Save/Load). MVP : aucun settings persisté (Audio bus volume hardcoded, mouse_sensitivity owned Input system-internal). | gameplay-programmer + Settings GDD author | Tier 2+ |
| **OQ-SAV-3** | **Async I/O Tier 2+** : si profilage révèle drop de frame sur HDD spinning ou disk loaded, faut-il batch + thread pool worker async write ? F-SAV-1 dit < 1 ms SSD = safe MVP. À profiler en playtest étape 1. | OPEN — Tier 2+ | Recommandation : ajouter knob `BATCH_WRITE_DELAY_MS` reservé R-SAV-4 ; async via `WorkerThreadPool` Godot 4.6 ; deferred flush dans `_notification(NOTIFICATION_WM_CLOSE_REQUEST)`. Attention `Save/Load` accède file via thread non-main — vérifier safety (ConfigFile pas thread-safe — copy-on-write avant flush). | gameplay-programmer | Tier 2+ playtest 1 |
| **OQ-SAV-4** | **Atomic write** (anti-corruption crash mid-write — EC-SAV-15) : ConfigFile.save() pas atomique POSIX. Faut-il temp file + DirAccess.rename() ? | OPEN — Tier 2+ | Recommandation : implémenter `_atomic_save(path, content)` qui write `path.tmp`, fsync, DirAccess.rename(`path.tmp`, `path`). Coût : 2× I/O (write tmp + rename). Bénéfice : zéro perte progression au crash. Connaissance gap : Godot 4.6 `DirAccess.rename` atomique POSIX confirmé ? À valider engine-reference. | engine-programmer | Tier 2+ |
| **OQ-SAV-5** | **Schema migration v1→vN** : framework migration explicite ? Table de fonctions `_migrate_v1_to_v2()` etc. exécutées séquentiellement au boot si `_save_version < _CURRENT_SAVE_VERSION` ? Ou rejet (treat as corruption, defaults retournés) ? | OPEN — Tier 2+ | Recommandation : framework migration léger. Dictionary `_MIGRATIONS = {1: _migrate_v1_v2, 2: _migrate_v2_v3, ...}` ; appliqué avant que tout consumer hydrate. Backward-compat seulement (jamais downgrade). Test exhaustif chaque migration step. | systems-designer + Tier 2+ schema authors | Tier 2+ |
| **OQ-SAV-6** | **Multi-profile** (3 slots saves) : path dynamique `user://savegame_{N}.cfg`, API `set_active_profile(id)` qui reload `_config`. Credit r1 OQ-CRD-10 + Shop r1 OQ-SHP-10 référencent. | OPEN — Tier 2+ | Recommandation Save/Load r1 : prefix transparent côté Save/Load (préférable). API `set_active_profile(id: int)` switch path + reload, consumers oblivious. Shop r1 OQ-SHP-10 et Credit r1 OQ-CRD-10 confirment ce pattern. | gameplay-programmer | Tier 2+ |
| **OQ-SAV-7** | **Encryption** (Tier 3 anti-cheat leaderboards) : `ConfigFile.save_encrypted_pw(path, password)` Godot 4.6. Password derive de ? Hardware ID + project salt ? Server-issued token ? | OPEN — Tier 3 | Out of MVP scope. Reco : leaderboards Tier 3 = checksum SHA256 + server validation ; encryption locale = obfuscation (security through obscurity, casse au reverse Godot binary). Préférable : signed save via server. À designer `/design-system speedrun-leaderboards-system` Tier 3. | security-engineer + leaderboards GDD author | Tier 3 |
| **OQ-SAV-8** | **Save failure telemetry Tier 2+** : émettre signal `save_failed(key, err_code)` + capture analytics ? | OPEN — Tier 2+ | Recommandation : `SaveLoadSystem` ajoute Tier 2+ signal `save_failed(key: String, err: int)` ; AnalyticsSystem (Tier 2+) capture. MVP push_error suffit. | analytics-engineer Tier 2+ | Tier 2+ |
| **OQ-SAV-9** | **Cross-platform path edge cases** : `user://` traduit en sandboxed paths sur certaines distributions (Flatpak, MacOS App Sandbox). Permission denial possibles ? Fallback à `OS.get_user_data_dir()` + custom subdir ? | OPEN — Tier 2 platform-cert | Out of MVP scope. Steam release Tier 2.5+ devra valider. itch.io Tier 1 utilise simplement user:// std Godot 4.6 — safe. | release-manager + devops-engineer | Tier 2 platform-cert |
| **OQ-SAV-10** | **Save file size cap** : limite la taille du `savegame.cfg` à `MAX_SAVE_KEYS_MVP` (sanity 1000 keys) ? Garde-fou contre fuite (consumer écrivant infinies keys par bug). | OPEN — défensif Tier 2+ | Reco : MVP no cap (2 keys, négligeable). Tier 2+ : cap 100 keys + push_error si dépassement. | systems-designer | Tier 2+ |

**OQ critiques bloquantes Sprint 1** : 1 (OQ-SAV-1 Upgrade contract — vérifier que Upgrade ne require pas verbe additionnel).

**OQ Tier 2+ deferred** : 9 (toutes les autres — split file Settings, async I/O, atomic write, migration, multi-profile, encryption, telemetry, sandbox paths, size cap).

**Résolutions induites par Save/Load r1** :
- **OQ-CRD-2 RESOLVED** : Credit r1 attendait API `try_spend` côté Shop (pas Save/Load). N/A pour Save/Load r1.
- **OQ-SHP-3 RESOLVED** : Shop r1 attendait API exacte `save_string_array` + `load_string_array` — Save/Load r1 confirme la signature à l'identique (R-SAV-4). Credit r1 + Shop r1 peuvent promote leur OQ correspondante en RESOLVED ou laisser le statut tel quel.
- **OQ-SEC-2 PROVISIONAL Tier 2+** : Secret r1 Tier 2+ persistance utilisera `save_int_array` + `load_int_array` réservés R-SAV-4. Pas implémenté MVP.

**Bidirectional updates requis** sur GDDs amont :
- Credit r1 §Open Questions OQ-CRD-2 : peut être marqué RESOLVED ou conservé (cosmetic).
- Shop r1 §Open Questions OQ-SHP-3 : peut être marqué RESOLVED ou conservé (cosmetic).
- Secret r1 §Open Questions OQ-SEC-2 : reste OPEN Tier 2+ (verbes réservés mais pas activés MVP).
- Systems Index #3 Save/Load row : Not Started → Designed r1 (Phase 5d).
