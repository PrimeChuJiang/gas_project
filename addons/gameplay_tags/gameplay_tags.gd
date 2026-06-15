@tool
extends EditorPlugin

const GAMEPLAYTAGMANAGER_AUTOLOAD_NAME = "GameplayTags"

# 持有我们刚才写的 UI 面板的实例引用
var editor_instance: Control

var inspector_plugin_instance: EditorInspectorPlugin

# 缓存上一次的配置路径，用来判断 settings_changed 触发时到底是不是我们这一项变了
var _last_config_path: String = ""

func _enter_tree():
	# Initialization of the plugin goes here.
	# 先把项目设置注册好，确保 autoload 的 _ready 读取时这一项已经存在
	_register_project_settings()
	add_autoload_singleton(GAMEPLAYTAGMANAGER_AUTOLOAD_NAME, "res://addons/gameplay_tags/scripts/gameplay_tag_manager.gd");
	var editor_scene : Resource = load("res://addons/gameplay_tags/scenes/GameplayTagsEditor.tscn");
	if editor_scene:
		editor_instance = editor_scene.instantiate();
		add_control_to_bottom_panel(editor_instance, "Gameplay Tags Manager")
	# 1. 实例化我们的属性检查器拦截器
	inspector_plugin_instance = load("res://addons/gameplay_tags/scripts/inspector_plugin_gameplay_tags.gd").new()
	
	# 2. 正式向 Godot 引擎的全局检查器数据库注册
	add_inspector_plugin(inspector_plugin_instance)

	# 3. 记录当前路径，并监听项目设置变更，实现「改完路径自动重新拉取」
	_last_config_path = ProjectSettings.get_setting(GameplayTagsManager.SETTING_CONFIG_PATH, GameplayTagsManager.DEFAULT_CONFIG_PATH)
	if not ProjectSettings.settings_changed.is_connected(_on_project_settings_changed):
		ProjectSettings.settings_changed.connect(_on_project_settings_changed)
	pass


## 项目设置任意一项变动都会回调这里，所以先比对我们关心的那一项是否真的变了
func _on_project_settings_changed() -> void:
	var new_path: String = ProjectSettings.get_setting(GameplayTagsManager.SETTING_CONFIG_PATH, GameplayTagsManager.DEFAULT_CONFIG_PATH)
	if new_path == _last_config_path:
		return # 变的是别的设置，跟我们无关，直接忽略
	_last_config_path = new_path

	# 拿到运行中的 autoload 单例（@tool 脚本在编辑器里也会挂到 /root 下）
	var manager := get_node_or_null("/root/" + GAMEPLAYTAGMANAGER_AUTOLOAD_NAME) as GameplayTagsManager
	if manager:
		manager.set_config_path(new_path)

	# 让底部面板的标签树立刻重绘
	if editor_instance and editor_instance.has_method("refresh_tree_view"):
		editor_instance.refresh_tree_view()


## 向 Project Settings 注册「Gameplay Tags / config / config_file_path」这一项
func _register_project_settings() -> void:
	var key := GameplayTagsManager.SETTING_CONFIG_PATH
	var default_path := GameplayTagsManager.DEFAULT_CONFIG_PATH

	# 只有第一次（用户还没配过）才写入默认值，避免每次启用插件都覆盖用户已经改好的路径
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, default_path)

	# 设定「恢复默认」按钮指向的初始值
	ProjectSettings.set_initial_value(key, default_path)

	# 关键：声明它是「文件路径」类型，设置面板里就会出现一个带文件选择器的输入框，且只筛 .cfg
	ProjectSettings.add_property_info({
		"name": key,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.cfg",
	})

	# 设为「基础设置」，这样不开启右上角 Advanced Settings 也能直接看到
	ProjectSettings.set_as_basic(key, true)

	# 立刻持久化到 project.godot，避免重启后丢失
	ProjectSettings.save()

func _unregister_project_settings() -> void:
	var key := GameplayTagsManager.SETTING_CONFIG_PATH
	
	# 如果本来就没有了，那么我们也不用走删除逻辑
	if not ProjectSettings.has_setting(key):
		return;
	ProjectSettings.set_setting(key, null)

func _exit_tree():
	# Clean-up of the plugin goes here.
	# 先断开信号，避免插件热重载后留下悬空连接
	if ProjectSettings.settings_changed.is_connected(_on_project_settings_changed):
		ProjectSettings.settings_changed.disconnect(_on_project_settings_changed)
	remove_autoload_singleton(GAMEPLAYTAGMANAGER_AUTOLOAD_NAME)
	if editor_instance:
		# 显式从编辑器面板中移除
		remove_control_from_bottom_panel(editor_instance)
		editor_instance.queue_free()
	if inspector_plugin_instance:
		# 插件卸载时，必须干净地注销，否则会产生内存残留报错
		remove_inspector_plugin(inspector_plugin_instance)
	pass
