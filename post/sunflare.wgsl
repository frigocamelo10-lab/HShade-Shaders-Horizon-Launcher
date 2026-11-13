
override sunflare_enabled: bool = true;
override sunflare_shadow_bias: f32 = 0.0015;
override sunflare_shadow_samples: i32 = 12;
override sunflare_max_distance: f32 = 96.0;

fn sunflare_safe_normalize(v: vec3<f32>) -> vec3<f32> {
    let l = length(v);
    return select(vec3<f32>(0.0, 0.0, 1.0), v / max(l, 0.00001), l > 0.00001);
}

fn sunflare_blob(uv: vec2<f32>, center: vec2<f32>, radius: f32) -> f32 {
    let d = (uv - center) / max(radius, 0.0001);
    return exp(-dot(d, d) * 2.0);
}

fn sunflare_ring(uv: vec2<f32>, center: vec2<f32>, radius: f32, width: f32) -> f32 {
    let d = abs(length(uv - center) - radius);
    return exp(-(d * d) / max(width * width, 0.000001) * 2.0);
}

fn sunflare_streak(uv: vec2<f32>, center: vec2<f32>, width: f32, fade: f32) -> f32 {
    let d = uv - center;
    return exp(-abs(d.y) / max(width, 0.0001)) * exp(-abs(d.x) * fade);
}

fn sunflare_cross(uv: vec2<f32>, center: vec2<f32>) -> f32 {
    let d = uv - center;

    let horizontal = exp(-abs(d.y) / 0.0020) *
        exp(-abs(d.x) * 34.0);

    let vertical = exp(-abs(d.x) / 0.0020) *
        exp(-abs(d.y) * 34.0);

    let center_glow = exp(-dot(d, d) / 0.000025);

    return horizontal + vertical + center_glow * 0.5;
}

fn sunflare_project_sun(sun_direction: vec3<f32>) -> vec3<f32> {
    let center_uv = vec2<f32>(0.5, 0.5);

    let center_ray = sunflare_safe_normalize(
        view_position(center_uv, 1.0)
    );

    let left_ray = view_position(vec2<f32>(0.0, 0.5), 1.0);
    let right_ray = view_position(vec2<f32>(1.0, 0.5), 1.0);
    let top_ray = view_position(vec2<f32>(0.5, 0.0), 1.0);
    let bottom_ray = view_position(vec2<f32>(0.5, 1.0), 1.0);

    let horizontal = right_ray - left_ray;
    let vertical = bottom_ray - top_ray;

    let right_axis = sunflare_safe_normalize(
        horizontal - center_ray * dot(horizontal, center_ray)
    );

    let vertical_flat = vertical - center_ray * dot(vertical, center_ray);

    let up_axis = sunflare_safe_normalize(
        vertical_flat - right_axis * dot(vertical_flat, right_axis)
    );

    let horizontal_span = max(dot(horizontal, right_axis), 0.0001);
    let vertical_span = max(dot(vertical, up_axis), 0.0001);
    let center_length = max(length(view_position(center_uv, 1.0)), 0.0001);

    let sun = sunflare_safe_normalize(sun_direction);

    let forward = dot(sun, center_ray);
    let right = dot(sun, right_axis);
    let up = dot(sun, up_axis);

    let depth = max(forward, 0.0001);

    let screen_x = 0.5 + (right / depth) * (center_length / horizontal_span);
    let screen_y = 0.5 + (up / depth) * (center_length / vertical_span);

    return vec3<f32>(screen_x, screen_y, forward);
}

fn sunflare_shadow_visibility(position: vec3<f32>) -> f32 {
    let shadow_coord = shadow_position(position);

    let inside_shadow =
        all(shadow_coord.xy >= vec2<f32>(0.002)) &&
        all(shadow_coord.xy <= vec2<f32>(0.998)) &&
        shadow_coord.z >= 0.0 &&
        shadow_coord.z <= 1.0;

    if (!inside_shadow) {
        return 1.0;
    }

    return textureSampleCompareLevel(
        shadow_map,
        shadow_sampler,
        shadow_coord.xy,
        shadow_coord.z - sunflare_shadow_bias
    );
}

fn sunflare_raycast(sun_direction: vec3<f32>) -> f32 {
    if (frame.has_shadow == 0u) {
        return 1.0;
    }

    let sample_count = clamp(
        sunflare_shadow_samples,
        4,
        16
    );

    let max_distance = max(
        sunflare_max_distance,
        16.0
    );

    var visibility = 1.0;

    for (var i = 0; i < 16; i = i + 1) {
        if (i >= sample_count) {
            break;
        }

        let t = f32(i + 1) / f32(sample_count);

        let distance = mix(
            1.5,
            max_distance,
            t * t
        );

        let ray_position = sun_direction * distance;

        let sample_visibility = sunflare_shadow_visibility(
            ray_position
        );

        visibility = min(
            visibility,
            sample_visibility
        );

        if (visibility < 0.01) {
            return 0.0;
        }
    }

    return smoothstep(0.05, 0.75, visibility);
}

fn post(input: PostInput) -> vec4<f32> {
    if (!sunflare_enabled) {
        return input.color;
    }

    if (frame.eye_in == 1u || frame.eye_in == 2u) {
        return input.color;
    }

    if (frame.sun_direction.y <= 0.015) {
        return input.color;
    }

    let light_length = length(frame.light_direction);

    if (light_length < 0.0001) {
        return input.color;
    }

    let sun_direction = frame.light_direction / light_length;

    let projected = sunflare_project_sun(sun_direction);
    let sun_position = projected.xy;

    if (projected.z <= 0.001) {
        return input.color;
    }

    if (any(sun_position < vec2<f32>(0.0)) ||
        any(sun_position > vec2<f32>(1.0))) {
        return input.color;
    }

    let visibility = sunflare_raycast(sun_direction);

    if (visibility < 0.01) {
        return input.color;
    }

    let daylight = smoothstep(
        0.015,
        0.30,
        frame.sun_direction.y
    );

    let weather = clamp(
        1.0 - frame.rain * 0.65,
        0.0,
        1.0
    );

    let energy = daylight * weather * visibility;

    if (energy < 0.001) {
        return input.color;
    }

    let uv = input.uv;
    let screen_center = vec2<f32>(0.5, 0.5);

    let axis = sun_position - screen_center;
    let axis_length = length(axis);

    let ghost_a = screen_center - axis * 0.35;
    let ghost_b = screen_center + axis * 0.50;
    let ghost_c = screen_center - axis * 0.75;
    let ghost_d = screen_center + axis * 1.15;

    let cross = sunflare_cross(uv, sun_position);

    let core = sunflare_blob(uv, sun_position, 0.016);
    let halo = sunflare_ring(uv, sun_position, 0.040, 0.009);
    let outer_halo = sunflare_ring(uv, sun_position, 0.070, 0.016);

    let ghost_1 = sunflare_blob(uv, ghost_a, 0.035);
    let ghost_2 = sunflare_blob(uv, ghost_b, 0.027);
    let ghost_3 = sunflare_blob(uv, ghost_c, 0.043);
    let ghost_4 = sunflare_blob(uv, ghost_d, 0.023);

    let ring_1 = sunflare_ring(uv, ghost_b, 0.023, 0.006);
    let ring_2 = sunflare_ring(uv, ghost_c, 0.035, 0.008);
    let ring_3 = sunflare_ring(uv, ghost_d, 0.018, 0.005);

    let streak_1 = sunflare_streak(uv, sun_position, 0.0018, 3.8);
    let streak_2 = sunflare_streak(uv, sun_position, 0.0035, 6.0);

    let warm = vec3<f32>(1.0, 0.80, 0.58);
    let orange = vec3<f32>(1.0, 0.55, 0.32);
    let cyan = vec3<f32>(0.48, 0.82, 1.0);
    let violet = vec3<f32>(0.78, 0.60, 1.0);

    let ghost_color =
        warm * (ghost_1 * 0.27 + ghost_4 * 0.16) +
        orange * (ghost_2 * 0.20 + ghost_3 * 0.15) +
        cyan * (ring_1 * 0.16 + ring_2 * 0.12) +
        violet * (ring_3 * 0.14);

    let halo_color =
        vec3<f32>(1.0, 0.86, 0.68) *
        (halo * 0.15 + outer_halo * 0.05);

    let core_color =
        vec3<f32>(1.0, 0.94, 0.82) *
        core * 0.18;

    let cross_color =
        vec3<f32>(1.0, 0.91, 0.76) *
        cross * 0.065;

    let streak_color =
        vec3<f32>(0.82, 0.90, 1.0) *
        (streak_1 * 0.04 + streak_2 * 0.022);

    let edge_fade = clamp(
        1.0 - axis_length * 0.12,
        0.65,
        1.0
    );

    let flare = (
        ghost_color +
        halo_color +
        core_color +
        cross_color +
        streak_color
    ) * energy * edge_fade;

    return vec4<f32>(
        input.color.rgb + flare,
        input.color.a
    );
}
