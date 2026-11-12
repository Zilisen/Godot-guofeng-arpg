class_name Enemy
extends CharacterBody2D
## 杂兵 AI：只会“追”和“打”，够第一期验证战斗循环即可。
##
## 状态：追击 → 前摇（变色预警）→ 挥击判定 → 后摇 → 冷却，被打断进受击。
## 关键设计：前摇必须可见（变色 + 微退），否则玩家无法用闪避做出反应，
## 动作游戏的“读招”体验就是从这里来的。

signal died(enemy: Enemy)

enum State { CHASE, WINDUP, ATTACK, RECOVER, HURT, DEAD }

const STATE_NAMES := ["追击", "前摇", "挥击", "后摇", "受击", "死亡"]

@export_group("移动")
@export var move_speed := 300.0
## 进入攻击的距离（像素，按 1080p 尺度）
@export var attack_range := 190.0
## 贴脸时略微后退，避免完全重叠
@export var keep_distance := 120.0

@export_group("节奏（秒）")
@export var windup := 0.45
@export var active := 0.12
@export var recovery := 0.6
@export var attack_cooldown := 0.55

@export_group("数值")
@export var max_health := 40.0
@export var damage := 8.0
@export var hit_stun := 0.25
@export_range(0.0, 1.0, 0.05) var knockback_resist := 0.15

@export_group("判定")
@export var hitbox_offset := Vector2(105, -80)
@export var hitbox_size := Vector2(210, 170)

@onready var _body: Polygon2D = $Body
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _attack_hitbox: Hitbox = $AttackHitbox
@onready var _attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

var current_health := 0.0
var state: State = State.CHASE
var facing := Vector2.LEFT

var _state_time := 0.0
var _cooldown := 0.0
var _player: Node2D = null
var _base_color := Color.WHITE
var _hit := HitData.new()
var _shape_rect := RectangleShape2D.new()


func _ready() -> void:
	add_to_group("enemy")
	current_health = max_health
	_base_color = _body.color

	_hurtbox.actor = self
	_hurtbox.team = 1
	_hurtbox.hurt.connect(_on_hurt)

	_attack_hitbox.source = self
	_attack_hitbox.attack_team = 1
	_shape_rect.size = hitbox_size
	_attack_shape.shape = _shape_rect
	_attack_hitbox.position = hitbox_offset
	_attack_hitbox.deactivate()

	_hit.damage = damage
	_hit.knockback = 420.0
	_hit.hitstop = 0.05
	_hit.shake = 0.12
	_hit.hit_flash = 0.1
	_hit.stun = 0.18

	_player = get_tree().get_first_node_in_group("player")


## 由房间生成时调用，用房间数据覆盖默认数值
func apply_room_data(data: RoomData) -> void:
	max_health = data.enemy_health
	current_health = max_health
	damage = data.enemy_damage
	move_speed = data.enemy_speed


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_state_time += delta
	_cooldown = maxf(_cooldown - delta, 0.0)

	match state:
		State.CHASE:
			_update_chase(delta)
		State.WINDUP:
			_update_windup(delta)
		State.ATTACK:
			_update_attack(delta)
		State.RECOVER:
			_update_recover(delta)
		State.HURT:
			_update_hurt(delta)
		State.DEAD:
			velocity = Vector2.ZERO

	move_and_slide()
	_update_visual()


func _update_chase(delta: float) -> void:
	if _player == null:
		velocity = velocity.move_toward(Vector2.ZERO, 2600.0 * delta)
		return
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > 0.01:
		facing = to_player.normalized()

	if dist > keep_distance:
		velocity = velocity.move_toward(facing * move_speed, 2600.0 * delta)
	else:
		# 太近就退一点，别糊在玩家身上
		velocity = velocity.move_toward(-facing * move_speed * 0.5, 2000.0 * delta)

	if dist <= attack_range and _cooldown <= 0.0:
		_enter_state(State.WINDUP)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 2000.0 * delta)


func _update_windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 3200.0 * delta)
	if _player != null:
		facing = (_player.global_position - global_position).normalized()
	if _state_time >= windup:
		_enter_state(State.ATTACK)
		_attack_hitbox.position = hitbox_offset.rotated(facing.angle())
		_attack_hitbox.rotation = facing.angle()
		_attack_hitbox.activate(_hit)


func _update_attack(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 3200.0 * delta)
	if _state_time >= active:
		_attack_hitbox.deactivate()
		_enter_state(State.RECOVER)


func _update_recover(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 2200.0 * delta)
	if _state_time >= recovery:
		_cooldown = attack_cooldown
		_enter_state(State.CHASE)


func _update_hurt(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 2400.0 * delta)
	if _state_time >= hit_stun:
		_enter_state(State.CHASE)


func _enter_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


func _update_visual() -> void:
	# 前摇预警：身体逐渐泛红，给玩家“该闪了”的信号
	if state == State.WINDUP:
		var t := clampf(_state_time / maxf(windup, 0.01), 0.0, 1.0)
		_body.modulate = _base_color.lerp(Color(1.0, 0.35, 0.3), t)
	else:
		_body.modulate = _body.modulate.lerp(Color.WHITE, 0.3)


func _on_hurt(hit: HitData, source: Node2D, _hitbox: Hitbox) -> void:
	if state == State.DEAD:
		return

	current_health = maxf(current_health - hit.damage, 0.0)
	_flash(hit.hit_flash)
	get_tree().call_group("shake_camera", "add_trauma", hit.shake)

	var knock_dir := facing
	if source != null:
		knock_dir = (global_position - source.global_position).normalized()
	if knock_dir.length_squared() < 0.001:
		knock_dir = -facing
	velocity = knock_dir * hit.knockback * (1.0 - knockback_resist)

	_attack_hitbox.deactivate()

	if current_health <= 0.0:
		_die()
	else:
		_enter_state(State.HURT)


func _die() -> void:
	state = State.DEAD
	_hurtbox.set_invulnerable(true)
	_attack_hitbox.deactivate()
	died.emit(self)
	# 死亡表现：压扁 + 淡出，然后移除
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_body, "scale", Vector2(1.35, 0.45), 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)


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


func state_name() -> String:
	return STATE_NAMES[state]


func health_ratio() -> float:
	return current_health / maxf(max_health, 1.0)
