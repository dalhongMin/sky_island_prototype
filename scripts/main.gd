extends Node3D

## Scene root: routes pointer input, nothing else.
##
## A press that lands on the island (tested against the island plane, no
## physics bodies involved) becomes care; a press on empty sky becomes a
## camera look-around. HUD buttons never reach here because Control nodes
## consume the event first, so UI, care and camera can't fight over a drag.

## Care added per pixel of stroking; a ~220 px stroke equals one tap.
const CARE_PER_PIXEL := 0.0045
## Care is flushed to the state in small steps instead of every drag event.
const CARE_FLUSH_STEP := 0.2
const ISLAND_PLANE_Y := 0.0

enum DragMode { NONE, CARE, LOOK }

@onready var _camera: Camera3D = $CameraRig/Camera3D
@onready var _camera_rig: Node3D = $CameraRig
@onready var _island: Node3D = $World

var _mode := DragMode.NONE
var _care_buffer := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _hits_island(touch.position):
				_mode = DragMode.CARE
				GameState.add_care(1.0)
			else:
				_mode = DragMode.LOOK
				_camera_rig.set_dragging(true)
		else:
			if _care_buffer > 0.0:
				GameState.add_care(_care_buffer)
			_care_buffer = 0.0
			_mode = DragMode.NONE
			_camera_rig.set_dragging(false)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _mode == DragMode.CARE:
			_care_buffer += drag.relative.length() * CARE_PER_PIXEL
			if _care_buffer >= CARE_FLUSH_STEP:
				GameState.add_care(_care_buffer)
				_care_buffer = 0.0
		elif _mode == DragMode.LOOK:
			_camera_rig.look_drag(drag.relative.x)


## Intersects the pointer ray with the island's top plane and compares the hit
## against the current stage radius.
func _hits_island(screen_position: Vector2) -> bool:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return false
	var distance := (ISLAND_PLANE_Y - origin.y) / direction.y
	if distance < 0.0:
		return false
	var hit := origin + direction * distance
	return Vector2(hit.x, hit.z).length() <= _island.care_radius()
