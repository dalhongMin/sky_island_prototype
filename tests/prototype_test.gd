extends SceneTree

## Headless checks for the parts of this prototype that can break silently.
##
## Run:
##   Godot --headless --path <project> --script res://tests/prototype_test.gd
##
## Scope on purpose: the authoritative state transitions, the sky whale gate,
## the mesh winding convention all the generated geometry depends on, the
## island shell staying one coherent body, and the pointer rules that keep the
## HUD, the orbit camera and care from stealing each other's gestures.
## Colour and "does it look good" are not testable here.

const SkyIslandState := preload("res://scripts/state/sky_island_state.gd")
const LowPoly := preload("res://scripts/art/low_poly.gd")
const MeshKit := preload("res://scripts/art/mesh_kit.gd")
const WhaleMesh := preload("res://scripts/art/whale_mesh.gd")
const IslandShell := preload("res://scripts/art/island_shell.gd")
const CameraRig := preload("res://scripts/camera_rig.gd")

## Where the HUD bars end, as a fraction of the viewport height. Read off
## scenes/hud.tscn: the top bar is about 0.13 tall and the bottom bar, now that
## it also carries the Reset view row, starts at about 0.79.
const HUD_TOP := 0.13
const HUD_BOTTOM := 0.785

## Bearings the island outline and framing are sampled on.
const YAW_SAMPLES := [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]

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
## Yaw parked in the input phase, re-read much later to prove it never sprang
## back on its own.
var _parked_yaw := 0.0


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

	print("\n[art] island shell")
	_test_island_shell()

	print("\n[art] sky whale")
	_test_whale_mesh()

	print("\n[camera] orbit limits")
	_test_camera_limits()

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

	var island: ArrayMesh = IslandShell.build(IslandShell.STAGE_COUNT - 1)
	var island_sign := _winding_sign(island.surface_get_arrays(0))
	_check(island_sign == box_sign,
		"the island rock uses the engine winding (rock %d vs engine %d)" % [island_sign, box_sign])

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


# --- island shell ----------------------------------------------------------

## The island has to be one body, not a pile of plates. These are the three
## properties the screenshots were failing on: a coastline that only ever grows
## outwards, a top surface that faces the sky everywhere, and a single keel.
func _test_island_shell() -> void:
	for stage in IslandShell.STAGE_COUNT:
		var mesh: ArrayMesh = IslandShell.build(stage)
		var built := mesh.get_surface_count() == 2 \
			and mesh.surface_get_array_len(0) > 0 and mesh.surface_get_array_len(1) > 0
		_check(built, "stage %d builds one shell with rock and ground surfaces" % stage)
		if not built:
			continue

		var ground_up := _normals_within(mesh, 1, Vector3.UP, 0.05)
		_check(ground_up, "stage %d ground faces the sky everywhere" % stage)

		var rock_down := _normals_within(mesh, 0, Vector3.DOWN, -0.99)
		_check(rock_down, "stage %d rock never points straight back up" % stage)

		_check(_single_keel(mesh), "stage %d hangs from one keel, not several cones" % stage)
		_check(_rim_is_shared(mesh), "stage %d ground and rock meet on the same rim" % stage)

	var grows := true
	var shrank := ""
	for stage in range(IslandShell.STAGE_COUNT - 1):
		for i in 48:
			var angle := TAU * float(i) / 48.0
			var inner := IslandShell.perimeter_radius(stage, angle)
			var outer := IslandShell.perimeter_radius(stage + 1, angle)
			if outer <= inner + 0.05:
				grows = false
				shrank = " (stage %d at %.2f rad: %.2f -> %.2f)" % [stage, angle, inner, outer]
	_check(grows, "the coastline only ever pushes outwards%s" % shrank)

	# Growing must not lift ground an earlier stage already planted on: the
	# shoulder and the pond are gated outside everything stages 0-2 can reach.
	var core := minf(IslandShell.SHOULDER_GATE.x, IslandShell.POND_GATE.x)
	var core_stable := true
	for i in 32:
		var angle := TAU * float(i) / 32.0
		var p := Vector2(cos(angle), sin(angle)) * (core - 0.01)
		if absf(IslandShell.ground_height(0, p) - IslandShell.ground_height(3, p)) > 0.001:
			core_stable = false
	_check(core_stable, "the core keeps its height through every stage (inside %.2f)" % core)

	# The rock has to be visible under the coastline from a view that looks down
	# on the island: a wall that stays out near the full radius while it falls,
	# not a chamfer that hides behind the rim.
	for stage in IslandShell.STAGE_COUNT:
		var drop := _cliff_drop(stage)
		_check(drop > 0.22 * IslandShell.keel_depth(stage),
			"stage %d hangs a steep cliff under its rim (%.2f of %.2f deep)"
				% [stage, drop, IslandShell.keel_depth(stage)])

	_check(IslandShell.pond_radius() > 0.5,
		"the pond fits inside its own shoreline (radius %.2f)" % IslandShell.pond_radius())
	_check(IslandShell.pond_water_y() < IslandShell.ground_height(3, IslandShell.POND_CENTER + Vector2(2.0, 0.0)),
		"the pond surface sits below the bank around it")


## True when every face normal of a surface is on the right side of `axis`.
func _normals_within(mesh: ArrayMesh, surface: int, axis: Vector3, minimum: float) -> bool:
	var norms: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_NORMAL]
	for n in norms:
		if n.dot(axis) < minimum:
			return false
	return true


## The rock has to narrow to one place. Everything near the lowest point of the
## shell must sit in a single small column; two cones would spread it.
func _single_keel(mesh: ArrayMesh) -> bool:
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lowest := INF
	for v in verts:
		lowest = minf(lowest, v.y)
	var spread := 0.0
	for v in verts:
		if v.y < lowest + 0.35:
			spread = maxf(spread, Vector2(v.x, v.z).length())
	return spread < 0.9


## How far the rock falls while it is still within 12 % of the coastline, i.e.
## the height of the near-vertical upper wall measured from the rim.
func _cliff_drop(stage: int) -> float:
	var mesh: ArrayMesh = IslandShell.build(stage)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rim_total := 0.0
	var rim_count := 0
	var lowest := INF
	for v in verts:
		var here := Vector2(v.x, v.z)
		var share := here.length() / IslandShell.perimeter_radius(stage, atan2(here.y, here.x))
		if share > 0.995:
			rim_total += v.y
			rim_count += 1
		if share >= 0.88:
			lowest = minf(lowest, v.y)
	if rim_count == 0 or is_inf(lowest):
		return 0.0
	return rim_total / float(rim_count) - lowest


## The top surface and the keel are built from the same rim ring, so their
## outermost vertices have to agree to the millimetre or the island has a seam.
func _rim_is_shared(mesh: ArrayMesh) -> bool:
	var ground := _widest_ring(mesh, 1)
	var rock := _widest_ring(mesh, 0)
	return absf(ground - rock) < 0.001


func _widest_ring(mesh: ArrayMesh, surface: int) -> float:
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var widest := 0.0
	for v in verts:
		widest = maxf(widest, Vector2(v.x, v.z).length())
	return widest


# --- sky whale -------------------------------------------------------------

func _test_whale_mesh() -> void:
	var body_size := WhaleMesh.body().get_aabb().size
	_check(body_size.z > 4.0, "the whale body is long (%.2f)" % body_size.z)
	_check(body_size.y < body_size.z * 0.5, "the whale body is slimmer than it is long")

	# A blunt head: the body is still thick most of the way to the nose, which
	# is the difference between a whale and the pointed fish it used to be.
	var widest := WhaleMesh.section(2.80).x
	var near_nose := WhaleMesh.section(WhaleMesh.LENGTH - 0.55).x
	_check(near_nose > widest * 0.5,
		"the head stays full close to the nose (%.2f of %.2f)" % [near_nose, widest])
	# ...and a peduncle that is genuinely narrow where the tail takes over.
	_check(WhaleMesh.section(0.0).x < widest * 0.35,
		"the body tapers into a narrow peduncle (%.2f of %.2f)" % [WhaleMesh.section(0.0).x, widest])

	var fluke := WhaleMesh.fluke().get_aabb()
	_check(fluke.size.x > 2.4, "the tail fluke spans wide (%.2f)" % fluke.size.x)
	_check(_fluke_is_notched(), "the fluke has two lobes with a notch between them")

	var fin_left := WhaleMesh.fin(true).get_aabb()
	var fin_right := WhaleMesh.fin(false).get_aabb()
	_check(fin_left.get_center().x < 0.0 and fin_right.get_center().x > 0.0,
		"the pectoral fins sit on opposite sides")
	_check(fin_left.size.x > 1.1 and fin_left.size.z > 0.8,
		"the flippers are broad, not splinters (%.2f x %.2f)" % [fin_left.size.x, fin_left.size.z])
	_check(WhaleMesh.tail_stock().get_surface_count() > 0, "the tail stock builds geometry")
	_check(WhaleMesh.dorsal().get_surface_count() > 0, "the whale has a dorsal ridge")

	_check(_markings_are_attached(), "every luminous marking lies on the skin, not beside it")

	var painted := LowPoly.paint_by_height(
		WhaleMesh.body(), -0.60, 0.12, Color(1, 1, 1), Color(0, 0, 0))
	var colors: PackedColorArray = painted.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_check(colors.size() == painted.surface_get_array_len(0),
		"the body carries one vertex colour per vertex")
	var pale := 0
	var dark := 0
	for c in colors:
		if c.r > 0.75:
			pale += 1
		elif c.r < 0.25:
			dark += 1
	_check(pale > 0 and dark > 0,
		"the body really is two toned (%d pale, %d dark facets)" % [pale / 3, dark / 3])


## The fluke must come back towards the body between its two tips.
func _fluke_is_notched() -> bool:
	var verts: PackedVector3Array = WhaleMesh.fluke().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tip_reach := 0.0
	var notch_reach := INF
	for v in verts:
		if absf(v.x) > 0.9:
			tip_reach = maxf(tip_reach, v.z)
		if absf(v.x) < 0.1:
			notch_reach = minf(notch_reach, v.z)
	return tip_reach - notch_reach > 0.4


## Markings are patches of skin, so every one of their vertices has to sit on
## the body's own surface. Anything further out is a floating dot again.
func _markings_are_attached() -> bool:
	var verts: PackedVector3Array = WhaleMesh.markings().surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in verts:
		var s := WhaleMesh.section(-v.z)
		if s.x < 0.01 or s.y < 0.01:
			return false
		var across := v.x / s.x
		var up := (v.y - s.z) / s.y
		if absf(sqrt(across * across + up * up) - 1.0) > 0.12:
			return false
	return true


# --- camera ----------------------------------------------------------------

## The rig on its own, with no scene around it: the clamps are the part that
## keeps the player out from under the island and out of the terrain.
func _test_camera_limits() -> void:
	var rig := Node3D.new()
	rig.set_script(CameraRig)
	rig.call("reset_view")
	_check(rig.get("elevation") == CameraRig.DEFAULT_ELEVATION, "reset starts at the default elevation")

	rig.call("orbit", Vector2(0.0, 100000.0))
	_check_close(rig.get("elevation"), CameraRig.MAX_ELEVATION, "looking down stops at the maximum elevation")
	rig.call("orbit", Vector2(0.0, -100000.0))
	_check_close(rig.get("elevation"), CameraRig.MIN_ELEVATION, "looking up stops before the camera goes under the island")
	_check(CameraRig.MIN_ELEVATION >= 10.0 and CameraRig.MAX_ELEVATION <= 75.0,
		"the elevation range stays a diorama view (%.0f-%.0f degrees)"
			% [CameraRig.MIN_ELEVATION, CameraRig.MAX_ELEVATION])

	rig.call("zoom_steps", 1000.0)
	_check_close(rig.get("distance"), CameraRig.MIN_DISTANCE, "zooming in stops at the near limit")
	rig.call("zoom_by_factor", 100.0)
	_check_close(rig.get("distance"), CameraRig.MIN_DISTANCE, "a pinch cannot pass the near limit either")
	rig.call("zoom_steps", -1000.0)
	_check_close(rig.get("distance"), CameraRig.MAX_DISTANCE, "zooming out stops at the far limit")

	# The near limit has to clear the widest island, keel included, at the
	# lowest elevation the player can reach.
	var reach := CameraRig.MIN_DISTANCE * cos(deg_to_rad(CameraRig.MIN_ELEVATION))
	var widest := 0.0
	for i in 48:
		widest = maxf(widest, IslandShell.perimeter_radius(
			IslandShell.STAGE_COUNT - 1, TAU * float(i) / 48.0))
	_check(reach > widest + 1.5,
		"the closest view still stands off the coastline (%.2f vs %.2f)" % [reach, widest])

	rig.call("orbit", Vector2(-5000.0, 0.0))
	var spun: float = rig.get("yaw")
	_check(spun >= -180.0 and spun <= 180.0, "yaw wraps instead of running away (%.1f)" % spun)
	rig.call("set_view", 400.0, 30.0, 10.0)
	_check(absf(rig.get("yaw")) <= 180.0, "an out of range yaw is wrapped, not clamped")
	rig.call("reset_view")
	_check(rig.call("is_default_view"), "reset view restores the default framing")
	rig.free()


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
			print("\n[scene] island shell in the scene")
			_check_island_in_scene()
			_elapsed = 0.0
			_scene_phase = 2
		2:
			# One frame later the HUD containers have laid themselves out, which
			# the pointer tests need in order to aim at a real bar.
			print("\n[input] pointer ownership")
			_check_pointer_rules()
			print("\n[input] pointer ownership through the GUI")
			_check_gui_pointer_rules()
			_state.force_stage(SkyIslandState.MAX_STAGE)
			_state.set_time_phase(SkyIslandState.TimePhase.NIGHT, true)
			_elapsed = 0.0
			_scene_phase = 3
		3:
			if _state.whale_active:
				_check(true, "a grown island at night puts a whale in the sky (%.1f s)" % _elapsed)
				_scene_phase = 4
			elif _elapsed > 8.0:
				_check(false, "a grown island at night puts a whale in the sky")
				_scene_phase = 4
		4:
			var stage3: Node3D = _main.get_node("World/IslandRoot/Stage3")
			var whale: Node3D = _main.get_node("SkyWhale/Whale")
			_check(stage3.visible, "growing to the last stage reveals its content")
			_check(whale.visible, "the whale node is shown during a visit")
			_check(_grown_shell_is_alone(), "the grown island is still a single shell")

			var rig: Node3D = _main.get_node("CameraRig")
			_check(is_equal_approx(rig.get("yaw"), _parked_yaw),
				"the camera never sprang back on its own (%.1f, parked at %.1f)"
					% [rig.get("yaw"), _parked_yaw])

			print("\n[scene] portrait framing")
			rig.call("reset_view")
			_check_framing()
			_state.reset()
			_main.free()
			_finish()
			return true
	return false


func _check_scene_structure() -> void:
	_check(_main.get_node_or_null("World/IslandRoot/Shells/Shell0") != null, "the stage 0 shell is built")
	_check(_main.get_node_or_null("World/IslandRoot/Shells/Shell3") != null, "the stage 3 shell is built")
	_check(_main.get_node_or_null("World/IslandRoot/Stage0") != null, "stage 0 props are built")
	_check(_main.get_node_or_null("World/IslandRoot/Stage3") != null, "stage 3 props are built")
	_check(_main.get_node_or_null("SkyWhale/Whale/Rig/Body") != null, "the whale is assembled")
	_check(_main.get_node_or_null("SkyWhale/Whale/Rig/Markings") != null, "the whale markings are one surface mesh")
	_check(_main.get_node_or_null("SkyWhale/Whale/Rig/Dorsal") != null, "the dorsal ridge is in the rig")
	_check(_main.get_node_or_null("SkyWhale/Whale/Rig/Tail/Fluke") != null, "the whale tail is a separate pivot")
	_check(_main.get_node_or_null("CameraRig/Camera3D") != null, "the camera rig is wired")
	_check(_main.get_node_or_null("HUD/Bottom/Box/TendButton") != null, "the HUD button path is valid")
	_check(_main.get_node_or_null("HUD/Bottom/Box/ViewRow/ResetViewButton") != null, "the Reset view control exists")
	_check(_main.get_node_or_null("HUD/Bottom/Box/ViewRow/ControlHint") != null, "the control hint is shown")

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


## Exactly one shell on screen at a time, and every prop standing on the real
## surface — at the stage that planted it and at the stage the player ends on.
func _check_island_in_scene() -> void:
	var shells: Node3D = _main.get_node_or_null("World/IslandRoot/Shells")
	if shells == null:
		_check(false, "the island shells are under World/IslandRoot/Shells")
		return
	_check(shells.get_child_count() == IslandShell.STAGE_COUNT,
		"one shell is prepared per stage (%d)" % shells.get_child_count())
	var visible_shells := 0
	for child in shells.get_children():
		if (child as Node3D).visible:
			visible_shells += 1
	_check(visible_shells == 1, "exactly one shell is visible at stage 0 (%d)" % visible_shells)

	var floating := ""
	var hovering := ""
	var outside := ""
	var seen: Array = []
	var duplicates := ""
	for stage in IslandShell.STAGE_COUNT:
		var group: Node3D = _main.get_node_or_null("World/IslandRoot/Stage%d" % stage)
		if group == null:
			continue
		for child in group.get_children():
			var node := child as Node3D
			if node == null or not node.has_meta("ground_y"):
				continue
			var p := Vector2(node.position.x, node.position.z)
			var placed := float(node.get_meta("ground_y"))
			var last := IslandShell.STAGE_COUNT - 1
			# The contour a prop was planted on may not move out from under it
			# when the island grows: the raised shoulder and the pond arrive at
			# the last stage and must leave earlier ground exactly where it was.
			var drift := IslandShell.ground_height(stage, p) - IslandShell.ground_height(last, p)
			if absf(drift) > 0.03:
				floating += "\n    %s from stage %d at (%.2f, %.2f): the contour moves %.3f by stage %d" \
					% [node.name, stage, p.x, p.y, drift, last]
			# And the prop has to stand on the shell that is actually drawn —
			# at its own stage and at the one the player ends on. This is the
			# stricter of the two: a prop in the rim fold, or over a facet whose
			# far corner dips into the pond, passes the contour and fails here.
			var stages: Array = [stage] if stage == last else [stage, last]
			for check_stage in stages:
				var mesh_gap := placed - IslandShell.surface_height(check_stage, p)
				if absf(mesh_gap) > 0.03:
					hovering += "\n    %s from stage %d at (%.2f, %.2f) is %.3f off the stage %d mesh" \
						% [node.name, stage, p.x, p.y, mesh_gap, check_stage]
			if not IslandShell.contains_point(stage, p):
				outside += " %s(%.2f)" % [node.name, p.length()]
			for other in seen:
				if (other as Vector2).distance_to(p) < 0.10:
					duplicates += " %s" % node.name
			seen.append(p)
	_check(floating.is_empty(), "growing never moves the contour under a prop%s" % floating)
	_check(hovering.is_empty(), "every prop stands on the drawn shell, at its stage and at the last%s" % hovering)
	_check(outside.is_empty(), "every prop is inside its own coastline%s" % outside)
	_check(duplicates.is_empty(), "no two props share a spot%s" % duplicates)


func _grown_shell_is_alone() -> bool:
	var shells: Node3D = _main.get_node_or_null("World/IslandRoot/Shells")
	if shells == null:
		return false
	var visible_names: Array = []
	for child in shells.get_children():
		if (child as Node3D).visible:
			visible_names.append(String(child.name))
	return visible_names.size() == 1 and visible_names[0] == "Shell3"


# --- pointer rules ---------------------------------------------------------

## The rules main.gd exists to enforce. Most of these go straight at the scene
## root's handler, which keeps the rule itself free of the GUI's own routing;
## _check_gui_pointer_rules() below then re-tests the cases where the GUI is
## the whole problem, through Viewport.push_input().
func _check_pointer_rules() -> void:
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D")
	var rig: Node3D = _main.get_node_or_null("CameraRig")
	var hud: CanvasLayer = _main.get_node_or_null("HUD")
	var bottom: Control = _main.get_node_or_null("HUD/Bottom")
	if camera == null or rig == null or hud == null or bottom == null:
		_check(false, "the camera, HUD and rig are available for the pointer tests")
		return
	if bottom.get_global_rect().size.y < 2.0:
		print("  skip  the HUD has no laid out size yet")
		return

	var on_island := camera.unproject_position(Vector3.ZERO)
	var off_island := camera.unproject_position(Vector3(3.5, 0.0, 0.0))
	var on_hud := bottom.get_global_rect().get_center()
	_check(not hud.blocks_point(on_island), "the island centre is not behind a HUD bar")
	_check(hud.blocks_point(on_hud), "the HUD claims its own bar")

	rig.call("reset_view")

	_clear_growth_lock()
	var before: float = _care_total()
	_touch(0, on_island, true)
	_touch(0, on_island, false)
	_check(_care_total() > before, "a short tap on the island tends it")

	before = _care_total()
	var yaw_before: float = rig.get("yaw")
	_touch(0, on_island, true)
	_drag(0, on_island + Vector2(140.0, 0.0), Vector2(140.0, 0.0))
	_touch(0, on_island + Vector2(140.0, 0.0), false)
	_check(is_equal_approx(_care_total(), before), "a drag across the island never tends it")
	_check(not is_equal_approx(rig.get("yaw"), yaw_before), "a drag across the island orbits the camera")

	before = _care_total()
	yaw_before = rig.get("yaw")
	_touch(0, off_island, true)
	_drag(0, off_island + Vector2(0.0, 90.0), Vector2(0.0, 90.0))
	_touch(0, off_island + Vector2(0.0, 90.0), false)
	_check(is_equal_approx(_care_total(), before), "a drag on empty sky never tends it")
	_check(not is_equal_approx(rig.get("elevation"), CameraRig.DEFAULT_ELEVATION),
		"a vertical drag changes the elevation")

	# Two fingers: a pinch, never care, whichever one is lifted first.
	before = _care_total()
	var distance_before: float = rig.get("distance")
	_touch(0, on_island, true)
	_touch(1, on_island + Vector2(60.0, 0.0), true)
	_drag(1, on_island + Vector2(220.0, 0.0), Vector2(160.0, 0.0))
	_touch(1, on_island + Vector2(220.0, 0.0), false)
	_touch(0, on_island, false)
	_check(is_equal_approx(_care_total(), before), "a pinch never tends the island")
	_check(rig.get("distance") < distance_before,
		"spreading two fingers zooms in (%.2f -> %.2f)" % [distance_before, rig.get("distance")])

	# A HUD pointer owns itself: no care, no camera, even though the event
	# reaches the world handler.
	before = _care_total()
	yaw_before = rig.get("yaw")
	var elevation_before: float = rig.get("elevation")
	_touch(0, on_hud, true)
	_drag(0, on_hud + Vector2(120.0, 0.0), Vector2(120.0, 0.0))
	_touch(0, on_hud + Vector2(120.0, 0.0), false)
	_check(is_equal_approx(_care_total(), before), "a pointer on the HUD never tends the island")
	_check(is_equal_approx(rig.get("yaw"), yaw_before)
			and is_equal_approx(rig.get("elevation"), elevation_before),
		"a pointer on the HUD never moves the camera")

	# Synthesised duplicates of the other pointer kind are dropped.
	before = _care_total()
	yaw_before = rig.get("yaw")
	_touch(0, on_island, true, -1)
	_touch(0, on_island, false, -1)
	_check(is_equal_approx(_care_total(), before), "emulated pointers never tend the island")

	# A gesture interrupted by losing the window must not land as a tap.
	before = _care_total()
	_touch(0, on_island, true)
	_main.call("release_all_pointers")
	_touch(0, on_island, false)
	_check(is_equal_approx(_care_total(), before), "a release after focus loss is not a tap")

	# A cancelled touch is not a tap either.
	before = _care_total()
	_touch(0, on_island, true)
	var cancel := InputEventScreenTouch.new()
	cancel.index = 0
	cancel.position = on_island
	cancel.pressed = false
	cancel.canceled = true
	_main.call("_input", cancel)
	_check(is_equal_approx(_care_total(), before), "a cancelled touch is not a tap")

	# A finger never holds perfectly still, and a hand tremor is not an orbit.
	_clear_growth_lock()
	before = _care_total()
	rig.call("reset_view")
	yaw_before = rig.get("yaw")
	elevation_before = rig.get("elevation")
	_touch(0, on_island, true)
	_drag(0, on_island + Vector2(7.0, 5.0), Vector2(7.0, 5.0))
	_touch(0, on_island + Vector2(7.0, 5.0), false)
	_check(is_equal_approx(rig.get("yaw"), yaw_before)
			and is_equal_approx(rig.get("elevation"), elevation_before),
		"a tap that wanders inside the slop never moves the camera")
	_check(_care_total() > before, "a tap that wanders inside the slop still tends the island")

	# The mouse is its own pointer: left drag orbits, the wheel zooms.
	yaw_before = rig.get("yaw")
	_mouse_button(MOUSE_BUTTON_LEFT, off_island, true)
	_mouse_motion(off_island + Vector2(100.0, 0.0), Vector2(100.0, 0.0))
	_mouse_button(MOUSE_BUTTON_LEFT, off_island + Vector2(100.0, 0.0), false)
	_check(not is_equal_approx(rig.get("yaw"), yaw_before), "a left mouse drag orbits the camera")

	rig.call("reset_view")
	distance_before = rig.get("distance")
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, off_island, true)
	_check(rig.get("distance") < distance_before, "the wheel zooms in")
	distance_before = rig.get("distance")
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, on_hud, true)
	_check(is_equal_approx(rig.get("distance"), distance_before),
		"the wheel over the HUD leaves the distance alone (%.2f)" % rig.get("distance"))

	# A finger parked on the HUD owns the gesture: nothing else may zoom either,
	# which is the trackpad and wheel equivalent of the two-finger case below.
	_touch(0, on_hud, true)
	distance_before = rig.get("distance")
	_mouse_button(MOUSE_BUTTON_WHEEL_UP, off_island, true)
	var magnify := InputEventMagnifyGesture.new()
	magnify.device = 0
	magnify.position = off_island
	magnify.factor = 1.5
	_main.call("_input", magnify)
	_check(is_equal_approx(rig.get("distance"), distance_before),
		"the wheel and the trackpad are ignored while a finger is on the HUD")
	_touch(0, on_hud, false)

	# Reset view is a control, not an automatic drift.
	rig.call("orbit", Vector2(-300.0, 40.0))
	hud.emit_signal("reset_view_requested")
	_check(rig.call("is_default_view"), "the Reset view control restores the default framing")


## The three cases the handler cannot be trusted on by itself, because the GUI
## sits between the window and the world: these go through the real
## Viewport.push_input() pipeline, Controls and all.
func _check_gui_pointer_rules() -> void:
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D")
	var rig: Node3D = _main.get_node_or_null("CameraRig")
	var hint: Control = _main.get_node_or_null("HUD/Bottom/Box/ViewRow/ControlHint")
	var tend: Control = _main.get_node_or_null("HUD/Bottom/Box/TendButton")
	if camera == null or rig == null or hint == null or tend == null:
		_check(false, "the camera, rig and HUD controls are available for the GUI pointer tests")
		return
	if tend.get_global_rect().size.y < 2.0:
		print("  skip  the HUD has no laid out size yet")
		return

	var on_island := camera.unproject_position(Vector3.ZERO)
	var off_island := camera.unproject_position(Vector3(3.5, 0.0, 0.0))
	var on_button := tend.get_global_rect().get_center()
	var on_bar := hint.get_global_rect().get_center()

	# A world drag that ends with the finger over a HUD button. The button eats
	# the release, so if the world only ever saw unhandled events this pointer
	# would stay down for good and the next touch would be read as a pinch.
	rig.call("reset_view")
	var yaw_before: float = rig.get("yaw")
	_gui_touch(0, on_island, true)
	_gui_drag(0, on_island + Vector2(130.0, 0.0), Vector2(130.0, 0.0))
	_gui_touch(0, on_button, false)
	_check(not is_equal_approx(rig.get("yaw"), yaw_before),
		"a drag through the GUI pipeline still orbits the camera")

	yaw_before = rig.get("yaw")
	var distance_before: float = rig.get("distance")
	_gui_touch(0, off_island, true)
	_gui_drag(0, off_island + Vector2(-130.0, 0.0), Vector2(-130.0, 0.0))
	_gui_touch(0, off_island + Vector2(-130.0, 0.0), false)
	_check(not is_equal_approx(rig.get("yaw"), yaw_before)
			and is_equal_approx(rig.get("distance"), distance_before),
		"a drag that ended over the HUD leaves no pointer stuck behind it")

	# Two fingers at once, one of them the HUD's. The HUD bar does not consume
	# the press itself, so this is exactly the case ownership has to decide.
	var care_before: float = _care_total()
	yaw_before = rig.get("yaw")
	distance_before = rig.get("distance")
	_gui_touch(0, on_bar, true)
	_gui_touch(1, on_island, true)
	_gui_drag(1, on_island + Vector2(140.0, 20.0), Vector2(140.0, 20.0))
	_gui_touch(1, on_island + Vector2(140.0, 20.0), false)
	_gui_touch(0, on_bar, false)
	_check(is_equal_approx(rig.get("yaw"), yaw_before)
			and is_equal_approx(rig.get("distance"), distance_before),
		"a finger held on the HUD blocks another finger from moving the camera")
	_check(is_equal_approx(_care_total(), care_before),
		"a finger held on the HUD blocks another finger from tending the island")

	yaw_before = rig.get("yaw")
	_gui_touch(0, off_island, true)
	_gui_drag(0, off_island + Vector2(110.0, 0.0), Vector2(110.0, 0.0))
	_gui_touch(0, off_island + Vector2(110.0, 0.0), false)
	_check(not is_equal_approx(rig.get("yaw"), yaw_before),
		"the world is usable again once the HUD finger is lifted")

	# A short tap with the usual bit of wander, all the way through the GUI.
	rig.call("reset_view")
	_clear_growth_lock()
	care_before = _care_total()
	yaw_before = rig.get("yaw")
	var elevation_before: float = rig.get("elevation")
	_gui_touch(0, on_island, true)
	_gui_drag(0, on_island + Vector2(6.0, -4.0), Vector2(6.0, -4.0))
	_gui_touch(0, on_island + Vector2(6.0, -4.0), false)
	_check(_care_total() > care_before, "a short tap through the GUI pipeline tends the island")
	_check(is_equal_approx(rig.get("yaw"), yaw_before)
			and is_equal_approx(rig.get("elevation"), elevation_before),
		"a short tap through the GUI pipeline never moves the camera")

	# Park a view and leave it: phase 4 checks it is still there seconds later.
	rig.call("orbit", Vector2(-420.0, 25.0))
	_parked_yaw = rig.get("yaw")
	_check(not rig.call("is_default_view"), "the camera keeps the view the player left it in")


## Care that cannot be undone by a growth step: these checks fire enough taps to
## grow the island, and care_progress on its own resets every time it does.
func _care_total() -> float:
	return float(_state.stage) * SkyIslandState.CARE_PER_STAGE + _state.care_progress


## The growth reveal refuses care while it runs, so the checks that expect a tap
## to land step past it first.
func _clear_growth_lock() -> void:
	_state.advance(SkyIslandState.GROWTH_TIME + 0.01)


func _touch(index: int, position: Vector2, pressed: bool, device: int = 0) -> void:
	_main.call("_input", _touch_event(index, position, pressed, device))


func _drag(index: int, position: Vector2, relative: Vector2) -> void:
	_main.call("_input", _drag_event(index, position, relative))


func _mouse_button(button: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = 0
	event.button_index = button
	event.position = position
	event.pressed = pressed
	_main.call("_input", event)


func _mouse_motion(position: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = 0
	event.position = position
	event.relative = relative
	_main.call("_input", event)


## The same events, but handed to the viewport so the GUI gets its turn.
## `true` keeps the coordinates in viewport space, which is where everything
## here is measured.
func _gui_touch(index: int, position: Vector2, pressed: bool) -> void:
	root.push_input(_touch_event(index, position, pressed, 0), true)


func _gui_drag(index: int, position: Vector2, relative: Vector2) -> void:
	root.push_input(_drag_event(index, position, relative), true)


func _touch_event(index: int, position: Vector2, pressed: bool, device: int) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.device = device
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _drag_event(index: int, position: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.device = 0
	event.index = index
	event.position = position
	event.relative = relative
	return event


# --- framing ---------------------------------------------------------------

## The composition rules the camera has to keep: a fully grown island large in
## the portrait frame but never cropped from any bearing it can be orbited to,
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
	_check(width >= 0.70 and width <= 0.88,
		"a grown island fills 70-88%% of the frame width (got %.0f%%)" % (width * 100.0))
	_check(centred.position.y > HUD_TOP,
		"the island clears the top bar (top at %.2f)" % centred.position.y)
	_check(centred.end.y < HUD_BOTTOM,
		"the island clears the bottom bar (bottom at %.2f)" % centred.end.y)

	# The orbit goes all the way round, so the island has to hold together from
	# every bearing, not just the one it was framed on.
	var cropped := ""
	for yaw in YAW_SAMPLES:
		rig.call("set_view", yaw, CameraRig.DEFAULT_ELEVATION, CameraRig.DEFAULT_DISTANCE)
		var rect := _screen_rect(camera, island)
		if rect.position.x < 0.0 or rect.end.x > 1.0 or rect.position.y < HUD_TOP or rect.end.y > HUD_BOTTOM:
			cropped += " %.0f°(x %.2f..%.2f y %.2f..%.2f)" % [yaw, rect.position.x, rect.end.x, rect.position.y, rect.end.y]
	rig.call("reset_view")
	_check(cropped.is_empty(), "the island stays whole all the way round%s" % cropped)

	# The lowest and highest views the player can reach must still hold it.
	var clipped := ""
	for elevation in [CameraRig.MIN_ELEVATION, CameraRig.MAX_ELEVATION]:
		rig.call("set_view", 0.0, elevation, CameraRig.DEFAULT_DISTANCE)
		var rect := _screen_rect(camera, island)
		if rect.position.x < 0.0 or rect.end.x > 1.0:
			clipped += " %.0f°" % elevation
	rig.call("reset_view")
	_check(clipped.is_empty(), "the island stays whole across the elevation range%s" % clipped)

	# How big the island reads at the start. The stage 0 shell is hidden once
	# the island has grown past it, so it is shown just long enough to measure.
	var shell0: MeshInstance3D = _main.get_node("World/IslandRoot/Shells/Shell0")
	var shell0_visible := shell0.visible
	shell0.visible = true
	var stage0 := _screen_rect(camera, shell0)
	shell0.visible = shell0_visible
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
## bounding boxes — a round island never reaches the corners of its own AABB,
## and this close to the camera that gap is a tenth of the frame.
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
