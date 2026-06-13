extends Object
class_name node_t

var name : StringName;
var n_children : int;
var level : int;
var children : Array[node_t];
var parent : node_t

# 生成多叉树节点
static func create_node() -> node_t:
	var q = node_t.new();
	q.n_children = 0;
	q.level = -1;
	q.parent = null
	return q;

func _to_string():
	var children_name : String;
	for child in children:
		children_name = children_name + ", " + child.name;
	return "name : " + self.name + "\nchildren num : " + str(self.n_children) + "\nlevel : " + str(self.level) + "\nchildren" + children_name
