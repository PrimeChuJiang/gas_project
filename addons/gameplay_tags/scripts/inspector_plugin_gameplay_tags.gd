# inspector_plugin_gameplay_tags.gd
@tool
extends EditorInspectorPlugin

## 引擎内置虚函数：返回 true 代表这个插件想要拦截并处理这个类
func _can_handle(object: Object) -> bool:
	# 我们拦截所有对象
	return true


## 引擎内置虚函数：遍历对象的每一个属性
func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	# 关键判定：通过检查属性格子的底层类名，来精准拦截我们的 FGameplayTagContainer
	if hint_string == "FGameplayTagContainer" or object.get(name) is FGameplayTagContainer:
		# 实例化我们刚才写好的自定义按钮和弹出树控件
		var custom_property_cell = load("res://addons/gameplay_tags/scripts/editor_property_tag_container.gd").new()
		
		# 将其强行注入并替换掉 Godot 原生的渲染格子
		add_property_editor(name, custom_property_cell)
		
		# 返回 true 意味着：“这个格子被我承包了，Godot 你闭嘴不要再画默认输入框了！”
		return true
		
	return false # 其它不相关的属性放行，由 Godot 默认渲染
