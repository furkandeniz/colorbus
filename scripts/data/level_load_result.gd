class_name LevelLoadResult
extends RefCounted
## Pure data: the outcome of LevelLoader.load_level(). `level` is null on
## any failure (missing file, malformed JSON, or a level that fails
## LevelValidator) and `errors` explains why -- callers must check
## is_success() rather than assume level is usable.

var level: LevelData = null
var errors: Array[String] = []


func is_success() -> bool:
	return level != null and errors.is_empty()
