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
@export var attack_charge_time = 0.7  # Time in seconds to charge heavy attack
@export var max_combo_delay = 0.6     # Maximum time between attacks to continue combo

# Track player state
var is_attacking = false
var is_charging_attack = false
var is_crouching = false
var is_sliding = false
var is_rolling = false
var is_climbing = false
var can_double_jump = false
var has_double_jumped = false
var direction = 0
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Animation state tracking
var prev_y_velocity = 0
var just_landed = false
var land_timer = 0.0
var land_animation_time = 0.3  # Time to play landing animation

# Combat variables
var current_combo = 0       # Current combo attack (0, 1, 2)
var combo_timer = 0.0       # Timer for combo window
var charge_timer = 0.0      # Timer for charge attack
var next_attack_queued = false # Whether player has queued up the next attack

# Get references to nodes
@onready var animated_sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D

func _ready():
	# Start with the idle animation
	animated_sprite.play("idle")

func _physics_process(delta):
	apply_gravity(delta)
	handle_input(delta)
	apply_movement(delta)
	
	# Store velocity before move_and_slide for landing detection
	prev_y_velocity = velocity.y
	
	move_and_slide()
	
	# Check for landing after move_and_slide
	check_landing()
	
	# Update animations after checking landing state
	update_animations(delta)

func apply_gravity(delta):
	# Apply gravity when in the air and not climbing
	if not is_on_floor() and not is_climbing:
		velocity.y += gravity * gravity_multiplier * delta

func check_landing():
	# Check if we just landed from a jump or fall
	if is_on_floor() and prev_y_velocity > 150:  # If we were falling fast enough
		just_landed = true
		land_timer = land_animation_time

func handle_input(delta):
	# Update combo timer
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			current_combo = 0  # Reset combo if time expired
	
	# Handle landing animation timer
	if land_timer > 0:
		land_timer -= delta
		if land_timer <= 0:
			just_landed = false
	
	# Handle inputs while attacking or rolling
	if is_attacking or is_rolling:
		# Handle charging attack while in the charging state
		if is_charging_attack:
			charge_timer += delta
			
			# If player releases attack button during charge
			if Input.is_action_just_released("attack"):
				is_charging_attack = false
				is_attacking = false
				
				if charge_timer >= attack_charge_time:
					# Fully charged - do heavy attack
					start_heavy_attack_release()
				else:
					# Not fully charged - do attack2
					start_attack(1)  # Force attack2
		
		# Allow queuing up the next attack during current attack animation
		# But only register one button press, ignore additional mashing
		elif Input.is_action_just_pressed("attack") and not next_attack_queued:
			next_attack_queued = true
		
		return
	
	# Don't process movement inputs during landing animation
	if just_landed:
		return
	
	# If we have a queued attack and previous attack finished, execute it now
	if next_attack_queued:
		next_attack_queued = false
		start_attack() 
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
	
	# Handle attack
	if Input.is_action_just_pressed("attack"):
		# If player taps attack, start normal attack sequence
		start_attack()
	elif Input.is_action_pressed("attack") and not is_charging_attack and not is_attacking:
		# If player is holding attack, start charging
		start_attack_charge()
	
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

func start_attack(forced_combo = -1):
	is_attacking = true
	next_attack_queued = false
	
	# Determine which attack in the combo to use
	var combo_index = forced_combo if forced_combo >= 0 else current_combo
	
	# Select the appropriate animation
	var attack_anim = ""
	if is_on_floor():
		if is_crouching:
			attack_anim = "crouchattack"
		else:
			match combo_index:
				0: attack_anim = "attack1"  # Upswing
				1: attack_anim = "attack2"  # Downswing
				2: attack_anim = "attack3"  # Thrust
	else:
		attack_anim = "airattack"
	
	# Play the animation
	animated_sprite.play(attack_anim)
	
	# If this isn't a forced attack, advance the combo
	if forced_combo < 0 and is_on_floor() and not is_crouching:
		current_combo = (current_combo + 1) % 3  # Cycle through 0,1,2
		combo_timer = max_combo_delay  # Reset combo timer
	
	# Wait for animation to finish before allowing next action
	await animated_sprite.animation_finished
	
	is_attacking = false

func start_attack_charge():
	is_attacking = true
	is_charging_attack = true
	charge_timer = 0.0
	
	# Play the charge animation
	animated_sprite.play("heavyattackcharge")

func start_heavy_attack_release():
	is_attacking = true
	
	# Play the appropriate animation
	if is_on_floor():
		if is_crouching:
			animated_sprite.play("crouchattack")  # Fallback for crouching
		else:
			animated_sprite.play("heavyattackrelease")
	else:
		animated_sprite.play("airattack")  # Fallback for air
	
	# Reset combo
	current_combo = 0
	
	# Wait for animation to finish
	await animated_sprite.animation_finished
	
	is_attacking = false

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
	
	# If attacking while on the ground, stop horizontal movement
	if is_attacking and is_on_floor():
		velocity.x = 0
	elif direction != 0 and not is_sliding and not is_rolling and not is_crouching and not just_landed:
		# Determine appropriate acceleration based on whether on floor
		var current_acceleration = acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, direction * move_speed, current_acceleration)
	elif not is_sliding and not is_rolling and not just_landed:
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
	
	# Reset just_landed flag when jumping
	just_landed = false

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

func update_animations(delta):
	# Don't change animation during an attack, roll or slide
	if is_attacking or is_rolling or is_sliding:
		return
	
	# Handle different states
	if not is_on_floor():
		# Air animations
		if velocity.y < 0:
			# Moving upward - jump animation
			animated_sprite.play("jump")
		else:
			# Moving downward - fall animation
			animated_sprite.play("fall")
	else:
		# Ground animations
		if just_landed:
			# Landing animation
			animated_sprite.play("land")
		elif is_crouching:
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
