extends RigidBody3D

class_name RigidbodyGizmo

#FOR LATER USE START
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
#FOR LATER USE END

var visual_node: MeshInstance3D
var collider : CollisionShape3D

#Init transform dictionaries, NOT USED
func _node_init():
	if visual_node and visual_node.get_surface_override_material(0):
		original["position"] = position
		original["scale"] = visual_node.mesh._get_aabb().size
		original["rotation"] = rotation
		current = original

#Adjusts fun rigidbody variables
func _ready():
	gravity_scale = 0
	angular_damp = 1
	linear_damp = 1

					
#Scales everything uniformly
func uniform_scale_update(scale : Vector3):
	if(scale.length()<.03):
		scale = Vector3(0.03,0.03,0.03)
	visual_node.scale = scale
	self.scale = scale
	
func lock_in_scale(scale : Vector3):
	current["scale"] = scale
