class_name CheckLevelSolvability
extends RefCounted
## Runs LevelSolver against every level under res://data/levels -- a level
## that fails to load/validate at all is reported as a failure here too
## (a level that can't even load can't be solvable), and a level whose
## search is merely "inconclusive" (see LevelSolver.MAX_EXPLORED_STATES)
## also fails the check, never silently passing as solvable.


static func run() -> bool:
	var results: Array = LevelRepository.load_all_levels()

	var all_ok: bool = true
	for result: LevelLoadResult in results:
		if not result.is_success():
			all_ok = false
			for error: String in result.errors:
				print("[CheckLevelSolvability] load failed -> FAIL (%s)" % error)
			continue

		var level: LevelData = result.level
		var outcome: Dictionary = LevelSolver.solve(level)

		if outcome["solvable"]:
			print(
				"[CheckLevelSolvability] level %d (%s) -> OK (min_moves=%d, states_explored=%d)"
				% [level.id, level.name_key, outcome["min_moves"], outcome["states_explored"]]
			)
		else:
			all_ok = false
			print(
				"[CheckLevelSolvability] level %d (%s) -> FAIL (%s)"
				% [level.id, level.name_key, outcome["reason"]]
			)

	print("[CheckLevelSolvability] %d level(s) checked, result=%s" % [results.size(), "PASS" if all_ok else "FAIL"])
	return all_ok
