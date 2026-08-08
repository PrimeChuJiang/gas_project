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

## 当前进度（2026-08-08 深夜）

- **最近一次提交**：`68f0c84`（Stacking 到期策略）；聚合器三阶段 + Stacking 全部代码已提交本地（远端由用户同步）
- **课程：聚合器（第 17 节）三阶段全部关账**（2026-08-08）：见上（第一步/第二步/第三阶段依赖登记簿，验证目标 1-5 全绿）
- **课程：Stacking（第 19 节）关账**（2026-08-08，渐进式六步）：
  - ✅ 身份判定 `_same_ge`（resource_path + 引用兜底，策划无可忘配置）；
    抓出 get_rid() 恒 RID(0) 潜伏 bug
  - ✅ `stack_policy`：NONE / LIMITED（+stack_limit，默认 1）/ REFRESH_DURATION；
    先验后发（检查在取号前）
  - ✅ 合并叠层：单条目 + stack_count + pile.stack_count + evaluate ADD ×count
    + `_sync_stack_count` 同步（与依赖登记簿互不冲突：重算写单层量）
  - ✅ 到期策略（方案 A）：REMOVE_SINGLE 掉层续满时长（不续=同帧连环掉层）/
    CLEAR_ENTIRE 整条删；主动移除永远整条（"到期策略不劫持主动动作"）
  - ✅ `get_stack_count(handle)` 层数查询（查无票返回 0）
  - ✅ 验证：LIMITED 上限、REFRESH 刷新、合并叠层同 handle、REMOVE_SINGLE
    逐层 250→200→150→100、主动移除整条、F 回归全绿
  - 已决：LIMITED=合并不续时长、REFRESH=合并+续时长+满层纯刷新（用户语义）；
    MULTIPLY/DIVIDE 不乘层数；叠层类型（AggregateBySource 等）未做
- **课程：数据处理层收官（第 20 节）关账**（2026-08-08 深夜，10 项清账）：
  - ✅ 8 项：捕获声明显式化（声明+fail-closed 校验）/ ApplicationTagRequirements
    （GASGameplayTagRequirements 类，免疫拒收）/ 驱散（has_any 复用）/
    OngoingTagRequirements（suspended flag，暂停恢复）/ 叠层类型
    （STACK_BY_SOURCE 独立栈）/ 周期叠层计时（reset_period_on_stack）/
    GE Level 层次 2（AttributeBased level_curve + CharacterLevel 属性 +
    登记簿实时——三件套合体）/ spec 级改写核查（已满足零改动）
  - ❌ 取消：SetByCaller key 换 tag（画蛇添足——与 data_key 无区别，用户否决）
  - ⏸ 挂起：tag 祖先计数 O(1)（matches_tag 已 O(1)，等真实需求）
  - 新账：Resource _init 零参铁律（必填参导致反序列化崩，探针定位）；
    快照离手即定（level 必须构建前传——GASEffectSpec._init(p_level)）；
    周期 GE 不挂账（_sync_stack_count 周期守卫）
- **下一课**（第二梯队第 1 位）：**GameplayCue**——`gameplay_cue_tags` 躺了
  十几节没人消费：OnActive / WhileActive / OnRemoved 三时刻，INSTANT 一次性 cue
  与 DURATION 持续 cue；原则预告：**逻辑不许知道表现存在**（信号只出不进）
- **路线图**（第 18 节，不变）：第一梯队 ✅ → GameplayCue → 更多 Task →
  TargetData；第三梯队 Tag 门禁（免疫/暂停/驱散已提前做完）→ Ability 间
  tag 关系；选修 GE Level 曲线（已完成层次2）；**网络同步明确不做**；加餐池
  照旧（tag 祖先计数 O(1)、首跳立即开关、spec 级改写已核查、SetByCaller
  key 换 tag 已判定画蛇添足）

## 核心架构速记（讲思路时的参照）

- 层次：Resource 定义层（GE/Ability）→ 实例层（Spec）→ 执行层（ASC/AttributeSet/AttributeData）→ 异步层（Task）→ 通信层（Tag）
- 9 条设计原则（DEVLOG 第 3 节）：先记账再放权 / 唯一收尾漏斗 / 生命周期不变量 / 门票代替引用 / fail-open vs fail-closed / CQS / 校验压在边界 / 计数+跳变沿 / 数据当参数传
- 已立的坑与教训：快照 vs 实时（离手即定，持续附着）、工厂填 source apply 填 target、改副本不另起炉灶、报错必须带拦截、resolved 即定案、代码与文档不能分家
