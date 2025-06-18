#[compute]
#version 450

#define PROP_X 0
#define PROP_Y 1
#define PROP_Z 2
#define PROP_SCALE_X 55
#define PROP_SCALE_Y 56
#define PROP_SCALE_Z 57
#define PROP_QROT_X 58
#define PROP_QROT_Y 59
#define PROP_QROT_Z 60
#define PROP_QROT_W 61

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
        sx * cy * cz + cx * sy * sz, //x
        cx * sy * cz - sx * cy * sz, //y
        cx * cy * sz + sx * sy * cz, //z
        cx * cy * cz - sx * sy * sz  //w
    );
}

vec4 quatMultiply(vec4 q1, vec4 q2) {
    return vec4(
        q1.w*q2.x + q1.x*q2.w + q1.y*q2.z - q1.z*q2.y, //x
        q1.w*q2.y - q1.x*q2.z + q1.y*q2.w + q1.z*q2.x, //y
        q1.w*q2.z + q1.x*q2.y - q1.y*q2.x + q1.z*q2.w, //z
        q1.w*q2.w - q1.x*q2.x - q1.y*q2.y - q1.z*q2.z  //w
    );
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
			myDataBuffer.data[xid + PROP_X] += params.float1;
			myDataBuffer.data[xid + PROP_Y] += params.float2;
			myDataBuffer.data[xid + PROP_Z] += params.float3;
		}
		else if(globalParams.transformation == 3) {//rotate
			vec3 pos = vec3(
				myDataBuffer.data[xid + PROP_X],
				myDataBuffer.data[xid + PROP_Y],
				myDataBuffer.data[xid + PROP_Z]
			);
			vec4 quat = vec4(
				myDataBuffer.data[xid + PROP_QROT_X],
				myDataBuffer.data[xid + PROP_QROT_Y],
				myDataBuffer.data[xid + PROP_QROT_Z],
				myDataBuffer.data[xid + PROP_QROT_W]
			);
			vec3 pivot = vec3(
				globalParams.centerX,
				globalParams.centerY,
				globalParams.centerZ
			);
			vec3 eulerPos = vec3(
				params.float1,
				params.float2,
				params.float3
			);
			vec3 eulerRot = vec3(
				-params.float3,
				params.float2,
				-params.float1
			);

			vec4 q_rot_pos = eulerToQuat(eulerPos);
			vec4 q_rot_rot = eulerToQuat(eulerRot);
			vec3 new_pos = rotateVectorByQuat(pos - pivot, q_rot_pos) + pivot;
			vec4 new_quat = quatMultiply(quat, q_rot_rot);

			myDataBuffer.data[xid + PROP_X] = new_pos.x;
			myDataBuffer.data[xid + PROP_Y] = new_pos.y;
			myDataBuffer.data[xid + PROP_Z] = new_pos.z;
			myDataBuffer.data[xid + PROP_QROT_X] = new_quat.x;
			myDataBuffer.data[xid + PROP_QROT_Y] = new_quat.y;
			myDataBuffer.data[xid + PROP_QROT_Z] = new_quat.z;
			myDataBuffer.data[xid + PROP_QROT_W] = new_quat.w;
		}
		else if(globalParams.transformation == 4) {//scale
			float cenX = globalParams.centerX;
			float cenY = globalParams.centerY;
			float cenZ = globalParams.centerZ;
			myDataBuffer.data[xid + PROP_X] = (myDataBuffer.data[xid + PROP_X] - cenX) * params.float1 + cenX;
			myDataBuffer.data[xid + PROP_Y] = (myDataBuffer.data[xid + PROP_Y] - cenY) * params.float1 + cenY;
			myDataBuffer.data[xid + PROP_Z] = (myDataBuffer.data[xid + PROP_Z] - cenZ) * params.float1 + cenZ;
			myDataBuffer.data[xid + PROP_SCALE_X] += params.float2;
			myDataBuffer.data[xid + PROP_SCALE_Y] += params.float2;
			myDataBuffer.data[xid + PROP_SCALE_Z] += params.float2;
		}
	}
}
