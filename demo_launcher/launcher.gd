extends Control

func _ready() -> void:
	$Center/VBox/CardButton.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://addons/gameplay_abilities_system/test/TestScene.tscn"))
	$Center/VBox/TopdownButton.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://addons/gameplay_abilities_system/test_topdown/TopdownDungeon.tscn"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				get_tree().change_scene_to_file("res://addons/gameplay_abilities_system/test/TestScene.tscn")
			KEY_2:
				get_tree().change_scene_to_file("res://addons/gameplay_abilities_system/test_topdown/TopdownDungeon.tscn")
