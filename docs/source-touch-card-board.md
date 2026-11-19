# Source touch presses and card drops

Scope: locked StackCraft 1.0.0 gameplay input in Main and Island. The integration exercise uses Main.

- InputSystem 1.19.0 default SingleMouseOrPenButMultiTouchAndTrack binds touch*/position and touch*/press. It stores the IPointerDownHandler object even if CardController.OnPointerDown returned under InputManager lock. Every normal or canceled up for that contact goes to its original receiver; skipping Unity's click dispatch on cancel does not skip OnPointerUp.
- A card controller, not the contact, owns the held position. A second accepted contact on the same standard card re-samples drag origin and offset without creating another held stack; its first routed up finishes the card. Other cards remain held. An accepted up clears the shared trade/stack highlights, as in the original.
- Picking uses each touch position after native GUI admission. Active holders project the common StackCraftInput pointer, including orphaned primary. Secondary coordinates do not move the cards. Release uses last held pose, not the up location. The emulated mouse event may precede touch; card receivers ignore the duplicate while retaining blank-camera and existing GUI/panel mouse ingress.
- Standard drops split a tail, resume only its own active craft if returned, permit ordinary reattachment to another still-held stack, and use existing trade/equipment/combat drop adapters. Checkpoints normalize ordinary held stacks on an isolated clone. See [concurrent-held-stacks.md](concurrent-held-stacks.md) for guarded pickup conflicts.
- Existing Godot overlap placement locking and scoped equipment/combat adapters remain. Unity's physics solver checks its stack's own lock, not controller drag state. Concurrent overlap settlement, mixed-device filtering, equipment/combat edge cases and physical device or Unity runtime comparison are not part of this acceptance.

The source touch card Board script injects viewport events on real colliders with the private locked catalog and exercises independent holds, captured and canceled ups, same-card repeats, lock-rejected receives, primary orphan, standalone mouse, real same-stack split/attachment, two paused recipe origins with an isolated save, buyer terminal drop and title cleanup. The camera Board script verifies blank/GUI paths with the appropriate source or fallback height. Native injection does not substitute for device testing.

## 装备面板与已装备卡牌

原 `EquipmentPanel.OnPointerClick` 和 `CardController.OnPointerUp` 是两类接收：
面板仅在未取消、释放仍命中同一个实际面板且未被 HUD 覆盖时切换；
装备卡牌在按下后由原触点释放，即使释放已离开卡牌也执行一次落下。
关闭其它面板仍由主触点触发，不能把第二触点当成新的共享左键按下。

原 `CardController.OnPointerDown` 装备分支先调用 `CardEquipper.Unequip`，
`CardManager.ReturnCardToBoard` 按挂点的可见 XZ、Y=0 注册单牌堆。
随后计算共享指针偏移，但不写普通拾取起点、不播放拾取音、也不在按下
同步升到拖动高度。之后的正常更新才使用源 `DragHeight`；释放读取
真正已提交的位置，不取释放事件坐标。现有 Godot 摆放解算仍不是 Unity
物理解算的等价证明，复杂重叠与混合设备不在本批证据内。

`test_equipped_touch_board.gd` 使用原 Main 目录数据、实际装备面板和卡牌碰撞体，
注入按下、取消、正常释放与实际 GUI 遮挡，验证在原面板上展开、按住并卸下
武器、按下与下一帧姿态不同、最后释放落下与模型登记。原生窗口事件注入不等同
真实触屏，也不证明 Unity 渲染完全一致。
