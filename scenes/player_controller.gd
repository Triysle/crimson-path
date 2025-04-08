extends CharacterBody2D

# Player movement parameters
@export var move_speed = 200.0
@export var jump_velocity = -350.0
@export var acceleration = 20.0
@export var air_acceleration = 10.0
@export var friction = 10.0
@export var air_resistance = 5.0
@export var gravity_multiplier = 1.0

# Track player state
var is_attacking = false
var is_crouching = false
var is_sliding = false
var can_double_jump = false
var has_double_jumped = false
var direction = 0
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Get references to nodes
@onready var animated_sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D

func _ready():
	# Start with the idle animation
	animated_sprite.play("idle")

func _physics_process(delta):
	apply_gravity(delta)
	handle_input()
	apply_movement(delta)
	update_animations()
	move_and_slide()

func apply_gravity(delta):
	# Apply gravity when in the air
	if not is_on_floor():
		velocity.y += gravity * gravity_multiplier * delta

func handle_input():
	# Only process input if not attacking
	if is_attacking:
		direction = 0
		return
		
	# Get horizontal movement input
	direction = Input.get_axis("ui_left", "ui_right")
	
	# Handle jumping
	if Input.is_action_just_pressed("ui_accept"):
		if is_on_floor():
			jump()
			can_double_jump = true
			has_double_jumped = false
		elif can_double_jump and not has_double_jumped:
			jump()
			has_double_jumped = true
	
	# Handle attack input
	if Input.is_action_just_pressed("ui_focus_next") and not is_attacking:
		attack()
	
	# Handle crouching
	is_crouching = Input.is_action_pressed("ui_down") and is_on_floor()
	
	# Start slide if running and pressing down
	if is_on_floor() and abs(velocity.x) > move_speed * 0.5 and Input.is_action_just_pressed("ui_down"):
		start_slide()

func apply_movement(delta):
	# Handle horizontal movement
	if direction != 0:
		# Determine appropriate acceleration based on whether on floor
		var current_acceleration = acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, direction * move_speed, current_acceleration)
	else:
		# Apply friction/air resistance to slow down
		var current_friction = friction if is_on_floor() else air_resistance
		velocity.x = move_toward(velocity.x, 0, current_friction)
	
	# Limit speed while crouching
	if is_crouching and not is_sliding:
		velocity.x = move_toward(velocity.x, 0, friction * 2)

func jump():
	velocity.y = jump_velocity
	animated_sprite.play("jump")

func attack():
	is_attacking = true
	if is_on_floor():
		if is_crouching:
			animated_sprite.play("crouchattack")
		else:
			animated_sprite.play("attacks")
	else:
		animated_sprite.play("airattack")
	
	# Wait for animation to finish
	await animated_sprite.animation_finished
	is_attacking = false

func start_slide():
	is_sliding = true
	is_crouching = false
	animated_sprite.play("slide")
	
	# Slide duration
	await get_tree().create_timer(0.5).timeout
	is_sliding = false

func update_animations():
	# Don't change animation during an attack
	if is_attacking:
		return
		
	# Handle different states
	if not is_on_floor():
		animated_sprite.play("jump")
	else:
		if is_sliding:
			animated_sprite.play("slide")
		elif is_crouching:
			animated_sprite.play("crouch")
		else:
			if direction != 0:
				animated_sprite.play("run")
			else:
				animated_sprite.play("idle")
	
	# Handle sprite flipping
	if direction > 0:
		animated_sprite.flip_h = false
	elif direction < 0:
		animated_sprite.flip_h = true
