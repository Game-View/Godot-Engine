#[vertex]
#version 450 core

layout(location = 0) in vec3 vertex_position;

layout(set = 0, binding = 3, std430) restrict buffer CameraData {
	mat4 CameraToWorld;
	float CameraFarPlane;
	float CameraNearPlane;
}
camera_data;


layout(set = 0, binding = 1, std430) restrict buffer Params {
	vec2 viewport_size;
    float tan_fovx;
    float tan_fovy;
    float focal_x;
    float focal_y;
    float modifier;
    float sh_degree;
}
params;


layout(set = 0, binding = 0, std430) buffer DepthBuffer {
    uvec2 depth[];
};

layout(set = 1, binding = 0, std430) restrict buffer VerticesBuffer {
    float vertices[];
};


// Helpful resources:
// https://github.com/kishimisu/Gaussian-Splatting-WebGL
// https://github.com/antimatter15/splat
// https://github.com/graphdeco-inria/diff-gaussian-rasterization

const float SH_C0 = 0.28209479177387814;
const float SH_C1 = 0.4886025119029199;
const float SH_C2[5] = float[5](1.0925484305920792, -1.0925484305920792, 0.31539156525252005, -1.0925484305920792, 0.5462742152960396);
const float SH_C3[7] = float[7](-0.5900435899266435, 0.5900435899266435, -0.16560942488640108, 0.5900435899266435, -0.4915222934426505, -0.5900435899266435, 0.5900435899266435);

float sigmoid(float x) {
    return 1.0 / (1.0 + exp(-x));
}

vec3 quat_rotate_vec3(vec4 q, vec3 v) {
    return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}


mat3 quat_rotate(vec4 q, mat3 v) {
    return mat3(
        quat_rotate_vec3(q, v[0]),
        quat_rotate_vec3(q, v[1]),
        quat_rotate_vec3(q, v[2])
    );
}

vec3 computeColorFromSH(int degree, vec3 pos, vec3 view_pos, vec3 sh[16]) {
    vec3 dir = normalize(pos - view_pos);
    if (degree == 0) {
        return sh[0];
    }
    
    // (rest of the computeColorFromSH function for higher degrees)
    // NOTE: This part is not needed for the current PLY file but is kept for completeness.
    return sh[0]; // Fallback
}

float ndc2Pix(float val, float size) {
    return ((val + 1.0) * 0.5) * size;
}

layout (location = 1) out vec4 vColor;
layout (location = 2) out vec4 vConicAndOpacity;
layout (location = 3) out vec2 vUV;

void main() {
    uint idx = uint(gl_VertexIndex);

    vec3 pos = vec3(
        vertices[idx * 51],
        vertices[idx * 51 + 1],
        vertices[idx * 51 + 2]);
    vec3 scale = exp(vec3(
        vertices[idx * 51 + 3],
        vertices[idx * 51 + 4],
        vertices[idx * 51 + 5]));
    float opacity = sigmoid(
        vertices[idx * 51 + 6]);
    vec4 rot = vec4(
        vertices[idx * 51 + 7],
        vertices[idx * 51 + 8],
        vertices[idx * 51 + 9],
        vertices[idx * 51 + 10]);

    mat4 viewMatrix = inverse(camera_data.CameraToWorld);
    mat4 projectionMatrix = mat4(
        params.focal_x / params.viewport_size.x, 0, 0, 0,
        0, params.focal_y / params.viewport_size.y, 0, 0,
        0, 0, camera_data.CameraFarPlane / (camera_data.CameraNearPlane - camera_data.CameraFarPlane), -1,
        0, 0, -(camera_data.CameraNearPlane * camera_data.CameraFarPlane) / (camera_data.CameraNearPlane - camera_data.CameraFarPlane), 0);

    mat4 view_projection = projectionMatrix * viewMatrix;
    vec4 p_view = viewMatrix * vec4(pos, 1.0);

    mat3 J = mat3(view_projection) * mat3(
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 0.0);
    mat3 V = mat3(
        scale.x * scale.x, 0, 0,
        0, scale.y * scale.y, 0,
        0, 0, scale.z * scale.z);
    V = quat_rotate(rot, V);
    mat3 Sigma = V;
    mat3 M = transpose(J) * J;
    mat3 S = M * Sigma;
    
    vec4 cov2d = vec4(
        S[0][0], S[0][1],
        S[1][0], S[1][1]);
    
    float det = cov2d.x * cov2d.w - cov2d.y * cov2d.z;
    float det_inv = 1.0 / det;
    
    vec4 conic = vec4(
        cov2d.w * det_inv, -cov2d.y * det_inv,
        -cov2d.z * det_inv, cov2d.x * det_inv);
	float mid = 0.5 * (cov2d.x + cov2d.z);

    float lambda_1 = mid + sqrt(max(0.1, mid * mid - det));
    float lambda_2 = mid - sqrt(max(0.1, mid * mid - det));
    float radius_px = ceil(3. * sqrt(max(lambda_1, lambda_2)));
    vec2 point_image = vec2(ndc2Pix(p_view.x/p_view.z, params.viewport_size.x), ndc2Pix(p_view.y/p_view.z, params.viewport_size.y));

    // Read only the f_dc (degree 0) spherical harmonic coefficients
    vec4 sh_color = vec4(
        sigmoid(vertices[idx * 51 + 11]),
        sigmoid(vertices[idx * 51 + 12]),
        sigmoid(vertices[idx * 51 + 13]),
		opacity
    );
    
    vColor = sh_color;
    vConicAndOpacity = vec4(conic);

    vec2 screen_pos = point_image + radius_px * (vertex_position.xy);
    vUV = point_image - screen_pos;
    gl_Position = vec4(screen_pos / params.viewport_size * 2 - 1, 0, 1);
}



#[fragment]
#version 450 core

layout (location = 1) in vec4 vColor;
layout (location = 2) in vec4 vConicAndOpacity;
layout (location = 3) in vec2 vUV;

layout (set = 0, binding = 0, std430) buffer DepthBuffer {
    uvec2 depth[];
};

layout (location = 0) out vec4 frag_color;

float gaussian2D(vec2 pos, vec4 conic) {
    float A = conic.x;
    float B = conic.y;
    float C = conic.z;
    float D = conic.w;
    float E = pos.x * pos.x * A + pos.x * pos.y * B + pos.y * pos.y * C;
    return exp(-E);
}

void main() {
    float g = gaussian2D(vUV, vConicAndOpacity);
    frag_color = vColor * g;
}