class_name FootContacts
extends RefCounted
## Instants où chaque pied se pose dans une animation, lus dans les pistes d'os (une fois, au branchement du modèle).
##
## Pour chaque pied, la hauteur de l'os du pied dans l'espace du squelette est échantillonnée sur toute l'animation en
## composant les pistes (ou la pose de repos) de l'os et de tous ses parents. Un appui commence quand le pied, après
## s'être levé d'au moins `lift_m` au-dessus de son point le plus bas, redescend à moins de `height_m` de ce point ;
## l'instant est interpolé entre les deux échantillons qui encadrent ce passage. Une boucle est parcourue en partant du
## point le plus haut du pied (l'appui qui chevauche la fin et le début n'est ni perdu ni compté deux fois).
##
## Deux appuis séparés de moins de min_gap_s n'en font qu'un. Résultat : temps (secondes, croissants) et pied
## (0 gauche, 1 droit) de chaque appui. Coût : échantillons × longueur de la chaîne d'os, une seule fois par
## animation ; rien par image.


## Appuis de l'animation : { "times": PackedFloat32Array, "feet": PackedInt32Array }, triés par temps.
## skeleton_path : chemin du squelette dans les pistes (relatif à la racine de l'AnimationPlayer).
static func analyze(
	animation: Animation,
	skeleton: Skeleton3D,
	skeleton_path: String,
	foot_bones: PackedInt32Array,
	samples_per_second: float,
	height_m: float,
	lift_m: float,
	min_gap_s: float
) -> Dictionary:
	var times := PackedFloat32Array()
	var feet := PackedInt32Array()
	var length: float = animation.length
	var count: int = maxi(8, ceili(length * samples_per_second))
	var looped: bool = animation.loop_mode != Animation.LOOP_NONE
	for foot: int in foot_bones.size():
		var heights := PackedFloat32Array()
		heights.resize(count + 1)
		for i: int in count + 1:
			heights[i] = bone_height(animation, skeleton, skeleton_path, foot_bones[foot], length * float(i) / float(count))
		_contacts_of(heights, length, count, looped, height_m, lift_m, foot, times, feet)
	_sort_by_time(times, feet)
	# Deux pieds posés presque ensemble (arrêt, pieds joints) : un seul bruit de pas.
	var kept_times := PackedFloat32Array()
	var kept_feet := PackedInt32Array()
	for i: int in times.size():
		if kept_times.is_empty() or times[i] - kept_times[kept_times.size() - 1] >= min_gap_s:
			kept_times.append(times[i])
			kept_feet.append(feet[i])
	return {"times": kept_times, "feet": kept_feet}


## Hauteur (espace du squelette) de l'os à l'instant t de l'animation : pistes de l'os et de ses parents, sinon repos.
static func bone_height(animation: Animation, skeleton: Skeleton3D, skeleton_path: String, bone: int, time: float) -> float:
	var global := Transform3D.IDENTITY
	var current: int = bone
	while current >= 0:
		var rest: Transform3D = skeleton.get_bone_rest(current)
		var path := NodePath("%s:%s" % [skeleton_path, skeleton.get_bone_name(current)])
		var position: Vector3 = rest.origin
		var rotation: Quaternion = rest.basis.get_rotation_quaternion()
		var scale: Vector3 = rest.basis.get_scale()
		var track: int = animation.find_track(path, Animation.TYPE_POSITION_3D)
		if track >= 0:
			position = animation.position_track_interpolate(track, time)
		track = animation.find_track(path, Animation.TYPE_ROTATION_3D)
		if track >= 0:
			rotation = animation.rotation_track_interpolate(track, time)
		track = animation.find_track(path, Animation.TYPE_SCALE_3D)
		if track >= 0:
			scale = animation.scale_track_interpolate(track, time)
		global = Transform3D(Basis(rotation).scaled(scale), position) * global
		current = skeleton.get_bone_parent(current)
	return global.origin.y


static func _contacts_of(
	heights: PackedFloat32Array,
	length: float,
	count: int,
	looped: bool,
	height_m: float,
	lift_m: float,
	foot: int,
	times: PackedFloat32Array,
	feet: PackedInt32Array
) -> void:
	var lowest: float = heights[0]
	var highest_index: int = 0
	for i: int in count + 1:
		lowest = minf(lowest, heights[i])
		if heights[i] > heights[highest_index]:
			highest_index = i
	var threshold: float = lowest + height_m
	# Boucle : départ au point le plus haut (pied levé) ; sinon : départ au début, levé seulement s'il est déjà haut.
	var start: int = highest_index if looped else 0
	var lifted: bool = heights[start] >= lowest + lift_m
	for k: int in count:
		var a: int = (start + k) % count if looped else k
		var b: int = a + 1
		var ha: float = heights[a]
		var hb: float = heights[b]
		if ha >= lowest + lift_m:
			lifted = true
		if lifted and ha > threshold and hb <= threshold:
			var fraction: float = (ha - threshold) / (ha - hb)
			var time: float = length * (float(a) + fraction) / float(count)
			times.append(fposmod(time, length) if looped else time)
			feet.append(foot)
			lifted = false


static func _sort_by_time(times: PackedFloat32Array, feet: PackedInt32Array) -> void:
	for i: int in range(1, times.size()):
		var t: float = times[i]
		var f: int = feet[i]
		var j: int = i - 1
		while j >= 0 and times[j] > t:
			times[j + 1] = times[j]
			feet[j + 1] = feet[j]
			j -= 1
		times[j + 1] = t
		feet[j + 1] = f
