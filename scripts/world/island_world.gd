extends Node3D

## Builds and animates the floating island.
##
## The island body is one closed shell per growth stage (scripts/art/
## island_shell.gd), not a stack of chunks: at any moment exactly one shell is
## visible. Growing swaps in the next, larger shell starting at the previous
## stage's outline and expanding outwards, so the player watches the coastline
## push out rather than a second plate appearing above the first.
##
## Props are additive the way they always were: all four stage groups are built
## at startup and growing reveals the next with a staggered pop-in, so nothing
## a player already saw ever disappears. Every prop goes through
## IslandShell.plant_point() — which keeps it out of the rim fold and off any
## ground a later stage will fold away — and then takes its height from
## IslandShell.surface_height(), the triangle it is actually standing on. That
## is why the raised shoulder and the pond read as contours of the one surface
## instead of extra islands, and why growing never leaves a prop hanging.
##
## This node owns no game state: it reacts to GameState signals and reads
## GameState.stage.

const MeshKit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/art/palette.gd")
const IslandShell := preload("res://scripts/art/island_shell.gd")

## Taps are forgiven this far past the real coastline.
const CARE_MARGIN := 1.08

const BOB_HEIGHT := 0.11
const BOB_SPEED := 0.55

## How long the new coastline takes to push out, and how flat the shell starts.
const GROW_TIME := 0.9
const GROW_SQUASH := 0.70

@onready var _island_root: Node3D = $IslandRoot
@onready var _growth_flash: OmniLight3D = $IslandRoot/GrowthFlash

var _shell_root: Node3D
var _shells: Array[MeshInstance3D] = []
var _stage_groups: Array[Node3D] = []
var _night_lights: Array[OmniLight3D] = []
var _rng := RandomNumberGenerator.new()
var _elapsed := 0.0
var _care_pulse := 0.0
## The stage currently being authored, so spawners can sample the right ground.
var _stage := 0


func _ready() -> void:
	Palette.ensure()
	_rng.seed = 20261003

	_shell_root = Node3D.new()
	_shell_root.name = "Shells"
	_island_root.add_child(_shell_root)
	_build_shells()

	for stage in IslandShell.STAGE_COUNT:
		var group := Node3D.new()
		group.name = "Stage%d" % stage
		group.visible = false
		_island_root.add_child(group)
		_stage_groups.append(group)
	_build_stage_0(_stage_groups[0])
	_build_stage_1(_stage_groups[1])
	_build_stage_2(_stage_groups[2])
	_build_stage_3(_stage_groups[3])

	GameState.growth_started.connect(_on_growth_started)
	GameState.care_applied.connect(_on_care_applied)
	for stage in range(GameState.stage + 1):
		_reveal(stage, false)
	_show_shell(GameState.stage, false)


func _process(delta: float) -> void:
	_elapsed += delta
	# Idle motion #1: the island breathes on its invisible current.
	_island_root.position.y = sin(_elapsed * BOB_SPEED) * BOB_HEIGHT
	_island_root.rotation.z = sin(_elapsed * 0.37) * 0.006
	_island_root.rotation.x = cos(_elapsed * 0.29) * 0.005
	if _care_pulse > 0.0:
		_care_pulse = maxf(_care_pulse - delta * 2.6, 0.0)
		var eased := sin(_care_pulse * PI)
		_island_root.scale = Vector3.ONE * (1.0 + eased * 0.012)


## True when an XZ point is on (or just off) the current coastline. main.gd
## uses it to tell an island tap from a tap on empty sky.
func contains_point(p: Vector2) -> bool:
	var angle := atan2(p.y, p.x)
	return p.length() <= IslandShell.perimeter_radius(GameState.stage, angle) * CARE_MARGIN


## Small squash so tapping the island feels answered, whether the input came
## from the HUD button or straight from the island.
func care_feedback(strength: float) -> void:
	_care_pulse = maxf(_care_pulse, clampf(strength, 0.0, 1.0))


func _on_care_applied(accepted: bool) -> void:
	care_feedback(1.0 if accepted else 0.35)


## Driven by sky_cycle.gd: 0 at noon, 1 at full night.
func set_night(amount: float) -> void:
	for light in _night_lights:
		light.light_energy = float(light.get_meta("night_energy")) * amount
		light.visible = amount > 0.03


# --- growth ----------------------------------------------------------------

func _on_growth_started(stage: int) -> void:
	_show_shell(stage, true)
	_reveal(stage, true)
	_flash()


func _build_shells() -> void:
	for stage in IslandShell.STAGE_COUNT:
		var shell := MeshInstance3D.new()
		shell.name = "Shell%d" % stage
		shell.mesh = IslandShell.build(stage)
		shell.set_surface_override_material(0, Palette.rock)
		# Bare soil until the first growth greens the whole island over.
		shell.set_surface_override_material(1, Palette.soil if stage == 0 else Palette.grass_top)
		shell.visible = false
		_shell_root.add_child(shell)
		_shells.append(shell)


## Exactly one shell is ever visible. When it changes it starts at the previous
## stage's outline — scaled so the two silhouettes coincide at the moment of
## the swap — and grows out from there, which is the land the player gains.
func _show_shell(stage: int, animate: bool) -> void:
	stage = IslandShell.clamp_stage(stage)
	for i in _shells.size():
		_shells[i].visible = i == stage
	var shell := _shells[stage]
	shell.scale = Vector3.ONE
	if not animate or stage == 0:
		return
	var start := IslandShell.mean_radius(stage - 1) / IslandShell.mean_radius(stage)
	shell.scale = Vector3(start, start * GROW_SQUASH, start)
	create_tween().tween_property(shell, "scale", Vector3.ONE, GROW_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _reveal(stage: int, animate: bool) -> void:
	if stage < 0 or stage >= _stage_groups.size():
		return
	var group := _stage_groups[stage]
	group.visible = true
	var index := 0
	for child in group.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var base_scale: Vector3 = node.get_meta("base_scale", Vector3.ONE)
		var base_y: float = float(node.get_meta("base_y", node.position.y))
		if not animate:
			node.scale = base_scale
			node.position.y = base_y
			continue
		var delay := minf(0.045 * float(index), 0.55)
		node.scale = base_scale * 0.001
		node.position.y = base_y - 0.55
		var tween := create_tween().set_parallel(true)
		tween.tween_property(node, "scale", base_scale, 0.7) \
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(node, "position:y", base_y, 0.8) \
			.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		index += 1


func _flash() -> void:
	_growth_flash.light_energy = 0.0
	_growth_flash.visible = true
	var tween := create_tween()
	tween.tween_property(_growth_flash, "light_energy", 3.2, 0.18).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_growth_flash, "light_energy", 0.0, 0.75).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: _growth_flash.visible = false)


# --- stage contents --------------------------------------------------------
# Each stage plants on the land it just gained. Positions given as polar
# (bearing, fraction of the perimeter) follow the organic coastline; Cartesian
# positions are used where a prop belongs to a named contour instead.
#
# Stages 0-2 stay clear of the stage 3 shoulder and pond, which is why nothing
# before stage 3 is planted outside IslandShell's feature gates.

func _build_stage_0(group: Node3D) -> void:
	_stage = 0
	_add_tree(group, Vector2(0.45, -0.25), 0.42, false)
	_add_grass(group, Vector2(0.95, 0.60), "grass_a")
	_add_grass(group, Vector2(-1.00, 0.35), "grass_b")
	_add_grass(group, Vector2(0.10, -1.15), "grass_a")
	_add_grass(group, Vector2(-0.40, -0.60), "grass_b")
	_add_pebble(group, Vector2(-1.25, -0.70), 0.55)
	_add_pebble(group, Vector2(1.10, 0.80), 0.42)


func _build_stage_1(group: Node3D) -> void:
	# The coastline pushes out on two bearings and the bare soil greens over.
	_stage = 1
	_add_tree(group, _polar(0.30, 0.68), 0.62, false)
	_add_tree(group, _polar(2.65, 0.70), 0.52, false)
	# Nothing here reaches into the north west, which is where the stage 3
	# headland will rise.
	_add_grass(group, _polar(1.55, 0.76), "grass_c")
	_add_grass(group, _polar(3.05, 0.78), "grass_a")
	_add_grass(group, _polar(3.55, 0.64), "grass_b")
	_add_grass(group, _polar(0.70, 0.74), "grass_c")
	_add_grass(group, _polar(5.70, 0.52), "grass_a")
	_add_grass(group, _polar(5.35, 0.72), "grass_b")
	_add_pebble(group, _polar(1.15, 0.80), 0.38)
	_add_pebble(group, _polar(6.05, 0.76), 0.33)
	_add_path_stone(group, Vector2(0.55, 0.80))
	_add_path_stone(group, Vector2(-0.15, 0.95))
	_add_path_stone(group, Vector2(-0.85, 1.05))


func _build_stage_2(group: Node3D) -> void:
	# Flowers, grown trees, lantern light and a path out to the front shore.
	_stage = 2
	_add_tree(group, Vector2(-1.45, 0.95), 0.95, true)
	_add_tree(group, _polar(4.55, 0.74), 0.75, true)
	_add_tree(group, _polar(0.40, 0.78), 0.62, false)
	_add_path_stone(group, Vector2(0.50, -0.35))
	_add_path_stone(group, Vector2(0.35, -1.10))
	_add_path_stone(group, Vector2(0.20, -1.85))
	_add_path_stone(group, Vector2(-0.40, -2.30))
	_add_path_stone(group, Vector2(-1.00, -2.25))
	_add_flower(group, Vector2(-1.30, -1.90), false)
	_add_flower(group, Vector2(-1.55, -2.05), true)
	_add_flower(group, Vector2(-0.75, -2.45), false)
	_add_flower(group, Vector2(1.90, -0.25), true)
	_add_flower(group, Vector2(-1.05, 1.55), true)
	_add_flower(group, Vector2(1.55, 0.95), false)
	_add_grass(group, Vector2(0.65, -2.35), "grass_c")
	_add_grass(group, Vector2(-0.45, -2.40), "grass_a")
	_add_grass(group, Vector2(0.95, -1.15), "grass_b")
	_add_lantern(group, Vector2(1.15, -1.05))
	_add_lantern(group, Vector2(-1.25, -1.30))


func _build_stage_3(group: Node3D) -> void:
	# The last coastline carries two contours: a raised shoulder to the north
	# west and a pond settled into a basin to the south east. Both are folds of
	# the same surface, so everything here is placed on it the same way.
	_stage = 3
	_add_water(group, IslandShell.POND_CENTER)
	_add_tree(group, Vector2(-2.45, 1.95), 0.74, true)
	_add_tree(group, Vector2(2.85, -0.60), 0.58, false)
	_add_grass(group, Vector2(-1.95, 2.15), "grass_c")
	_add_grass(group, Vector2(-2.95, 1.30), "grass_a")
	_add_grass(group, Vector2(1.35, -0.85), "grass_b")
	_add_grass(group, Vector2(2.55, -2.10), "grass_c")
	_add_flower(group, Vector2(-2.10, 1.45), true)
	_add_flower(group, Vector2(-2.80, 1.95), false)
	_add_flower(group, Vector2(-1.75, 1.35), false)
	_add_pebble(group, Vector2(1.40, -2.35), 0.45)
	_add_pebble(group, Vector2(2.95, -1.20), 0.36)
	_add_crystal(group, Vector2(1.25, -2.55), 1.15, true)
	_add_crystal(group, Vector2(2.35, -2.55), 0.85, false)
	_add_crystal(group, Vector2(-2.05, 1.15), 1.00, true)
	_add_lantern(group, Vector2(-1.95, 2.45))


# --- spawners --------------------------------------------------------------

## A point `fraction` of the way out to the coastline of the stage being built.
func _polar(angle: float, fraction: float) -> Vector2:
	return IslandShell.polar(_stage, angle, fraction)


## Where an authored position actually ends up. Every spawner starts with this,
## so no prop can be planted in the rim fold or on ground a later stage folds
## away; see IslandShell.plant_point().
func _plant(p: Vector2) -> Vector2:
	return IslandShell.plant_point(_stage, p)


## The drawn surface, not the design contour: a prop sits on the facet it is
## standing on. Inside PLANT_LIMIT the two agree to a few millimetres, and
## tests/prototype_test.gd checks props against both.
func _ground(p: Vector2) -> float:
	return IslandShell.surface_height(_stage, p)


## Records the pose the growth tween returns to, plus the ground the prop was
## placed on, which tests/prototype_test.gd checks against the real surface.
func _register(group: Node3D, node: Node3D, p: Vector2) -> void:
	group.add_child(node)
	node.set_meta("base_scale", node.scale)
	node.set_meta("base_y", node.position.y)
	node.set_meta("ground_stage", _stage)
	node.set_meta("ground_y", _ground(p))


func _add_tree(group: Node3D, pos: Vector2, scale_factor: float, three_tiers: bool) -> void:
	pos = _plant(pos)
	var root := Node3D.new()
	root.position = Vector3(pos.x, _ground(pos), pos.y)
	root.rotation.y = _rng.randf_range(0.0, TAU)
	root.scale = Vector3.ONE * scale_factor

	var trunk := MeshInstance3D.new()
	trunk.mesh = MeshKit.get_mesh("trunk")
	trunk.material_override = Palette.trunk
	trunk.scale = Vector3(1.0, 1.15, 1.0)
	root.add_child(trunk)

	var low := MeshInstance3D.new()
	low.mesh = MeshKit.get_mesh("leaf_low")
	low.material_override = Palette.leaf_dark
	low.position.y = 0.52
	root.add_child(low)

	var mid := MeshInstance3D.new()
	mid.mesh = MeshKit.get_mesh("leaf_mid")
	mid.material_override = Palette.leaf_light
	mid.position.y = 1.0
	mid.rotation.y = 0.4
	root.add_child(mid)

	if three_tiers:
		var top := MeshInstance3D.new()
		top.mesh = MeshKit.get_mesh("leaf_top")
		top.material_override = Palette.leaf_light
		top.position.y = 1.42
		top.rotation.y = -0.6
		root.add_child(top)

	_register(group, root, pos)


func _add_grass(group: Node3D, pos: Vector2, mesh_key: String) -> void:
	pos = _plant(pos)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.get_mesh(mesh_key)
	mi.material_override = Palette.grass_blade
	mi.position = Vector3(pos.x, _ground(pos), pos.y)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	mi.scale = Vector3.ONE * _rng.randf_range(0.85, 1.35)
	_register(group, mi, pos)


func _add_flower(group: Node3D, pos: Vector2, warm: bool) -> void:
	pos = _plant(pos)
	var root := Node3D.new()
	root.position = Vector3(pos.x, _ground(pos), pos.y)
	root.rotation.y = _rng.randf_range(0.0, TAU)
	root.scale = Vector3.ONE * _rng.randf_range(0.9, 1.25)

	var stem := MeshInstance3D.new()
	stem.mesh = MeshKit.get_mesh("flower_stem")
	stem.material_override = Palette.leaf_dark
	root.add_child(stem)

	var head := MeshInstance3D.new()
	head.mesh = MeshKit.get_mesh("flower_head")
	head.material_override = Palette.flower_warm if warm else Palette.flower_cool
	head.position.y = 0.24
	root.add_child(head)

	_register(group, root, pos)


func _add_pebble(group: Node3D, pos: Vector2, scale_factor: float) -> void:
	pos = _plant(pos)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.get_mesh("pebble")
	mi.material_override = Palette.rock
	mi.position = Vector3(pos.x, _ground(pos), pos.y)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	mi.scale = Vector3(1.0, _rng.randf_range(0.7, 1.0), 1.0) * scale_factor
	_register(group, mi, pos)


func _add_path_stone(group: Node3D, pos: Vector2) -> void:
	pos = _plant(pos)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.get_mesh("path_stone")
	mi.material_override = Palette.stone
	mi.position = Vector3(pos.x, _ground(pos) + 0.01, pos.y)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	mi.scale = Vector3.ONE * _rng.randf_range(0.6, 0.95)
	_register(group, mi, pos)


## The pond surface. Its level and radius both come from the basin contour, so
## the water always sits inside its own shoreline.
func _add_water(group: Node3D, pos: Vector2) -> void:
	var radius := IslandShell.pond_radius()
	var mi := MeshInstance3D.new()
	mi.name = "Pond"
	mi.mesh = MeshKit.flat_disc(radius / 1.12, 7)
	mi.material_override = Palette.water
	# flat_disc is 0.07 tall, so the top face lands exactly on the water line.
	mi.position = Vector3(pos.x, IslandShell.pond_water_y() - 0.07, pos.y)
	_register(group, mi, pos)
	# The only prop that deliberately does not sit on the ground.
	mi.set_meta("water_surface", true)


func _add_lantern(group: Node3D, pos: Vector2) -> void:
	pos = _plant(pos)
	var root := Node3D.new()
	root.position = Vector3(pos.x, _ground(pos), pos.y)
	root.rotation.y = _rng.randf_range(0.0, TAU)

	var post := MeshInstance3D.new()
	post.mesh = MeshKit.get_mesh("lantern_post")
	post.material_override = Palette.lantern_post
	root.add_child(post)

	var globe := MeshInstance3D.new()
	globe.mesh = MeshKit.get_mesh("lantern_globe")
	globe.material_override = Palette.lantern_glow
	globe.position.y = 0.56
	root.add_child(globe)

	var light := OmniLight3D.new()
	light.position.y = 0.72
	light.light_color = Color(1.0, 0.76, 0.45)
	light.omni_range = 4.2
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.light_energy = 0.0
	light.visible = false
	light.set_meta("night_energy", 1.7)
	root.add_child(light)
	_night_lights.append(light)

	_register(group, root, pos)


func _add_crystal(group: Node3D, pos: Vector2, scale_factor: float, with_light: bool) -> void:
	pos = _plant(pos)
	var root := Node3D.new()
	root.position = Vector3(pos.x, _ground(pos), pos.y)
	root.rotation = Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf_range(0.0, TAU), _rng.randf_range(-0.12, 0.12))
	root.scale = Vector3.ONE * scale_factor

	var shard := MeshInstance3D.new()
	shard.mesh = MeshKit.get_mesh("crystal")
	shard.material_override = Palette.crystal
	root.add_child(shard)

	if with_light:
		var light := OmniLight3D.new()
		light.position.y = 0.4
		light.light_color = Color(0.52, 0.80, 1.0)
		light.omni_range = 3.6
		light.omni_attenuation = 1.6
		light.shadow_enabled = false
		light.light_energy = 0.0
		light.visible = false
		light.set_meta("night_energy", 1.2)
		root.add_child(light)
		_night_lights.append(light)

	_register(group, root, pos)
