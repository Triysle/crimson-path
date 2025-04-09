extends Node2D

class_name TrailEffect

@export var trail_length = 4  # Reduced from 5 to be more subtle
@export var trail_delay = 0.04  # Slightly increased for fewer images
@export var fade_time = 0.3  # How long each afterimage takes to fade out
@export var min_velocity = 20.0  # Lower threshold to show during small movements
@export var idle_alpha_multiplier = 0.4  # How visible the trail is during idle

# References
var sprite_to_trail = null
var parent_node = null

# Trail management
var trail_points = []
var trail_sprites = []
var timer = 0.0
var current_visibility = 0.0  # For smooth transitions
var target_visibility = 0.0

func _ready():
	parent_node = get_parent()
	sprite_to_trail = parent_node.get_node("AnimatedSprite2D")
	
	# Create trail sprites
	for i in range(trail_length):
		var new_sprite = AnimatedSprite2D.new()
		new_sprite.sprite_frames = sprite_to_trail.sprite_frames
		# More subtle coloring - closer to original with less tint
		new_sprite.modulate = Color(0.9, 0.85, 0.95, 0.0)  # Start invisible, will fade in
		add_child(new_sprite)
		new_sprite.z_index = -1  # Ensure trail appears behind player
		trail_sprites.append(new_sprite)
		trail_points.append({"pos": Vector2.ZERO, "flip": false, "anim": "", "frame": 0})

func _process(delta):
	# Calculate visibility target based on velocity
	var velocity_magnitude = parent_node.velocity.length()
	var is_idle = parent_node.animated_sprite.animation == "idle"
	
	# Determine target visibility - higher when moving, lower when idle
	if velocity_magnitude > min_velocity:
		target_visibility = min(velocity_magnitude / 200.0, 1.0)
	else:
		# Still show some trail during idle animation but more subtle
		target_visibility = idle_alpha_multiplier if is_idle else 0.0
	
	# Smoothly transition current visibility
	if current_visibility < target_visibility:
		current_visibility = min(current_visibility + delta * 4.0, target_visibility)
	else:
		current_visibility = max(current_visibility - delta * 4.0, target_visibility)
	
	# Only capture positions if there's some visibility
	timer += delta
	if timer >= trail_delay and current_visibility > 0.05:
		timer = 0
		
		# Shift trail data
		for i in range(trail_length - 1, 0, -1):
			trail_points[i] = trail_points[i-1].duplicate()
		
		# Add newest position
		trail_points[0] = {
			"pos": sprite_to_trail.global_position,
			"flip": sprite_to_trail.flip_h,
			"anim": sprite_to_trail.animation,
			"frame": sprite_to_trail.frame
		}
	
	# Update all trail sprites
	for i in range(trail_length):
		var sprite = trail_sprites[i]
		
		if i < trail_points.size():
			# Always update properties
			sprite.visible = true
			sprite.global_position = trail_points[i].pos
			sprite.flip_h = trail_points[i].flip
			sprite.animation = trail_points[i].anim
			sprite.frame = trail_points[i].frame
			
			# More rapid alpha falloff for subtlety
			var base_alpha = 0.5 - (0.5 * i / trail_length)
			
			# Apply idle animation specific adjustments
			if trail_points[i].anim == "idle":
				# Pulse slightly with the idle animation
				var frame_factor = float(trail_points[i].frame) / sprite_to_trail.sprite_frames.get_frame_count("idle")
				base_alpha *= 0.5 + (0.2 * sin(frame_factor * PI * 2))
			
			# Apply current visibility multiplier
			sprite.modulate.a = base_alpha * current_visibility
		else:
			sprite.visible = false
