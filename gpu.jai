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


maybe_resize_world_texture :: (tile: *Tile_Binding, resolution: *Vector2, world_size: Vector2, zoom: f32) {
    target := compute_world_tex_resolution(world_size, zoom);
    if target == resolution.* return;
    resolution.* = target;

    glBindTexture(GL_TEXTURE_2D, tile.world_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8,
                 xx target.x, xx target.y, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
    // Re-attach (the FBO object itself is reused)
    glBindFramebuffer(GL_FRAMEBUFFER, tile.framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tile.world_texture, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
}

compute_world_tex_resolution :: (world_size: Vector2, zoom: f32) -> Vector2 {
  BUCKET : s32 : 64;
  clamp_and_bucket :: (v: f32) -> f32 {
    return cast(f32)(cast(s32)(clamp(v, 128., 16384.) / BUCKET) * BUCKET + BUCKET);
  }
  return .{
    clamp_and_bucket(world_size.x * zoom),
    clamp_and_bucket(world_size.y * zoom),
  };
}

compile_shader :: (source: string, shader_type: GLenum) -> GLuint {
    shader := glCreateShader(shader_type);
    src := source.data;
    len : GLint = xx source.count;
    glShaderSource(shader, 1, *src, *len);
    glCompileShader(shader);

    ok : GLint;
    glGetShaderiv(shader, GL_COMPILE_STATUS, *ok);
    if !ok {
      buf : [512] u8; glGetShaderInfoLog(shader, 512, null, buf.data);
      panic("Shader compile error: %", to_string(buf.data));
    }
    return shader;
}

Shader :: struct { source: string; type: GLenum; };
create_shader_program :: (sources: ..Shader) -> GLuint {  
  prog := glCreateProgram();
  shaders : [..] GLuint; defer array_free(shaders);

  for sources {
    shader := compile_shader(it.source, it.type);
    glAttachShader(prog, shader);
    array_add(*shaders, shader);
  }
  glLinkProgram(prog);

  ok: GLint; glGetProgramiv(prog, GL_LINK_STATUS, *ok);
  if !ok {
    buf : [512] u8; glGetProgramInfoLog(prog, 512, null, buf.data);
    panic("Shader link error: %", to_string(buf.data));
  }
  for shaders glDeleteShader(it);

  return prog;
}

create_compute_binding :: (particles_count: s64, attraction_matrix: [] f32) -> Compute_Binding {
  b: Compute_Binding;
  b.shader = create_shader_program(.{ COMPUTE_SHADER, GL_COMPUTE_SHADER });

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
  glUseProgram(shader);

  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, pos_ssbo);
  glBufferSubData (GL_SHADER_STORAGE_BUFFER, 0, size_of(Vector2) * particles.count, particles.pos.data);
  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, vel_ssbo);
  glBufferSubData (GL_SHADER_STORAGE_BUFFER, 0, size_of(Vector2) * particles.count, particles.vel.data);
  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, type_ssbo);
  glBufferSubData (GL_SHADER_STORAGE_BUFFER, 0, size_of(u32) * particles.count, particles.type.data);
  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, a_ssbo);
  glBufferSubData (GL_SHADER_STORAGE_BUFFER, 0, size_of(f32) * particles.atr.count, particles.atr.data);
  glBindBuffer    (GL_SHADER_STORAGE_BUFFER, 0);

  // Set uniforms
  glUniform2f(glGetUniformLocation(shader, "u_worldSize"), state.world_size.x, state.world_size.y);
  glUniform1f(glGetUniformLocation(shader, "u_dt"), state.dt);
  glUniform1f(glGetUniformLocation(shader, "u_rMax"), R_MAX);
  glUniform1f(glGetUniformLocation(shader, "u_frictionFactor"), pow(0.5, state.dt / T_HALF));
  glUniform1i(glGetUniformLocation(shader, "u_numParticles"), xx particles.count);
  glUniform1i(glGetUniformLocation(shader, "u_numParticleTypes"), xx particles.num_types);

  work_groups := (particles.count + PARTICLES_PER_WORK_GROUPS - 1) / PARTICLES_PER_WORK_GROUPS;
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

resize_compute_particle_buffers :: (using b: Compute_Binding, particles: Particles) {
  glUseProgram(shader);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, pos_ssbo);
  glBufferData(GL_SHADER_STORAGE_BUFFER, size_of(Vector2) * particles.count, null, GL_DYNAMIC_COPY);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, vel_ssbo);
  glBufferData(GL_SHADER_STORAGE_BUFFER, size_of(Vector2) * particles.count,null, GL_DYNAMIC_COPY);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, type_ssbo);
  glBufferData(GL_SHADER_STORAGE_BUFFER, size_of(u32) * particles.count, null, GL_DYNAMIC_COPY);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
  glUseProgram(0);
}

resize_compute_attraction_buffer :: (using b: Compute_Binding, particles: Particles) {
  glUseProgram(shader);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, a_ssbo);
  glBufferData(GL_SHADER_STORAGE_BUFFER, size_of(f32) * particles.atr.count, null, GL_DYNAMIC_COPY);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
  glUseProgram(0);
}

create_tile_binding :: (resolution: Vector2) -> Tile_Binding {
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
  layout.shader = create_shader_program(.{ TILE_VS, GL_VERTEX_SHADER }, .{ TILE_FS, GL_FRAGMENT_SHADER });

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  return layout;
}

tile_render_pass :: (
  using layout: Tile_Binding,
  using state:  Simulation_State,
  camera: Camera,
) {
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, 0, xx window_size.x, xx window_size.y);
  glClearColor(0., 0., 0., 1.);
  glClear(GL_COLOR_BUFFER_BIT);

  glUseProgram(shader);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, world_texture);
  glUniform1i(glGetUniformLocation(shader, "u_worldTexture"), 0);
  glUniform2f(glGetUniformLocation(shader, "u_worldSize"),    world_size.x,    world_size.y);
  glUniform2f(glGetUniformLocation(shader, "u_windowSize"),   window_size.x,   window_size.y);
  glUniform2f(glGetUniformLocation(shader, "u_cameraPos"),    camera.pos.x,    camera.pos.y);
  glUniform1f(glGetUniformLocation(shader, "u_cameraZoom"),   camera.zoom);

  glBindVertexArray(quad_vao);
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  glBindVertexArray(0);
  glUseProgram(0);
}

create_world_binding :: (particles: *Particles) -> World_Binding {
  using layout :World_Binding;
  glGenVertexArrays(1, *vao);
  glBindVertexArray(vao);

  glGenBuffers(1, *quad_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, quad_vbo);
  quad_verts :: f32.[-1,-1, 1,-1, -1,1, 1,1];
  glBufferData(GL_ARRAY_BUFFER, size_of(type_of(quad_verts)) , quad_verts.data, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, size_of(f32) * 2, null);

  glGenBuffers(1, *pos_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, pos_vbo);
  glBufferData(GL_ARRAY_BUFFER, size_of(Vector2) * particles.count, null, GL_DYNAMIC_DRAW);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(Vector2), null);
  glVertexAttribDivisor(1, 1);

  glGenBuffers(1, *type_vbo);
  glBindBuffer(GL_ARRAY_BUFFER, type_vbo);
  glBufferData(GL_ARRAY_BUFFER, size_of(u32) * particles.count, null, GL_DYNAMIC_DRAW);
  glEnableVertexAttribArray(2);
  glVertexAttribIPointer(2, 1, GL_UNSIGNED_BYTE, size_of(u32), null);
  glVertexAttribDivisor(2, 1);
  glBindVertexArray(0);

  glGenBuffers     (1, *color_ssbo);
  glBindBuffer     (GL_SHADER_STORAGE_BUFFER, color_ssbo);
  glBufferData     (GL_SHADER_STORAGE_BUFFER, size_of(Vector4) * particles.num_types, null, GL_DYNAMIC_DRAW);
  glBindBufferBase (GL_SHADER_STORAGE_BUFFER, 4, color_ssbo);

  glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
  shader = create_shader_program(.{ WORLD_VS, GL_VERTEX_SHADER }, { WORLD_FS, GL_FRAGMENT_SHADER });
  return layout;
}

world_render_pass :: (
  using layout:    World_Binding,
  using particles: Particles,
  using state:     Simulation_State,
  camera:          Camera,
  framebuffer:     GLuint,
) {
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glViewport(0, 0, xx resolution.x, xx resolution.y);
  glClearColor(0., 0., 0., 1.);
  glClear(GL_COLOR_BUFFER_BIT);

  glBindBuffer(GL_ARRAY_BUFFER, pos_vbo);
  glBufferData(GL_ARRAY_BUFFER, size_of(Vector2) * count, pos.data, GL_DYNAMIC_DRAW);
  glBindBuffer(GL_ARRAY_BUFFER, type_vbo);
  glBufferData(GL_ARRAY_BUFFER, size_of(u32) * count, type.data, GL_DYNAMIC_DRAW);

  glBindBuffer(GL_SHADER_STORAGE_BUFFER, color_ssbo);
  glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, size_of(Vector4) * num_types, colors.data);

  glUseProgram(shader);
  glUniform2f (glGetUniformLocation(shader, "u_world_size"),  world_size.x, world_size.y);
  glUniform2f (glGetUniformLocation(shader, "u_resolution"),  resolution.x, resolution.y);

  glBindVertexArray(vao);
  glEnable(GL_BLEND); 
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, xx count);

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glBindVertexArray(0);
}
