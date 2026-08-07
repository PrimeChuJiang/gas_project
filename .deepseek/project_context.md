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

## 当前进度（2026-08-04 晚）

- **最近一次提交**：`a5687c8`（热身清理 + 聚合器第一步，已 push origin/main）
- **课程：聚合器（Aggregator，第 17 节）进行中，处于第二步**：
  - ✅ 热身三小项清账（warn 文案补 "executions ignored" / docstring 旧示例删除 /
    `_registered_tags` 幽灵字段除根 / tags 插件日志统一 GameLogger / `%d`→`%s` 修复 /
    manager 的 const LL 死代码删除）
  - ✅ 第一步"先抽不改"：`attribute_data.gd` 的 `_evaluate()` 抽为
    `static func evaluate(base, modifiers)`，`current_value` 改走它，逻辑逐行一致
  - ⚠️ **未确认**：第一步安检门（"现有测试键一个数不变"）用户尚未口头确认跑过
  - ⏳ **第二步待开工**：按 op 语义改 base 的权威入口 + 三处落账收编（INSTANT 分支 /
    周期跳 / execution 小票）+ 拆 ADD-only 哨兵
    - 设计问题未决：**逐条串行（A）vs 聚合一次（B）**——A 保持现状行为（纯修病），
      B 让 INSTANT 与 DURATION 数学同构（定序与数组顺序解耦，行为变化需实验取证）；
      另需答：MULTIPLY magnitude 语义须与 `_evaluate` 一致（0.5 表示 ×1.5）
  - 后续：第三步依赖登记簿（跨墙依赖 + 实时重算），真实用例 `ge_buff_armor_from_attack`
  - 合账权威唯一化（`_evaluate()` 抽成静态纯函数）
  - INSTANT/周期跳/execution 三处 op 旧债清算（统一走按 op 语义改 base）
  - 捕获声明成数据 + 依赖重算（跨墙依赖 + 实时重算，第 18 节路线图第一梯队 1）
- **路线图**（第 18 节）：
  - 第一梯队：聚合器 → Stacking
  - 第二梯队：GameplayCue → 更多 AbilityTask → TargetData
  - 第三梯队：Tag 门禁（免疫/暂停/驱散）→ Ability 间 tag 关系
  - 选修：GE Level 曲线；**网络同步明确不做**
  - 加餐池：tag 祖先计数 O(1)、首跳立即开关、SetByCaller key 换 tag、spec 级改写等

## 待清的小遗留（第 17 节热身清理项）

1. warn 文案补后果半句（"executions ignored"）
2. 测试文件 docstring 旧 float magnitude 示例
3. GameplayTagsManager 启动日志"加载 6 个/注册总数 0"两行打架

## 核心架构速记（讲思路时的参照）

- 层次：Resource 定义层（GE/Ability）→ 实例层（Spec）→ 执行层（ASC/AttributeSet/AttributeData）→ 异步层（Task）→ 通信层（Tag）
- 9 条设计原则（DEVLOG 第 3 节）：先记账再放权 / 唯一收尾漏斗 / 生命周期不变量 / 门票代替引用 / fail-open vs fail-closed / CQS / 校验压在边界 / 计数+跳变沿 / 数据当参数传
- 已立的坑与教训：快照 vs 实时（离手即定，持续附着）、工厂填 source apply 填 target、改副本不另起炉灶、报错必须带拦截、resolved 即定案、代码与文档不能分家
