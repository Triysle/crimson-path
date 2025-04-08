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
# Will add climb_speed when we implement climbing mechanics

# Attack parameters
@export var attack_charge_time = 1  # Time in seconds to charge heavy attack
@export var max_combo_delay = 0.8     # Maximum time between attacks to continue combo

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

# Combat variables
var current_combo = 0       # Current combo attack (0, 1, 2)
var max_combo = 2           # Maximum combo attack index (0-based, so 0,1,2 = 3 attacks)
var combo_timer = 0.0       # Timer for combo window
var attack_charging = false # Whether heavy attack is charging
var charge_timer = 0.0      # Timer for charge attack
var attack_pressed_time = 0.0 # When attack button was pressed

# Get references to nodes
@onready var animated_sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D

func _ready():
	# Start with the idle animation
	animated_sprite.play("idle")

func _physics_process(delta):
	apply_gravity(delta)
	handle_input()
	handle_combat(delta)
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
	
	# Handle crouching - movedown key when on floor
	if is_on_floor() and Input.is_action_pressed("movedown"):
		is_crouching = true
		# Cancel horizontal movement when crouching
		direction = 0
	elif is_on_floor():
		# Only stop crouching if we're on the floor
		# This prevents the player from getting stuck in crouching state when jumping
		is_crouching = false
	
	# Handle jumping with custom jump mapping
	if Input.is_action_just_pressed("jump"):
		if is_on_floor() and not is_crouching: # Don't allow jumping while crouching
			jump()
			can_double_jump = true
			has_double_jumped = false
		elif can_double_jump and not has_double_jumped:
			jump()
			has_double_jumped = true
	
	# Attack handling moved to handle_combat()
	
	# Handle sliding with custom slide mapping
	if Input.is_action_just_pressed("slide") and is_on_floor() and not is_sliding and not is_crouching:
		start_slide()
	
	# Handle rolling with custom roll mapping
	if Input.is_action_just_pressed("roll") and is_on_floor() and not is_rolling and not is_crouching:
		start_roll()
	
	# Climbing will be implemented later for ladders, vines, etc.
	is_climbing = is_near_climbable_object()
	
	# For now, just check if we're at a ledge for hanging animation
	# In a real implementation, you would use raycasts to detect ledges
	# This is a placeholder until we implement proper ledge detection

	# Handle interaction with custom interact mapping
	if Input.is_action_just_pressed("interact"):
		interact()

func handle_combat(delta):
	# Decrement combo timer
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			# Reset combo if player waited too long
			current_combo = 0
	
	# Don't process new attacks if already attacking
	if is_attacking:
		return
	
	# Process attack input
	if Input.is_action_just_pressed("attack"):
		attack_pressed_time = Time.get_ticks_msec() / 1000.0
		
		# Start charging heavy attack if not already attacking
		if not is_attacking:
			attack_charging = true
			charge_timer = 0.0
	
	# Handle charging for heavy attack
	if attack_charging:
		if Input.is_action_pressed("attack"):
			charge_timer += delta
			# Visual indication of charging could be added here
		
		# Release attack button - execute appropriate attack
		if Input.is_action_just_released("attack"):
			attack_charging = false
			
			# If charged enough, do heavy attack
			if charge_timer >= attack_charge_time:
				perform_heavy_attack()
			else:
				# Otherwise do next combo attack
				perform_combo_attack()

func perform_combo_attack():
	is_attacking = true
	
	# Determine which animation to play based on combo state
	var attack_anim = ""
	
	if is_on_floor():
		if is_crouching:
			attack_anim = "crouchattack"
		else:
			# Choose the appropriate attack animation based on combo
			match current_combo:
				0: attack_anim = "attack1" # Upswing
				1: attack_anim = "attack2" # Downswing
				2: attack_anim = "attack3" # Thrust
	else:
		attack_anim = "airattack"
	
	# Actually play the animation
	animated_sprite.play(attack_anim)
	
	# Apply any attack effects
	apply_attack_effects(current_combo)
	
	# Advance combo if on ground and not crouching
	if is_on_floor() and not is_crouching:
		current_combo = (current_combo + 1) % (max_combo + 1)
		combo_timer = max_combo_delay
	
	# Wait for animation to finish
	await animated_sprite.animation_finished
	is_attacking = false

func perform_heavy_attack():
	is_attacking = true
	
	# Play heavy attack animation
	if is_on_floor():
		if is_crouching:
			animated_sprite.play("crouchattack")  # For now, use same anim
		else:
			animated_sprite.play("attack4")  # Heavy slash
	else:
		animated_sprite.play("airattack")  # For now, use same anim
	
	# Apply heavy attack effects
	apply_heavy_attack_effects()
	
	# Reset combo
	current_combo = 0
	
	# Wait for animation to finish
	await animated_sprite.animation_finished
	is_attacking = false

func apply_attack_effects(combo_index):
	# This function would apply different effects for each attack in the combo
	# For example, different damage, knockback, or particle effects
	match combo_index:
		0:  # Upswing - quick, low damage
			print("Upswing attack")
			# Code for upswing effects
		1:  # Downswing - medium damage
			print("Downswing attack")
			# Code for downswing effects
		2:  # Thrust - longer reach
			print("Thrust attack")
			# Code for thrust effects

func apply_heavy_attack_effects():
	# Heavy attack effects - high damage, knockback, etc.
	print("Heavy attack!")
	# Code for heavy attack effects

func is_near_climbable_object():
	# This is a placeholder for future implementation
	# Will be used for ladders, vines, ropes, etc.
	# Currently we have no climbable objects in the test level
	return false

func interact():
	# Placeholder for interaction functionality
	# This would interact with objects in the game world
	print("Interacting with nearby object")

func apply_movement(delta):
	# Handle horizontal movement
	if direction != 0 and not is_sliding and not is_rolling and not is_crouching:
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
	
	# When crouching, ensure we don't move horizontally
	if is_crouching:
		velocity.x = 0

func jump():
	velocity.y = jump_velocity
	animated_sprite.play("jump")

func attack():
	# This method is kept for backward compatibility
	# But main attack logic is now in handle_combat()
	perform_combo_attack()

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
	if not is_on_floor():
		# For now, we always use jump animation when in air
		# We'll implement hanging and climbing animations later
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
