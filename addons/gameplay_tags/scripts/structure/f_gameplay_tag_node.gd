class_name FGameplayTagNode
extends RefCounted

# 当前节点的缩写名字 (e.g., 如果完整路径是 "A.B.C"，这里存 &"C")
var tag_token: StringName = &""

# 当前节点的完整标签名字 (e.g., &"A.B.C")
var complete_tag_name: StringName = &""

# 指向父节点的弱引用（防止循环引用导致内存泄漏）
var parent_node: FGameplayTagNode = null

# 存储所有子节点的数组（多叉树的核心结构）
var children: Array[FGameplayTagNode] = []

# 【核心优化】：预先缓存所有祖先节点的完整名字（等同于 UE 的完全匹配层级优化）
# 比如 A.B.C 节点的这个数组里会直接存着 [&"A", &"A.B", &"A.B.C"]
var parent_tags_chain: Dictionary = {}
