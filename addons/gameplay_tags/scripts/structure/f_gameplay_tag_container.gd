class_name FGameplayTagContainer
extends Resource

## 隐藏变量：专门给 Godot 引擎序列化保存字符串名字。场景保存时，会自动写入 .tscn
@export var _saved_tag_names: Array[StringName] = []:
	set(v):
		_saved_tag_names = v
		_restore_tags_from_saved_names()

# 使用字典作为底层，键为FGameplayTag对象，值为 bool（利用哈希表实现 O(1) 的增删改查）
var _tags: Dictionary = {}

## 内部桥接方法：从保存的 StringName 还原为高性能全局唯一指针对象
func _restore_tags_from_saved_names() -> void:
	_tags.clear()
	# 确保全局大脑存在
	if not Engine.has_singleton("GameplayTags") and not is_instance_valid(GameplayTags): 
		return
	
	for tag_name in _saved_tag_names:
		var runtime_tag = GameplayTags.request_gameplay_tag(tag_name, false)
		if runtime_tag.is_valid():
			_tags[runtime_tag] = true

## 核心接口：添加
func add_tag(tag: FGameplayTag) -> void:
	if tag and tag.is_valid():
		if not _tags.has(tag):
			_tags[tag] = true
			if not _saved_tag_names.has(tag.get_tag_name()):
				_saved_tag_names.append(tag.get_tag_name())
			emit_changed() # 触发脏标记，通知 Godot 场景需要保存

## 核心接口：删除
func remove_tag(tag: FGameplayTag) -> void:
	if tag and _tags.has(tag):
		_tags.erase(tag)
		_saved_tag_names.erase(tag.get_tag_name())
		emit_changed()

## 原有的层级匹配检索保持不变
func has_matching_tag(tag_to_check: FGameplayTag) -> bool:
	for owned_tag in _tags:
		if owned_tag.matches_tag(tag_to_check): return true
	return false

# 检查容器是否包含指定容器内的【任意一个】标签
# 对应 UE 的 HasAny
func has_any(other_container: FGameplayTagContainer) -> bool:
	for other_tag in other_container._tags:
		if has_matching_tag(other_tag):
			return true
	return false
