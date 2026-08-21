# project_context.md —— 项目状态快照

> 本文件记录**已验证/已落地**的事实。权威源头：仓库内 DEVLOG.md、git 历史。
> 最后更新：2026-08-14（会话 6，九课关账：UE GAS 单机版全貌对齐完毕）

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

## 当前进度（2026-08-11 晚，会话 5 续）

- **TargetActor 课（第 22 节）全关账**（git `54d416d` 已推送）：
  - 基类 GASAbilityTargetActor（Node，缓存/跳变沿/confirm 买定离手/cancel/filter 注入）
  - GASAbilityTargetData.is_same_as 四步独立判定 + ENTITY_META 协议
  - 2D 子类 select_at（点选）/ select_area（范围多选）/ _resolve_entity 过滤链
  - **GASAbilityTaskWaitTargetData**（注入实例、confirm 拒绝空选、取消路径善后、
    get_target_data 交付）——需求 2 同课完成
  - 测试基础-50~111 共 62 条，**回归 192/0**（ExitCode=0）
- **新账**：GDScript lambda 值捕获（回调改外部变量无效，成员变量+命名函数）——
  我自己写测试也踩了；新 class_name 需 --import 重建类缓存；场景编译失败时
  Godot 不退出会挂死 WaitForExit
- **已还欠账**（git `a4a0b9d` 已推送）：DEVLOG 第 21 节（GameplayCue 四步）与
  第 22 节（TargetData 课三需求）复盘已补写
- **遗留小账收尾**（2026-08-14，DEVLOG 22.5）：
  - ✅ z 排序（框架，用户实现）：sort_custom + 契约（z 降序、y 平手裁判），
    红测试基础-112~117 转绿
  - ✅ demo2 接真选择器 + AOE 预览（落雷技能：右键瞄准/左键确认/右键取消，
    WaitTargetData 全链路，怪物物理身份证 StaticBody2D+ENTITY_META）
  - ✅ ge_damage_50.tres 死资产（查证：磁盘早已不存在）
  - ❌ collide_with_areas 开关：无消费者，画蛇添足取消（第二例）
  - 测试侧新账：headless await 两帧才稳；monsters 数组顺序不可靠（重生 append）；
    Attack=35 暗雷（铁剑+15）→ 断言读属性现算
- **回归**：桌游 198/0 + topdown 63/0 全绿，双 UI 检查 issues=0
- **WaitInput 课（第 23 节）关账**（2026-08-14）：
  - ✅ `GASAbilityTaskWaitInput`（框架，用户实现）：等输入动作 + 超时窗口
    （`create(ability, input_action, timeout=-1)`，按下 end_task(false)/超时 end_task(true)，
    轮询 `is_action_just_pressed`——headless 可模拟，与超时共用 _process）
  - ✅ demo2 连击技能：普攻后 0.6s 窗口按攻击键 → 强化斩击（×1.5/110/50°），
    开窗点在 game 攻击落点、`open_combo` 参数防无限连、场景层 combo active 时按键被消费
  - ✅ 回归：topdown 63→**75/0**（连击 12 条），桌游 198/0 无回归
  - 测试新账：普攻 CD 挡二次开窗（先等 0.6s）；伤害累计致死 freed（回血复战）
- **WaitAnimNotify 课（第 24 节）关账**（2026-08-14）：
  - ✅ `GASAbilityTaskWaitAnimNotify`（框架，用户实现）：等通知源动态信号 +
    名称匹配（`create(ability, source, signal, name)`）；**CONNECT_ONE_SHOT 语义
    陷阱**——按触发次数断连而非按匹配断连，正确姿势普通连接 + is_running 守卫
  - ✅ 落雷前摇：确认后法阵 0.4s（表现层 _vfx）→ 命中帧 emit anim_notify →
    结算；快照离手即定（targets/center confirm 时定）；前摇可打断（无伤害 +
    通知无人听合法）
  - ✅ 回归：topdown 75→**92/0**（天罚重写 34 条），桌游 198/0，UI 0
- **互斥矩阵课（第 25 节）关账**（2026-08-14）：
  - ✅ 框架（用户）：`block_abilities_with_tags` / `cancel_abilities_with_tags`
    两字段 + try_activate_ability 四段式（block 拒绝 → cancel 打断 → 激活）；
    **审查抓出字段张冠李戴**（记法：has_any 容器=我的列表，参数=对方身份 tag）
  - ✅ 狂暴技能（Q）：3s 攻击力 ×2，buff 能力保持激活（block 窗口），
    tag 消失（GE 到期/移除）→ 结束；覆写 end_ability 断连防 RefCounted 泄漏；
    互斥自洽方案：狂暴 cancel 落雷前摇 + block 落雷激活（用户否决自相矛盾版）
  - ✅ 回归：topdown 92→**111/0**（狂暴 19 条），桌游 198/0，UI 0
- **GE 授予 + 被动能力课（第 26 节）关账**（2026-08-14）：
  - ✅ 框架（用户）：`granted_abilities` + `activate_abilities_on_grant` 两字段；
    **引用计数**（_ability_grant_counts，tag 同款：先给后记账/归零才移除）；
    entry 凭据 + _cleanup_effect 回收（唯一漏斗）；INSTANT fail-closed
    （审查三连错修正：位置/缺 return/文案假口供）
  - ✅ 圣光护符：佩戴 → 授予即激活圣光被动（Defense +5，能力自己挂 GE 自清理）；
    摘除 → 能力回收 → buff 回退
  - ✅ 回归：topdown 111→**136/0**（授予 25 条），桌游 198/0，UI 0
  - 新账：catalog 引用 null 陷阱（创建顺序）；装备槽存显示名非 key
- **事件驱动激活课（第 27 节）关账**（2026-08-14）：
  - ✅ 框架（用户）：`GASGameplayEventData` 小票 + `activation_event_tags`/
    `last_event_data`（ASC 注入零破坏）+ `send_gameplay_event_to_actor` →
    `_on_gameplay_event` 层级匹配激活；**事件=激活入口非授予机制**
    （没 grant 的能力事件激活不了——UE 同款）；审查抓拼写/字段缺失两编译错
  - ✅ 复仇技能：受击发 GameplayEvent.Hurt（带伤害量）→ 自动激活 →
    3s 攻击 ×1.2（buff 带 granted tag 可驱散）+ 5s 冷却
  - ✅ 回归：topdown 136→**145/0**（事件 9 条），桌游 198/0，UI 0
  - 新账：**enable_vengeance 开关隔离测试**（复仇污染全测试：AI 触发不可控，
    断言必须建立在可控状态上）
- **Loose Tags 课（第 28 节）关账**（2026-08-14）：
  - ✅ 框架（用户）：`add_loose_tag` / `remove_loose_tag` 两薄壳公开方法
    （无效 tag 防御 + 复用 _add/_remove_owned_tag）——Loose 无需新机制，
    与 GE 授予的 tag 混同一本 _tag_counts 账（引用计数天然正确）
  - ✅ 玩家死亡 → add_loose_tag(State.Dead)（经典 UE 用例）
  - ✅ 回归：topdown 145→**157/0**（Loose 12 条），桌游 198/0，UI 0
  - 新账：**lambda 值捕获快照又踩一次**（DEVLOG 22 三遍教训：回调改状态
    必须成员变量+命名函数）
- **WaitGameplayEvent 课（第 29 节）关账**（2026-08-14）：
  - ✅ 框架（用户）：ASC `gameplay_event_received` 广播信号（_on_gameplay_event
    开头 emit，激活端+等待端并行）+ `GASAbilityTaskWaitGameplayEvent`
    （WaitInput 超时 + WaitAnimNotify 监听的组合；get_event_data 交付）
  - ✅ 反击技能（T）：3s 反击姿态 → 受击 → 对攻击者 1.5× 反击伤害；超时落空；
    与复仇（激活端）共存实证（emit 先行 → 反击用激活前 Attack）
  - ✅ 回归：topdown 157→**165/0**（反击 8 条），桌游 198/0，UI 0
  - 新账：**漏 emit**（信号声明了 Task 连了中间广播断线）；反击秒杀选怪
    （复读"选怪算血量"）
- **Custom Application Requirement 课（第 30 节）关账**（2026-08-14）：
  - ✅ 框架（用户）：`GASCustomApplicationRequirement` 基类（can_apply 虚函数，
    fail-open 默认放行——对齐 execution 模式）+ GE 数组字段 + apply 入口检查
    （target_asc 就位后，与 tag 版并列双门禁）
  - ✅ GASLevelRequirement：圣光护符要求 Level ≥ 2（读属性——tag 检查做不到）
  - ✅ 回归：topdown 165→**174/0**（CAR 9 条），桌游 198/0，UI 0
  - 新账：既有测试被新条件破坏（授予回归玩家 Lv1 佩戴挂——需全局排查）
- **加餐池收官课（第 31 节）关账**（2026-08-14）：
  - ✅ tag 祖先 O(1)（用户实现）：`_tag_ancestor_counts` 反向祖先索引双写
    （跟 _tag_counts 0→1/1→0 同步，UE TagMap 同款）+ has_tag 改查表；
    **过程事故**：AI 重复实现导致声明冲突（动手前先 git diff 看用户已放代码）
  - ✅ 首跳立即开关（AI 实现）：GE `execute_periodic_effect_on_application`
    （默认 false）+ apply 入账后立即 _apply_periodic_effect（period_timer 不动）
  - ✅ 回归：topdown 174→**184/0**（优化 10 条），桌游 198/0，UI 0
  - 新账：两个周期 GE 共用 dummy 时序污染（先移除再测）
- **UE 语义查证**（AGENTS.md 已记）：tranek/GASDocumentation 4.6.9 Ability Tags
  表格（四字段区别：查 ASC 状态 vs 查能力 AbilityTags）
- **里程碑**：25.5 盘点缺口全清 + 加餐池全清——UE GAS 单机版全貌对齐完毕
- **想法清单**：重叠命中 z 排序、AOE 圈视觉预览、collide_with_areas 开关、
  ge_damage_50.tres 死资产待删
- 环境备忘：同会话 4

## 核心架构速记（讲思路时的参照）

- 层次：Resource 定义层（GE/Ability）→ 实例层（Spec）→ 执行层（ASC/AttributeSet/AttributeData）→ 异步层（Task）→ 通信层（Tag）
- 9 条设计原则（DEVLOG 第 3 节）：先记账再放权 / 唯一收尾漏斗 / 生命周期不变量 / 门票代替引用 / fail-open vs fail-closed / CQS / 校验压在边界 / 计数+跳变沿 / 数据当参数传
- 已立的坑与教训：快照 vs 实时（离手即定，持续附着）、工厂填 source apply 填 target、改副本不另起炉灶、报错必须带拦截、resolved 即定案、代码与文档不能分家
