#[compute]
#version 450

// Invocations
layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer MyDataBuffer {
	float data[];
}
myDataBuffer;

layout(set = 0, binding = 1, std430) restrict buffer GlobalParams {
	int transformation;
	int offset;
	int size;
	int property_count;
	float centerX;
	float centerY;
	float centerZ;
}
globalParams;

layout(set = 0, binding = 2, std430) restrict buffer Params {
	int integer;
	float float1;
	float float2;
	float float3;
}
params;

vec4 eulerToQuat(vec3 euler) {
    float cx = cos(euler.x * 0.5);
    float sx = sin(euler.x * 0.5);
    float cy = cos(euler.y * 0.5);
    float sy = sin(euler.y * 0.5);
    float cz = cos(euler.z * 0.5);
    float sz = sin(euler.z * 0.5);

    return vec4(
        sx * cy * cz - cx * sy * sz, //x
        cx * sy * cz + sx * cy * sz,
        cx * cy * sz - sx * sy * cz,
        cx * cy * cz + sx * sy * sz  //w
    );
}

vec4 quatMultiply(vec4 q1, vec4 q2) {
    return vec4(
        q1.w*q2.x + q1.x*q2.w + q1.y*q2.z - q1.z*q2.y, //x
        q1.w*q2.y - q1.x*q2.z + q1.y*q2.w + q1.z*q2.x, //y
        q1.w*q2.z + q1.x*q2.y - q1.y*q2.x + q1.z*q2.w,
        q1.w*q2.w - q1.x*q2.x - q1.y*q2.y - q1.z*q2.z
    );
	/*return vec4(
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,  // 1
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,  // i
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,  // j
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w   // k
    );*/
}

vec3 rotateVectorByQuat(vec3 v, vec4 q) {
    vec3 qv = q.xyz;
    vec3 t = 2.0 * cross(qv, v);
    return v + q.w * t + cross(qv, t);
}

void main() {
	uint xid = gl_GlobalInvocationID.x * globalParams.property_count;
	int byteOffset = globalParams.offset;
	int endPoint = (globalParams.offset + (globalParams.size * globalParams.property_count));
	if(xid >= byteOffset && xid < endPoint) {
		if(globalParams.transformation == 2) {//translate
			myDataBuffer.data[xid + params.integer] += params.float1;
		}
		else if(globalParams.transformation == 3) {//rotate
			vec3 pos = vec3(
				myDataBuffer.data[xid],
				myDataBuffer.data[xid + 1],
				myDataBuffer.data[xid + 2]
			);
			vec4 quat = vec4(
				myDataBuffer.data[xid + 58],
				myDataBuffer.data[xid + 59],
				myDataBuffer.data[xid + 60],
				myDataBuffer.data[xid + 61]
			);
			vec3 pivot = vec3(
				globalParams.centerX,
				globalParams.centerY,
				globalParams.centerZ
			);
			vec3 euler = vec3(
				params.float1,
				params.float2,
				params.float3
			);

			vec4 q_rot = eulerToQuat(euler);
			vec3 new_pos = rotateVectorByQuat(pos - pivot, q_rot) + pivot;
			//vec4 new_quat = quatMultiply(q_rot, quat);
			vec4 new_quat = quatMultiply(quat, q_rot);

			myDataBuffer.data[xid] = new_pos.x;
			myDataBuffer.data[xid + 1] = new_pos.y;
			myDataBuffer.data[xid + 2] = new_pos.z;
			myDataBuffer.data[xid + 58] = new_quat.x;
			myDataBuffer.data[xid + 59] = new_quat.y;
			myDataBuffer.data[xid + 60] = new_quat.z;
			myDataBuffer.data[xid + 61] = new_quat.w;
		}
		else if(globalParams.transformation == 4) {//scale
			myDataBuffer.data[xid] *= params.float1;
			myDataBuffer.data[xid + 1] *= params.float1;
			myDataBuffer.data[xid + 2] *= params.float1;
			myDataBuffer.data[xid + 55] += params.float2;
			myDataBuffer.data[xid + 56] += params.float2;
			myDataBuffer.data[xid + 57] += params.float2;
		}
	}
}
