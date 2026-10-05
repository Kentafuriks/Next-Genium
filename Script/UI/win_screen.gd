extends CanvasLayer

# ссылки на элементы окна (пути считаются от корня сцены)
@onready var title_label: Label = $Center/Panel/VBox/TitleLabel      # "Ты выиграл!" / "Ты проиграл"
@onready var time_label: Label = $Center/Panel/VBox/TimeLabel        # время прохождения
@onready var kills_label: Label = $Center/Panel/VBox/KillsLabel      # сколько врагов убито
@onready var restart_button: Button = $Center/Panel/VBox/Buttons/RestartButton
@onready var quit_button: Button = $Center/Panel/VBox/Buttons/QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # кнопки должны работать, пока игра на паузе
	hide()                                    # окно скрыто, пока не вызван show_result
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


# показывает окно: won = true это победа, false это поражение
func show_result(time_sec: float, kills: int, total_enemies: int, won: bool = true) -> void:
	title_label.text = "Ты выиграл!" if won else "Ты проиграл"
	# переводим секунды в формат ММ:СС.сотые
	var minutes := int(time_sec) / 60
	var seconds := fmod(time_sec, 60.0)
	time_label.text = "Время: %02d:%05.2f" % [minutes, seconds]
	kills_label.text = "Убито врагов: %d из %d" % [kills, total_enemies]
	show()
	restart_button.grab_focus()   # фокус на кнопке, чтобы можно было нажать Enter


# снимаем паузу и загружаем уровень заново
func _on_restart_pressed() -> void:
	get_tree().paused = false     # иначе новая сцена загрузится замороженной
	get_tree().reload_current_scene()


# закрывает игру
func _on_quit_pressed() -> void:
	get_tree().quit()
