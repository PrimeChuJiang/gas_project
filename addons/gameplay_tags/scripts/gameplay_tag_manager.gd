@tool
extends Node
class_name GameplayTagsManager

# 项目设置（Project Settings）里这一项的 key 与默认值；插件注册和运行时读取共用同一份常量，避免字符串分裂
const SETTING_CONFIG_PATH := "gameplay_tags/config/config_file_path"
const DEFAULT_CONFIG_PATH := "res://addons/gameplay_tags/samples/config/default_gameplay_tags.cfg"

# 重定向映射表，键为旧StringName，值为新StringName
var _redirect_map : Dictionary = {}

# 持有这个运行时的数据代理资源对象
var _tags_data_list: GameplayTagsList

# 轨道 1（哈希字典）：用于 O(1) 的极速查找。Key 是 StringName，Value 是真·树节点对象
var _tag_node_map: Dictionary = {}

# 轨道 2（多叉树根）：对应 UE 的树根，存储最顶层的节点（如 Combat、State 等）
var _root_nodes: Array[FGameplayTagNode] = []

# Key 是 StringName，Value 是全局唯一的 FGameplayTag 对象实例
var _runtime_tag_pool: Dictionary = {}

# 默认资源路径
var config_resource_path = "res://addons/gameplay_tags/samples/resources/sample.tres"

func _ready():
	GameLogger.info("GameplayTagsManager", "正在初始化基础标签...")
	
# 1. 实例化我们的配置资源，并指定我们要读写的外部文本文件路径
	_tags_data_list = GameplayTagsList.new()
	# 从项目设置读取路径；若用户没配过（或插件还没注册），用默认值兜底
	_tags_data_list.config_file_path = ProjectSettings.get_setting(SETTING_CONFIG_PATH, DEFAULT_CONFIG_PATH)
	reload_tags_from_config()
	
	GameLogger.info("GameplayTagsManager", "初始化完成。当前注册标签总数: %d" % _runtime_tag_pool.size())

# 核心注册方法，将字符串转换为全局唯一的FGameplayTag对象，并且处理多叉树的层级拆分
func add_native_gameplay_tag(p_name: StringName) -> FGameplayTag:
	if p_name == &"": 
		return FGameplayTag.get_empty()
	
	# 如果已经完全注册过了，直接从我们的运行时池子里拿它
	if _tag_node_map.has(p_name):
		if not _runtime_tag_pool.has(p_name):
			_runtime_tag_pool[p_name] = FGameplayTag.new(p_name)
		return _runtime_tag_pool[p_name]
		
	var tag_string = String(p_name)
	var parts = tag_string.split(".")
	var current_path = ""
	var last_parent_node: FGameplayTagNode = null
	
	# 显式循环，长出多叉树的树枝
	for i in range(parts.size()):
		if i == 0: current_path = parts[i]
		else: current_path += "." + parts[i]
		
		var current_sn = StringName(current_path)
		var current_token = StringName(parts[i])
		
		var current_node: FGameplayTagNode
		if not _tag_node_map.has(current_sn):
			current_node = FGameplayTagNode.new()
			current_node.tag_token = current_token
			current_node.complete_tag_name = current_sn
			
			# 确立父子指针纽带
			if last_parent_node == null:
				_root_nodes.append(current_node)
			else:
				current_node.parent_node = last_parent_node
				last_parent_node.children.append(current_node)
			
			# 传承祖先链
			if last_parent_node != null:
				for parent_tag in last_parent_node.parent_tags_chain:
					current_node.parent_tags_chain[parent_tag] = true
			current_node.parent_tags_chain[current_sn] = true
			
			_tag_node_map[current_sn] = current_node
		else:
			current_node = _tag_node_map[current_sn]
			
		last_parent_node = current_node
		
	# 【核心绑定】：当多叉树这一枝长好后，确保这个长标签的名字在享元池里被唯一初始化
	if not _runtime_tag_pool.has(p_name):
		_runtime_tag_pool[p_name] = FGameplayTag.new(p_name)
		
	return _runtime_tag_pool[p_name]

# 外部索要接口，如果没找到则返回empty
func request_gameplay_tag(p_name : StringName, p_error_if_not_found : bool = true) -> FGameplayTag:
	if p_name == &"":
		return FGameplayTag.get_empty()
		
	# 1. 核心安全机制：如果请求的名字在池子里已经有了，100% 返回这同一个唯一实例（ObjectID 绝对一致）
	if _runtime_tag_pool.has(p_name):
		return _runtime_tag_pool[p_name]
		
	# 2. 如果池子里没有，但多叉树上合法注册过，说明是加载完被漏掉了，立刻实例化并补塞进池子
	if _tag_node_map.has(p_name):
		var new_tag = FGameplayTag.new(p_name)
		_runtime_tag_pool[p_name] = new_tag
		return new_tag
		
	# 3. 如果连多叉树上都没有，说明这个标签完全是非法的（比如配置加载失败或策划没配）
	if p_error_if_not_found:
		push_error("【GameplayTags】请求了未注册的非法标签（可能配置未成功读取）: ", p_name)
		
	# ❌ 重点修复：绝对不能返回同一个 _empty_tag 造成ObjectID串扰！
	# 我们为未注册的非法请求返回一个崭新的、独立的临时标签
	return FGameplayTag.new(&"")
	
## 对外接口：切换配置文件路径并立刻重新拉取（供项目设置变更时调用）
func set_config_path(path : String) -> void:
	if _tags_data_list == null:
		_tags_data_list = GameplayTagsList.new()
	_tags_data_list.config_file_path = path
	reload_tags_from_config()

## 核心删除/重载逻辑：清空旧内存，重新读取最新的文件数据
func reload_tags_from_config() -> void:
	_tag_node_map.clear()
	_root_nodes.clear()
	_runtime_tag_pool.clear()
	
	var target_path := _tags_data_list.config_file_path if _tags_data_list else ProjectSettings.get_setting(SETTING_CONFIG_PATH, DEFAULT_CONFIG_PATH)
	
	# 编辑器内确定是否有初始化的cfg文件
	_ensure_config_exists(target_path);
				
	# 确信存在后，正常数据加载（两端安全读取）
	_tags_data_list = GameplayTagsList.new()
	_tags_data_list.config_file_path = target_path
	_tags_data_list.load_from_config()
	
	# 重定向与多叉树重建保持不变...
	for re_data in _tags_data_list.gameplay_tag_redirects:
		var old_t = re_data.get("old_tag", &"")
		var new_t = re_data.get("new_tag", &"")
		if old_t != &"" and new_t != &"":
			_redirect_map[old_t] = new_t
			
	for tag_data in _tags_data_list.gameplay_tag_list:
		var t_name = tag_data.get("tag", &"")
		if t_name != &"":
			add_native_gameplay_tag(t_name)

func _ensure_config_exists(path : String) -> void:
	if not Engine.is_editor_hint(): return;
	if FileAccess.file_exists(path): return;
	GameLogger.info("[GameplayTagManager]", "创建初始化标签")
	var dir := path.get_base_dir();
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir);
	var _seed := GameplayTagsList.new();
	_seed.config_file_path = path;
	_seed.gameplay_tag_list = [
		{
		"tag": &"This.is.Tag1"
		},
		{
		"tag": &"This.is.Tag2"
		},
		{
		"tag": &"And.this.is.another.Tag.from.root"
		}
	]
	_seed.save_to_config();
	
