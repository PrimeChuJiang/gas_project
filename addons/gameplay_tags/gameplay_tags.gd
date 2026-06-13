@tool
extends EditorPlugin

const GAMEPLAYTAGMANAGER_AUTOLOAD_NAME = "GameplayTags"

# 持有我们刚才写的 UI 面板的实例引用
var editor_instance: Control

var inspector_plugin_instance: EditorInspectorPlugin

func _enter_tree():
	# Initialization of the plugin goes here.
	add_autoload_singleton(GAMEPLAYTAGMANAGER_AUTOLOAD_NAME, "res://addons/gameplay_tags/scripts/gameplay_tag_manager.gd");
	var editor_scene : Resource = load("res://addons/gameplay_tags/scenes/GameplayTagsEditor.tscn");
	if editor_scene:
		editor_instance = editor_scene.instantiate();
		add_control_to_bottom_panel(editor_instance, "Gameplay Tags Manager")
	# 1. 实例化我们的属性检查器拦截器
	inspector_plugin_instance = load("res://addons/gameplay_tags/scripts/inspector_plugin_gameplay_tags.gd").new()
	
	# 2. 正式向 Godot 引擎的全局检查器数据库注册
	add_inspector_plugin(inspector_plugin_instance)
	pass


func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_autoload_singleton(GAMEPLAYTAGMANAGER_AUTOLOAD_NAME)
	if editor_instance:
		# 显式从编辑器面板中移除
		remove_control_from_bottom_panel(editor_instance)
		editor_instance.queue_free()
	if inspector_plugin_instance:
		# 插件卸载时，必须干净地注销，否则会产生内存残留报错
		remove_inspector_plugin(inspector_plugin_instance)
	pass
