// Chrome Zen flat shader — story-022 final.
// Type     : spatial (Forward+ pipeline, Godot 4.6)
// Category : env (environment surfaces, rooms, walls, floors)
// Purpose  : Albedo + atlas UV remap, no lighting, cull back.
//            Single shared shader for all Chrome Zen primitives — 1 shader path,
//            minimal VRAM, zero runtime compile stutter (ADR-0003 Shader Baker
//            pré-compile une fois au boot).
//
// Uniforms :
//   albedo       — RGBA tint modulant l'échantillon atlas (source_color pour color picker).
//   atlas        — Texture2D atlas unique ≤ 1024² (TR-lvl-041) ; default white = albedo pur.
//   atlas_offset — Coin bas-gauche de la sous-région de l'atlas (UV space [0, 1]).
//   atlas_scale  — Taille de la sous-région en UV (sous-texture 256² → scale = 0.25).
//
// Platform  : PC Desktop (Forward+, Windows/macOS/Linux). Not tested on Mobile/Compat.
// Budget    : 1 texture sample + 1 multiply — minimal fragment cost.
//
// Source    : story-022 TR-lvl-040, TR-lvl-041 ; ADR-0003 (Shader Baker).
// No magic numbers : offset/scale exposed as uniforms ; palette via albedo per-material.
shader_type spatial;
render_mode unshaded, cull_back;

/// Tinte de couleur de surface (RGBA). Modulates l'échantillon atlas.
/// Default : gris acier pâle Chrome Zen (#595E6B approximatif).
/// source_color = hint Godot pour afficher un color picker dans l'inspecteur.
uniform vec4 albedo : source_color = vec4(0.35, 0.38, 0.42, 1.0);

/// Atlas de texture unique (≤ 1024×1024, TR-lvl-041).
/// hint_default_white : si aucun atlas n'est lié, retourne vec4(1) → albedo pur.
/// source_color : hint Godot pour la conversion espace colorimétrique (sRGB → linear).
uniform sampler2D atlas : source_color, hint_default_white;

/// Décalage UV vers le coin bas-gauche de la sous-région dans l'atlas.
/// Exemple : sous-texture à (256, 512) dans un atlas 1024² → offset = vec2(0.25, 0.5).
uniform vec2 atlas_offset = vec2(0.0);

/// Échelle UV de la sous-région dans l'atlas.
/// Exemple : sous-texture 256×256 dans un atlas 1024² → scale = vec2(0.25).
uniform vec2 atlas_scale = vec2(1.0);

void fragment() {
	// Remap UV vers la sous-région atlas : UV * scale + offset.
	// UV natifs Godot [0, 1] ; résultat dans [atlas_offset, atlas_offset + atlas_scale].
	vec2 uv = UV * atlas_scale + atlas_offset;
	ALBEDO = texture(atlas, uv).rgb * albedo.rgb;
}
