extends RigidBody3D

class_name RigidbodyGizmo

@export var selection_color: Color = Color.BLUE
@export var default_color: Color = Color.DARK_GRAY

var original : Dictionary = {
	"position" : Vector3.ZERO,
	"rotation" : Quaternion.IDENTITY,
	"scale" : Vector3.ONE
}

var current : Dictionary = {
	"position" : Vector3.ZERO,
	"rotation" : Quaternion.IDENTITY,
	"scale" : Vector3.ONE
}

# A reference to the visual node we'll change the color of.
# This should be a MeshInstance3D with a StandardMaterial3D.
var visual_node: MeshInstance3D
var collider : CollisionShape3D

var is_selected: bool = false
var original_material: StandardMaterial3D = null

func _node_init():
	if visual_node and visual_node.get_surface_override_material(0):
		# Create a local material to prevent changing the original resource.
		var material = visual_node.get_surface_override_material(0)
		original_material = material.duplicate() as StandardMaterial3D
		visual_node.set_surface_override_material(0, original_material)
		original_material.albedo_color = default_color
		original["position"] = position
		original["scale"] = visual_node.mesh._get_aabb().size
		original["rotation"] = rotation
		current = original

# This function is called when the scene is ready.
func _ready():
	gravity_scale = 0
	angular_damp = 1
	linear_damp = 1
	# Make sure the visual node and its material exist before proceeding.
	
	# Connect the RigidBody3D's 'input_event' signal to our custom function.
	# This signal is emitted when an input event happens on the body.
	connect("input_event", _on_input_event)

# This function handles the input events.
# 'camera' is the camera used to generate the ray.
# 'event' is the InputEvent object (e.g., mouse click).
# 'position' is the intersection point on the surface.
# 'normal' is the normal vector of the surface at the intersection point.
# 'shape_idx' is the index of the shape that was clicked.
func _on_input_event(camera, event, position, normal, shape_idx):
	# We check if the event is a mouse button press.
	if event is InputEventMouseButton:
		# We check if the left mouse button was pressed down.
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Toggle the selection state.
			is_selected = !is_selected
			
			# Ensure we have a material to modify.
			if original_material:
				if is_selected:
					# Change the material's albedo color to the selection color.
					original_material.albedo_color = selection_color
					print("3D object selected!")
				else:
					# Change the material's albedo color back to the default color.
					original_material.albedo_color = default_color
					print("3D object deselected.")
					
func uniform_scale_update(scale : Vector3):
	if(scale.length()<.03):
		scale = Vector3(0.03,0.03,0.03)
	visual_node.scale = scale
	self.scale = scale
	
func lock_in_scale(scale : Vector3):
	current["scale"] = scale
