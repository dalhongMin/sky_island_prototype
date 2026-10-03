extends SceneTree

## Captures reference images of the real GUI Mobile render into docs/images/.
##
## Needs a window, so it must NOT be run with --headless:
##   /Applications/Godot.app/Contents/MacOS/Godot \
##     --path /Users/mindalhong/Desktop/Project/sky_island_prototype \
##     --script res://tools/capture_prototype.gd
##
## It drives the autoloaded GameState the same way a player would (care, then
## the Night button) and writes PNGs next to the docs. It only ever touches
## res://docs/images inside this project: no user:// data is read or written.

const OUT_DIR := "res://docs/images"
const SHOT_SIZE := Vector2i(540, 960)

var _state: Node
var _main: Node
var _shots := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("capture_prototype.gd needs a real window: run it without --headless.")
		quit(2)
		return
	_state = root.get_node_or_null("GameState")
	if _state == null:
		printerr("capture_prototype.gd needs the GameState autoload.")
		quit(3)
		return
	_run()


func _run() -> void:
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	var error := DirAccess.make_dir_recursive_absolute(dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		printerr("cannot create %s (error %d)" % [dir, error])
		quit(4)
		return

	DisplayServer.window_set_size(SHOT_SIZE)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)

	# The automatic day/night cycle would fight the script.
	_state.auto_cycle = false

	await _wait(2.0)
	await _shot("01_stage0_day.png")

	for stage in 3:
		await _tend_until_growth()
		await _wait(2.2)
		await _shot("%02d_stage%d_day.png" % [stage + 2, stage + 1])

	# Two views of the grown island that the fixed portrait shot cannot show:
	# the far side, and a close low angle where a stack of plates would be
	# obvious if the terrain were still built that way.
	var rig := _main.get_node_or_null("CameraRig")
	if rig != null:
		rig.set_view(134.0, 26.0, 11.1)
		await _wait(0.8)
		await _shot("07_stage3_orbit.png")
		rig.set_view(38.0, 17.0, 7.3)
		await _wait(0.8)
		await _shot("08_stage3_close.png")
		rig.reset_view()
		await _wait(0.8)

	_state.set_time_phase(2, true)  # TimePhase.NIGHT

	# The gate opens about two seconds after the sky goes dark, which is before
	# the colour blend has even finished, so the whale is shot first and the
	# quiet night shot is taken once the visit is over.
	var waited := 0.0
	while not _state.whale_active and waited < 10.0:
		await _wait(0.25)
		waited += 0.25
	if not _state.whale_active:
		printerr("the whale visit never started; capture incomplete")
		quit(5)
		return
	await _wait(6.5)
	await _shot("06_sky_whale.png")

	while _state.whale_active:
		await _wait(0.5)
	await _wait(1.0)
	await _shot("05_stage3_night.png")

	print("wrote %d images to %s" % [_shots, dir])
	quit(0)


func _tend_until_growth() -> void:
	var guard := 0
	while not _state.is_growing() and not _state.is_fully_grown() and guard < 20:
		_state.add_care(1.0)
		guard += 1
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		printerr("could not read the viewport for %s" % file_name)
		return
	var path := "%s/%s" % [OUT_DIR, file_name]
	var error := image.save_png(path)
	if error != OK:
		printerr("could not save %s (error %d)" % [path, error])
		return
	_shots += 1
	print("captured %s%s" % [path, _framing_note()])


## How much of the frame the island covers in the shot that was just taken, so
## the reference images come with the number the framing was tuned against.
func _framing_note() -> String:
	var camera: Camera3D = _main.get_node_or_null("CameraRig/Camera3D")
	var island: Node3D = _main.get_node_or_null("World/IslandRoot")
	if camera == null or island == null:
		return ""
	var viewport := camera.get_viewport().get_visible_rect().size
	var low := Vector2.INF
	var high := -Vector2.INF
	# owned = false: every mesh here was built by a script, so none of them
	# belong to a scene file.
	for node in island.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.is_visible_in_tree():
			continue
		var xf := mesh_instance.global_transform
		for surface in mesh_instance.mesh.get_surface_count():
			for vertex in mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := camera.unproject_position(xf * vertex) / viewport
				low = low.min(point)
				high = high.max(point)
	if low.x > high.x:
		return ""
	return "  (island %.0f%% wide, y %.2f..%.2f)" % [(high.x - low.x) * 100.0, low.y, high.y]
