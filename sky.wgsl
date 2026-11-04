
override sky_strength: f32 = 1.0;
override sky_gradient_strength: f32 = 1.0;
override sky_horizon_strength: f32 = 1.0;
override sky_horizon_width: f32 = 0.32;
override sky_horizon_glow: f32 = 0.65;
override sky_zenith_strength: f32 = 1.0;
override sky_sunset_strength: f32 = 1.0;
override sky_night_strength: f32 = 1.0;
override sky_atmosphere_warmth: f32 = 1.0;
override sky_rain_darkening: f32 = 0.55;

override sky_day_horizon_r: f32 = 0.48;
override sky_day_horizon_g: f32 = 0.78;
override sky_day_horizon_b: f32 = 1.0;

override sky_day_zenith_r: f32 = 0.035;
override sky_day_zenith_g: f32 = 0.22;
override sky_day_zenith_b: f32 = 0.58;

override sky_night_horizon_r: f32 = 0.12;
override sky_night_horizon_g: f32 = 0.16;
override sky_night_horizon_b: f32 = 0.36;

override sky_night_zenith_r: f32 = 0.008;
override sky_night_zenith_g: f32 = 0.015;
override sky_night_zenith_b: f32 = 0.065;

fn sky(input: SkyInput) -> vec4<f32> {
    let direction = normalize(input.direction);
    let height = direction.y;

    let sun_height = frame.sun_direction.y;

    let day_factor = smoothstep(-0.12, 0.16, sun_height);
    let night_factor = 1.0 - day_factor;

    let sunset_factor = 1.0 - smoothstep(0.015, 0.28, abs(sun_height));

    let gradient = smoothstep(
        -sky_horizon_width,
        0.82,
        height
    );

    let horizon_band = exp(-abs(height) * 7.0);

    let day_horizon = vec3<f32>(
        sky_day_horizon_r,
        sky_day_horizon_g,
        sky_day_horizon_b
    );

    let day_zenith = vec3<f32>(
        sky_day_zenith_r,
        sky_day_zenith_g,
        sky_day_zenith_b
    );

    let night_horizon = vec3<f32>(
        sky_night_horizon_r,
        sky_night_horizon_g,
        sky_night_horizon_b
    );

    let night_zenith = vec3<f32>(
        sky_night_zenith_r,
        sky_night_zenith_g,
        sky_night_zenith_b
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

    let day_sky = mix(
        day_horizon,
        day_zenith,
        gradient
    );

    let night_sky = mix(
        night_horizon,
        night_zenith,
        gradient
    );

    let sunset_sky = mix(
        sunset_horizon,
        sunset_zenith,
        gradient
    );

    let sunset_amount = sunset_factor * sky_sunset_strength;

    var sky_color = mix(
        night_sky,
        day_sky,
        day_factor
    );

    sky_color = mix(
        sky_color,
        sunset_sky,
        sunset_amount * 0.82 * (1.0 - gradient * 0.55)
    );

    let sunset_glow = sunset_amount * horizon_band;

    sky_color += vec3<f32>(
        1.0,
        0.34,
        0.12
    ) * sunset_glow * sky_horizon_glow * sky_atmosphere_warmth;

    let horizon_light = horizon_band * sky_horizon_strength;

    sky_color += vec3<f32>(
        0.12,
        0.20,
        0.32
    ) * horizon_light * day_factor * sky_horizon_glow;

    let rain_darkening = clamp(
        frame.rain * sky_rain_darkening,
        0.0,
        0.85
    );

    sky_color *= 1.0 - rain_darkening;

    sky_color *= mix(
        sky_night_strength,
        sky_zenith_strength,
        day_factor
    );

    sky_color = mix(
        input.color.rgb,
        sky_color,
        clamp(sky_gradient_strength, 0.0, 1.0)
    );

    sky_color *= sky_strength;

    return vec4<f32>(
        max(sky_color, vec3<f32>(0.0)),
        input.color.a
    );
}
