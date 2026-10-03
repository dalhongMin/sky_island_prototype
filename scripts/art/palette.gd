extends RefCounted

## The whole prototype's material set, built once and shared by every
## MeshInstance3D. Limited palette on purpose: warm greens and browns for day,
## a cool blue shift plus a few emissive accents for night.
##
## Static only — `Palette.ensure()` then `Palette.grass`, no instances.

const FOLIAGE_SHADER := preload("res://assets/shaders/foliage_sway.gdshader")

static var rock: StandardMaterial3D
static var soil: StandardMaterial3D
static var grass_top: StandardMaterial3D
static var cliff: StandardMaterial3D
static var trunk: StandardMaterial3D
static var stone: StandardMaterial3D
static var water: StandardMaterial3D
static var cloud: StandardMaterial3D
static var lantern_post: StandardMaterial3D
static var lantern_glow: StandardMaterial3D
static var crystal: StandardMaterial3D
static var whale_body: StandardMaterial3D
static var whale_fin: StandardMaterial3D
static var whale_mark: StandardMaterial3D
static var whale_eye: StandardMaterial3D

static var grass_blade: ShaderMaterial
static var leaf_dark: ShaderMaterial
static var leaf_light: ShaderMaterial
static var flower_warm: ShaderMaterial
static var flower_cool: ShaderMaterial

static var _built := false
## [material, base albedo] for every solid that follows the time-of-day tint.
static var _tinted: Array = []
## [material, base albedo] for every foliage shader material.
static var _foliage: Array = []
## [material, emission energy at full night]
static var _emissive: Array = []


static func ensure() -> void:
	if _built:
		return
	_built = true

	# The rock and soil are a shade lighter than a daylight reading would want,
	# because the undersides are the first thing to go black once night falls.
	rock = _solid(Color(0.45, 0.40, 0.38))
	soil = _solid(Color(0.48, 0.34, 0.25))
	grass_top = _solid(Color(0.36, 0.55, 0.29))
	cliff = _solid(Color(0.48, 0.44, 0.42))
	trunk = _solid(Color(0.33, 0.24, 0.19))
	stone = _solid(Color(0.56, 0.54, 0.50))
	cloud = _solid(Color(0.95, 0.95, 0.98))

	water = _solid(Color(0.21, 0.52, 0.60), 0.25)
	water.metallic = 0.25
	_make_emissive(water, Color(0.30, 0.65, 0.85), 0.35)

	lantern_post = _solid(Color(0.27, 0.21, 0.17))
	lantern_glow = _solid(Color(0.98, 0.80, 0.50))
	_make_emissive(lantern_glow, Color(1.0, 0.74, 0.38), 2.4)

	crystal = _solid(Color(0.55, 0.80, 0.95), 0.4)
	_make_emissive(crystal, Color(0.45, 0.80, 1.0), 2.0)

	# The whale only ever flies at night, so its materials skip the day/night
	# tint: they are authored for the one sky they are ever seen against. Pale
	# fins against a mid-blue body keep the flippers and the fluke apart from
	# the silhouette, and a little emission stops the whole animal from sinking
	# into the dark sky.
	whale_body = _untinted(Color(0.28, 0.37, 0.63))
	_make_emissive(whale_body, Color(0.18, 0.28, 0.56), 0.45)
	whale_fin = _untinted(Color(0.47, 0.58, 0.84))
	whale_fin.cull_mode = BaseMaterial3D.CULL_DISABLED
	_make_emissive(whale_fin, Color(0.30, 0.42, 0.70), 0.60)
	whale_eye = _untinted(Color(0.88, 0.93, 1.0))
	_make_emissive(whale_eye, Color(0.80, 0.90, 1.0), 1.6)
	whale_mark = _untinted(Color(0.74, 0.90, 1.0))
	whale_mark.emission_enabled = true
	whale_mark.emission = Color(0.66, 0.88, 1.0)
	whale_mark.emission_energy_multiplier = 3.0

	grass_blade = _foliage_material(Color(0.46, 0.68, 0.33), 0.16, 1.3)
	leaf_dark = _foliage_material(Color(0.24, 0.49, 0.33), 0.05, 0.7)
	leaf_light = _foliage_material(Color(0.35, 0.62, 0.36), 0.06, 0.8)
	flower_warm = _foliage_material(Color(0.95, 0.72, 0.33), 0.10, 1.1)
	flower_cool = _foliage_material(Color(0.90, 0.45, 0.60), 0.10, 1.1)


## Called every frame by sky_cycle.gd with the blended time-of-day values.
static func apply_time(tint: Color, night: float, cloud_tint: Color) -> void:
	ensure()
	for entry in _tinted:
		var mat: StandardMaterial3D = entry[0]
		var base: Color = entry[1]
		mat.albedo_color = base * tint
	for entry in _foliage:
		var mat: ShaderMaterial = entry[0]
		mat.set_shader_parameter("tint", tint)
		mat.set_shader_parameter("emission_strength", night * 0.10)
	for entry in _emissive:
		var mat: StandardMaterial3D = entry[0]
		mat.emission_energy_multiplier = float(entry[1]) * night
	cloud.albedo_color = cloud_tint


# --- internals -------------------------------------------------------------

static func _solid(color: Color, roughness: float = 1.0) -> StandardMaterial3D:
	var m := _untinted(color, roughness)
	_tinted.append([m, color])
	return m


## Same material, but it keeps its authored colour through the whole cycle.
static func _untinted(color: Color, roughness: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	return m


static func _make_emissive(m: StandardMaterial3D, emission: Color, night_energy: float) -> void:
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = 0.0
	_emissive.append([m, night_energy])


static func _foliage_material(color: Color, sway: float, speed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("tint", Color.WHITE)
	m.set_shader_parameter("emission_color", Color(0.45, 0.85, 0.70))
	m.set_shader_parameter("emission_strength", 0.0)
	m.set_shader_parameter("sway_strength", sway)
	m.set_shader_parameter("sway_speed", speed)
	_foliage.append([m, color])
	return m
