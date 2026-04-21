Simulation_State :: struct {
  world_size:        Vector2 = #run .{1920, 1080} * 3.;
  resolution:        Vector2;
  window_size:       Vector2 = .{1920, 1080};
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
  type:   ToolType  = .None;
  shape:  ShapeType = .Circle;
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
  #as using pos:  Vector2; // world space point at screen centre
  zoom: f32 = 1.;          // pixels per world unit
}

Camera :: struct {
  #as using uniform: Camera_Uniform;
  is_panning:        bool;
  pan_start_mouse:   Vector2;
  pan_start_camera:  Vector2;
}

screen_to_world :: (screen: Vector2, state: Simulation_State, camera: Camera) -> Vector2 {
  screen_center := state.window_size * 0.5;
  offset := (screen - screen_center) / camera.zoom;
  return camera.pos + {offset.x, offset.y};
}

wrap_distance :: (r: *Vector2, world_size: Vector2) {
  r.* -= world_size * (r >  world_size * 0.5);
  r.* += world_size * (r < -world_size * 0.5);
}

main :: () {
  posix.setenv("__NV_PRIME_RENDER_OFFLOAD", "1",      1);
  posix.setenv("__GLX_VENDOR_LIBRARY_NAME", "nvidia", 1);
  posix.setenv("DRI_PRIME",                 "1",      1);

  state: Simulation_State;
  particles: Particles; defer particles_free(*particles);
  camera: Camera;

  SDL_Init(SDL_INIT_VIDEO);
  window := SDL_CreateWindow("Particle Life", 0, 0, xx state.window_size.x, xx state.window_size.y, SDL_WINDOW_OPENGL|SDL_WINDOW_RESIZABLE|SDL_WINDOW_FULLSCREEN);
  assert(window != null, "Could not create window: %", to_string(SDL_GetError()));

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);
  gl_context := SDL_GL_CreateContext(window);
  assert(gl_context != null, "Could not create OpenGL context: %", to_string(SDL_GetError()));

  major, minor : GLint;
  glGetIntegerv(GL_MAJOR_VERSION, *major);
  glGetIntegerv(GL_MINOR_VERSION, *minor);
  assert(major > 4 || (major == 4 && minor >= 3), "Compute shader requires OpenGL 4.3 or higher.");

  SDL_GL_SetSwapInterval(0);
  imgui_context := ImGui.CreateContext();
  ImGui_ImplSdl_Init(window);
  ImGui.StyleColorsDark(); 

  gl_load(*gl, SDL_GL_GetProcAddress);

  println("GL Version = %", to_string(glGetString(GL_VERSION)));
  println("GL Renderer = %", to_string(glGetString(GL_RENDERER)));

  init_simulation(*particles, state.world_size);

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
      ImGui_ImplSdl_ProcessEvent(*event);
      if !io.WantCaptureMouse && !io.WantCaptureKeyboard
        handle_event(event, *particles, *state, *camera, compute_binding);
        
      if event.type == { // events that superceed gui
        case SDL_QUIT; state.exit = true;
      }
    }

    ImGui_ImplSdl_NewFrame(window);
    ImGui.NewFrame();
    ImGui.SetNextWindowPos(.{10, 10}, ImGui.Cond.FirstUseEver, .{0, 0});
    ImGui.SetNextWindowSize(.{200, 80}, ImGui.Cond.FirstUseEver);
    free_id : s32 = 1;
    if !state.gui_hidden simulation_dev_gui(*state, *particles, *camera, *free_id, compute_binding);
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

handle_event :: (event: SDL_Event, particles: *Particles, using state: *Simulation_State, camera: *Camera, compute_binding: Compute_Binding) {
  mod := SDL_GetModState();
  if event.type == {
    case SDL_WINDOWEVENT;
      if event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED
      window_size = .{xx event.window.data1, xx event.window.data2};
    case SDL_MOUSEBUTTONDOWN; if event.button.button == {
      case SDL_BUTTON_LEFT;
        camera.is_panning = true;
        camera.pan_start_mouse  = .{xx event.button.x, xx event.button.y};
        camera.pan_start_camera = camera.pos;
      case SDL_BUTTON_RIGHT; 
        mouse := Vector2.{xx event.motion.x, xx event.motion.y};
        target := screen_to_world(mouse, state, camera);
        target = wrap_world_pos(.{target.x, -target.y}, world_size);
        use_tool(target, particles, state, compute_binding);
    }
    case SDL_MOUSEBUTTONUP; if event.button.button == SDL_BUTTON_LEFT camera.is_panning = false;
    case SDL_MOUSEMOTION; if camera.is_panning {
      mouse := Vector2.{xx event.motion.x, xx event.motion.y};
      world_now    := screen_to_world(mouse, state, camera);
      world_start  := screen_to_world(camera.pan_start_mouse, state, camera);
      camera.pos    = camera.pan_start_camera + (world_start - world_now);
    }
    case SDL_MOUSEWHEEL; if mod & .KMOD_CTRL {
      tool.radius *= ifx event.wheel.y < 0 then 1.1 else 1./1.1;
      tool.radius  = clamp(tool.radius, 1., max(world_size.x/2, world_size.y/2));
      } else {
      mx, my: s32; SDL_GetMouseState(*mx, *my);
      mouse := Vector2.{xx mx, xx my};
      world_before := screen_to_world(mouse, state, camera);
      zoom_factor  := ifx event.wheel.y > 0 then 1.1 else 1./1.1;
      camera.zoom  *= zoom_factor;
      camera.zoom   = clamp(camera.zoom, 0.2, 20.);
      world_after  := screen_to_world(mouse, state, camera);
      camera.pos   += world_before - world_after;
    }
    case SDL_KEYUP; if event.key.keysym.sym == {
      case SDLK_ESCAPE; exit = true;
      case SDLK_SPACE;  paused = !paused;
      case SDLK_h;      gui_hidden = !gui_hidden;
      case SDLK_0;      tool.type = .None;
      case SDLK_1;      tool.type = .Attract;
      case SDLK_2;      tool.type = .Repel;
      case SDLK_3;      tool.type = .Spawn;
      case SDLK_4;      tool.type = .Delete;
    }
  }
}

use_tool :: (target: Vector2, particles: *Particles, state: *Simulation_State, compute_binding: Compute_Binding) {
  dir :=  ifx state.tool.type == .Attract then 5. else -5.;
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
          return .{random_get_within_range(-tool_r, tool_r), random_get_within_range(-tool_r, tool_r)} + target;
        };
      }

      for 0..state.tool.count-1 {
        pos  := wrap_world_pos(gen_particle(state.tool.radius, target), state.world_size);
        type := gen_type(state.tool.color) % xx particles.num_types;
        particles_add(particles, pos=pos, type=type);
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
        if cond(r, state.tool.radius) && (state.tool.color == -1 || state.tool.color == particles.type[it])
          particles_delete(particles, it);
        else it += 1;
      }

      resize_compute_particle_buffers(compute_binding, particles);
  }
}

#import "SDL";
#import "GL";
#import "Basic";
#import "Math";
#import "Random";
posix :: #import "POSIX";
#load "imgui_sd_gl.jai";
#load "particles.jai";
#load "widgets.jai";
#load "shaders.jai";
#load "util.jai";
#load "gpu.jai";
