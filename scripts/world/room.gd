class_name Room
extends Node2D
## 一个战斗房间：生成敌人 → 清空后开门 → 玩家上门 → 通知主流程。
##
## 为什么房间自己管“开门”而不是主流程管：
##   房间是唯一知道“还剩几个敌人”的地方；主流程只关心“能不能进下一间”。
##   这样以后加“宝箱房/商店房”时，只需要换一个 Room 实现，主流程不用改。

signal cleared
signal door_entered
signal enemy_count_changed(count: int)

const ENEMY_SCENE := preload("res://scenes/enemies/enemy_melee.tscn")

@export_group("布局")
## 房间可行走区域（世界坐标）
@export var bounds := Rect2(80, 80, 1760, 920)
## 玩家进入房间时的落点
@export var player_spawn := Vector2(320, 540)

@export_group("门")
@export var door_open_color := Color(0.85, 0.7, 0.25, 1.0)
@export var door_locked_color := Color(0.28, 0.28, 0.33, 1.0)

@onready var _enemies_root: Node2D = $Enemies
@onready var _spawn_points: Node2D = $SpawnPoints
@onready var _door: Area2D = $Door
@onready var _door_fill: Polygon2D = $Door/Fill
@onready var _door_label: Label = $Door/Label

var data: RoomData
var alive_count := 0
var is_cleared := false

var _door_fired := false


func _ready() -> void:
	_set_door_open(false)


## 由主流程在 add_child 之后调用
func setup(room_data: RoomData) -> void:
	data = room_data
	alive_count = 0
	is_cleared = false
	_door_fired = false
	_set_door_open(false)
	_spawn_enemies()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	# 用重叠轮询而不是 body_entered：
	# 如果玩家在“开门瞬间”已经站在门口，body_entered 不会补发，会卡住流程。
	if not is_cleared or _door_fired:
		return
	for body in _door.get_overlapping_bodies():
		if body is Player:
			_door_fired = true
			door_entered.emit()
			return


func _spawn_enemies() -> void:
	var points := _spawn_points.get_children()
	if points.is_empty():
		push_warning("房间没有配置出生点")
		return
	var count: int = data.enemy_count if data != null else 3
	for i in count:
		var marker := points[i % points.size()] as Marker2D
		# 超过出生点数量时向外围铺开：每多刷一圈，整圈偏移一格
		var ring := floori(i / float(points.size()))
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.position = marker.position + Vector2(ring * 90.0, ring * 70.0)
		if data != null:
			enemy.apply_room_data(data)
			enemy.max_health = data.enemy_health
			enemy.current_health = enemy.max_health
		enemy.died.connect(_on_enemy_died)
		_enemies_root.add_child(enemy)
		alive_count += 1
	enemy_count_changed.emit(alive_count)


func _on_enemy_died(_enemy: Enemy) -> void:
	alive_count = maxi(alive_count - 1, 0)
	enemy_count_changed.emit(alive_count)
	if alive_count == 0 and not is_cleared:
		is_cleared = true
		_set_door_open(true)
		cleared.emit()


func _set_door_open(open: bool) -> void:
	if _door_fill == null:
		return
	_door_fill.color = door_open_color if open else door_locked_color
	_door_label.text = "门已开" if open else "封"


# ---------------------------------------------------------------- 占位美术


func _draw() -> void:
	# 地面
	var rect := Rect2(bounds.position, bounds.size)
	draw_rect(rect, Color(0.13, 0.14, 0.17, 1.0), true)

	# 墨色网格：低成本地把“距离感”做出来，正式版换成手绘地砖
	var step := 120.0
	var x := bounds.position.x
	while x <= bounds.end.x:
		draw_line(Vector2(x, bounds.position.y), Vector2(x, bounds.end.y), Color(1, 1, 1, 0.05), 2.0)
		x += step
	var y := bounds.position.y
	while y <= bounds.end.y:
		draw_line(Vector2(bounds.position.x, y), Vector2(bounds.end.x, y), Color(1, 1, 1, 0.05), 2.0)
		y += step

	# 墙线
	draw_rect(rect, Color(0.78, 0.68, 0.5, 0.6), false, 8.0)


func camera_center() -> Vector2:
	return bounds.position + bounds.size * 0.5


## 仅供调试 / 自动化测试：一次性清空房间（走真实的受击 → 死亡路径）
func debug_kill_all() -> void:
	for child in _enemies_root.get_children():
		var enemy := child as Enemy
		if enemy == null:
			continue
		var hit := HitData.new()
		hit.damage = 99999.0
		hit.knockback = 0.0
		hit.hitstop = 0.0
		hit.shake = 0.0
		hit.hit_flash = 0.05
		var hurtbox := enemy.get_node("Hurtbox") as Hurtbox
		if hurtbox != null:
			hurtbox.receive_hit(hit, null, null)
