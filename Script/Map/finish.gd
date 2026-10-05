extends Area2D

@export var win_screen: CanvasLayer   # окно результатов, назначается в Инспекторе

var finished: bool = false            # дошёл ли игрок до финиша
var start_time_ms: int = 0            # момент старта уровня (мс), для подсчёта времени
var total_enemies: int = 0            # сколько врагов было в начале уровня


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # работает и на паузе, иначе клавиша R не сработает
	body_entered.connect(_on_body_entered)
	start_time_ms = Time.get_ticks_msec()
	_count_enemies.call_deferred()   # ждём, пока все враги добавятся в группу


# запоминает общее число врагов в начале уровня
func _count_enemies() -> void:
	total_enemies = get_tree().get_nodes_in_group("enemies").size()


# игрок зашёл в зону финиша
func _on_body_entered(body: Node2D) -> void:
	if finished:             # защита от повторного срабатывания
		return
	if body.is_in_group("player"):
		finished = true
		get_tree().paused = true   # останавливаем игру

		# время прохождения в секундах
		var time_sec := (Time.get_ticks_msec() - start_time_ms) / 1000.0
		# убитые = было всего - осталось живых
		var alive := get_tree().get_nodes_in_group("enemies").size()
		var kills := total_enemies - alive
		win_screen.show_result(time_sec, kills, total_enemies)


# после победы клавиша R перезапускает уровень
func _unhandled_input(event: InputEvent) -> void:
	if finished and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_tree().paused = false          # снимаем паузу, иначе новая сцена загрузится замороженной
		get_tree().reload_current_scene()
