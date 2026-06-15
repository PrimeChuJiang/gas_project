# editor_property_tag_container.gd
@tool
extends EditorProperty

var _btn: Button;
var _popup: Window;
var _tree: Tree;
var _current_container: FGameplayTagContainer;
var _is_updating_tree_ui: bool = false;

func _init() -> void:
	_btn = Button.new();
	_btn.text = "编辑游戏标签 (GameplayTags)";
	_btn.pressed.connect(_on_button_pressed);
	add_child(_btn);
	set_bottom_editor(_btn);


func _update_property() -> void:
	var obj = get_edited_object();
	var prop = get_edited_property();
	if obj:
		_current_container = obj.get(prop);
		
	if _current_container and !_current_container._saved_tag_names.is_empty():
		_btn.text = "GameplayTags (" + str(_current_container._saved_tag_names.size()) + "个已选中)";
	else:
		_btn.text = "GameplayTags (0个已选中)";


func _on_button_pressed() -> void:
	var obj = get_edited_object();
	var prop = get_edited_property();
	
	_current_container = obj.get(prop);
	if not _current_container:
		_current_container = FGameplayTagContainer.new();
		obj.set(prop, _current_container);
		emit_changed(prop, _current_container);
		
	_popup = Window.new();
	_popup.title = "选择内置标签 (多选树状菜单)";
	_popup.position = Vector2i(100, 100);
	_popup.size = Vector2i(450, 550);
	_popup.close_requested.connect(_on_popup_closed);
	
	var vbox = VBoxContainer.new();
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
	_popup.add_child(vbox);
	
	_tree = Tree.new();
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	_tree.hide_root = true;
	_tree.columns = 1;
	
	# 监听单元格修改事件
	_tree.item_edited.connect(_on_tree_item_edited);
	vbox.add_child(_tree);
	
	_rebuild_popup_tree();
	
	EditorInterface.get_base_control().add_child(_popup);
	_popup.popup_centered();


func _rebuild_popup_tree() -> void:
	_is_updating_tree_ui = true;
	_tree.clear();
	var root = _tree.create_item();
	var data_list = GameplayTags._tags_data_list;
	var ui_nodes: Dictionary = {};
	
	if not data_list: 
		_is_updating_tree_ui = false;
		return;
		
	for tag_data in data_list.gameplay_tag_list:
		var tag_name: String = String(tag_data.get("tag", ""));
		if tag_name.is_empty(): continue;
		
		var parts = tag_name.split(".");
		var current_path = "";
		var parent_item = root;
		
		for i in range(parts.size()):
			if i == 0: current_path = parts[i];
			else: current_path += "." + parts[i];
			var current_sn = StringName(current_path);
			
			if ui_nodes.has(current_sn):
				parent_item = ui_nodes[current_sn];
			else:
				var new_item: TreeItem = _tree.create_item(parent_item);
				new_item.set_metadata(0, current_sn);
				new_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK);
				new_item.set_text(0, " " + parts[i]);
				new_item.set_editable(0, true);
				
				if _current_container and _current_container._saved_tag_names.has(current_sn):
					new_item.set_checked(0, true);
					
				ui_nodes[current_sn] = new_item;
				parent_item = new_item;
				
	_is_updating_tree_ui = false;


## 【核心重写】：手写精准控制的 UE 级联算法（彻底抛弃原生的偏激广播）
func _on_tree_item_edited() -> void:
	if _is_updating_tree_ui: return;
	_is_updating_tree_ui = true;
	
	var edited_item = _tree.get_edited();
	if not edited_item:
		_is_updating_tree_ui = false;
		return;
		
	var is_checked: bool = edited_item.is_checked(0);
	
	# 【核心机制 1】：向上联动（子推父）
	# 如果当前节点被打勾了，强制让它头顶所有的长辈节点也全部联动打勾
	if is_checked:
		var p_item = edited_item.get_parent();
		while p_item and p_item != _tree.get_root():
			p_item.set_checked(0, true);
			p_item = p_item.get_parent();
			
	# 【核心机制 2】：向下联动（父砍子）
	# 如果当前节点被取消打勾了，强制让它下面连带的所有子孙节点全部熄灭
	else:
		_recursive_uncheck_children(edited_item);
		
	# 【核心机制 3】：独立性（父不推子）
	# 观察上面的代码：当勾选一个父节点时，没有任何代码去操作它的 children 数组，因此子节点保持不动！
	
	# 双向同步回灌数据结构
	_sync_container_with_ui_tree()
	_is_updating_tree_ui = false;


## 内部递归：安全取消所有子项勾选样式
func _recursive_uncheck_children(p_item: TreeItem) -> void:
	for child in p_item.get_children():
		child.set_checked(0, false);
		_recursive_uncheck_children(child);


func _sync_container_with_ui_tree() -> void:
	if !_current_container: return;
	
	var new_saved_names: Array[StringName] = [];
	var root = _tree.get_root();
	if root:
		_collect_checked_metadata(root, new_saved_names);
		
	_current_container._saved_tag_names = new_saved_names;
	_current_container.emit_changed();
	emit_changed(get_edited_property(), _current_container);
	_update_property();


func _on_popup_closed() -> void:
	if _current_container:
		_sync_container_with_ui_tree();
		get_edited_object().notify_property_list_changed();
	if _popup:
		_popup.queue_free();
	print("💾 【GameplayTags】成功保存！");


func _collect_checked_metadata(item: TreeItem, collected: Array[StringName]) -> void:
	for child in item.get_children():
		if child.is_checked(0):
			var sn: StringName = child.get_metadata(0);
			if sn != &"":
				collected.append(sn);
		_collect_checked_metadata(child, collected);
