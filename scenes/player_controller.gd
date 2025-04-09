extends CharacterBody2D

# Player movement parameters
@export var move_speed = 200.0
@export var jump_velocity = -350.0
@export var acceleration = 20.0
@export var air_acceleration = 10.0
@export var friction = 30.0  # Increased from 10.0 to reduce sliding
@export var air_resistance = 10.0  # Increased from 5.0
@export var gravity_multiplier = 1.0
@export var roll_speed = 300.0
@export var roll_duration = 0.5
@export var slide_duration = 0.7
@export var dive_speed = 350.0  # Speed for dive attack
@export var attack_step_distance = 15.0  # Distance to step forward with each attack
@export var attack_speed_multiplier = 1.5  # Increase animation speed for attacks

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

# New state variables for air attacks
var is_dive_attacking = false
var air_combo = 0  # Track air combo for alternating air attacks

# Animation state tracking
var prev_y_velocity = 0
var just_landed = false
var land_timer = 0.0
var land_animation_time = 0.2  # Reduced from 0.3 for more responsive controls

# Combat variables
var current_combo = 0       # Current combo attack (0, 1, 2)
var combo_timer = 0.0       # Timer for combo window
var charge_timer = 0.0      # Timer for charge attack
var next_attack_queued = false # Whether player has queued up the next attack
var air_attacking = false    # Track if we're currently performing an air attack
var can_interrupt_attack = false  # Whether attack can be interrupted for jumping

# Get references to nodes
@onready var animated_sprite = $AnimatedSprite2D
@onready var collision_shape = $CollisionShape2D

func _ready():
	# Start with the idle animation
	animated_sprite.play("idle")

func _physics_process(delta):
	# Store velocity before anything for landing detection
	prev_y_velocity = velocity.y
	
	apply_gravity(delta)
	handle_input(delta)
	apply_movement(delta)
	
	move_and_slide()
	
	# Check for landing after move_and_slide
	check_landing()
	
	# Update animations after checking landing state
	update_animations(delta)
	
	# Safety check - don't stay in air attack state when on floor
	if is_on_floor() and air_attacking:
		air_attacking = false
		is_attacking = false
		# Only force animation change if we're showing air attack
		if "airattack" in animated_sprite.animation:
			animated_sprite.play("land")

func apply_gravity(delta):
	# Apply gravity when in the air and not climbing
	if not is_on_floor() and not is_climbing:
		if is_dive_attacking:
			# During dive attack, maintain the dive velocity
			# The velocity is already set in start_dive_attack
			pass
		else:
			velocity.y += gravity * gravity_multiplier * delta

func check_landing():
	# Check if we just landed from a jump or fall
	if is_on_floor() and prev_y_velocity > 150:  # If we were falling fast enough
		just_landed = true
		land_timer = land_animation_time
		
		# Reset double jump on landing - this is the only place where double jump should be reset
		can_double_jump = true
		has_double_jumped = false
		
		# Handle landing during a dive attack
		if is_dive_attacking:
			is_dive_attacking = false
			# Keep attacking state true during end animation
			animated_sprite.play("diveattackend")
			animated_sprite.speed_scale = attack_speed_multiplier
			
			# Wait for the diveattackend animation to finish, but don't block the process
			var animation_name = animated_sprite.animation
			animated_sprite.animation_finished.connect(func():
				if animated_sprite.animation == animation_name:
					is_attacking = false
					animated_sprite.speed_scale = 1.0
			, CONNECT_ONE_SHOT)
			return  # Skip the air attack landing check
			
		# Handle landing during an air attack
		if air_attacking:
			air_attacking = false
			is_attacking = false  # Immediately reset attacking state
			# Use the land animation instead of a custom end animation
			animated_sprite.play("land")
			animated_sprite.speed_scale = 1.0
		
		# Reset air combo when landing
		air_combo = 0

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
	
	# Always update direction input
	direction = Input.get_axis("moveleft", "moveright")
	
	# Update sprite direction even during attacks to allow changing direction mid-combo
	if direction < 0:
		animated_sprite.flip_h = true
	elif direction > 0:
		animated_sprite.flip_h = false
	
	# Handle jumping, allowing it to interrupt attacks after a brief window
	if Input.is_action_just_pressed("jump"):
		# If we're attacking but in the interruptible window and on the ground
		if is_attacking and can_interrupt_attack and is_on_floor():
			# Cancel attack and jump
			is_attacking = false
			air_attacking = false
			is_charging_attack = false
			animated_sprite.speed_scale = 1.0
			jump()
		# Jump down through platforms if pressing down + jump while on a one-way platform
		elif is_on_floor() and Input.is_action_pressed("movedown"):
			# Set collision layer to temporarily pass through one-way platforms
			position.y += 1  # Move down slightly to avoid getting stuck
		# Normal jump logic - removed "not just_landed" to fix sticky jumping
		elif is_on_floor() and not is_crouching:
			jump()
			can_double_jump = true
			has_double_jumped = false
		# Double jump only if we haven't used it already and not in the middle of an air attack
		elif can_double_jump and not has_double_jumped and not air_attacking:
			jump()
			has_double_jumped = true
	
	# Handle inputs while attacking or rolling
	if is_attacking or is_rolling:
		# Handle charging attack while in the charging state
		if is_charging_attack:
			charge_timer += delta
			
			# If player releases attack button during charge
			if Input.is_action_just_released("attack"):
				is_charging_attack = false
				is_attacking = false
				animated_sprite.speed_scale = 1.0
				
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
			
			# For air attacks, we need to immediately continue the combo if animation is done
			if air_attacking and animated_sprite.frame >= animated_sprite.sprite_frames.get_frame_count(animated_sprite.animation) - 1:
				next_attack_queued = false
				air_attacking = false
				is_attacking = false
				start_attack()
		
		# Still need to handle other inputs like sliding, rolling, etc.
		# but skip the rest of input processing for now
		return
	
	# If we have a queued attack and previous attack finished, execute it now
	if next_attack_queued:
		next_attack_queued = false
		start_attack() 
		return
	
	# Handle crouching - movedown key when on floor
	if is_on_floor() and Input.is_action_pressed("movedown"):
		is_crouching = true
		# Zero out velocity for crouching
		direction = 0
	elif is_on_floor():
		# Only stop crouching if we're on the floor
		# This prevents the player from getting stuck in crouching state when jumping
		is_crouching = false
	
	# Handle attack - only if not crouching (as requested)
	if not is_crouching:
		if Input.is_action_just_pressed("attack"):
			# If in air and pressing down, do dive attack
			if not is_on_floor() and Input.is_action_pressed("movedown"):
				start_dive_attack()
			else:
				# If player taps attack, start normal attack sequence
				start_attack()
		elif Input.is_action_pressed("attack") and not is_charging_attack and not is_attacking:
			# If player is holding attack, start charging
			start_attack_charge()
	
	# Handle sliding with custom slide mapping
	if Input.is_action_just_pressed("slide") and is_on_floor() and not is_sliding and not is_crouching and not just_landed:
		start_slide()
	
	# Handle rolling with custom roll mapping
	if Input.is_action_just_pressed("roll") and is_on_floor() and not is_rolling and not is_crouching and not just_landed:
		start_roll()
	
	# Climbing will be implemented later for ladders, vines, etc.
	is_climbing = is_near_climbable_object()
	
	# Handle interaction with custom interact mapping
	if Input.is_action_just_pressed("interact"):
		interact()

func start_attack(forced_combo = -1):
	is_attacking = true
	next_attack_queued = false
	can_interrupt_attack = false
	
	# Add a movement impulse based on current direction input
	if is_on_floor() and direction != 0:
		var facing_direction = -1 if animated_sprite.flip_h else 1
		# Only step if moving in same direction as facing
		if (facing_direction > 0 and direction > 0) or (facing_direction < 0 and direction < 0):
			# Apply a simple position offset
			position.x += facing_direction * attack_step_distance
	
	# Determine which attack in the combo to use
	var combo_index = forced_combo if forced_combo >= 0 else current_combo
	
	# Select the appropriate animation
	var attack_anim = ""
	if is_on_floor():
		match combo_index:
			0: attack_anim = "attack1"  # Upswing
			1: attack_anim = "attack2"  # Downswing
			2: attack_anim = "attack3"  # Thrust
	else:
		# Air attacks alternate between 1 and 2
		if air_combo == 0:
			attack_anim = "airattack1"
			air_combo = 1
		else:
			attack_anim = "airattack2"
			air_combo = 0
		
		air_attacking = true
	
	# Play the animation with increased speed
	animated_sprite.play(attack_anim)
	animated_sprite.speed_scale = attack_speed_multiplier
	
	# If this isn't a forced attack, advance the combo
	if forced_combo < 0 and is_on_floor():
		current_combo = (current_combo + 1) % 3  # Cycle through 0,1,2
		combo_timer = max_combo_delay  # Reset combo timer
	
	# Allow jumping after a brief delay (about halfway through the animation)
	var jump_interrupt_timer = get_tree().create_timer(0.15 / attack_speed_multiplier)
	jump_interrupt_timer.timeout.connect(func():
		if is_attacking:
			can_interrupt_attack = true
	)
	
	# Setup an air attack timer to auto-complete air attacks
	if air_attacking:
		# For air attacks, wait for animation to finish, then reset attack state
		# This ensures we can chain air attacks without getting stuck
		var animation_timer = get_tree().create_timer(0.3 / attack_speed_multiplier)  # Adjust for animation speed
		animation_timer.timeout.connect(func():
			if air_attacking and not is_on_floor():
				is_attacking = false
				air_attacking = false
				animated_sprite.speed_scale = 1.0
		)
	else:
		# For ground attacks, wait for full animation to finish
		await animated_sprite.animation_finished
		is_attacking = false
		animated_sprite.speed_scale = 1.0

func start_dive_attack():
	if is_dive_attacking or is_attacking:
		return
		
	is_dive_attacking = true
	is_attacking = true
	
	# Play the dive attack start animation with increased speed
	animated_sprite.play("diveattackstart")
	animated_sprite.speed_scale = attack_speed_multiplier
	
	# Override velocity for diving straight down
	velocity.x = 0
	velocity.y = dive_speed  # Use configurable dive speed

func start_attack_charge():
	is_attacking = true
	is_charging_attack = true
	charge_timer = 0.0
	
	# Play the charge animation
	animated_sprite.play("heavyattackcharge")
	# Don't increase speed for charging, it should feel like holding

func start_heavy_attack_release():
	is_attacking = true
	can_interrupt_attack = false
	
	# Add a movement impulse based on current direction input (same as normal attacks)
	if is_on_floor() and direction != 0:
		var facing_direction = -1 if animated_sprite.flip_h else 1
		# Only step if moving in same direction as facing
		if (facing_direction > 0 and direction > 0) or (facing_direction < 0 and direction < 0):
			# Apply a simple position offset, slightly more for heavy attack
			position.x += facing_direction * (attack_step_distance * 1.5)
	
	# Play the appropriate animation with increased speed
	if is_on_floor():
		animated_sprite.play("heavyattackrelease")
		animated_sprite.speed_scale = attack_speed_multiplier
	else:
		# For air heavy attacks, use the same air attack system
		animated_sprite.play("airattack1")
		animated_sprite.speed_scale = attack_speed_multiplier
		air_attacking = true
		return  # Don't await animation, handled by landing
	
	# Reset combo
	current_combo = 0
	
	# Allow jumping interrupt after a delay
	var jump_interrupt_timer = get_tree().create_timer(0.2 / attack_speed_multiplier)
	jump_interrupt_timer.timeout.connect(func():
		if is_attacking:
			can_interrupt_attack = true
	)
	
	# Wait for animation to finish
	await animated_sprite.animation_finished
	
	is_attacking = false
	animated_sprite.speed_scale = 1.0

func is_near_climbable_object():
	# This is a placeholder for future implementation
	# Will be used for ladders, vines, ropes, etc.
	# Currently we have no climbable objects in the test level
	return false

func interact():
	# Placeholder for interaction functionality
	# This would interact with objects in the game world
	print("Interacting with nearby object")

func apply_movement(_delta):
	# Handle horizontal movement
	
	# If attacking while on the ground, stop horizontal movement
	if is_attacking and is_on_floor():
		# Force velocity to zero to prevent sliding during attack animations
		velocity.x = 0
	elif direction != 0 and not is_sliding and not is_rolling and not is_crouching:
		# Determine appropriate acceleration based on whether on floor
		var current_acceleration = acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, direction * move_speed, current_acceleration)
	elif not is_sliding and not is_rolling:
		# Apply friction/air resistance to slow down
		var current_friction = friction if is_on_floor() else air_resistance
		# Apply stronger friction during landing
		if just_landed:
			velocity.x = move_toward(velocity.x, 0, friction * 2)
		else:
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
	
	# If we're jumping from an attack, make sure we can't chain with double jump
	if air_attacking or is_attacking:
		can_double_jump = false

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

func update_animations(_delta):
	# Don't change animation during an attack, roll or slide
	if is_attacking or is_rolling or is_sliding:
		return
	
	# If we're in the middle of an air attack, don't change animation
	if air_attacking or is_dive_attacking:
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
