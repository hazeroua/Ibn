// Fondu des niveaux de détail par tramage (et non par transparence) : l'objet reste dans la passe opaque, avec un
// tampon de profondeur juste. La transparence triée par objet faisait passer des arbres (et des cellules entières)
// de l'arrière devant ceux de l'avant pendant les fondus. Réglé par LodFade (lod_fade.gd) pour chaque instance :
// lod_fade = (début de l'apparition, pleine apparition, début de la disparition, disparition complète), en mètres,
// mesurés comme Godot depuis la caméra jusqu'au centre de l'objet (lod_center, repère du monde).
instance uniform vec4 lod_fade = vec4(-2.0, -1.0, 1.0e9, 2.0e9);
instance uniform vec3 lod_center = vec3(0.0);

// Vrai si le pixel doit être écarté (matrice de Bayer 4 × 4 : 16 niveaux de fondu, sans bruit qui scintille).
bool lod_fade_discard(vec2 frag_coord, vec3 camera_world) {
	float distance_m = distance(camera_world, lod_center);
	float visible_in = clamp((distance_m - lod_fade.x) / max(lod_fade.y - lod_fade.x, 0.001), 0.0, 1.0);
	float visible_out = clamp((lod_fade.w - distance_m) / max(lod_fade.w - lod_fade.z, 0.001), 0.0, 1.0);
	float visible = visible_in * visible_out;
	if (visible >= 1.0) {
		return false;
	}
	ivec2 cell = ivec2(mod(frag_coord, 4.0));
	int index = cell.x + cell.y * 4;
	float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return visible <= (bayer[index] + 0.5) / 16.0;
}
