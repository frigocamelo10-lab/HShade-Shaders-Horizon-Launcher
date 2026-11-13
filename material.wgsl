
override water_strength: f32 = 1.0;
override water_opacity: f32 = 0.82;
override water_gradient: f32 = 0.85;
override water_brightness: f32 = 1.08;
override water_saturation: f32 = 0.95;
override water_noise_strength: f32 = 0.22;
override water_noise_scale: f32 = 0.8;
override water_reflection_strength: f32 = 0.85;
override water_reflection_sharpness: f32 = 72.0;
override water_fresnel_strength: f32 = 0.25;

override water_wave_height: f32 = 0.045;
override water_wave_scale: f32 = 0.8;
override water_wave_speed: f32 = 0.65;
override water_wave_normal_strength: f32 = 2.5;
override water_specular_strength: f32 = 1.15;
override water_specular_sharpness: f32 = 180.0;

override water_noise_animation: f32 = 0.32;
override water_noise_contrast: f32 = 2.2;
override water_noise_ripple: f32 = 1.8;

override water_reflections_enabled: bool = true;
override block_reflections_enabled: bool = true;

override shadow_enabled: bool = true;
override shadow_light_response: f32 = 0.5;
override shadow_opacity: f32 = 0.48;

struct WaterNoiseSample {
    value: f32,
    gradient: vec2<f32>,
}

struct WaterWaveSample {
    height: f32,
    gradient: vec2<f32>,
}

fn hash3(p: vec3<f32>) -> f32 {
    let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
    return fract(sin(h) * 43758.5453);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);

    let n000 = hash3(i);
    let n100 = hash3(i + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = hash3(i + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = hash3(i + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = hash3(i + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = hash3(i + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = hash3(i + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = hash3(i + vec3<f32>(1.0, 1.0, 1.0));

    let x00 = mix(n000, n100, u.x);
    let x10 = mix(n010, n110, u.x);
    let x01 = mix(n001, n101, u.x);
    let x11 = mix(n011, n111, u.x);

    return mix(
        mix(x00, x10, u.y),
        mix(x01, x11, u.y),
        u.z
    );
}

fn fbm3(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var position = p;

    for (var i = 0u; i < 3u; i++) {
        value += noise3(position) * amplitude;
        position *= 2.0;
        amplitude *= 0.5;
    }

    return value;
}

fn water_hash2(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);

    p3 += vec3<f32>(
        dot(p3, p3.yzx + vec3<f32>(33.33))
    );

    return fract((p3.x + p3.y) * p3.z);
}

fn water_noise2(p: vec2<f32>) -> WaterNoiseSample {
    let i = floor(p);
    let f = fract(p);

    let u = f * f * f * (
        f * (f * 6.0 - 15.0) + 10.0
    );

    let du = 30.0 * f * f * (
        f * (f - 2.0) + 1.0
    );

    let n00 = water_hash2(i);
    let n10 = water_hash2(i + vec2<f32>(1.0, 0.0));
    let n01 = water_hash2(i + vec2<f32>(0.0, 1.0));
    let n11 = water_hash2(i + vec2<f32>(1.0, 1.0));

    let nx0 = mix(n00, n10, u.x);
    let nx1 = mix(n01, n11, u.x);

    let value = mix(nx0, nx1, u.y);

    let gradient_x = mix(
        (n10 - n00) * du.x,
        (n11 - n01) * du.x,
        u.y
    );

    let gradient_y = (nx1 - nx0) * du.y;

    return WaterNoiseSample(
        value,
        vec2<f32>(gradient_x, gradient_y)
    );
}

fn water_wave(
    position: vec2<f32>,
    direction: vec2<f32>,
    frequency: f32,
    speed: f32,
    amplitude: f32,
    time: f32
) -> WaterWaveSample {
    let phase = dot(position, direction) * frequency
        + time * speed;

    let wave_sin = sin(phase);
    let wave_cos = cos(phase);

    return WaterWaveSample(
        wave_sin * amplitude,
        direction * (wave_cos * amplitude * frequency)
    );
}

fn fresnel_schlick(cos_theta: f32, f0: vec3<f32>) -> vec3<f32> {
    let factor = pow(
        1.0 - clamp(cos_theta, 0.0, 1.0),
        5.0
    );

    return f0 + (vec3<f32>(1.0) - f0) * factor;
}

fn distribution_ggx(n_dot_h: f32, roughness: f32) -> f32 {
    let a = roughness * roughness;
    let a2 = a * a;
    let d = n_dot_h * n_dot_h * (a2 - 1.0) + 1.0;

    return a2 / max(3.14159265 * d * d, 0.0001);
}

fn geometry_schlick_ggx(n_dot_v: f32, roughness: f32) -> f32 {
    let r = roughness + 1.0;
    let k = (r * r) * 0.125;

    return n_dot_v / max(
        n_dot_v * (1.0 - k) + k,
        0.0001
    );
}

fn automatic_shadow_opacity() -> f32 {
    let sun_height = frame.sun_direction.y;

    let morning_evening = 1.0 - smoothstep(
        0.08,
        0.55,
        max(sun_height, 0.0)
    );

    let nighttime = 1.0 - smoothstep(
        -0.25,
        -0.02,
        sun_height
    );

    let time_factor = max(
        morning_evening,
        nighttime
    );

    let automatic_opacity = shadow_opacity
        + morning_evening * 0.10
        + nighttime * 0.12;

    return clamp(
        automatic_opacity,
        0.0,
        0.75
    );
}

fn calculate_shadow(input: MaterialInput) -> f32 {
    if !shadow_enabled || frame.has_shadow == 0u {
        return 1.0;
    }

    let shadow_pos = shadow_position(input.position);

    let inside = all(shadow_pos.xy >= vec2<f32>(0.0))
        && all(shadow_pos.xy <= vec2<f32>(1.0))
        && shadow_pos.z >= 0.0
        && shadow_pos.z <= 1.0;

    if !inside {
        return 1.0;
    }

    let resolution = max(f32(frame.shadow_resolution), 1.0);
    let texel_size = 1.0 / resolution;

    let normal = normalize(input.normal);
    let light_direction = normalize(frame.sun_direction);

    let n_dot_l = clamp(
        dot(normal, light_direction),
        0.0,
        1.0
    );

    let bias = max(
        0.00015,
        0.00020 + (1.0 - n_dot_l) * 0.00075
    );

    let safe_uv = clamp(
        shadow_pos.xy,
        vec2<f32>(texel_size * 0.5),
        vec2<f32>(1.0 - texel_size * 0.5)
    );

    var visibility = 0.0;
    var total_weight = 0.0;

    if input.fluid == 1u {
        visibility = textureSampleCompareLevel(
            shadow_map,
            shadow_sampler,
            safe_uv,
            shadow_pos.z - bias
        );

        total_weight = 1.0;
    } else {
        for (var y = -1; y <= 1; y++) {
            for (var x = -1; x <= 1; x++) {
                let offset = vec2<f32>(f32(x), f32(y))
                    * texel_size;

                var weight = 1.0;

                if x == 0 && y == 0 {
                    weight = 4.0;
                } else if x == 0 || y == 0 {
                    weight = 2.0;
                }

                let sample_uv = clamp(
                    safe_uv + offset,
                    vec2<f32>(texel_size * 0.5),
                    vec2<f32>(1.0 - texel_size * 0.5)
                );

                let sample_visibility = textureSampleCompareLevel(
                    shadow_map,
                    shadow_sampler,
                    sample_uv,
                    shadow_pos.z - bias
                );

                visibility += sample_visibility * weight;
                total_weight += weight;
            }
        }
    }

    visibility /= max(total_weight, 1.0);

    let vanilla_block_light = input.light.x;

    let colored_light = max(
        input.colored_light.r,
        max(
            input.colored_light.g,
            input.colored_light.b
        )
    );

    let local_light = clamp(
        max(vanilla_block_light, colored_light),
        0.0,
        1.0
    );

    let shadow_illumination = max(
        0.12,
        local_light * shadow_light_response
    );

    let shadow_result = mix(
        shadow_illumination,
        1.0,
        visibility
    );

    let opacity_limit = automatic_shadow_opacity();

    return mix(
        1.0,
        shadow_result,
        opacity_limit
    );
}

fn specular_shadow_visibility(shadow_factor: f32) -> f32 {
    return smoothstep(
        0.72,
        0.98,
        shadow_factor
    );
}

fn metallic_surface(
    input: MaterialInput,
    vanilla: vec4<f32>,
    shadow_factor: f32
) -> vec4<f32> {
    let world_position = input.position + frame.camera_position;

    let base_color = vanilla.rgb;
    let sky_light = clamp(input.light.y, 0.0, 1.0);
    let block_light = clamp(input.light.x, 0.0, 1.0);

    let local_luminance = dot(
        max(input.lightmap, vec3<f32>(0.0)),
        vec3<f32>(0.2126, 0.7152, 0.0722)
    );

    let local_brightness = clamp(
        local_luminance * 0.65
        + sky_light * 0.25
        + block_light * 0.10,
        0.0,
        1.0
    );

    let reflection_visibility = mix(
        0.10,
        1.0,
        smoothstep(0.08, 0.72, local_brightness)
    );

    let metal_position = world_position.xz;

    let metal_noise_a = water_noise2(metal_position * 3.2);

    let metal_noise_b = water_noise2(
        metal_position * 7.5 + vec2<f32>(4.7, 9.2)
    );

    let surface_noise = mix(
        metal_noise_a.value,
        metal_noise_b.value,
        0.28
    );

    let roughness = clamp(
        0.20 + surface_noise * 0.085,
        0.14,
        0.34
    );

    let metal_gradient = (
        metal_noise_a.gradient * 3.2 * 0.72
        + metal_noise_b.gradient * 7.5 * 0.28
    );

    let normal_detail = vec3<f32>(
        metal_gradient.x,
        0.0,
        metal_gradient.y
    ) * 0.055;

    let normal = normalize(
        input.normal - normal_detail
    );

    let view_direction = normalize(-input.position);
    let sun_direction = normalize(frame.sun_direction);

    let half_direction = normalize(
        sun_direction + view_direction
    );

    let n_dot_l = max(dot(normal, sun_direction), 0.0);
    let n_dot_v = max(dot(normal, view_direction), 0.001);
    let n_dot_h = max(dot(normal, half_direction), 0.0);
    let v_dot_h = max(dot(view_direction, half_direction), 0.0);

    let metalness = 0.92;
    let f0 = mix(vec3<f32>(0.04), base_color, metalness);

    let fresnel = fresnel_schlick(v_dot_h, f0);
    let distribution = distribution_ggx(n_dot_h, roughness);

    let geometry = geometry_schlick_ggx(n_dot_v, roughness)
        * geometry_schlick_ggx(n_dot_l, roughness);

    let specular = (
        distribution * geometry * fresnel
    ) / max(4.0 * n_dot_v * n_dot_l, 0.001);

    let sun_visibility = smoothstep(
        -0.05,
        0.15,
        frame.sun_direction.y
    );

    let specular_visibility = specular_shadow_visibility(
        shadow_factor
    );

    let direct_light = n_dot_l
        * sun_visibility
        * (0.65 + sky_light * 0.35);

    let diffuse = base_color
        * (1.0 - metalness)
        * direct_light;

    let specular_light = specular
        * input.lightmap
        * sun_visibility
        * n_dot_l
        * 0.65
        * reflection_visibility
        * specular_visibility;

    let environment_fresnel = fresnel_schlick(n_dot_v, f0);

    let environment = environment_fresnel
        * base_color
        * (0.12 + sky_light * 0.18)
        * reflection_visibility
        * specular_visibility;

    let reflected_direction = reflect(-sun_direction, normal);

    let glint_alignment = max(
        dot(reflected_direction, view_direction),
        0.0
    );

    let glint_core = pow(glint_alignment, 256.0);
    let glint_halo = pow(glint_alignment, 48.0);

    let glint = (
        glint_core * 1.8
        + glint_halo * 0.12
    ) * sun_visibility
      * n_dot_l
      * (0.55 + sky_light * 0.45)
      * reflection_visibility
      * specular_visibility;

    let glint_color = mix(
        vec3<f32>(1.0, 0.82, 0.58),
        vec3<f32>(1.0, 0.97, 0.88),
        smoothstep(0.05, 0.75, frame.sun_direction.y)
    );

    let metallic_base = base_color
        * (0.24 + sky_light * 0.20 + block_light * 0.08);

    let final_color = metallic_base
        + diffuse
        + environment
        + specular_light
        + glint_color * glint;

    return vec4<f32>(
        clamp(final_color, vec3<f32>(0.0), vec3<f32>(1.0)),
        vanilla.a
    );
}

fn material(input: MaterialInput) -> Surface {
    let vanilla = input.albedo * input.tint * vec4<f32>(input.lightmap, 1.0);

    let shadow_factor = calculate_shadow(input);

    let specular_visibility = specular_shadow_visibility(
        shadow_factor
    );

    if input.fluid != 1u {
        let is_ore = input.material >= 10u && input.material <= 19u;

        if block_reflections_enabled && is_ore {
            let metallic = metallic_surface(
                input,
                vanilla,
                shadow_factor
            );

            return Surface(vec4<f32>(
                metallic.rgb * shadow_factor,
                metallic.a
            ));
        }

        return Surface(vec4<f32>(
            vanilla.rgb * shadow_factor,
            vanilla.a
        ));
    }

    if !water_reflections_enabled {
        return Surface(vec4<f32>(
            vanilla.rgb * shadow_factor,
            vanilla.a
        ));
    }

    let deep_blue = vec3<f32>(0.012, 0.105, 0.19);
    let dark_teal = vec3<f32>(0.018, 0.22, 0.29);
    let ocean_blue = vec3<f32>(0.025, 0.34, 0.43);
    let turquoise = vec3<f32>(0.075, 0.49, 0.54);
    let shallow_blue = vec3<f32>(0.24, 0.64, 0.66);

    let sky_light = clamp(input.light.y, 0.0, 1.0);
    let block_light = clamp(input.light.x, 0.0, 1.0);

    let local_luminance = dot(
        max(input.lightmap, vec3<f32>(0.0)),
        vec3<f32>(0.2126, 0.7152, 0.0722)
    );

    let local_brightness = clamp(
        local_luminance * 0.65
        + sky_light * 0.25
        + block_light * 0.10,
        0.0,
        1.0
    );

    let reflection_visibility = mix(
        0.10,
        1.0,
        smoothstep(0.08, 0.72, local_brightness)
    );

    let gradient_a = smoothstep(0.0, 0.30, sky_light);
    let gradient_b = smoothstep(0.25, 0.65, sky_light);
    let gradient_c = smoothstep(0.60, 1.0, sky_light);

    var water_color = mix(deep_blue, dark_teal, gradient_a);
    water_color = mix(water_color, ocean_blue, gradient_b);
    water_color = mix(water_color, turquoise, gradient_c * 0.8);
    water_color = mix(water_color, shallow_blue, gradient_c * 0.35);

    let world_xz = input.position.xz + frame.camera_position.xz;
    let time = frame.time;

    let direction_a = vec2<f32>(0.83205, 0.55470);
    let direction_b = vec2<f32>(-0.44721, 0.89443);
    let direction_c = vec2<f32>(0.98058, -0.19612);
    let direction_d = vec2<f32>(-0.24254, -0.97014);

    let wave_a = water_wave(
        world_xz,
        direction_a,
        water_wave_scale * 0.85,
        water_wave_speed,
        water_wave_height,
        time
    );

    let wave_b = water_wave(
        world_xz,
        direction_b,
        water_wave_scale * 1.65,
        -water_wave_speed * 0.78,
        water_wave_height * 0.38,
        time
    );

    let wave_c = water_wave(
        world_xz,
        direction_c,
        water_wave_scale * 3.15,
        water_wave_speed * 1.34,
        water_wave_height * 0.13,
        time
    );

    let wave_d = water_wave(
        world_xz,
        direction_d,
        water_wave_scale * 4.7,
        -water_wave_speed * 1.17,
        water_wave_height * 0.055,
        time
    );

    let wave_height = wave_a.height
        + wave_b.height
        + wave_c.height
        + wave_d.height;

    let wave_gradient = (
        wave_a.gradient
        + wave_b.gradient
        + wave_c.gradient
        + wave_d.gradient
    ) * water_wave_normal_strength;

    let noise_flow_a = vec2<f32>(
        time * water_noise_animation,
        -time * water_noise_animation * 0.67
    );

    let noise_flow_b = vec2<f32>(
        -time * water_noise_animation * 0.73,
        time * water_noise_animation * 1.13
    );

    let noise_scale_a = water_noise_scale * 0.85;
    let noise_scale_b = water_noise_scale * 2.15;

    let noise_a = water_noise2(
        world_xz * noise_scale_a + noise_flow_a
    );

    let noise_b = water_noise2(
        world_xz * noise_scale_b
        + noise_flow_b
        + vec2<f32>(8.37, 3.71)
    );

    let noise_combined = (
        (noise_a.value - 0.5) * 0.70
        + (noise_b.value - 0.5) * 0.30
    );

    let noise_centered = noise_combined * water_noise_contrast;

    let noise_gradient = (
        noise_a.gradient * (noise_scale_a * 0.70)
        + noise_b.gradient * (noise_scale_b * 0.30)
    ) * water_noise_contrast
      * water_noise_strength
      * water_noise_ripple
      * 0.55;

    let noise_height = noise_centered
        * water_noise_strength
        * water_wave_height
        * 0.65;

    let noise_detail = noise_centered * water_noise_strength;

    let noise_ridges = smoothstep(
        0.06,
        0.36,
        noise_centered
    );

    let noise_valleys = smoothstep(
        0.06,
        0.36,
        -noise_centered
    );

    let noise_pattern = noise_ridges - noise_valleys;

    let wave_normal = normalize(vec3<f32>(
        -(wave_gradient.x + noise_gradient.x),
        1.0,
        -(wave_gradient.y + noise_gradient.y)
    ));

    let original_normal = normalize(input.normal);
    let top_face = select(0.0, 1.0, input.face == 1u);

    var mapped_normal = original_normal;

    if block_pbr_maps() {
        let normal_tex = block_normal_map(input.uv);

        let map_xy = normal_tex.rg * 2.0 - vec2<f32>(1.0);

        let map_z = sqrt(max(
            1.0 - dot(map_xy, map_xy),
            0.001
        ));

        let tangent = normalize(input.tangent.xyz);

        let bitangent = normalize(
            cross(original_normal, tangent)
        ) * input.tangent.w;

        mapped_normal = normalize(
            tangent * map_xy.x
            + bitangent * map_xy.y
            + original_normal * map_z
        );
    }

    let procedural_normal = normalize(vec3<f32>(
        wave_normal.x,
        wave_normal.y,
        wave_normal.z
    ));

    let normal = normalize(
        mapped_normal
        + (procedural_normal - vec3<f32>(0.0, 1.0, 0.0)) * top_face
    );

    let face_light = smoothstep(
        0.0,
        0.9,
        abs(normal.y)
    );

    water_color = mix(
        water_color * 0.62,
        water_color,
        face_light
    );

    let noise_color = 1.0
        + noise_pattern * water_noise_ripple * 0.075
        + noise_detail * 0.35;

    let ripple_color = 1.0
        + noise_detail * 0.45;

    water_color *= noise_color * ripple_color;

    let luminance = dot(
        water_color,
        vec3<f32>(0.2126, 0.7152, 0.0722)
    );

    water_color = mix(
        vec3<f32>(luminance),
        water_color,
        water_saturation
    );

    let lighting = max(
        input.lightmap,
        vec3<f32>(0.08)
    );

    let light_intensity = water_brightness
        * (0.88 + sky_light * 0.12 + block_light * 0.10);

    let lit_water = water_color
        * input.tint.rgb
        * lighting
        * light_intensity;

    let final_strength = clamp(
        water_strength * water_gradient,
        0.0,
        1.0
    );

    var final_color = mix(
        vanilla.rgb,
        lit_water,
        final_strength
    );

    let view_direction = normalize(
        -input.position + vec3<f32>(0.0, 0.0001, 0.0)
    );

    let sun_direction = normalize(frame.sun_direction);

    let half_direction = normalize(
        sun_direction + view_direction
    );

    let sun_visibility = smoothstep(
        -0.05,
        0.15,
        frame.sun_direction.y
    );

    let n_dot_l = max(dot(normal, sun_direction), 0.0);
    let n_dot_v = max(dot(normal, view_direction), 0.001);
    let n_dot_h = max(dot(normal, half_direction), 0.0);
    let v_dot_h = max(dot(view_direction, half_direction), 0.0);

    let roughness = clamp(
        pow(
            2.0 / max(water_specular_sharpness + 2.0, 2.0),
            0.25
        ),
        0.06,
        0.48
    );

    let specular_distribution = distribution_ggx(
        n_dot_h,
        roughness
    );

    let specular_geometry = geometry_schlick_ggx(
        n_dot_v,
        roughness
    ) * geometry_schlick_ggx(
        n_dot_l,
        roughness
    );

    let specular_fresnel = fresnel_schlick(
        v_dot_h,
        vec3<f32>(0.04)
    );

    let water_specular = (
        specular_distribution
        * specular_geometry
        * specular_fresnel
    ) / max(
        4.0 * n_dot_v * n_dot_l,
        0.001
    );

    let specular_color = mix(
        vec3<f32>(1.0, 0.72, 0.48),
        vec3<f32>(1.0, 0.96, 0.86),
        smoothstep(0.05, 0.75, frame.sun_direction.y)
    );

    let fresnel = pow(
        1.0 - clamp(n_dot_v, 0.0, 1.0),
        5.0
    );

    if frame.has_reflection == 1u && top_face > 0.0 {
        let reflection_softness = 1.0
            - smoothstep(
                16.0,
                160.0,
                water_reflection_sharpness
            );

        let reflection_distortion = mix(
            0.65,
            1.45,
            reflection_softness
        );

        let reflection_uv = input.screen
            + normal.xz * 0.012 * reflection_distortion
            + vec2<f32>(
                noise_detail * 0.012,
                (wave_height + noise_height) * 0.025
            ) * reflection_distortion;

        let environment = textureSample(
            reflection,
            reflection_sampler,
            reflection_uv
        ).rgb;

        let reflection_amount = clamp(
            (0.28 + fresnel * 0.62)
            * water_reflection_strength
            * reflection_visibility,
            0.0,
            0.88
        );

        final_color = mix(
            final_color,
            environment,
            reflection_amount
        );
    }

    final_color += water_color
        * fresnel
        * water_fresnel_strength
        * top_face
        * reflection_visibility;

    let specular_energy = water_specular_strength
        * 1.30
        * sun_visibility
        * n_dot_l
        * top_face
        * reflection_visibility
        * specular_visibility;

    final_color += specular_color
        * water_specular
        * specular_energy;

    final_color *= shadow_factor;

    final_color = clamp(
        final_color,
        vec3<f32>(0.0),
        vec3<f32>(1.0)
    );

    return Surface(vec4<f32>(
        final_color,
        vanilla.a * water_opacity
    ));
}
