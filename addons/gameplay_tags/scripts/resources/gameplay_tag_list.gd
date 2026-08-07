@tool
extends Resource
class_name GameplayTagsList

## 对应 UE 的 ConfigFileName：关联的外部配置文件路径
@export var config_file_path: String = "res://addons/gameplay_tags/samples/config/default_gameplay_tags.cfg"

# 字典格式为{"tag": &"Combat.Weapon", "component": "备注"} 
@export var gameplay_tag_list : Array[Dictionary] = []

# 字典格式为{"old_tag": &"Old.Name", "new_tag": &"New.Name"}
@export var gameplay_tag_redirects : Array[Dictionary] = []

## 对应 UE 的 void UGameplayTagsList::SortTags()
func sort_tags() -> void:
	# 1. 按照标签名字字母序排序
	gameplay_tag_list.sort_custom(
		func(a: Dictionary, b: Dictionary):
			return String(a.get("tag", &"")) < String(b.get("tag", &""))
	)
	# 2. 按照旧标签名字字母序排序
	gameplay_tag_redirects.sort_custom(
		func(a: Dictionary, b: Dictionary):
			return String(a.get("old_tag", &"")) < String(b.get("old_tag", &""))
	)
	emit_changed()


## 从指定的 .cfg 文件读取并加载数据
func load_from_config() -> void:
	var config = ConfigFile.new()
	var err = config.load(config_file_path)
	if err != OK:
		GameLogger.warn("GameplayTagsList", "未能成功加载配置文件，可能文件不存在，将使用空列表。路径: %s" % config_file_path)
		return
		
	gameplay_tag_list.clear()
	gameplay_tag_redirects.clear()
	
	# 1. 读取有效标签列表 [GameplayTags] 部分
	if config.has_section("GameplayTags"):
		var tags = config.get_value("GameplayTags", "GameplayTagList", [])
		for tag_data in tags:
			if tag_data is Dictionary:
				gameplay_tag_list.append(tag_data)
				
	# 2. 读取重定向列表 [GameplayTagRedirects] 部分
	if config.has_section("GameplayTagRedirects"):
		var redirects = config.get_value("GameplayTagRedirects", "GameplayTagRedirects", [])
		for re_data in redirects:
			if re_data is Dictionary:
				gameplay_tag_redirects.append(re_data)
	
	GameLogger.info("GameplayTagsList", "成功从文本配置加载了 %d 个标签" % gameplay_tag_list.size())


## 将当前数据持久化保存到 .cfg 文件中
func save_to_config() -> void:
	# 保存前先像 UE 一样强制排序，方便 Git/P4 版本控制，防止文本冲突
	sort_tags()
	
	var config = ConfigFile.new()
	config.set_value("GameplayTags", "GameplayTagList", gameplay_tag_list)
	config.set_value("GameplayTagRedirects", "GameplayTagRedirects", gameplay_tag_redirects)
	
	# 确保目标文件夹存在
	var dir_path = config_file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
		
	var err = config.save(config_file_path)
	if err != OK:
		GameLogger.error("GameplayTagsList", "无法将配置保存到文件 %s" % config_file_path)
	else:
		GameLogger.info("GameplayTagsList", "成功将最新配置持久化到硬盘文本: %s" % config_file_path)
