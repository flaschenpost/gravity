const std = @import("std");

const TheVersion: u16 = 11;
extern fn consoleLog(arg: i64) void;
extern fn preparePaint() void;
extern fn paintShip(x: f32, y: f32) void;
extern fn addResult(x: f32, y: f32, color: u8) void;
extern fn finishPaint() void;
extern fn debugBlock(nr: u32, x: f32, y: f32) void;
extern fn finished() void;

var globWidth: u32 = 0;
// var planetPositions: [*]f32 = undefined;

// 4 byte for x, 4 byte for y, 8 byte ship
var xy: []f32 = undefined;
// 4 byte for sx, 4 byte for sy, 8 byte ship
var sxy: []f32 = undefined;
// ai
var axy: []f32 = undefined;
// 4 byte for sx, 4 byte for sy
var startPos: []f32 = undefined;
// 1 byte per ship, -1 = not landed, >=0 = planet unevaluated (new), -2 = waiting for rewrite
var landed: []i8 = undefined;
var radius: f32 = 11;
var rad2: f32 = undefined;

const Config = struct {
    width: usize,
    height: usize,
    blockSize: usize,
    length: usize,
    extra: usize,
    speed: f32,
    dampening: f32,
    planetCount: u8,
    planetPositions: [200]f32,
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
var blockCols: usize = undefined;
var blockRows: usize = undefined;
var pixelsPerMiniCol: usize = undefined;
var rowsPerMiniBlock: usize = undefined;

export fn init(width: usize, height: usize, blockSize: usize, length: usize, extra: usize, speed: f32, dampening: f32) i8 {
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
    xy = std.heap.wasm_allocator.alloc(f32, pages * 16 * 1024) catch {
        return -1;
    };
    sxy = std.heap.wasm_allocator.alloc(f32, pages * 16 * 1024) catch {
        return -1;
    };
    axy = std.heap.wasm_allocator.alloc(f32, pages * 16 * 1024) catch {
        return -1;
    };
    startPos = std.heap.wasm_allocator.alloc(f32, pages * 16 * 1024) catch {
        return -1;
    };

    pages = 1 + length / 16 / 1024;
    consoleLog(pages);
    landed = std.heap.wasm_allocator.alloc(i8, pages * 16 * 1024) catch {
        return -1;
    };

    config = Config{ .width = width, .height = height, .blockSize = blockSize, .length = length, .extra = extra, .speed = speed, .dampening = dampening, .planetCount = 0, .planetPositions = undefined, .nextShip = 0, .maxPoints = width * height / blockSize / blockSize };
    config.pointsX = width / blockSize;

    const part: f32 = @sqrt(@as(f32, @floatFromInt(width * height)) / @as(f32, @floatFromInt((length - extra) * blockSize * blockSize)));

    blockCols = 1 + @as(usize, @intFromFloat(part));
    blockRows = 1 + @as(usize, @intFromFloat(part));

    pixelsPerMiniCol = @as(usize, width / blockCols);
    rowsPerMiniBlock = @as(usize, height / blockRows);

    config.currentlength = rowsPerMiniBlock * pixelsPerMiniCol;
    if (config.currentlength > length - extra) {
        rowsPerMiniBlock -= 1;
        config.currentlength = rowsPerMiniBlock * pixelsPerMiniCol;
    }
    consoleLog(399);
    consoleLog(length);
    // block columns per row
    consoleLog(blockCols);
    // block rows per column
    consoleLog(blockRows);
    consoleLog(pixelsPerMiniCol);
    consoleLog(rowsPerMiniBlock);
    consoleLog(config.currentlength);

    // consoleLog(config.pointsX);
    //config.currentlength = getBlockStartSize() + config.extra;

    freeShips = length;

    for (0..length) |i| {
        landed[i] = 99;
    }
    for (0..config.currentlength) |i| {
        if (initShip(i) == 0) {
            break;
        }
    }
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
    while (created < config.currentlength and created < config.length - config.extra and search < config.length) {
        if (landed[search] >= 0) {
            if (initShip(search) == 0) {
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

fn getBlockStartPos(nr: usize, result: [*]u32) void {
    const metaBlockSize = pixelsPerMiniCol * rowsPerMiniBlock;
    const metaPos = nr / metaBlockSize;
    const rest = nr - metaPos * metaBlockSize;
    result[0] = config.blockSize * (metaPos % blockCols * pixelsPerMiniCol + rest % pixelsPerMiniCol) + config.blockSize / 2;
    result[1] = config.blockSize * (metaPos / blockCols * rowsPerMiniBlock + rest / pixelsPerMiniCol) + config.blockSize / 2;
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
    config.nextShip += 1;
    getBlockStartPos(nr, &pos);
    landed[i] = -1;
    startPos[2 * i] = @as(f32, @floatFromInt(pos[0]));
    startPos[2 * i + 1] = @as(f32, @floatFromInt(pos[1]));
    // debugBlock(nr, startPos[2 * i], startPos[2 * i + 1]);
    xy[2 * i] = startPos[2 * i];
    xy[2 * i + 1] = startPos[2 * i + 1];
    sxy[2 * i] = 0;
    sxy[2 * i + 1] = 0;
    freeShips -= 1;

    var ax: f32 = 0;
    var ay: f32 = 0;
    var dummy1: f32 = 0;
    var dummy2: f32 = 0;

    const planet = getAi(startPos[2 * i], startPos[2 * i + 1], &ax, &ay, &dummy1, &dummy2);
    axy[2 * i] = ax;
    axy[2 * i + 1] = ay;

    if (0 <= planet) {
        landed[i] = @intCast(planet);
        freeShips += 1;
        //changed = true;
        //consoleLog(24);
        //consoleLog(nr);
        addResult(startPos[2 * i], startPos[2 * i + 1], @intCast(planet));
    }

    return 1;
}

export fn getVersion() u16 {
    return TheVersion;
}

export fn addPlanet(x: f32, y: f32) i8 {
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
fn getAi(xi: f32, yi: f32, ax: *f32, ay: *f32, dx: *f32, dy: *f32) i8 {
    ax.* = 0;
    ay.* = 0;
    for (0..config.planetCount) |planet| {
        //console.log("position = ", p);
        dx.* = config.planetPositions[2 * planet] - xi;
        dy.* = config.planetPositions[2 * planet + 1] - yi;
        const r2 = dx.* * dx.* + dy.* * dy.*;
        if (r2 <= rad2) {
            return @as(i8, @intCast(planet));
        }
        ax.* += config.speed / (r2) * dx.*;
        ay.* += config.speed / (r2) * dy.*;
    }
    return -1;
}

export fn updatePositions() i8 {
    // dt is taken fixed to 1.0, play with dampening and config.speed (gravity) instead
    const loops = config.loops;
    var dx: f32 = undefined;
    var dy: f32 = undefined;
    var ax: f32 = undefined;
    var ay: f32 = undefined;
    //var changed: bool = false;
    for (0..config.length) |i| {
        if (landed[i] >= 0) {
            continue;
        }
        ship: for (0..loops) |_| {
            const planet = getAi(xy[2 * i], xy[2 * i + 1], &ax, &ay, &dx, &dy);
            if (0 <= planet) {
                landed[i] = @intCast(planet);
                freeShips += 1;
                //changed = true;
                //consoleLog(24);
                //consoleLog(nr);
                addResult(startPos[2 * i], startPos[2 * i + 1], @intCast(planet));
                break :ship;
            }

            xy[2 * i] += sxy[2 * i] + 0.5 * ax;
            xy[2 * i + 1] += sxy[2 * i + 1] + 0.5 * ay;

            sxy[2 * i] += 0.5 * (ax + axy[2 * i]);
            sxy[2 * i + 1] += 0.5 * (ay + axy[2 * i + 1]);
            axy[2 * i] = ax;
            axy[2 * i + 1] = ay;
            //console.log("sx=", sxy[2*i], " sy=", sxy[2*i+1]," ax=", ax," ay=" , ay);
            sxy[2 * i] *= config.dampening;
            sxy[2 * i + 1] *= config.dampening;
        }
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
