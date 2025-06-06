extends Node3D

@onready var camera = get_node("Control/HBoxContainer/SubViewportContainer2/SubViewport/Camera")
@onready var screen_texture = get_node("Control/HBoxContainer/SubViewportContainer2/SubViewport/TextureRect")

var splatBegun: bool = false

# # temp debug
var splatNames = []
var splatNameIndex = 0
var transformationIndex = 0
var transformAxis = 0
var iterationsSinceRadix = 0
# # temp debug

var rd = RenderingServer.create_local_rendering_device()
var pipeline: RID
var shader: RID
var vertex_format: int
var blend := RDPipelineColorBlendState.new()

var framebuffer: RID
var vertex_array: RID
var index_array: RID
var static_uniform_set: RID
var dynamic_uniform_set: RID
var clear_color_values := PackedColorArray([Color(0,0,0,0)])

var num_coeffs = 45
var num_coeffs_per_color = num_coeffs / 3
var sh_degree = sqrt(num_coeffs_per_color + 1) - 1	

var sort_pipeline: RID
var histogram_pipeline: RID
var transform_pipeline: RID
var depth_in_buffer: RID
var depth_out_buffer: RID
var histogram_buffer: RID
var transform_buffer: RID
var depth_uniform
var depth_out_uniform
var histogram_uniform_set0
var histogram_uniform_set1
var transform_uniform
var radixsort_hist_shader: RID
var radixsort_shader: RID
var transform_shader: RID
var globalInvocationSize: int

var num_vertex: int
var output_tex: RID

var camera_matrices_buffer: RID
var params_buffer: RID
var transform_global_params_buffer: RID
var transform_params_buffer: RID
var modifier: float = 1.0
var last_direction := Vector3.ZERO

const NUM_BLOCKS_PER_WORKGROUP = 1024
var NUM_WORKGROUPS

func _matrix_to_bytes(t : Transform3D):
	var myBasis : Basis = t.basis
	var origin : Vector3 = t.origin
	var bytes : PackedByteArray = PackedFloat32Array([
		myBasis.x.x, myBasis.x.y, myBasis.x.z, 0.0,
		myBasis.y.x, myBasis.y.y, myBasis.y.z, 0.0,
		myBasis.z.x, myBasis.z.y, myBasis.z.z, 0.0,
		origin.x, origin.y, origin.z, 1.0
	]).to_byte_array()
	return bytes

func _initialise_screen_texture():
	var image_size = camera.get_viewport().size
	var image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBAF)
	var image_texture = ImageTexture.create_from_image(image)
	screen_texture.texture = image_texture

func _set_screen_texture_data(data: PackedByteArray):
	var image_size = camera.get_viewport().size
	var image := Image.create_from_data(image_size.x, image_size.y, false, Image.FORMAT_RGBAF, data)
	screen_texture.texture.update(image)

func _load_ply_file(filename: String):
	var file = FileAccess.open(filename, FileAccess.READ)

	if not file:
		print("Failed to open file: " + filename)
		return
	
	var plyFile = PlyFile.create(filename)
	# # temp debug
	splatNames.append(plyFile.name)
	# # temp debug

	var num_properties = 0
	var line = file.get_line()
	while not file.eof_reached():
		if line.begins_with("element vertex"):
			var line2 = int(line.split(" ")[2])
			num_vertex += line2
			plyFile.vertex_count = line2
		elif line.begins_with("property"):
			num_properties += 1
		elif line.begins_with("end_header"):
			break
		line = file.get_line()
	
	PlyFile.property_count = num_properties
	print("num splats: ", plyFile.vertex_count)
	print("num properties: ", num_properties)
	
	var data: PackedFloat32Array = file.get_buffer(plyFile.vertex_count * num_properties * 4).to_float32_array()
	plyFile.appendRawData(data)
	print("vertices size: " + str(data.size()))
	file.close()
	return plyFile

func _initialise_framebuffer_format():
	_initialise_screen_texture()
	var tex_format := RDTextureFormat.new()
	var tex_view := RDTextureView.new()
	tex_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tex_format.height = camera.get_viewport().size.y
	tex_format.width = camera.get_viewport().size.x
	tex_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tex_format.usage_bits = (RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT) 
	output_tex = rd.texture_create(tex_format,tex_view)

	var attachments = []
	var attachment_format := RDAttachmentFormat.new()
	attachment_format.set_format(tex_format.format)
	attachment_format.set_samples(RenderingDevice.TEXTURE_SAMPLES_1)
	attachment_format.usage_flags = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	attachments.push_back(attachment_format)	
	var framebuf_format = rd.framebuffer_format_create(attachments)
	return framebuf_format

# Previously called when the node enters the scene tree for the first time.
# Now manually called when opening a ply file
func _myReady(filename: String):
	if not camera.get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		camera.get_viewport().size_changed.connect(_on_viewport_size_changed)
	splatBegun = true

	print("unpacking .ply file data...")
	#var plyFile = _load_ply_file(filename)	
	_load_ply_file(filename)
	
	print("configuring shaders...")
	var depth_in_data = PackedInt32Array()
	for i in range(num_vertex):
		depth_in_data.append_array([0, i])
	depth_in_buffer = rd.storage_buffer_create(num_vertex * 2 * 4, depth_in_data.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	depth_uniform = shaderLib.createUniform(depth_in_buffer, 0)
	
	var params = shaderLib.setParams(camera, modifier, sh_degree)
	params_buffer = rd.storage_buffer_create(params.size(), params)
	var params_uniform = shaderLib.createUniform(params_buffer, 1)
	
	radixsort_shader = shaderLib.createShader("res://shaders/multi_radixsort.glsl", rd)
	radixsort_hist_shader = shaderLib.createShader("res://shaders/multi_radixsort_histograms.glsl", rd)
	transform_shader = shaderLib.createShader("res://shaders/compute_example.glsl", rd)
	
	globalInvocationSize = num_vertex / NUM_BLOCKS_PER_WORKGROUP
	var remainder = num_vertex % NUM_BLOCKS_PER_WORKGROUP
	if remainder > 0:
		globalInvocationSize += 1

	var WORKGROUP_SIZE = 512
	var RADIX_SORT_BINS = 256
	NUM_WORKGROUPS = num_vertex / WORKGROUP_SIZE

	var depth_out_data = PackedInt32Array()
	var hist_data = PackedInt32Array()
	
	depth_out_data.resize(num_vertex * 2)
	hist_data.resize(RADIX_SORT_BINS * NUM_WORKGROUPS)

	depth_out_buffer = rd.storage_buffer_create(depth_out_data.size() * 4, depth_out_data.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	histogram_buffer = rd.storage_buffer_create(hist_data.size() * 4, hist_data.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	transform_buffer = rd.storage_buffer_create(PlyFile.rawData.size() * 4, PlyFile.rawData.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	
	depth_out_uniform = shaderLib.createUniform(depth_out_buffer, 1)
	histogram_uniform_set0 = shaderLib.createUniform(histogram_buffer, 1)
	histogram_uniform_set1 = shaderLib.createUniform(histogram_buffer, 2)
	transform_uniform = shaderLib.createUniform(transform_buffer, 0)
	
	sort_pipeline = rd.compute_pipeline_create(radixsort_shader)
	histogram_pipeline = rd.compute_pipeline_create(radixsort_hist_shader)
	transform_pipeline = rd.compute_pipeline_create(transform_shader)

	# Configure splat vertex/frag shader
	shader = shaderLib.createShader("res://shaders/splat.glsl", rd)

	var points := PackedFloat32Array([
		-1,-1,0,
		1,-1,0,
		-1,1,0,
		1,1,0,
	])
	var points_bytes := points.to_byte_array()
	
	var indices := PackedByteArray()
	indices.resize(12)
	var pos = 0
	
	for i in [0,2,1,0,2,3]:
		indices.encode_u16(pos,i)
		pos += 2
		
	var index_buffer = rd.index_buffer_create(6,RenderingDevice.INDEX_BUFFER_FORMAT_UINT16,indices)
	index_array = rd.index_array_create(index_buffer,0,6)
	
	var vertex_buffers := [
		rd.vertex_buffer_create(points_bytes.size(), points_bytes),
	]
	
	var vertex_attrs = [ RDVertexAttribute.new()]
	vertex_attrs[0].format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	vertex_attrs[0].location = 0
	vertex_attrs[0].stride = 4 * 3
	vertex_format = rd.vertex_format_create(vertex_attrs)
	vertex_array = rd.vertex_array_create(4, vertex_format, vertex_buffers)
			
	# Camera Matrices Buffer
	var cam_to_world : Transform3D = camera.global_transform
	var camera_matrices_bytes := PackedByteArray()
	camera_matrices_bytes.append_array(_matrix_to_bytes(cam_to_world))
	camera_matrices_bytes.append_array(PackedFloat32Array([4000.0, 0.05]).to_byte_array())
	camera_matrices_buffer = rd.storage_buffer_create(camera_matrices_bytes.size(), camera_matrices_bytes)
	var camera_matrices_uniform = shaderLib.createUniform(camera_matrices_buffer, 3)
	
	# Configure blend mode
	var blend_attachment = RDPipelineColorBlendStateAttachment.new()	
	blend_attachment.enable_blend = true
	blend_attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	blend_attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	blend_attachment.color_blend_op = RenderingDevice.BLEND_OP_ADD
	blend_attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	blend_attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	blend_attachment.alpha_blend_op = RenderingDevice.BLEND_OP_ADD
	blend_attachment.write_r = true
	blend_attachment.write_g = true
	blend_attachment.write_b = true
	blend_attachment.write_a = true 
	blend.attachments.push_back(blend_attachment)	

	var framebuffer_format = _initialise_framebuffer_format()
	framebuffer = rd.framebuffer_create([output_tex], framebuffer_format)
	print("framebuffer valid: ",rd.framebuffer_is_valid(framebuffer))
	
	var static_bindings = [
		transform_uniform
	]
	var dynamic_bindings = [
		camera_matrices_uniform,
		params_uniform,
		depth_uniform,
	]
	
	dynamic_uniform_set = rd.uniform_set_create(dynamic_bindings, shader, 0)
	static_uniform_set = rd.uniform_set_create(static_bindings, shader, 1)
	
	pipeline = rd.render_pipeline_create(
		shader,
		framebuffer_format,
		vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLE_STRIPS,
		RDPipelineRasterizationState.new(),
		RDPipelineMultisampleState.new(),
		RDPipelineDepthStencilState.new(),
		blend
	)
	
	print("render pipeline valid: ", rd.render_pipeline_is_valid(pipeline))
	print("compute1 pipeline valid: ", rd.compute_pipeline_is_valid(sort_pipeline))
	
	# Do once to ensure splat drawn in correct order at start
	update()
	render()
	radix_sort()

# Reconfigure render pipeline with new viewport size
func _on_viewport_size_changed():
	var framebuf_format = _initialise_framebuffer_format()
	framebuffer = rd.framebuffer_create([output_tex], framebuf_format)
	
	pipeline = rd.render_pipeline_create(
		shader,
		framebuf_format,
		vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLE_STRIPS,
		RDPipelineRasterizationState.new(),
		RDPipelineMultisampleState.new(),
		RDPipelineDepthStencilState.new(),
		blend
	)

func radix_sort():
	var compute_list := rd.compute_list_begin()
	for i in range(4):
		var push_constant = PackedInt32Array([num_vertex, i * 8, NUM_WORKGROUPS, NUM_BLOCKS_PER_WORKGROUP])
		depth_uniform.clear_ids()
		depth_out_uniform.clear_ids()
		
		if i == 0 or i == 2:
			depth_uniform.add_id(depth_in_buffer)
			depth_out_uniform.add_id(depth_out_buffer)
		else:
			depth_uniform.add_id(depth_out_buffer)
			depth_out_uniform.add_id(depth_in_buffer)
			
		var histogram_bindings = [
			depth_uniform,
			histogram_uniform_set0
		]
		var hist_uniform_set = rd.uniform_set_create(histogram_bindings, radixsort_hist_shader, 0)
		rd.compute_list_bind_compute_pipeline(compute_list, histogram_pipeline)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
		rd.compute_list_bind_uniform_set(compute_list, hist_uniform_set, 0)
		rd.compute_list_dispatch(compute_list, globalInvocationSize, 1, 1)
		rd.compute_list_add_barrier(compute_list)
		
		var radixsort_bindings = [
			depth_uniform,
			depth_out_uniform,
			histogram_uniform_set1
		]
		var sort_uniform_set = rd.uniform_set_create(radixsort_bindings, radixsort_shader, 1)
		
		rd.compute_list_bind_compute_pipeline(compute_list, sort_pipeline)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
		rd.compute_list_bind_uniform_set(compute_list, sort_uniform_set, 1)
		rd.compute_list_dispatch(compute_list, globalInvocationSize, 1, 1)
		rd.compute_list_add_barrier(compute_list)
	
	rd.compute_list_end()
	rd.submit()
	rd.sync()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func update():	
	if not splatBegun:
		return
	
	# Camera Matrices Buffer
	var camera_matrices_bytes := PackedByteArray()
	var cgt: Transform3D = camera.global_transform
	cgt.basis.x *= -1
	cgt.basis.y *= -1
	cgt = cgt.rotated(Vector3.RIGHT, PI).affine_inverse()
	camera_matrices_bytes.append_array(_matrix_to_bytes(cgt))
	camera_matrices_bytes.append_array(PackedFloat32Array([4000.0, 0.05]).to_byte_array())
	rd.buffer_update(camera_matrices_buffer, 0, camera_matrices_bytes.size(), camera_matrices_bytes)
	
	var params = shaderLib.setParams(camera, modifier, sh_degree)
	rd.buffer_update(params_buffer, 0, params.size(), params)

	_sort_splats_by_depth()

func render():
	var draw_list := rd.draw_list_begin(framebuffer, RenderingDevice.INITIAL_ACTION_CLEAR, RenderingDevice.FINAL_ACTION_READ, RenderingDevice.INITIAL_ACTION_CLEAR, RenderingDevice.FINAL_ACTION_READ, clear_color_values)
	rd.draw_list_bind_render_pipeline(draw_list, pipeline)
	rd.draw_list_bind_uniform_set(draw_list, dynamic_uniform_set, 0)
	rd.draw_list_bind_uniform_set(draw_list, static_uniform_set, 1)
	rd.draw_list_bind_vertex_array(draw_list, vertex_array)
	rd.draw_list_draw(draw_list, false, num_vertex)
	rd.draw_list_end()
	
	var byte_data := rd.texture_get_data(output_tex,0)
	_set_screen_texture_data(byte_data)

func _process(_delta):	
	if splatBegun:
		if(Input.is_action_just_pressed("debug1")):
			splatNameIndex = (splatNameIndex + 1) % splatNames.size()
			print("Selected " + splatNames[splatNameIndex])
		if(Input.is_action_just_pressed("debug2")):
			transformationIndex = (transformationIndex + 1) % 3
			if(transformationIndex == 0):
				print("Set to TRANSLATE")
			elif(transformationIndex == 1):
				print("Set to ROTATE")
			else:
				print("Set to SCALE")
		if(Input.is_action_just_pressed("debug3")):
			transformAxis = (transformAxis + 1) % 3
			match transformAxis:
				0:
					print("Set to x")
				1:
					print("Set to y")
				2:
					print("Set to z")
		if(Input.is_action_pressed("debug4")):
			match transformationIndex:
				0:
					transformTranslate(splatNames[splatNameIndex], transformAxis, 0.01)
				1:
					transformRotate(splatNames[splatNameIndex], transformAxis, 0.005)
				2:
					transformScale(splatNames[splatNameIndex], 1.02)
		if(Input.is_action_pressed("debug5")):
			match transformationIndex:
				0:
					transformTranslate(splatNames[splatNameIndex], transformAxis, -0.01)
				1:
					transformRotate(splatNames[splatNameIndex], transformAxis, -0.005)
				2:
					transformScale(splatNames[splatNameIndex], 1/1.02)
		update()
		render()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			modifier += 0.05
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			modifier = clampf(modifier - 0.05, 0, 2147483647)

func _sort_splats_by_depth():
	var direction = camera.global_transform.basis.z.normalized()
	var cos_angle = last_direction.dot(direction)
	var angle = acos(clamp(cos_angle, -1, 1))
	
	# Only re-sort if camera has changed enough
	if angle > 0.2:
		radix_sort()
		last_direction = direction

func transformTranslate(file: String, direction: int, dist: float):
	var byteStream = StreamPeerBuffer.new()
	byteStream.put_32(direction)
	byteStream.put_float(dist)
	byteStream.put_float(0)
	byteStream.put_float(0)
	var ply: PlyFile = PlyFile.allFiles.get(file)
	ply.center[direction] += dist
	transformSplat(byteStream.data_array, ply, 2)

func transformRotate(file: String, axis: int, angle: float):
	var byteStream = StreamPeerBuffer.new()
	byteStream.put_32(0)
	for i in range(axis):
		byteStream.put_float(0)
	byteStream.put_float(angle)
	for i in range(2 - axis):
		byteStream.put_float(0)
	transformSplat(byteStream.data_array, PlyFile.allFiles.get(file), 3)

func transformScale(file: String, amount: float):
	var byteStream = StreamPeerBuffer.new()
	byteStream.put_32(0)
	var newThing = log(amount)/log(2.7182818284590459)
	byteStream.put_float(amount)
	#ln(x) = log(x) / log(e)
	byteStream.put_float(newThing)
	byteStream.put_float(0)
	transformSplat(byteStream.data_array, PlyFile.allFiles.get(file), 4)

func transformSplat(params: PackedByteArray, plyFile: PlyFile, transformation: int):
	var globalStream = StreamPeerBuffer.new()
	globalStream.put_32(transformation)
	globalStream.put_32(plyFile.offset)
	globalStream.put_32(plyFile.vertex_count)
	globalStream.put_32(PlyFile.property_count)
	globalStream.put_32(plyFile.center.x)
	globalStream.put_32(plyFile.center.y)
	globalStream.put_32(plyFile.center.z)
	var globalParams: PackedByteArray = globalStream.data_array
	transform_global_params_buffer = rd.storage_buffer_create(globalParams.size(), globalParams)
	var globalParams_uniform = shaderLib.createUniform(transform_global_params_buffer, 1)
	
	transform_params_buffer = rd.storage_buffer_create(params.size(), params)
	var params_uniform = shaderLib.createUniform(transform_params_buffer, 2)
	
	var transform_bindings = [
		transform_uniform,
		globalParams_uniform,
		params_uniform
	]
	var transform_uniform_set = rd.uniform_set_create(transform_bindings, transform_shader, 0)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, transform_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, transform_uniform_set, 0)
	var shaderSizeX = 128
	var transformInvocations: int = (num_vertex + shaderSizeX - 1) / shaderSizeX
	rd.compute_list_dispatch(compute_list, transformInvocations, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	iterationsSinceRadix += 1
	if(iterationsSinceRadix >= 10):
		radix_sort()
		iterationsSinceRadix = 0

# # testing
func printBuffer(buffer: RID, text: String, start: int, length: int):
	var temp = rd.buffer_get_data(buffer, PlyFile.property_count * 4 * start, length * 4).to_float32_array()
	for j in range(temp.size()):
		temp[j] = round(temp[j]*1000)
	print(text + str(start) + ": \t" + str(temp))

class PlyFile:
	var name: String
	var vertex_count: int
	var offset: int
	var center: Vector3
	
	static var property_count: int
	static var allFiles: Dictionary
	static var rawData: PackedFloat32Array
	
	static func create(filepath: String):
		var splitPath = filepath.split("/")
		if splitPath.size() == 1:
			splitPath = filepath.split("\\")
		var splitName = splitPath[splitPath.size()-1]
		var plyFile = PlyFile.new()
		plyFile.name = splitName
		allFiles[splitName] = plyFile
		plyFile.center = Vector3.ZERO
		return plyFile
	
	func appendRawData(data: PackedFloat32Array):
		offset = rawData.size()
		rawData.append_array(data)

class shaderLib:
	static func createUniform(buffer: RID, binding: int):
		var uni = RDUniform.new()
		uni.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uni.binding = binding
		uni.add_id(buffer)
		return uni
	
	static func createShader(filename: String, rd: RenderingDevice):
		var file = load(filename)
		var spirv = file.get_spirv()
		return rd.shader_create_from_spirv(spirv)
	
	static func setParams(camera: Node, modifier: float, sh_degree: float):
		var tan_fovy = tan(deg_to_rad(camera.fov) * 0.5)
		var tan_fovx = tan_fovy * camera.get_viewport().size.x / camera.get_viewport().size.y
		var focal_y = camera.get_viewport().size.y / (2 * tan_fovy)
		var focal_x = camera.get_viewport().size.x / (2 * tan_fovx)
		var params: PackedByteArray = PackedFloat32Array([
			camera.get_viewport().size.x,
			camera.get_viewport().size.y,
			tan_fovx,
			tan_fovy,
			focal_x,
			focal_y,
			modifier,
			sh_degree,
		]).to_byte_array()
		return params
