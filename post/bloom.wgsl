
override bloom_enabled: bool = true;
override bloom_intensity: f32 = 0.8;
override bloom_threshold: f32 = 0.72;
override bloom_samples: i32 = 4;

fn post(input: PostInput) -> vec4<f32> {
    let original = input.color;

    if (!bloom_enabled || bloom_intensity <= 0.0) {
        return original;
    }

    let resolution = max(vec2<f32>(textureDimensions(previous)), vec2<f32>(1.0));
    let texel = 1.0 / resolution;
    let radius = texel * 4.0;

    var bloom_sum = vec3<f32>(0.0);
    var total_samples = 0.0;

    for (var i: i32 = 0; i < 4; i = i + 1) {
        if (i < bloom_samples) {
            var offset = vec2<f32>(0.0);

            if (i == 0) {
                offset = vec2<f32>(-radius.x, 0.0);
            } else if (i == 1) {
                offset = vec2<f32>(radius.x, 0.0);
            } else if (i == 2) {
                offset = vec2<f32>(0.0, -radius.y);
            } else {
                offset = vec2<f32>(0.0, radius.y);
            }

            let sample_uv = clamp(
                input.uv + offset,
                vec2<f32>(0.001),
                vec2<f32>(0.999)
            );

            let sample_color = textureSampleLevel(
                previous,
                linear_sampler,
                sample_uv,
                0.0
            ).rgb;

            let brightness = dot(
                sample_color,
                vec3<f32>(0.2126, 0.7152, 0.0722)
            );

            let contribution = max(
                brightness - bloom_threshold,
                0.0
            ) / max(brightness, 0.0001);

            bloom_sum += sample_color * contribution;
            total_samples += 1.0;
        }
    }

    if (total_samples <= 0.0) {
        return original;
    }

    let bloom_color = bloom_sum / total_samples;

    let result = clamp(
        original.rgb + bloom_color * bloom_intensity,
        vec3<f32>(0.0),
        vec3<f32>(1.0)
    );

    return vec4<f32>(result, original.a);
}
