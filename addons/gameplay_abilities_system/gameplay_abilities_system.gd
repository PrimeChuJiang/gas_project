@tool
extends EditorPlugin


func _enable_plugin():
	# Add autoloads here.
	pass


func _disable_plugin():
	# Remove autoloads here.
	pass


func _enter_tree():
	# Initialization of the plugin goes here.
	add_autoload_singleton("GameplayCueManager", "res://addons/gameplay_abilities_system/scripts/gameplay_cue_manager.gd")
	pass


func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_autoload_singleton("GameplayCueManager")
	pass
