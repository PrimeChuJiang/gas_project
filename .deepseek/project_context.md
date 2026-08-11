# project_context.md —— 项目状态快照

> 本文件记录**已验证/已落地**的事实。权威源头：仓库内 DEVLOG.md、git 历史。
> 最后更新：2026-08-10（会话 3，GameplayCue 第 1+2 步关账、第 3 步开局）

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

## 当前进度（2026-08-10，会话 3）

- **最近一次提交**：`a95f3cb`（已推送 origin/main，12 文件）：GameplayCue
  第 1+2 步关账 + 第 3 步开局
- **课程：GameplayCue（第 21 节）—— 第 1 步关账（邮局事件流）**：
  - ✅ `GASEnums.GameplayCueEvent` 四事件（对齐 UE EGameplayCueEvent：
    ON_ACTIVE / WHILE_ACTIVE / EXECUTED / ON_REMOVED）
  - ✅ `GASGameplayCueManager`（Autoload）：`HandlerList` 内嵌薄类（注册表 +
    去重 warn + 倒序删除 + 快照遍历）；查无 handler 静默（表现空白合法）
  - ✅ ASC 三时刻钩子：INSTANT→EXECUTED、挂账后→ON_ACTIVE、remove_active_effect
    →ON_REMOVED（唯一漏斗单点）；叠层 early return 不重发（UE 同款）
  - ✅ 测试：GameplayCue.Status.Stun 进 config + ge_skeleton_stun.tres 配
    cue tag + 回归 count handler（OnActive/驱散/到期三断言），105 项全绿
- **课程：GameplayCue 第 2 步关账（参数小票）**：
  - ✅ `GASGameplayCueParameters`（RefCounted 空壳：target/instigator/magnitude
    ——快照离手即定，构造器不接 spec：变相传 spec + source_asc 可空两坑）
  - ✅ 签名三参统一全链路 `handler.call(tag, event, params)`（tag 数据当参数传，
    不存薄类）；magnitude 取第一个 modifier（execution 类缺口已记录）
  - ✅ 测试：params.target 非空 + 纯标签 GE magnitude==0，107 项全绿
- **课程：GameplayCue 第 3 步进行中（凭票制 + 节点生灭）**：
  - 已决：对齐 UE **句柄制**（Add 返回票、Remove 凭票退场、AGE 条目存票列表、
    Manager 内部按 tag 引用计数）——门票代替引用原则第三例；
  - 已决：实例身份 = `(tag, target)` 组合键（两人都眩晕 = 两颗星；UE 按 tag
    复用是已知粗糙点，我们修正实例粒度）；
  - ✅ 已落地：`ActiveCue` 薄类、`_cue_instances`（票根→账页）、`_active_cues`
    （组合键→账页）、`_cue_factories`（tag→工厂）、`register_factory`、
    `add_cue`（查账→0→1 调工厂挂 target 下→计数+1→发票；没工厂也发票）
  - ⏳ 待改三处：`factory` 用 `Callable()` 兜底（null 不能赋值值类型）、
    `node: Node` 上类型、register_factory 重复注册 warn
  - ⏳ 待做：`remove_cue`（凭票→计数-1→1→0 销毁销账→旧票无害化 false）；
    ASC 接线（entry 加 cue_handles、挂账后逐 tag add_cue 存票、移除逐票退场、
    INSTANT 改 execute_cue，原 ON_ACTIVE/ON_REMOVED 广播退役）；测试重写
    （工厂计数、节点生灭 is_instance_valid、双重施加一节点、旧票二次退场）；
    DEVLOG 第 21 节复盘（第 3 步关账时一并写）
- **本课踩坑记录**（新账）：
  - 迭代 Resource 本体崩溃：`for tag in container` → `_iter_next` 错误；
    正确姿势 `for tag in container._tags`（容器键是 FGameplayTag 对象，不是
    StringName——StringName 只在 `_saved_tag_names` 序列化通道）
  - `_init(spec)` 小票构造器被拦：变相传 spec + `spec.source_asc` 可空裸写必崩
  - 嵌套 typed collection 不支持 → 薄类 + 组合键两招破解
- **路线图**（第 18 节，不变）：第一梯队 ✅ → GameplayCue（进行中）→ 更多
  Task → TargetData；第三梯队 Tag 门禁（免疫/暂停/驱散已提前做完）→ Ability
  间 tag 关系；选修 GE Level 曲线（已完成层次2）；**网络同步明确不做**；加餐池
  照旧（tag 祖先计数 O(1)、首跳立即开关、spec 级改写已核查、SetByCaller
  key 换 tag 已判定画蛇添足）

## 当前进度（2026-08-11 晚，会话 5）

- **TargetActor 课（第 22 节需求 1 延伸）全关账**：基类 GASAbilityTargetActor
  （Node，缓存/信号/confirm 买定离手/cancel/跳变沿全量比较）+ GASAbilityTargetData
  .is_same_as 四步独立判定 + 2D 子类（select_at 点选 / select_area 范围多选 /
  _resolve_entity 过滤链）+ filter Callable 注入（逻辑层过滤，fail-open）；
  测试基础-63~90 全绿，**回归 171/0**（ExitCode=0）
- **需求 2 未开始**：WaitTargetData Task（把"等玩家选目标"包成 Task，task_finished
  出 TargetData，GA 起手挂 task）——下次课
- **新账（GDScript 坑）**：lambda 值捕获实锤——回调改外部局部变量无效，必须
  成员变量 + 命名函数（或容器）；已记 sessions/2026-08-11
- **想法清单**：重叠命中 z 排序、AOE 圈视觉预览、collide_with_areas 开关
  （当前测试用 StaticBody2D 规避）
- 环境备忘：同会话 4（Godot 4.7.1 路径、--import 缓存、TestScene --run-tests、
  Start-Process 重定向、输出文件 GBK 需 -Encoding UTF8 读取）

## 核心架构速记（讲思路时的参照）

- 层次：Resource 定义层（GE/Ability）→ 实例层（Spec）→ 执行层（ASC/AttributeSet/AttributeData）→ 异步层（Task）→ 通信层（Tag）
- 9 条设计原则（DEVLOG 第 3 节）：先记账再放权 / 唯一收尾漏斗 / 生命周期不变量 / 门票代替引用 / fail-open vs fail-closed / CQS / 校验压在边界 / 计数+跳变沿 / 数据当参数传
- 已立的坑与教训：快照 vs 实时（离手即定，持续附着）、工厂填 source apply 填 target、改副本不另起炉灶、报错必须带拦截、resolved 即定案、代码与文档不能分家
