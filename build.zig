const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .atomics,
            .simd128, // Enable SIMD
            .relaxed_simd,
            .bulk_memory, // Enable bulk memory operations
            .multivalue, // Enable multi-value returns
            .reference_types, // Enable reference types
        }),
    });

    const exe = b.addExecutable(.{
        .name = "gravity",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        //.optimize = .Debug,
    });

    // <https://github.com/ziglang/zig/issues/8633>
    //exe.global_base = 6560;
    exe.entry = .disabled;
    exe.rdynamic = true;
    exe.stack_size = std.wasm.page_size * 2;

    b.installArtifact(exe);
}
