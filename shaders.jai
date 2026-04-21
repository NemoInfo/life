WORLD_VS :: #run tprint(#string GLSL
#version 430 core

layout (location = 0) in vec2 vertex_pos;
layout (location = 1) in vec2 particle_pos;
layout (location = 2) in int  particle_type;
layout(std430, binding = 4) buffer ColorBuffer {
  vec4 colors[];
};

out vec2 out_vertex_pos;
out vec4 out_vertex_col; 

uniform vec2  u_resolution;
uniform vec2  u_world_size;
const float PARTICLE_RADIUS = %1;

void main() {
  out_vertex_pos = vertex_pos;
  out_vertex_col = colors[particle_type];

  vec2 world_pos  = particle_pos + vertex_pos * PARTICLE_RADIUS;
  vec2 scale   = u_resolution / u_world_size;
  vec2 fbo_pos = (world_pos + u_world_size * 0.5) * scale;

  vec2 ndc = (fbo_pos / u_resolution ) * 2.0 - 1.0;
  ndc.y    = -ndc.y;
  gl_Position = vec4(ndc, 0.0, 1.0);
}
GLSL, PARTICLE_RADIUS);

WORLD_FS :: #string GLSL
#version 330 core

in vec2 out_vertex_pos;
in vec4 out_vertex_col; 

out vec4 frag_color;

void main() {
  // SDF circle discard — local_pos is in [-1,1], circle has radius 1 in local space
  float d = length(out_vertex_pos) - 1.0;
  if (d > 0.0) discard;

  // Soft anti-aliased edge
  float alpha = 1.0 - smoothstep(-0.3, 0.0, d);
  frag_color = vec4(out_vertex_col.rgb, out_vertex_col.a * alpha);
}
GLSL

TILE_VS :: #string GLSL
#version 330 core
layout (location = 0) in vec2 aPos;
out vec2 vTexCoord;
void main() {
  vTexCoord = aPos * 0.5 + 0.5;
  gl_Position = vec4(aPos, 0.0, 1.0);
}
GLSL

TILE_FS :: #string GLSL
#version 330 core

in vec2 vTexCoord;
out vec4 fragColor;

uniform sampler2D u_worldTexture;
uniform vec2      u_windowSize;
uniform vec2      u_worldSize;
uniform vec2      u_cameraPos;
uniform float     u_cameraZoom;

vec3 grayscale(vec3 c) {
  return vec3(dot(c, vec3(0.299, 0.587, 0.114)));
}

void main() {
  vec2 offset   = (gl_FragCoord.xy - u_windowSize * 0.5) / u_cameraZoom;
  vec2 worldPos = u_cameraPos + vec2(offset.x, -offset.y); // flip Y: screen down = world up
  vec2  worldUV = fract(worldPos / u_worldSize + 0.5);
  ivec2 tileIdx = ivec2(floor(worldPos / u_worldSize + 0.5));
  bool isOrigin = ((worldPos.x - u_cameraPos.x) > -u_worldSize.x / 2 && 
                   (worldPos.y - u_cameraPos.y) > -u_worldSize.y / 2 &&
                   (worldPos.x - u_cameraPos.x) <  u_worldSize.x / 2 &&
                   (worldPos.y - u_cameraPos.y) <  u_worldSize.y / 2);
  vec4 col      = texture(u_worldTexture, worldUV);
  fragColor     = vec4(isOrigin ? col.rgb : grayscale(col.rgb), col.a);
}
GLSL

COMPUTE_SHADER :: #run tprint(#string GLSL
#version 430 core

layout(local_size_x = %1) in;

layout(std430, binding = 0) buffer PosBuffer {
    vec2 pos[];
};

layout(std430, binding = 1) buffer VelBuffer {
    vec2 vel[];
};

layout(std430, binding = 2) buffer TypeBuffer {
    int type[];
};

layout(std430, binding = 3) buffer AttractionBuffer {
    float attraction_matrix[];
};

uniform vec2  u_worldSize;
uniform float u_dt;
uniform float u_rMax;
uniform float u_frictionFactor;
uniform int   u_numParticles;
uniform int   u_numParticleTypes;

const float BETA = 0.3;

float force(float r, float a) {
    if (r < BETA) return r / BETA - 1.0;
    if (r < 1.0)  return a * (1.0 - abs(2.0 * r - 1.0 - BETA) / (1.0 - BETA));
    return 0.0;
}

void main() {
  uint i = gl_GlobalInvocationID.x;
  if (i >= u_numParticles) return;

  vec2 total_a = vec2(0.);
  for (uint j = 0; j < u_numParticles; ++j) {
    if (i == j) continue;
    vec2 r = pos[j] - pos[i];
    r.x -= u_worldSize.x * float(r.x >  u_worldSize.x * 0.5);
    r.x += u_worldSize.x * float(r.x < -u_worldSize.x * 0.5);
    r.y -= u_worldSize.y * float(r.y >  u_worldSize.y * 0.5);
    r.y += u_worldSize.y * float(r.y < -u_worldSize.y * 0.5);
    float r_len = length(r);
    if (r_len > u_rMax) continue;
    float a = attraction_matrix[type[i] * u_numParticleTypes + type[j]];
    total_a += (r / r_len) * force(r_len / u_rMax, a);
  }
  vel[i] *= u_frictionFactor;
  vel[i] += total_a * u_rMax * u_dt; 
  pos[i] += vel[i] * u_dt;

  pos[i].x -= u_worldSize.x * float(pos[i].x >  u_worldSize.x * 0.5);
  pos[i].x += u_worldSize.x * float(pos[i].x < -u_worldSize.x * 0.5);
  pos[i].y -= u_worldSize.y * float(pos[i].y >  u_worldSize.y * 0.5);
  pos[i].y += u_worldSize.y * float(pos[i].y < -u_worldSize.y * 0.5);
}
GLSL, PARTICLES_PER_WORK_GROUPS);
