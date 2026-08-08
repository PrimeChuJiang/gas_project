class_name DungeonBoard
extends Node

enum TileType { EMPTY, TRAP, TREASURE, EXIT }

var tiles: Array[int] = []

func build(p_tiles: Array[int]) -> void:
	tiles = p_tiles.duplicate()

func get_length() -> int:
	return tiles.size()

func get_tile_type(index: int) -> int:
	if index < 0 or index >= tiles.size():
		return TileType.EMPTY
	return tiles[index]

func is_exit(index: int) -> bool:
	return index == tiles.size() - 1

func is_in_bounds(index: int) -> bool:
	return index >= 0 and index < tiles.size()
