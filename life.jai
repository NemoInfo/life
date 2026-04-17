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
  float alpha = 1.0 - smoothstep(-0.1, 0.0, d);
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

in vec2 vTexCoord; // full‑screen quad UV [0,1]
out vec4 fragColor;

uniform sampler2D u_worldTexture;
uniform vec2      u_worldSize;
uniform vec2      u_cameraPos;
uniform float     u_cameraZoom;
uniform vec2      u_windowSize;
uniform float     u_particleRadius;   // world units

vec3 grayscale(vec3 c) {
  float luma = dot(c, vec3(0.299, 0.587, 0.114));
  return vec3(luma);
}

void main() {
  // 1. Compute world position from fragment coordinate
  vec2 fragCoord = gl_FragCoord.xy;
  vec2 screenCenter = u_windowSize * 0.5;
  vec2 offset = (fragCoord - screenCenter) / u_cameraZoom;
  vec2 worldPos = u_cameraPos + offset;

  // 2. Convert to texture UV space (0..1 covers exactly one world tile)
  vec2 worldUV = worldPos / u_worldSize + 0.5;
  vec2 tileUV  = fract(worldUV);
  ivec2 tileIndex = ivec2(floor(worldUV));

  // Camera tile index (the "original" coloured tile)
  vec2 camUV = u_cameraPos / u_worldSize + 0.5;
  ivec2 camTile = ivec2(floor(camUV));

  // 4. Sample base tile
  vec4 baseColor = texture(u_worldTexture, tileUV);
  bool isOriginal = (tileIndex == camTile);
  vec3 rgb = isOriginal ? baseColor.rgb : grayscale(baseColor.rgb);
    
  fragColor = vec4(rgb, baseColor.a);
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

f32 :: float32;
f64 :: float64;

PARTICLE_RADIUS           :: 2.;
NUM_PARTICLE_TYPES        :: 8;
NUM_PARTICLES             :: 20_000;
PIXELS_PER_WORLD_UNIT     :: 10;
R_MAX                     :: 100.;
T_HALF                    :: 0.04;
PARTICLES_PER_WORK_GROUPS :: 256;

Simulation_State :: struct {
  world_size:        Vector2 = .{1920*3., 1080*3.};
  attraction_matrix: [..] f32;
  particle_colors:   [..] Vector4;
  resolution:        Vector2 = #run .{1920., 1080.} * PIXELS_PER_WORLD_UNIT;
  window_size:       Vector2 = .{1920., 1080.};
  dt:                f32;
  time_last_frame:   Apollo_Time;
  exit:              bool = false;
}

Camera_Uniform :: struct {
  #as using pos:  Vector2;   // world space point at screen centre
  zoom: f32 = 1. / PIXELS_PER_WORLD_UNIT; // pixels per world unit
}

Camera :: struct {
  #as using uniform: Camera_Uniform;
  is_panning:        bool;
  pan_start_mouse:   Vector2;
  pan_start_camera:  Vector2;
}

Particle_Instances :: struct {
  pos:  [..] Vector2;
  type: [..] u32;
  count: s64;
}

Particles :: struct {
  #as using instances: Particle_Instances;
  vel:  [..] Vector2;
}

Compute_Binding :: struct {
  pos_ssbo: GLuint;
  vel_ssbo: GLuint;
  type_ssbo: GLuint;
  a_ssbo:   GLuint;
  shader:   GLuint;
}

World_Binding :: struct {
  vao:        GLuint;
  quad_vbo:   GLuint;
  pos_vbo:    GLuint;
  type_vbo:   GLuint;
  color_ssbo: GLuint;
  shader:     GLuint;
}

Tile_Binding :: struct {
  framebuffer:   GLuint;
  world_texture: GLuint;
  quad_vao:      GLuint;
  quad_vbo:      GLuint;
  shader:        GLuint;
}

add_instance :: (instances: *Particle_Instances, pos: Vector2, type: u32) {
  array_add(*instances.pos,  pos);
  array_add(*instances.type, type);
  instances.count += 1;
}

remove_n_instances_from_end :: (instances: *Particle_Instances, n: s64) {
  instances.*.count      -= n;
  instances.*.pos.count  -= n;
  instances.*.type.count -= n;
}

add_particle :: (particles: *Particles, pos: Vector2, vel: Vector2, acc: Vector2, type: u32) {
  array_add(*particles.pos,  pos);
  array_add(*particles.vel,  vel);
  array_add(*particles.type, type);
  particles.count += 1;
}

wrap_particle_instances :: (instances: *Particle_Instances, world_size: Vector2) -> s64 {
  init_count := instances.count;
  for 0..init_count-1 {
    if instances.pos[it].x > world_size.x * 0.5 - PARTICLE_RADIUS
      add_instance(instances, instances.pos[it] - .{world_size.x,0}, instances.type[it]);
    if instances.pos[it].x < -world_size.x * 0.5 + PARTICLE_RADIUS
      add_instance(instances, instances.pos[it] + .{world_size.x,0}, instances.type[it]);
    if instances.pos[it].y > world_size.y * 0.5 - PARTICLE_RADIUS
      add_instance(instances, instances.pos[it] - .{0,world_size.y}, instances.type[it]);
    if instances.pos[it].y < -world_size.y * 0.5 + PARTICLE_RADIUS
      add_instance(instances, instances.pos[it] + .{0,world_size.y}, instances.type[it]);
  }
  return instances.count - init_count;
}

// @TODO
//   ✔  remove radius and maybe color from instance, maybe bake them into the shader?
//   ✔  implement 2D Camera, switch to world coordonates
//   ✔  attraction laws
//   - gui & tools
//     - controls, pause play etc.
//     - brushes
//
// @PERFORMANCE:
//   ✔  push update to compute shader
//   - async simulation thread 
//   - hierarichal structure 
//
// @QUALITY:
//   - fix render to texture pipeline, 
//     think about how to tie tile resolution to camera zoom
//   - refactor tiling logic, 
//     i think it should be slightly simpler
//   - break the monolith, refactor game loop
//   - async logging
//   - fix flickering at distance out
//   ? add bloom in post

compile_shader :: (source: string, shader_type: GLenum) -> GLuint {
    using gl;
    id := glCreateShader(shader_type);
    src := source.data;
    len : GLint = xx source.count;
    glShaderSource(id, 1, *src, *len);
    glCompileShader(id);

    ok : GLint;
    glGetShaderiv(id, GL_COMPILE_STATUS, *ok);
    if !ok {
      buf : [512] u8; glGetShaderInfoLog(id, 512, null, buf.data);
      print("Shader compile error: %\n", to_string(buf.data));
      exit(1);
    }
    return id;
}

create_compute_shader :: (source: string) -> GLuint {
    using gl;
    shader := glCreateShader(GL_COMPUTE_SHADER);
    src := source.data;
    len : GLint = xx source.count;
    glShaderSource(shader, 1, *src, *len);
    glCompileShader(shader);

    ok : GLint;
    glGetShaderiv(shader, GL_COMPILE_STATUS, *ok);
    if !ok {
        buf : [512] u8; glGetShaderInfoLog(shader, 512, null, buf.data);
        print("Compute shader compile error: %\n", to_string(buf.data));
        exit(1);
    }

    prog := glCreateProgram();
    glAttachShader(prog, shader);
    glLinkProgram(prog);
    glGetProgramiv(prog, GL_LINK_STATUS, *ok);
    if !ok {
        buf : [512] u8; glGetProgramInfoLog(prog, 512, null, buf.data);
        print("Compute program link error: %\n", to_string(buf.data));
        exit(1);
    }
    glDeleteShader(shader);

    return prog;
}

create_shader_program :: (vert_src: string, frag_src: string) -> GLuint {
  using gl;
  vert := compile_shader(vert_src, GL_VERTEX_SHADER);
  frag := compile_shader(frag_src, GL_FRAGMENT_SHADER);
  prog := glCreateProgram();
  glAttachShader(prog, vert);
  glAttachShader(prog, frag);
  glLinkProgram(prog);

  ok : GLint;
  glGetProgramiv(prog, GL_LINK_STATUS, *ok);
  if !ok {
    buf : [512] u8; glGetProgramInfoLog(prog, 512, null, buf.data);
    print("Shader link error: %\n", to_string(buf.data));
    exit(1);
  }
  glDeleteShader(vert);
  glDeleteShader(frag);
  return prog;
}

create_compute_binding :: (particles_count: s64, attraction_matrix: [] f32) -> Compute_Binding {
  using gl;
  b: Compute_Binding;
  b.shader = create_compute_shader(COMPUTE_SHADER);

  // location = 0 pos Vector2
  glGenBuffers     (1, *b.pos_ssbo);
  glBindBuffer     (GL_SHADER_STORAGE_BUFFER, b.pos_ssbo);
  glBufferData     (GL_SHADER_STORAGE_BUFFER, size_of(Vector2) * particles_count, null, GL_DYNAMIC_COPY);
  glBindBufferBase (GL_SHADER_STORAGE_BUFFER, 0, b.pos_ssbo);

  // location = 1 pos Vector2
  glGenBuffers     (1, *b.vel_ssbo);
  glBindBuffer     (GL_SHADER_STORAGE_BUFFER, b.vel_ssbo);
  glBufferData     (GL_SHADER_STORAGE_BUFFER, size_of(Vector2) * particles_count, null, GL_DYNAMIC_COPY);
  glBindBufferBase (GL_SHADER_STORAGE_BUFFER, 1, b.vel_ssbo);

  // location = 2 pos Vector2
  glGenBuffers     (1, *b.type_ssbo);
  glBindBuffer     (GL_SHADER_STORAGE_BUFFER, b.type_ssbo);
  glBufferData     (GL_SHADER_STORAGE_BUFFER, size_of(u32) * particles_count, null, GL_DYNAMIC_COPY);
  glBindBufferBase (GL_SHADER_STORAGE_BUFFER, 2, b.type_ssbo);

  // location = 3 pos Vector2
  glGenBuffers     (1, *b.a_ssbo);
  glBindBuffer     (GL_SHADER_STORAGE_BUFFER, b.a_ssbo);
  glBufferData     (GL_SHADER_STORAGE_BUFFER, size_of(f32) * attraction_matrix.count, attraction_matrix.data, GL_DYNAMIC_COPY);
  glBindBufferBase (GL_SHADER_STORAGE_BUFFER, 3, b.a_ssbo);

  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, 0);
  return b;
}


compute_pass :: (using b: Compute_Binding, particles: *Particles, state: Simulation_State) {
  using gl;
  glUseProgram(shader);

  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, pos_ssbo);
  glBufferSubData (GL_SHADER_STORAGE_BUFFER, 0, size_of(Vector2) * particles.count, particles.pos.data);
  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, vel_ssbo);
  glBufferSubData (GL_SHADER_STORAGE_BUFFER, 0, size_of(Vector2) * particles.count, particles.vel.data);
  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, type_ssbo);
  glBufferSubData (GL_SHADER_STORAGE_BUFFER, 0, size_of(u32) * particles.count, particles.type.data);
  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, a_ssbo);
  glBufferSubData (GL_SHADER_STORAGE_BUFFER, 0, size_of(f32) * state.attraction_matrix.count, state.attraction_matrix.data);
  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, 0);

  // Set uniforms
  glUniform2f(glGetUniformLocation(shader, "u_worldSize"), state.world_size.x, state.world_size.y);
  glUniform1f(glGetUniformLocation(shader, "u_dt"), state.dt);
  glUniform1f(glGetUniformLocation(shader, "u_rMax"), R_MAX);
  glUniform1f(glGetUniformLocation(shader, "u_frictionFactor"), pow(0.5, state.dt / T_HALF));
  glUniform1i(glGetUniformLocation(shader, "u_numParticles"), NUM_PARTICLES);
  glUniform1i(glGetUniformLocation(shader, "u_numParticleTypes"), NUM_PARTICLE_TYPES);

  work_groups := (NUM_PARTICLES + PARTICLES_PER_WORK_GROUPS - 1) / PARTICLES_PER_WORK_GROUPS;
  glDispatchCompute(xx work_groups, 1, 1);

  // Ensure SSBO writes are visible to subsequent draw calls
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT | GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT);
  glUseProgram(0);

  glBindBuffer(GL_SHADER_STORAGE_BUFFER, pos_ssbo);
  glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, size_of(Vector2) * particles.count, particles.pos.data);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, vel_ssbo);
  glGetBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, size_of(Vector2) * particles.count, particles.vel.data);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
}

create_tile_binding :: (resolution: Vector2) -> Tile_Binding {
  using gl;
  using layout: Tile_Binding;

  // Framebuffer texture (same as before)
  glGenTextures(1, *world_texture); 
  glBindTexture(GL_TEXTURE_2D, world_texture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 
               cast(u32) resolution.x, cast(u32) resolution.y, 
               0, GL_RGBA, GL_UNSIGNED_BYTE, null);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  glGenFramebuffers(1, *framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, world_texture, 0);

  // Full‑screen quad VAO
  glGenVertexArrays(1, *quad_vao);
  glBindVertexArray(quad_vao);
  glGenBuffers(1, *quad_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, quad_vbo);
  quad_verts :: f32.[-1,-1, 1,-1, -1,1, 1,1];
  glBufferData(GL_ARRAY_BUFFER, size_of(type_of(quad_verts)), quad_verts.data, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, size_of(f32)*2, null);
  glBindVertexArray(0);

  // Compile tile shaders
  layout.shader = create_shader_program(TILE_VS, TILE_FS);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  return layout;
}

tile_render_pass :: (
  using layout: *Tile_Binding,
  using state:  *Simulation_State,
  camera:       Camera,
) {
  using gl;
  // Render to default framebuffer (the screen)
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, 0, xx state.window_size.x, xx state.window_size.y);
  glClearColor(0.0, 0.0, 0.0, 1.0);
  glClear(GL_COLOR_BUFFER_BIT);

  glUseProgram(shader);

  // Bind world texture to unit 0
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, world_texture);
  glUniform1i(glGetUniformLocation(shader, "u_worldTexture"), 0);
  glUniform2f(glGetUniformLocation(shader, "u_worldSize"),  state.resolution.x, state.resolution.y);
  glUniform2f(glGetUniformLocation(shader, "u_cameraPos"),  camera.pos.x, camera.pos.y);
  glUniform1f(glGetUniformLocation(shader, "u_cameraZoom"), camera.zoom);
  glUniform2f(glGetUniformLocation(shader, "u_windowSize"), state.window_size.x, state.window_size.y);
  glUniform1f(glGetUniformLocation(shader, "u_particleRadius"), PARTICLE_RADIUS);

  glBindVertexArray(quad_vao);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  glBindVertexArray(0);

  glUseProgram(0);
}

create_world_binding :: (particles_count: s64) -> World_Binding {
    using gl;
    using layout :World_Binding;
    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);

    // Quad VBO (static)
    glGenBuffers(1, *quad_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, quad_vbo);
    quad_verts :: f32.[-1,-1, 1,-1, -1,1, 1,1];
    glBufferData(GL_ARRAY_BUFFER, size_of(type_of(quad_verts)) , quad_verts.data, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, size_of(f32) * 2, null);

    // pos stream
    glGenBuffers(1, *pos_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, pos_vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vector2) * particles_count, null, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(Vector2), null);
    glVertexAttribDivisor(1, 1);
    
    // type stream
    glGenBuffers(1, *type_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, type_vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(u32) * particles_count, null, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(2);
    glVertexAttribIPointer(2, 1, GL_UNSIGNED_BYTE, size_of(u32), null);
    glVertexAttribDivisor(2, 1);
    glBindVertexArray(0);

    glGenBuffers     (1, *color_ssbo);
    glBindBuffer     (GL_SHADER_STORAGE_BUFFER, color_ssbo);
    glBufferData     (GL_SHADER_STORAGE_BUFFER, size_of(Vector4) * NUM_PARTICLE_TYPES, null, GL_DYNAMIC_DRAW);
    glBindBufferBase (GL_SHADER_STORAGE_BUFFER, 4, color_ssbo);
    glBindBuffer    (GL_SHADER_STORAGE_BUFFER, 0);

    shader = create_shader_program(WORLD_VS, WORLD_FS);
    return layout;
}

world_render_pass :: (
  using layout: *World_Binding,
  using state:  *Simulation_State,
  camera: Camera,
  instances:    Particle_Instances,
  framebuffer:  GLuint,
) {
  using gl;

  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glViewport(0, 0, xx resolution.x, xx resolution.y);
  glClearColor(0., 0., 0., 1.);
  glClear(GL_COLOR_BUFFER_BIT);

  glBindBuffer(GL_ARRAY_BUFFER, pos_vbo);
  glBufferData(GL_ARRAY_BUFFER, size_of(Vector2) * instances.count, instances.pos.data, GL_DYNAMIC_DRAW);

  glBindBuffer(GL_ARRAY_BUFFER, type_vbo);
  glBufferData(GL_ARRAY_BUFFER, size_of(u32) * instances.count, instances.type.data, GL_DYNAMIC_DRAW);

  glBindBuffer(GL_SHADER_STORAGE_BUFFER, color_ssbo);
  glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, size_of(Vector4) * particle_colors.count, particle_colors.data);

  glUseProgram(shader);
  glUniform2f (glGetUniformLocation(shader, "u_world_size"),  world_size.x, world_size.y);
  glUniform2f (glGetUniformLocation(shader, "u_resolution"),  resolution.x, resolution.y);

  glBindVertexArray(vao);
  glEnable(GL_BLEND); 
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, xx instances.count);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glBindVertexArray(0);
}


init_simulation :: (particles: *Particles, using state: Simulation_State) {
  seed := transmute(u64, to_seconds(current_time_monotonic()));
  // seed = 14183857;
  random_seed(seed);
  print("seed = %;\n", seed);

  array_resize(*particle_colors, NUM_PARTICLE_TYPES);
  for *particle_colors 
    it.* = .{xyz=hsl_to_rgb01(360. * it_index / (NUM_PARTICLE_TYPES + 1), 1., .7), w=1.};

  array_resize(*attraction_matrix, NUM_PARTICLE_TYPES * NUM_PARTICLE_TYPES);
  for *attraction_matrix it.* = random_get_within_range(-1., 1.);
  print("attraction_matrix = %\n", attraction_matrix);

  for 0..NUM_PARTICLES-1 add_particle(particles, 
    .{random_get_within_range(-world_size.x/2, world_size.x/2), 
      random_get_within_range(-world_size.y/2, world_size.y/2)},
    .{random_get_within_range(-10., 10.), 
      random_get_within_range(-10., 10.)},
    .{0,0},
    cast(u32) (random_get() % NUM_PARTICLE_TYPES),
  );


}

force :: (r: f32, a: f32, beta: f32 = 0.3) -> f32 {
  if r < beta return r / beta - 1.;
  if r < 1.   return a * (1. - abs(2.*r-1-beta)/(1-beta));
  return 0.;
}

main :: () {
  setenv("__NV_PRIME_RENDER_OFFLOAD",  "1",       1);
  setenv("__GLX_VENDOR_LIBRARY_NAME",  "nvidia",  1);
  setenv("DRI_PRIME",                  "1",       1);

  SDL_Init(SDL_INIT_VIDEO);
  state: Simulation_State;
  window := SDL_CreateWindow("An SDL2 window", 0, 0, xx state.window_size.x, xx state.window_size.y, SDL_WINDOW_OPENGL|SDL_WINDOW_RESIZABLE|SDL_WINDOW_FULLSCREEN);


  if window == null {
    print("Could not create window: %\n", to_string(SDL_GetError()));
    exit(1);
  }

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);
  gl_context := SDL_GL_CreateContext(window);
  if !gl_context {
    print( "Could not create OpenGL context: %\n", to_string(SDL_GetError()));
    exit(1);
  }  

  major, minor : GLint;
  glGetIntegerv(GL_MAJOR_VERSION, *major);
  glGetIntegerv(GL_MINOR_VERSION, *minor);
  if major < 4 || (major == 4 && minor < 3) {
    print("Compute shaders require OpenGL 4.3 or higher.\n");
    exit(1);
  }

  SDL_GL_SetSwapInterval(0);
  imgui_context := ImGui.CreateContext();
  ImGui_ImplSdl_Init(window);
  ImGui.StyleColorsDark(); 

  gl_load(*gl, SDL_GL_GetProcAddress);
  using gl;

  print ("GL Vendor = %\n", to_string(glGetString(GL_VENDOR)));
  print ("GL Version = %\n", to_string(glGetString(GL_VERSION)));
  print("GL Renderer = %\n", to_string(glGetString(GL_RENDERER)));

  particles: Particles;
  init_simulation(*particles, state);

  world_binding   := create_world_binding (particles.count);
  tile_binding    := create_tile_binding(state.resolution);
  compute_binding := create_compute_binding(particles.count, state.attraction_matrix);
  io := ImGui.GetIO();
  config: ImGui.ImFontConfig;
  ImGui.ImFontConfig.Constructor(*config);
  config.OversampleH = 4;
  config.OversampleV = 4;
  font := io.Fonts.AddFontFromFileTTF(io.Fonts, "assets/JetBrainsMonoNerdFont-Regular.ttf", 24.0, *config, null);
  io.FontDefault = font;

  camera: Camera;
  state.time_last_frame = current_time_monotonic();
  while !state.exit {
    time_this_frame := current_time_monotonic();
    state.dt = xx to_float64_seconds(time_this_frame - state.time_last_frame);
    state.time_last_frame = time_this_frame;

    event : SDL_Event;
    while SDL_PollEvent(*event) {
      ImGui_ImplSdl_ProcessEvent(*event);
      if !io.WantCaptureMouse && !io.WantCaptureKeyboard {
        if event.type == {
        case SDL_WINDOWEVENT;
          if event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED
            state.window_size = .{xx event.window.data1, xx event.window.data2};
        case SDL_MOUSEBUTTONDOWN;
          if event.button.button == SDL_BUTTON_LEFT {
            camera.is_panning = true;
            camera.pan_start_mouse  = .{xx event.button.x, xx event.button.y};
            camera.pan_start_camera = camera.pos;
          }
        case SDL_MOUSEBUTTONUP;
          if event.button.button == SDL_BUTTON_LEFT camera.is_panning = false;
        case SDL_MOUSEMOTION;
          if camera.is_panning {
            mouse := Vector2.{xx event.motion.x, xx event.motion.y};
            world_now    := screen_to_world(mouse, state, camera);
            world_start  := screen_to_world(camera.pan_start_mouse, state, camera);
            camera.pos    = camera.pan_start_camera + (world_start - world_now);
          }
        case SDL_MOUSEWHEEL;
          mx, my: s32;
          SDL_GetMouseState(*mx, *my);
          mouse := Vector2.{xx mx, xx my};
          world_before := screen_to_world(mouse, state, camera);
          zoom_factor  := ifx event.wheel.y > 0 then 1.1 else 1./1.1;
          camera.zoom  *= zoom_factor;
          camera.zoom   = clamp(camera.zoom, 0.5 / PIXELS_PER_WORLD_UNIT, 20. / PIXELS_PER_WORLD_UNIT);
          world_after  := screen_to_world(mouse, state, camera);
          camera.pos   += world_before - world_after;
        case SDL_KEYUP; if event.key.keysym.sym == SDLK_ESCAPE state.exit = true;
        }
      }

      if event.type == {
        case SDL_QUIT; state.exit = true;
      }
    }

    ImGui_ImplSdl_NewFrame(window);
    ImGui.NewFrame();
    ImGui.SetNextWindowPos(.{10, 10}, ImGui.Cond.FirstUseEver, .{0, 0});
    ImGui.SetNextWindowSize(.{200, 80}, ImGui.Cond.FirstUseEver);
    free_id : s32 = 1;
    if ImGui.Begin("Performance", null, ImGui.WindowFlags.NoTitleBar | ImGui.WindowFlags.AlwaysAutoResize) {
      ImGui.TextColored(.{0, 1, 0, 1}, "FPS: %", cast(s64) io.Framerate);
      ImGui.Text("Particles: %", particles.count);

      if ImGui.TreeNode("Attraction Matrix") {
        ImGui.PushStyleVar(.CellPadding, ImGui.ImVec2.{4, 4});
        ImGui.BeginTable("Attraction Matrix", NUM_PARTICLE_TYPES + 1);
        ImGui.TableNextRow();
        for c: 1..NUM_PARTICLE_TYPES {
          ImGui.TableSetColumnIndex(xx c);
          ImGui.PushID(free_id); free_id += 1;
          ImGui.SetNextItemWidth(ImGui.GetContentRegionAvail().x);
          ImGui.ColorEdit3("", *state.particle_colors[c-1].xyz.component, ImGui.ColorEditFlags.NoLabel | ImGui.ColorEditFlags.NoInputs);
          ImGui.PopID();
        }
        for r: 0..NUM_PARTICLE_TYPES-1 {
          ImGui.TableNextRow();
          ImGui.TableSetColumnIndex(0);
          ImGui.PushID(free_id); free_id += 1;
          ImGui.ColorEdit3("", *state.particle_colors[r].xyz.component, ImGui.ColorEditFlags.NoLabel | ImGui.ColorEditFlags.NoInputs);
          ImGui.PopID();
          for c: 1..NUM_PARTICLE_TYPES {
            ImGui.TableSetColumnIndex(xx c);
            ImGui.PushID(free_id); free_id += 1;
            ImGui.SetNextItemWidth(ImGui.GetContentRegionAvail().x);
            a := state.attraction_matrix[r * NUM_PARTICLE_TYPES + c - 1];
            ImGui.PushStyleColor(.SliderGrab, ImGui.ImVec4.{0, 0, 0, 0});
            ImGui.PushStyleColor(.SliderGrabActive, ImGui.ImVec4.{0, 0, 0, 0.3});
            ImGui.PushStyleColor(.FrameBg,        ImGui.ImVec4.{0.5 - a/2, a/2+0.5, 0, pow(abs(a), 0.5)});
            ImGui.PushStyleColor(.FrameBgHovered, ImGui.ImVec4.{0.5 - a/2, a/2+0.5, 0, pow(abs(a), 0.5)});
            ImGui.PushStyleColor(.FrameBgActive,  ImGui.ImVec4.{0.5 - a/2, a/2+0.5, 0, pow(abs(a), 0.5)});
            ImGui.SliderFloat("", *state.attraction_matrix[r * NUM_PARTICLE_TYPES + c - 1], -1., 1., "");
            if ImGui.IsItemHovered() || ImGui.IsItemActive()
              ImGui.SetTooltip("%", formatFloat(state.attraction_matrix[r * NUM_PARTICLE_TYPES + c - 1], trailing_width=2));
            ImGui.PopStyleColor(5);
            ImGui.PopID();
          }
        }
        ImGui.EndTable();
        ImGui.PopStyleVar();
        ImGui.TreePop();
      }
    }
    ImGui.End();

    compute_pass(compute_binding, *particles, state);
    wrap_count := wrap_particle_instances(*particles.instances, state.world_size);
    defer remove_n_instances_from_end(*particles.instances, wrap_count);
    world_render_pass(*world_binding, *state, camera, particles.instances, tile_binding.framebuffer);
    tile_render_pass (*tile_binding,  *state, camera);

    ImGui.Render();
    ImGui_ImplSdl_RenderDrawLists(ImGui.GetDrawData());
    SDL_GL_SwapWindow(window);
    reset_temporary_storage();
  }
  SDL_DestroyWindow(window);
  SDL_Quit();
}

screen_to_world :: (screen: Vector2, state: Simulation_State, camera: Camera) -> Vector2 {
  screen_center := state.window_size * 0.5;
  offset := (screen - screen_center) / camera.zoom;
  return camera.pos + .{offset.x, -offset.y};
}

transmute :: inline ($toT: Type, x: $T) -> toT {
    union { from : T = ---; to : toT = ---; }    
    from = x;
    return to;
}

hsl_to_rgb01 :: (h: f32, s: f32, l: f32) -> Vector3 {
  c  := (1 - abs(2*l - 1)) * s;
  hp := h / 60.0;
  x  := c * (1 - abs(hp - floor(hp/2) * 2 - 1));
  m  := l - c/2;
  r1, g1, b1: f32;
  sector := cast(s32) hp; 
  if sector ==  {
    case 0; r1, g1, b1 = c, x, 0;
    case 1; r1, g1, b1 = x, c, 0;
    case 2; r1, g1, b1 = 0, c, x;
    case 3; r1, g1, b1 = 0, x, c;
    case 4; r1, g1, b1 = x, 0, c;
    case 5; r1, g1, b1 = c, 0, x;
    case;   r1, g1, b1 = c, 0, x;
  }

  return Vector3.{r1 + m, g1 + m, b1 + m};
}

#import "Basic";
#import "POSIX";
#import "String";
#import "SDL";
#import "GL";
#import "Math";
#import "Random";
#load "imgui_sd_gl.jai";
