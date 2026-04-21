PARTICLE_RADIUS           :: 2.;
R_MAX                     :: 100.;
T_HALF                    :: 0.04;
PARTICLES_PER_WORK_GROUPS :: 256;

Simulation_State :: struct {
  world_size:        Vector2 = .{1920*3., 1080*3.};
  resolution:        Vector2;
  window_size:       Vector2 = .{1920., 1080.};
  dt:                f32;
  time_last_frame:   Apollo_Time;
  exit:              bool = false;
  paused:            bool = false;
  gui_hidden:        bool = false;
  tool:              Tool;
}

ToolType :: enum s32 {
  None;
  Repel;
  Attract;
  Spawn;
  Delete;
}
TOOL_NAMES :: #run enum_names(ToolType);

Tool :: struct {
  type:   ToolType;
  shape:  ShapeType;
  radius: f32 = 100.;
  force:  f32 = 0.2;
  count:  s32 = 100;
  color:  s64 = -1;
}

ShapeType :: enum s64 {
  Circle;
  Square;
}
SHAPE_NAMES :: #run enum_names(ShapeType);

Camera_Uniform :: struct {
  #as using pos:  Vector2;   // world space point at screen centre
  zoom: f32 = 1.; // pixels per world unit
}

Camera :: struct {
  #as using uniform: Camera_Uniform;
  is_panning:        bool;
  pan_start_mouse:   Vector2;
  pan_start_camera:  Vector2;
}

Particles :: struct {
  pos:    [..] Vector2;
  type:   [..] u32;
  #overlay (pos.count) count: s64;
  vel:    [..] Vector2;
  atr:    [..] f32;
  colors: [..] Vector4;
  #overlay (colors.count) num_types: s64;
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

particles_add_ghost :: (using particles: *Particles, new_pos: Vector2, new_type: u32) {
  array_add(*pos,  new_pos);
  array_add(*type, new_type);
}

particles_pop_ghost :: (using particles: *Particles, n :s64= 1) {
  pos.count  -= n;
  type.count -= n;
}

particles_add :: (particles: *Particles, pos: Vector2 = .{}, vel: Vector2 = .{}, type: u32 = 0) {
  array_add(*particles.pos,  pos);
  array_add(*particles.vel,  vel);
  array_add(*particles.type, type);
}

particles_free :: (using particles: *Particles) {
  array_free(pos);
  array_free(vel);
  array_free(type);
  array_free(colors);
  array_free(atr);
}

particles_delete :: inline (using particles: *Particles, it: s64) {
  n := particles.count - 1;
  pos[it]  = pos[n];  pos.count  -= 1;
  vel[it]  = vel[n];  vel.count  -= 1;
  type[it] = type[n]; type.count -= 1;
}

wrap_distance :: (r: *Vector2, world_size: Vector2) {
  r.* -= world_size * (r >  world_size * 0.5);
  r.* += world_size * (r < -world_size * 0.5);
}

particles_add_wrap_ghosts :: (particles: *Particles, world_size: Vector2) -> s64 {
  init_count := particles.count;
  for 0..init_count-1 {
    if particles.pos[it].x > world_size.x * 0.5 - PARTICLE_RADIUS
      particles_add_ghost(particles, particles.pos[it] - .{world_size.x,0}, particles.type[it]);
    if particles.pos[it].x < -world_size.x * 0.5 + PARTICLE_RADIUS
      particles_add_ghost(particles, particles.pos[it] + .{world_size.x,0}, particles.type[it]);
    if particles.pos[it].y > world_size.y * 0.5 - PARTICLE_RADIUS
      particles_add_ghost(particles, particles.pos[it] - .{0,world_size.y}, particles.type[it]);
    if particles.pos[it].y < -world_size.y * 0.5 + PARTICLE_RADIUS
      particles_add_ghost(particles, particles.pos[it] + .{0,world_size.y}, particles.type[it]);
  }
  return particles.count - init_count;
}

init_simulation :: (using particles: *Particles, using state: *Simulation_State, num_particles: s64 = 20_000, num_particle_types : s64 = 6, seed : u64 = 0) {
  if seed == 0 seed = transmute(u64, to_seconds(current_time_monotonic()));
  random_seed(seed);
  randomize_particle_colors(particles, num_particles, num_particle_types);
  randomize_attraction_matrix(particles);
  randomize_particle_positions(particles, state, num_particles, num_particle_types);
}

wrap_world_pos :: inline (world_pos: Vector2, world_size: Vector2) -> Vector2 {
  return fmod_cycling(world_pos + world_size / 2, world_size) - world_size / 2;
}

randomize_particle_colors :: (using particles: *Particles, num_particles : s64 = 0, num_particle_types : s64 = 0) {
  if num_particle_types == 0 num_particle_types = particles.num_types;
  array_free(colors);
  array_resize(*colors, num_particle_types);
  for *colors it.* = .{xyz=hsl_to_rgb01(360. * it_index / (num_particle_types + 1), 1., .7), w=1.};
}

randomize_particle_positions :: (using particles: *Particles, using state: *Simulation_State, num_particles : s64 = 0, num_particle_types : s64 = 0) {
  if num_particles == 0 num_particles = particles.count;
  if num_particle_types == 0 num_particle_types = particles.num_types;
  array_resize(*pos, num_particles);
  array_resize(*vel, num_particles);
  array_resize(*type, num_particles);
  for 0..num_particles-1 {
    pos[it] = .{random_get_within_range(-world_size.x/2, world_size.x/2), 
                random_get_within_range(-world_size.y/2, world_size.y/2)};
    vel[it] = .{random_get_within_range(-10., 10.), 
                random_get_within_range(-10., 10.)};
    type[it] = cast(u32) (random_get() % xx num_particle_types);
  }
}

randomize_attraction_matrix :: (using particles: Particles) {
  array_free(atr);
  array_resize(*atr, particles.num_types * particles.num_types);
  for *atr it.* = random_get_within_range(-1., 1.);
}

main :: () {
  posix.setenv("__NV_PRIME_RENDER_OFFLOAD", "1",      1);
  posix.setenv("__GLX_VENDOR_LIBRARY_NAME", "nvidia", 1);
  posix.setenv("DRI_PRIME",                 "1",      1);

  SDL_Init(SDL_INIT_VIDEO);
  state: Simulation_State;
  window := SDL_CreateWindow("Particle Life", 0, 0, xx state.window_size.x, xx state.window_size.y, SDL_WINDOW_OPENGL|SDL_WINDOW_RESIZABLE|SDL_WINDOW_FULLSCREEN);

  if window == null panic("Could not create window: %", to_string(SDL_GetError()));

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);
  gl_context := SDL_GL_CreateContext(window);
  if !gl_context panic( "Could not create OpenGL context: %", to_string(SDL_GetError()));

  major, minor : GLint;
  glGetIntegerv(GL_MAJOR_VERSION, *major);
  glGetIntegerv(GL_MINOR_VERSION, *minor);
  if major < 4 || (major == 4 && minor < 3) panic("Compute shaders require OpenGL 4.3 or higher.");

  SDL_GL_SetSwapInterval(0);
  imgui_context := ImGui.CreateContext();
  ImGui_ImplSdl_Init(window);
  ImGui.StyleColorsDark(); 

  gl_load(*gl, SDL_GL_GetProcAddress);

  println("GL Version = %", to_string(glGetString(GL_VERSION)));
  println("GL Renderer = %", to_string(glGetString(GL_RENDERER)));

  particles: Particles; defer particles_free(*particles);
  camera: Camera;
  init_simulation(*particles, *state);

  world_binding   := create_world_binding(*particles);
  state.resolution = compute_world_tex_resolution(state.world_size, camera.zoom);
  tile_binding    := create_tile_binding(state.resolution);
  compute_binding := create_compute_binding(particles.count, particles.atr);
  io := ImGui.GetIO();
  config: ImGui.ImFontConfig;
  ImGui.ImFontConfig.Constructor(*config);
  config.OversampleH = 4; 
  config.OversampleV = 4;
  font := io.Fonts.AddFontFromFileTTF(io.Fonts, "assets/JetBrainsMonoNerdFont-Regular.ttf", 24.0, *config, null);

  state.time_last_frame = current_time_monotonic();
  while !state.exit {
    time_this_frame := current_time_monotonic();
    state.dt = xx to_float64_seconds(time_this_frame - state.time_last_frame);
    state.time_last_frame = time_this_frame;

    event : SDL_Event;
    while SDL_PollEvent(*event) {
      if event.type == { // events that superceed gui
        case SDL_QUIT; state.exit = true;
      }

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
          if event.button.button == SDL_BUTTON_RIGHT {
            dir :=  ifx state.tool.type == .Attract then 5. else -5.;
            mouse := Vector2.{xx event.motion.x, xx event.motion.y};
            target := screen_to_world(mouse, state, camera);
            target = wrap_world_pos(.{target.x, -target.y}, state.world_size);
            if state.tool.type == {
              case .Repel; #through;
              case .Attract; 
                for 0..particles.count-1 {
                  r := target - particles.pos[it];
                  wrap_distance(*r, state.world_size);
                  if length(r) > state.tool.radius continue; 
                  particles.vel[it] += normalize(r) * state.tool.force * 1000. * dir;
                }
              case .Spawn;
                gen_type := (color: s64) -> u32 {
                  if color > 0 return cast(u32) color;
                  return cast,no_check(u32) random_get();
                };

                gen_particle : (tool_r: f32, target: Vector2) -> Vector2;
                if #complete state.tool.shape == {
                  case .Circle; gen_particle = (tool_r: f32, target: Vector2) -> Vector2 {
                    theta := random_get_within_range(0., 2*PI);
                    r     := tool_r * sqrt(random_get_zero_to_one());
                    return .{r * cos(theta), r * sin(theta)} + target;
                  };
                  case .Square; gen_particle = (tool_r: f32, target: Vector2) -> Vector2 {
                    return .{random_get_within_range(-tool_r, tool_r),
                             random_get_within_range(-tool_r, tool_r)} + target;
                  };
                }

                for 0..state.tool.count-1 {
                  pos  := wrap_world_pos(gen_particle(state.tool.radius, target), state.world_size);
                  type := gen_type(state.tool.color) % xx particles.num_types;
                  particles_add(*particles, pos=pos, type=type);
                }

                resize_compute_particle_buffers(compute_binding, particles);
              case .Delete;
                cond : (r: Vector2, tool_r: f32) -> bool;
                if #complete state.tool.shape == {
                  case .Circle; cond = (r: Vector2, tool_r: f32) -> bool { return length(r) < tool_r; }; 
                  case .Square; cond = (r: Vector2, tool_r: f32) -> bool { return abs(r.x) < tool_r && abs(r.y) < tool_r; }; 
                }

                it := 0; while it < particles.count - 1 {
                  r := target - particles.pos[it];
                  wrap_distance(*r, state.world_size);
                  if cond(r, state.tool.radius) && 
                    (state.tool.color == -1 || state.tool.color == particles.type[it])
                    particles_delete(*particles, it);
                  else it += 1;
                }
                
                resize_compute_particle_buffers(compute_binding, particles);
            }
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
          mx, my: s32; SDL_GetMouseState(*mx, *my);
          mouse := Vector2.{xx mx, xx my};
          world_before := screen_to_world(mouse, state, camera);
          zoom_factor  := ifx event.wheel.y > 0 then 1.1 else 1./1.1;
          camera.zoom  *= zoom_factor;
          camera.zoom   = clamp(camera.zoom, 0.2, 20.);
          world_after  := screen_to_world(mouse, state, camera);
          camera.pos   += world_before - world_after;
        case SDL_KEYUP; if event.key.keysym.sym == {
            case SDLK_ESCAPE; state.exit = true;
            case SDLK_SPACE;  state.paused = !state.paused;
            case SDLK_h;      state.gui_hidden = !state.gui_hidden;
          }
        }
      }

    }

    ImGui_ImplSdl_NewFrame(window);
    ImGui.NewFrame();
    ImGui.SetNextWindowPos(.{10, 10}, ImGui.Cond.FirstUseEver, .{0, 0});
    ImGui.SetNextWindowSize(.{200, 80}, ImGui.Cond.FirstUseEver);
    free_id : s32 = 1;
    if !state.gui_hidden simulation_tools_gui(*state, *particles, camera, *free_id, compute_binding);
    tool_pointer_gui(*state, camera, *free_id);

    if !state.paused compute_pass(compute_binding, *particles, state);
    wrap_count := particles_add_wrap_ghosts(*particles, state.world_size);
    defer particles_pop_ghost(*particles, wrap_count);
    maybe_resize_world_texture(*tile_binding, *state.resolution, state.world_size, camera.zoom);
    world_render_pass(world_binding, particles, state, camera, tile_binding.framebuffer);
    tile_render_pass(tile_binding, state, camera);

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
  return camera.pos + {offset.x, offset.y};
}

#import "SDL";
#import "GL";
#import "Basic";
#import "Math";
#import "Random";
posix :: #import "POSIX";
#load "imgui_sd_gl.jai";
#load "widgets.jai";
#load "shaders.jai";
#load "util.jai";
#load "gpu.jai";
