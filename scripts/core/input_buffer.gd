class_name InputBuffer
extends RefCounted
## 输入缓冲：按下后的一小段时间内持续“有效”，让连招/闪避不会因为早按几帧而丢失。
##
## 典型手感值：
##   0.12 - 0.15s：动作游戏里“跟手但严格”
##   0.15 - 0.18s：更宽松，适合键盘玩家 / 网络延迟补偿
##   超过 0.2s：会出现“我没按它却自己动”的粘滞感
##
## 用真实时间计时（Time.get_ticks_msec），因此不受暂停影响。

## 缓冲窗口（秒）
var window := 0.15

## action -> 按下时刻（毫秒）
var _stamps := {}


func press(action: StringName) -> void:
	_stamps[action] = Time.get_ticks_msec()


## 取出并清除该输入；只有在窗口内才返回 true
func consume(action: StringName) -> bool:
	if not _stamps.has(action):
		return false
	var stamp := int(_stamps[action])
	_stamps.erase(action)
	var age := (Time.get_ticks_msec() - stamp) / 1000.0
	return age <= window


## 只查询不清除，调试面板用
func age_of(action: StringName) -> float:
	if not _stamps.has(action):
		return -1.0
	return (Time.get_ticks_msec() - int(_stamps[action])) / 1000.0


func has_buffered(action: StringName) -> bool:
	var age := age_of(action)
	return age >= 0.0 and age <= window


func clear() -> void:
	_stamps.clear()
