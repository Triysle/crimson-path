extends CharacterBody2D

# Player movement parameters
@export var move_speed = 200.0
@export var jump_velocity = -350.0
@export var acceleration = 20.0
@export var air_acceleration = 10.0
@export var friction = 10.0
@export var air_resistance = 5.0
@export var gravity_multiplier = 1.0
@export var roll_speed = 300.0
@export var roll_duration = 0.5
@export var slide_duration = 0.7

# Track player state
var is_attacking = false
var is_crouching = false
var is_sliding = false
var is_rolling = false
var is_climbing = false
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
	# Apply gravity when in the air and not climbing
	if not is_on_floor() and not is_climbing:
		velocity.y += gravity * gravity_multiplier * delta

func handle_input():
	# Only process movement input if not attacking and not rolling
	if is_attacking or is_rolling:
		return
	
	# Get horizontal movement input using custom mappings
	direction = Input.get_axis("moveleft", "moveright")
	
	# Handle jumping with custom jump mapping
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			jump()
			can_double_jump = true
			has_double_jumped = false
		elif can_double_jump and not has_double_jumped:
			jump()
			has_double_jumped = true
	
	# Handle attack with custom attack mapping
	if Input.is_action_just_pressed("attack") and not is_attacking:
		attack()
	
	# Handle sliding with custom slide mapping
	if Input.is_action_just_pressed("slide") and is_on_floor() and not is_sliding:
		start_slide()
	
	# Handle rolling with custom roll mapping
	if Input.is_action_just_pressed("roll") and is_on_floor() and not is_rolling:
		start_roll()
	
	# Handle climbing with custom climb mapping
	# Note: This would need additional collision detection for climb-able objects
	is_climbing = Input.is_action_pressed("climb") and is_near_climbable_object()
	if is_climbing:
		velocity.y = -move_speed * 0.7 if Input.is_action_pressed("climb") else 0

	# Handle interaction with custom interact mapping
	if Input.is_action_just_pressed("interact"):
		interact()

func is_near_climbable_object():
	# This is a placeholder. You would need to implement proper detection
	# of ladder or climbable objects via raycasts or area detection.
	return false

func interact():
	# Placeholder for interaction functionality
	# This would interact with objects in the game world
	print("Interacting with nearby object")

func apply_movement(delta):
	# Handle horizontal movement
	if direction != 0 and not is_sliding and not is_rolling:
		# Determine appropriate acceleration based on whether on floor
		var current_acceleration = acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, direction * move_speed, current_acceleration)
	elif not is_sliding and not is_rolling:
		# Apply friction/air resistance to slow down
		var current_friction = friction if is_on_floor() else air_resistance
		velocity.x = move_toward(velocity.x, 0, current_friction)
	
	# Movement during rolling
	if is_rolling:
		# Maintain roll speed in the facing direction
		var roll_direction = -1 if animated_sprite.flip_h else 1
		velocity.x = roll_direction * roll_speed
	
	# Movement during sliding
	if is_sliding:
		# Gradually slow down the slide
		velocity.x = move_toward(velocity.x, 0, friction * 0.5)

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
	
	# Set initial slide velocity
	velocity.x = move_speed * 1.5 * (-1 if animated_sprite.flip_h else 1)
	animated_sprite.play("slide")
	
	# Slide duration
	await get_tree().create_timer(slide_duration).timeout
	is_sliding = false

func start_roll():
	is_rolling = true
	animated_sprite.play("roll")
	
	# Roll duration
	await get_tree().create_timer(roll_duration).timeout
	is_rolling = false

func update_animations():
	# Don't change animation during an attack, roll or slide
	if is_attacking or is_rolling or is_sliding:
		return
	
	# Handle different states
	if is_climbing:
		animated_sprite.play("climb")
	elif not is_on_floor():
		animated_sprite.play("jump")
	else:
		if is_crouching:
			animated_sprite.play("crouch")
		else:
			if direction != 0:
				animated_sprite.play("run")
			else:
				animated_sprite.play("idle")
	
	# Handle sprite flipping (unless in special states)
	if direction > 0 and not is_rolling and not is_sliding:
		animated_sprite.flip_h = false
	elif direction < 0 and not is_rolling and not is_sliding:
		animated_sprite.flip_h = true
