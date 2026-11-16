shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
// Végétation texturée du désert (palmiers, arbres, buissons, touffes) : cartes découpées par l'alpha de l'atlas peint
// (alpha scissor, jamais de transparence triée), vent et teintes de saison. Corps commun : desert_foliage.gdshaderinc.

#define FOLIAGE_CARDS
#include "res://world/desert_jeu/desert_foliage.gdshaderinc"
