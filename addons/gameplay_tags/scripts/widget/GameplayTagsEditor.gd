@tool
extends Control

@onready var tag_input: LineEdit = $VBoxContainer/HBoxContainer/TagInput
@onready var tag_tree: Tree = $VBoxContainer/TagTree
@onready var tag_comment: LineEdit = $VBoxContainer/HBoxContainer/TagComment

const LL := GameplayTagsLogger.LogLevel;

func _ready() -> void:
	# 防止在纯编辑视图渲染时报错（确保节点加载完）
	if not is_inside_tree(): return;
	
	# 重新绑定按钮（保持不变）
	$VBoxContainer/HBoxContainer/AddButton.pressed.connect(_on_add_pressed);
	$VBoxContainer/HBoxContainer/DeleteButton.pressed.connect(_on_delete_pressed);
	$VBoxContainer/HBoxContainer/SaveButton.pressed.connect(_on_save_pressed);
	
	tag_tree.hide_root = true;
	tag_tree.select_mode = Tree.SELECT_SINGLE;
	
	# 在纯编辑器状态下，自动拉取当前硬盘里的数据并渲染出来
	refresh_tree_view();


## 核心函数：将扁平的数据名单重新构造成 UI 上的多叉树
func refresh_tree_view() -> void:
	tag_tree.clear();
	
	# 1. 创建一个虚拟根节点
	var root : TreeItem = tag_tree.create_item();
	
	# 2. 从我们的全局大脑中拿到大名单数据源代理
	var data_list: GameplayTagsList = GameplayTags._tags_data_list;
	
	# 3. 维护一个临时字典，用来记录已经创建好的 UI 树节点指针，防止重复创建
	var ui_nodes: Dictionary = {};
	
	# 4. 遍历大名单，拆分并构建树
	for tag_data in data_list.gameplay_tag_list:
		var tag_name: String = str(tag_data.get("tag", ""));
		if tag_name.is_empty(): continue;
		
		var parts : Array = tag_name.split(".") as Array;
		var current_path : String = "";
		var parent_item : TreeItem = root;
		
		# 顺着路径一层层往下爬，在 UI 上建树
		for i in range(parts.size()):
			if i == 0: current_path = parts[i];
			else: current_path += "." + parts[i];
			
			var current_sn : StringName = StringName(current_path);
			
			if ui_nodes.has(current_sn):
				# 如果这一层的 UI 节点已经建过了，直接把它当作下一个层级的父节点
				parent_item = ui_nodes[current_sn];
			else:
				# 否则，在当前的父节点下，新建一个子 UI 节点
				var new_item: TreeItem = tag_tree.create_item(parent_item);
				new_item.set_text(0, parts[i]); # 只显示当前层级的名字 (如 Melee)
				new_item.set_metadata(0, current_sn); # 把完整的 StringName 塞进元数据，方便后续删除
				
				ui_nodes[current_sn] = new_item;
				parent_item = new_item;


## 添加新标签
func _on_add_pressed() -> void:
	var new_tag_str: String = tag_input.text.strip_edges();
	if new_tag_str.is_empty(): return;
	
	var data_list: GameplayTagsList = GameplayTags._tags_data_list;
	
	# 1. 检查大名单中是否已经存在
	var exists = false;
	for tag_data in data_list.gameplay_tag_list:
		if String(tag_data.get("tag", "")) == new_tag_str:
			exists = true;
			break;
			
	if exists:
		GameplayTagsLogger.print_log(LL.WARNING, "[GameplayTagsEditor]", "标签已存在于名单中，无需重复添加！");
		return;
	
	
	var comment_text : String = tag_comment.text.strip_edges();
		
	# 2. 将数据同步灌入大名单资源的内存数组中
	data_list.gameplay_tag_list.append({
		"tag": StringName(new_tag_str),
		"comment": comment_text
	});
	
	# 3. 让单例立刻注册这个新标签（动态更新运行时的多叉树）
	GameplayTags.add_native_gameplay_tag(StringName(new_tag_str));
	
	# 4. 清空输入框并刷新 UI 树
	tag_input.clear();
	refresh_tree_view();
	GameplayTagsLogger.print_log(LL.INFO, "[GameplayTagsEditor]", "成功添加标签: " + new_tag_str);
	_on_save_pressed();


## 删除选中的标签
func _on_delete_pressed() -> void:
	var selected_item: TreeItem = tag_tree.get_selected();
	if not selected_item:
		GameplayTagsLogger.print_log(LL.WARNING, "[GameplayTagsEditor]", "请先在树状图中选择一个你想删除的标签！");
		return;
	
	var full_tag_name: StringName = selected_item.get_metadata(0);
	var data_list: GameplayTagsList = GameplayTags._tags_data_list;
	
	# 1. 找出被选中的标签的“直接父级”路径
	# 例如：选中 A.B，那么它的直接父级就是 A
	var full_tag_str: String = String(full_tag_name);
	var last_dot_index: int = full_tag_str.rfind(".");
	var parent_tag_str: String = "";
	if last_dot_index != -1:
		parent_tag_str = full_tag_str.substr(0, last_dot_index); # 得到 "A"
	
	# 2. 检查这个父级 "A" 是否已经在我们的 .cfg 大名单数组里“显式注册”过了
	var is_parent_explicitly_registered: bool = false
	if not parent_tag_str.is_empty():
		for tag_data in data_list.gameplay_tag_list:
			if String(tag_data.get("tag", "")) == parent_tag_str:
				is_parent_explicitly_registered = true;
				break;

	# 3. 执行级联删除（删除自身 A.B 和子项 A.B.C）
	var delete_count : int = 0;
	var prefix_to_match: String = full_tag_str + ".";
	
	for i in range(data_list.gameplay_tag_list.size() - 1, -1, -1):
		var check_tag_name: String = String(data_list.gameplay_tag_list[i].get("tag", &""));
		if check_tag_name == full_tag_str or check_tag_name.begins_with(prefix_to_match):
			data_list.gameplay_tag_list.remove_at(i);
			delete_count += 1;
			
	# 4. 如果有父级（如 "A"），且它之前只是个隐式节点，
	# 那么既然现在它的子节点都被我们斩断了，为了不让 "A" 跟着消失，
	# 我们须在数据层将 "A" 显式补录进去
	if not parent_tag_str.is_empty() and not is_parent_explicitly_registered:
		data_list.gameplay_tag_list.append({
			"tag": StringName(parent_tag_str),
			"comment": "由于子项被删，由系统自动保留的父级标签"
		});
		GameplayTagsLogger.print_log(LL.INFO, "[GameplayTagsEditor]", "已将父级标签 [" + parent_tag_str + "] 转换为显式注册，防止其意外消失。")

	# 5. 刷新 UI 树状视图
	refresh_tree_view();
	GameplayTagsLogger.print_log(LL.INFO, "[GameplayTagsEditor]", "已从大名单数据中抹除目标项，共计移除行数: "+ str(delete_count) )
	_on_save_pressed();


## UI 动作：双向同步保存至 .cfg 文件
func _on_save_pressed() -> void:
	var data_list: GameplayTagsList = GameplayTags._tags_data_list;
	
	# 1. 将删除后的新数据状态物理写入到硬盘的 .cfg 文件中
	data_list.save_to_config();
	
	# 2. 核心联动：触发大名单管理器的完全重载，将内存中那些被删掉的标签彻底清洗干净
	GameplayTags.reload_tags_from_config();
	
	# 3. 刷新 Godot 编辑器的文件系统，让外部文件的变动立刻在引擎内生效
	if Engine.is_editor_hint():
		var editor_fs := EditorInterface.get_resource_filesystem();
		if editor_fs:
			editor_fs.scan();
			
	# 4. 最终重绘 UI 树
	refresh_tree_view();

	GameplayTagsLogger.print_log(LL.INFO, "[GameplayTagsEditor]", "删除操作已完全固化到外部文本，且编辑器单例已安全重新加载！")
