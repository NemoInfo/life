f32 :: float32;
f64 :: float64;

transmute :: inline ($toT: Type, x: $T) -> toT {
    union { from : T = ---; to : toT = ---; }    
    from = x;
    return to;
}

println :: inline (s: string, args: ..Any) {
  print(s, ..args); print("\n");
}

eprint :: inline (s: string, args: ..Any) {
  write_string(tprint(s, ..args), to_standard_error=true);
}

eprintln :: inline (s: string, args: ..Any) {
  eprint(s, ..args); eprint("\n");
}

panic :: inline (s: string, args: ..Any, exit_code: s32 = 1, loc := #caller_location) {
  eprint("[%:%:%] ", loc.fully_pathed_filename, loc.line_number, loc.character_number);
  print_color("panicked:", color=.RED, .BOLD, to_standard_error=true);
  eprintln(" %", tprint(s, ..args));
  exit(exit_code);
}

operator > :: inline (a: Vector2, b: Vector2) -> Vector2 {
  return .{cast(f32) (a.x > b.x), cast(f32) (a.y > b.y)};
}

operator < :: inline (a: Vector2, b: Vector2) -> Vector2 {
  return .{cast(f32) (a.x < b.x), cast(f32) (a.y < b.y)};
}

clamp :: inline (a: Vector2, low: f32, high: f32) -> Vector2 {
  return .{clamp(a.x, low, high), clamp(a.y, low, high)};
}

fmod_cycling :: inline (x: Vector2, y: Vector2) -> Vector2 {
  return .{fmod_cycling(x.x, y.x), fmod_cycling(x.y, y.y)};
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
#import "Math";
#import "Print_Color";
