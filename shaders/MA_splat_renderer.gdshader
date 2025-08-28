shader_type spatial;
render_mode unshaded, cull_disabled;
#ifdef FULL_SH
#define SH_COEFF_COUNT 16
#else
#define SH_COEFF_COUNT 4
#endif
#ifdef OUTPUT_IS_SRGB
float SRGBToLinearF(float srgb) {
    if (srgb <= 0.04045) {
        return srgb / 12.92;
    } else {
        return pow((srgb + 0.055) / 1.055, 2.4);
    }
}
vec3 SRGBToLinear(vec3 srgbColor) {
    return vec3(SRGBToLinearF(srgbColor.r), SRGBToLinearF(srgbColor.g), SRGBToLinearF(srgbColor.b));
}
#endif

// Uniforms matching GDScript's camera_matrices_buffer
uniform mat4 viewMat;
// Camera to world inverse (view matrix)
uniform mat4 projMat; // Projection matrix
uniform vec4 viewport;
// Viewport parameters (x, y, width, height)
uniform vec4 projParams; // Projection parameters (width, near, far, 0.0)
uniform vec3 eye;
// Camera position in world space

// Vertex inputs (order must match GDScript's RDVertexAttribute setup)
//VERTEX
// Center of Gaussian (alpha in w)
uniform vec4 r_sh0; // Red SH coefficients (order 0)
uniform vec4 g_sh0;
// Green SH coefficients (order 0)
uniform vec4 b_sh0; // Blue SH coefficients (order 0)
#ifdef FULL_SH
uniform vec4 r_sh1;
// Red SH coefficients (order 1)
uniform vec4 r_sh2; // Red SH coefficients (order 2)
uniform vec4 r_sh3;
// Red SH coefficients (order 3)
uniform vec4 g_sh1; // Green SH coefficients (order 1)
uniform vec4 g_sh2;
// Green SH coefficients (order 2)
uniform vec4 g_sh3; // Green SH coefficients (order 3)
uniform vec4 b_sh1;
// Blue SH coefficients (order 1)
uniform vec4 b_sh2; // Blue SH coefficients (order 2)
uniform vec4 b_sh3;
// Blue SH coefficients (order 3)
uniform vec3 cov3_col0; // Covariance matrix column 0
uniform vec3 cov3_col1;
// Covariance matrix column 1
uniform vec3 cov3_col2; // Covariance matrix column 2
#else
uniform vec3 cov3_col0;
// Covariance matrix column 0
uniform vec3 cov3_col1; // Covariance matrix column 1
uniform vec3 cov3_col2;
// Covariance matrix column 2
#endif

// Outputs to fragment shader
varying vec4 frag_color; // Radiance and alpha of splat
varying vec4 frag_cov2inv;
// Inverse 2D screen-space covariance matrix
varying vec2 frag_p; // 2D screen-space center of Gaussian

// Compute radiance using spherical harmonics
vec3 ComputeRadianceFromSH(vec3 v) {
    float b[SH_COEFF_COUNT];
float vx2 = v.x * v.x;
    float vy2 = v.y * v.y;
    float vz2 = v.z * v.z;
// Zeroth order
    b[0] = 0.28209479177387814;
    
    // First order
    float k1 = 0.4886025119029199;
b[1] = -k1 * v.y;
    b[2] = k1 * v.z;
    b[3] = -k1 * v.x;
#ifdef FULL_SH
    // Second order
    float k2 = 1.0925484305920792;
    float k3 = 0.31539156525252005;
float k4 = 0.5462742152960396;
    b[4] = k2 * v.y * v.x;
    b[5] = -k2 * v.y * v.z;
b[6] = k3 * (3.0 * vz2 - 1.0);
    b[7] = -k2 * v.x * v.z;
b[8] = k4 * (vx2 - vy2);
    
    // Third order
    float k5 = 0.5900435899266435;
float k6 = 2.8906114426405543;
    float k7 = 0.4570457994644658;
    float k8 = 0.37317633259011546;
    float k9 = 1.4453057213202771;
b[9] = -k5 * v.y * (3.0 * vx2 - vy2);
    b[10] = k6 * v.y * v.x * v.z;
b[11] = -k7 * v.y * (5.0 * vz2 - 1.0);
b[12] = k8 * v.z * (5.0 * vz2 - 3.0);
b[13] = -k7 * v.x * (5.0 * vz2 - 1.0);
    b[14] = k9 * v.z * (vx2 - vy2);
b[15] = -k5 * v.x * (vx2 - 3.0 * vy2);
float re = (b[0] * r_sh0.x + b[1] * r_sh0.y + b[2] * r_sh0.z + b[3] * r_sh0.w +
                b[4] * r_sh1.x + b[5] * r_sh1.y + b[6] * r_sh1.z + b[7] * r_sh1.w +
                b[8] * r_sh2.x + b[9] * r_sh2.y + b[10] * r_sh2.z + b[11] * r_sh2.w +
                b[12] * r_sh3.x + 
b[13] * r_sh3.y + b[14] * r_sh3.z + b[15] * r_sh3.w);
float gr = (b[0] * g_sh0.x + b[1] * g_sh0.y + b[2] * g_sh0.z + b[3] * g_sh0.w +
                b[4] * g_sh1.x + b[5] * g_sh1.y + b[6] * g_sh1.z + b[7] * g_sh1.w +
                b[8] * g_sh2.x + b[9] * g_sh2.y + b[10] * g_sh2.z + b[11] * g_sh2.w +
                b[12] * g_sh3.x + 
b[13] * g_sh3.y + b[14] * g_sh3.z + b[15] * g_sh3.w);
float bl = (b[0] * b_sh0.x + b[1] * b_sh0.y + b[2] * b_sh0.z + b[3] * b_sh0.w +
                b[4] * b_sh1.x + b[5] * b_sh1.y + b[6] * b_sh1.z + b[7] * b_sh1.w +
                b[8] * b_sh2.x + b[9] * b_sh2.y + b[10] * b_sh2.z + b[11] * b_sh2.w +
                b[12] * b_sh3.x + 
b[13] * b_sh3.y + b[14] * b_sh3.z + b[15] * b_sh3.w);
#else
    float re = (b[0] * r_sh0.x + b[1] * r_sh0.y + b[2] * r_sh0.z + b[3] * r_sh0.w);
float gr = (b[0] * g_sh0.x + b[1] * g_sh0.y + b[2] * g_sh0.z + b[3] * g_sh0.w);
float bl = (b[0] * b_sh0.x + b[1] * b_sh0.y + b[2] * b_sh0.z + b[3] * b_sh0.w);
#endif
    return vec3(0.5, 0.5, 0.5) + vec3(re, gr, bl);
}

// Compute inverse of a 2x2 matrix
mat2 inverse_mat2(mat2 m) {
    float det = m[0][0] * m[1][1] - m[0][1] * m[1][0];
if (det == 0.0) {
        return mat2(0.0);
}
	mat2 inv = mat2(m[1][1]);
	inv[0][1] = -m[0][1];
	inv[1][0] = -m[1][0];
	inv[1][1] = m[0][0];
	inv/=det;
    return inv;
}

void vertex() {
    // Extract alpha from position
	//CHANGE POSITION.w to COLOR.a
    float alpha = COLOR.a;
// Transform position to view space
    vec4 t = viewMat * vec4(VERTEX.xyz, 1.0);
// Viewport dimensions
    float width = viewport.z;
    float height = viewport.w;
    float zNear = projParams.y;
float zFar = projParams.z;
    
    // Jacobian of projection and viewport transformations
    float sx = projMat[0][0];
float sy = projMat[1][1];
    float wz = projMat[3][2];
    float tzSq = t.z * t.z;
float jsx = -(sx * width) / (2.0 * t.z);
    float jsy = -(sy * height) / (2.0 * t.z);
float jtx = (sx * t.x * width) / (2.0 * tzSq);
float jty = (sy * t.y * height) / (2.0 * tzSq);
float jtz = ((zFar - zNear) * wz) / (2.0 * tzSq);
mat3 J = mat3(vec3(jsx, 0.0, 0.0),
                  vec3(0.0, jsy, 0.0),
                  vec3(jtx, jty, jtz));
// Combine view and projection transformations
    mat3 W = mat3(viewMat);
    mat3 V = mat3(cov3_col0, cov3_col1, cov3_col2);
mat3 JW = J * W;
    mat3 V_prime = JW * V * transpose(JW);
// Project 3D covariance to 2D and apply anti-aliasing
    mat2 cov2D = mat2(V_prime);
    cov2D[0][0] += 0.3;
cov2D[1][1] += 0.3;
    
    // Compute inverse covariance for fragment shader
    frag_cov2inv = vec4(inverse_mat2(cov2D)[0], inverse_mat2(cov2D)[1]);
// Compute screen-space center
    vec4 p4 = projMat * t;
frag_p = vec2(p4.x / p4.w, p4.y / p4.w);
    frag_p.x = 0.5 * (width + (frag_p.x * width));
frag_p.y = 0.5 * (height + (frag_p.y * height));
    
    // Compute radiance
    vec3 v = normalize(VERTEX.xyz - eye);
frag_color = vec4(ComputeRadianceFromSH(v), alpha);
#ifdef OUTPUT_IS_SRGB
    frag_color.rgb = SRGBToLinear(frag_color.rgb);
#endif
    
    // Set clip-space position
    POSITION = p4;
}

void fragment() {
    // Compute Gaussian contribution
    vec2 d = FRAGCOORD.xy - frag_p;
	mat2 cov2Dinv = mat2(frag_cov2inv.x);
	cov2Dinv[0][1] = frag_cov2inv.y;
	cov2Dinv[1][0] = frag_cov2inv.z;
	cov2Dinv[1][1] = frag_cov2inv.w;
    float g = exp(-0.5 * dot(d, cov2Dinv * d));
// Set color and alpha
    ALBEDO = frag_color.rgb * frag_color.a * g;
    ALPHA = frag_color.a * g;
// Discard low-alpha fragments
    if (ALPHA <= (1.0 / 256.0)) {
        discard;
    }
}