
override godrays_enabled: bool = true;
override godrays_intensity: f32 = 2.5;
override godrays_density: f32 = 0.035;
override godrays_weight: f32 = 1.55;
override godrays_decay: f32 = 0.988;
override godrays_exposure: f32 = 1.65;
override godrays_samples: i32 = 20;
override godrays_max_distance: f32 = 128.0;
override godrays_anisotropy: f32 = 0.82;
override godrays_shadow_bias: f32 = 0.0015;

override godrays_tint_r: f32 = 1.0;
override godrays_tint_g: f32 = 0.96;
override godrays_tint_b: f32 = 0.88;

override godrays_morning_direction: f32 = 1.0;
override godrays_morning_strength: f32 = 1.8;
override godrays_afternoon_strength: f32 = 1.15;
override godrays_sunset_strength: f32 = 1.95;

override godrays_morning_r: f32 = 1.0;
override godrays_morning_g: f32 = 0.83;
override godrays_morning_b: f32 = 0.58;

override godrays_sunset_r: f32 = 1.0;
override godrays_sunset_g: f32 = 0.57;
override godrays_sunset_b: f32 = 0.32;

override godrays_sunrise_height: f32 = 0.32;
override godrays_noon_height: f32 = 0.78;

override godrays_beam_contrast: f32 = 1.85;
override godrays_beam_visibility: f32 = 1.75;
override godrays_beam_scattering: f32 = 1.65;

fn godrays_phase(cos_theta: f32, anisotropy: f32) -> f32 {
    let g = clamp(anisotropy, 0.0, 0.9);
    let g2 = g * g;

    let d = max(
        1.0 + g2 - 2.0 * g * cos_theta,
        0.05
    );

    return (1.0 - g2) /
        (12.5663706 * d * sqrt(d));
}

fn godrays_noise(uv: vec2<f32>) -> f32 {
    let p = floor(uv * 4096.0);

    return fract(
        52.9829189 *
        fract(dot(
            p,
            vec2<f32>(0.06711056, 0.00583715)
        ))
    );
}

fn godrays_shadow_visibility(position: vec3<f32>) -> f32 {
    let shadow_coord = shadow_position(position);

    let inside =
        all(shadow_coord.xy >= vec2<f32>(0.002)) &&
        all(shadow_coord.xy <= vec2<f32>(0.998)) &&
        shadow_coord.z >= 0.0 &&
        shadow_coord.z <= 1.0;

    if (!inside) {
        return 1.0;
    }

    return textureSampleCompareLevel(
        shadow_map,
        shadow_sampler,
        shadow_coord.xy,
        shadow_coord.z - godrays_shadow_bias
    );
}

fn godrays_solar_color(
    sun_direction: vec3<f32>,
    out_strength: ptr<function, f32>
) -> vec3<f32> {

    let sun_height = clamp(sun_direction.y, 0.0, 1.0);

    let low_sun = 1.0 - smoothstep(
        godrays_sunrise_height,
        godrays_noon_height,
        sun_height
    );

    let morning_side = sun_direction.x *
        godrays_morning_direction;

    let morning = 1.0 - smoothstep(
        -0.12,
        0.12,
        morning_side
    );

    let sunset = 1.0 - morning;

    let morning_amount = low_sun * morning;
    let sunset_amount = low_sun * sunset;

    let solar_strength = mix(
        godrays_afternoon_strength,
        godrays_morning_strength,
        morning_amount
    );

    let final_strength = mix(
        solar_strength,
        godrays_sunset_strength,
        sunset_amount
    );

    *out_strength = final_strength;

    let neutral_color = vec3<f32>(
        godrays_tint_r,
        godrays_tint_g,
        godrays_tint_b
    );

    let morning_color = vec3<f32>(
        godrays_morning_r,
        godrays_morning_g,
        godrays_morning_b
    );

    let sunset_color = vec3<f32>(
        godrays_sunset_r,
        godrays_sunset_g,
        godrays_sunset_b
    );

    let morning_mix = mix(
        neutral_color,
        morning_color,
        morning_amount
    );

    return mix(
        morning_mix,
        sunset_color,
        sunset_amount
    );
}

fn post(input: PostInput) -> vec4<f32> {
    if (!godrays_enabled ||
        frame.has_shadow == 0u ||
        frame.sun_direction.y <= 0.015 ||
        frame.eye_in == 1u ||
        frame.eye_in == 2u ||
        godrays_intensity <= 0.0 ||
        godrays_weight <= 0.0 ||
        godrays_exposure <= 0.0) {
        return input.color;
    }

    let light_length = length(frame.light_direction);

    if (light_length < 0.0001) {
        return input.color;
    }

    let sun_direction = normalize(frame.sun_direction);
    let light_direction = frame.light_direction / light_length;

    let depth = input.depth;

    var ray_end = view_position(
        input.uv,
        max(depth, 0.0001)
    );

    var ray_length = length(ray_end);

    if (ray_length < 0.0001) {
        return input.color;
    }

    if (depth <= 0.00001) {
        ray_length = godrays_max_distance;

        ray_end *= ray_length /
            max(length(ray_end), 0.0001);
    } else if (ray_length > godrays_max_distance) {
        ray_end *= godrays_max_distance / ray_length;
        ray_length = godrays_max_distance;
    }

    if (ray_length < 1.0) {
        return input.color;
    }

    let view_direction = normalize(ray_end);

    let cos_theta = clamp(
        dot(view_direction, light_direction),
        -1.0,
        1.0
    );

    let phase = godrays_phase(
        cos_theta,
        godrays_anisotropy
    );

    let density = max(godrays_density, 0.0001);

    let requested_samples = clamp(
        godrays_samples,
        8,
        24
    );

    let distance_samples = i32(
        ceil(ray_length / 4.0)
    );

    let sample_count = clamp(
        min(
            requested_samples,
            max(8, distance_samples)
        ),
        8,
        24
    );

    let step_length = ray_length /
        f32(sample_count);

    let half_step = step_length * 0.5;

    let step_transmittance = exp(
        -density * step_length
    );

    let half_transmittance = exp(
        -density * half_step
    );

    let segment_scattering =
        1.0 - step_transmittance;

    let raw_noise = godrays_noise(input.uv);

    let jitter = mix(
        0.5,
        raw_noise,
        0.35
    );

    let decay_factor = clamp(
        godrays_decay,
        0.8,
        1.0
    );

    var scattering = 0.0;
    var transmittance = 1.0;
    var artistic_decay = 1.0;

    for (var i = 0; i < 24; i = i + 1) {
        if (i >= sample_count) {
            break;
        }

        let sample_position =
            (f32(i) + jitter) /
            f32(sample_count);

        let position =
            ray_end * sample_position;

        let visibility =
            godrays_shadow_visibility(position);

        let contribution =
            visibility *
            transmittance *
            half_transmittance *
            segment_scattering *
            artistic_decay;

        scattering += contribution;

        transmittance *= step_transmittance;
        artistic_decay *= decay_factor;
    }

    let optical_depth = 1.0 - exp(
        -density * ray_length
    );

    let normalized_scattering =
        scattering /
        max(optical_depth, 0.0001);

    let atmospheric_scattering =
        normalized_scattering *
        optical_depth *
        phase *
        godrays_intensity *
        godrays_exposure *
        godrays_weight;

    var solar_strength = 1.0;

    let solar_color = godrays_solar_color(
        sun_direction,
        &solar_strength
    );

    let rain_attenuation = clamp(
        1.0 - frame.rain * 0.55,
        0.0,
        1.0
    );

    let distance_fade = smoothstep(
        1.0,
        10.0,
        ray_length
    );

    let beam_contrast = pow(
        clamp(
            1.0 - scattering,
            0.0,
            1.0
        ),
        0.55
    );

    let beam_strength =
        mix(
            1.0,
            beam_contrast,
            clamp(godrays_beam_contrast - 1.0, 0.0, 1.0)
        );

    let volumetric_strength =
        atmospheric_scattering *
        godrays_beam_scattering *
        godrays_beam_visibility *
        beam_strength;

    let final_strength = clamp(
        volumetric_strength *
        solar_strength *
        rain_attenuation *
        distance_fade,
        0.0,
        0.65
    );

    let final_color =
        input.color.rgb +
        solar_color * final_strength;

    return vec4<f32>(
        final_color,
        input.color.a
    );
}
