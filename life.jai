// u_resolution still being here feels wierd
WORLD_VS :: #run tprint(#string GLSL
#version 330 core

layout (location = 0) in vec2 vertex_pos;
layout (location = 1) in vec2 particle_pos;
layout (location = 2) in int  particle_type;

out vec2 out_vertex_pos;
out vec4 out_vertex_col; 

uniform vec2  u_resolution;
uniform vec4  u_color_types[%2];
// uniform vec2  u_camera_pos;
// uniform float u_camera_zoom;

const float PARTICLE_RADIUS = %1;

void main() {
  out_vertex_pos = vertex_pos;
  out_vertex_col = u_color_types[particle_type];

  vec2 world_pos  = particle_pos + vertex_pos * PARTICLE_RADIUS;
  // vec2 cam_pos    = (world_pos - u_camera_pos) * u_camera_zoom;
  vec2 screen_pos = world_pos + u_resolution * 0.5;

  vec2 ndc = (screen_pos / u_resolution ) * 2.0 - 1.0;
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
  float alpha = 1.0 - smoothstep(-0.2, 0.0, d);
  frag_color = vec4(out_vertex_col.rgb, out_vertex_col.a * alpha);
}
GLSL

f32 :: float32;
f64 :: float64;

PARTICLE_RADIUS :: 5.;
MAX_PARTICLE_TYPES :: 32;
NUM_PARTICLE_TYPES :: 5;
PARTICLE_COLORS : [MAX_PARTICLE_TYPES] Vector4;
NUM_PARTICLES :: 10_000;

Simulation_State :: struct {
  world_size  : Vector2 = .{1800., 1000.};
  window_size : Vector2 = .{1920., 1080.};
  dt          : f32;
}

Camera_Uniform :: struct {
  #as using pos:  Vector2;  // world space point at screen centre
  zoom: f32 = 1.;           // pixels per world unit
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
  vao          : GLuint;
  quad_vbo     : GLuint;
  pos_vbo      : GLuint;
  type_vbo     : GLuint;
  shader       : GLuint;
}

Tile_Binding_Layout :: struct {
  framebuffer: GLuint;
  world_texture: GLuint;
  quad_vao: GLuint;
  quad_vbo: GLuint;
  shader: GLuint;
}

add_particle :: (particles: *Particles, pos: Vector2, vel: Vector2, acc: Vector2, type: u8) {
  array_add(*particles.pos,  pos);
  array_add(*particles.vel,  vel);
  array_add(*particles.acc,  acc);
  array_add(*particles.type, type);
  particles.count += 1;
}

update_particles :: (using particles: *Particles, using state: Simulation_State) {
  for 0..count-1 {
    vel[it] += acc[it] * dt;
    pos[it] += vel[it] * dt;
    pos[it].x -= world_size.x * xx (pos[it].x >  world_size.x  * 0.5);
    pos[it].x += world_size.x * xx (pos[it].x < -world_size.x  * 0.5);
    pos[it].y -= world_size.y * xx (pos[it].y >  world_size.y * 0.5);
    pos[it].y += world_size.y * xx (pos[it].y < -world_size.y * 0.5);
  }
}

// @TODO
//   ✔  remove radius and maybe color from instance, maybe bake them into the shader?
//   ✔  implement 2D Camera, switch to world coordonates
//   3. attraction laws
//   4. hierarichal structure 
//   5. gui & tools
//
// @QUALITY:
//   - break the monolith, refactor game loop
//   - simulation struct, world size, dt
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

create_tile_binding_layout :: (world_size: Vector2) -> Tile_Binding_Layout {
  using gl;
  using layout: Tile_Binding_Layout;

  glGenTextures(1, *world_texture); 
  glBindTexture(GL_TEXTURE_2D, world_texture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 
               cast(u32) world_size.x, cast(u32) world_size.y, 
               0, GL_RGBA, GL_UNSIGNED_BYTE, null);

  glGenFramebuffers(1, *framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, world_texture, 0);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  return layout;
}

tile_render_pass :: (
  using layout: *Tile_Binding_Layout,
  using state:  *Simulation_State,
  camera:       Camera,
) {
  glViewport(0, 0, xx window_size.x, xx window_size.y);
  glClearColor(0.0, 0.0, 0.0, 1.0);
  glClear(GL_COLOR_BUFFER_BIT);
}

create_world_binding_layout :: (particles: *Particles) -> World_Binding_Layout {
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
    glBufferData(GL_ARRAY_BUFFER, size_of(Vector2) * particles.count, null, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(Vector2), null);
    glVertexAttribDivisor(1, 1);
    
    // type stream
    glGenBuffers(1, *type_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, type_vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(u8) * particles.count, null, GL_DYNAMIC_DRAW);
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
  instances:    Particle_Instances,
  framebuffer:  GLuint,
) {
  using gl;

  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glViewport(0, 0, xx world_size.x, xx world_size.y);
  glClearColor(0., 0., 0., 1.);
  glClear(GL_COLOR_BUFFER_BIT);

  glBindBuffer(GL_ARRAY_BUFFER, pos_vbo);
  glBufferSubData(GL_ARRAY_BUFFER,  0, xx (size_of(Vector2) * instances.count), instances.pos.data);

  glBindBuffer(GL_ARRAY_BUFFER, type_vbo);
  glBufferSubData(GL_ARRAY_BUFFER,  0, xx (size_of(u8) * instances.count), instances.type.data);

  glUseProgram(shader);
  glUniform2f (glGetUniformLocation(shader, "u_resolution"),  window_size.x, window_size.y);
  glUniform4fv(glGetUniformLocation(shader, "u_color_types"), MAX_PARTICLE_TYPES, *PARTICLE_COLORS[0].x);
  // glUniform2f (glGetUniformLocation(shader, "u_camera_pos"),  camera.x, camera.y);
  // glUniform1f (glGetUniformLocation(shader, "u_camera_zoom"), camera.zoom);

  glBindVertexArray(vao);
  glEnable(GL_BLEND); 
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, xx instances.count);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glBindVertexArray(0);
}

main :: () {
  setenv("__NV_PRIME_RENDER_OFFLOAD",  "1",       1);
  setenv("__GLX_VENDOR_LIBRARY_NAME",  "nvidia",  1);
  setenv("DRI_PRIME",                  "1",       1);

  SDL_Init(SDL_INIT_VIDEO);
  state: Simulation_State;
  window := SDL_CreateWindow("An SDL2 window", 0, 0, xx state.window_size.x, xx state.window_size.y, SDL_WINDOW_OPENGL|SDL_WINDOW_RESIZABLE);

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
  random_seed(transmute(u64, to_seconds(current_time_monotonic())));

  for *PARTICLE_COLORS if it_index < NUM_PARTICLE_TYPES
    it.* = .{
      random_get_zero_to_one(),
      random_get_zero_to_one(),
      random_get_zero_to_one(),
      1.,
    };

  for 0..NUM_PARTICLES add_particle(*particles, 
    .{random_get_within_range(-state.world_size.x/2, state.world_size.x/2), 
      random_get_within_range(-state.world_size.y/2, state.world_size.y/2)},
    .{random_get_within_range(-100., 100.), 
      random_get_within_range(-100., 100.)},
    .{random_get_within_range(-10., 10.), 
      random_get_within_range(-10., 10.)},
    cast(u8) (random_get() % NUM_PARTICLE_TYPES),
  );

  world_binding_layout := create_world_binding_layout (*particles);
  tile_binding_layout  := create_tile_binding_layout(state.world_size);

  camera: Camera;
  is_panning: bool;
  pan_start_mouse: Vector2;
  pan_start_camera: Vector2;
  time_last_frame := current_time_monotonic();
  exit := false;
  fps_counter : int = 0;
  fps_timer   : f32 = 0;
  while !exit {
    time_this_frame := current_time_monotonic();
    dt := time_this_frame - time_last_frame;
    state.dt = xx to_float64_seconds(dt);
    time_last_frame = time_this_frame;
    fps_timer   += state.dt;
    fps_counter += 1;
    if fps_timer > 1. {
      title := tprint("Particle Sim | FPS: %\0", fps_counter);
      SDL_SetWindowTitle(window, title.data);
      fps_timer, fps_counter = 0, 0;
    }

    event : SDL_Event;
    while SDL_PollEvent(*event) {
      if event.type == {
        case SDL_QUIT; exit = true;
        case SDL_KEYUP;
          if event.key.keysym.sym == SDLK_ESCAPE exit = true;
        case SDL_WINDOWEVENT;
          if event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED
            state.window_size = .{xx event.window.data1, xx event.window.data2};
        case SDL_MOUSEBUTTONDOWN;
          if event.button.button == SDL_BUTTON_LEFT {
            is_panning = true;
            pan_start_mouse  = .{xx event.button.x, xx event.button.y};
            pan_start_camera = camera.pos;
          }
        case SDL_MOUSEBUTTONUP;
          if event.button.button == SDL_BUTTON_LEFT is_panning = false;
        case SDL_MOUSEMOTION;
          if is_panning {
            dm := Vector2.{xx event.motion.x, xx event.motion.y} - pan_start_mouse;
            camera.pos = pan_start_camera - .{dm.x, dm.y} / camera.zoom;
          }
        case SDL_MOUSEWHEEL; 
          mx, my: s32;
          SDL_GetMouseState(*mx, *my);
          mp: Vector2 = .{xx mx, xx my};
          mouse_screen := mp - .{xx state.window_size.x, xx state.window_size.y} * 0.5;
          world_before := camera.pos + mouse_screen / camera.zoom;
          zoom_factor  := ifx event.wheel.y > 0 then 1.1 else 1./1.1;
          camera.zoom  *= zoom_factor;
          camera.zoom   = clamp(camera.zoom, 0.05, 20.);
          world_after  := camera.pos + mouse_screen / camera.zoom;
          camera.pos   += world_before - world_after;
      }
    }

    update_particles (*particles, state);

    world_render_pass(*world_binding_layout, *state, particles.instances, tile_binding_layout.framebuffer);
    tile_render_pass (*tile_binding_layout,  *state, camera);

    SDL_GL_SwapWindow(window);
  }

  SDL_DestroyWindow(window);
  SDL_Quit();
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
#import "Random";
#import "Random";
