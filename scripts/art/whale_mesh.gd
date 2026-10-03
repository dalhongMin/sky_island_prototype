extends RefCounted

## Hand-built low-poly sky whale. No external model or reference asset: the
## body is one lathed tube, the pectoral fins and the tail fluke are flat
## polygons, which is enough for the silhouette (body / flippers / fluke) to
## read against the night sky.
##
## The whale faces -Z, Godot's forward, so the flight code can just look_at()
## the next point on its path. The body is lathed along +Y and rotated into
## place, which keeps the winding and normals of low_poly.gd valid.

const LowPoly := preload("res://scripts/art/low_poly.gd")

## Where the tail joins the body, in whale-local coordinates.
const TAIL_PIVOT_Z := 0.0
## Nose tip, for sizing and for the eye placement below.
const NOSE_Z := -3.55

static var _cache: Dictionary = {}


## Rotates the lathe axis (+Y) onto the forward axis (-Z).
static func _forward_basis() -> Basis:
	return Basis(Vector3.RIGHT, -PI * 0.5)


static func body() -> ArrayMesh:
	if _cache.has("body"):
		return _cache["body"]
	# Vector4(axis, radius sideways, radius vertical, vertical offset).
	var rings := [
		Vector4(0.00, 0.100, 0.100, 0.00),
		Vector4(0.35, 0.175, 0.165, -0.01),
		Vector4(0.90, 0.300, 0.285, -0.03),
		Vector4(1.50, 0.450, 0.445, -0.05),
		Vector4(2.10, 0.520, 0.530, -0.06),
		Vector4(2.65, 0.480, 0.505, -0.05),
		Vector4(3.10, 0.340, 0.360, -0.03),
		Vector4(3.40, 0.175, 0.190, -0.01),
		Vector4(3.55, 0.000, 0.000, 0.00),
	]
	var mesh: ArrayMesh = LowPoly.lathe(
		rings, 8, LowPoly.no_mods(), true, false, false, 0.0, 0, _forward_basis())
	_cache["body"] = mesh
	return mesh


static func tail_stock() -> ArrayMesh:
	if _cache.has("stock"):
		return _cache["stock"]
	# Rings always ascend along the lathe axis; -0.58 here becomes z = +0.58.
	var rings := [
		Vector4(-0.58, 0.055, 0.042, 0.00),
		Vector4(-0.28, 0.078, 0.072, 0.00),
		Vector4(0.00, 0.100, 0.100, 0.00),
	]
	var mesh: ArrayMesh = LowPoly.lathe(
		rings, 6, LowPoly.no_mods(), true, true, false, 0.0, 0, _forward_basis())
	_cache["stock"] = mesh
	return mesh


## Horizontal two-lobed fluke with a notch, local to the tail pivot.
static func fluke() -> ArrayMesh:
	if _cache.has("fluke"):
		return _cache["fluke"]
	var outline := [
		Vector3(0.00, 0.00, 0.30),
		Vector3(-1.26, 0.12, 1.20),
		Vector3(-0.24, 0.00, 1.02),
		Vector3(0.24, 0.00, 1.02),
		Vector3(1.26, 0.12, 1.20),
	]
	var mesh: ArrayMesh = LowPoly.flat_polygon(outline, Vector3(0.0, 1.0, 0.0))
	_cache["fluke"] = mesh
	return mesh


static func fin(left: bool) -> ArrayMesh:
	var key := "fin_left" if left else "fin_right"
	if _cache.has(key):
		return _cache[key]
	var outline: Array
	# Wide and clearly dropped. The whale passes overhead, so a flipper held
	# level would be edge on to the camera and disappear; angled down about
	# 20° it turns its broad face towards the ground and reads as a shape.
	if left:
		outline = [
			Vector3(-0.40, 0.00, -1.85),
			Vector3(-1.50, -0.40, -0.82),
			Vector3(-1.58, -0.44, -0.58),
			Vector3(-0.42, -0.04, -1.32),
		]
	else:
		outline = [
			Vector3(0.40, 0.00, -1.85),
			Vector3(0.42, -0.04, -1.32),
			Vector3(1.58, -0.44, -0.58),
			Vector3(1.50, -0.40, -0.82),
		]
	var mesh: ArrayMesh = LowPoly.flat_polygon(outline, Vector3(0.0, 1.0, 0.25))
	_cache[key] = mesh
	return mesh


## Small glowing blob used for the back markings and the eyes.
static func blob() -> ArrayMesh:
	if _cache.has("blob"):
		return _cache["blob"]
	var mesh: ArrayMesh = LowPoly.revolve([
		Vector2(0.0, 0.0), Vector2(0.075, 0.05), Vector2(0.055, 0.10), Vector2(0.0, 0.13),
	], 5, LowPoly.no_mods(), false, false)
	_cache["blob"] = mesh
	return mesh
