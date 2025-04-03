extends Camera3D

@export var mouse_sensitivity : float = 0.25
@export var move_speed : float = 1.0
@export var roll_speed : float = 40.0
@export var gizmo : Gizmo3D
@export var message : Label

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		gizmo.set_process_unhandled_input(!event.pressed)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var pitch = clamp(event.relative.y * mouse_sensitivity, -90, 90)
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		if transform.rotated_local(Vector3.RIGHT, deg_to_rad(-pitch)).basis.get_euler().z == 0:
			rotate_object_local(Vector3.RIGHT, deg_to_rad(-pitch))

func _process(_delta: float) -> void:
	var input_vector := Vector3.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
	input_vector.z = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	#var input := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	var move := (basis * input_vector).normalized()
	position += move * move_speed * _delta
	if Input.is_action_pressed("roll_cw"):
		rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(-roll_speed * _delta))
	if Input.is_action_pressed("roll_ccw"):
		rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(roll_speed * _delta))

	message.visible = gizmo.editing
	if !gizmo.editing:
		return
	message.position = get_viewport().get_mouse_position() + Vector2(16, 16)
	message.text = gizmo.message
