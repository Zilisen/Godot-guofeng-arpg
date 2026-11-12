class_name Hurtbox
extends Area2D
## 受击判定盒（hurtbox）。
##
## 只负责“能不能挨打”和把命中转发给角色本体，不处理扣血/硬直，
## 因为那些逻辑依赖角色自己的状态机（比如角色在死/无敌时表现不同）。

## 受击信号：命中数据、攻击者、来源 hitbox
signal hurt(hit: HitData, source: Node2D, hitbox: Hitbox)

## 所属阵营：0 = 玩家，1 = 敌人
@export var team := 0
## 无敌时不接收任何命中（闪避无敌帧、受击后保护帧都改这个标记）
var invulnerable := false

## 拥有该 hurtbox 的角色节点（由角色在 _ready 里赋值）
var actor: Node2D


func _ready() -> void:
	# hurtbox 只需要“被别人侦测”，自己不必侦测别人
	monitoring = false
	monitorable = true
	if actor == null:
		actor = get_parent() as Node2D
	add_to_group("hurtbox")


func can_receive() -> bool:
	return not invulnerable


## 统一的受击入口，供 Hitbox 调用
func receive_hit(hit: HitData, source: Node2D, hitbox: Hitbox) -> void:
	if invulnerable:
		return
	hurt.emit(hit, source, hitbox)


func get_actor() -> Node2D:
	return actor


func set_invulnerable(value: bool) -> void:
	invulnerable = value
