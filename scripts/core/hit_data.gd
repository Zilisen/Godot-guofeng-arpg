class_name HitData
extends Resource
## 一次命中的全部结算参数。
## 为什么不把伤害写死在攻击脚本里：同一个攻击以后要能被 buff / 词条修改数值，
## 拆成 Resource 才能被 Roguelite 的成长系统直接替换或叠加。

## 伤害值
@export var damage := 10.0
## 击退初速度（像素/秒）。玩家受击时会再乘自身的击退抗性
@export var knockback := 180.0
## 命中停顿时长（秒）。0 表示不停顿
@export var hitstop := 0.06
## 震屏强度（0-1 的 trauma 增量）
@export var shake := 0.15
## 受击闪白时长（秒）
@export var hit_flash := 0.10
## 受击者硬直时长（秒），期间不能行动
@export var stun := 0.18
