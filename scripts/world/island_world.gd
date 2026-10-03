extends Node3D

## Builds and animates the floating island.
##
## The four growth stages are generated once at startup into separate groups;
## growing just reveals the next group with a short staggered pop-in, so
## nothing a player already saw ever disappears. This node owns no game state:
## it reacts to GameState signals and reads GameState.stage.

const MeshKit := preload("res://scripts/art/mesh_kit.gd")
const Palette := preload("res://scripts/art/palette.gd")

## Radius of the care hit area per stage, used by main.gd to tell an island
## drag apart from an empty-sky camera drag.
const CARE_RADIUS := [2.7, 4.1, 4.8, 5.4]

const BOB_HEIGHT := 0.11
const BOB_SPEED := 0.55

@onready var _island_root: Node3D = $IslandRoot
@onready var _growth_flash: OmniLight3D = $IslandRoot/GrowthFlash

var _stage_groups: Array[Node3D] = []
var _night_lights: Array[OmniLight3D] = []
var _rng := RandomNumberGenerator.new()
var _elapsed := 0.0
var _care_pulse := 0.0


func _ready() -> void:
	Palette.ensure()
	_rng.seed = 20261003
	for stage in 4:
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


func care_radius() -> float:
	return float(CARE_RADIUS[clampi(GameState.stage, 0, CARE_RADIUS.size() - 1)])


## Small squash so tapping or stroking the island feels answered, whether the
## input came from the HUD button or straight from the island.
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
	_reveal(stage, true)
	_flash()


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
# Stage 0 is a bare rock with a sapling; every later stage widens the
# silhouette with new ground chunks and adds a new kind of life.

func _build_stage_0(group: Node3D) -> void:
	_add_chunk(group, Vector2(0.0, 0.0), 2.3, 0.0, 3.2, 9, 1, Palette.rock, Palette.soil)
	_add_grass(group, Vector2(0.85, 0.55), 0.0, "grass_a")
	_add_grass(group, Vector2(-0.95, 0.35), 0.0, "grass_b")
	_add_grass(group, Vector2(0.15, -1.15), 0.0, "grass_a")
	_add_grass(group, Vector2(-0.35, -0.55), 0.0, "grass_b")
	_add_tree(group, Vector2(0.55, -0.15), 0.0, 0.42, false)
	_add_pebble(group, Vector2(-1.45, -0.85), 0.0, 0.55)
	_add_pebble(group, Vector2(1.5, 0.95), 0.0, 0.42)


func _build_stage_1(group: Node3D) -> void:
	# Soil and grass spread outwards: the bare core greens over and two new
	# shelves widen the silhouette either side of it.
	_add_ground_patch(group, Vector2(0.0, 0.0), 0.02, 2.1, 8, Palette.grass_top)
	_add_chunk(group, Vector2(-1.95, 0.7), 1.85, -0.12, 2.3, 9, 2, Palette.rock, Palette.grass_top)
	_add_chunk(group, Vector2(1.95, 0.45), 1.6, -0.2, 2.0, 8, 3, Palette.rock, Palette.grass_top)
	_add_tree(group, Vector2(1.9, 0.45), -0.2, 0.66, false)
	_add_tree(group, Vector2(-2.1, 0.95), -0.12, 0.5, false)
	_add_grass(group, Vector2(-1.4, 1.35), -0.12, "grass_c")
	_add_grass(group, Vector2(-2.5, 0.25), -0.12, "grass_a")
	_add_grass(group, Vector2(-1.75, -0.15), -0.12, "grass_b")
	_add_grass(group, Vector2(2.4, 1.0), -0.2, "grass_c")
	_add_grass(group, Vector2(1.35, -0.3), -0.2, "grass_a")
	_add_grass(group, Vector2(2.2, -0.45), -0.2, "grass_b")
	_add_pebble(group, Vector2(-2.6, 1.3), -0.12, 0.38)
	_add_pebble(group, Vector2(2.5, -0.1), -0.2, 0.33)
	_add_path_stone(group, Vector2(0.55, 0.75), 0.0)
	_add_path_stone(group, Vector2(-0.2, 0.95), 0.0)
	_add_path_stone(group, Vector2(-0.95, 1.0), -0.06)


func _build_stage_2(group: Node3D) -> void:
	# Flowers, a grown tree, lantern light and a path towards the front edge.
	_add_chunk(group, Vector2(0.3, -2.25), 1.95, -0.08, 2.5, 9, 4, Palette.rock, Palette.grass_top)
	_add_tree(group, Vector2(-1.85, 0.95), -0.12, 1.0, true)
	_add_tree(group, Vector2(0.35, -2.5), -0.08, 0.78, true)
	_add_path_stone(group, Vector2(0.45, -0.3), 0.0)
	_add_path_stone(group, Vector2(0.3, -1.1), 0.0)
	_add_path_stone(group, Vector2(0.2, -1.8), -0.05)
	_add_path_stone(group, Vector2(-0.35, -2.3), -0.08)
	_add_path_stone(group, Vector2(-1.0, -2.6), -0.08)
	_add_flower(group, Vector2(1.15, -1.75), -0.08, true)
	_add_flower(group, Vector2(1.45, -2.15), -0.08, false)
	_add_flower(group, Vector2(0.95, -2.5), -0.08, true)
	_add_flower(group, Vector2(-1.25, -1.85), -0.08, false)
	_add_flower(group, Vector2(-1.55, -2.35), -0.08, true)
	_add_flower(group, Vector2(-2.45, 1.75), -0.12, false)
	_add_flower(group, Vector2(-1.1, 1.45), -0.12, true)
	_add_grass(group, Vector2(1.3, -2.8), -0.08, "grass_c")
	_add_grass(group, Vector2(-0.6, -3.05), -0.08, "grass_a")
	_add_grass(group, Vector2(0.9, -1.25), 0.0, "grass_b")
	_add_lantern(group, Vector2(1.25, -1.2), 0.0)
	_add_lantern(group, Vector2(-1.3, -1.35), 0.0)


func _build_stage_3(group: Node3D) -> void:
	# A cliff shoulder rises and a pond settles into a lowered shelf.
	_add_chunk(group, Vector2(-2.45, 1.6), 1.45, 0.95, 1.7, 8, 5, Palette.cliff, Palette.grass_top)
	_add_chunk(group, Vector2(2.3, -1.5), 1.55, -0.45, 1.8, 9, 6, Palette.rock, Palette.soil)
	_add_water(group, Vector2(2.3, -1.5), -0.3, 1.15)
	_add_tree(group, Vector2(-2.6, 1.75), 0.95, 0.74, true)
	_add_tree(group, Vector2(2.95, -0.55), -0.45, 0.6, false)
	_add_grass(group, Vector2(-1.85, 1.95), 0.95, "grass_c")
	_add_grass(group, Vector2(-2.9, 1.0), 0.95, "grass_a")
	_add_grass(group, Vector2(1.45, -0.9), -0.45, "grass_b")
	_add_grass(group, Vector2(3.0, -2.2), -0.45, "grass_c")
	_add_flower(group, Vector2(-2.0, 1.25), 0.95, true)
	_add_flower(group, Vector2(-3.0, 1.85), 0.95, false)
	_add_pebble(group, Vector2(1.35, -2.3), -0.45, 0.45)
	_add_pebble(group, Vector2(3.25, -1.2), -0.45, 0.36)
	_add_crystal(group, Vector2(1.6, -1.95), -0.45, 1.15, true)
	_add_crystal(group, Vector2(3.1, -1.75), -0.45, 0.85, false)
	_add_crystal(group, Vector2(-1.95, 0.85), 0.95, 1.0, true)
	_add_lantern(group, Vector2(-2.85, 2.2), 0.95)


# --- spawners --------------------------------------------------------------

func _register(group: Node3D, node: Node3D) -> void:
	group.add_child(node)
	node.set_meta("base_scale", node.scale)
	node.set_meta("base_y", node.position.y)


func _add_chunk(group: Node3D, pos: Vector2, radius: float, top_y: float, depth: float,
		sides: int, seed_value: int, side_mat: Material, top_mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.chunk(radius, depth, sides, seed_value)
	mi.set_surface_override_material(0, side_mat)
	if mi.mesh.get_surface_count() > 1:
		mi.set_surface_override_material(1, top_mat)
	mi.position = Vector3(pos.x, top_y, pos.y)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	_register(group, mi)


func _add_tree(group: Node3D, pos: Vector2, y: float, scale_factor: float, three_tiers: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x, y, pos.y)
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

	_register(group, root)


func _add_grass(group: Node3D, pos: Vector2, y: float, mesh_key: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.get_mesh(mesh_key)
	mi.material_override = Palette.grass_blade
	mi.position = Vector3(pos.x, y, pos.y)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	mi.scale = Vector3.ONE * _rng.randf_range(0.85, 1.35)
	_register(group, mi)


func _add_flower(group: Node3D, pos: Vector2, y: float, warm: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x, y, pos.y)
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

	_register(group, root)


func _add_pebble(group: Node3D, pos: Vector2, y: float, scale_factor: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.get_mesh("pebble")
	mi.material_override = Palette.rock
	mi.position = Vector3(pos.x, y, pos.y)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	mi.scale = Vector3(1.0, _rng.randf_range(0.7, 1.0), 1.0) * scale_factor
	_register(group, mi)


func _add_path_stone(group: Node3D, pos: Vector2, y: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.get_mesh("path_stone")
	mi.material_override = Palette.stone
	mi.position = Vector3(pos.x, y + 0.01, pos.y)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	mi.scale = Vector3.ONE * _rng.randf_range(0.6, 0.95)
	_register(group, mi)


func _add_water(group: Node3D, pos: Vector2, y: float, radius: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.flat_disc(radius, 7)
	mi.material_override = Palette.water
	mi.position = Vector3(pos.x, y, pos.y)
	_register(group, mi)


## New ground cover laid over an older chunk, so growing also changes the
## colour of ground the player has already seen.
func _add_ground_patch(group: Node3D, pos: Vector2, y: float, radius: float,
		seed_value: int, material: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.flat_disc(radius, seed_value)
	mi.material_override = material
	mi.position = Vector3(pos.x, y, pos.y)
	mi.rotation.y = _rng.randf_range(0.0, TAU)
	_register(group, mi)


func _add_lantern(group: Node3D, pos: Vector2, y: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x, y, pos.y)
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

	_register(group, root)


func _add_crystal(group: Node3D, pos: Vector2, y: float, scale_factor: float, with_light: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x, y, pos.y)
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

	_register(group, root)
