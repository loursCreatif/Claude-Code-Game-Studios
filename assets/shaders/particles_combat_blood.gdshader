// Particles shader — blood spurt Chrome Zen flat unshaded.
// Type     : particles (GPU particles process shader, Godot 4.6 Forward+)
// Category : combat
// Purpose  : Flat unshaded blood particles #C8232C — no PBR, no lighting.
//            Handles: spawn position, velocity cone spread, opacity fade-out
//            linéaire lifetime (F-VFX-3). One shared ShaderMaterial for all
//            8 pool slots (R-VFX-16 — set_shader_parameter per-spawn safe because
//            spread_deg is global reduce_motion flag, not per-slot variance).
//
// Uniforms :
//   blood_color  — RGBA couleur sang (#C8232C, source_color pour color picker).
//   spread_deg   — Demi-angle cone dispersion en degrés [0, 90]. Défaut 30°
//                  (BLOOD_CONE_ANGLE_DEG). Réduit à 15° si reduce_motion actif.
//
// Outputs built-in particles:
//   TRANSFORM     — position world (passée via slot.global_position, pas mutée ici)
//   VELOCITY      — direction + vitesse initiale dans le cone spread
//   COLOR         — blood_color avec alpha fade-out linéaire (F-VFX-3)
//   ACTIVE        — toujours true au start
//
// Formula F-VFX-3 : opacity(t) = 1.0 - (CUSTOM.x / lifetime)
//   CUSTOM.x stocke le temps écoulé normalisé [0, 1].
//
// Platform  : PC Desktop (Forward+). Not tested on Mobile/Compatibility.
// Budget    : 0 texture samples — colour + alpha calc only. Minimal GPU cost.
//
// AC-VFX-11 : flat shader sans PBR (render_mode unshaded, no lighting).
// AC-VFX-12 : spread_deg paramètre exposé — réduit par reduce_motion côté GDScript.
// R-VFX-8   : cone 30°, 6 particules, #C8232C, lifetime 400 ms, fade-out linéaire.
// Story-014 : story-002 tech-debt impl (déféré explicitement dans story-002 Out of Scope §shader).
shader_type particles;
render_mode disable_force;

/// Couleur sang flat Chrome Zen (#C8232C ≈ vec4(0.784, 0.137, 0.173, 1.0)).
/// source_color : hint Godot pour color picker + conversion sRGB→linear correcte.
uniform vec4 blood_color : source_color = vec4(0.784, 0.137, 0.173, 1.0);

/// Demi-angle du cone de dispersion en degrés.
/// Défaut 30° (BLOOD_CONE_ANGLE_DEG). Appliqué via set_shader_parameter par GDScript
/// avant chaque restart() — reduce_motion → 15° (REDUCE_MOTION_PARTICLE_ANGLE_MULT × 0.5).
uniform float spread_deg : hint_range(0.0, 90.0) = 30.0;

/// Vitesse initiale des particules (m/s). Défaut calibré pour splash 400 ms visible.
uniform float emit_speed : hint_range(0.1, 10.0) = 3.0;

// Pseudo-random float [0, 1] depuis un uint via LCG (Linear Congruential Generator).
// Pas de built-in hash() en GLSL — LCG suffisant pour dispersion de particules.
// Constantes LCG standard (Numerical Recipes) : multiplier=1664525, increment=1013904223.
float _lcg_rand(uint seed) {
	uint v = seed * 1664525u + 1013904223u;
	return float(v) / float(0xFFFFFFFFu);
}

void start() {
	// Particule active dès le spawn.
	ACTIVE = true;

	// Génération pseudo-aléatoire via LCG depuis NUMBER (index particule — unique par slot).
	// Deux tirages indépendants : azimuth + angle polaire.
	float rand_azimuth = _lcg_rand(NUMBER);
	float rand_polar   = _lcg_rand(NUMBER * 1664525u + 1013904223u);

	// Conversion demi-angle degrés → radians.
	float half_angle_rad = radians(spread_deg);

	// Direction dans le cone autour de Vector3.UP (0, 1, 0).
	// polar_angle : tirage dans [0, half_angle_rad] pondéré sqrt pour distribution uniforme.
	float polar_angle = half_angle_rad * sqrt(rand_polar);
	float azimuth     = rand_azimuth * 2.0 * PI;

	// Sphérique → cartésien (cone autour de +Y).
	float sin_p = sin(polar_angle);
	vec3 dir = vec3(
		sin_p * cos(azimuth),
		cos(polar_angle),
		sin_p * sin(azimuth)
	);

	// Vitesse initiale dans la direction du cone.
	VELOCITY = dir * emit_speed;

	// CUSTOM.x = 0.0 au spawn (réservé pour usage futur).
	CUSTOM = vec4(0.0, 0.0, 0.0, 0.0);

	// Couleur initiale opacité pleine.
	COLOR = vec4(blood_color.rgb, 1.0);
}

void process() {
	// Accumulation du temps normalisé dans CUSTOM.a (Godot 4 built-in — stocké par particule).
	// CUSTOM.a commence à 0.0 (initialisé dans start()), incrémenté chaque DELTA.
	// LIFETIME = durée totale en secondes (GPUParticles3D.lifetime).
	// Ratio [0, 1] : 0 = spawn, 1 = fin de lifetime.
	CUSTOM.a = CUSTOM.a + DELTA / LIFETIME;
	float t = clamp(CUSTOM.a, 0.0, 1.0);

	// F-VFX-3 : opacity(t) = 1.0 - t (fade-out linéaire, pas de Tween — wall-clock safe).
	float opacity = 1.0 - t;

	COLOR = vec4(blood_color.rgb, opacity);

	// Gravité légère pour arc naturel (Chrome Zen minimal — pas de physique réaliste).
	VELOCITY += vec3(0.0, -4.9, 0.0) * DELTA;
}
