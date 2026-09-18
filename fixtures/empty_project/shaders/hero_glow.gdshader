shader_type spatial;
void fragment() {
  ALBEDO = vec3(0.2, 0.8, 1.0);
  EMISSION = ALBEDO * 0.6;
}