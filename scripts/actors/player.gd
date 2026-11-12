class_name Player
extends CharacterBody2D
## 玩家：8 向移动 / 三段普攻 / 闪避（含无敌帧）/ 一个技能。
##
## 状态机用枚举 + match，而不是每个状态一个节点：
##   本切片只有 6 个状态、且彼此共享大量数据（朝向、速度、hitbox），
##   单文件枚举状态机更好读、更好调。等状态超过 12 个或需要多角色复用时，
##   再拆成“状态节点 + StateMachine”不迟（见文档里的演进建议）。
##
## 所有手感参数都通过 @export 暴露，改完直接在编辑器里跑，不用改代码。

## 血量变化（HUD 用）
signal health_changed(current: float, maximum: float)
## 死亡
signal died

enum State { IDLE, MOVE, ATTACK, DASH, SKILL, HURT, DEAD }

const STATE_NAMES := ["待机", "移动", "普攻", "闪避", "技能", "受击", "死亡"]

@export_group("移动")
## 主角屏幕高 280px（@1080p），所以位移速度按大屏取值，不能用小分辨率数值
@export var move_speed := 620.0
## 加速度：越大越“硬”，越小越滑
@export var accel := 5200.0
@export var friction := 6400.0

@export_group("闪避")
@export var dash_speed := 1800.0
@export var dash_duration := 0.18
## 无敌帧窗口（从闪避开始计时）。通常覆盖闪避前 70% 左右
@export var dash_iframe_begin := 0.0
@export var dash_iframe_end := 0.14
@export var dash_cooldown := 0.30

@export_group("输入手感")
## 输入缓冲窗口：早按的指令不会被吞。推荐 0.12 - 0.18
@export_range(0.05, 0.30, 0.01) var input_buffer_window := 0.15

@export_group("受击")
@export var max_health := 100.0
## 受击硬直时长
@export var hit_stun := 0.20
## 受击后的保护帧，避免被多个敌人同时命中瞬间暴毙
@export var hurt_iframe := 0.55
## 击退抗性：0 = 完全被推开，1 = 不动
@export_range(0.0, 1.0, 0.05) var knockback_resist := 0.5

@export_group("攻击")
## 三段普攻，按顺序循环
@export var combo: Array[AttackData] = []
## 连段保持窗口：上一段结束后多久内再按普攻算“下一段”
@export var combo_window := 0.35
## 技能
@export var skill: AttackData
@export var skill_cooldown := 3.0

@onready var _body: Polygon2D = $Body
@onready var _weapon_pivot: Node2D = $WeaponPivot
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _attack_hitbox: Hitbox = $AttackHitbox
@onready var _attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

var current_health := 0.0
var state: State = State.IDLE
## 当前朝向（单位向量），攻击判定按它旋转
var facing := Vector2.RIGHT
## 是否处于无敌（闪避无敌帧 / 受击保护）：调试面板与 hurtbox 都读它
var invulnerable := false

var _state_time := 0.0
var _dash_cd := 0.0
var _skill_cd := 0.0
var _iframe_left := 0.0
var _combo_index := -1
var _combo_reset_left := 0.0
var _active_data: AttackData = null
var _phase := 0  # 0 前摇 / 1 判定 / 2 后摇
var _swing_offset := 0.0

var _buffer := InputBuffer.new()
var _shape_rect := RectangleShape2D.new()
var _shape_circle := CircleShape2D.new()


func _ready() -> void:
	add_to_group("player")
	_buffer.window = input_buffer_window
	current_health = max_health

	_hurtbox.actor = self
	_hurtbox.team = 0
	_hurtbox.hurt.connect(_on_hurt)

	_attack_hitbox.source = self
	_attack_hitbox.attack_team = 0
	_attack_shape.shape = _shape_rect

	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_poll_input()

	match state:
		State.IDLE, State.MOVE:
			_update_free(delta)
		State.ATTACK, State.SKILL:
			_update_action(delta)
		State.DASH:
			_update_dash(delta)
		State.HURT:
			_update_hurt(delta)
		State.DEAD:
			velocity = Vector2.ZERO

	move_and_slide()
	_update_visual()
	_update_invulnerable()


# ---------------------------------------------------------------- 主循环分段


func _tick_timers(delta: float) -> void:
	_state_time += delta
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_skill_cd = maxf(_skill_cd - delta, 0.0)
	_iframe_left = maxf(_iframe_left - delta, 0.0)
	if _combo_reset_left > 0.0:
		_combo_reset_left = maxf(_combo_reset_left - delta, 0.0)
		if _combo_reset_left == 0.0:
			_combo_index = -1
	_buffer.window = input_buffer_window


func _poll_input() -> void:
	# 用轮询而不是 _input 事件：轮询的实现同时兼容键盘、手柄与自动化测试
	# （Input.action_press 不会产生 InputEvent，事件驱动的写法在测试里会失效）。
	if Input.is_action_just_pressed("attack"):
		_buffer.press("attack")
	if Input.is_action_just_pressed("dash"):
		_buffer.press("dash")
	if Input.is_action_just_pressed("skill"):
		_buffer.press("skill")


func _update_free(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length_squared() > 0.001:
		facing = dir.normalized()
		velocity = velocity.move_toward(dir * move_speed, accel * delta)
		state = State.MOVE
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		state = State.IDLE

	# 动作优先级：闪避 > 技能 > 普攻
	if _buffer.consume("dash") and _dash_cd <= 0.0:
		_start_dash()
		return
	if _buffer.consume("skill") and _skill_cd <= 0.0 and skill != null:
		_start_action(skill, State.SKILL)
		return
	if _buffer.consume("attack") and not combo.is_empty():
		var next := 0
		if _combo_reset_left > 0.0 and _combo_index >= 0:
			next = (_combo_index + 1) % combo.size()
		_start_attack(next)


func _start_attack(index: int) -> void:
	index = clampi(index, 0, combo.size() - 1)
	_combo_index = index
	_combo_reset_left = 0.0
	_start_action(combo[index], State.ATTACK)


func _start_action(data: AttackData, new_state: State) -> void:
	_active_data = data
	state = new_state
	_state_time = 0.0
	_phase = 0
	_swing_offset = -1.1
	_attack_hitbox.deactivate()

	# 出招前冲：只给一点点，太多会变成“按键位移”
	if data.step_impulse > 0.0:
		velocity = facing * data.step_impulse

	if new_state == State.SKILL:
		_skill_cd = skill_cooldown


func _update_action(delta: float) -> void:
	var data := _active_data
	if data == null:
		state = State.IDLE
		return

	velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	var active_end := data.windup + data.active
	var total := active_end + data.recovery

	# 阶段推进
	if _phase == 0 and _state_time >= data.windup:
		_phase = 1
		_apply_hitbox(data)
		_attack_hitbox.activate(data.hit)
	elif _phase == 1 and _state_time >= active_end:
		_phase = 2
		_attack_hitbox.deactivate()

	# ---- 取消窗：判定结束后允许用闪避 / 技能 / 下一段普攻提前结束后摇 ----
	if _state_time >= data.cancel_from:
		if _buffer.consume("dash") and _dash_cd <= 0.0:
			_attack_hitbox.deactivate()
			_start_dash()
			return
		if state == State.ATTACK and _buffer.consume("skill") and _skill_cd <= 0.0 and skill != null:
			_attack_hitbox.deactivate()
			_start_action(skill, State.SKILL)
			return
		if state == State.ATTACK and _buffer.consume("attack"):
			var next := _combo_index + 1
			if next < combo.size():
				_attack_hitbox.deactivate()
				_start_attack(next)
				return

	if _state_time >= total:
		_attack_hitbox.deactivate()
		_end_action()


func _end_action() -> void:
	if state == State.ATTACK:
		# 连段没打满：留一个窗口，下一段可以接着出
		_combo_reset_left = combo_window
	state = State.IDLE
	_phase = 0
	_active_data = null


func _apply_hitbox(data: AttackData) -> void:
	if data.hitbox_shape == 0:
		_shape_rect.size = data.hitbox_size
		_attack_shape.shape = _shape_rect
	else:
		_shape_circle.radius = data.hitbox_radius
		_attack_shape.shape = _shape_circle
	# 判定盒跟着朝向转
	_attack_hitbox.position = data.hitbox_offset.rotated(facing.angle())
	_attack_hitbox.rotation = facing.angle()


func _start_dash() -> void:
	if state == State.ATTACK or state == State.SKILL:
		_attack_hitbox.deactivate()
	state = State.DASH
	_state_time = 0.0
	_dash_cd = dash_cooldown

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length_squared() > 0.001:
		facing = dir.normalized()
	velocity = facing * dash_speed


func _update_dash(delta: float) -> void:
	# 匀速略衰减：前段快、尾段收，避免“滑冰”
	var t := clampf(_state_time / maxf(dash_duration, 0.01), 0.0, 1.0)
	velocity = facing * dash_speed * lerpf(1.0, 0.55, t)
	if _state_time >= dash_duration:
		velocity *= 0.4
		state = State.IDLE


func _update_hurt(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, friction * 0.6 * delta)
	if _state_time >= hit_stun:
		state = State.IDLE


func _update_invulnerable() -> void:
	var inv := _iframe_left > 0.0
	if state == State.DASH and _state_time >= dash_iframe_begin and _state_time <= dash_iframe_end:
		inv = true
	invulnerable = inv
	_hurtbox.set_invulnerable(inv)


func _update_visual() -> void:
	# 武器跟随朝向，并在出招期间做一个挥砍弧
	var target := facing.angle()
	if state == State.ATTACK or state == State.SKILL:
		var data := _active_data
		if data != null:
			var swing_time := maxf(data.windup + data.active, 0.01)
			var t := clampf(_state_time / swing_time, 0.0, 1.0)
			_swing_offset = lerpf(-1.15, 0.95, ease(t, 0.35))
		else:
			_swing_offset = 0.0
	else:
		_swing_offset = lerpf(_swing_offset, 0.0, 0.35)
	_weapon_pivot.rotation = target + _swing_offset

	# 闪避时压扁一点，读得出“在闪”
	if state == State.DASH:
		_body.scale = Vector2(1.12, 0.88)
	else:
		_body.scale = _body.scale.lerp(Vector2.ONE, 0.25)


# ---------------------------------------------------------------- 受击 / 死亡


func _on_hurt(hit: HitData, source: Node2D, _hitbox: Hitbox) -> void:
	if state == State.DEAD:
		return

	current_health = maxf(current_health - hit.damage, 0.0)
	health_changed.emit(current_health, max_health)

	_flash(hit.hit_flash)
	get_tree().call_group("shake_camera", "add_trauma", hit.shake)

	var knock_dir := facing
	if source != null:
		knock_dir = (global_position - source.global_position).normalized()
	velocity = knock_dir * hit.knockback * (1.0 - knockback_resist)

	_iframe_left = hurt_iframe
	attack_hitbox_stop()

	if current_health <= 0.0:
		_die()
	else:
		state = State.HURT
		_state_time = 0.0


## 硬直/死亡时立刻关掉自己的判定盒，避免“死了还在出刀”
func attack_hitbox_stop() -> void:
	_attack_hitbox.deactivate()
	_phase = 2


func _die() -> void:
	state = State.DEAD
	_hurtbox.set_invulnerable(true)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_body, "modulate:a", 0.25, 0.35)
	tw.tween_property(_body, "scale", Vector2(1.3, 0.6), 0.35)
	died.emit()


func _flash(duration: float) -> void:
	var mat := _body.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flash_amount", 1.0)
	var tw := create_tween()
	tw.tween_method(_set_flash, 1.0, 0.0, maxf(duration, 0.01))


func _set_flash(value: float) -> void:
	var mat := _body.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("flash_amount", value)


# ---------------------------------------------------------------- 对外查询（HUD / 调试）


func state_name() -> String:
	return STATE_NAMES[state]


func health_ratio() -> float:
	return current_health / maxf(max_health, 1.0)


func combo_index() -> int:
	return _combo_index


func buffered(action: StringName) -> bool:
	return _buffer.has_buffered(action)
