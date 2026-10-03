extends Node3D

## Drifting low-poly clouds below and behind the island.
##
## Opaque geometry on purpose: no transparency, no particles, no shadow
## casting, so the cloud layer stays cheap on mobile. They are kept under the
## whale's flight band so they never hide the visit.

const MeshKit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/art/palette.gd")

const COUNT := 9
const X_LIMIT := 32.0

var _clouds: Array[Node3D] = []
var _speeds: PackedFloat32Array = PackedFloat32Array()
var _elapsed := 0.0


func _ready() -> void:
	Palette.ensure()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in COUNT:
		var cloud := Node3D.new()
		cloud.name = "Cloud%d" % i
		var puffs := rng.randi_range(2, 3)
		for p in puffs:
			var mi := MeshInstance3D.new()
			mi.mesh = MeshKit.get_mesh("cloud_puff_a" if (p + i) % 2 == 0 else "cloud_puff_b")
			mi.material_override = Palette.cloud
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(
				rng.randf_range(-0.85, 0.85),
				rng.randf_range(-0.10, 0.10),
				rng.randf_range(-0.5, 0.5))
			mi.scale = Vector3(
				rng.randf_range(0.8, 1.4),
				rng.randf_range(0.45, 0.8),
				rng.randf_range(0.8, 1.3))
			mi.rotation.y = rng.randf_range(0.0, TAU)
			cloud.add_child(mi)
		cloud.position = Vector3(
			rng.randf_range(-X_LIMIT, X_LIMIT),
			rng.randf_range(-6.0, 2.0),
			rng.randf_range(-26.0, -10.0))
		cloud.scale = Vector3.ONE * rng.randf_range(1.6, 3.4)
		add_child(cloud)
		_clouds.append(cloud)
		_speeds.append(rng.randf_range(0.22, 0.65))


func _process(delta: float) -> void:
	# Idle motion #2: a slow one-way drift with a little vertical breathing.
	_elapsed += delta
	for i in _clouds.size():
		var cloud := _clouds[i]
		cloud.position.x += _speeds[i] * delta
		if cloud.position.x > X_LIMIT:
			cloud.position.x = -X_LIMIT
		cloud.position.y += sin(_elapsed * 0.3 + float(i)) * delta * 0.08
