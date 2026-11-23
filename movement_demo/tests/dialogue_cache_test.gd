extends SceneTree

const Cache = preload("res://addons/dialogue_manager/utilities/dialogue_cache.gd")
var failures := 0
var fixture := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	fixture = "user://dialogue_cache_test_%d" % Time.get_ticks_usec()
	for directory in ["visible", "ignored/nested", "parent/ignored", ".godot", ".tmp"]:
		DirAccess.make_dir_recursive_absolute(fixture.path_join(directory))
	for name in ["root.dialogue", "visible/npc.dialogue", "ignored/hidden.dialogue",
			"ignored/nested/hidden.dialogue", "parent/ignored/hidden.dialogue",
			".godot/hidden.dialogue", ".tmp/hidden.dialogue", "visible/readme.txt",
			"ignored/.gdignore", "parent/ignored/.gdignore"]:
		var file := FileAccess.open(fixture.path_join(name), FileAccess.WRITE)
		if file == null:
			push_error("Unable to create dialogue cache fixture: " + name)
			_cleanup(fixture)
			quit(1)
			return
		file.store_string("")
		file.close()
	var found: PackedStringArray = Cache._get_dialogue_files_in_filesystem(fixture)
	_check(found.has(fixture.path_join("root.dialogue")), "root dialogue is included")
	_check(found.has(fixture.path_join("visible/npc.dialogue")), "visible nested dialogue is included")
	_check(found.size() == 2, "ignored descendants and non-dialogue files are excluded")
	_check(Cache._get_dialogue_files_in_filesystem(fixture.path_join("ignored")).is_empty(), "direct scan of ignored directory is empty")
	DirAccess.remove_absolute(fixture.path_join("ignored/.gdignore"))
	_check(Cache._get_dialogue_files_in_filesystem(fixture.path_join("ignored")).size() == 2, "removing the marker restores discovery on the next scan")
	_check(Cache._get_dialogue_files_in_filesystem(fixture.path_join("missing")).is_empty(), "missing directories remain harmless")
	_cleanup(fixture)
	print("Dialogue cache: %d/6 passed" % (6 - failures))
	quit(1 if failures else 0)


func _check(passed: bool, label: String) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1


func _cleanup(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in directory.get_directories():
		_cleanup(path.path_join(name))
	# Dot files/directories are part of this test's own temporary fixture.
	for name in [".gdignore", ".godot", ".tmp"]:
		var child := path.path_join(name)
		if DirAccess.dir_exists_absolute(child):
			_cleanup(child)
		elif FileAccess.file_exists(child):
			DirAccess.remove_absolute(child)
	DirAccess.remove_absolute(path)
