class_name LevelRepository
extends RefCounted
## Enumerates and loads every level under data/levels/. A broken level
## file never stops the rest from loading -- each file gets its own
## independent LevelLoadResult.

const LEVELS_DIRECTORY: String = "res://data/levels"


## Every level JSON file's path under data/levels/, sorted for
## deterministic ordering (level_01.json before level_02.json, etc).
static func list_level_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(LEVELS_DIRECTORY)
	if dir == null:
		return paths

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			paths.append(LEVELS_DIRECTORY.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()

	paths.sort()
	return paths


## Loads and validates every level file found under data/levels/, in path
## order. Each result stands on its own -- one broken file among five
## doesn't prevent the other four from loading.
static func load_all_levels() -> Array[LevelLoadResult]:
	var results: Array[LevelLoadResult] = []
	for path: String in list_level_paths():
		results.append(LevelLoader.load_level(path))
	return results


## Loads a single level by its numeric id, searching every file under
## data/levels/. Returns a LevelLoadResult with a descriptive error (not a
## crash) if no file defines that id.
static func load_level_by_id(id: int) -> LevelLoadResult:
	for path: String in list_level_paths():
		var result: LevelLoadResult = LevelLoader.load_level(path)
		if result.level != null and result.level.id == id:
			return result

	var not_found: LevelLoadResult = LevelLoadResult.new()
	not_found.errors.append("no level file under %s defines id %d" % [LEVELS_DIRECTORY, id])
	return not_found
