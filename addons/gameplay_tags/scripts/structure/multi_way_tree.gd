extends Object
class_name MultiwayTree
	
static var M : int = 100 + 1;

## 栈
class stack_t extends Object:
	var array : Array[node_t];
	var index : int = 0;
	var size : int = 0;

## 队列
class queue_t extends Object:
	var array : Array[node_t];
	var head : int = 0;
	var tail : int = 0;
	var size : int = 0;
	var num : int = 0;

## 栈操作

# 初始化栈
func stack_init(size : int) -> stack_t:
	var sp = stack_t.new();
	sp.size = size;
	sp.index = 0;
	sp.array = [];
	sp.resize(size);
	return sp;

# 检测栈是否为空，为空返回1，否则返回0
func stack_empty(sp : stack_t) -> int:
	if sp == null or sp.index <=0:
		return 1;
	return 0;
	
# 压栈
func stack_push(sp : stack_t, x : node_t) -> int:
	if (sp == null or sp.index >= sp.size):
		return 0;
	sp.array[sp.index] = x;
	sp.index += 1;
	return 1;
	
# 弹栈
func stack_pop(sp : stack_t, x : node_t) -> int:
	if (sp == null or sp.index <=0):
		return 0;
	x = sp.array[sp.index - 1];
	sp.index -= 1;
	return 1;

# 销毁栈
func stack_destroy(sp : stack_t):
	sp.free();
	
## 队列操作

# 初始化队列
func queue_init(size : int) -> queue_t:
	var qp = queue_t.new();
	qp.size = size;
	qp.head = 0;
	qp.tail = 0;
	qp.num = 0;
	qp.array = [];
	qp.resize(size);
	return qp;
	
# 检测队列是否为空，为空返回1，否则返回0
func queue_empty(qp : queue_t) -> int:
	if qp == null or qp.num <= 0:
		return 1;
	return 0;
	
# 入队列
func queue_enqueue(qp : queue_t, x : node_t) -> int:
	if (qp == null or qp.num >= qp.size):
		return 0;
	qp.array[qp.tail] = x;
	qp.tail = (qp.tail + 1) % qp.size;
	qp.num += 1;
	return 1;

# 出队列
func queue_dequeue(qp : queue_t, x : node_t) -> int:
	if (qp == null or qp.num <=0):
		return 0;
	x = qp.array[qp.head];
	qp.head = (qp.head + 1) % qp.size;
	qp.num -= 1;
	return 1;
	
# 销毁队列
func queue_destroy(qp : queue_t):
	qp.free();

## 多叉树操作

# 按照节点名称查找
static func search_node_r(head : node_t, name : StringName) -> node_t:
	var temp : node_t = null;
	if head != null :
		if name == head.name : 
			temp = head;
		else :
			for i in range(head.n_children) :
				if temp != null:
					break;
				else:
					temp = search_node_r(head.children[i], name);
	return temp;

# 从文件中读取多叉树数据，并建立多叉树
func read_file(path : String, head : node_t = null) -> node_t:
	var temp : node_t = null;
	var n : int = 0;
	var file = FileAccess.open(path, FileAccess.ModeFlags.READ);
	if file == null :
		push_error("read_file: 无法打开文件， 路径名为： " + path);
		return;
	var regex : RegEx = RegEx.new();
	regex.compile("\\S+");
	while not file.eof_reached() :
		var line = file.get_line();
		var result : Array[RegExMatch] = regex.search_all(line);
		var name = result[0].get_string();
		n = result[1].get_string() as int;
		var line_childs : Array;
		if result.size() > 2:
			line_childs = result.duplicate().slice(2);
		else:
			line_childs = [];
		if head == null:
			temp = node_t.create_node();
			temp.name = name;
			temp.level = 0;
			head = temp;
		else :
			temp = search_node_r(head, name)
		
		temp.n_children = n;
		temp.children = [];
		temp.children.resize(n);
		
		
		if temp.children == null :
			push_error("read_file: 无法分配内存， 跂点名为： " + name);
			return;
		for i in range(n):
			var child = line_childs[i].get_string();
			temp.children[i] = node_t.create_node();
			temp.children[i].name = child;
			temp.children[i].parent = temp;
			temp.children[i].level = temp.level + 1;
	file.close();
	return head;

# 销毁树
func free_tree(head : node_t) -> void:
	if head == null : return;
	for i in range(head.n_children):
		free_tree(head.children[i]);
	head.free();

## 多叉树遍历，代码做示例

# 层次优先遍历输出多叉树
func _level_order(head : node_t) -> void:
	if head == null:
		return;
	var i : int = 0;
	var child : node_t = null;
	while i < head.n_children:
		child = head.children[i];
		if child == null : 
			push_error("_level_order_ERROR: 节点名为： " + head.name + "， 子节点名为： " + child.name);
			i += 1;
			continue;
		_level_order(child);
		i += 1;
	print(head);
	
