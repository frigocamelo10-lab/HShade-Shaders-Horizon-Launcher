
override water_strength: f32 = 1.0;
override water_opacity: f32 = 0.82;
override water_gradient: f32 = 0.85;
override water_brightness: f32 = 1.08;
override water_saturation: f32 = 0.95;
override water_noise_strength: f32 = 0.035;
override water_noise_scale: f32 = 0.8;
override water_reflection_strength: f32 = 0.85;
override water_reflection_sharpness: f32 = 72.0;
override water_fresnel_strength: f32 = 0.25;

fn material(input: MaterialInput) -> Surface {
    let vanilla = input.albedo * input.tint * vec4<f32>(input.lightmap, 1.0);

    if input.fluid != 1u {
        return Surface(vanilla);
    }

    let deep_blue = vec3<f32>(0.012, 0.105, 0.19);
    let dark_teal = vec3<f32>(0.018, 0.22, 0.29);
    let ocean_blue = vec3<f32>(0.025, 0.34, 0.43);
    let turquoise = vec3<f32>(0.075, 0.49, 0.54);
    let shallow_blue = vec3<f32>(0.24, 0.64, 0.66);
    let bright_water = vec3<f32>(0.48, 0.78, 0.74);

    let sky_light = clamp(input.light.y, 0.0, 1.0);
    let block_light = clamp(input.light.x, 0.0, 1.0);

    let gradient_a = smoothstep(0.0, 0.30, sky_light);
    let gradient_b = smoothstep(0.25, 0.65, sky_light);
    let gradient_c = smoothstep(0.60, 1.0, sky_light);

    var water_color = mix(deep_blue, dark_teal, gradient_a);
    water_color = mix(water_color, ocean_blue, gradient_b);
    water_color = mix(water_color, turquoise, gradient_c * 0.8);
    water_color = mix(water_color, shallow_blue, gradient_c * 0.35);

    let normal = normalize(input.normal);
    let top_face = select(0.0, 1.0, input.face == 1u);
    let face_light = smoothstep(0.0, 0.9, abs(normal.y));

    water_color = mix(
        water_color * 0.62,
        water_color,
        face_light
    );

    let world_xz = input.position.xz + frame.camera_position.xz;

    let wave_a = sin(
        dot(world_xz, vec2<f32>(0.73, 0.41)) * water_noise_scale
        + frame.time * 0.35
    );

    let wave_b = sin(
        dot(world_xz, vec2<f32>(-0.31, 0.87)) * water_noise_scale
        - frame.time * 0.23
    );

    let noise = wave_a * wave_b;

    water_color *= 1.0 + noise * water_noise_strength;

    let luminance = dot(
        water_color,
        vec3<f32>(0.2126, 0.7152, 0.0722)
    );

    water_color = mix(
        vec3<f32>(luminance),
        water_color,
        water_saturation
    );

    let lighting = max(input.lightmap, vec3<f32>(0.08));
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
    let half_direction = normalize(sun_direction + view_direction);

    let sun_visibility = smoothstep(
        -0.05,
        0.15,
        frame.sun_direction.y
    );

    let specular_dot = max(
        dot(normal, half_direction),
        0.0
    );

    let sun_specular = pow(
        specular_dot,
        water_reflection_sharpness
    );

    let sun_color = mix(
        vec3<f32>(1.0, 0.66, 0.39),
        vec3<f32>(1.0, 0.94, 0.78),
        smoothstep(0.05, 0.75, frame.sun_direction.y)
    );

    let reflection = sun_specular
        * water_reflection_strength
        * sun_visibility
        * top_face;

    final_color += sun_color * reflection;

    let fresnel = pow(
        1.0 - clamp(dot(normal, view_direction), 0.0, 1.0),
        3.0
    );

    final_color += water_color
        * fresnel
        * water_fresnel_strength
        * top_face;

    final_color = clamp(
        final_color,
        vec3<f32>(0.0),
        vec3<f32>(1.0)
    );

    let alpha = clamp(
        vanilla.a * water_opacity,
        0.0,
        1.0
    );

    return Surface(vec4<f32>(final_color, alpha));
}
