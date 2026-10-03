extends RefCounted

## Flat shaded low-poly mesh builders.
##
## Everything is generated from two primitives — a lathe and a flat polygon
## fan — so the whole diorama shares a handful of mesh resources (see
## mesh_kit.gd) instead of importing external models. One normal per face, no
## UVs, no textures, no smoothing.
##
## Winding: helpers take triangles counter-clockwise as seen from outside and
## insert them swapped, because Godot expects clockwise front faces. The
## convention is pinned down against the engine's own BoxMesh in
## tests/prototype_test.gd.


static func make_mods(sides: int, amount: float, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedFloat32Array()
	for _i in sides:
		out.append(rng.randf_range(-amount, amount))
	return out


static func no_mods() -> PackedFloat32Array:
	return PackedFloat32Array()


## Solid of revolution. `profile` is an Array of Vector2(radius, y) ordered
## bottom to top; a zero radius collapses into a single apex vertex.
## With `split_top_surface` the top cap becomes surface 1, which lets an island
## chunk wear grass on top and rock on the sides with one MeshInstance3D.
static func revolve(
		profile: Array,
		sides: int,
		mods: PackedFloat32Array,
		cap_bottom: bool,
		cap_top: bool,
		split_top_surface: bool = false,
		y_jitter: float = 0.0,
		seed_value: int = 0) -> ArrayMesh:
	var rings: Array = []
	for p in profile:
		rings.append(Vector4(p.y, p.x, p.x, 0.0))
	return lathe(rings, sides, mods, cap_bottom, cap_top, split_top_surface, y_jitter, seed_value, Basis.IDENTITY)


## Generic lathe. Each ring is Vector4(y, radius_x, radius_z, z_offset), which
## is enough for cones, pebbles and the elliptical whale body with a belly.
## `basis` rotates the finished mesh, used to lay the whale along -Z.
## Rings must ascend along the axis: the face normals are derived from that
## order, so a descending list would turn the mesh inside out.
static func lathe(
		rings: Array,
		sides: int,
		mods: PackedFloat32Array,
		cap_bottom: bool,
		cap_top: bool,
		split_top_surface: bool = false,
		y_jitter: float = 0.0,
		seed_value: int = 0,
		basis: Basis = Basis.IDENTITY) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var points: Array = []
	for ring_index in rings.size():
		var ring: Vector4 = rings[ring_index]
		var row: Array = []
		if is_zero_approx(ring.y) and is_zero_approx(ring.z):
			row.append(Vector3(0.0, ring.x, ring.w))
		else:
			for i in sides:
				var m := 1.0
				if mods.size() == sides:
					m += mods[i]
				var a := TAU * float(i) / float(sides)
				var y := ring.x
				if y_jitter > 0.0:
					y += rng.randf_range(-y_jitter, y_jitter)
				row.append(Vector3(cos(a) * ring.y * m, y, sin(a) * ring.z * m + ring.w))
		points.append(row)

	var body: Array = [[], []]  # [vertices, normals]
	var top: Array = [[], []]

	for k in range(points.size() - 1):
		var lo: Array = points[k]
		var hi: Array = points[k + 1]
		var lo_apex: bool = lo.size() == 1
		var hi_apex: bool = hi.size() == 1
		if lo_apex and hi_apex:
			continue
		for i in sides:
			var j := (i + 1) % sides
			var a: Vector3 = lo[0] if lo_apex else lo[i]
			var b: Vector3 = lo[0] if lo_apex else lo[j]
			var c: Vector3 = hi[0] if hi_apex else hi[j]
			var d: Vector3 = hi[0] if hi_apex else hi[i]
			if not lo_apex:
				_tri(body, a, c, b)
			if not hi_apex:
				_tri(body, a, d, c)

	var first: Array = points[0]
	if cap_bottom and first.size() > 1:
		var center0 := _average(first)
		for i in sides:
			_tri(body, center0, first[i], first[(i + 1) % sides])

	var last: Array = points[points.size() - 1]
	if cap_top and last.size() > 1:
		var centern := _average(last)
		var cap: Array = top if split_top_surface else body
		for i in sides:
			_tri(cap, centern, last[(i + 1) % sides], last[i])

	var mesh := ArrayMesh.new()
	_add_surface(mesh, body, basis)
	_add_surface(mesh, top, basis)
	return mesh


## Fan-triangulated flat polygon. Pass Vector3.ZERO as `normal` to derive it
## from the winding of the points.
static func flat_polygon(points: Array, normal: Vector3) -> ArrayMesh:
	return flat_polygon_set([[points, normal]])


## Merges several flat polygons (given as [Array of Vector3, normal] pairs)
## into a single surface, so a whole tail fluke stays one draw call.
static func flat_polygon_set(parts: Array) -> ArrayMesh:
	var buffer: Array = [[], []]
	for part in parts:
		var points: Array = part[0]
		var normal: Vector3 = part[1]
		for i in range(1, points.size() - 1):
			if normal.length_squared() < 1e-9:
				_tri(buffer, points[0], points[i], points[i + 1])
			else:
				_tri_with_normal(buffer, points[0], points[i], points[i + 1], normal.normalized())
	var mesh := ArrayMesh.new()
	_add_surface(mesh, buffer, Basis.IDENTITY)
	return mesh


## Per-facet colour ramp from `low_y` to `high_y`, returned as a new mesh with
## an ARRAY_COLOR channel. The colour is taken once per triangle from the face
## centre, so a flat shaded mesh keeps crisp facet edges instead of smearing a
## gradient across a face. Used for the whale's pale belly / lavender back on a
## single mesh and material.
static func paint_by_height(mesh: ArrayMesh, low_y: float, high_y: float,
		low_color: Color, high_color: Color) -> ArrayMesh:
	var out := ArrayMesh.new()
	var span := maxf(high_y - low_y, 0.0001)
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors := PackedColorArray()
		colors.resize(verts.size())
		for t in verts.size() / 3:
			var centre := (verts[t * 3].y + verts[t * 3 + 1].y + verts[t * 3 + 2].y) / 3.0
			var color := low_color.lerp(high_color, clampf((centre - low_y) / span, 0.0, 1.0))
			for k in 3:
				colors[t * 3 + k] = color
		arrays[Mesh.ARRAY_COLOR] = colors
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# --- face buffers ----------------------------------------------------------
# For builders that need more than a lathe or a flat polygon — island_shell.gd
# sweeps its own polar grid — but must keep the same winding and flat shading.

static func new_faces() -> Array:
	return [[], []]


## Appends one triangle, given counter-clockwise as seen from outside.
static func add_face(faces: Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	_tri(faces, a, b, c)


## Turns a face buffer into the next surface of `mesh`. An empty buffer adds
## nothing, so surface indices stay predictable only while buffers are filled.
static func add_faces_surface(mesh: ArrayMesh, faces: Array) -> void:
	_add_surface(mesh, faces, Basis.IDENTITY)


## A tuft of tapered blades leaning outwards. Normals are biased upwards so
## the vertical blades still catch the sun instead of going flat grey.
static func grass_tuft(count: int, height: float, width: float, lean: float, seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parts: Array = []
	for i in count:
		var a := TAU * (float(i) / float(count)) + rng.randf_range(-0.35, 0.35)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var h := height * rng.randf_range(0.7, 1.2)
		var base := dir * width * 0.4
		var tip := base + dir * lean * h + Vector3(0.0, h, 0.0)
		var p0 := base - side * width * 0.5
		var p1 := base + side * width * 0.5
		var flat := (p1 - p0).cross(tip - p0).normalized()
		var n := (flat * 0.35 + Vector3.UP * 0.65).normalized()
		parts.append([[p0, p1, tip], n])
	return flat_polygon_set(parts)


# --- internals -------------------------------------------------------------

static func _average(points: Array) -> Vector3:
	var sum := Vector3.ZERO
	for v in points:
		sum += v
	return sum / float(points.size())


## Appends one flat-shaded triangle, given counter-clockwise from outside.
static func _tri(buffer: Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	_tri_with_normal(buffer, a, b, c, n.normalized())


static func _tri_with_normal(buffer: Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	# Arguments are counter-clockwise around `n`; Godot front faces are
	# clockwise, so b and c swap on the way in.
	var verts: Array = buffer[0]
	var norms: Array = buffer[1]
	verts.append(a)
	verts.append(c)
	verts.append(b)
	norms.append(n)
	norms.append(n)
	norms.append(n)


static func _add_surface(mesh: ArrayMesh, buffer: Array, basis: Basis) -> void:
	var verts: Array = buffer[0]
	if verts.is_empty():
		return
	var norms: Array = buffer[1]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var rotate := basis != Basis.IDENTITY
	for v in verts:
		out_v.push_back(basis * v if rotate else v)
	for n in norms:
		out_n.push_back((basis * n).normalized() if rotate else n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
