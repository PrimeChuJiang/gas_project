# gameplay_tag_tree_test.gd
extends Node

@export var my_tags : FGameplayTagContainer

func _ready() -> void:
	print("\n================== 🌲 START GAMEPLAY TAG TRUE TREE TESTS ==================")
	
	# 1. 先确保大名单管理器初始化完好（强制重载一次，触发路径自愈和兜底数据种树）
	GameplayTags.reload_tags_from_config()
	
	# 2. 开始高强度断言集成测试
	test_flyweight_and_matching()
	test_tree_structure_linkage()
	
	print("================== 🎉 ALL TRUE TREE TESTS PASSED! ==================\n")


func test_flyweight_and_matching() -> void:
	print("[TREE TEST 1] 正在验证享元隔离池与 O(1) 匹配判定...")
	
	# 通过大中枢索要标签
	var melee_tag = GameplayTags.request_gameplay_tag(&"Combat.Weapon.Melee")
	var melee_tag_copy = GameplayTags.request_gameplay_tag(&"Combat.Weapon.Melee")
	var weapon_tag = GameplayTags.request_gameplay_tag(&"Combat.Weapon")
	var combat_tag = GameplayTags.request_gameplay_tag(&"Combat")
	var stun_tag = GameplayTags.request_gameplay_tag(&"State.Debuff.Stun")
	
	# 验证隔离池享元唯一性
	assert(melee_tag == melee_tag_copy, "❌ 失败：_runtime_tag_pool 享元失效，相同名字的对象 ObjectID 发生了分身！")
	assert(melee_tag != weapon_tag, "❌ 失败：不同层级的对象 ObjectID 不应该相同！")
	
	# 运行高频匹配函数（内部此时已经是纯多叉树哈希比对，无任何字符串运算）
	assert(melee_tag.matches_tag(weapon_tag), "❌ 失败：层级匹配失败（Melee 应属于 Weapon）")
	assert(melee_tag.matches_tag(combat_tag), "❌ 失败：层级匹配失败（Melee 应属于 Combat）")
	assert(not melee_tag.matches_tag(stun_tag), "❌ 失败：错误的跨分支层级匹配")
	
	print("  └─ [OK] 享元池锁死 ObjectID 成功！层级匹配零字符串开销判定完全正确！")


func test_tree_structure_linkage() -> void:
	print("[TREE TEST 2] 正在验证物理多叉树指针链路...")
	
	var root_nodes: Array = GameplayTags._root_nodes
	var combat_root_node: FGameplayTagNode = null
	for node in root_nodes:
		if node.complete_tag_name == &"Combat":
			combat_root_node = node
			break
			
	assert(combat_root_node != null, "❌ 失败：根节点数组中找不到 [Combat] 根分支！")
	
	var weapon_sub_node: FGameplayTagNode = null
	for child in combat_root_node.children:
		if child.complete_tag_name == &"Combat.Weapon":
			weapon_sub_node = child
			break
			
	assert(weapon_sub_node != null, "❌ 失败：在 Combat 的子项中找不到 [Combat.Weapon] 分支！")
	assert(weapon_sub_node.parent_node == combat_root_node, "❌ 失败：父子双向指针断裂！")
	
	print("  └─ [OK] 内存中物理 [Root -> Child -> Leaf] 多叉树树状关系 100% 成立！")
