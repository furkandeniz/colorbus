class_name ValidationFsUtils
extends RefCounted
## Shared filesystem helpers for the validation checks in this directory.


## Recursively collects every file under `dir_path` whose name ends with
## `extension` (e.g. ".gd", ".json") into `out_files`.
static func collect_files_with_extension(dir_path: String, extension: String, out_files: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			collect_files_with_extension(full_path, extension, out_files)
		elif entry.ends_with(extension):
			out_files.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


## Recursively collects every file under `dir_path` whose name ends with any
## of `extensions` into `out_files`.
static func collect_files_with_extensions(dir_path: String, extensions: Array[String], out_files: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full_path: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			collect_files_with_extensions(full_path, extensions, out_files)
		else:
			for extension: String in extensions:
				if entry.ends_with(extension):
					out_files.append(full_path)
					break
		entry = dir.get_next()
	dir.list_dir_end()
