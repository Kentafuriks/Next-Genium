extends CharacterBody2D

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack1_area: Area2D = $Attack1Area2D   # зона лёгкого удара (ЛКМ)
@onready var attack2_area: Area2D = $Attack2Area2D   # зона тяжёлого удара (ПКМ)
@onready var health_bar: ProgressBar = $HealthBar


const SPEED = 300.0
const JUMP_VELOCITY = -400.0

# Урон и кадр, на котором оружие попадает (кадры считаются с 0)
@export var light_damage: int = 1
@export var heavy_damage: int = 3
@export var light_hit_frame: int = 2
@export var heavy_hit_frame: int = 3
@export var max_health: int = 10

var is_attacking: bool = false      # идёт ли сейчас анимация атаки
var current_attack: String = ""     # "attack1" или "attack2"
var hit_done: bool = false          # урон за этот удар уже нанесён (чтобы не бил каждый кадр)
var attack1_area_x: float           # исходное смещение зон по X (справа от игрока)
var attack2_area_x: float
var health: int
var is_dead: bool = false

@export var feet_offset: float = 12.0   # расстояние от центра игрока до ног

# сцена окна результата, показываем её при смерти
const WIN_SCREEN_SCENE := preload("res://Script/UI/UI_Finished.tscn")

var start_time_ms: int = 0          # момент старта уровня, для подсчёта времени
var total_enemies: int = 0          # сколько врагов было в начале


func _ready() -> void:
	start_time_ms = Time.get_ticks_msec()
	_count_enemies.call_deferred()  # ждём, пока все враги встанут в группу
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	# запоминаем смещение зон, чтобы потом зеркалить при развороте
	attack1_area_x = abs(attack1_area.position.x)
	attack2_area_x = abs(attack2_area.position.x)
	anim.frame_changed.connect(_on_frame_changed)
	anim.play("idle")


# атаки на кнопки мыши: ЛКМ - быстрая, ПКМ - тяжёлая
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_start_attack("attack1")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_start_attack("attack2")


func _physics_process(delta: float) -> void:
	# гравитация, пока в воздухе
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Стоять на месте заставляет только тяжёлая атака
	var movement_locked := is_attacking and current_attack == "attack2"

	# Прыжок
	if not movement_locked and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_up")) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Движение
	var direction := Input.get_axis("ui_left", "ui_right")
	if movement_locked:
		velocity.x = move_toward(velocity.x, 0, SPEED)   # тяжёлый удар: плавно останавливаемся
	elif direction:
		velocity.x = direction * SPEED
		# во время удара не разворачиваемся, чтобы зона не прыгала на другую сторону
		if not is_attacking:
			anim.flip_h = direction < 0
			_update_attack_areas()
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()
	_check_lava()
	play_anim()


# смерть, если ноги игрока стоят на клетке лавы
func _check_lava() -> void:
	if is_dead:
		return
	var lava := get_tree().get_first_node_in_group("lava") as TileMapLayer
	if lava == null:
		return
	# позицию ног переводим в координаты клетки тайлмапа
	var feet := global_position + Vector2(0, feet_offset)
	var cell := lava.local_to_map(lava.to_local(feet))
	if lava.get_cell_source_id(cell) != -1:   # -1 значит клетка пустая
		take_damage(max_health)


# зеркалит зоны атаки в сторону, куда смотрит игрок
func _update_attack_areas() -> void:
	var sign_x := -1.0 if anim.flip_h else 1.0
	attack1_area.position.x = attack1_area_x * sign_x
	attack2_area.position.x = attack2_area_x * sign_x


# выбор анимации: прыжок, бег или покой
func play_anim() -> void:
	if is_attacking:      # анимацию атаки не перебиваем
		return
	if not is_on_floor():
		anim.play("jump")
	elif abs(velocity.x) > 1.0:
		anim.play("run")
	else:
		anim.play("idle")


# запуск атаки: attack_name это "attack1" или "attack2"
func _start_attack(attack_name: String) -> void:
	if is_dead or is_attacking:
		return
	is_attacking = true
	hit_done = false
	current_attack = attack_name
	anim.play(attack_name)

	# Конец атаки по длительности анимации
	var frames := anim.sprite_frames
	var duration := frames.get_frame_count(attack_name) / frames.get_animation_speed(attack_name) / anim.speed_scale
	await get_tree().create_timer(duration).timeout
	is_attacking = false
	current_attack = ""


# на кадре удара один раз наносим урон
func _on_frame_changed() -> void:
	if not is_attacking or hit_done:
		return
	var hit_frame := light_hit_frame if current_attack == "attack1" else heavy_hit_frame
	if anim.animation == current_attack and anim.frame == hit_frame:
		hit_done = true
		_deal_damage()


# бьём всех, кто сейчас в зоне текущей атаки
func _deal_damage() -> void:
	var is_light := current_attack == "attack1"
	var area := attack1_area if is_light else attack2_area
	var damage := light_damage if is_light else heavy_damage

	for body in area.get_overlapping_bodies():
		if body != self and body.has_method("take_damage"):
			body.take_damage(damage)


# получение урона (вызывается врагом и лавой)
func take_damage(amount: int) -> void:
	if is_dead:
		return
	health = max(health - amount, 0)

	# полоска уменьшается плавно
	var tween := create_tween()
	tween.tween_property(health_bar, "value", health, 0.15)

	# Короткая красная вспышка
	anim.modulate = Color(1, 0.4, 0.4)
	await get_tree().create_timer(0.1).timeout
	if not is_dead:
		anim.modulate = Color.WHITE

	if health <= 0:
		_die()


# смерть: останавливаем игрока и показываем экран "Ты проиграл"
func _die() -> void:
	if is_dead:     # защита от повторного вызова
		return
	is_dead = true
	is_attacking = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	anim.modulate = Color.WHITE

	if anim.sprite_frames.has_animation("dead"):
		anim.play("dead")

	await get_tree().create_timer(1.0).timeout   # время на анимацию смерти

	# статистика для окна: время и количество убитых
	var time_sec := (Time.get_ticks_msec() - start_time_ms) / 1000.0
	var alive := get_tree().get_nodes_in_group("enemies").size()
	var kills := total_enemies - alive

	var screen := WIN_SCREEN_SCENE.instantiate()
	get_tree().current_scene.add_child(screen)
	screen.show_result(time_sec, kills, total_enemies, false)
	get_tree().paused = true   # пауза после показа окна, иначе таймер выше не досчитал бы


# запоминает общее число врагов в начале уровня
func _count_enemies() -> void:
	total_enemies = get_tree().get_nodes_in_group("enemies").size()
