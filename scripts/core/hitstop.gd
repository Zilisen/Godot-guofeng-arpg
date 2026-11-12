extends Node
## 命中停顿（hitstop）管理器（Autoload，全局名 HitStop）。
##
## 为什么不用 Engine.time_scale = 0：
##   1) 它是全局的，连 UI、摄像机、粒子一起冻住，玩家会觉得“卡了”，而不是“打中了”；
##   2) 改 time_scale 会让所有 delta 突然变成 0，任何用 delta 累计的计时器（含 Tween）都会跳变；
##   3) 声音不会跟着停，观感割裂。
##
## 这里提供两种方案，默认第一种：
##   ENTITY_ONLY  : 只把参与命中的实体 process_mode 设为 DISABLED 一小段时间。
##                  其他敌人、场景、摄像机照常跑，打击感只发生在“这一刀”上。
##   GLOBAL_PAUSE : get_tree().paused = true 的时间窗口，一次性冻结整个游戏世界
##                  （UI/摄像机需要 PROCESS_MODE_ALWAYS）。适合做大招/处决的强调。
##
## 计时使用真实时间（本节点 process_mode = ALWAYS，且从不修改 Engine.time_scale），
## 所以暂停期间计时照样走，不会出现“暂停卡死”。

enum Mode {
	ENTITY_ONLY,   ## 按实体冻结（推荐）
	GLOBAL_PAUSE,  ## 全局暂停时间窗口
}

## 当前使用的模式，可在运行时切换
var mode: Mode = Mode.ENTITY_ONLY

## instance_id -> {node, prev_mode, left}
var _records := {}
var _global_left := 0.0
var _global_prev_paused := false


func _ready() -> void:
	# 自己必须在暂停中也能跑，否则全局暂停窗口永远结束不了
	process_mode = Node.PROCESS_MODE_ALWAYS


## 冻结一组实体 duration 秒。重复调用取最长剩余时间（不会叠加成双倍）
func freeze(actors: Array, duration: float) -> void:
	if duration <= 0.0:
		return
	if mode == Mode.GLOBAL_PAUSE:
		_freeze_global(duration)
	else:
		_freeze_entities(actors, duration)


## 便捷写法：单个实体
func freeze_one(actor: Node, duration: float) -> void:
	freeze([actor], duration)


func is_frozen(actor: Node) -> bool:
	if actor == null:
		return false
	return _records.has(actor.get_instance_id())


## 切换到“按实体冻结”（默认）
func use_entity_mode() -> void:
	mode = Mode.ENTITY_ONLY


## 切换到“全局暂停窗口”
func use_global_pause_mode() -> void:
	mode = Mode.GLOBAL_PAUSE


## 立刻结束所有停顿（切换场景 / 重开时调用，避免状态泄漏）
func clear_all() -> void:
	for id in _records.keys():
		var rec: Dictionary = _records[id]
		var n = rec["node"]
		if is_instance_valid(n):
			n.process_mode = rec["prev"]
	_records.clear()
	if _global_left > 0.0:
		get_tree().paused = _global_prev_paused
	_global_left = 0.0


func _process(delta: float) -> void:
	_tick_global(delta)
	_tick_entities(delta)


func _freeze_entities(actors: Array, duration: float) -> void:
	for a in actors:
		var n := a as Node
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var id := n.get_instance_id()
		var rec = _records.get(id)
		if rec == null:
			_records[id] = {
				"node": n,
				"prev": n.process_mode,
				"left": duration,
			}
			# 延迟应用：命中通常发生在 Area2D 的物理回调里，
			# 引擎禁止在物理回调中直接禁用 CollisionObject（会报错并且行为不确定）。
			n.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
		else:
			# 已经在停：只延长，不重复保存 prev_mode
			rec["left"] = max(float(rec["left"]), duration)


func _tick_entities(delta: float) -> void:
	for id in _records.keys():
		var rec: Dictionary = _records[id]
		rec["left"] = float(rec["left"]) - delta
		if float(rec["left"]) > 0.0:
			continue
		var n = rec["node"]
		if is_instance_valid(n):
			# 同样用 set_deferred，保证“恢复”一定排在“禁用”之后执行
			n.set_deferred("process_mode", rec["prev"])
		_records.erase(id)


func _freeze_global(duration: float) -> void:
	if _global_left <= 0.0:
		_global_prev_paused = get_tree().paused
		get_tree().paused = true
	_global_left = max(_global_left, duration)


func _tick_global(delta: float) -> void:
	if _global_left <= 0.0:
		return
	_global_left -= delta
	if _global_left <= 0.0:
		_global_left = 0.0
		get_tree().paused = _global_prev_paused
