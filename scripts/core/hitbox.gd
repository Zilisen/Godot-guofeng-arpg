class_name Hitbox
extends Area2D
## 攻击判定盒（hitbox）。
##
## 用法：由角色脚本在“判定帧”调用 activate()，判定帧结束时调用 deactivate()。
## 只在激活期间生效，且一次激活内对同一个 hurtbox 最多命中一次（防止一刀多段）。

## 命中时发出，参数：被命中的 hurtbox、命中数据、命中点世界坐标
signal hit_landed(hurtbox: Hurtbox, hit: HitData, world_pos: Vector2)

## 本次攻击的命中数据；为空时使用一个默认值，避免忘配置直接报错
@export var hit: HitData
## 攻击方所属阵营：0 = 玩家，1 = 敌人。只有阵营不同的 hurtbox 才会被命中
@export var attack_team := 0
## 攻击者自身，用于命中停顿（让攻击方也一起停住）
var source: Node2D

var is_active := false

## 本次激活已命中的 hurtbox 实例 id
var _hit_ids := {}


func _ready() -> void:
	# hitbox 只“侦测”，不需要被别的 hitbox 侦测到
	monitoring = true
	monitorable = false
	if hit == null:
		hit = HitData.new()
	area_entered.connect(_on_area_entered)


## 开始判定。传入数据可覆盖本 hitbox 上的默认值（常见用法：同一把武器不同招式）
func activate(data: HitData = null) -> void:
	if data != null:
		hit = data
	_hit_ids.clear()
	is_active = true
	monitoring = true

	# 坑点：Area2D 如果“已经和某个 hurtbox 重叠”之后才打开 monitoring，
	# 引擎不会补发 area_entered。所以激活后等一个物理帧，手动补扫一次重叠。
	await get_tree().physics_frame
	if not is_active:
		return
	for area in get_overlapping_areas():
		_try_hit(area)


func deactivate() -> void:
	is_active = false
	_hit_ids.clear()


func _on_area_entered(area: Area2D) -> void:
	if is_active:
		_try_hit(area)


func _try_hit(area: Area2D) -> void:
	if not is_active:
		return
	var hurtbox := area as Hurtbox
	if hurtbox == null:
		return
	if hurtbox.team == attack_team:
		return
	if not hurtbox.can_receive():
		return
	var id := hurtbox.get_instance_id()
	if _hit_ids.has(id):
		return
	_hit_ids[id] = true

	var resolved := hit if hit != null else HitData.new()
	var point := hurtbox.global_position

	# 命中停顿：只冻结攻防双方，不冻结整个世界
	var actors: Array[Node] = []
	if source != null:
		actors.append(source)
	var target_actor := hurtbox.get_actor()
	if target_actor != null:
		actors.append(target_actor)
	HitStop.freeze(actors, resolved.hitstop)

	hurtbox.receive_hit(resolved, source, self)
	hit_landed.emit(hurtbox, resolved, point)
