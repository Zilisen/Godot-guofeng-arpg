extends Node2D
## 主流程：跑图序列、房间切换、死亡与重开。
## 这一层只做“编排”，不含战斗细节——方便以后换成正式的地图/关卡系统。

const ROOM_SCENE := preload("res://scenes/game/room.tscn")

## 房间序列（资源里配 3 个；为空时用代码兜底，保证空工程也能跑）
@export var run_config: RunConfig

@onready var _room_host: Node2D = $World/RoomHost
@onready var _player: Player = $World/Player
@onready var _camera: Camera2D = $Camera2D
@onready var _hud: HUD = $HUD
@onready var _debug: Node2D = $DebugOverlay

var room_index := 0
var room: Room = null

var _transitioning := false
var _run_finished := false
var _player_dead := false


func _ready() -> void:
	if run_config == null or run_config.rooms.is_empty():
		run_config = _fallback_run_config()

	_player.health_changed.connect(_hud.set_health)
	_player.died.connect(_on_player_died)
	_hud.set_health(_player.current_health, _player.max_health)

	_load_room(0)
	_hud.show_banner("清空房间 → 走到右侧门", 3.0)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart") and (_player_dead or _run_finished):
		_restart()


func _load_room(index: int) -> void:
	room_index = index
	if is_instance_valid(room):
		room.queue_free()
		room = null

	room = ROOM_SCENE.instantiate() as Room
	_room_host.add_child(room)
	room.door_entered.connect(_on_door_entered)
	room.cleared.connect(_on_room_cleared)
	room.enemy_count_changed.connect(_hud.set_enemies)
	room.setup(run_config.rooms[index])

	# 玩家跨房间保留血量与状态，只重置位置
	_player.global_position = room.player_spawn
	_player.velocity = Vector2.ZERO
	_camera.snap_to(room.camera_center())

	var data := run_config.rooms[index]
	_hud.set_room(index + 1, run_config.rooms.size(), data.display_name)
	_hud.set_enemies(room.alive_count)
	_hud.hide_center()


func _on_room_cleared() -> void:
	_hud.show_banner("房间已清空 · 右侧门开启", 2.5)


func _on_door_entered() -> void:
	if _transitioning or _run_finished or _player_dead:
		return
	_transitioning = true

	await _hud.fade_out(0.18)
	if room_index + 1 >= run_config.rooms.size():
		_run_finished = true
		_hud.show_center("演示通关\n\n按 R 再来一轮")
		await _hud.fade_in(0.25)
	else:
		_load_room(room_index + 1)
		await _hud.fade_in(0.25)

	_transitioning = false


func _on_player_died() -> void:
	_player_dead = true
	_hud.show_center("你倒下了\n\n按 R 重来")


func _restart() -> void:
	HitStop.clear_all()
	_transitioning = false
	_run_finished = false
	_player_dead = false
	get_tree().reload_current_scene()


## 兜底：没有配置 .tres 时也能连续走 3 间
func _fallback_run_config() -> RunConfig:
	var cfg := RunConfig.new()
	var names := ["山门", "断桥", "佛窟"]
	for i in 3:
		var rd := RoomData.new()
		rd.display_name = names[i]
		rd.enemy_count = 2 + i
		rd.enemy_health = 40.0 + i * 15.0
		rd.enemy_damage = 8.0 + i * 2.0
		rd.enemy_speed = 300.0 + i * 20.0
		cfg.rooms.append(rd)
	return cfg
