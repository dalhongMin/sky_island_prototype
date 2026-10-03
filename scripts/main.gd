extends Node3D

## Scene root: pointer routing, nothing else.
##
## Every pointer — a touch index, or the left mouse button — is tracked from
## press to release and owned by exactly one thing: the HUD, the orbit camera,
## or a tap waiting to become care. The rules are:
##
##   * a press on the HUD is the HUD's, and while it is down no other pointer,
##     wheel or trackpad gesture may move the camera or tend the island;
##   * one world pointer dragging past TAP_SLOP orbits the camera, two pinch
##     zoom it;
##   * care is added on release, and only if that pointer never dragged, was
##     never joined by a second one, started on the island and ended on it.
##
## Why _input() and not _unhandled_input(): the GUI sits between the two, and it
## eats events. A world drag that ends with the finger over a HUD button would
## never see its own release, and the pointer would stay down forever — the next
## touch anywhere would be read as the second finger of a pinch. Watching the
## whole lifecycle here, before the GUI picks anything, is what makes the
## bookkeeping reliable. Nothing is marked handled, so the HUD keeps working
## exactly as it did; ownership is decided by asking the HUD what it covers.
##
## Pointer kinds are kept apart. project.godot leaves mouse-from-touch
## emulation on so the HUD buttons work under a finger, and the events the
## engine synthesises that way carry device == EMULATED_DEVICE; dropping those
## here is what stops one finger counting as two pointers.

## Pointer id for the left mouse button. Touch indices are never negative.
const MOUSE_POINTER := -7
## InputEvent.DEVICE_ID_EMULATION: anything the engine made up from the other
## pointer kind.
const EMULATED_DEVICE := -1
## A press may wander this far in viewport pixels and still count as a tap, and
## until it has, it does not move the camera either.
const TAP_SLOP := 16.0
const ISLAND_PLANE_Y := 0.0

@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _rig: Node3D = $CameraRig
@onready var _world: Node3D = $World
@onready var _hud: CanvasLayer = $HUD

## id -> { start, position, dragged, ui, on_island }
var _pointers: Dictionary = {}
## Set the moment a second world pointer joins, cleared only once every pointer
## is up, so neither finger of a pinch can leave a tap behind.
var _multi_pointer := false


func _ready() -> void:
	if _hud != null and _hud.has_signal("reset_view_requested"):
		_hud.reset_view_requested.connect(_on_reset_view)


## Losing the window mid-gesture would otherwise leave a pointer pressed
## forever, and the release that never arrives could land as care.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all_pointers()


## Runs before the GUI picks a Control, and never consumes anything.
func _input(event: InputEvent) -> void:
	if event.device == EMULATED_DEVICE:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		elif touch.canceled:
			_cancel(touch.index)
		else:
			_release(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move(drag.index, drag.position, drag.relative)
	elif event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pointers.has(MOUSE_POINTER):
			_move(MOUSE_POINTER, motion.position, motion.relative)
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch, the desktop equivalent of a two finger zoom.
		var magnify := event as InputEventMagnifyGesture
		if _zoom_allowed(magnify.position):
			_rig.zoom_by_factor(magnify.factor)


func release_all_pointers() -> void:
	_pointers.clear()
	_multi_pointer = false


# --- pointers --------------------------------------------------------------

func _mouse_button(button: InputEventMouseButton) -> void:
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			if button.pressed:
				_press(MOUSE_POINTER, button.position)
			else:
				_release(MOUSE_POINTER, button.position)
		MOUSE_BUTTON_WHEEL_UP:
			if button.pressed and _zoom_allowed(button.position):
				_rig.zoom_steps(1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed and _zoom_allowed(button.position):
				_rig.zoom_steps(-1.0)


func _press(id: int, position: Vector2) -> void:
	if _pointers.has(id):
		return
	var ui := _over_ui(position)
	_pointers[id] = {
		"start": position,
		"position": position,
		"dragged": false,
		"ui": ui,
		"on_island": not ui and _hits_island(position),
	}
	if _world_pointer_count() > 1:
		_multi_pointer = true


func _move(id: int, position: Vector2, relative: Vector2) -> void:
	if not _pointers.has(id):
		return
	var pointer: Dictionary = _pointers[id]
	var previous: Vector2 = pointer["position"]
	pointer["position"] = position
	if pointer["ui"]:
		return
	# A finger never holds perfectly still. Until it has left the tap slop it is
	# still a tap being made, so the camera does not follow it at all; a pinch is
	# exempt, because two fingers are unambiguous from the first pixel.
	if not pointer["dragged"]:
		if not _multi_pointer and position.distance_to(pointer["start"]) <= TAP_SLOP:
			return
		pointer["dragged"] = true
	if _ui_pointer_held():
		return
	if _multi_pointer:
		_pinch(id, previous, position)
	else:
		_rig.orbit(relative)


func _release(id: int, position: Vector2) -> void:
	if not _pointers.has(id):
		return
	var pointer: Dictionary = _pointers[id]
	var was_multi := _multi_pointer
	var was_blocked := _ui_pointer_held()
	_pointers.erase(id)
	if _pointers.is_empty():
		_multi_pointer = false
	if pointer["ui"] or pointer["dragged"] or was_multi or was_blocked:
		return
	if position.distance_to(pointer["start"]) > TAP_SLOP:
		return
	if pointer["on_island"] and _hits_island(position):
		GameState.add_care(1.0)


func _cancel(id: int) -> void:
	_pointers.erase(id)
	if _pointers.is_empty():
		_multi_pointer = false


## The gap between the two world pointers decides the zoom; the one that did
## not move supplies the anchor.
func _pinch(moved_id: int, previous: Vector2, position: Vector2) -> void:
	for other_id in _pointers:
		if other_id == moved_id:
			continue
		var pointer: Dictionary = _pointers[other_id]
		if pointer["ui"]:
			continue
		var anchor: Vector2 = pointer["position"]
		var before := previous.distance_to(anchor)
		var after := position.distance_to(anchor)
		if before >= 1.0 and after >= 1.0:
			_rig.zoom_by_factor(after / before)
		return


func _world_pointer_count() -> int:
	var count := 0
	for id in _pointers:
		if not (_pointers[id] as Dictionary)["ui"]:
			count += 1
	return count


## True while any pointer that started on the HUD is still down. The HUD owns
## the gesture until that finger lifts, so a second finger, the wheel and the
## trackpad all stay out of the world in the meantime.
func _ui_pointer_held() -> bool:
	for id in _pointers:
		if (_pointers[id] as Dictionary)["ui"]:
			return true
	return false


func _zoom_allowed(position: Vector2) -> bool:
	return not _ui_pointer_held() and not _over_ui(position)


func _on_reset_view() -> void:
	_rig.reset_view()


# --- hit tests -------------------------------------------------------------

## Control nodes consume their own presses, but only the ones that are really
## buttons: the HUD bars themselves let presses through, and a real touch is not
## routed through the GUI the way a mouse click is either. So the HUD is asked
## directly, and everything over a bar belongs to the HUD.
func _over_ui(position: Vector2) -> bool:
	if _hud == null or not _hud.has_method("blocks_point"):
		return false
	return _hud.blocks_point(position)


## Intersects the pointer ray with the island's top plane and asks the island
## whether that point is inside the current coastline.
func _hits_island(screen_position: Vector2) -> bool:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return false
	var distance := (ISLAND_PLANE_Y - origin.y) / direction.y
	if distance < 0.0:
		return false
	var hit := origin + direction * distance
	return _world.contains_point(Vector2(hit.x, hit.z))
