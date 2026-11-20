# Source camera movement adapter

CameraController.cs and the scene-referenced CameraController prefab were statically audited. The prefab declares panSpeed0.01, smoothTime0.15, panPadding0.5, zoomSpeed1, minDistance5 and maxDistance20. CameraMotion resolves that scene's prefab and matching component overrides. It does not replace imported camera pose, projection, FOV30, near2 or far40.

Pointer pan changes a target using pixel displacement and current camera height/10. Screen-Y and world-Z reflections preserve the source direction. Left pan checks the admitted Godot HUD and card receivers at a frame sample; middle pan bypasses the left blocker. Button and pointer events are collected before GUI; pan is not applied in an event callback. This does not reproduce the Unity EventSystem's cached raycast or its complete 3D hit list. Target X/Z is clamped to reflected board bounds plus source padding. Changed/shrinking bounds clamp the target immediately, not the current smoothed position. Zoom adds forward×scroll×zoomSpeed to target and rejects the complete step if its ground distance is outside5..20.

Movement uses the standard critically damped SmoothDamp polynomial (0.48/0.235 coefficients), retained velocity and overshoot prevention, evaluated with real frame delta. This is an independent numerical port, not a guarantee of identical Unity floating-point results. Manual gameplay pause does not freeze camera smoothing. Feeding, encounter, ready, game-over, vendor reveal and non-portal outgoing transitions block new camera input and ordinary smoothing. PauseMenu/Options only externally pause time and do not acquire InputManager locks; camera zoom, middle pan and unscaled smoothing remain active. Selling removes the source day-cycle input lock and permits camera movement, while Escape still checks the separate ending-cycle flag. Source Update returns before HandlePan while locked, preserving dragOrigin/isDragging. The native adapter now likewise preserves them; unlock samples accumulated pointer displacement, and a release while locked is not retroactively replayed.

`_focus_camera_position(source_position: Vector3, duration=0.5)` preserves source height and reflects Z. `_focus_camera(Vector2,duration)` is a ground-plane convenience wrapper. Focus runs with real time independently of ordinary input locks, toward target−forward×8, since source desired distance is lerp(20,5,0.8). Completion replaces target without an arbitrary board clamp. Only later pan/zoom or changed bounds clamps it. The interpolation uses explicit OutQuad matching the source default tween intent; arbitrary global DOTween overrides are not imported. No cycle event is wired in this batch and focus completion never drives model progression.

Combat shake remains independent camera h/v offsets. The unsupported native WASD camera extension has been removed. Source focus uses a controller parent and camera child; the native imported camera's flattened pose and camera-only shake offsets approximate this hierarchy. Pointer physics hit ordering, rendered framing, exact easing/floating-point parity and GPU/manual acceptance remain unverified.

Tests: camera_motion20 covers pan, clamping, zoom rejection, smoothing, source overrides and lock-independent focus. camera_board28 uses real imported source data and temporary local save/preferences; it covers lens preservation, manual pause, every cycle lock,3D focus, pointer routing and independent shake offsets. Existing smoke advances one camera frame before testing zoom/ray/drag roundtrips, reflecting the newly restored target smoothing instead of asserting the former instantaneous jump.

## Input routing correction evidence

CameraController.Update checks only InputManager.IsInputEnabled. HandleZoom never
calls IsPointerBlocked; only the left-press clause of HandlePan does. The middle
clause bypasses GUI, and neither clause depends on Time.timeScale. PauseMenu's
ToggleActiveState only calls TimeManager.SetExternalPause. InputManager uses a
HashSet of lock owners; DayCycleManager owns its phase lock and TradeManager
PlayActivationSequence independently owns tradeSequenceLock. Releasing day lock
while vendor reveal remains active cannot unlock camera input.

Wheel now enters via _input before GUI, not _unhandled_input. It is not consumed,
so the same event may scroll a panel and zoom, as source allows. The old tooltip
regression asserting no zoom was corrected rather than used to justify a deviation.
New tests push actual viewport GUI wheel events, verify exactly-once camera dispatch,
pause zoom/middle pan, independent lock release, preserved drag during locks and
transition gating. Card left-press remains GUI-blocked. Starting a blocked left
press does not cancel a previously active middle drag, matching the source clauses.

Cross-platform hardware scroll-unit calibration remains unverified: StackCraftInput
returns Mouse.scroll.ReadValue directly; Godot's event.factor supplies native wheel
units. This batch fixes routing/gating and preserves magnitude rather than inventing
a multiplier or claiming device-level raw-delta identity.

Verified: camera_board28, camera_motion20, card_feedback_board71, vendor_unlock_board47,
source camera pose/projection PASS. No Unity or manual GPU/input acceptance claimed.

## Dynamic frame pan

Input System 1.19.0 mouse left, mouse middle and touchscreen primary are
distinct controls. Once polled, physical press/release bits can both be
true in the same dynamic frame. A duplicate release does not make an
edge. Godot's touch-emulated mouse event can arrive before true touch:
it is ignored by the camera sampler only; native cards and GUI retain
their existing paths. Native primary touch works without the emulation
setting. Secondary touches never replace the retained primary/orphan.

CameraController starts (left if unblocked, or middle), then stops if
either release was seen, then reads **one final physical pointer sample**
and clamps once. A down/motion frame has zero initial displacement; an
up/motion frame does not move; overshoot/reversal is not clamped between
events. The vertical wheel sum is applied after that pan and before
unscaled smoothing. A locked Update drains that frame's edges without
changing drag state or saved origin; unlocking reads accumulated position
without replaying a release. Explicit MoveTo clears drag and samples
the current physical position before its existing tween.

Tests use real viewport injection for device duplication, origin and
scaling, plus deterministic batches for late releases, both-button
ordering, clamp reversal and wheel ordering. They do not model Input
System's lazy very-first-read edge caveat, backend focus/reset policy,
Unity EventSystem cache order or all original PhysicsRaycaster blockers.
Native injected tests do not replace a physical-device or Unity
reference run.

## Trade collider admission

The locked CameraController prefab's camera has an enabled PhysicsRaycaster:
both its event mask and camera culling mask include the buyer/vendor's default
layer. Their source BoxColliders are enabled and non-trigger. PackVendor changes
transaction eligibility and its text on unlock; it does not deactivate its collider.
As with cards and occupied equipment panels, the current native pointer ray can
therefore block the source left-button pan over either trade receiver, regardless
of whether hover text or a purchase is available. Middle pan still bypasses the
check, and wheel/transaction routing are unchanged. A missing/disabled collision
does not block. Board floor prefabs do not add a body to this admission path.

The live trade fixture feeds the real viewport and source-positioned collider
geometry (no fake ray result), including the locked vendor and a removed receiver.
These checks do not recreate Unity's uGUI/EventSystem cached ordering or establish
native physical hardware, global physics-layer, or Unity image parity.

## 普通传送的旧场景相机

原 `GameDirector.TravelSequence` 只外部暂停游戏时间，淡出并不取得
`InputManager` 的锁；原 `ScreenFader` 立即为整屏 Image 启用射线遮挡。
由已核验的 Grand Portal（Main ↔ Island）启动时，旧场景继续原相机
Update：淡出前已开始的平移继续，新左键被遮罩挡住，新中键不受遮罩
影响，任一有效左/中释放先停止平移，最后一笔指针取样后再处理累计
滚轮、跑不受时间倍率影响的阻尼。Travel 发生在同一 Update 之前时，
同一个旧场景尚未消费的正常滚轮也只计一次，不因淡出开始丢失。
即使没有新滚轮，旧场景未到位的目标也继续收敛。

权限只属于原传送的旧场景实例与淡出代号；同实例取消后另开的淡出
不继承，黑屏交换到新场景时新相机不继承平移或速度。淡入仍走现有
正常输入路径。游戏牌、菜单、HUD 无新增输入权限，独立喂食/商店锁
仍有效。牌已捕获时跨淡出的接收时序、并行镜头聚焦、非原配方和
Unity EventSystem 同帧射线缓存顺序不是此验收范围；并未把此边界
描述成额外的原版输入锁。双向真实传送与原生窗口回归不等于使用
物理输入设备或完成 Unity 画面对照。

## 原暂停菜单返回标题的旧场景相机

锁定版的 `PauseMenu.Awake` 将实际 Title 接收件连接到
`GameDirector.BackToTitle`。该方法先保存当前局，再启动同一
`TravelSequence(Title, null)`；Pause 与淡出都只是暂停时间，
不获取 `InputManager` 输入锁。

在 Main / Island 的普通进行中，只有已挂载且核对过原按钮引用、
GameDirector 目标和原目录的 Pause Title 路径才保留旧相机。在变黑前，
已开始的中键平移、后按的中键、竖直滚轮和未缩放阻尼继续；
新左键仍被整屏遮罩挡住。独立商贩锁仍挡相机；淡出不授予卡牌释放、
重开菜单或其他 GUI 操作权限。保存失败没有淡出；成功先保存一份，
黑屏加载标题不再次保存、重置旧手势与相机。标题读取同档仍回原游戏
场景，不读取旧相机位置。通用保存按钮、日末/游戏结束、并行镜头
聚焦和已经捕获的牌不扩大到此接入范围。

定向验收 `test_source_pause_title_camera_board.gd` 使用本地授权源，
从实际 Pause Title 鼠标按钮、原场景、独立存档和标题列表验证 Main 与
Island 的往返，包含窗口 Viewport 中的按键、平移和滚轮事件；不是
Unity 像素或物理鼠标验收。
