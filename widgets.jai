color_gui :: (state: *Simulation_State, particles: *Particles, free_id: *s32) {
  colored_combo := state.tool.color + 1 > 0;
  if colored_combo {
    col := particles.colors[state.tool.color].xyz;
    ImGui.PushStyleColor(.FrameBg, .{col.x, col.y, col.z, 1.});
    ImGui.PushStyleColor(.FrameBgHovered, .{col.x, col.y, col.z, 0.8});
    ImGui.PushStyleColor(.FrameBgActive, .{col.x, col.y, col.z, 0.6});
  }

  if ImGui.BeginCombo("Color", ifx state.tool.color == -1 "Random".data else "".data) {
    is_selected := state.tool.color == -1;
    ImGui.PushID(free_id); free_id += 1;
    if ImGui.Selectable("Random", is_selected)
    state.tool.color = -1;
    ImGui.PopID();
    if is_selected ImGui.SetItemDefaultFocus();

    for 0..particles.num_types-1 {
      is_selected = state.tool.color == it;
      ImGui.PushID(free_id); free_id += 1;
      if ImGui.Selectable("", is_selected)
      state.tool.color = it;
      ImGui.PopID();
      col := particles.colors[it - 0].xyz;
      SelectableColor(ImGui.GetColorU32(.{col.x, col.y, col.z, 1.}));
      if is_selected ImGui.SetItemDefaultFocus();
    }

    ImGui.EndCombo();
  }
  if colored_combo ImGui.PopStyleColor(3);
}

shape_gui :: (state: *Simulation_State, particles: *Particles, free_id: *s32) {
  if ImGui.BeginCombo("Shape", SHAPE_NAMES[xx state.tool.shape].data) {
    for SHAPE_NAMES {
      is_selected := xx state.tool.shape == it_index;
      if ImGui.Selectable(it.data, is_selected)
      state.tool.shape = xx it_index;
      if is_selected ImGui.SetItemDefaultFocus();
    }
    ImGui.EndCombo();
  }
}

circle_shape_pointer :: (state: *Simulation_State, camera: Camera, color: ImGui.ImVec4, segments : s32 = 64, thickness : f32 = 2.) {
  mx, my: s32; SDL_GetMouseState(*mx, *my);
  mouse := ImGui.ImVec2.{xx mx, xx my};
  dl := ImGui.GetForegroundDrawList();
  ImGui.ImDrawList.AddCircle(dl, mouse, state.tool.radius * camera.zoom, ImGui.GetColorU32(color), segments, thickness);
}

square_shape_pointer :: (state: *Simulation_State, camera: Camera, color: ImGui.ImVec4, thickness : f32 = 2.) {
  mx, my: s32; SDL_GetMouseState(*mx, *my);
  mouse := ImGui.ImVec2.{xx mx, xx my};
  dl := ImGui.GetForegroundDrawList();
  r2 := state.tool.radius * camera.zoom;
  p1 := ImGui.ImVec2.{mouse.x - r2, mouse.y - r2};
  p2 := ImGui.ImVec2.{mouse.x + r2, mouse.y + r2};
  ImGui.ImDrawList.AddRect(dl, p1, p2, ImGui.GetColorU32(color), thickness=thickness);
}

attraction_matrix_gui :: (state: *Simulation_State, particles: *Particles, free_id: *s32, compute_binding: Compute_Binding) {
  if ImGui.TreeNode("Attraction Matrix") {
    new_colors:    [..] Vector4;
    new_atr:       [..] f32;
    removed_color := false;

    ImGui.PushStyleVar(.CellPadding, ImGui.ImVec2.{4, 4});
    ImGui.BeginTable("Attraction Matrix", xx (particles.num_types + 2));
    ImGui.TableNextRow();
    for c: 2..particles.num_types + 1 {
      ImGui.TableSetColumnIndex(xx c);
      ImGui.PushID(free_id); free_id += 1;
      ImGui.SetNextItemWidth(ImGui.GetContentRegionAvail().x);
      ImGui.ColorEdit3("", *particles.colors[c-2].xyz.component, ImGui.ColorEditFlags.NoLabel | ImGui.ColorEditFlags.NoInputs);
      ImGui.PopID();
    }
    for r: 0..particles.num_types - 1 {
      ImGui.TableNextRow();

      ImGui.TableSetColumnIndex(0);
      ImGui.PushID(free_id); free_id += 1;

      ImGui.PushStyleColor(.Text,          .{1., 1., 1., 1.});
      ImGui.PushStyleColor(.Button,        .{1., 0, 0, .5});
      ImGui.PushStyleColor(.ButtonHovered, .{1., 0, 0, .8});
      ImGui.PushStyleColor(.ButtonActive,  .{1., 0, 0, 1.});
      if ImGui.Button("x") {
        removed_color = true;
        for i: 0..particles.num_types - 1 if i != r
        array_add(*new_colors, particles.colors[i]);

        for i: 0..particles.num_types - 1 if i != r
        for j: 0..particles.num_types - 1 if j != r
        array_add(*new_atr, particles.atr[i*particles.num_types + j]);

        it := 0; while it < particles.count - 1 {
          particles.type[it] -= xx (particles.type[it] > r);
          if particles.type[it] == r 
            particles_delete(particles, it);
          else it += 1;
        }
      }
      ImGui.PopStyleColor(4);
      ImGui.PopID();

      ImGui.TableSetColumnIndex(1);
      ImGui.PushID(free_id); free_id += 1;
      ImGui.ColorEdit3("", *particles.colors[r].xyz.component, ImGui.ColorEditFlags.NoLabel | ImGui.ColorEditFlags.NoInputs);
      ImGui.PopID();
      for c: 2..particles.num_types+1 {
        a_id := r * particles.num_types + c - 2;
        a := particles.atr[a_id];
        ImGui.TableSetColumnIndex(xx c);
        ImGui.PushID(free_id); free_id += 1;
        ImGui.SetNextItemWidth(ImGui.GetContentRegionAvail().x);
        ImGui.PushStyleColor(.SliderGrab, .{0, 0, 0, 0});
        ImGui.PushStyleColor(.SliderGrabActive, .{0, 0, 0, 0.3});
        ImGui.PushStyleColor(.FrameBg,        .{0.5 - a/2, a/2+0.5, 0, pow(abs(a), 0.5)});
        ImGui.PushStyleColor(.FrameBgHovered, .{0.5 - a/2, a/2+0.5, 0, pow(abs(a), 0.5)});
        ImGui.PushStyleColor(.FrameBgActive,  .{0.5 - a/2, a/2+0.5, 0, pow(abs(a), 0.5)});
        ImGui.SliderFloat("", *particles.atr[a_id], -1., 1., "");
        if ImGui.IsItemHovered() || ImGui.IsItemActive()
        ImGui.SetTooltip("%", formatFloat(particles.atr[a_id], trailing_width=2));
        if ImGui.IsItemHovered() {
          scroll := ImGui.GetIO().MouseWheel;
          if scroll != 0 {
            particles.atr[a_id] += scroll * 0.05;
            particles.atr[a_id] = clamp(particles.atr[a_id], -1., 1.);
          }
        }
        ImGui.PopStyleColor(5);
        ImGui.PopID();
      }
    }

    ImGui.TableNextRow();
    ImGui.TableSetColumnIndex(0);
    ImGui.PushID(free_id); free_id += 1;
    if ImGui.Button("+") {
      for i: 0..particles.num_types - 1 {
        for j: 0..particles.num_types - 1
        array_add(*new_atr, particles.atr[i*particles.num_types + j]);
        array_add(*new_atr, random_get_within_range(-1., 1.));
      }
      for i: 0..particles.num_types
      array_add(*new_atr, random_get_within_range(-1., 1.));

      array_add(*particles.colors, .{xyz=hsl_to_rgb01(random_get_within_range(0., 360.), 1., .7), w=1.});

      array_free(particles.atr);
      particles.atr = new_atr;
      resize_compute_attraction_buffer(compute_binding, particles);
    }
    ImGui.PopID();

    if removed_color {
      array_free(particles.atr);
      array_free(particles.colors);
      particles.atr = new_atr;
      particles.colors = new_colors;
      state.tool.color = -1;
      resize_compute_particle_buffers(compute_binding, particles);
      resize_compute_attraction_buffer(compute_binding, particles);
    }

    ImGui.EndTable();
    ImGui.PopStyleVar();

    if ImGui.Button("Randomize") randomize_attraction_matrix(particles);
    ImGui.SameLine();
    if ImGui.Button("Save") print("attraction_matrix = %\n", particles.atr);
    ImGui.TreePop();
  }

}

info_gui :: (state: *Simulation_State, particles: *Particles, camera: Camera, free_id: *s32) {
  io := ImGui.GetIO();
  ImGui.SeparatorText("Info");
  ImGui.TextColored(.{0, 1, 0, 1}, "FPS:%", formatInt(cast(s64) io.Framerate, padding = #char " ", minimum_digits=4)); 
  ImGui.SameLine();
  window_width := ImGui.GetWindowWidth();
  text_width := ImGui.CalcTextSize(tprint("particles: %", particles.count)).x;
  ImGui.SetCursorPosX(window_width - text_width - ImGui.GetStyle().WindowPadding.x);
  ImGui.Text("particles: %", particles.count);
  if ImGui.Button((ifx state.paused then "Run" else "Pause").data) state.paused = !state.paused;
  ImGui.SameLine();
  text_width = ImGui.CalcTextSize(tprint("resolution: %x%", state.resolution.x, state.resolution.y)).x;
  ImGui.SetCursorPosX(window_width - text_width - ImGui.GetStyle().WindowPadding.x);
  ImGui.Text("resolution: %x%", state.resolution.x, state.resolution.y);

  fint := context;
  fint.print_style.default_format_int.padding = #char "0";
  fint.print_style.default_format_int.minimum_digits = 4;
  push_context fint {
    mx, my: s32; SDL_GetMouseState(*mx, *my);
    mouse := screen_to_world(.{xx mx, xx my}, state, camera);
    mouse  = wrap_world_pos(mouse * .{1,-1}, state.world_size);
    text_width = ImGui.CalcTextSize(tprint("mouse: %x%", cast(s32) mouse.x, cast(s32) mouse.y)).x;
    ImGui.SetCursorPosX(window_width - text_width - ImGui.GetStyle().WindowPadding.x);
    ImGui.Text("mouse: %x%", cast(s32) mouse.x, cast(s32) mouse.y);
  }
}

tool_pointer_gui :: (state: *Simulation_State, camera: Camera, free_id: *s32) {
  color: ImGui.ImVec4;
  if state.tool.type == {
    case .Attract; color = .{0, 1, 0, .5};
    case .Repel;   color = .{1, 0, 0, .5};
    case .Delete;  color = .{0.239, 0.012, 0.98, .5};
    case .Spawn;   color = .{0.969, 0.6, 0.012, .5};
  }
  if state.tool.type == .Attract || state.tool.type == .Repel
    circle_shape_pointer(state, camera, color);
  else if state.tool.shape == {
    case .Circle; circle_shape_pointer(state, camera, color);
    case .Square; square_shape_pointer(state, camera, color);
  }
}

tool_gui :: (state: *Simulation_State, particles: *Particles, camera: Camera, free_id: *s32) {
  if state.tool.type == {
    case .Attract; #through;
    case .Repel;
      ImGui.SliderFloat("Force",  *state.tool.force, 0., 1.);
      ImGui.SliderFloat("Radius", *state.tool.radius, 10., min(state.world_size.x, state.world_size.y) / 2);
    case .Delete;
      if ImGui.Button("Delete All") { 
        array_resize(*particles.pos, 0);
        array_resize(*particles.vel, 0);
        array_resize(*particles.type, 0);
      }
      ImGui.SliderFloat("Radius", *state.tool.radius, 10., min(state.world_size.x, state.world_size.y) / 2);
      color_gui(state, particles, free_id);
      shape_gui(state, particles, free_id);
    case .Spawn;
      ImGui.SliderFloat("Radius", *state.tool.radius, 10., state.world_size.x);
      ImGui.SliderInt  ("Count", *state.tool.count, 0, 1000);
      color_gui(state, particles, free_id);
      shape_gui(state, particles, free_id);
  }
}


simulation_dev_gui :: (using state: *Simulation_State, using particles: *Particles, camera: *Camera, free_id: *s32, compute_binding: Compute_Binding) {
  if ImGui.Begin("Simulation Tools", null, .AlwaysAutoResize) {
    info_gui(state, particles, camera, free_id);

    ImGui.InputFloat2("Camera position", *camera.pos.component); 
    if ImGui.Button("Reset All") init_simulation(particles, world_size, count, num_types);
    ImGui.SameLine();
    if ImGui.Button("Reset Positions") randomize_particle_positions(particles, world_size);
    ImGui.SameLine();
    if ImGui.Button("Reset Colors") randomize_particle_colors(particles);

    attraction_matrix_gui(state, particles, free_id, compute_binding);

    if ImGui.BeginCombo("Tool", TOOL_NAMES[tool.type].data) {
      for TOOL_NAMES {
        is_selected := xx tool.type == it_index;
        if ImGui.Selectable(it.data, is_selected)
        tool.type = xx it_index;
        if is_selected ImGui.SetItemDefaultFocus();
      }
      ImGui.EndCombo();
    }

    tool_gui(state, particles, camera, free_id);
  }
  ImGui.End();
}

SelectableColor :: (color: ImGui.ImU32 )
{
  p_min := ImGui.GetItemRectMin();
  p_max := ImGui.GetItemRectMax();
  ImGui.ImDrawList.AddRectFilled(ImGui.GetWindowDrawList(), p_min, p_max, color);
}
