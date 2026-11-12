extends Node2D
## 调试可视化：hitbox / hurtbox / 无敌帧 / 状态机状态。
##
## 为什么画在世界坐标而不是 CanvasLayer：
##   直接画世界坐标就不用做屏幕坐标换算，镜头抖动时判定框也会跟着抖，看到的就是真实位置。
##
## 开关：F1 总开关，F2 只切判定框。

const UI_THEME := preload("res://assets/theme/ui_theme.tres")

@export var enabled := false
@export var show_shapes := true
@export var show_actor_text := true
@export var fill_alpha := 0.20

const COLOR_HITBOX := Color(1.0, 0.3, 0.25)
const COLOR_HURTBOX := Color(0.25, 0.85, 1.0)
const COLOR_TEXT := Color(0.85, 1.0, 0.85)
const COLOR_IFRAME := Color(0.4, 1.0, 1.0)

var _font: Font


func _ready() -> void:
	z_index = 100
	_font = UI_THEME.default_font


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_debug"):
		enabled = not enabled
	if Input.is_action_just_pressed("toggle_shapes"):
		show_shapes = not show_shapes
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return

	if show_shapes:
		_draw_areas("hitbox", COLOR_HITBOX)
		_draw_areas("hurtbox", COLOR_HURTBOX)

	if show_actor_text:
		_draw_actor_text()

	_draw_legend()


func _draw_areas(group: StringName, color: Color) -> void:
	for node in get_tree().get_nodes_in_group(group):
		var area := node as Area2D
		if area == null or not is_instance_valid(area):
			continue

		var has_hitbox := area is Hitbox
		var active := true
		if has_hitbox:
			active = (area as Hitbox).is_active
		# 未激活的 hitbox 画得很淡，激活时高亮——这样能一眼看出“判定帧到底有没有生效”
		var line := color
		var fill := Color(color.r, color.g, color.b, fill_alpha)
		if has_hitbox and not active:
			line = Color(color.r, color.g, color.b, 0.25)
			fill = Color(color.r, color.g, color.b, 0.05)

		for child in area.get_children():
			var cs := child as CollisionShape2D
			if cs == null or cs.shape == null:
				continue
			_draw_shape(cs, fill, line, 3.0 if active else 1.5)


func _draw_shape(cs: CollisionShape2D, fill: Color, line: Color, width: float) -> void:
	var xf := cs.global_transform
	var shape := cs.shape
	if shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius * xf.get_scale().x
		draw_circle(xf.origin, radius, fill)
		draw_arc(xf.origin, radius, 0.0, TAU, 48, line, width)
	elif shape is RectangleShape2D:
		var size: Vector2 = (shape as RectangleShape2D).size * xf.get_scale()
		var half := size * 0.5
		var pts := PackedVector2Array([
			xf * Vector2(-half.x, -half.y),
			xf * Vector2(half.x, -half.y),
			xf * Vector2(half.x, half.y),
			xf * Vector2(-half.x, half.y),
		])
		draw_colored_polygon(pts, fill)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, line, width)


func _draw_actor_text() -> void:
	# 玩家：状态 + 无敌 + 缓冲
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null and is_instance_valid(player):
		var inv := "是" if player.invulnerable else "否"
		var frozen := "是" if HitStop.is_frozen(player) else "否"
		var txt := "状态:%s  无敌:%s  停顿:%s  连段:%d" % [
			player.state_name(), inv, frozen, player.combo_index() + 1
		]
		draw_string(_font, player.global_position + Vector2(-150, -330), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, COLOR_TEXT)
		if player.invulnerable:
			draw_arc(player.global_position + Vector2(0, -140), 150.0, 0.0, TAU, 48, COLOR_IFRAME, 5.0)

	# 敌人：状态 + 血量
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		var label := "%s %.0f" % [enemy.state_name(), enemy.current_health]
		draw_string(_font, enemy.global_position + Vector2(-80, -230), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.85, 0.7))


func _draw_legend() -> void:
	var lines := [
		"F1 调试开关：%s    F2 判定框：%s" % ["开" if enabled else "关", "开" if show_shapes else "关"],
		"红=hitbox（亮=判定帧生效）  蓝=hurtbox  青圈=无敌帧",
		"J 普攻 / K 闪避 / L 技能 / R 重开",
	]
	var pos := Vector2(60, 760)
	for i in lines.size():
		draw_string(_font, pos + Vector2(0, i * 34), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.75, 0.8, 0.75))
