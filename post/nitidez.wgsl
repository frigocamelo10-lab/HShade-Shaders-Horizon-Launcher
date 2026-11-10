
override sharpen_enabled: bool = true;
override sharpen_intensity: f32 = 0.8;
override sharpen_size: f32 = 1.0;

fn post(input: PostInput) -> vec4<f32> {
    let original = input.color;

    if (!sharpen_enabled || sharpen_intensity <= 0.0) {
        return original;
    }

    let resolution = max(
        vec2<f32>(textureDimensions(previous)),
        vec2<f32>(1.0)
    );

    let texel = sharpen_size / resolution;

    let left = textureSampleLevel(
        previous,
        linear_sampler,
        clamp(input.uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.001), vec2<f32>(0.999)),
        0.0
    ).rgb;

    let right = textureSampleLevel(
        previous,
        linear_sampler,
        clamp(input.uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.001), vec2<f32>(0.999)),
        0.0
    ).rgb;

    let top = textureSampleLevel(
        previous,
        linear_sampler,
        clamp(input.uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.001), vec2<f32>(0.999)),
        0.0
    ).rgb;

    let bottom = textureSampleLevel(
        previous,
        linear_sampler,
        clamp(input.uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.001), vec2<f32>(0.999)),
        0.0
    ).rgb;

    let surrounding = (left + right + top + bottom) * 0.25;

    let detail = original.rgb - surrounding;

    let sharpened = original.rgb + detail * sharpen_intensity;

    return vec4<f32>(
        clamp(sharpened, vec3<f32>(0.0), vec3<f32>(1.0)),
        original.a
    );
}
