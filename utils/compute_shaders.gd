static var rd := RenderingServer.create_local_rendering_device()
static var irs: Array[RDShaderSPIRV]
static var shaders: Array[RID] = get_shaders(irs)
const files: Array[RDShaderFile]= []#[preload("res://Dev/Compute Netcode.glsl")]

static func get_shaders(shader_irs: Array[RDShaderSPIRV]) -> Array[RID]:
	var array: Array[RID] = []
	var num_shaders := files.size()
	irs.resize(num_shaders)
	array.resize(num_shaders)
	var ir: RDShaderSPIRV
	for i in num_shaders:
		ir = files[i].get_spirv()
		irs[i] = ir
		array[i] = rd.shader_create_from_spirv(ir)
	return array

static func get_uniforms(buffers: Array[RID]) -> Array[RDUniform]:
	var uniforms: Array[RDUniform] = []
	var num_uniforms: int = buffers.size()
	uniforms.resize(num_uniforms)
	var uniform: RDUniform
	for i in num_uniforms:
		uniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = i
		uniform.add_id(buffers[i])
		uniforms[i] = uniform
	return uniforms

static func compute(idx: int, inputs: Array[PackedByteArray], usage: int = 0) -> Array[RID]:
	var shader := shaders[idx]
	var buffers: Array[RID]
	var num_inputs: int = inputs.size()
	buffers.resize(num_inputs)
	var input: PackedByteArray
	for i in num_inputs:
		input = inputs[i]
		buffers[i] = rd.storage_buffer_create(input.size(),input,usage)
	
	# TODO: Change
	var uniform_set := rd.uniform_set_create(get_uniforms(buffers),shader,0) # 0 needs to match set in given shader file
	
	var pipeline := rd.compute_pipeline_create(shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list,pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	# TODO: Change
	rd.compute_list_dispatch(compute_list, 2, 1, 1) # 2, 1, 1 needs to match x, y, z axes
	rd.compute_list_end()
	
	rd.submit()
	
	return buffers

static func sync() -> void:
	rd.sync()

static func get_computed_buffer(buffer: RID, offset: int = 0, size: int = 0) -> PackedByteArray:
	return rd.buffer_get_data(buffer,offset,size)
