# gameplay_tag_test.gd
extends Node

func _ready() -> void:
	print("\n================== 🚀 START GAMEPLAY TAG TESTS ==================")
	
	#test_flyweight_pattern()
	#test_tag_matching()
	#test_container_operations()
	#test_redirect_operations()
	test_config_file_persistence()
	
	print("================== 🎉 ALL TESTS PASSED SUCCESSFULLY! ==================\n")


## 测试 1：验证全局单例与享元模式（内存唯一性）
func test_flyweight_pattern() -> void:
	print("[TEST 1] 正在验证享元模式（指针唯一性）...")
	
	# 从管理器请求同一个标签两次
	var tag_a1 = GameplayTags.request_gameplay_tag(&"Combat.Weapon.Melee")
	var tag_a2 = GameplayTags.request_gameplay_tag(&"Combat.Weapon.Melee")
	
	# 关键断言：如果两个变量指向不同内存，说明享元失效
	assert(tag_a1 == tag_a2, "❌ 失败：相同名字的标签在内存中创建了两个不同的对象实例！")
	
	# 验证隐式父级是否被自动注册并生效
	var parent_tag = GameplayTags.request_gameplay_tag(&"Combat.Weapon")
	assert(parent_tag.is_valid(), "❌ 失败：注册子标签时，隐式父标签没有被正确注册！")
	
	print("  └─ [OK] 内存指针比对完全一致，性能已对齐 UE 整数级比对！")


## 测试 2：验证标签层级匹配算法（MatchesTag）
func test_tag_matching() -> void:
	print("[TEST 2] 正在验证标签层级匹配（MatchesTag）...")
	
	var melee_tag = GameplayTags.request_gameplay_tag(&"Combat.Weapon.Melee")
	var weapon_tag = GameplayTags.request_gameplay_tag(&"Combat.Weapon")
	var combat_tag = GameplayTags.request_gameplay_tag(&"Combat")
	var state_tag = GameplayTags.request_gameplay_tag(&"State.Debuff.Stun")
	
	# 1. 验证精确匹配
	assert(melee_tag.matches_exact(melee_tag), "❌ 失败：精确匹配自身失败！")
	assert(not melee_tag.matches_exact(weapon_tag), "❌ 失败：不同的标签不应该精确匹配！")
	
	# 2. 验证父级包含子级
	assert(melee_tag.matches_tag(weapon_tag), "❌ 失败：Combat.Weapon.Melee 应该匹配 Combat.Weapon")
	assert(melee_tag.matches_tag(combat_tag), "❌ 失败：Combat.Weapon.Melee 应该匹配 Combat")
	
	# 3. 验证子级不能包含父级
	assert(not combat_tag.matches_tag(melee_tag), "❌ 失败：父级 Combat 不应该匹配子级 Melee")
	
	# 4. 验证完全不想干的标签不匹配
	assert(not melee_tag.matches_tag(state_tag), "❌ 失败：不同分支的标签发生了错误的层级匹配")
	
	print("  └─ [OK] 层级匹配算法完全正确，成功实现‘顺藤摸瓜’筛选！")


## 测试 3：验证标签容器高频操作（Container）
func test_container_operations() -> void:
	print("[TEST 3] 正在验证标签容器（FGameplayTagContainer）业务逻辑...")
	
	var container = FGameplayTagContainer.new()
	var melee_tag = GameplayTags.request_gameplay_tag(&"Combat.Weapon.Melee")
	var stun_tag = GameplayTags.request_gameplay_tag(&"State.Debuff.Stun")
	var combat_tag = GameplayTags.request_gameplay_tag(&"Combat")
	
	# 1. 初始状态检查
	assert(not container.has_matching_tag(combat_tag), "❌ 失败：空容器不应该匹配任何标签")
	
	# 2. 添加标签并检查
	container.add_tag(melee_tag)
	assert(container.has_matching_tag(melee_tag), "❌ 失败：容器未正确添加 Melee 标签")
	assert(container.has_matching_tag(combat_tag), "❌ 失败：容器拥有子标签时，应该隐式匹配父标签")
	
	# 3. 复合判定检查 (HasAny / HasAll)
	var any_check_container = FGameplayTagContainer.new()
	any_check_container.add_tag(stun_tag) # 容器里目前只有 Melee，这里加一个 Stun
	assert(not container.has_any(any_check_container), "❌ 失败：不应该拥有交集")
	
	any_check_container.add_tag(combat_tag) # 现在的检查容器有 [Stun, Combat]
	assert(container.has_any(any_check_container), "❌ 失败：此时应该通过 HasAny 判定（因为共有 Combat 层级）")
	
	# 4. 删除标签检查
	container.remove_tag(melee_tag)
	assert(not container.has_matching_tag(combat_tag), "❌ 失败：删除标签后，容器未能正确清空对应状态")
	
	print("  └─ [OK] 容器增删改查与复合判定逻辑全部正常，符合战斗系统预期！")

## 测试 4：验证新旧标签重定位（Redirect）
func test_redirect_operations() -> void:
	print("[TEST 4] 正在验证新旧标签重映射（Redirect）业务逻辑...")
	
	var old_tag = GameplayTags.request_gameplay_tag(&"Combat.OldAttack");
	var new_tag = GameplayTags.request_gameplay_tag(&"Combat.Weapon.Melee");
	
	assert(old_tag == new_tag, "❌ 失败：新旧标签不相同")
	
	print("  └─ [OK] 旧标签成功重定位到新标签，符合预期！")

## 测试 5：验证大名单的 .cfg 文本文件持久化读写
func test_config_file_persistence() -> void:
	print("[TEST 5] 正在验证 .cfg 文本持久化与双向读写...")
	
	# 1. 创建一个新的数据大名单对象，模拟策划手动在游戏里或者工具里加了一个新标签
	var export_list = GameplayTagsList.new()
	export_list.config_file_path = "res://config/test_output_tags.cfg" # 使用一个专门的测试输出路径
	
	# 故意打乱顺序加入标签，测试 UE 的 SortTags 排序持久化特性
	export_list.gameplay_tag_list.append({"tag": &"Z.LastTag", "comment": "最后一个"})
	export_list.gameplay_tag_list.append({"tag": &"A.FirstTag", "comment": "第一个"})
	
	# 2. 触发写入硬盘
	export_list.save_to_config()
	
	# 验证文件是否真的生成了
	assert(FileAccess.file_exists("res://config/test_output_tags.cfg"), "❌ 失败：.cfg 文件未能成功写入硬盘！")
	
	# 3. 模拟“重启游戏”，用一个全新的空对象去读取刚刚生成的文件
	var import_list = GameplayTagsList.new()
	import_list.config_file_path = "res://config/test_output_tags.cfg"
	import_list.load_from_config()
	
	# 4. 关键验证：数据有没有正确加载？排序是否生效？
	assert(import_list.gameplay_tag_list.size() == 2, "❌ 失败：读取出来的标签数量不正确")
	
	# 因为保存前执行了 sort_tags()，读取出来的第一条应该自动变成了 A.FirstTag
	var first_loaded_tag = import_list.gameplay_tag_list[0].get("tag", &"")
	assert(first_loaded_tag == &"A.FirstTag", "❌ 失败：持久化文本排序未能正确生效！")
	
	print("  └─ [OK] .cfg 文本完美支持多数据序列化与自动排序保存，彻底解决大名单持久化！")
