extends Node3D

## Persistent orbit camera around the island.
##
## The rig sits at the pivot and carries the yaw and the elevation; the camera
## hangs off it at `distance` and is tilted back up by PITCH_BIAS, which drops
## the island into the lower half of the portrait frame and leaves the band of
## sky above it free for the sky whale.
##
## Nothing springs back. The view a player leaves is the view they get until
## they ask for it back with reset_view(). Yaw goes all the way round;
## elevation is clamped so the camera never crawls under the island, and the
## distance is clamped so it never pushes through the terrain either.

const DEFAULT_YAW := 0.0
const DEFAULT_ELEVATION := 22.0
const DEFAULT_DISTANCE := 11.1

## Below MIN_ELEVATION the camera starts looking up at the keel from below and
## the diorama loses its ground; above MAX_ELEVATION it reads as a map.
const MIN_ELEVATION := 15.0
const MAX_ELEVATION := 60.0
## MIN_DISTANCE keeps the camera outside the widest coastline and its keel even
## at the lowest elevation; MAX_DISTANCE stops the island shrinking to a dot.
const MIN_DISTANCE := 6.9
const MAX_DISTANCE := 16.0

## Orbit centre, a little above the ground plane so the island does not sink
## out of frame when the camera is lifted.
const PIVOT := Vector3(0.0, 0.25, 0.0)
## Extra upward tilt on top of the elevation, i.e. the camera aims above the
## pivot. This is the whole of the "composed portrait" framing.
const PITCH_BIAS := 6.8

const DEGREES_PER_PIXEL := 0.22
const WHEEL_UNITS := 0.75

var yaw := DEFAULT_YAW
var elevation := DEFAULT_ELEVATION
var distance := DEFAULT_DISTANCE

var _camera: Camera3D


func _ready() -> void:
	position = PIVOT
	reset_view()


func reset_view() -> void:
	set_view(DEFAULT_YAW, DEFAULT_ELEVATION, DEFAULT_DISTANCE)


func is_default_view() -> bool:
	return is_equal_approx(yaw, DEFAULT_YAW) \
		and is_equal_approx(elevation, DEFAULT_ELEVATION) \
		and is_equal_approx(distance, DEFAULT_DISTANCE)


## Absolute view, used by reset, by the capture tool and by tests.
func set_view(new_yaw: float, new_elevation: float, new_distance: float) -> void:
	yaw = wrapf(new_yaw, -180.0, 180.0)
	elevation = clampf(new_elevation, MIN_ELEVATION, MAX_ELEVATION)
	distance = clampf(new_distance, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


## `pixels` is a pointer delta: the island follows the finger horizontally and
## the camera climbs when the finger moves down.
func orbit(pixels: Vector2) -> void:
	set_view(
		yaw - pixels.x * DEGREES_PER_PIXEL,
		elevation + pixels.y * DEGREES_PER_PIXEL,
		distance)


## One mouse wheel notch. Positive steps move in.
func zoom_steps(steps: float) -> void:
	set_view(yaw, elevation, distance - steps * WHEEL_UNITS)


## Pinch: `factor` is how much wider the two fingers got, so spreading them
## apart moves the camera in.
func zoom_by_factor(factor: float) -> void:
	set_view(yaw, elevation, distance / maxf(factor, 0.05))


func _apply() -> void:
	rotation_degrees = Vector3(-elevation, yaw, 0.0)
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		return
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.rotation_degrees = Vector3(PITCH_BIAS, 0.0, 0.0)
