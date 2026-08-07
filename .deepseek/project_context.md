# project_context.md —— 项目状态快照

> 本文件记录**已验证/已落地**的事实。权威源头：仓库内 DEVLOG.md、git 历史。
> 最后更新：2026-08-04（会话 1，初始化记忆）

## 项目一句话

Godot 4.7（Forward Plus）下用 GDScript 复刻 UE GameplayAbilitySystem 单机版，
已实现 Attribute / GE / GESpec / ASC / Ability / Task / Tag 全链路，正在做结算深水区。

## 插件构成

- `addons/gameplay_abilities_system/` —— GAS 主体（scripts/ + test/ + DEVLOG.md）
- `addons/gameplay_tags/` —— Tag 系统（FGameplayTag、多叉树、编辑器 UI）
- `addons/logger/` —— 日志工具
- `docs/GAS_Documentation.md` —— 文档

## 已完成的课程（按 DEVLOG 节数）

1. Bug 修复三连：幽灵条目 / Task 尸体 / Effect Handle（第 1-4 节）
2. 冷却缩短 30%（虚函数缝 + CDR 属性）（第 7 节）
3. 属性上限联动 + attribute_initialized（第 8 节）
4. 眩晕打断 push 式打断 + 漏斗幂等（第 9-10 节）
5. EffectContext + make_effect_spec 工厂（第 11-12 节）
6. MMC：ModifierMagnitude 家族（ScalableFloat / AttributeBased / SetByCaller）
   + is_snapshot 开关（第 13-14 节）
7. ExecutionCalculation：多属性攻防结算 + 小票 EvaluatedData + DoT 实时结算
   + 木桩（第 15-16 节）

## 当前进度（2026-08-08）

- **最近一次提交**：`2678c97`（记忆更新，已 push）；聚合器实作代码已随本会话提交
- **课程：聚合器（第 17 节）第一步+第二步已关账**（2026-08-08）：
  - ✅ 第一步"先抽不改"：`_evaluate()` → `static evaluate(base, modifiers)`，
    current_value 走它；安检门全键回归通过（一个数不变）
  - ✅ 第二步 B 方案（聚合一次）：三本账并成一本——`apply_modifiers_to_base`
    唯一落账漏斗；INSTANT 与周期跳合并 `_apply_effect_modifiers`；execution
    拆 target/source 双桶；ADD-only 哨兵拆除
  - ✅ 类型化重构：GASModifierPile（op/magnitude/handle）+ GASModifierBucket
    （GDScript 禁嵌套类型化集合 → 薄持有类）；账本/参数全换
    `Array[GASModifierPile]`，evaluate 函数体零改动
  - ✅ 验证目标 1/2/3 全绿：回归全键；INSTANT MULTIPLY -0.5 → 500→250；
    execution 非 ADD 小票 → npc 500→250
  - 已决：DIVIDE 保留 1+m 语义（166 事件复盘：÷2 写 1.0）
- **待办：第三阶段（依赖登记簿，验证目标 4/5 的门）**：
  - 捕获声明成数据挂在配方上；apply 时登记"谁依赖谁"、连 attribute_changed；
    属性变 → 找受影响 modifier 重算 → 更新聚合器 magnitude → dirty → 信号级联
  - 注销与登记对称（`_cleanup_effect` 加拆线，温习 tag 引用计数）
  - 真实用例 `ge_buff_armor_from_attack`（DURATION，Armor += 30% source Attack，
    is_snapshot=false）——跨墙依赖 + 实时重算一靶两验
  - 设计未决：依赖环（A 依赖 B、B 依赖 A）第一课是否处理、至少是否看得见
- **路线图**（第 18 节，不变）：第一梯队 聚合器（第三阶段）→ Stacking
  （连按 2 无限叠 buff 已知问题正法）；第二梯队 GameplayCue → 更多 Task →
  TargetData；第三梯队 Tag 门禁（免疫/暂停/驱散）→ Ability 间 tag 关系；
  选修 GE Level 曲线；**网络同步明确不做**；加餐池照旧
  （tag 祖先计数 O(1)、首跳立即开关、SetByCaller key 换 tag、spec 级改写等）

## 核心架构速记（讲思路时的参照）

- 层次：Resource 定义层（GE/Ability）→ 实例层（Spec）→ 执行层（ASC/AttributeSet/AttributeData）→ 异步层（Task）→ 通信层（Tag）
- 9 条设计原则（DEVLOG 第 3 节）：先记账再放权 / 唯一收尾漏斗 / 生命周期不变量 / 门票代替引用 / fail-open vs fail-closed / CQS / 校验压在边界 / 计数+跳变沿 / 数据当参数传
- 已立的坑与教训：快照 vs 实时（离手即定，持续附着）、工厂填 source apply 填 target、改副本不另起炉灶、报错必须带拦截、resolved 即定案、代码与文档不能分家
