class_name RoomData
extends Resource
## 单个房间的配置。用 Resource 而不是 JSON 的原因见 docs/制作流程文档.md：
## 可以在编辑器里直接拖拽、有类型检查、能被 @export 引用。

## 房间名（HUD 显示）
@export var display_name := "山门"
## 敌人数
@export var enemy_count := 3
## 敌人血量（用房间来缩放难度，第一期够用）
@export var enemy_health := 40.0
## 敌人伤害
@export var enemy_damage := 8.0
## 敌人移动速度
@export var enemy_speed := 105.0
