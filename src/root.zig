const std = @import("std");

extern fn consoleLog(arg: i64) void;
extern fn preparePaint() void;
extern fn paintShip(x: f64, y: f64) void;
extern fn addResult(x: f64, y: f64, color: u8) void;
extern fn finishPaint() void;
extern fn debugBlock(nr: u32, x: f64, y: f64) void;
extern fn finished() void;

var globWidth: u32 = 0;
// var planetPositions: [*]f64 = undefined;

// 4 byte for x, 4 byte for y, 8 byte ship
var xy: []f64 = undefined;
// 4 byte for sx, 4 byte for sy, 8 byte ship
var sxy: []f64 = undefined;
// 4 byte for sx, 4 byte for sy
var startPos: []f64 = undefined;
// 1 byte per ship, -1 = not landed, >=0 = planet unevaluated (new), -2 = waiting for rewrite
var landed: []i8 = undefined;
var radius: f64 = 51;
var rad2: f64 = undefined;
const dT: f64 = 0.3;

// 4th order Yoshida https://en.wikipedia.org/wiki/Leapfrog_integration
const THIRD_S_2: f64 = std.math.pow(f64, 2.0, 1.0 / 3.0);
const w0 = -THIRD_S_2 / (2 - THIRD_S_2);
const w1 = 1 / (2 - THIRD_S_2);
const c1 = w1 / 2;
const c4 = w1 / 2;
const c2 = (w0 + w1) / 2;
const c3 = (w0 + w1) / 2;

const d1 = w1;
const d3 = w1;
const d2 = w0;

const Config = struct {
    width: usize,
    height: usize,
    blockSize: usize,
    length: usize,
    extra: usize,
    speed: f64,
    dampening: f64,
    planetCount: u8,
    planetPositions: [200]f64,
    nextShip: usize,
    maxPoints: usize,
    pointsX: usize = 0,
    loops: usize = 5,
    currentlength: usize = 0,
    showShips: bool = true,
};
var config: Config = undefined;
var freeShips: usize = 0;
var createShips: usize = 0;
var packetLock: bool = false;

export fn init(width: usize, height: usize, blockSize: usize, length: usize, extra: usize, speed: f64, dampening: f64) i8 {
    // 3*4 byte for exchange
    // each active point needs
    // 8 byte for xy
    // 8 byte for sxy
    // 8 byte for startPoints
    // 1 byte for "landed" information
    // 1 byte for "is new landed" information
    // some bytes between for alignment

    rad2 = radius * radius;

    var pages: usize = 1 + 2 * 4 * length / 16 / 1024;
    consoleLog(pages);
    xy = std.heap.wasm_allocator.alloc(f64, pages * 16 * 1024) catch {
        return -1;
    };
    sxy = std.heap.wasm_allocator.alloc(f64, pages * 16 * 1024) catch {
        return -1;
    };
    startPos = std.heap.wasm_allocator.alloc(f64, pages * 16 * 1024) catch {
        return -1;
    };

    pages = 1 + length / 16 / 1024;
    consoleLog(pages);
    landed = std.heap.wasm_allocator.alloc(i8, pages * 16 * 1024) catch {
        return -1;
    };

    config = Config{ .width = width, .height = height, .blockSize = blockSize, .length = length, .extra = extra, .speed = speed, .dampening = dampening, .planetCount = 0, .planetPositions = undefined, .nextShip = 0, .maxPoints = width * height / blockSize / blockSize };
    config.pointsX = width / blockSize;
    config.currentlength = getBlockStartSize() + config.extra;

    freeShips = length;

    for (0..length) |i| {
        landed[i] = 99;
    }
    for (0..getBlockStartSize()) |i| {
        if (initShip(i) == 0) {
            break;
        }
    }
    debugBlock(0, c1, c2);
    debugBlock(0, c3, c4);
    debugBlock(0, d1, d2);
    debugBlock(0, d3, d3);
    return 0;
}
export fn setLoops(loops: u16) void {
    config.loops = loops;
}
export fn setShowShips(showShips: bool) bool {
    const res = config.showShips;
    config.showShips = showShips;
    return res;
}

fn nextPacket() void {
    if (packetLock) {
        return;
    }
    packetLock = true;
    var created: u32 = 0;
    var search: u32 = 0;
    while (created < config.currentlength - config.extra and search < config.length) {
        if (landed[search] >= 0) {
            if (initShip(search) == 0) {
                consoleLog(499);
                consoleLog(499);
                consoleLog(499);
                consoleLog(499);
                return;
            }
            created += 1;
        }
        search += 1;
    }
    packetLock = false;
}

fn getCols() u32 {
    return @as(usize, @intFromFloat(1.6 * std.math.sqrt(@as(f64, @floatFromInt(config.length - config.extra)))));
}
fn getBlockStartSize() u32 {
    const cols = getCols();
    const rows = (config.length - config.extra) / cols;
    return cols * rows;
}
fn getBlockStartPos(nr: usize, result: [*]u32) void {
    const cols = getCols();
    const rows = (config.length - config.extra) / cols;
    const metaBlockSize = cols * rows;
    const metaPos = nr / metaBlockSize;
    const rest = nr - metaPos * metaBlockSize;
    result[0] = config.blockSize * (metaPos % 5 * cols + rest % cols) + config.blockSize / 2;
    result[1] = config.blockSize * (metaPos / 5 * rows + rest / cols) + config.blockSize / 2;
}

fn getStartPos(nr: usize, result: [*]u32) void {
    result[0] = config.blockSize * (nr % config.pointsX) + config.blockSize / 2;
    result[1] = config.blockSize * (nr / (config.pointsX)) + config.blockSize / 2;
}

var pos = [2]u32{ 0, 0 };

// i = memory place of ship
fn initShip(i: usize) u8 {
    // nr = point on image
    const nr = config.nextShip;
    if (nr >= config.maxPoints) {
        return 0;
    }
    //consoleLog(199);
    //consoleLog(i);
    //consoleLog(nr);
    //consoleLog(198);
    config.nextShip += 1;
    getBlockStartPos(nr, &pos);
    landed[i] = -1;
    startPos[2 * i] = @as(f64, @floatFromInt(pos[0]));
    startPos[2 * i + 1] = @as(f64, @floatFromInt(pos[1]));
    // debugBlock(nr, startPos[2 * i], startPos[2 * i + 1]);
    xy[2 * i] = startPos[2 * i];
    xy[2 * i + 1] = startPos[2 * i + 1];
    sxy[2 * i] = 0;
    sxy[2 * i + 1] = 0;
    freeShips -= 1;
    return 1;
}

export fn addPlanet(x: f64, y: f64) i8 {
    config.planetPositions[2 * config.planetCount] = x;
    config.planetPositions[2 * config.planetCount + 1] = y;
    config.planetCount += 1;
    return 0;
}

export fn setLength(l: usize) usize {
    if (l < config.length) {
        config.currentlength = l;
        return 0;
    }
    return config.length;
}
fn getAi(xi: f64, yi: f64, ax: *f64, ay: *f64) i8 {
    ax.* = 0;
    ay.* = 0;
    for (0..config.planetCount) |planet| {
        //console.log("position = ", p);
        const dx: f64 = config.planetPositions[2 * planet] - xi;
        const dy: f64 = config.planetPositions[2 * planet + 1] - yi;
        const r2 = dx * dx + dy * dy;
        if (r2 <= rad2) {
            return @intCast(planet);
        }
        ax.* += config.speed / (1 + r2) * dx;
        ay.* += config.speed / (1 + r2) * dy;
        // console.log("dx=", dx, " dy=", dy," ax=", ax," ay=" , ay);
    }
    return -1;
}

fn landPlanet(i: usize, planet: i8) void {
    landed[i] = planet;
    freeShips += 1;
    //changed = true;
    //consoleLog(24);
    //consoleLog(nr);
    addResult(startPos[2 * i], startPos[2 * i + 1], @intCast(planet));
}

export fn updatePositions() i8 {
    const loops = config.loops;
    var ax: f64 = undefined;
    var ay: f64 = undefined;
    var xm: f64 = undefined;
    var ym: f64 = undefined;
    var vxm: f64 = undefined;
    var vym: f64 = undefined;

    //var changed: bool = false;
    for (0..config.length) |i| {
        if (landed[i] >= 0) {
            continue;
        }

        consoleLog(64);
        ship: for (0..loops) |_| {
            // step 1, x_i¹
            xm = xy[2 * i] + c1 * sxy[2 * i] * dT;
            ym = xy[2 * i + 1] + c1 * sxy[2 * i + 1] * dT;
            debugBlock(i, xm, ym);
            debugBlock(i, xm, ym);

            var planet = getAi(xm, ym, &ax, &ay);
            if (0 <= planet) {
                landPlanet(i, planet);
                break :ship;
            }
            debugBlock(i, ax, ay);

            // v_i¹
            vxm = sxy[2 * i] + d1 * ax * dT;
            vym = sxy[2 * i + 1] + d1 * ay * dT;
            debugBlock(i, vxm, vym);

            // step 2, x_i²
            xm = xm + c2 * vxm * dT;
            ym = ym + c2 * vym * dT;
            debugBlock(i, xm, ym);
            debugBlock(i, xm, ym);

            planet = getAi(xm, ym, &ax, &ay);
            if (0 <= planet) {
                landPlanet(i, planet);
                break :ship;
            }
            debugBlock(i, ax, ay);

            // v_i²
            vxm = xm + d2 * ax * dT;
            vym = ym + d2 * ay * dT;
            debugBlock(i, vxm, vym);

            // step 3, x_i³
            xm = xm + c3 * vxm * dT;
            ym = ym + c3 * vym * dT;
            debugBlock(i, xm, ym);
            debugBlock(i, xm, ym);

            planet = getAi(xm, ym, &ax, &ay);
            if (0 <= planet) {
                landPlanet(i, planet);
                break :ship;
            }
            debugBlock(i, ax, ay);

            // v_i³
            vxm = xm + d3 * ax * dT;
            vym = ym + d3 * ay * dT;
            debugBlock(i, vxm, vym);

            xy[2 * i] = xm + c4 * vxm * dT;
            xy[2 * i + 1] = ym + c4 * vym * dT;
            debugBlock(i, xy[2 * i], xy[2 * i + 1]);
            debugBlock(i, xy[2 * i], xy[2 * i + 1]);

            sxy[2 * i] = vxm * config.dampening;
            sxy[2 * i + 1] = vym * config.dampening;
        }
        consoleLog(65);
    }
    if (!packetLock and freeShips >= config.length - config.extra - 1) {
        nextPacket();
    }
    //if (changed) {
    //    preparePaint();
    //}
    return 0;
}

export fn paint() i8 {
    preparePaint();
    if (config.showShips) {
        var s: usize = 0;
        var shown: usize = 0;

        while (s < config.length and shown < 150000) {
            if (landed[s] < 0) {
                paintShip(xy[2 * s], xy[2 * s + 1]);
                shown += 1;
            }
            s += 1;
        }
    }
    finishPaint();
    return 0;
}

// The returned pointer will be used as an offset integer to the wasm memory
export fn getColors() [*]u8 {
    return @ptrCast(&landed);
}

export fn getData(i: usize) u32 {
    //std.debug.print("getData: {d}\n", .{i});
    return globWidth + i;
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}
