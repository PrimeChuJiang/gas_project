class_name TopdownChest
extends TopdownEntity

var opened: bool = false

func setup_chest() -> void:
	setup_entity("宝箱", {&"Health": 1.0, &"MaxHealth": 1.0})
