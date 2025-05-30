#[compute]
#version 450

// Invocations
layout(local_size_x = 620, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer MyDataBuffer {
	float data[];
}
my_data_buffer;

layout(set = 0, binding = 1, std430) restrict buffer Params {
	float property_count;
	float dist;
}
params;

void main() {
	float a  = gl_GlobalInvocationID.x;
	float b = params.property_count;
	if(a - (b * floor(a/b)) == 0) {//a mod b (only the x property)
		my_data_buffer.data[gl_GlobalInvocationID.x] += params.dist;
		
		//spherical explosion
		/*vec3 direction = normalize(vec3(my_data_buffer.data[gl_GlobalInvocationID.x], my_data_buffer.data[gl_GlobalInvocationID.x + 1], my_data_buffer.data[gl_GlobalInvocationID.x + 2]));
		my_data_buffer.data[gl_GlobalInvocationID.x] += direction.x * params.dist;
		my_data_buffer.data[gl_GlobalInvocationID.x + 1] += direction.y * params.dist;
		my_data_buffer.data[gl_GlobalInvocationID.x + 2] += direction.z * params.dist;*/
		
		/*my_data_buffer.data[gl_GlobalInvocationID.x + 6] += params.dist;
		my_data_buffer.data[gl_GlobalInvocationID.x + 7] += params.dist;
		my_data_buffer.data[gl_GlobalInvocationID.x + 8] += params.dist;*/
		/*my_data_buffer.data[gl_GlobalInvocationID.x + 58] = 0;
		my_data_buffer.data[gl_GlobalInvocationID.x + 59] = 0;
		my_data_buffer.data[gl_GlobalInvocationID.x + 60] = 1;
		my_data_buffer.data[gl_GlobalInvocationID.x + 61] = 0;*/
		
		//split in half
		/*if(my_data_buffer.data[gl_GlobalInvocationID.x] < 0) {
			my_data_buffer.data[gl_GlobalInvocationID.x] -= params.dist;
		}
		else {
			my_data_buffer.data[gl_GlobalInvocationID.x] += params.dist;
		}*/
	}
}