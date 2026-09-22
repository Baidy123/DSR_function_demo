extends SceneTree
var checks := 0
var failed := 0
const IDS = ["patrol", "search", "engage", "cover", "attack_position", "suppression", "exit_suppression", "covering_retreat"]
func _initialize() -> void:
    var unit = load("res://enemy_unit_type.gd").new()
    var training = load("res://enemy_training.gd").new()
    check(unit.available_actions is Array, "兵种清单接受资源数组")
    check(training.allowed_actions is Array, "训练清单接受资源数组")
    if failed > 0:
        unit.free()
        training.free()
        finish()
        return
    for id in IDS:
        var path = "res://enemy_actions/" + id + ".tres"
        check(ResourceLoader.exists(path), "可拖拽资源存在 " + id)
        if not ResourceLoader.exists(path):
            continue
        var entry = load(path)
        check(entry.action_id == StringName(id) and not entry.display_name.is_empty(), "动作资源ID及中文名称 " + id)
        check(unit.has_action(id), "默认兵种拥有 " + id)
    var original = load("res://enemy_actions/attack_position.tres")
    var custom = original.duplicate()
    var replacement = GDScript.new()
    replacement.source_code = 'extends "res://enemy_attack_position_action.gd"\nvar resource_test_marker = true\n'
    check(replacement.reload() == OK, "自定义动作脚本编译")
    custom.implementation = replacement
    unit.available_actions.assign([null, custom])
    training.allowed_actions.assign([original])
    check(unit.has_action(&"attack_position") and training.allows_action(&"attack_position"), "不同资源同ID仍匹配训练权限")
    check(not unit.has_action(&"patrol"), "空槽不授予额外动作")
    var first = unit.create_actions()
    var second = unit.create_actions()
    check(first[&"attack_position"].get_script() == replacement, "资源脚本替换实际实现")
    check(first[&"attack_position"] != second[&"attack_position"], "共享资源不共享运行对象")
    check(original.implementation != replacement, "复制资源不修改公共实现")
    training.allowed_actions.clear()
    check(not training.allows_action(&"attack_position"), "删除资源撤销训练权限")
    unit.available_actions.clear()
    training.allowed_actions.assign([original])
    check(not unit.has_action(&"attack_position"), "训练不能赋予兵种没有的动作")
    var arena = load("res://arena.tscn").instantiate()
    check(arena.get_node("Enemy/UnitType").available_actions.size() == 8, "实际场景加载8个兵种动作")
    check(arena.get_node("Enemy/Training").allowed_actions.size() == 8, "实际场景加载8个训练动作")
    var scene_unit = arena.get_node("Enemy/UnitType")
    scene_unit.available_actions.remove_at(0)
    var scene_custom = scene_unit.available_actions[3].duplicate()
    scene_custom.display_name = "测试自定义架枪"
    scene_unit.available_actions[3] = scene_custom
    var packed = PackedScene.new()
    check(packed.pack(arena) == OK, "配置可打包保存")
    var file = "user://enemy_action_resources_roundtrip.tscn"
    check(ResourceSaver.save(packed, file) == OK, "场景资源写盘")
    var restored = load(file).instantiate()
    var restored_unit = restored.get_node("Enemy/UnitType")
    check(restored_unit.has_action(&"attack_position") and not restored_unit.has_action(&"patrol"), "重新加载保留增删后的权限")
    check(restored_unit.available_actions[3].display_name == "测试自定义架枪" and restored_unit.available_actions[3].implementation == original.implementation, "重新加载保留自定义资源与实现脚本")
    check(restored.get_node("Enemy/Training").allowed_actions[4].resource_path == original.resource_path, "训练保留公共资源引用")
    restored.free()
    arena.free()
    DirAccess.remove_absolute(file)
    unit.free()
    training.free()
    finish()
func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failed += 1
        print("FAIL ", label)
func finish() -> void:
    print("ACTION RESOURCES: ", checks-failed, "/", checks)
    quit(0 if failed == 0 else 1)
