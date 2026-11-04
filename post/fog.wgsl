
override fog_strength: f32 = 1.0;
override fog_distance: f32 = 1.0;
override fog_density: f32 = 1.0;
override fog_horizon_strength: f32 = 1.0;
override fog_horizon_width: f32 = 0.32;
override fog_atmosphere_strength: f32 = 0.85;
override fog_sunset_strength: f32 = 1.0;
override fog_night_strength: f32 = 1.0;
override fog_rain_strength: f32 = 0.65;
override fog_thunder_strength: f32 = 0.75;

override fog_day_horizon_r: f32 = 0.55;
override fog_day_horizon_g: f32 = 0.78;
override fog_day_horizon_b: f32 = 0.95;

override fog_day_zenith_r: f32 = 0.16;
override fog_day_zenith_g: f32 = 0.34;
override fog_day_zenith_b: f32 = 0.62;

override fog_night_horizon_r: f32 = 0.12;
override fog_night_horizon_g: f32 = 0.15;
override fog_night_horizon_b: f32 = 0.30;

override fog_night_zenith_r: f32 = 0.018;
override fog_night_zenith_g: f32 = 0.025;
override fog_night_zenith_b: f32 = 0.075;

fn post(input: PostInput) -> vec4<f32> {
    if input.depth <= 0.000001 {
        return input.color;
    }

    let view_pos = view_position(input.uv, input.depth);
    let distance = length(view_pos);

    let direction = normalize(view_pos);
    let height = direction.y;

    let sun_height = frame.sun_direction.y;

    let day_factor = smoothstep(-0.12, 0.16, sun_height);
    let sunset_factor = 1.0 - smoothstep(0.015, 0.28, abs(sun_height));

    let night_factor = 1.0 - day_factor;

    let gradient = smoothstep(
        -fog_horizon_width,
        0.82,
        height
    );

    let horizon_band = exp(-abs(height) * 7.0);

    let day_horizon = vec3<f32>(
        fog_day_horizon_r,
        fog_day_horizon_g,
        fog_day_horizon_b
    );

    let day_zenith = vec3<f32>(
        fog_day_zenith_r,
        fog_day_zenith_g,
        fog_day_zenith_b
    );

    let night_horizon = vec3<f32>(
        fog_night_horizon_r,
        fog_night_horizon_g,
        fog_night_horizon_b
    );

    let night_zenith = vec3<f32>(
        fog_night_zenith_r,
        fog_night_zenith_g,
        fog_night_zenith_b
    );

    let sunset_horizon = vec3<f32>(
        1.0,
        0.34,
        0.16
    );

    let sunset_zenith = vec3<f32>(
        0.28,
        0.20,
        0.48
    );

    let day_fog = mix(
        day_horizon,
        day_zenith,
        gradient
    );

    let night_fog = mix(
        night_horizon,
        night_zenith,
        gradient
    );

    let sunset_fog = mix(
        sunset_horizon,
        sunset_zenith,
        gradient
    );

    var fog_color = mix(
        night_fog,
        day_fog,
        day_factor
    );

    fog_color = mix(
        fog_color,
        sunset_fog,
        sunset_factor * fog_sunset_strength * 0.82
    );

    let sunset_glow = horizon_band * sunset_factor;

    fog_color += vec3<f32>(
        1.0,
        0.34,
        0.12
    ) * sunset_glow * fog_atmosphere_strength;

    let rain = clamp(frame.rain, 0.0, 1.0);
    let thunder = clamp(frame.thunder, 0.0, 1.0);

    let weather_fog = mix(
        fog_color,
        frame.fog_color,
        rain * fog_rain_strength
    );

    fog_color = mix(
        fog_color,
        weather_fog,
        1.0
    );

    fog_color *= 1.0 - thunder * fog_thunder_strength * 0.35;

    fog_color *= mix(
        fog_night_strength,
        1.0,
        day_factor
    );

    let fog_start = max(
        frame.fog_start,
        0.0
    );

    let fog_end = max(
        frame.fog_end * fog_distance,
        fog_start + 1.0
    );

    let distance_factor = smoothstep(
        fog_start,
        fog_end,
        distance
    );

    let atmospheric_distance = smoothstep(
        fog_start * 0.55,
        fog_end,
        distance
    );

    let horizon_factor = mix(
        1.0,
        1.0 + horizon_band * fog_horizon_strength,
        0.5
    );

    let fog_amount = clamp(
        distance_factor *
        fog_density *
        fog_strength *
        horizon_factor,
        0.0,
        1.0
    );

    let atmosphere_amount = clamp(
        atmospheric_distance *
        fog_atmosphere_strength *
        fog_strength,
        0.0,
        1.0
    );

    let final_amount = max(
        fog_amount,
        atmosphere_amount * fog_amount
    );

    let result = mix(
        input.color.rgb,
        fog_color,
        final_amount
    );

    return vec4<f32>(
        result,
        input.color.a
    );
}
