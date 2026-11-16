# Standalone CombatRect.Initialize 的入战前原生站位

锁定原项目：`a11a89b04cea8370476f2559b639bb9b4cbc08d8`。本切片不包含原始素材。

## 源码顺序

`CombatManager.CreateCombatTaskInternal` 先调用 `CombatRect.Initialize`，后构造
`CombatTask`（全员进度随机数），再依序调用攻击方、守方 `EnterCombat`。
Initialize 由原生当前位置均值计算中心、按原预制体与棋盘限制钳制，执行
`ResolveOverlaps` 后 `ArrangeCards/SetTargetInstant(forceGround: true)`。
登记新战斗后再执行一次 `ResolveOverlaps`。原重载忽略传入的 rect，首次仅查询
已登记战斗区；不可提前把新区加入首次重叠查询。

此前 Board 在之后的刷新才同步槽位：即使中心正确，第一条 combat_entered
通知里所有原生卡片仍处于旧位置。本次在独立新战斗的构造前接入原生站位，
清除旧普通移动，并让后续 detach 使用已排好的槽位而不是旧堆叠目标。
两边角色反向时仍按攻击方、守方顺序；不额外抽随机数。

## 严格的接入范围

- 仅没有现有战斗的独立开始；不是合并、恢复或 AddCombatants。
- 入战者都是完整普通单卡堆叠；全部具备身份匹配、当前地面姿态的原生视图与
  普通运动状态。任一成员高度、拖动、循环演出、装备归属或变换不明则全体回退。
- 可以保留正常世界中的其他堆叠，不要求清空资源。使用原目标位置的堆叠 bounds
  检查首次全体堆叠之间无分离量；再检查移除入战单卡后，所有幸存普通堆叠与新
  战斗区无分离量。因此两次源重叠处理都是无分离尝试的 no-op。
- 不是“计算完位置没变”就认可；边界钳制可能掩盖分离尝试。检测非零分离量便回退。
- 先验证整个集合，再写任何原生位置；未接入集合保留原迁移路径，不能称为完整
  Initialize 重叠顺序已还原。现有模型的 task 登记/事件暴露方式并未重构。

## 证据与剩余范围

`test_combat_preenter_board.gd` 使用真实私有导入源数据和 Board 节点，在
combat_entered 回调里验证所有成员已原生归位、旧普通移动已清除、构造随机数
已完整抽取、detach 没重用旧位置，并核对远处资源不动。反向一轮经真正
`MobAI.tick → aggressive_intent → start_combat` 驱动，不是仅调用方便按钮。
另测前后重叠处理各自有分离尝试、单一抬高成员时原子拒绝。

此测试仅证明原生节点与同步事件顺序，不是 GPU、Unity 同帧或截图验收。
多成员堆叠、需要真实分离的拥挤布局、已有战斗、原生活跃近战 Tween、恢复与
合并的全套初始化顺序仍需继续源码对照，不能用本切片宣称迁移完成。
