extends Node3D

## The sky whale visit.
##
## Assembles the hand-built whale (scripts/art/whale_mesh.gd) and flies it
## along a fixed path across the upper sky, above the clouds and clear of both
## the HUD and the island silhouette. Whether a visit happens is GameState's
## decision; the position on the path is read back from GameState.whale_progress()
## so there is no second timer here.

const WhaleMesh := preload("res://scripts/art/whale_mesh.gd")
const LowPoly := preload("res://scripts/art/low_poly.gd")
const Palette := preload("res://scripts/art/palette.gd")

const WHALE_SCALE := 2.0
const TAIL_BEAT_SPEED := 2.4
const TAIL_BEAT_AMOUNT := 0.30
const BOB_AMOUNT := 0.35
const ROLL_AMOUNT := 0.08

## Standing bank, in radians, on top of the roll. The whale crosses about ten
## degrees above the default camera, so held level it shows nothing but its
## flank: a pale belly, a broad fluke and the near flipper are all facing the
## ground, away from the player. Tipping it a quarter turn towards the camera is
## what makes those read, and it is the pose a turning whale is in anyway.
const BANK := 0.46

## Where the pale belly stops and the lavender back begins, in body-local Y.
## The band is wide and sits high, so the underside the camera actually sees is
## pale instead of only the last row of facets along the keel of the belly.
const BELLY_LOW := -0.70
const BELLY_HIGH := 0.06

var _whale: Node3D
var _tail: Node3D
var _glow: OmniLight3D
var _path: Curve3D
var _elapsed := 0.0


func _ready() -> void:
	Palette.ensure()
	_build()
	_path = _make_path()
	_whale.visible = false
	GameState.whale_visit_started.connect(_on_visit_started)
	GameState.whale_visit_finished.connect(_on_visit_finished)
	if GameState.whale_active:
		_on_visit_started()


func _process(delta: float) -> void:
	_elapsed += delta
	if not _whale.visible:
		return

	var length := _path.get_baked_length()
	var offset := length * GameState.whale_progress()
	var here := _path.sample_baked(offset)
	var ahead := _path.sample_baked(minf(offset + 1.5, length))
	var bob := Vector3(0.0, sin(_elapsed * 0.7) * BOB_AMOUNT, 0.0)

	_whale.position = here + bob
	if here.distance_to(ahead) > 0.01:
		_whale.look_at(ahead + bob, Vector3.UP)
	# Positive roll about the whale's own forward axis turns its belly towards
	# the camera, which sits off to the side of the flight path.
	_whale.rotate_object_local(
		Vector3(0.0, 0.0, 1.0), BANK + sin(_elapsed * 0.55) * ROLL_AMOUNT)
	_tail.rotation.x = sin(_elapsed * TAIL_BEAT_SPEED) * TAIL_BEAT_AMOUNT


func _on_visit_started() -> void:
	_whale.visible = true
	_elapsed = 0.0
	_process(0.0)


func _on_visit_finished() -> void:
	_whale.visible = false


# --- assembly --------------------------------------------------------------

func _build() -> void:
	# _whale is moved and aimed with look_at(), so the size lives on a child
	# rig: look_at() is only safe on an unscaled node.
	_whale = Node3D.new()
	_whale.name = "Whale"
	add_child(_whale)

	var rig := Node3D.new()
	rig.name = "Rig"
	rig.scale = Vector3.ONE * WHALE_SCALE
	_whale.add_child(rig)

	# One mesh, two tones: the facets are coloured by how high up the body they
	# sit, so a pale belly runs into blue-lavender upper facets without a seam
	# and without a second material.
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = LowPoly.paint_by_height(
		WhaleMesh.body(), BELLY_LOW, BELLY_HIGH, Palette.WHALE_BELLY, Palette.WHALE_BACK)
	body.material_override = Palette.whale_body
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(body)

	for left in [true, false]:
		var fin := MeshInstance3D.new()
		fin.name = "FinLeft" if left else "FinRight"
		fin.mesh = WhaleMesh.fin(left)
		fin.material_override = Palette.whale_fin
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(fin)

	var dorsal := MeshInstance3D.new()
	dorsal.name = "Dorsal"
	dorsal.mesh = WhaleMesh.dorsal()
	dorsal.material_override = Palette.whale_fin
	dorsal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(dorsal)

	_tail = Node3D.new()
	_tail.name = "Tail"
	_tail.position = Vector3(0.0, 0.0, WhaleMesh.TAIL_PIVOT_Z)
	rig.add_child(_tail)

	var stock := MeshInstance3D.new()
	stock.name = "Stock"
	stock.mesh = WhaleMesh.tail_stock()
	stock.material_override = Palette.whale_body
	stock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail.add_child(stock)

	var fluke := MeshInstance3D.new()
	fluke.name = "Fluke"
	fluke.mesh = WhaleMesh.fluke()
	fluke.material_override = Palette.whale_fin
	fluke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail.add_child(fluke)

	# Luminous markings lying on the skin — a row down each flank and a short
	# line along the spine — rather than blobs floating beside the body.
	var marks := MeshInstance3D.new()
	marks.name = "Markings"
	marks.mesh = WhaleMesh.markings()
	marks.material_override = Palette.whale_mark
	marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(marks)

	for left in [true, false]:
		var eye := MeshInstance3D.new()
		eye.name = "EyeL" if left else "EyeR"
		eye.mesh = WhaleMesh.blob()
		eye.material_override = Palette.whale_eye
		eye.basis = _lying_on(WhaleMesh.eye_normal(left))
		eye.position = WhaleMesh.eye_position(left)
		eye.scale = Vector3.ONE * 0.46
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(eye)

	_glow = OmniLight3D.new()
	_glow.name = "WhaleGlow"
	_glow.light_color = Color(0.58, 0.74, 1.0)
	_glow.light_energy = 1.0
	# The rig scale multiplies the light range, so this ends up around 11 units.
	_glow.omni_range = 4.5
	_glow.omni_attenuation = 2.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(0.0, 0.3, -1.2)
	rig.add_child(_glow)


## Tips a mesh that was lathed along +Y so its axis follows a surface normal,
## which is how the eye lies flat on the flank instead of sticking out of it.
func _lying_on(up: Vector3) -> Basis:
	var y := up.normalized()
	var x := Vector3.FORWARD.cross(y)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


## A slow left-to-right arc. Roughly 50 units long over the 16 s visit, which
## keeps the whale inside the portrait frame for about 9 seconds. It crosses
## the band of sky between the HUD and the island: above the cloud layer, below
## the top bar, and clear of the island silhouette.
func _make_path() -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3(-24.0, 7.6, -13.0))
	curve.add_point(Vector3(-11.0, 8.4, -15.0))
	curve.add_point(Vector3(2.0, 8.8, -14.0))
	curve.add_point(Vector3(14.0, 8.2, -12.0))
	curve.add_point(Vector3(25.0, 7.4, -10.0))
	return curve
