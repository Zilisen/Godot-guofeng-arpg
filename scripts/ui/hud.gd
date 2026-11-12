class_name HUD
extends CanvasLayer
## 极简 HUD：气血、房间进度、剩余敌人、横幅提示、转场淡入淡出。
## 文本全部中文，字体走 assets/theme/ui_theme.tres（系统字体占位）。

@onready var _room_label: Label = %RoomLabel
@onready var _enemy_label: Label = %EnemyLabel
@onready var _hp_bar: ProgressBar = %HPBar
@onready var _hp_text: Label = %HPText
@onready var _banner: Label = %BannerLabel
@onready var _center: Label = %CenterLabel
@onready var _fade: ColorRect = %Fade

var _banner_timer := 0.0


func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer = maxf(_banner_timer - delta, 0.0)
		if _banner_timer == 0.0:
			_banner.modulate.a = 0.0


func set_health(current: float, maximum: float) -> void:
	_hp_bar.max_value = maxf(maximum, 1.0)
	_hp_bar.value = current
	_hp_text.text = "气血 %d / %d" % [roundi(current), roundi(maximum)]


func set_room(index: int, total: int, room_name: String) -> void:
	_room_label.text = "第 %d / %d 间 · %s" % [index, total, room_name]


func set_enemies(count: int) -> void:
	_enemy_label.text = "残敌 %d" % count


func show_banner(text: String, duration := 2.0) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner_timer = duration


func show_center(text: String) -> void:
	_center.text = text
	_center.modulate.a = 1.0


func hide_center() -> void:
	_center.modulate.a = 0.0


func fade_out(duration := 0.2) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, duration)
	await tw.finished


func fade_in(duration := 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, duration)
	await tw.finished
