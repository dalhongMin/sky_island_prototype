extends RefCounted

## One coherent floating island, rebuilt per growth stage.
##
## A stage is a single closed shell, never a pile of cones: an organic
## perimeter R(stage, angle), a contiguous top surface sampled on a polar grid
## inside it, and one connected faceted keel hanging from that same perimeter
## ring down to a single apex. It is built as three surfaces, which is the
## contract island_world.gd assigns materials to: 0 the rock underside, 1 the
## grass or soil the island is walked on, and 2 the steep shore band where the
## ground folds over the rock lip.
##
## Growth only ever pushes the perimeter outwards — every lobe below is
## positive — so a later stage always contains the earlier silhouette. That is
## what lets island_world.gd swap the whole shell on growth and still animate
## the new land expanding out of the old outline.
##
## The raised shoulder and the pond are contours of this one surface, gated to
## a radius the earlier stages never reach, so growing never lifts ground a
## player already planted on.

const LowPoly := preload("res://scripts/art/low_poly.gd")

const STAGE_COUNT := 4

## Facet density. Low on purpose: 24 sectors keeps the silhouette chunky and
## the whole shell at roughly 600 triangles.
const SECTORS := 24
## Radial bands of the top surface as a fraction of the perimeter, denser near
## the rim where the ground rolls over the rock lip.
const RINGS := [0.0, 0.17, 0.33, 0.49, 0.64, 0.77, 0.88, 0.95, 1.0]
## Keel rings as [radius fraction, how far that ring has blended from the rim
## down towards the apex].
##
## The first two rings barely pull in at all: that is a near vertical cliff
## hanging straight off the rim, and it is the whole reason the island reads as
## a rock mass instead of a pancake. From a portrait view looking slightly down,
## anything that starts sloping inwards immediately disappears behind the
## coastline, so the taper only begins once the wall has fallen far enough to
## be seen under the rim. Below that it narrows steadily to one apex.
const KEEL := [[0.97, 0.12], [0.92, 0.30], [0.78, 0.50], [0.52, 0.66], [0.26, 0.80]]
## The narrowest keel ring always stays at least this much of the keel depth
## above the apex, whatever the rim above it does. It is what makes the apex the
## single lowest vertex of the shell instead of one of a ring of them.
const APEX_CLEARANCE := 0.22

const BASE_RADIUS := [2.15, 2.75, 3.15, 3.50]
## How far the ground folds down over the rock lip at the perimeter, and where
## in the top surface that fold starts. It is kept to the outermost band so the
## roll-over is a crisp lip on top of the cliff instead of a dome, and so the
## ground props stand on is flat right up to PLANT_LIMIT.
const RIM_DROP := 0.42
const RIM_FOLD_START := 0.88

## Props may stand this far out, as a fraction of the perimeter. Past it the
## rim fold starts and the drawn surface runs away below the contour, so a prop
## planted there would hang in the air over its own facet.
const PLANT_LIMIT := 0.86
## How far inwards a prop is nudged per attempt when the drawn surface under it
## would still move as the island grows, and how much movement counts as none.
## The tolerance is tighter than the 0.03 tests/prototype_test.gd allows, so a
## settled prop has margin rather than sitting on the limit.
const PLANT_NUDGE := 0.04
const PLANT_SETTLE := 0.02

const SHOULDER_CENTER := Vector2(-2.45, 1.85)
const SHOULDER_HEIGHT := 0.92
## Inside this radius the shoulder is switched off entirely, so stages 0-2 can
## plant anywhere in the core without being buried when stage 3 arrives.
const SHOULDER_GATE := Vector2(2.05, 2.75)

const POND_CENTER := Vector2(2.30, -1.60)
const POND_DEPTH := 0.52
const POND_GATE := Vector2(1.95, 2.60)
## How far the water sits above the bottom of the basin.
const POND_FILL := 0.34

static var _cache: Dictionary = {}
static var _rows_cache: Dictionary = {}


static func clamp_stage(stage: int) -> int:
	return clampi(stage, 0, STAGE_COUNT - 1)


## Nominal radius of a stage, used for the growth animation and for framing.
static func mean_radius(stage: int) -> float:
	return float(BASE_RADIUS[clamp_stage(stage)])


## Shallower than the first pass, because the rock is now actually seen: with a
## cliff hanging off the rim the island reads as a mass at this depth, where the
## old tapered spike needed every unit it had and still pushed into the bottom
## HUD bar from some bearings.
static func keel_depth(stage: int) -> float:
	return 0.76 * mean_radius(stage) + 0.42


## The island outline at one bearing. Always larger than the previous stage's.
static func perimeter_radius(stage: int, angle: float) -> float:
	var radius := mean_radius(stage) * _outline_shape(angle)
	return radius + _lobes(clamp_stage(stage), angle)


static func contains_point(stage: int, p: Vector2) -> bool:
	return p.length() <= perimeter_radius(stage, atan2(p.y, p.x))


## A point at `fraction` of the way out to the perimeter along `angle`. Props
## placed with this follow the organic outline and can never land off the edge.
static func polar(stage: int, angle: float, fraction: float) -> Vector2:
	var radius := perimeter_radius(stage, angle) * fraction
	return Vector2(cos(angle), sin(angle)) * radius


## Height of the walkable top surface at a world XZ position, before the rim
## fold. This is the contour the island is designed around; surface_height()
## is what actually gets drawn, and props are checked against both.
static func ground_height(stage: int, p: Vector2) -> float:
	return _contour(p) + _shoulder(stage, p) + _basin(stage, p)


## Height of the drawn top surface at an XZ position: the very triangle of the
## shell the point falls in, read back from the same polar grid build() uses.
## Props stand on this, so nothing hovers over — or sinks into — its own facet.
static func surface_height(stage: int, p: Vector2) -> float:
	stage = clamp_stage(stage)
	var rows: Array = _rows(stage)
	var sector := int(floor(fposmod(atan2(p.y, p.x), TAU) / (TAU / float(SECTORS)))) % SECTORS
	var j := (sector + 1) % SECTORS
	for ring in range(RINGS.size() - 1):
		var lo: PackedVector3Array = rows[ring]
		var hi: PackedVector3Array = rows[ring + 1]
		var y := INF
		if lo.size() == 1:
			y = _triangle_y(p, lo[0], hi[j], hi[sector])
		else:
			y = _triangle_y(p, lo[j], hi[j], hi[sector])
			if is_inf(y):
				y = _triangle_y(p, lo[j], hi[sector], lo[sector])
		if not is_inf(y):
			return y
	# Past the coastline there is no top surface left; the lip is the answer.
	var rim: PackedVector3Array = rows[RINGS.size() - 1]
	return (rim[sector].y + rim[j].y) * 0.5


## The nominal radius inside which neither late contour reaches, so the ground
## is identical at every stage. Everything an early stage plants ends up here
## or on ground the last stage leaves alone.
static func settled_radius() -> float:
	return minf(SHOULDER_GATE.x, POND_GATE.x) - 0.02


## Where `p` may actually be planted at `stage`. Three rules, all about ground
## moving out from under a prop that is already standing on it: nothing stands
## past PLANT_LIMIT, where the rim folds away below the contour; nothing an
## early stage plants may sit on ground the last stage folds into its shoulder
## or its pond; and the facet it ends up on has to be the same facet at every
## later stage too. A point that already obeys all three comes back untouched;
## anything else is pulled straight back towards the middle, which is the one
## direction that switches every late contour off.
static func plant_point(stage: int, p: Vector2) -> Vector2:
	stage = clamp_stage(stage)
	var radius := p.length()
	if radius < 0.0001:
		return p
	var limit := perimeter_radius(stage, atan2(p.y, p.x)) * PLANT_LIMIT
	if stage < STAGE_COUNT - 1 and not is_equal_approx(
			ground_height(stage, p), ground_height(STAGE_COUNT - 1, p)):
		limit = minf(limit, settled_radius())
	var out := p if radius <= limit else p * (limit / radius)
	# The contour is only the design. What a prop actually stands on is one
	# triangle of the drawn shell, and a triangle whose far corner reaches into
	# the pond tilts under a point whose own contour never moves at all — which
	# is exactly how a prop two centimetres inside the basin gate still ended up
	# hanging over the stage 3 mesh. So the drawn surface gets the last word:
	# step inwards until the ground under the point is the same here as it is at
	# every stage after this one.
	var direction := out.normalized()
	var toward_rim := out.length()
	var attempts := 0
	while attempts < 24 and toward_rim > 0.2 and not _surface_is_settled(stage, out):
		toward_rim -= PLANT_NUDGE
		out = direction * toward_rim
		attempts += 1
	return out


## True when the drawn surface under `p` is the same at `stage` as at every
## stage after it, so a prop placed here stands on its own facet for the rest of
## the run and not only at the stage that planted it.
static func _surface_is_settled(stage: int, p: Vector2) -> bool:
	var here := surface_height(stage, p)
	for later in range(stage + 1, STAGE_COUNT):
		if absf(surface_height(later, p) - here) > PLANT_SETTLE:
			return false
	return true


## Water level of the stage 3 pond.
static func pond_water_y() -> float:
	return ground_height(STAGE_COUNT - 1, POND_CENTER) + POND_FILL


## Largest disc that still fits inside the shoreline, found by walking outwards
## in eight directions until the bank rises above the water.
static func pond_radius() -> float:
	var water := pond_water_y()
	var shortest := 2.0
	for i in 8:
		var direction := Vector2.from_angle(TAU * float(i) / 8.0)
		var reach := 0.1
		while reach < 2.0 and ground_height(STAGE_COUNT - 1, POND_CENTER + direction * reach) < water:
			reach += 0.05
		shortest = minf(shortest, reach)
	return maxf(shortest - 0.14, 0.3)


static func build(stage: int) -> ArrayMesh:
	stage = clamp_stage(stage)
	if _cache.has(stage):
		return _cache[stage]

	var ground := LowPoly.new_faces()
	var rock := LowPoly.new_faces()
	var rows := _top_rows(stage)

	for ring in range(RINGS.size() - 1):
		var lo: PackedVector3Array = rows[ring]
		var hi: PackedVector3Array = rows[ring + 1]
		for i in SECTORS:
			var j := (i + 1) % SECTORS
			if lo.size() == 1:
				LowPoly.add_face(ground, lo[0], hi[j], hi[i])
			else:
				LowPoly.add_face(ground, lo[j], hi[j], hi[i])
				LowPoly.add_face(ground, lo[j], hi[i], lo[i])

	# The keel hangs off the same rim vertices the ground ends on, so the two
	# surfaces meet exactly and the island has no seam to show daylight through.
	var keel := _keel_rows(stage, rows[RINGS.size() - 1])
	for ring in range(keel.size() - 1):
		var lo: PackedVector3Array = keel[ring]
		var hi: PackedVector3Array = keel[ring + 1]
		var apex: bool = lo.size() == 1
		for i in SECTORS:
			var j := (i + 1) % SECTORS
			var a: Vector3 = lo[0] if apex else lo[i]
			var b: Vector3 = lo[0] if apex else lo[j]
			if not apex:
				LowPoly.add_face(rock, a, hi[j], b)
			LowPoly.add_face(rock, a, hi[i], hi[j])

	var mesh := ArrayMesh.new()
	LowPoly.add_faces_surface(mesh, rock)
	LowPoly.add_faces_surface(mesh, ground)
	_cache[stage] = mesh
	return mesh


# --- outline ---------------------------------------------------------------

## Three gentle harmonics: enough to break the circle without ever folding the
## outline back on itself.
static func _outline_shape(angle: float) -> float:
	return 1.0 + 0.055 * sin(angle * 3.0 + 0.6) + 0.035 * sin(angle * 5.0 - 1.1)


## Positive-only bays that open up where each stage grows, so the new coastline
## bulges somewhere specific instead of the whole island inflating evenly.
static func _lobes(stage: int, angle: float) -> float:
	var out := 0.0
	if stage >= 1:
		out += 0.22 * _bump(angle, 2.45) + 0.18 * _bump(angle, -1.00)
	if stage >= 2:
		out += 0.20 * _bump(angle, -2.30) + 0.14 * _bump(angle, 0.50)
	if stage >= 3:
		out += 0.26 * _bump(angle, 2.10) + 0.20 * _bump(angle, -0.60)
	return out


static func _bump(angle: float, center: float) -> float:
	var t := absf(wrapf(angle - center, -PI, PI)) / 1.10
	if t >= 1.0:
		return 0.0
	var falloff := 1.0 - t * t
	return falloff * falloff


# --- contour ---------------------------------------------------------------

## Soft ground swell, the same at every stage, so a prop placed on it at stage
## 0 is still standing on it at stage 3.
static func _contour(p: Vector2) -> float:
	return 0.055 * sin(p.x * 1.05 + 0.4) * cos(p.y * 0.85 - 0.3) \
		+ 0.045 * cos(p.x * 0.62 - p.y * 1.15 + 1.2)


static func _shoulder(stage: int, p: Vector2) -> float:
	if stage < 3:
		return 0.0
	# A compact headland rather than a broad tilt. The falloff is deliberately
	# short: it has to die out well before the ground the earlier stages planted
	# on, including the grid cells around it, or growing would tilt the facet a
	# prop is standing on even where the contour under the prop itself holds.
	var plateau := 1.0 - smoothstep(0.40, 1.15, p.distance_to(SHOULDER_CENTER))
	var gate := smoothstep(SHOULDER_GATE.x, SHOULDER_GATE.y, p.length())
	return SHOULDER_HEIGHT * plateau * gate


static func _basin(stage: int, p: Vector2) -> float:
	if stage < 3:
		return 0.0
	# Same reasoning as the shoulder: a pond, not a valley. A wide bowl reached
	# back into the middle of the island and sank ground that stages 1 and 2 had
	# already planted on.
	var dip := 1.0 - smoothstep(0.80, 1.45, p.distance_to(POND_CENTER))
	var gate := smoothstep(POND_GATE.x, POND_GATE.y, p.length())
	return -POND_DEPTH * dip * gate


# --- geometry --------------------------------------------------------------

static func _rows(stage: int) -> Array:
	if not _rows_cache.has(stage):
		_rows_cache[stage] = _top_rows(stage)
	return _rows_cache[stage]


## Height inside one grid triangle, or INF when the point is not in it. The
## tiny negative slack keeps a point that lands exactly on a shared edge from
## falling through every triangle that owns it.
static func _triangle_y(p: Vector2, a: Vector3, b: Vector3, c: Vector3) -> float:
	var ax := a.x - c.x
	var az := a.z - c.z
	var bx := b.x - c.x
	var bz := b.z - c.z
	var det := ax * bz - bx * az
	if absf(det) < 1e-12:
		return INF
	var px := p.x - c.x
	var pz := p.y - c.z
	var u := (px * bz - bx * pz) / det
	var v := (ax * pz - px * az) / det
	var w := 1.0 - u - v
	if u < -0.0005 or v < -0.0005 or w < -0.0005:
		return INF
	return a.y * u + b.y * v + c.y * w


static func _top_rows(stage: int) -> Array:
	var rows: Array = []
	for ring in RINGS.size():
		var t: float = RINGS[ring]
		var row := PackedVector3Array()
		if is_zero_approx(t):
			row.push_back(Vector3(0.0, ground_height(stage, Vector2.ZERO), 0.0))
		else:
			for i in SECTORS:
				var angle := TAU * float(i) / float(SECTORS)
				var p := polar(stage, angle, t)
				# The rim fold only bites in the outermost band, so it changes
				# the lip of the island and nothing a prop stands on.
				var y := ground_height(stage, p) - RIM_DROP * smoothstep(RIM_FOLD_START, 1.0, t)
				row.push_back(Vector3(p.x, y, p.y))
		rows.push_back(row)
	return rows


## Keel rings, ordered apex first so the winding matches low_poly's lathe.
##
## Every ring vertex is its own rim vertex interpolated towards the one apex, so
## each column of the cliff keeps the relief of the coastline it hangs from
## while all of them close on the same point. Two properties fall out of that
## and both matter. The blend never reaches 1, so the apex is the only lowest
## vertex of the shell even under the pond-side rim, which sits well below the
## average and used to drag a whole ring down level with the apex. And blend and
## crag only ever move a column inwards and downwards, so the rings stay nested:
## no ring overhangs the one above it, which is what makes the wall read as one
## continuous slope rather than self-intersecting bands that stripe their own
## shadow.
static func _keel_rows(stage: int, rim: PackedVector3Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + stage
	var depth := keel_depth(stage)

	var rim_y := 0.0
	var rim_low := INF
	for v in rim:
		rim_y += v.y
		rim_low = minf(rim_low, v.y)
	rim_y /= float(rim.size())

	# Slightly off centre: a keel that hangs dead straight reads as a cone.
	var apex_y := rim_y - depth
	var rows: Array = [PackedVector3Array([Vector3(0.22, apex_y, -0.15)])]

	# The column hanging off the lowest point of the rim has the least height to
	# give away, so the clearance is budgeted there and the whole blend ladder is
	# scaled by what that column can afford. Every other column then clears the
	# apex by more than APEX_CLEARANCE of the depth, and the rings keep their
	# spacing instead of one of them being clamped onto another.
	var afford := 1.0 - APEX_CLEARANCE * depth / maxf(rim_low - apex_y, 0.001)
	var blend_scale := clampf(afford / float(KEEL[KEEL.size() - 1][1]), 0.0, 1.0)

	# Crags only ever cut in, never out, and they accumulate down a column: the
	# rim has to stay the widest ring of the whole shell and every ring below it
	# narrower than the last. The top two rings keep the full width of their own
	# coastline, which is the near vertical wall the silhouette needs. The lean
	# is per column, not per ring, so it varies the wall without ever reordering
	# the rings on it.
	var reach: Array = []
	var running := PackedFloat32Array()
	var lean := PackedFloat32Array()
	for i in SECTORS:
		running.push_back(1.0)
		lean.push_back(1.0 - rng.randf_range(0.0, 0.06))
	for k in KEEL.size():
		if k >= 2:
			for i in SECTORS:
				running[i] *= 1.0 - rng.randf_range(0.0, 0.055)
		reach.push_back(running.duplicate())

	for k in range(KEEL.size() - 1, -1, -1):
		var fraction: float = KEEL[k][0]
		var blend: float = float(KEEL[k][1]) * blend_scale
		var crag: PackedFloat32Array = reach[k]
		var row := PackedVector3Array()
		for i in SECTORS:
			var narrow := fraction * crag[i]
			row.push_back(Vector3(
				rim[i].x * narrow,
				lerpf(rim[i].y, apex_y, blend * lean[i]),
				rim[i].z * narrow))
		rows.push_back(row)
	rows.push_back(rim)
	return rows
