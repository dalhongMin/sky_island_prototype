extends Node3D

## Day / sunset / night presentation.
##
## GameState owns which phase we are in and how far the blend has travelled;
## this node only turns that into sky colours, one directional light, ambient
## light, the island tint and the strength of the night glow.

const Palette := preload("res://scripts/art/palette.gd")

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $SunLight

## How much the night glow swells and fades, and how fast.
const GLOW_BREATH := 0.11
const GLOW_BREATH_SPEED := 1.05

var _env: Environment
var _sky_material: ShaderMaterial
var _presets: Array = []
var _island: Node3D
var _elapsed := 0.0


func _ready() -> void:
	Palette.ensure()
	_env = _world_environment.environment
	_sky_material = _env.sky.sky_material as ShaderMaterial
	_presets = [_day_preset(), _sunset_preset(), _night_preset()]
	_island = get_tree().get_first_node_in_group("island_world") as Node3D
	_apply(_presets[GameState.time_phase])


func _process(delta: float) -> void:
	_elapsed += delta
	var from: Dictionary = _presets[GameState.previous_phase]
	var to: Dictionary = _presets[GameState.time_phase]
	var t := smoothstep(0.0, 1.0, GameState.phase_blend)
	var blended := _mix(from, to, t)
	# Idle motion #4: the lanterns, crystals and plant glow breathe at night.
	var breath := 1.0 + sin(_elapsed * GLOW_BREATH_SPEED) * GLOW_BREATH
	blended["night"] = clampf(float(blended["night"]) * breath, 0.0, 1.0)
	_apply(blended)


func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in a.keys():
		var va = a[key]
		if va is Color:
			out[key] = (va as Color).lerp(b[key], t)
		elif va is Vector2:
			out[key] = (va as Vector2).lerp(b[key], t)
		else:
			out[key] = lerpf(float(va), float(b[key]), t)
	return out


func _apply(p: Dictionary) -> void:
	_sun.light_color = p["sun_color"]
	_sun.light_energy = p["sun_energy"]
	var angles: Vector2 = p["sun_angles"]
	_sun.rotation_degrees = Vector3(angles.x, angles.y, 0.0)

	_env.ambient_light_color = p["ambient_color"]
	_env.ambient_light_energy = p["ambient_energy"]

	if _sky_material != null:
		_sky_material.set_shader_parameter("top_color", p["sky_top"])
		_sky_material.set_shader_parameter("horizon_color", p["sky_horizon"])
		_sky_material.set_shader_parameter("glow_color", p["glow_color"])
		_sky_material.set_shader_parameter("glow_strength", p["glow_strength"])
		_sky_material.set_shader_parameter("glow_tightness", p["glow_tightness"])
		_sky_material.set_shader_parameter("star_amount", p["star_amount"])
		_sky_material.set_shader_parameter("moon_amount", p["moon_amount"])
		# Direction towards the light: a DirectionalLight3D shines along -Z.
		_sky_material.set_shader_parameter("sun_direction", _sun.global_transform.basis.z)

	Palette.apply_time(p["island_tint"], p["night"], p["cloud_tint"])
	if _island != null and _island.has_method("set_night"):
		_island.set_night(p["night"])


# --- presets ---------------------------------------------------------------
# Visual candidates, not final art direction.

func _day_preset() -> Dictionary:
	return {
		"sky_top": Color(0.27, 0.56, 0.86),
		"sky_horizon": Color(0.80, 0.90, 0.95),
		"glow_color": Color(1.0, 0.97, 0.88),
		"glow_strength": 0.35,
		"glow_tightness": 40.0,
		"star_amount": 0.0,
		# A pale daytime moon, mostly to give the empty upper sky one thing to
		# rest on. It is the same disc the night uses, just barely there.
		"moon_amount": 0.22,
		"sun_color": Color(1.0, 0.96, 0.86),
		"sun_energy": 1.35,
		"sun_angles": Vector2(-52.0, -28.0),
		"ambient_color": Color(0.56, 0.68, 0.82),
		"ambient_energy": 0.50,
		"island_tint": Color(1.0, 1.0, 1.0),
		"cloud_tint": Color(0.97, 0.97, 1.0),
		"night": 0.0,
	}


func _sunset_preset() -> Dictionary:
	return {
		"sky_top": Color(0.30, 0.28, 0.52),
		"sky_horizon": Color(0.99, 0.60, 0.36),
		"glow_color": Color(1.0, 0.66, 0.38),
		"glow_strength": 1.0,
		"glow_tightness": 10.0,
		"star_amount": 0.12,
		"moon_amount": 0.30,
		"sun_color": Color(1.0, 0.62, 0.36),
		"sun_energy": 1.15,
		"sun_angles": Vector2(-9.0, -84.0),
		"ambient_color": Color(0.52, 0.40, 0.46),
		"ambient_energy": 0.45,
		"island_tint": Color(1.06, 0.90, 0.82),
		"cloud_tint": Color(1.0, 0.74, 0.60),
		"night": 0.18,
	}


## The night is still deep blue, but the sky is lifted off black and the
## moonlight and sky ambient are strong enough to keep the terrain, the trees
## and the rock edges readable. The moon disc sits in the same part of the sky
## as the moonlight (same azimuth, lower in the frame) without being a light.
func _night_preset() -> Dictionary:
	return {
		"sky_top": Color(0.028, 0.055, 0.145),
		"sky_horizon": Color(0.080, 0.130, 0.280),
		"glow_color": Color(0.75, 0.82, 1.0),
		"glow_strength": 0.0,
		"glow_tightness": 90.0,
		"star_amount": 1.0,
		"moon_amount": 1.0,
		"sun_color": Color(0.62, 0.74, 1.0),
		"sun_energy": 0.56,
		"sun_angles": Vector2(-42.0, -164.0),
		"ambient_color": Color(0.17, 0.24, 0.46),
		"ambient_energy": 0.72,
		"island_tint": Color(0.78, 0.85, 1.05),
		"cloud_tint": Color(0.36, 0.42, 0.62),
		"night": 1.0,
	}
