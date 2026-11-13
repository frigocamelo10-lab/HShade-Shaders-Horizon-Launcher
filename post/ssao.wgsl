
override ao_enabled: bool = true;
override ao_strength: f32 = 1.2;
override ao_radius: f32 = 1.3;
override ao_bias: f32 = 0.06;
override ao_contrast: f32 = 1.2;
override ao_pixel_radius: f32 = 6.0;
override ao_edge_threshold: f32 = 0.06;
override ao_minimum: f32 = 0.72;

fn post(input: PostInput) -> vec4<f32> {
    if (!ao_enabled || ao_strength <= 0.0) {
        return input.color;
    }

    let uv = input.uv;
    let resolution = max(frame.resolution, vec2<f32>(1.0));
    let texel = 1.0 / resolution;

    let depth = depth_at(uv);

    if (depth <= 0.00001) {
        return input.color;
    }

    let center = view_position(uv, depth);

    let left_uv = clamp(uv - vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let right_uv = clamp(uv + vec2<f32>(texel.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let up_uv = clamp(uv - vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0));
    let down_uv = clamp(uv + vec2<f32>(0.0, texel.y), vec2<f32>(0.0), vec2<f32>(1.0));

    let dl = depth_at(left_uv);
    let dr = depth_at(right_uv);
    let du = depth_at(up_uv);
    let dd = depth_at(down_uv);

    if ((dl <= 0.00001 && dr <= 0.00001) ||
        (du <= 0.00001 && dd <= 0.00001)) {
        return input.color;
    }

    var dx = vec3<f32>(0.0);
    var dy = vec3<f32>(0.0);

    if (dl > 0.00001 && dr > 0.00001) {
        let pl = view_position(left_uv, dl);
        let pr = view_position(right_uv, dr);

        let vl = center - pl;
        let vr = pr - center;

        dx = select(vl, vr, length(vr) < length(vl));
    } else if (dl > 0.00001) {
        dx = center - view_position(left_uv, dl);
    } else {
        dx = view_position(right_uv, dr) - center;
    }

    if (du > 0.00001 && dd > 0.00001) {
        let pu = view_position(up_uv, du);
        let pd = view_position(down_uv, dd);

        let vu = center - pu;
        let vd = pd - center;

        dy = select(vu, vd, length(vd) < length(vu));
    } else if (du > 0.00001) {
        dy = center - view_position(up_uv, du);
    } else {
        dy = view_position(down_uv, dd) - center;
    }

    let normal_cross = cross(dx, dy);
    let normal_length = length(normal_cross);

    if (normal_length < 0.00001) {
        return input.color;
    }

    var normal = normal_cross / normal_length;

    if (dot(normal, -center) < 0.0) {
        normal = -normal;
    }

    let kernel = array<vec2<f32>, 8>(
        vec2<f32>(0.130, 0.991),
        vec2<f32>(-0.737, 0.675),
        vec2<f32>(-0.608, -0.794),
        vec2<f32>(0.843, -0.537),
        vec2<f32>(0.438, 0.899),
        vec2<f32>(-0.954, 0.299),
        vec2<f32>(-0.276, -0.961),
        vec2<f32>(0.994, 0.110)
    );

    let safe_radius = max(ao_radius, ao_bias + 0.001);
    let edge_limit = max(ao_edge_threshold, 0.0001);

    var occlusion = 0.0;
    var total_weight = 0.0;

    for (var i = 0u; i < 8u; i = i + 1u) {
        let offset = kernel[i] * ao_pixel_radius * texel;
        let sample_uv = uv + offset;

        if (sample_uv.x <= 0.001 ||
            sample_uv.y <= 0.001 ||
            sample_uv.x >= 0.999 ||
            sample_uv.y >= 0.999) {
            continue;
        }

        let sample_depth = depth_at(sample_uv);

        if (sample_depth <= 0.00001) {
            continue;
        }

        let depth_difference = abs(depth - sample_depth);

        let edge_weight = 1.0 - smoothstep(
            edge_limit * 0.5,
            edge_limit,
            depth_difference
        );

        if (edge_weight <= 0.001) {
            continue;
        }

        let sample_position = view_position(sample_uv, sample_depth);
        let delta = sample_position - center;
        let distance = length(delta);

        if (distance <= ao_bias || distance >= safe_radius) {
            continue;
        }

        let direction = delta / max(distance, 0.0001);
        let hemisphere = max(dot(normal, direction), 0.0);

        let range_weight = 1.0 - smoothstep(
            ao_bias,
            safe_radius,
            distance
        );

        let contribution = hemisphere * range_weight * edge_weight;

        occlusion += contribution;
        total_weight += edge_weight;
    }

    if (total_weight <= 0.001) {
        return input.color;
    }

    let average_occlusion = clamp(
        occlusion / total_weight,
        0.0,
        1.0
    );

    let contrasted = pow(
        average_occlusion,
        max(ao_contrast, 0.01)
    );

    let darkening = clamp(
        contrasted * ao_strength,
        0.0,
        1.0
    );

    let final_ao = max(
        ao_minimum,
        1.0 - darkening
    );

    return vec4<f32>(
        input.color.rgb * final_ao,
        input.color.a
    );
}
