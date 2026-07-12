class_name GASAttributeSet
extends Resource

# 编辑器内静态配置属性，结构为{attribute_name(StringName) : data(AttributeData)}
@export var attributes : Dictionary = {}

# 运行时实际工作的属性映射表，结构为{attribute_name(StringName) : data(AttributeData)}
var _attributes: Dictionary = {}
# 宿主ASC
var asc : GASAbilitySystemComponent = null 

# 初始化运行数据
func initialize_attributes(owner_asc: GASAbilitySystemComponent):
	self.asc = owner_asc
	for attr_name in attributes.keys():
		var data = GASAttributeDATA.new()
		data.base_value = attributes[attr_name]
		data.current_value = data.base_value
		_attributes[attr_name] = data
		
# 获取最终计算值
func get_attribute_value(attr_name: StringName) -> float:
	if _attributes.has(attr_name):
		return _attributes[attr_name].current_value
	return 0.0
		
