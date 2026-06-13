class_name FGameplayTag
extends RefCounted

# 使用 StringName（底层是唯一的指针/ID，比对速度极快，等同于 UE 的 FName）
var _tag_name: StringName = &""

# 静态空标签常量，对应 UE 的 FGameplayTag::EmptyTag
static var _empty_tag: FGameplayTag

static func get_empty() -> FGameplayTag:
	if not _empty_tag:
		_empty_tag = FGameplayTag.new()
	return _empty_tag

func _init(p_name : StringName = &""):
	_tag_name = p_name;

# 获取完整的标签字符串 (e.g., "Combat.Weapon.Melee")
func get_tag_name() -> StringName:
	return _tag_name

# 检查标签是否有效
func is_valid() -> bool:
	return _tag_name != &""

# 基于String(_tag_name)的字母进行排序
func is_less_than(other : FGameplayTag) -> bool:
	if not other :
		return false
	return String(self._tag_name) < String(other._tag_name)

# 核心算法 1：精确匹配 (Exact Match)
# 因为全局唯一，直接对比对象引用（指针），性能等同于 C++ 整数对比
func matches_exact(other: FGameplayTag) -> bool:
	if not other: return false
	return self == other

# 核心算法 2：层级包含匹配 (Matches Tag)
# 例如：自身是 "Combat.Weapon.Melee"，传入 "Combat.Weapon"，应该返回 true
func matches_tag(parent_tag: FGameplayTag) -> bool:
	if not is_valid() or not parent_tag.is_valid():
		return false
	if self._tag_name == parent_tag._tag_name:
		return true
		
	# 去中央大脑的双轨哈希表里，直接拿我自己的真·树节点
	var my_node: FGameplayTagNode = GameplayTags._tag_node_map.get(self._tag_name, null)
	if not my_node:
		return false
		
	# O(1) 判定：看我自己的祖先链缓存字典里，有没有包含父标签的名字
	return my_node.parent_tags_chain.has(parent_tag._tag_name)
