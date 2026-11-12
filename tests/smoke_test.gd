extends Node
## 无头冒烟测试：把“能跑”变成可验证的断言，而不是靠眼睛看。
##
## 运行：
##   godot --headless --path D:\godot-guofeng-arpg res://tests/smoke_test.tscn
## 退出码 0 = 全过，1 = 有失败项。
##
## 覆盖：资源加载、移动、普攻命中、闪避无敌帧、受击与保护帧、
##       命中停顿（按实体 / 全局暂停）、输入缓冲、清怪开门、连续 3 房间。

const MAIN_SCENE := "res://scenes/main.tscn"

var _main
var _player: Player
var _fails := 0
var _checks := 0


func _ready() -> void:
	print("========== 冒烟测试开始 ==========")
	# 看门狗：任何一步卡住都强制退出，避免 CI / 命令行一直挂着
	var watchdog := get_tree().create_timer(45.0, true, false, true)
	watchdog.timeout.connect(func() -> void:
		print("!! 测试超时，强制退出")
		get_tree().quit(2)
	)
	await get_tree().physics_frame

	await _test_resources()
	await _test_movement()
	await _test_attack_hits_enemy()
	await _test_dash_iframes()
	await _test_player_hurt()
	await _test_input_buffer()
	await _test_hitstop_entity()
	await _test_hitstop_global()
	await _test_room_loop()

	print("========== 结束：检查 %d 项，失败 %d 项 ==========" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- 各项测试


func _test_resources() -> void:
	print("[1] 资源加载")
	var cfg := load("res://resources/run_config.tres") as RunConfig
	_check(cfg != null, "RunConfig 能被加载")
	if cfg != null:
		_check(cfg.rooms.size() == 3, "跑图序列有 3 间房（实际 %d）" % cfg.rooms.size())
		if cfg.rooms.size() == 3:
			_check(cfg.rooms[0].display_name == "山门", "第一间是「山门」（实际 %s）" % cfg.rooms[0].display_name)

	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	_check(player_scene != null, "玩家场景能加载")

	# 真正把主场景挂进来，后续测试都在它上面跑
	_main = load(MAIN_SCENE).instantiate() as Node2D
	add_child(_main)
	await get_tree().physics_frame
	_player = _main.get_node("World/Player") as Player
	_check(_player != null, "主场景里有玩家")
	_check(_player.combo.size() == 3, "普攻有 3 段（实际 %d）" % _player.combo.size())
	_check(_player.skill != null, "技能已配置")
	_check(get_tree().get_nodes_in_group("enemy").size() > 0, "房间里生成了敌人")


func _test_movement() -> void:
	print("[2] 8 向移动")
	var start := _player.global_position
	Input.action_press("move_right")
	await _wait_frames(24)
	Input.action_release("move_right")
	var moved := _player.global_position.x - start.x
	_check(moved > 120.0, "按 D 向右移动了 %.0f px（应 > 120）" % moved)

	var before := _player.global_position
	Input.action_press("move_up")
	await _wait_frames(18)
	Input.action_release("move_up")
	_check(_player.global_position.y < before.y - 80.0, "按 W 向上移动（支持 8 向）")
	await _wait_frames(10)


func _test_attack_hits_enemy() -> void:
	print("[3] 普攻命中（hitbox → hurtbox）")
	var enemy := _first_enemy()
	if enemy == null:
		_check(false, "找不到敌人")
		return

	# 战斗测试要可复现：把玩家挪到角落，其他敌人赶到远端，只留一个靶子
	_player.global_position = Vector2(520, 800)
	_player.velocity = Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other != enemy:
			(other as Node2D).global_position = Vector2(1640, 180)
	await _wait_frames(4)

	# 等玩家离开受击/闪避硬直，确保能出招
	await _wait_until_ready()

	# 判定盒跟着朝向走：先朝右再放靶子，否则会打空（这本身也是一条要验证的行为）
	Input.action_press("move_right")
	await _wait_frames(3)
	Input.action_release("move_right")
	await _wait_frames(2)
	_check(_player.facing.x > 0.9, "朝向已对准右侧")

	enemy.global_position = _player.global_position + Vector2(230, 0)
	enemy.velocity = Vector2.ZERO
	await _wait_frames(2)

	var hp_before := enemy.current_health
	await _tap("attack")
	await _wait_frames(22)
	_check(enemy.current_health < hp_before, "普攻造成伤害（%.0f → %.0f）" % [hp_before, enemy.current_health])

	# 闪白材质是否真的被驱动过
	var mat := (enemy.get_node("Body") as Polygon2D).material as ShaderMaterial
	_check(mat != null, "敌人身上挂了闪白材质")


func _test_dash_iframes() -> void:
	print("[4] 闪避无敌帧")
	_player.global_position = Vector2(700, 700)
	await _wait_frames(2)
	await _tap("dash")
	await _wait_frames(3)
	_check(_player.state == Player.State.DASH, "闪避进入 DASH 状态")
	_check(_player.invulnerable, "闪避窗口内 invulnerable = true")
	await _wait_frames(20)
	_check(not _player.invulnerable, "闪避结束后无敌解除")


func _test_player_hurt() -> void:
	print("[5] 受击 / 保护帧")
	var hurtbox := _player.get_node("Hurtbox") as Hurtbox
	var hp_before := _player.current_health

	var hit := HitData.new()
	hit.damage = 12.0
	hit.knockback = 600.0
	hit.shake = 0.2
	hit.hit_flash = 0.1
	hurtbox.receive_hit(hit, null, null)
	await _wait_frames(2)
	_check(_player.current_health < hp_before, "受击扣血（%.0f → %.0f）" % [hp_before, _player.current_health])

	var hp_mid := _player.current_health
	hurtbox.receive_hit(hit, null, null)
	await _wait_frames(2)
	_check(is_equal_approx(_player.current_health, hp_mid), "保护帧内不会被连续扣血")

	# 等保护帧结束，确认又能被打
	await _wait_seconds(0.7)
	hurtbox.receive_hit(hit, null, null)
	await _wait_frames(2)
	_check(_player.current_health < hp_mid, "保护帧结束后恢复可受击")


func _test_input_buffer() -> void:
	print("[6] 输入缓冲（单元测试）")
	var buf := InputBuffer.new()
	buf.window = 0.15
	buf.press("attack")
	_check(buf.consume("attack"), "窗口内按下可以取出")
	buf.press("attack")
	await _wait_seconds(0.25)
	_check(not buf.consume("attack"), "超出窗口的输入被丢弃")
	_check(not buf.has_buffered("skill"), "没按过的输入不会误触发")


func _test_hitstop_entity() -> void:
	print("[7] 命中停顿（按实体冻结）")
	HitStop.use_entity_mode()
	var probe := Node.new()
	add_child(probe)
	HitStop.freeze_one(probe, 0.1)
	_check(HitStop.is_frozen(probe), "管理器记录了冻结状态")
	# process_mode 是延迟应用的（避免在物理回调里禁用 CollisionObject），等两帧再看
	await _wait_frames(2)
	_check(probe.process_mode == Node.PROCESS_MODE_DISABLED, "被冻结的实体 process_mode = DISABLED")
	await _wait_seconds(0.2)
	_check(not HitStop.is_frozen(probe), "到时自动解冻")
	_check(probe.process_mode == Node.PROCESS_MODE_INHERIT, "process_mode 被还原")
	probe.queue_free()


func _test_hitstop_global() -> void:
	print("[8] 命中停顿（全局暂停窗口）")
	HitStop.use_global_pause_mode()
	HitStop.freeze([], 0.12)
	_check(get_tree().paused, "全局暂停已开启")
	await _wait_seconds(0.25)
	_check(not get_tree().paused, "窗口结束后恢复运行")
	HitStop.use_entity_mode()
	HitStop.clear_all()


func _test_room_loop() -> void:
	print("[9] 清怪 → 开门 → 连续 3 间")
	var main_script = _main
	for expected in 3:
		var room := main_script.room as Room
		_check(room != null, "第 %d 间房已加载" % (expected + 1))
		if room == null:
			return
		_check(room.alive_count > 0, "第 %d 间有 %d 个敌人" % [expected + 1, room.alive_count])

		room.debug_kill_all()
		await _wait_frames(6)
		_check(room.is_cleared, "清空后房间标记为已清")
		_check(room.alive_count == 0, "剩余敌人为 0")

		# 走到门口
		_player.global_position = Vector2(1790, 540)
		_player.velocity = Vector2.ZERO
		await _wait_seconds(0.9)

		if expected < 2:
			_check(main_script.room_index == expected + 1, "进入第 %d 间（实际 %d）" % [expected + 2, main_script.room_index + 1])
		else:
			_check(main_script.room_index == 2, "最后一间停在索引 2")


# ---------------------------------------------------------------- 工具


func _first_enemy() -> Enemy:
	var nodes := get_tree().get_nodes_in_group("enemy")
	if nodes.is_empty():
		return null
	return nodes[0] as Enemy


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


## 等待玩家回到可行动状态（受击硬直会吞掉按键，测试必须先等它结束）
func _wait_until_ready() -> void:
	for i in 90:
		if _player.state == Player.State.IDLE or _player.state == Player.State.MOVE:
			return
		await get_tree().physics_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  [PASS] ", message)
	else:
		_fails += 1
		print("  [FAIL] ", message)
