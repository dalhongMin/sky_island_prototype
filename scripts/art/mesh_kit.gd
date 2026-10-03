extends RefCounted

## Lazily built, globally shared low-poly meshes.
##
## Every tree, tuft and pebble in the scene points at one of these Mesh
## resources, so adding content to a growth stage costs nodes but no new
## geometry. Static only: `MeshKit.get_mesh("trunk")`.

const LowPoly := preload("res://scripts/art/low_poly.gd")

static var _cache: Dictionary = {}


static func get_mesh(key: String) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var mesh := _build(key)
	_cache[key] = mesh
	return mesh


## Thin irregular disc, used for the pond surface. The island body itself is
## one shell per stage, built by scripts/art/island_shell.gd.
static func flat_disc(radius: float, seed_value: int) -> ArrayMesh:
	var key := "disc:%.2f:%d" % [radius, seed_value]
	if _cache.has(key):
		return _cache[key]
	var profile := [Vector2(radius, 0.0), Vector2(radius * 0.95, 0.07)]
	var mods := LowPoly.make_mods(8, 0.12, seed_value)
	var mesh := LowPoly.revolve(profile, 8, mods, false, true, false, 0.0, seed_value)
	_cache[key] = mesh
	return mesh


static func _build(key: String) -> ArrayMesh:
	match key:
		"trunk":
			return LowPoly.revolve([Vector2(0.10, 0.0), Vector2(0.072, 1.0)], 5, LowPoly.no_mods(), true, true)
		"leaf_low":
			return LowPoly.revolve([Vector2(0.64, 0.0), Vector2(0.0, 1.0)], 6, LowPoly.make_mods(6, 0.10, 101), true, false)
		"leaf_mid":
			return LowPoly.revolve([Vector2(0.50, 0.0), Vector2(0.0, 0.88)], 6, LowPoly.make_mods(6, 0.10, 102), true, false)
		"leaf_top":
			return LowPoly.revolve([Vector2(0.34, 0.0), Vector2(0.0, 0.72)], 6, LowPoly.make_mods(6, 0.10, 103), true, false)
		"pebble":
			return LowPoly.revolve([
				Vector2(0.0, 0.0), Vector2(0.50, 0.22), Vector2(0.40, 0.50), Vector2(0.0, 0.62),
			], 6, LowPoly.make_mods(6, 0.28, 211), false, false)
		"path_stone":
			return LowPoly.revolve([
				Vector2(0.0, 0.0), Vector2(0.50, 0.04), Vector2(0.44, 0.10), Vector2(0.0, 0.13),
			], 6, LowPoly.make_mods(6, 0.24, 222), false, false)
		"grass_a":
			return LowPoly.grass_tuft(5, 0.34, 0.085, 0.32, 311)
		"grass_b":
			return LowPoly.grass_tuft(4, 0.26, 0.075, 0.44, 312)
		"grass_c":
			return LowPoly.grass_tuft(6, 0.44, 0.095, 0.26, 313)
		"flower_stem":
			return LowPoly.revolve([Vector2(0.017, 0.0), Vector2(0.013, 0.26)], 3, LowPoly.no_mods(), false, false)
		"flower_head":
			return LowPoly.revolve([
				Vector2(0.0, 0.0), Vector2(0.090, 0.035), Vector2(0.055, 0.070), Vector2(0.0, 0.088),
			], 5, LowPoly.make_mods(5, 0.18, 401), false, false)
		"crystal":
			return LowPoly.revolve([
				Vector2(0.0, 0.0), Vector2(0.12, 0.16), Vector2(0.075, 0.42), Vector2(0.0, 0.66),
			], 5, LowPoly.make_mods(5, 0.14, 501), false, false)
		"lantern_post":
			return LowPoly.revolve([Vector2(0.055, 0.0), Vector2(0.042, 0.58)], 4, LowPoly.no_mods(), true, true)
		"lantern_globe":
			return LowPoly.revolve([
				Vector2(0.0, 0.0), Vector2(0.135, 0.10), Vector2(0.115, 0.23), Vector2(0.0, 0.31),
			], 6, LowPoly.make_mods(6, 0.10, 502), false, false)
		"cloud_puff_a":
			return LowPoly.revolve([
				Vector2(0.0, 0.0), Vector2(0.64, 0.30), Vector2(0.52, 0.64), Vector2(0.0, 0.86),
			], 7, LowPoly.make_mods(7, 0.22, 601), false, false)
		"cloud_puff_b":
			return LowPoly.revolve([
				Vector2(0.0, 0.0), Vector2(0.58, 0.26), Vector2(0.46, 0.58), Vector2(0.0, 0.80),
			], 7, LowPoly.make_mods(7, 0.26, 602), false, false)
	push_error("MeshKit: unknown mesh key '%s'" % key)
	return ArrayMesh.new()
