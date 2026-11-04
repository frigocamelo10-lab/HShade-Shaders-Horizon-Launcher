
override color_saturation: f32 = 1.18;
override color_vibrance: f32 = 0.30;
override color_contrast: f32 = 1.08;
override color_exposure: f32 = 0.0;
override color_brightness: f32 = 0.0;

override color_temperature: f32 = 0.025;
override color_tint: f32 = 0.0;

override color_tonemap_strength: f32 = 0.65;
override color_highlight_compression: f32 = 0.12;

override color_day_strength: f32 = 0.12;
override color_sunrise_strength: f32 = 0.55;
override color_sunset_strength: f32 = 0.65;
override color_night_strength: f32 = 0.48;
override color_rain_strength: f32 = 0.55;
override color_storm_strength: f32 = 0.75;

override color_adaptive_contrast: f32 = 0.12;
override color_shadow_tint_strength: f32 = 0.12;
override color_highlight_tint_strength: f32 = 0.10;

override color_underwater_strength: f32 = 0.35;
override color_final_intensity: f32 = 1.0;

fn color_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn color_saturate(value: f32) -> f32 {
    return clamp(value, 0.0, 1.0);
}

fn color_time_weight(time: f32, center: f32, radius: f32) -> f32 {
    let difference = abs(time - center);
    let distance = min(difference, 1.0 - difference);
    return 1.0 - smoothstep(radius * 0.35, radius, distance);
}

fn color_apply_contrast(color: vec3<f32>, amount: f32) -> vec3<f32> {
    return (color - vec3<f32>(0.5)) * amount + vec3<f32>(0.5);
}

fn color_apply_vibrance(color: vec3<f32>, amount: f32) -> vec3<f32> {
    let maximum = max(max(color.r, color.g), color.b);
    let minimum = min(min(color.r, color.g), color.b);
    let saturation = maximum - minimum;
    let gray = vec3<f32>(color_luminance(color));
    let vibrance = amount * (1.0 - saturation);
    return mix(gray, color, 1.0 + vibrance);
}

fn color_apply_temperature(color: vec3<f32>, temperature: f32, tint: f32) -> vec3<f32> {
    return color + vec3<f32>(
        temperature + tint * 0.25,
        tint * -0.25,
        -temperature + tint * 0.25
    );
}

fn color_apply_split_toning(
    color: vec3<f32>,
    shadow_color: vec3<f32>,
    highlight_color: vec3<f32>,
    strength: f32
) -> vec3<f32> {
    let luminance = color_luminance(color);
    let shadows = 1.0 - smoothstep(0.05, 0.65, luminance);
    let highlights = smoothstep(0.35, 0.95, luminance);

    let shadow_mix = color * mix(
        vec3<f32>(1.0),
        shadow_color,
        shadows * strength
    );

    return shadow_mix * mix(
        vec3<f32>(1.0),
        highlight_color,
        highlights * strength
    );
}

fn color_apply_tonemap(color: vec3<f32>) -> vec3<f32> {
    let x = max(color, vec3<f32>(0.0));

    let numerator = x * (2.51 * x + vec3<f32>(0.03));
    let denominator = x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14);

    return clamp(
        numerator / denominator,
        vec3<f32>(0.0),
        vec3<f32>(1.0)
    );
}

fn color_soft_highlights(color: vec3<f32>) -> vec3<f32> {
    let brightness = max(max(color.r, color.g), color.b);
    let excess = max(brightness - 1.0, 0.0);
    let compression = max(color_highlight_compression, 0.001);

    let compressed = 1.0 + excess / (1.0 + excess / compression);

    let scale = select(
        1.0,
        compressed / max(brightness, 0.0001),
        brightness > 1.0
    );

    return color * scale;
}

fn post(input: PostInput) -> vec4<f32> {
    var color = input.color.rgb;

    let time = frame.day_time;
    let rain = color_saturate(frame.rain);
    let thunder = color_saturate(frame.thunder);

    let sunrise = color_time_weight(time, 0.0, 0.105);
    let sunset = color_time_weight(time, 0.5, 0.105);

    let daylight = smoothstep(-0.12, 0.22, frame.sun_direction.y);
    let night = 1.0 - daylight;

    let midday = daylight * (1.0 - max(sunrise, sunset));

    let storm = color_saturate(thunder);
    let rainy_weather = color_saturate(rain * (1.0 - storm * 0.25));

    let weather_amount = color_saturate(
        rainy_weather * color_rain_strength
    );

    let storm_amount = color_saturate(
        storm * color_storm_strength
    );

    color *= exp2(color_exposure);
    color += vec3<f32>(color_brightness);

    color = color_apply_temperature(
        color,
        color_temperature,
        color_tint
    );

    let day_tint = vec3<f32>(1.025, 1.015, 0.985);
    let sunrise_tint = vec3<f32>(1.10, 0.91, 0.76);
    let sunset_tint = vec3<f32>(1.13, 0.82, 0.67);
    let night_tint = vec3<f32>(0.72, 0.82, 1.12);

    color *= mix(
        vec3<f32>(1.0),
        day_tint,
        midday * color_day_strength
    );

    color *= mix(
        vec3<f32>(1.0),
        sunrise_tint,
        sunrise * color_sunrise_strength
    );

    color *= mix(
        vec3<f32>(1.0),
        sunset_tint,
        sunset * color_sunset_strength
    );

    color *= mix(
        vec3<f32>(1.0),
        night_tint,
        night * color_night_strength
    );

    let rain_tint = vec3<f32>(0.78, 0.86, 1.08);
    let storm_tint = vec3<f32>(0.72, 0.80, 0.96);

    color *= mix(
        vec3<f32>(1.0),
        rain_tint,
        weather_amount
    );

    color *= mix(
        vec3<f32>(1.0),
        storm_tint,
        storm_amount
    );

    let weather_exposure = weather_amount * 0.10 + storm_amount * 0.16;
    color *= exp2(-weather_exposure);

    let day_shadows = vec3<f32>(0.96, 0.99, 1.035);
    let night_shadows = vec3<f32>(0.76, 0.84, 1.12);
    let warm_highlights = vec3<f32>(1.08, 1.025, 0.94);
    let cold_highlights = vec3<f32>(0.92, 0.97, 1.08);

    let shadow_tint = mix(
        day_shadows,
        night_shadows,
        night
    );

    let highlight_tint = mix(
        warm_highlights,
        cold_highlights,
        night
    );

    color = color_apply_split_toning(
        color,
        shadow_tint,
        highlight_tint,
        color_shadow_tint_strength
    );

    let weather_saturation = 1.0 - weather_amount * 0.18 - storm_amount * 0.22;

    let saturation = color_saturation * weather_saturation;

    color = color_apply_vibrance(
        color,
        color_vibrance
    );

    color = mix(
        vec3<f32>(color_luminance(color)),
        color,
        saturation
    );

    let adaptive_contrast = color_contrast
        + color_adaptive_contrast * midday
        - weather_amount * 0.05;

    color = color_apply_contrast(
        color,
        adaptive_contrast
    );

    color = color_soft_highlights(color);

    let mapped = color_apply_tonemap(color);

    color = mix(
        color,
        mapped,
        color_tonemap_strength
    );

    if (frame.eye_in == 1u) {
        let underwater_tint = vec3<f32>(0.55, 0.78, 0.95);
        color *= mix(
            vec3<f32>(1.0),
            underwater_tint,
            color_underwater_strength
        );
    }

    color = max(color, vec3<f32>(0.0));
    color *= color_final_intensity;

    return vec4<f32>(
        color,
        input.color.a
    );
}
