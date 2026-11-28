# 窗口与确认框管理

同一帧里只允许一扇窗口和一个确认框，并且只要还有窗层显示，窗层下面的场景就要压成
「黑色半透明 + 模糊」。这两件事都由 autoload `UiWindows`
（[`engine/ui/window_manager/ui_window_manager.gd`](../engine/ui/window_manager/ui_window_manager.gd)）统一管，
各页的 `WindowTransition` 只负责自己的开合动画与正文。

## 1. 两套窗层，两个槽

| 槽（`Kind`） | 原生绘制入口 | 本工程的实现 |
| --- | --- | --- |
| `WINDOW` | `Menu_win_Box4_DrawWindow` | `WindowTransition.kind = BOX4`（页窗口，带标题条／页脚） |
| `DIALOG` | `Menu_win_Box2_DrawWindow` | `WindowTransition.kind = BOX2`（`confirm_box` 一类确认框） |

两个槽互不顶替：确认框可以叠在窗口上（公会挑战、任务详情的「是／否」），窗口不会因此收起。
同一槽同一个宿主里只能留一扇。

## 2. 宿主与栈

- **宿主**＝窗层入栈时的父节点（`get_parent()`）。同一个宿主里同类的窗层才互相顶替；
  图鉴、菜单里的二级窗虽然都叫「窗口」，但分属不同宿主，各自只占自己那一层。
- 入栈顺序就是栈序（栈底在前），`entries()` 可以取快照做诊断。
- 关窗不等同于 `hide()`：管理器监听窗层的 `visibility_changed` 与 `tree_exited`，
  窗层真正不可见（关窗动画播完、整页被宿主收起、被释放）时才出栈。

旧窗层的去向由**开窗方**决定，`WindowTransition` 用 `keep_previous` 声明：

| 取值 | 行为 |
| --- | --- |
| `false`（默认） | `Previous.DISMISS`：旧窗层出栈并由管理器收起，调用方自己关窗／释放。对应原生「一页换一页」。 |
| `true` | `Previous.KEEP_HIDDEN`：旧窗层留在栈里先收起，本窗层出栈时自动恢复显示。对应菜单收起 `Frame` 后开二级选择窗、关窗后菜单窗框回来那一类。 |

## 3. 背景层

整个场景只建一个 `ScreenShade`（`engine/ui/screen_shade`），挂在**最底层可见窗层的紧前面**：

- 同一个父节点、同一个 `z_index`、树序排在窗层前面 ⇒ 压住窗层下面的场景，不盖窗层本身；
- 最底层按有效 `z_index`（`z_as_relative` 会把祖先的 `z_index` 累加）取最小，所以确认框
  叠在窗口上时背景仍然只在窗口下面，不会把窗口也糊掉；
- 固定铺 `400×240` 逻辑屏幕，不跟父矩形走——图鉴的 `Book` 根节点没有尺寸；
- 最后一扇窗层收起时隐藏（实例保留，下次开窗继续用）。

模糊与压暗在 `menu_map_blur.gdshader` 里做：3×3 盒式模糊（步长固定 1 个逻辑像素）叠加
`COLOR.a = 0.5` 的压暗，对应原生 `Field_Basic_Capture`／`Battle_info_Capture` 的
`JC_grpFillBLUR`。默认采样实时屏幕，所以窗层下面的静止画面就是定格画面；需要定格某一张
`Image` 时调用 `ScreenShade.set_snapshot()`。

## 4. 接入方式

- **`WindowTransition` 及其子类**：`open_window()` 自动入栈（按 `kind` 分槽、按 `keep_previous`
  决定旧窗去向），关窗／隐藏／释放自动出栈，不需要页面额外登记。
- **自绘全屏页**（例如菜单 `menu_view`）：页面自己判断可见性，调用
  `WindowTransition.register_window(self)` / `unregister_window(self)`，和 `WindowTransition`
  占同一个窗口槽。
- **主菜单子页**（`game/prime/startup/prime_view`）：环境设定／帮助／支持／网络连接与两张网络
  提示页共用同一个 `PrimeView` 节点换页画，换页不发 `visibility_changed`，所以在 `present()`
  末尾按 `paint.scene` 显式 `register_window` / `unregister_window`；标题页与存档槽页不登记。
- **冻结判据**：`WindowTransition.any_open()` 转发到 `UiWindows.any_open()`，野外据此停住推进
  （`field_runtime` 的 `_field_paused()`）。

管理器不抓帧、不销毁页面、不替页面决定生命周期；它只维护栈、可见性和背景层的挂载位置。

## 5. 验证

`tests/unit/test_window_manager.gd` 覆盖：背景层紧贴窗层前面、第二个窗口顶掉第一个、
确认框与窗口共存、`keep_previous` 的恢复、最后一扇收起后背景层与冻结判据一起复位，
以及主菜单子页（`PrimeView` 换页）按窗口登记／出栈。
