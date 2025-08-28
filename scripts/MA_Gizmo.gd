@tool
extends Node3D


class_name  MA_Gizmo
var target_node: RigidbodyGizmo = null # The object the gizmo will control
var is_dragging = false
var camera;
var is_scaling = false
var is_rotating = false
var is_foward_axis = false
@export var rotate_speed = 1.0
@export var scale_factor = 1.0
@export var attraction_strength = 2.0
@export var screen_stop_distance = .5

var rbGizCurrent: Dictionary;
var starting_scale
var scalePercentage

var initial_mouse_pos: Vector2
var last_mouse_pos : Vector2
var no_input = false
static var target_objects : Array[RigidbodyGizmo] = []
func _ready():
	camera = get_viewport().get_camera_3d()
	visible = false

#If you are not moving the object, but your mouse is still, move towards mouse
func _process(delta):
	if target_node and no_input and is_dragging:
		_calcMovementDir()

#move towards last mouse position
func _calcMovementDir():
	var drag_delta = last_mouse_pos - camera.unproject_position(target_node.position)
	var distance = drag_delta.length()
	if distance > screen_stop_distance:
		var movement_direction = (camera.transform.basis.x * drag_delta.x) + (camera.transform.basis.y * -drag_delta.y)
		movement_direction = movement_direction.normalized()
		var force_strength = (distance - screen_stop_distance) * attraction_strength
		target_node.apply_central_force(movement_direction * force_strength)

func _input(event):
	no_input = false
	if event is InputEventKey:
		if(event.keycode==KEY_CTRL):#Rotating On
			if(event.pressed):
				is_rotating = true
			elif(event.is_released()):#Rotating Off
				is_rotating = false
		if(event.keycode==KEY_ALT):
			if(event.pressed):#Move foward On
				is_foward_axis = true
			elif(event.is_released()):#Move foward Off
				is_foward_axis = false
		if(event.keycode==KEY_SHIFT):
			if(event.pressed):#Scale On
				is_scaling = true
			elif(event.is_released()):#Scale Off
				is_scaling = false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed(): #Find what is selected on mouse down
				var camera = get_viewport().get_camera_3d()
				var from = camera.project_ray_origin(event.position)
				var to = from + camera.project_ray_normal(event.position) * 1000000
				
				var space_state = get_world_3d().direct_space_state
				var ray_query = PhysicsRayQueryParameters3D.create(from, to)
				var result = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
				if result:#assign selected target_node
					if(target_node and result.collider!=target_node): 
						reset_target(target_node)
					target_node = result.collider
					target_node.set_collision_layer_value(2, true)
					target_node.set_collision_layer_value(3, false)
					target_node.set_collision_mask_value(3, false)
					rbGizCurrent = target_node.current
					starting_scale = target_node.scale
					is_dragging = true
					initial_mouse_pos = event.position
					last_mouse_pos = event.position
			else:
				is_dragging = false

	if event is InputEventMouseMotion and is_dragging:#If moving object by camera viewport
		var drag_delta = event.position - last_mouse_pos
		last_mouse_pos = event.position
		if is_rotating:#If Rotating
			var movement_direction = (camera.transform.basis.x * drag_delta.y) + (camera.transform.basis.y * -drag_delta.x)
			if movement_direction.length() > 0 :
				movement_direction = movement_direction.normalized()
			target_node.apply_torque_impulse(movement_direction * rotate_speed)
		elif is_scaling:#If Scaling
			var scaleLength = event.position.length() - initial_mouse_pos.length()
			if(scaleLength<0):
				scaleLength = -1/scaleLength
			scalePercentage = round((target_node.scale/starting_scale)*scaleLength*100)/100
			target_node.uniform_scale_update(scalePercentage)
		else:#If Moving
			var distance = (event.position - camera.unproject_position(target_node.position)).length()
			if distance > screen_stop_distance:
				var movement_direction;
				if(is_foward_axis):#If Moving forward
					movement_direction = (camera.transform.basis.x * drag_delta.x) + (-camera.transform.basis.z * -drag_delta.y)
				else:#If Moving regular
					movement_direction = (camera.transform.basis.x * drag_delta.x) + (camera.transform.basis.y * -drag_delta.y)
				movement_direction = movement_direction.normalized()
				var force_strength = (distance - screen_stop_distance) * attraction_strength
				target_node.apply_central_force(movement_direction * force_strength)
	no_input = true

func _physics_process(delta):
	# Only apply force if we are currently dragging.
	if is_dragging and not (is_rotating or is_scaling):
		target_node.angular_velocity = Vector3.ZERO
		
		var object_screen_pos = camera.unproject_position(global_transform.origin)
		var drag_delta = last_mouse_pos - object_screen_pos
		var distance = drag_delta.length()
		if distance > screen_stop_distance:
			var camera_transform = camera.global_transform
			var camera_right = camera_transform.basis.x
			var camera_up = camera_transform.basis.y
			var movement_direction = (camera_right * drag_delta.x) + (camera_up * -drag_delta.y)
			if movement_direction.length() > 0:
				movement_direction = movement_direction.normalized()
				
			target_node.apply_central_force(movement_direction * attraction_strength*delta)
	elif is_dragging and is_scaling:#If scaling, we don't want it moving or rotating
		target_node.linear_velocity = Vector3.ZERO
		target_node.angular_velocity = Vector3.ZERO
	elif is_dragging and is_rotating:#If rotating, we don't want it moving
		target_node.linear_velocity = Vector3.ZERO


#Unselect object
func reset_target(target : RigidbodyGizmo):
	target.set_collision_layer_value(2, false)
	target.set_collision_layer_value(3, true)
	target.set_collision_mask_value(3, true)
