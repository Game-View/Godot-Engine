# Copyright (c) 2024 Anthony J. Thibault
# This software is licensed under the MIT License. See LICENSE for more details.

class_name SplatRenderer
extends Node

# Rendering device for low-level rendering
var rd: RenderingDevice
# Shader and pipeline
var shader: RID
var pipeline: RID
# Vertex and index buffers
var vertex_format: int
var vertex_array: RID
var index_array: RID
# Uniform sets
var static_uniform_set: RID
var dynamic_uniform_set: RID
# Framebuffer
var framebuffer: RID
# Buffers for Gaussian data
var gaussian_data_buffer: RID
var index_buffer: RID
var key_buffer: RID
var val_buffer: RID
var pos_buffer: RID
var atomic_counter_buffer: RID
# Camera and projection data
var camera: Camera3D
var viewport: Vector4
var near_far: Vector2
# Flags
var is_framebuffer_srgb_enabled: bool = false
var use_rgc_sort_override: bool = false
var sort_count: int = 0
# Constants
const NUM_BLOCKS_PER_WORKGROUP: int = 1024
const LOCAL_SIZE: int = 256

# Gaussian data (simulating GaussianCloud)
var gaussian_data: PackedByteArray
var num_gaussians: int = 0
var pos_vec: Array[Vector4]
var depth_vec: Array[float]
var index_vec: Array[int]
var atomic_counter_vec: Array[int] = [0]

func _init():
	# Initializes the RenderingDevice for local rendering operations.
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("Failed to create RenderingDevice")
		return

func _ready():
	# Placeholder for any scene-ready initialization if needed.
	pass

func init_splat_renderer(gaussian_cloud_data: Dictionary, is_srgb: bool, use_rgc_sort: bool) -> bool:
	# Initializes the SplatRenderer with Gaussian data, setting flags and compiling the shader.
	# Loads and compiles the custom shader with conditional defines.
	# Sets up buffers, vertex formats, and the render pipeline.
	# Returns true if initialization succeeds, false otherwise.
	is_framebuffer_srgb_enabled = is_srgb
	use_rgc_sort_override = use_rgc_sort
	
	# Load shader
	var shader_code: String = _load_shader_code()
	var shader_spirv: RDShaderSPIRV = RDShaderFile.new().compile_source(shader_code, "splat_shader")
	if shader_spirv.get_stage_bytecode(RenderingDevice.SHADER_STAGE_VERTEX).is_empty():
		push_error("Failed to compile shader")
		return false
	shader = rd.shader_create_from_spirv(shader_spirv)
	
	# Initialize Gaussian data (simulating GaussianCloud)
	_setup_gaussian_data(gaussian_cloud_data)
	
	# Build buffers and vertex array
	_build_vertex_array_object()
	
	# Setup sorting buffers
	_setup_sorting_buffers()
	
	# Setup framebuffer (assuming output texture is provided externally)
	# Note: Framebuffer setup requires an output texture, which should be passed or created
	# For simplicity, assume it's set externally or use a default texture
	var output_tex: RID = _create_default_output_texture()
	var framebuffer_format: int = _initialize_framebuffer_format()
	framebuffer = rd.framebuffer_create([output_tex], framebuffer_format)
	if not rd.framebuffer_is_valid(framebuffer):
		push_error("Framebuffer is invalid")
		return false
	
	# Setup render pipeline
	_setup_render_pipeline()
	
	return true

func _load_shader_code() -> String:
	# Loads and formats the shader code with conditional defines based on flags.
	# The shader code is assumed to be loaded from a file; in practice, replace with actual file loading.
	var shader_code: String = """
	shader_type spatial;
	// Add defines based on flags
	%s
	// Insert the vertex shader code here
	%s
	"""
	var defines: String = ""
	if is_framebuffer_srgb_enabled:
		defines += "#define OUTPUT_IS_SRGB\n"
	if gaussian_data.size() > 0: # Assuming full SH if data includes SH coefficients
		defines += "#define FULL_SH\n"
	# Load the shader code from the previous artifact (simplified, assuming it's accessible)
	# In a real scenario, you'd load from a file or store it
	var vertex_shader: String = FileAccess.get_file_as_string("res://shaders/splat_vertex.gdshader")
	return shader_code % [defines, vertex_shader]

func _setup_gaussian_data(gaussian_cloud_data: Dictionary) -> void:
	# Prepares Gaussian data by extracting from the input dictionary and interleaving into a byte array.
	# Simulates the GaussianCloud class from the original C++ by using a Dictionary for data storage.
	# Expected format: { "positions": PackedVector4Array, "r_sh0": PackedVector4Array, ..., "cov3_col0": PackedVector3Array, ... }
	num_gaussians = gaussian_cloud_data["positions"].size()
	
	# Build pos_vec
	pos_vec.clear()
	for pos in gaussian_cloud_data["positions"]:
		pos_vec.append(pos)
	
	# Build interleaved vertex data
	gaussian_data = PackedByteArray()
	var stride: int = 4 * 4 + 4 * 4 * 3 + 3 * 4 * 3 # position (vec4) + SH (3 * vec4) + cov (3 * vec3)
	for i in range(num_gaussians):
		gaussian_data.append_array(gaussian_cloud_data["positions"][i].to_byte_array())
		gaussian_data.append_array(gaussian_cloud_data["r_sh0"][i].to_byte_array())
		gaussian_data.append_array(gaussian_cloud_data["g_sh0"][i].to_byte_array())
		gaussian_data.append_array(gaussian_cloud_data["b_sh0"][i].to_byte_array())
		if gaussian_cloud_data.has("r_sh1"):
			gaussian_data.append_array(gaussian_cloud_data["r_sh1"][i].to_byte_array())
			gaussian_data.append_array(gaussian_cloud_data["r_sh2"][i].to_byte_array())
			gaussian_data.append_array(gaussian_cloud_data["r_sh3"][i].to_byte_array())
			gaussian_data.append_array(gaussian_cloud_data["g_sh1"][i].to_byte_array())
			gaussian_data.append_array(gaussian_cloud_data["g_sh2"][i].to_byte_array())
			gaussian_data.append_array(gaussian_cloud_data["g_sh3"][i].to_byte_array())
			gaussian_data.append_array(gaussian_cloud_data["b_sh1"][i].to_byte_array())
			gaussian_data.append_array(gaussian_cloud_data["b_sh2"][i].to_byte_array())
			gaussian_data.append_array(gaussian_cloud_data["b_sh3"][i].to_byte_array())
		gaussian_data.append_array(gaussian_cloud_data["cov3_col0"][i].to_byte_array())
		gaussian_data.append_array(gaussian_cloud_data["cov3_col1"][i].to_byte_array())
		gaussian_data.append_array(gaussian_cloud_data["cov3_col2"][i].to_byte_array())
	
	# Build index_vec
	index_vec.clear()
	for i in range(num_gaussians):
		index_vec.append(i)

func _build_vertex_array_object() -> void:
	# Creates the vertex buffer and defines attributes to match the shader inputs.
	# Replaces the VertexArrayObject and BufferObject from the original C++.
	# Create vertex buffer
	gaussian_data_buffer = rd.vertex_buffer_create(gaussian_data.size(), gaussian_data)
	
	# Define vertex attributes
	var vertex_attrs: Array[RDVertexAttribute] = []
	var stride: int = 4 * 4 + 4 * 4 * 3 + 3 * 4 * 3 # position (vec4) + SH (3 * vec4) + cov (3 * vec3)
	var offset: int = 0
	
	# Position (vec4)
	var attr_pos: RDVertexAttribute = RDVertexAttribute.new()
	attr_pos.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	attr_pos.location = 0
	attr_pos.stride = stride
	attr_pos.offset = offset
	vertex_attrs.append(attr_pos)
	offset += 4 * 4
	
	# r_sh0, g_sh0, b_sh0 (vec4 each)
	for i in range(3):
		var attr_sh: RDVertexAttribute = RDVertexAttribute.new()
		attr_sh.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		attr_sh.location = 1 + i
		attr_sh.stride = stride
		attr_sh.offset = offset
		vertex_attrs.append(attr_sh)
		offset += 4 * 4
	
	# Full SH coefficients (if present)
	if gaussian_data.size() > 0: # Assuming full SH if data includes SH coefficients
		for i in range(3): # r_sh1, r_sh2, r_sh3
			for j in range(3): # r, g, b
				var attr_sh: RDVertexAttribute = RDVertexAttribute.new()
				attr_sh.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
				attr_sh.location = 4 + i * 3 + j
				attr_sh.stride = stride
				attr_sh.offset = offset
				vertex_attrs.append(attr_sh)
				offset += 4 * 4
	
	# Covariance (3 * vec3)
	for i in range(3):
		var attr_cov: RDVertexAttribute = RDVertexAttribute.new()
		attr_cov.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
		attr_cov.location = 13 + i
		attr_cov.stride = stride
		attr_cov.offset = offset
		vertex_attrs.append(attr_cov)
		offset += 4 * 3
	
	vertex_format = rd.vertex_format_create(vertex_attrs)
	
	# Create index buffer
	var indices_bytes: PackedByteArray = PackedByteArray()
	indices_bytes.resize(num_gaussians * 4)
	var pos: int = 0
	for i in index_vec:
		indices_bytes.encode_u32(pos, i)
		pos += 4
	index_buffer = rd.index_buffer_create(num_gaussians, RenderingDevice.INDEX_BUFFER_FORMAT_UINT32, indices_bytes)
	
	# Create vertex and index arrays
	var vertex_buffers: Array[RID] = [gaussian_data_buffer]
	vertex_array = rd.vertex_array_create(num_gaussians, vertex_format, vertex_buffers)
	index_array = rd.index_array_create(index_buffer, 0, num_gaussians)

func _setup_sorting_buffers() -> void:
	# Sets up buffers for sorting keys, values, and positions.
	# In the original C++, this includes additional buffers for multi-radix sort (keyBuffer2, valBuffer2, histogramBuffer) which are missing here due to CPU fallback.
	# Initialize depth and index buffers
	depth_vec.resize(num_gaussians)
	var depth_bytes: PackedByteArray = PackedByteArray()
	depth_bytes.resize(num_gaussians * 4)
	key_buffer = rd.storage_buffer_create(depth_bytes.size(), depth_bytes)
	
	var index_bytes: PackedByteArray = PackedByteArray()
	index_bytes.resize(num_gaussians * 4)
	for i in range(num_gaussians):
		index_bytes.encode_u32(i * 4, index_vec[i])
	val_buffer = rd.storage_buffer_create(index_bytes.size(), index_bytes)
	
	var pos_bytes: PackedByteArray = PackedByteArray()
	pos_bytes.resize(num_gaussians * 4 * 4)
	for i in range(num_gaussians):
		# Convert Vector4 to PackedFloat32Array
		var pos_floats: PackedFloat32Array = PackedFloat32Array([
			pos_vec[i].x,
			pos_vec[i].y,
			pos_vec[i].z,
			pos_vec[i].w])
		# Append the byte representation to pos_bytes
		pos_bytes.append_array(pos_floats.to_byte_array())
	pos_buffer = rd.storage_buffer_create(pos_bytes.size(), pos_bytes)
	
	# Atomic counter buffer
	var atomic_bytes: PackedByteArray = PackedByteArray()
	atomic_bytes.resize(4)
	atomic_bytes.encode_u32(0, 0)
	atomic_counter_buffer = rd.storage_buffer_create(atomic_bytes.size(), atomic_bytes)

func _create_default_output_texture() -> RID:
	# Creates a default texture for the framebuffer output.
	# In the original C++, framebuffer setup is handled externally; this is a placeholder.
	var tex_format: RDTextureFormat = RDTextureFormat.new()
	tex_format.width = 1280
	tex_format.height = 720
	tex_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(tex_format, RDTextureView.new())

func _initialize_framebuffer_format() -> int:
	# Initializes the framebuffer format for color attachment.
	# Depth attachment is missing here compared to potential needs in original C++ for depth sorting or blending.
	var attachment: RDAttachmentFormat = RDAttachmentFormat.new()
	attachment.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	attachment.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	return rd.framebuffer_format_create([attachment])

func _setup_render_pipeline() -> void:
	# Configures the render pipeline including uniforms and blend states.
	# Note: Original C++ uses separate geometry and fragment shaders (splat_geom.glsl, splat_frag.glsl) which are missing; assumed combined in Godot spatial shader.
	# Setup uniforms
	var camera_matrices_bytes: PackedByteArray = PackedByteArray()
	var cam_to_world: Transform3D = camera.global_transform if camera else Transform3D.IDENTITY
	camera_matrices_bytes.append_array(_matrix_to_bytes(cam_to_world))
	camera_matrices_bytes.append_array(PackedFloat32Array([4000.0, 0.05]).to_byte_array())
	var camera_matrices_buffer: RID = rd.storage_buffer_create(camera_matrices_bytes.size(), camera_matrices_bytes)
	var camera_matrices_uniform: RDUniform = RDUniform.new()
	camera_matrices_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	camera_matrices_uniform.add_id(camera_matrices_buffer)
	
	# Static and dynamic uniform sets (simplified, assuming additional uniforms are provided)
	static_uniform_set = rd.uniform_set_create([], shader, 1) # Placeholder
	dynamic_uniform_set = rd.uniform_set_create([camera_matrices_uniform], shader, 0)
	
	# Blend mode
	var blend: RDPipelineColorBlendState = RDPipelineColorBlendState.new()
	var blend_attachment: RDPipelineColorBlendStateAttachment = RDPipelineColorBlendStateAttachment.new()
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
	blend.attachments = [blend_attachment]
	
	# Create pipeline
	pipeline = rd.render_pipeline_create(
		shader,
		_initialize_framebuffer_format(),
		vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_POINTS,
		RDPipelineRasterizationState.new(),
		RDPipelineMultisampleState.new(),
		RDPipelineDepthStencilState.new(),
		blend
	)

func _matrix_to_bytes(transform: Transform3D) -> PackedByteArray:
	# Converts a Transform3D to a byte array representing a 4x4 matrix.
	# Matches glm::mat4 layout in original C++.
	var bytes: PackedByteArray = PackedByteArray()
	var basis: Basis = transform.basis
	var origin: Vector3 = transform.origin
	bytes.append_array(PackedFloat32Array([
		basis.x.x, basis.x.y, basis.x.z, 0.0,
		basis.y.x, basis.y.y, basis.y.z, 0.0,
		basis.z.x, basis.z.y, basis.z.z, 0.0,
		origin.x, origin.y, origin.z, 1.0
	]).to_byte_array())
	return bytes

func sort(cam_to_world: Transform3D, proj_mat: Projection, viewport: Vector4, near_far: Vector2) -> void:
	# Sorts the Gaussians by depth for back-to-front rendering.
	# Note: Original C++ uses GPU-based radix sort with compute shaders (presort_compute.glsl, multi_radixsort.glsl, multi_radixsort_histograms.glsl) and optional rgc::radix_sort library.
	# This is simplified to CPU-based sorting due to GDScript limitations in handling complex compute pipelines; GPU sorting is missing.
	# Simplified sorting (compute shader not fully supported in GDScript)
	# For now, use CPU-based sorting as a fallback
	var model_view_mat: Transform3D = cam_to_world.inverse()
	var model_view_proj: Projection = proj_mat * Projection(model_view_mat)
	
	# Reset atomic counter
	atomic_counter_vec[0] = 0
	var atomic_bytes: PackedByteArray = PackedByteArray()
	atomic_bytes.resize(4)
	atomic_bytes.encode_u32(0, 0)
	rd.buffer_update(atomic_counter_buffer, 0, atomic_bytes.size(), atomic_bytes)
	
	# CPU-based depth sorting
	var depth_key_pairs: Array = []
	for i in range(num_gaussians):
		var pos: Vector4 = pos_vec[i]
		var pos_3d: Vector3 = Vector3(pos.x, pos.y, pos.z)
		var view_pos: Vector3 = model_view_mat * pos_3d  # Transform Vector3
		var proj_pos: Vector4 = model_view_proj * Vector4(view_pos.x, view_pos.y, view_pos.z, 1.0)
		var depth: float = proj_pos.z / proj_pos.w
		depth_key_pairs.append({"depth": depth, "index": i})
	
	# Sort by depth (descending for back-to-front rendering)
	depth_key_pairs.sort_custom(func(a, b): return a["depth"] > b["depth"])
	
	# Update sort count
	sort_count = depth_key_pairs.size()
	
	# Update index buffer
	var indices_bytes: PackedByteArray = PackedByteArray()
	indices_bytes.resize(num_gaussians * 4)
	var pos: int = 0
	for pair in depth_key_pairs:
		indices_bytes.encode_u32(pos, pair["index"])
		pos += 4
	rd.buffer_update(index_buffer, 0, indices_bytes.size(), indices_bytes)

func render(cam_to_world: Transform3D, proj_mat: Projection, viewport: Vector4, near_far: Vector2) -> void:
	# Renders the sorted Gaussians using the configured pipeline.
	# Sets up camera uniforms and issues draw commands.
	# Note: Original C++ binds uniforms directly (viewMat, projMat, etc.) and draws with glDrawElements; here adapted to RenderingDevice.
	var view_mat: Transform3D = cam_to_world.inverse()
	var eye: Vector3 = cam_to_world.origin
	
	# Update camera matrices uniform
	var camera_matrices_bytes: PackedByteArray = _matrix_to_bytes(cam_to_world)
	camera_matrices_bytes.append_array(PackedFloat32Array([4000.0, 0.05]).to_byte_array())
	var camera_matrices_buffer: RID = rd.storage_buffer_create(camera_matrices_bytes.size(), camera_matrices_bytes)
	var camera_matrices_uniform: RDUniform = RDUniform.new()
	camera_matrices_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	camera_matrices_uniform.add_id(camera_matrices_buffer)
	
	dynamic_uniform_set = rd.uniform_set_create([camera_matrices_uniform], shader, 0)
	
	# Begin rendering\
	
	rd.draw_command_begin_label("SplatRenderer::Render", Color(1,1,1))
	rd.framebuffer_set(framebuffer)
	rd.pipeline_set(pipeline)
	rd.uniform_set_bind(dynamic_uniform_set, 0)
	rd.uniform_set_bind(static_uniform_set, 1)
	rd.vertex_array_set(vertex_array)
	rd.index_array_set(index_array)
	rd.draw_indexed(sort_count, 1, 0, 0, 0)
	rd.draw_command_end_label()
