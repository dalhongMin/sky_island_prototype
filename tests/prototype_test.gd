extends SceneTree

## Headless checks for the parts of this prototype that can break silently.
##
## Run:
##   Godot --headless --path <project> --script res://tests/prototype_test.gd
##
## Scope on purpose: the authoritative state transitions, the sky whale gate,
## and the mesh winding convention all the generated geometry depends on.
## Framing, colour and "does it look good" are not testable here.

const SkyIslandState := preload("res://scripts/state/sky_island_state.gd")
const LowPoly := preload("res://scripts/art/low_poly.gd")
const MeshKit := preload("res://scripts/art/mesh_kit.gd")
const WhaleMesh := preload("res://scripts/art/whale_mesh.gd")

## Where the HUD bars end, as a fraction of the viewport height. Read off
## scenes/hud.tscn: the top bar is about 0.13 tall and the bottom bar starts
## at about 0.84; the diorama has to stay between them.
const HUD_TOP := 0.13
const HUD_BOTTOM := 0.84
## How far the look-around can swing (camera_rig.gd MAX_YAW_DEGREES).
const LOOK_YAW := 10.0

var _failures: Array = []
var _checks := 0
var _mesh_points_cache: Dictionary = {}

## The scene part of the suite runs across real frames (see _process below),
## because a node added during _initialize() only gets _ready() on the next
## iteration of the main loop.
var _scene_phase := 0
var _main: Node
var _state: Node
var _elapsed := 0.0


func _initialize() -> void:
	print("sky island prototype — headless checks")

	print("\n[state] care and growth")
	_test_care_and_growth()

	print("\n[state] stage cap")
	_test_stage_cap()

	print("\n[state] time of day")
	_test_time_of_day()

	print("\n[state] sky whale gate")
	_test_whale_gate()

	print("\n[art] winding convention")
	_test_winding()

	print("\n[art] generated meshes")
	_test_meshes()

	print("\n[art] shaders")
	_test_shaders()

	print("\n[scene] main scene smoke test")
	_start_scene_test()


# --- state -----------------------------------------------------------------

func _test_care_and_growth() -> void:
	var state := SkyIslandState.new()
	_check(state.stage == 0, "starts at stage 0")
	_check(is_zero_approx(state.care_ratio()), "starts with no care progress")
	_check(not state.is_growing(), "starts idle")

	_check(state.add_care(1.0), "first tap is accepted")
	_check_close(state.care_ratio(), 1.0 / SkyIslandState.CARE_PER_STAGE, "one tap is one third of a stage")
	state.add_care(1.0)
	_check(state.stage == 0, "two taps are not enough to grow")

	state.add_care(1.0)
	_check(state.stage == 1, "the third tap grows the island")
	_check(is_zero_approx(state.care_ratio()), "progress resets after growing")
	_check(state.is_growing(), "the growth reveal locks input")
	_check(not state.add_care(1.0), "care is ignored during the reveal")
	_check(state.stage == 1, "ignored care does not skip a stage")

	state.advance(SkyIslandState.GROWTH_TIME + 0.01)
	_check(not state.is_growing(), "the reveal finishes on its own")

	# Reaching the final stage has to stay a "few seconds" affair.
	var taps := 3
	var seconds := SkyIslandState.GROWTH_TIME
	while state.stage < SkyIslandState.MAX_STAGE and taps < 40:
		if state.add_care(1.0):
			taps += 1
		else:
			state.advance(0.1)
			seconds += 0.1
	_check(state.stage == SkyIslandState.MAX_STAGE, "the island reaches the final stage")
	_check(taps <= 12, "stage 3 costs at most 12 taps (got %d)" % taps)
	_check(seconds < 8.0, "stage 3 is reachable within a few seconds (%.1f s of locks)" % seconds)
	state.free()


func _test_stage_cap() -> void:
	var state := SkyIslandState.new()
	state.force_stage(SkyIslandState.MAX_STAGE)
	state.advance(SkyIslandState.GROWTH_TIME + 0.01)
	_check(state.stage == SkyIslandState.MAX_STAGE, "force_stage reaches the final stage")
	_check(state.is_fully_grown(), "the final stage reports fully grown")
	_check(not state.add_care(5.0), "care is refused once fully grown")
	_check(state.stage == SkyIslandState.MAX_STAGE, "the stage never passes the maximum")
	state.force_stage(99)
	_check(state.stage == SkyIslandState.MAX_STAGE, "force_stage clamps out of range values")
	state.free()


func _test_time_of_day() -> void:
	var state := SkyIslandState.new()
	_check(state.time_phase == SkyIslandState.TimePhase.DAY, "starts in day")
	_check(state.phase_blend >= 1.0, "starts with no pending blend")

	state.set_time_phase(SkyIslandState.TimePhase.NIGHT, true)
	_check(state.time_phase == SkyIslandState.TimePhase.NIGHT, "the night button switches phase")
	_check(state.previous_phase == SkyIslandState.TimePhase.DAY, "the blend starts from day")
	_check(is_zero_approx(state.phase_blend), "the blend restarts at zero")
	_check(not state.auto_cycle, "a manual switch stops the automatic cycle")

	state.advance(SkyIslandState.PHASE_BLEND_TIME * 0.5)
	_check_close(state.phase_blend, 0.5, "the blend advances with time")
	state.advance(SkyIslandState.PHASE_BLEND_TIME)
	_check(state.phase_blend >= 1.0, "the blend settles at one")

	state.advance(1000.0)
	_check(state.time_phase == SkyIslandState.TimePhase.NIGHT, "no automatic cycling while it is off")

	state.auto_cycle = true
	state.advance(float(SkyIslandState.PHASE_HOLD[SkyIslandState.TimePhase.NIGHT]) + 0.1)
	_check(state.time_phase == SkyIslandState.TimePhase.DAY, "night cycles back to day automatically")
	_check(state.auto_cycle, "automatic cycling survives its own switch")
	state.free()


func _test_whale_gate() -> void:
	var state := SkyIslandState.new()
	_check(not state.can_whale_visit(), "no whale on a small island by day")

	state.set_time_phase(SkyIslandState.TimePhase.NIGHT, true)
	state.advance(SkyIslandState.PHASE_BLEND_TIME)
	_check(not state.can_whale_visit(), "no whale at night before the island has grown")
	state.advance(30.0)
	_check(not state.whale_active, "waiting at night alone never starts a visit")

	state.set_time_phase(SkyIslandState.TimePhase.DAY, true)
	state.force_stage(SkyIslandState.MAX_STAGE)
	state.advance(SkyIslandState.GROWTH_TIME + 0.01)
	_check(not state.can_whale_visit(), "no whale on a grown island in daylight")
	state.advance(30.0)
	_check(not state.whale_active, "daylight never starts a visit")

	state.set_time_phase(SkyIslandState.TimePhase.NIGHT, true)
	_check(state.can_whale_visit(), "a grown island at night opens the gate")

	var waited := 0.0
	while not state.whale_active and waited < 5.0:
		state.advance(0.1)
		waited += 0.1
	_check(state.whale_active, "the first visit starts (waited %.1f s)" % waited)
	_check(waited <= 5.0, "the first visit starts within 5 seconds")
	_check(state.first_whale_seen, "the first visit is remembered")
	_check(not state.can_whale_visit(), "the gate closes while a whale is in the air")

	var progress_start := state.whale_progress()
	state.advance(SkyIslandState.WHALE_VISIT_TIME * 0.5)
	var progress_mid := state.whale_progress()
	_check(progress_mid > progress_start, "the visit progress moves forward")
	_check(progress_mid < 1.0, "the visit is still running halfway through")

	state.advance(SkyIslandState.WHALE_VISIT_TIME)
	_check(not state.whale_active, "the visit ends")
	_check(is_zero_approx(state.whale_progress()), "the progress resets after the visit")

	# A visit that is still pending must be called off if the sky brightens.
	state.advance(1.0)
	_check(state.whale_wait_left() > 0.0, "a repeat visit is scheduled at night")
	state.set_time_phase(SkyIslandState.TimePhase.DAY, true)
	state.advance(0.1)
	_check(state.whale_wait_left() < 0.0, "leaving the night cancels the pending visit")
	state.free()


# --- art -------------------------------------------------------------------

## Reads the winding convention off one of the engine's own primitives and
## checks the generated geometry agrees, so the island can't silently render
## inside out.
func _test_winding() -> void:
	var box := BoxMesh.new()
	var box_sign := _winding_sign(box.get_mesh_arrays())
	_check(box_sign != 0, "BoxMesh exposes a usable winding (sign %d)" % box_sign)

	var island: ArrayMesh = MeshKit.chunk(2.3, 3.2, 9, 1)
	var island_sign := _winding_sign(island.surface_get_arrays(0))
	_check(island_sign == box_sign,
		"the island chunk uses the engine winding (chunk %d vs engine %d)" % [island_sign, box_sign])

	var whale_sign := _winding_sign(WhaleMesh.body().surface_get_arrays(0))
	_check(whale_sign == box_sign,
		"the whale body uses the engine winding (whale %d vs engine %d)" % [whale_sign, box_sign])

	var outward := _outward_ratio(MeshKit.get_mesh("pebble"))
	_check(outward > 0.9, "pebble normals point outwards (%.2f of faces)" % outward)
	var cloud_outward := _outward_ratio(MeshKit.get_mesh("cloud_puff_a"))
	_check(cloud_outward > 0.9, "cloud normals point outwards (%.2f of faces)" % cloud_outward)


## +1 when the winding is counter-clockwise around the shading normal,
## -1 when it is clockwise, 0 when the surface is unusable.
func _winding_sign(arrays: Array) -> int:
	if arrays.is_empty():
		return 0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if verts.size() < 3 or norms.size() != verts.size():
		return 0
	var total := 0.0
	var count := indices.size() / 3 if indices.size() > 0 else verts.size() / 3
	for t in count:
		var i0 := indices[t * 3] if indices.size() > 0 else t * 3
		var i1 := indices[t * 3 + 1] if indices.size() > 0 else t * 3 + 1
		var i2 := indices[t * 3 + 2] if indices.size() > 0 else t * 3 + 2
		var geometric := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		if geometric.length_squared() < 1e-12:
			continue
		total += signf(geometric.normalized().dot(norms[i0]))
	if absf(total) < 1.0:
		return 0
	return 1 if total > 0.0 else -1


## Share of faces whose normal points away from the mesh centre.
func _outward_ratio(mesh: ArrayMesh) -> float:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var center := mesh.get_aabb().get_center()
	var good := 0
	var total := 0
	for t in verts.size() / 3:
		var centroid := (verts[t * 3] + verts[t * 3 + 1] + verts[t * 3 + 2]) / 3.0
		var direction := centroid - center
		if direction.length_squared() < 1e-8:
			continue
		total += 1
		if direction.normalized().dot(norms[t * 3]) > 0.0:
			good += 1
	return float(good) / maxf(float(total), 1.0)


func _test_meshes() -> void:
	var keys := [
		"trunk", "leaf_low", "leaf_mid", "leaf_top", "pebble", "path_stone",
		"grass_a", "grass_b", "grass_c", "flower_stem", "flower_head",
		"crystal", "lantern_post", "lantern_globe", "cloud_puff_a",
		"cloud_puff_b",
	]
	var all_built := true
	for key in keys:
		var mesh: ArrayMesh = MeshKit.get_mesh(key)
		if mesh.get_surface_count() == 0 or mesh.surface_get_array_len(0) < 3:
			all_built = false
			print("    empty mesh: %s" % key)
	_check(all_built, "every shared mesh builds geometry")

	var chunk: ArrayMesh = MeshKit.chunk(2.3, 3.2, 9, 1)
	_check(chunk.get_surface_count() == 2, "an island chunk has separate rock and ground surfaces")
	var chunk_size := chunk.get_aabb().size
	_check(chunk_size.y > 3.0, "an island chunk hangs below its surface (%.2f)" % chunk_size.y)

	# The whale silhouette: a long body, a wide fluke, two swept-back fins.
	var body_size := WhaleMesh.body().get_aabb().size
	_check(body_size.z > 3.0, "the whale body is long (%.2f)" % body_size.z)
	_check(body_size.y < body_size.z * 0.5, "the whale body is slimmer than it is long")
	var fluke_size := WhaleMesh.fluke().get_aabb().size
	_check(fluke_size.x > 1.8, "the tail fluke spans wide (%.2f)" % fluke_size.x)
	var fin_left := WhaleMesh.fin(true).get_aabb()
	var fin_right := WhaleMesh.fin(false).get_aabb()
	_check(fin_left.get_center().x < 0.0 and fin_right.get_center().x > 0.0,
		"the pectoral fins sit on opposite sides")
	_check(WhaleMesh.tail_stock().get_surface_count() > 0, "the tail stock builds geometry")


## Headless uses a dummy rendering driver, so a shader may load without being
## compiled. When the uniform list comes back the code really was parsed; when
## it does not, the shaders stay an unverified item for the GUI run.
func _test_shaders() -> void:
	for path in ["res://assets/shaders/sky_gradient.gdshader", "res://assets/shaders/foliage_sway.gdshader"]:
		var shader: Shader = load(path)
		_check(shader != null, "%s loads" % path.get_file())
		if shader == null:
			continue
		var uniforms := shader.get_shader_uniform_list()
		if uniforms.is_empty():
			print("    note: no uniforms reported for %s (dummy renderer, not parsed here)" % path.get_file())
			continue
		_check(uniforms.size() > 0, "%s parsed, %d uniforms" % [path.get_file(), uniforms.size()])
		if path.ends_with("sky_gradient.gdshader"):
			var names: Array = []
			for uniform in uniforms:
				names.append(uniform["name"])
			_check(names.has("moon_amount") and names.has("moon_direction"),
				"the sky shader owns the moon disc, so it never becomes a light")


# --- scene -----------------------------------------------------------------

## Instantiates the real main scene so a broken node path or a _ready() error
## fails here instead of on first launch, then lets it run long enough for a
## grown island at night to actually put the whale in the sky.
func _start_scene_test() -> void:
	_state = root.get_node_or_null("GameState")
	if _state == null:
		print("  skip  autoload GameState is not available in --script mode")
		_finish()
		return
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_check(false, "res://scenes/main.tscn loads")
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	_scene_phase = 1


func _process(delta: float) -> bool:
	if _scene_phase == 0:
		return true
	_elapsed += delta
	match _scene_phase:
		1:
			_check_scene_structure()
			_state.force_stage(SkyIslandState.MAX_STAGE)
			_state.set_time_phase(SkyIslandState.TimePhase.NIGHT, true)
			_elapsed = 0.0
			_scene_phase = 2
		2:
			if _state.whale_active:
				_check(true, "a grown island at night puts a whale in the sky (%.1f s)" % _elapsed)
				_scene_phase = 3
			elif _elapsed > 8.0:
				_check(false, "a grown island at night puts a whale in the sky")
				_scene_phase = 3
		3:
			var stage3: Node3D = _main.get_node("World/IslandRoot/Stage3")
			var whale: Node3D = _main.get_node("SkyWhale/Whale")
			_check(stage3.visible, "growing to the last stage reveals its content")
			_check(whale.visible, "the whale node is shown during a visit")
			print("\n[scene] portrait framing")
			_check_framing()
			_state.reset()
			_main.free()
			_finish()
			return true
	return false


func _check_scene_structure() -> void:
	_check(_main.get_node_or_null("World/IslandRoot/Stage0") != null, "stage 0 content is built")
	_check(_main.get_node_or_null("World/IslandRoot/Stage3") != null, "stage 3 content is built")
	_check(_main.get_node_or_null("SkyWhale/Whale/Rig/Body") != null, "the whale is assembled")
	_check(_main.get_node_or_null("SkyWhale/Whale/Rig/Tail/Fluke") != null, "the whale tail is a separate pivot")
	_check(_main.get_node_or_null("CameraRig/Camera3D") != null, "the camera rig is wired")
	_check(_main.get_node_or_null("HUD/Bottom/Box/TendButton") != null, "the HUD button path is valid")

	var stage0: Node3D = _main.get_node_or_null("World/IslandRoot/Stage0")
	var stage3: Node3D = _main.get_node_or_null("World/IslandRoot/Stage3")
	if stage0 == null or stage3 == null:
		return
	_check(stage0.get_child_count() > 0, "stage 0 has props")
	_check(stage3.get_child_count() > 0, "stage 3 has props")
	_check(stage0.visible, "stage 0 is visible from the start")
	_check(not stage3.visible, "later stages stay hidden until grown")
	var whale: Node3D = _main.get_node_or_null("SkyWhale/Whale")
	_check(whale != null and not whale.visible, "the whale is hidden outside a visit")


# --- framing ---------------------------------------------------------------

## The composition rules the camera has to keep: a fully grown island large in
## the portrait frame but never cropped, even at the ends of the look-around,
## and a band of clear sky above it for the whale.
func _check_framing() -> void:
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D")
	var rig: Node3D = _main.get_node_or_null("CameraRig")
	var island: Node3D = _main.get_node_or_null("World/IslandRoot")
	var whale: Node3D = _main.get_node_or_null("SkyWhale/Whale")
	if camera == null or rig == null or island == null or whale == null:
		_check(false, "the camera, island and whale are available for framing")
		return
	var viewport := camera.get_viewport().get_visible_rect().size
	if viewport.x < 2.0 or viewport.y < 2.0:
		print("  skip  no usable viewport size (%v) to measure framing" % viewport)
		return

	var centred := _screen_rect(camera, island)
	var width := centred.size.x
	_check(width >= 0.70 and width <= 0.85,
		"a grown island fills 70-85%% of the frame width (got %.0f%%)" % (width * 100.0))
	_check(centred.position.y > HUD_TOP,
		"the island clears the top bar (top at %.2f)" % centred.position.y)
	_check(centred.end.y < HUD_BOTTOM,
		"the island clears the bottom bar (bottom at %.2f)" % centred.end.y)

	var base_yaw := rig.rotation_degrees.y
	var cropped := ""
	for yaw in [-LOOK_YAW, 0.0, LOOK_YAW]:
		rig.rotation_degrees.y = yaw
		var rect := _screen_rect(camera, island)
		if rect.position.x < 0.0 or rect.end.x > 1.0 or rect.position.y < 0.0 or rect.end.y > 1.0:
			cropped += " %+.0f°(x %.2f..%.2f)" % [yaw, rect.position.x, rect.end.x]
	rig.rotation_degrees.y = base_yaw
	_check(cropped.is_empty(), "the island stays whole across the look-around%s" % cropped)

	# Stage 0 is the same geometry at every stage, so measuring it here says
	# how big the starting island reads too.
	var stage0 := _screen_rect(camera, _main.get_node("World/IslandRoot/Stage0"))
	_check(stage0.size.x > 0.3,
		"the starting island is still a clear shape (%.0f%% of the width)" % (stage0.size.x * 100.0))

	# Halfway through the visit the whale is in the middle of the frame, which
	# is the pose worth measuring. The whale node reads its place on the path
	# straight from the state, so moving the clock moves the whale.
	_state.whale_time_left = SkyIslandState.WHALE_VISIT_TIME * 0.5
	_main.get_node("SkyWhale")._process(0.0)
	var sky := _screen_rect(camera, whale)
	_check(sky.size.x > 0.3, "the whale reads large in the sky (%.0f%% of the width)" % (sky.size.x * 100.0))
	_check(sky.get_center().x > 0.2 and sky.get_center().x < 0.8,
		"the whale crosses the middle of the frame (centre at %.2f)" % sky.get_center().x)
	_check(sky.end.y < centred.position.y,
		"the whale flies clear of the island (whale ends at %.2f, island starts at %.2f)"
			% [sky.end.y, centred.position.y])
	_check(sky.position.y > HUD_TOP,
		"the whale flies clear of the top bar (top at %.2f)" % sky.position.y)


## Screen-space silhouette of a subtree in viewport fractions: (0,0) is the top
## left corner, (1,1) the bottom right. Measured from real vertices, not from
## bounding boxes — a round island chunk never reaches the corners of its own
## AABB, and this close to the camera that gap is a tenth of the frame.
func _screen_rect(camera: Camera3D, root: Node3D) -> Rect2:
	var viewport := camera.get_viewport().get_visible_rect().size
	var rect := Rect2()
	var started := false
	for node in _visible_meshes(root):
		var mesh_instance := node as MeshInstance3D
		var xf := mesh_instance.global_transform
		for vertex in _mesh_points(mesh_instance.mesh):
			var point := camera.unproject_position(xf * vertex) / viewport
			if started:
				rect = rect.expand(point)
			else:
				rect = Rect2(point, Vector2.ZERO)
				started = true
	return rect


func _visible_meshes(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D and (root as MeshInstance3D).is_visible_in_tree():
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null:
			out.append(mesh_instance)
	for child in root.get_children():
		out.append_array(_visible_meshes(child))
	return out


func _mesh_points(mesh: Mesh) -> PackedVector3Array:
	if _mesh_points_cache.has(mesh):
		return _mesh_points_cache[mesh]
	var points := PackedVector3Array()
	for surface in mesh.get_surface_count():
		points.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	_mesh_points_cache[mesh] = points
	return points


# --- harness ---------------------------------------------------------------

func _finish() -> void:
	print("\n%d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		print("  FAILED: %s" % failure)
	quit(1 if _failures.size() > 0 else 0)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  ok    %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _check_close(value: float, expected: float, label: String) -> void:
	_check(absf(value - expected) < 0.001, "%s (got %.4f, expected %.4f)" % [label, value, expected])
