
override motion_blur_enabled: bool = true;
override motion_tolerance: f32 = 0.5;
override motion_intensity: f32 = 0.65;
override motion_threshold: f32 = 24.0;

fn post(input: PostInput) -> vec4<f32> {
    let original = input.color;

    if (!motion_blur_enabled) {
        return original;
    }

    if (frame.delta_time <= 0.0) {
        return original;
    }

    let depth = input.depth;

    if (depth <= 0.00001) {
        return original;
    }

    let current_position = view_position(input.uv, depth);
    let previous_position = current_position + frame.camera_motion;

    let previous_clip = frame.previous_view_projection * vec4<f32>(
        previous_position,
        1.0
    );

    if (previous_clip.w <= 0.00001) {
        return original;
    }

    let previous_ndc = previous_clip.xy / previous_clip.w;

    let previous_uv = vec2<f32>(
        previous_ndc.x * 0.5 + 0.5,
        0.5 - previous_ndc.y * 0.5
    );

    let motion = input.uv - previous_uv;
    let motion_pixels = motion * frame.resolution;
    let motion_length = length(motion_pixels);

    if (motion_length <= motion_tolerance) {
        return original;
    }

    let maximum_motion = max(motion_threshold, 0.1);
    let clamped_length = min(motion_length, maximum_motion);

    let motion_direction = normalize(motion_pixels);
    let motion_uv = motion_direction * clamped_length / frame.resolution;

    let tolerance_fade = smoothstep(
        motion_tolerance,
        max(motion_tolerance + 0.01, maximum_motion),
        motion_length
    );

    let strength = clamp(
        motion_intensity * tolerance_fade,
        0.0,
        1.0
    );

    var blurred = original.rgb;
    var total_weight = 1.0;

    for (var i: i32 = 1; i <= 8; i = i + 1) {
        let t = f32(i) / 8.0;

        let sample_uv = clamp(
            input.uv - motion_uv * t,
            vec2<f32>(0.001),
            vec2<f32>(0.999)
        );

        let sample_color = textureSampleLevel(
            previous,
            linear_sampler,
            sample_uv,
            0.0
        );

        let weight = 1.0 - t * 0.65;

        blurred += sample_color.rgb * weight;
        total_weight += weight;
    }

    blurred /= total_weight;

    let result = mix(
        original.rgb,
        blurred,
        strength
    );

    return vec4<f32>(result, original.a);
}
