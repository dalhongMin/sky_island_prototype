extends Node3D

## Fixed diorama camera with a small look-around.
##
## The camera position and pitch are authored in main.tscn so the whole island
## always reads in portrait. This rig only yaws a few degrees around the island
## and drifts back to the framed view once the finger is lifted. Not a free
## orbit camera: 360° viewing is out of scope for this prototype.

const MAX_YAW_DEGREES := 10.0
const DEGREES_PER_PIXEL := 0.045
const RETURN_IDLE_TIME := 1.2
const RETURN_SPEED := 3.0

var _yaw := 0.0
var _dragging := false
var _idle := 0.0


func set_dragging(dragging: bool) -> void:
	_dragging = dragging
	if dragging:
		_idle = 0.0


## `pixels` is the horizontal drag delta; the island follows the finger.
func look_drag(pixels: float) -> void:
	_yaw = clampf(_yaw - pixels * DEGREES_PER_PIXEL, -MAX_YAW_DEGREES, MAX_YAW_DEGREES)
	_idle = 0.0


func _process(delta: float) -> void:
	if not _dragging:
		_idle += delta
		if _idle > RETURN_IDLE_TIME:
			_yaw = move_toward(_yaw, 0.0, RETURN_SPEED * delta)
	rotation_degrees.y = _yaw
