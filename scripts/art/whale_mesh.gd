extends RefCounted

## Hand-built low-poly sky whale. No external model or reference asset.
##
## The silhouette is the point: a full, blunt head, a body that tapers into a
## narrow peduncle, a visibly two-lobed fluke, broad swept flippers and a low
## dorsal ridge. Around 350 triangles in five meshes, no textures.
##
## Everything is laid out on one axis. `a` runs from 0 at the tail joint to
## LENGTH at the tip of the nose, and `section(a)` is the half-width, the
## half-height and the belly drop there. The body is lathed along that axis and
## rotated so the whale faces -Z, Godot's forward, which lets the flight code
## just look_at() the next point on its path; markings, the eye and the dorsal
## ridge are all placed with surface_point(), so they sit on the skin instead
## of floating next to it.

const LowPoly := preload("res://scripts/art/low_poly.gd")

## Where the tail joins the body, in whale-local coordinates.
const TAIL_PIVOT_Z := 0.0
## Nose tip, for sizing and for placing the eye.
const LENGTH := 4.32
const NOSE_Z := -LENGTH

## Vector4(axis, half width, half height, belly drop). The body holds almost its
## full girth from 2.30 to 3.65 and the last rings never close to a point: the
## nose ends on a small cap instead, which is the difference between a blunt
## headed whale and the pointed fish the first pass rendered as.
const SECTIONS := [
	Vector4(0.00, 0.150, 0.175, 0.000),
	Vector4(0.28, 0.205, 0.240, -0.015),
	Vector4(0.70, 0.310, 0.360, -0.040),
	Vector4(1.20, 0.430, 0.490, -0.070),
	Vector4(1.75, 0.540, 0.590, -0.095),
	Vector4(2.30, 0.615, 0.650, -0.105),
	Vector4(2.80, 0.650, 0.670, -0.100),
	Vector4(3.25, 0.645, 0.645, -0.085),
	Vector4(3.65, 0.610, 0.580, -0.060),
	Vector4(3.95, 0.540, 0.495, -0.035),
	Vector4(4.15, 0.430, 0.380, -0.015),
	Vector4(4.26, 0.300, 0.260, -0.005),
	Vector4(LENGTH, 0.175, 0.150, 0.000),
]

const BODY_SIDES := 10

static var _cache: Dictionary = {}


## Rotates the lathe axis (+Y) onto the forward axis (-Z). Afterwards the ring
## half-width stays on X, the half-height becomes Y and the axis becomes -Z.
static func _forward_basis() -> Basis:
	return Basis(Vector3.RIGHT, -PI * 0.5)


## Half width, half height and belly drop at an axis position, interpolated
## between the authored rings. Markings are attached with this, and
## tests/prototype_test.gd uses it to check they really are on the skin.
static func section(a: float) -> Vector3:
	var first: Vector4 = SECTIONS[0]
	if a <= first.x:
		return Vector3(first.y, first.z, first.w)
	for i in range(1, SECTIONS.size()):
		var hi: Vector4 = SECTIONS[i]
		if a > hi.x:
			continue
		var lo: Vector4 = SECTIONS[i - 1]
		var t := (a - lo.x) / maxf(hi.x - lo.x, 0.0001)
		return Vector3(
			lerpf(lo.y, hi.y, t),
			lerpf(lo.z, hi.z, t),
			lerpf(lo.w, hi.w, t))
	return Vector3.ZERO


## A point on the skin. `around` is measured from the spine: 0 is the back, PI
## the belly, +PI/2 the +X flank. `lift` pushes the point out along the surface
## so a marking rests on the body instead of inside it.
static func surface_point(a: float, around: float, lift: float) -> Vector3:
	var s := section(a)
	return Vector3(
		sin(around) * (s.x + lift),
		cos(around) * (s.y + lift) + s.z,
		-a)


## Outward surface normal at the same place, from the gradient of the ellipse.
static func surface_normal(a: float, around: float) -> Vector3:
	var s := section(a)
	return Vector3(sin(around) / maxf(s.x, 0.01), cos(around) / maxf(s.y, 0.01), 0.0).normalized()


static func body() -> ArrayMesh:
	if _cache.has("body"):
		return _cache["body"]
	# Capped at both ends: the tail joint is sleeved by the stock, and the nose
	# closes on a small flat facet, which is what blunts the snout.
	var mesh: ArrayMesh = LowPoly.lathe(
		SECTIONS.duplicate(), BODY_SIDES, LowPoly.no_mods(),
		true, true, false, 0.0, 0, _forward_basis())
	_cache["body"] = mesh
	return mesh


## The peduncle: it keeps tapering behind the body and flattens sideways where
## the fluke grows out of it, the way a real tail stock does.
static func tail_stock() -> ArrayMesh:
	if _cache.has("stock"):
		return _cache["stock"]
	# Rings always ascend along the lathe axis; -0.78 here becomes z = +0.78.
	# The front ring is a touch wider than the body so it sleeves over the
	# body's end cap instead of fighting with it.
	var rings := [
		Vector4(-0.80, 0.048, 0.030, 0.012),
		Vector4(-0.52, 0.080, 0.068, 0.010),
		Vector4(-0.26, 0.118, 0.126, 0.005),
		Vector4(0.00, 0.162, 0.188, 0.000),
	]
	var mesh: ArrayMesh = LowPoly.lathe(
		rings, 6, LowPoly.no_mods(), true, false, false, 0.0, 0, _forward_basis())
	_cache["stock"] = mesh
	return mesh


## Two lobes with a notch between them, built as two convex fans so the
## concave outline survives fan triangulation. The tips lift, which keeps the
## fluke from vanishing edge-on when the whale is seen from below.
static func fluke() -> ArrayMesh:
	if _cache.has("fluke"):
		return _cache["fluke"]
	var left := [
		Vector3(0.00, 0.00, 0.72),
		Vector3(-0.66, 0.05, 0.86),
		Vector3(-1.54, 0.24, 1.34),
		Vector3(-1.05, 0.14, 1.62),
		Vector3(-0.24, 0.01, 1.38),
	]
	var right: Array = []
	for i in range(left.size() - 1, -1, -1):
		var p: Vector3 = left[i]
		right.append(Vector3(-p.x, p.y, p.z))
	var parts: Array = []
	parts.append_array(_shell(left, Vector3.UP, 0.014))
	parts.append_array(_shell(right, Vector3.UP, 0.014))
	var mesh: ArrayMesh = LowPoly.flat_polygon_set(parts)
	_cache["fluke"] = mesh
	return mesh


## A broad, swept pectoral flipper. The whale passes overhead and banked, so the
## flipper is dropped about 30 degrees: held level it would be edge-on from the
## ground and disappear, angled down it turns its broad face towards the camera.
static func fin(left: bool) -> ArrayMesh:
	var key := "fin_left" if left else "fin_right"
	if _cache.has(key):
		return _cache[key]
	var side := -1.0 if left else 1.0
	var outline := [
		Vector3(side * 0.42, -0.18, -2.72),
		Vector3(side * 1.22, -0.58, -2.26),
		Vector3(side * 1.94, -0.98, -1.74),
		Vector3(side * 1.62, -0.90, -1.40),
		Vector3(side * 0.44, -0.24, -1.86),
	]
	var mesh: ArrayMesh = LowPoly.flat_polygon_set(
		_shell(outline, Vector3(side * 0.46, -0.89, 0.0).normalized(), 0.018))
	_cache[key] = mesh
	return mesh


## A long, low dorsal hump rather than a fin. A tall triangle on this body reads
## as a shark the moment it is seen in silhouette; a rounded swell along the
## back says whale and still breaks the line when the camera orbits round.
static func dorsal() -> ArrayMesh:
	if _cache.has("dorsal"):
		return _cache["dorsal"]
	var outline := [
		surface_point(2.40, 0.0, 0.00),
		surface_point(2.05, 0.0, 0.10),
		surface_point(1.72, 0.0, 0.16),
		surface_point(1.42, 0.0, 0.12),
		surface_point(1.15, 0.0, 0.00),
	]
	var mesh: ArrayMesh = LowPoly.flat_polygon_set(
		_shell(outline, Vector3(1.0, 0.25, 0.0).normalized(), 0.018))
	_cache["dorsal"] = mesh
	return mesh


## A flat outline given a little thickness: the same shape offset along `up`
## and against it, each face carrying its own normal. The whale's fins are
## double sided, so both copies are drawn; the offset is what keeps them from
## z-fighting the way two coincident faces would.
static func _shell(outline: Array, up: Vector3, thickness: float) -> Array:
	var front: Array = []
	var back: Array = []
	for p in outline:
		front.append(p + up * thickness)
		back.append(p - up * thickness)
	return [[front, up], [back, -up]]


## Luminous markings: small patches of skin, not jewellery. The earlier row of
## five large diamonds read as a necklace draped over the animal, so there are
## fewer of them now, they are about half the size, and they sit high on the
## flank among the dark upper facets instead of straddling the pale belly.
static func markings() -> ArrayMesh:
	if _cache.has("marks"):
		return _cache["marks"]
	# [axis position, patch size]
	var flank := [[1.72, 0.58], [2.24, 0.66], [2.76, 0.56]]
	var spine := [[2.10, 0.42], [2.60, 0.38]]
	var parts: Array = []
	for entry in flank:
		for side in [1.0, -1.0]:
			parts.append_array(_patch(float(entry[0]), side * 1.45, float(entry[1])))
	for entry in spine:
		parts.append_array(_patch(float(entry[0]), 0.0, float(entry[1])))
	var mesh: ArrayMesh = LowPoly.flat_polygon_set(parts)
	_cache["marks"] = mesh
	return mesh


## One diamond of skin around (`a`, `around`), lifted clear of the body.
static func _patch(a: float, around: float, size: float) -> Array:
	var lift := 0.015
	var da := 0.19 * size
	var arc := 0.17 * size
	var points := [
		surface_point(a - da, around, lift),
		surface_point(a, around - arc, lift),
		surface_point(a + da, around, lift),
		surface_point(a, around + arc, lift),
	]
	return [[points, surface_normal(a, around)]]


## Small blob, used for the eyes.
static func blob() -> ArrayMesh:
	if _cache.has("blob"):
		return _cache["blob"]
	var mesh: ArrayMesh = LowPoly.revolve([
		Vector2(0.0, 0.0), Vector2(0.075, 0.05), Vector2(0.055, 0.10), Vector2(0.0, 0.13),
	], 5, LowPoly.no_mods(), false, false)
	_cache["blob"] = mesh
	return mesh


## The eye sits behind and below the widest part of the head, high enough on
## the flank to read against the darker upper facets rather than the pale
## belly. Sunk slightly into the skin so it is a mark, not a bead.
const EYE_AXIS := 3.30
const EYE_AROUND := 1.42


static func eye_position(left: bool) -> Vector3:
	return surface_point(EYE_AXIS, _eye_around(left), -0.03)


static func eye_normal(left: bool) -> Vector3:
	return surface_normal(EYE_AXIS, _eye_around(left))


static func _eye_around(left: bool) -> float:
	return -EYE_AROUND if left else EYE_AROUND
