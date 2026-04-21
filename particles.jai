PARTICLE_RADIUS           :: 2.;
R_MAX                     :: 100.;
T_HALF                    :: 0.04;
PARTICLES_PER_WORK_GROUPS :: 256;

Particles :: struct {
  pos:    [..] Vector2;
  type:   [..] u32;
  #overlay (pos.count) count: s64;
  vel:    [..] Vector2;
  atr:    [..] f32;
  colors: [..] Vector4;
  #overlay (colors.count) num_types: s64;
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

init_simulation :: (using particles: *Particles, world_size: Vector2, num_particles: s64 = 20_000, num_particle_types : s64 = 6, seed : u64 = 0) {
  if seed == 0 seed = transmute(u64, to_seconds(current_time_monotonic()));
  random_seed(seed);
  randomize_particle_colors(particles, num_particles, num_particle_types);
  randomize_attraction_matrix(particles);
  randomize_particle_positions(particles, world_size, num_particles, num_particle_types);
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

randomize_particle_positions :: (using particles: *Particles, world_size: Vector2, num_particles : s64 = 0, num_particle_types : s64 = 0) {
  if num_particles == 0 num_particles = count;
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
