extends Node

func _enter_tree():
	var multi_way_tree : MultiwayTree = MultiwayTree.new();
	var head : node_t = multi_way_tree.read_file("res://addons/gameplay_tags/samples/scripts/test.txt");
	multi_way_tree._level_order(head);
	pass
