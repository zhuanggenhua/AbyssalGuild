# 取消输入与原生确认框

## 静态来源

参考固定版本 `a11a89b04cea8370476f2559b639bb9b4cbc08d8` 的 `Assets/StackCraft`，不运行 Unity，也不复制模板源码或资源：

- `Scripts/Core/StackCraftInput.cs` 的 `CancelWasPressedThisFrame`：键盘 Escape 或手柄东侧按钮的按下边沿。
- `Scripts/UI/PauseMenu.cs` 的 `Update` / `ToggleActiveState`：结束日循环期间不切换暂停菜单；普通游戏中切换外部暂停锁。
- `Scripts/Core/TimeManager.cs` 的 `SetExternalPause` / `UpdateTimeScale`：外部暂停不覆盖玩家所选时间速度。
- `Scripts/UI/Title/TitleScreen.cs` 的 `Start`：标题页 Quit 先显示确认框，仅接受后才退出。
- `Scripts/UI/ModalWindow.cs` 的 `Show`：拒绝仅关闭确认框，接受才调用已配置的操作。

## Godot 输入适配

`scripts/ui/navigation_input.gd` 是独立实现的输入适配，不包含游戏规则或存档逻辑。

在当前固定引擎 `4.6.3.stable.official.7d41c59c4` 的隔离空工程中，实测默认 `ui_cancel` 只有 Escape。仅将原有按键判断换成 `is_action_pressed("ui_cancel")`，不会自动补上手柄东侧按钮。

- `ensure_cancel_bindings()` 幂等补入 Escape 和 `JOY_BUTTON_B`，保留已有映射，不改其他 UI action。手柄映射适用于所有设备。
- `is_cancel_press()` 使用 Godot action 判断，不接受松开事件或键盘自动重复。非取消按钮不触发。
- 当前引擎的原生 `ConfirmationDialog` 不会仅因添加手柄映射而响应东侧按钮。`enable_modal_cancel()` 通过 `window_input` 将该输入接到真实取消按钮，保留原生取消信号，不触发确认。键盘仍走原生处理。
- 确认框连接可重复配置；隐藏的确认框不处理取消。普通游戏中的两次独立按下仍是两次切换，不按时间去抖而吞掉有效操作。

调用方应在构建菜单前配置 action，并为各原生确认框启用手柄取消。外层菜单处理应先检查是否有可见确认框，避免同一操作穿透到暂停或选项界面。标题退出、日终退出和存档失败的路由属于桌面接入层，不由此输入适配决定。

## 验证范围

```sh
bash tools/test_godot.sh res://tests/godot/test_navigation_input.gd
```

当前专用检查为 **20/20**，不依赖私有导入数据。覆盖重复配置、保留已有映射、不同手柄编号、按下/松开、键盘 echo、自定义 action 映射，以及向嵌入式原生确认框实际分发键盘/手柄事件。两种输入都只发出一次取消信号，确认回调保持为零。

这证明合成输入与原生窗口分发可用，不代表实体手柄、平台窗口系统或完整桌面导航已做人工验收。标题 Quit 和存档/日终保护必须在桌面接入后另行测试。
