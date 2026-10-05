extends CharacterBody2D

# --- настройки движения ---
@export var patrol_speed: float = 60.0   # скорость при патруле
@export var chase_speed: float = 110.0   # скорость, когда гонится за игроком
@export var point_a: Marker2D            # левая точка патруля
@export var point_b: Marker2D            # правая точка патруля
@export var detection_area: Area2D       # зона, в которой враг замечает игрока
@export var jump_velocity: float = -260.0  # сила прыжка на ступеньках

# --- настройки атаки ---
@export var hit_frame: int = 2           # кадр анимации, на котором удар попадает
@export var attack_range: float = 24.0   # на каком расстоянии начинает бить
@export var attack_cooldown: float = 1.0 # пауза между ударами (сек)
@export var damage: int = 1              # сколько хп снимает за удар

var is_attacking: bool = false           # идёт ли сейчас анимация удара
var can_attack: bool = true              # прошла ли перезарядка
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var target: Node2D = null               # игрок, пока он в зоне обнаружения
var current_point: Marker2D             # точка, к которой идёт на патруле

# --- здоровье ---
@export var max_health: int = 10
var health: int
var is_dead: bool = false

@onready var health_bar: ProgressBar = $HealthBar


func _ready() -> void:
	add_to_group("enemies")              # нужно для подсчёта убитых врагов
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	floor_snap_length = 12.0             # прилипание к полу, чтобы не отрываться на спусках
	floor_max_angle = deg_to_rad(60)     # ступени не считаются слишком крутыми
	current_point = point_b              # начинаем патруль с правой точки
	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	anim.animation_finished.connect(_on_animation_finished)
	anim.frame_changed.connect(_on_frame_changed)


func _physics_process(delta: float) -> void:
	# гравитация, пока в воздухе
	if not is_on_floor():
		velocity.y += gravity * delta

	# выбор поведения: бьёт -> стоит, видит игрока -> гонится, иначе патрулирует
	if is_attacking:
		velocity.x = 0          # во время удара стоим на месте
	elif target:
		_chase()
	else:
		_patrol()

	# упёрся в стену на земле (ступенька) -> прыгает
	if not is_attacking and is_on_floor() and is_on_wall() and velocity.x != 0:
		velocity.y = jump_velocity

	move_and_slide()
	_update_animation()


# ходит между точками A и B
func _patrol() -> void:
	var dx := current_point.global_position.x - global_position.x

	# Дошли до точки, меняем на противоположную
	if abs(dx) < 4.0:
		current_point = point_a if current_point == point_b else point_b
		dx = current_point.global_position.x - global_position.x

	_move_horizontally(sign(dx), patrol_speed)


# преследует игрока, а когда подошёл близко - бьёт
func _chase() -> void:
	var dx := target.global_position.x - global_position.x
	var in_range := global_position.distance_to(target.global_position) <= attack_range

	if in_range:
		velocity.x = 0
		anim.flip_h = dx < 0     # поворачиваемся лицом к игроку
		if can_attack:
			_start_attack()
	else:
		_move_horizontally(sign(dx), chase_speed)


# задаёт скорость по X и разворачивает спрайт в сторону движения
func _move_horizontally(direction: float, speed: float) -> void:
	velocity.x = direction * speed
	if direction != 0:
		anim.flip_h = direction < 0


# игрок зашёл в зону обнаружения - запоминаем его как цель
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		target = body


# игрок вышел из зоны - сбрасываем цель
func _on_body_exited(body: Node2D) -> void:
	if body == target:
		target = null  # вернётся к патрулированию


# запускает анимацию удара и ждёт, пока она закончится
func _start_attack() -> void:
	is_attacking = true
	can_attack = false
	anim.play("attack")

	# считаем длительность анимации: кадры / FPS / скорость воспроизведения
	var frames := anim.sprite_frames
	var duration := frames.get_frame_count("attack") / frames.get_animation_speed("attack") / anim.speed_scale
	await get_tree().create_timer(duration).timeout
	_end_attack()


# заканчивает атаку и включает перезарядку
func _end_attack() -> void:
	if not is_attacking:     # защита от двойного вызова (таймер + сигнал)
		return
	is_attacking = false
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true


# на нужном кадре анимации атаки наносим урон
func _on_frame_changed() -> void:
	if anim.animation == "attack" and anim.frame == hit_frame:
		deal_damage()


# запасной вариант завершения атаки, если сработает сигнал анимации
func _on_animation_finished() -> void:
	if anim.animation == "attack":
		_end_attack()


# переключает idle/run в зависимости от скорости
func _update_animation() -> void:
	if is_attacking:         # во время удара анимацию не перебиваем
		return
	if abs(velocity.x) > 1.0:
		anim.play("run")
	else:
		anim.play("idle")


# наносит урон игроку, если он всё ещё рядом
func deal_damage() -> void:
	if is_dead:
		return
	# запас 1.5 на случай, если игрок чуть отошёл за время анимации
	if target and global_position.distance_to(target.global_position) <= attack_range * 1.5:
		if target.has_method("take_damage"):
			target.take_damage(damage)


# получение урона от игрока
func take_damage(amount: int) -> void:
	if is_dead:
		return
	health = max(health - amount, 0)

	# Плавное уменьшение полоски
	var tween := create_tween()
	tween.tween_property(health_bar, "value", health, 0.1)

	if health <= 0:
		_die()

	# Короткая вспышка при попадании
	anim.modulate = Color(1, 0.4, 0.4)
	await get_tree().create_timer(0.1).timeout
	if not is_dead:
		anim.modulate = Color.WHITE

	if health <= 0:
		_die()


# смерть: отключаем врага, играем анимацию и удаляем со сцены
func _die() -> void:
	remove_from_group("enemies")           # чтобы не считался живым в итоговой статистике
	is_dead = true
	is_attacking = false
	velocity = Vector2.ZERO
	health_bar.hide()
	set_physics_process(false)             # враг больше не двигается
	set_deferred("collision_layer", 0)     # игрок и удары его не задевают
	set_deferred("collision_mask", 0)
	detection_area.set_deferred("monitoring", false)  # перестаёт замечать игрока

	anim.modulate = Color.WHITE
	anim.play("dead")

	# Ждём конец анимации по длительности (как с атакой, надёжнее сигнала)
	var frames := anim.sprite_frames
	var duration := frames.get_frame_count("dead") / frames.get_animation_speed("dead") / anim.speed_scale
	await get_tree().create_timer(duration).timeout
	queue_free()
