extends Camera2D
## 震屏：trauma 模型。
##
## 为什么不直接随机抖动 offset：trauma 模型让“小打击轻微抖、大打击明显抖”，
## 并且用幂函数（trauma^2）让衰减更自然，不会一直嗡嗡抖。
##
## 使用方式：任意脚本调用 get_tree().call_group("shake_camera", "add_trauma", 0.3)

@export_group("震屏")
## 每秒衰减的 trauma 量
@export var decay := 1.8
## 最大位移（像素）
@export var max_offset := 16.0
## 最大旋转（弧度）
@export var max_roll := 0.02
## 抖动的频率（越大越碎）
@export var frequency := 26.0

var trauma := 0.0

var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _base_position := Vector2.ZERO


func _ready() -> void:
	add_to_group("shake_camera")
	_rng.randomize()
	_base_position = position


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if trauma <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		return

	trauma = maxf(trauma - decay * delta, 0.0)
	_time += delta * frequency
	var shake_amount := trauma * trauma
	# 用近似噪声的正弦叠加，避免纯 randf 造成的“闪烁抖动”
	offset = Vector2(
		sin(_time * 1.7 + _rng.randf() * 0.2) * max_offset * shake_amount,
		sin(_time * 2.3 + 1.1) * max_offset * shake_amount
	)
	rotation = sin(_time * 1.3) * max_roll * shake_amount


## 房间切换时把镜头复位
func snap_to(target: Vector2) -> void:
	_base_position = target
	position = target
	offset = Vector2.ZERO
	trauma = 0.0
