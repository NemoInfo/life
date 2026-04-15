WORLD_VS :: #run tprint(#string GLSL
#version 330 core

layout (location = 0) in vec2 vertex_pos;
layout (location = 1) in vec2 particle_pos;
layout (location = 2) in int  particle_type;

out vec2 out_vertex_pos;
out vec4 out_vertex_col; 

uniform vec2  u_resolution;
uniform vec2  u_world_size;
uniform vec4  u_color_types[%2];
const float PARTICLE_RADIUS = %1;

void main() {
  out_vertex_pos = vertex_pos;
  out_vertex_col = u_color_types[particle_type];

  vec2 world_pos  = particle_pos + vertex_pos * PARTICLE_RADIUS;
  vec2 scale   = u_resolution / u_world_size;
  vec2 fbo_pos = (world_pos + u_world_size * 0.5) * scale;

  vec2 ndc = (fbo_pos / u_resolution ) * 2.0 - 1.0;
  ndc.y    = -ndc.y;
  gl_Position = vec4(ndc, 0.0, 1.0);
}
GLSL, PARTICLE_RADIUS, MAX_PARTICLE_TYPES);

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

  // 3. Distance to tile edges in UV space
  vec2 distToLeft   = tileUV;
  vec2 distToRight  = 1.0 - tileUV;

  // 4. Sample base tile
  vec4 baseColor = texture(u_worldTexture, tileUV);
  bool isOriginal = (tileIndex == camTile);
  vec3 rgb = isOriginal ? baseColor.rgb : grayscale(baseColor.rgb);
    
  fragColor = vec4(rgb, baseColor.a);
}
GLSL

f32 :: float32;
f64 :: float64;

PARTICLE_RADIUS       :: 2.;
NUM_PARTICLE_TYPES    :: 5;
MAX_PARTICLE_TYPES    :: 32;
NUM_PARTICLES         :: 1200;
PIXELS_PER_WORLD_UNIT :: 10;
R_MAX                 :: 100.;
T_HALF                :: 1.5;

A : [NUM_PARTICLE_TYPES][NUM_PARTICLE_TYPES] f32;
PARTICLE_COLORS    : [MAX_PARTICLE_TYPES] Vector4;

Simulation_State:  : struct {
  world_size:      Vector2 = .{1920., 1080.};
  resolution:      Vector2 = #run .{1920., 1080.} * PIXELS_PER_WORLD_UNIT;
  window_size:     Vector2 = .{1920., 1080.};
  dt:              f32;
  time_last_frame: Apollo_Time;
  exit:            bool = false;
  fps_counter:     int = 0;
  fps_timer:       f32 = 0;
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
  type: [..] u8;
  count: s64;
}

Particles :: struct {
  #as using instances: Particle_Instances;
  acc:  [..] Vector2;
  vel:  [..] Vector2;
}

World_Binding_Layout :: struct {
  vao:      GLuint;
  quad_vbo: GLuint;
  pos_vbo:  GLuint;
  type_vbo: GLuint;
  shader:   GLuint;
}

Tile_Binding_Layout :: struct {
  framebuffer:   GLuint;
  world_texture: GLuint;
  quad_vao:      GLuint;
  quad_vbo:      GLuint;
  shader:        GLuint;
}

add_instance :: (instances: *Particle_Instances, pos: Vector2, type: u8) {
  array_add(*instances.pos,  pos);
  array_add(*instances.type, type);
  instances.count += 1;
}

add_particle :: (particles: *Particles, pos: Vector2, vel: Vector2, acc: Vector2, type: u8) {
  array_add(*particles.pos,  pos);
  array_add(*particles.vel,  vel);
  array_add(*particles.acc,  acc);
  array_add(*particles.type, type);
  particles.count += 1;
}

wrap_particle_instances :: (instances: Particle_Instances, world_size: Vector2) -> Particle_Instances {
  total: Particle_Instances;

  for 0..instances.count-1 {
    add_instance(*total, instances.pos[it], instances.type[it]);
    if instances.pos[it].x > world_size.x * 0.5 - PARTICLE_RADIUS
      add_instance(*total, instances.pos[it] - .{world_size.x,0}, instances.type[it]);
    if instances.pos[it].x < -world_size.x * 0.5 + PARTICLE_RADIUS
      add_instance(*total, instances.pos[it] + .{world_size.x,0}, instances.type[it]);
    if instances.pos[it].y > world_size.y * 0.5 - PARTICLE_RADIUS
      add_instance(*total, instances.pos[it] - .{0,world_size.y}, instances.type[it]);
    if instances.pos[it].y < -world_size.y * 0.5 + PARTICLE_RADIUS
      add_instance(*total, instances.pos[it] + .{0,world_size.y}, instances.type[it]);
  }

  return total;
}

update_particles :: (using particles: *Particles, using state: Simulation_State) {
  for i: 0..count-1 {
    acc[i] = Vector2.{};
    for j: 0..count-1 {
      if i == j continue;
      r       := pos[j] - pos[i];
      r.x -= world_size.x * xx (r.x >  world_size.x * 0.5);
      r.x += world_size.x * xx (r.x < -world_size.x * 0.5);
      r.y -= world_size.y * xx (r.y >  world_size.y * 0.5);
      r.y += world_size.y * xx (r.y < -world_size.y * 0.5);
      r_len   := length(r);
      acc[i] += r / r_len * force(r_len / R_MAX, A[type[i]][type[j]]);
    }
    vel[i]    = vel[i] * pow(1./2., dt / T_HALF) + acc[i] * dt;
    pos[i]   += vel[i] * dt;
    pos[i].x -= world_size.x * xx (pos[i].x >  world_size.x  * 0.5);
    pos[i].x += world_size.x * xx (pos[i].x < -world_size.x  * 0.5);
    pos[i].y -= world_size.y * xx (pos[i].y >  world_size.y * 0.5);
    pos[i].y += world_size.y * xx (pos[i].y < -world_size.y * 0.5);
  }
}

// @TODO
//   ✔  remove radius and maybe color from instance, maybe bake them into the shader?
//   ✔  implement 2D Camera, switch to world coordonates
//   ✔  attraction laws
//   - gui & tools
//
// @PERFORMANCE:
//   - async simulation thread 
//   - multi-processing for the particle-particle forces , maybe even push to compute shader? 
//   - hierarichal structure 
//
// @QUALITY:
//   - break the monolith, refactor game loop
//   - async logging

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

create_tile_binding_layout :: (resolution: Vector2) -> Tile_Binding_Layout {
  using gl;
  using layout: Tile_Binding_Layout;

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
  using layout: *Tile_Binding_Layout,
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

create_world_binding_layout :: (particles_count: s64) -> World_Binding_Layout {
    using gl;
    using layout : World_Binding_Layout;
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
    glBufferData(GL_ARRAY_BUFFER, size_of(Vector2) * particles_count * 5, null, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(Vector2), null);
    glVertexAttribDivisor(1, 1);
    
    // type stream
    glGenBuffers(1, *type_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, type_vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(u8) * particles_count * 5, null, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(2);
    glVertexAttribIPointer(2, 1, GL_UNSIGNED_BYTE, size_of(u8), null);
    glVertexAttribDivisor(2, 1);

    glBindVertexArray(0);
    shader = create_shader_program(WORLD_VS, WORLD_FS);
    return layout;
}

world_render_pass :: (
  using layout: *World_Binding_Layout,
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
  // @TODO: with a dynamic number of particles u have to call glBufferData again
  // glBufferData(GL_ARRAY_BUFFER, size_of(Vector2) * instances.count, null, GL_DYNAMIC_DRAW);
  glBufferSubData(GL_ARRAY_BUFFER,  0, xx (size_of(Vector2) * instances.count), instances.pos.data);

  glBindBuffer(GL_ARRAY_BUFFER, type_vbo);
  // glBufferData(GL_ARRAY_BUFFER, size_of(u8) * instances.count, null, GL_DYNAMIC_DRAW);
  glBufferSubData(GL_ARRAY_BUFFER,  0, xx (size_of(u8) * instances.count), instances.type.data);

  glUseProgram(shader);
  glUniform2f (glGetUniformLocation(shader, "u_world_size"),  world_size.x, world_size.y);
  glUniform2f (glGetUniformLocation(shader, "u_resolution"),  resolution.x, resolution.y);
  glUniform4fv(glGetUniformLocation(shader, "u_color_types"), MAX_PARTICLE_TYPES, *PARTICLE_COLORS[0].x);

  glBindVertexArray(vao);
  glEnable(GL_BLEND); 
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, xx instances.count);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glBindVertexArray(0);
}


init_simulation :: (particles: *Particles, world_size: Vector2) {
  random_seed(transmute(u64, to_seconds(current_time_monotonic())));

  for *PARTICLE_COLORS if it_index < NUM_PARTICLE_TYPES
    it.* = .{
      random_get_zero_to_one(),
      random_get_zero_to_one(),
      random_get_zero_to_one(),
      1.,
    };

  for 0..NUM_PARTICLES-1 add_particle(particles, 
    .{random_get_within_range(-world_size.x/2, world_size.x/2), 
      random_get_within_range(-world_size.y/2, world_size.y/2)},
    .{random_get_within_range(-10., 10.), 
      random_get_within_range(-10., 10.)},
    .{0,0},
    cast(u8) (random_get() % NUM_PARTICLE_TYPES),
  );

  for *A for *(it.*) it.* = random_get_within_range(-1., 1.) * 2.;
  // A = .[.[0.744254, -0.822552, -0.418013, -0.305391, 0.373153], .[0.266228, 0.903647, -0.11726, -0.119418, -0.623262], .[-0.062638, 0.277877, 0.92583, -0.635536, 0.524239], .[0.866223, 0.08902, -0.875463, 0.288696, -0.506347], .[0.846281, -0.477031, 0.351822, 0.487101, 0.738286]];
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
    return;
  }

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);

  gl_context := SDL_GL_CreateContext(window);
  if !gl_context {
    print( "Could not create OpenGL context: %\n", to_string(SDL_GetError()));
    return;
  }  

  SDL_GL_SetSwapInterval(0);

  gl_load(*gl, SDL_GL_GetProcAddress);
  using gl;

  print ("GL Vendor = %\n", to_string(glGetString(GL_VENDOR)));
  print ("GL Version = %\n", to_string(glGetString(GL_VERSION)));
  print("GL Renderer = %\n", to_string(glGetString(GL_RENDERER)));

  particles: Particles;
  init_simulation(*particles, state.world_size);

  world_binding_layout := create_world_binding_layout (particles.count);
  tile_binding_layout  := create_tile_binding_layout(state.resolution);

  camera: Camera;
  state.time_last_frame = current_time_monotonic();
  while !state.exit {
    time_this_frame := current_time_monotonic();
    state.dt = xx to_float64_seconds(time_this_frame - state.time_last_frame);
    state.time_last_frame = time_this_frame;
    state.fps_timer   += state.dt;
    state.fps_counter += 1;
    if state.fps_timer > 1. {
      title := tprint("Particle Sim | FPS: %\0", state.fps_counter);
      SDL_SetWindowTitle(window, title.data);
      state.fps_timer, state.fps_counter = 0, 0;
    }

    event : SDL_Event;
    while SDL_PollEvent(*event) {
      if event.type == {
        case SDL_QUIT; state.exit = true;
        case SDL_KEYUP; if event.key.keysym.sym == SDLK_ESCAPE state.exit = true;
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
            camera.pos.x  = clamp(camera.pos.x, -state.resolution.x/4, state.resolution.x/4);
            camera.pos.y  = clamp(camera.pos.y, -state.resolution.y/4, state.resolution.y/4);
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
          camera.pos.x  = clamp(camera.pos.x, -state.resolution.x/4, state.resolution.x/4);
          camera.pos.y  = clamp(camera.pos.y, -state.resolution.y/4, state.resolution.y/4);
      }
    }

    update_particles (*particles, state);
    instances := wrap_particle_instances(particles.instances, state.world_size);
    defer array_free(instances.pos);
    defer array_free(instances.type);

    world_render_pass(*world_binding_layout, *state, camera, instances, tile_binding_layout.framebuffer);
    tile_render_pass (*tile_binding_layout,  *state, camera);

    SDL_GL_SwapWindow(window);
    
    reset_temporary_storage();
  }

  print("A = .%\n", A);
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

#import "Basic";
#import "POSIX";
#import "String";
#import "SDL";
#import "GL";
#import "Math";
#import "Random";
