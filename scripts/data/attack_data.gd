class_name AttackData
extends Resource
## 一个“招式”的完整参数：节奏窗口 + 判定形状 + 结算数据。
##
## 为什么招式要做成 Resource：
##   三段普攻、技能、敌人挥击本质是同一套“前摇-判定-后摇”结构，
##   参数化后就能在检查器里调手感，不用复制粘贴状态机代码。
##   以后做武器差异化（长剑慢、匕首快）也只是换 .tres。

@export_group("显示")
## 调试面板 / 招式提示里显示的名字
@export var display_name := "轻斩"

@export_group("动作")
## 出招时播放的 AnimatedSprite2D 动画名（三段普攻各用不同方向的动作）
@export var animation: StringName = &"attack"

@export_group("节奏（秒）")
## 前摇：按下到判定出现
@export var windup := 0.08
## 判定持续
@export var active := 0.07
## 后摇：判定结束到可以再次自由行动
@export var recovery := 0.22
## 取消窗起点：从招式开始计时，到达这个时间后可以被闪避 / 技能 / 下一段普攻取消。
## 一般落在判定结束附近，让“打中就能连”成立，打空则不成立（我们也用命中与否区分）
@export_range(0.0, 2.0, 0.01) var cancel_from := 0.18

@export_group("判定盒")
@export_enum("矩形", "圆形") var hitbox_shape := 0
## 矩形尺寸
@export var hitbox_size := Vector2(56, 48)
## 圆形半径
@export var hitbox_radius := 64.0
## 相对角色朝向前方的偏移
@export var hitbox_offset := Vector2(30, 0)
## 出招瞬间给角色自身的前冲速度，让攻击有“重量”
@export var step_impulse := 110.0

@export_group("结算")
## 命中数据（伤害 / 击退 / 停顿 / 震屏）
@export var hit: HitData
