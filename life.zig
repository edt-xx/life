const std = @import("std");
const display = @import("zbox");

// Author Ed Tomlinson (2021), released under the GPL V3 license.
//
// This program is an implementation of life as create by John H. Conway.  
//
// change the pattern to one of the included patterns and rebuild, 
//
// zig build-exe -O ReleaseFast --pkg-begin zbox ../zbox/src/box.zig --pkg-end life.zig
//
// generation 299198(2) population 77132(11719) births 3217 deaths 3228 rate 260/s  heap(8) 61286/16841  window(2) -11402,-11587
//
// The title line tells us this is generation 200198 and the (2) that we are displaying every second generation ( see +, - )
// the population is 77132 cells with (11719) cells considered active (a birth or death near the cell in the last generation)
// birth and deaths as per the rules of life  
// generations per second.  If the rate is limited (see s, f) you will see rate> indicating we can run faster.
// we are using a heap size of 2^8 x 2^8 with 61286 entries and we need to check 16841 cells for the next generation.
// window(2) tells us autotracking is enabled ( t ) and it is using 2 generations for tracking info.  
// window(-2) would tell us autotracking is disabled, use cursor keys to move window or t to restart autotracking
// the last two numbers are the window position.
//
// s, f        : limits the generation rate, s halves the rate and f doubles it (when limited you will see rate>xxx/s )
// +, -        : only show every nth generation.  + doubles n, - halves n (generation xxxx(n) ...)
// cursor keys : allow manual positioning of the window using cursor keys (window(-autotracking generations) ...)
// t           : if manual tracking is enabled, disable it, if disabled toggle the number of generations used for autotracking
// esc, q      : will exit the program
//
// The algorythm used here was developed in the late 70s or early 80s.  I first implemented it on an OSI superboard II using 
// Basic and 6502 assembly.  This was before algorythms like hash life were discovered.  I've been using it when I want to learn a 
// new language environment.  This version was started to learn basic zig, then valgrind came into the picture and let me get a  
// better idea of how zig compiles and where the program was spending its time.
//
// This algorythm is nothing special by todays standards, its not super fast, it does not use SIMD or the GPU for speed, nor does it
// make much use of multiple CPUs.  As a learning exercise its been interesting though.
//
// Until jessrud accepts my fixes and enhancement for zbox you will need to clone: https://github.com/edt-xx/zbox.git
// 
// To build use something like: zig build-exe -O ReleaseFast --pkg-begin zbox ../zbox/src/box.zig --pkg-end life.zig

// set the pattern to run below
//const pattern = p_pony_express;
const pattern = p_1_700_000m;
//const pattern = p_max;
//const pattern = p_52513m;

const print = std.debug.print;

fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    display.deinit();
    std.io.getStdOut().writeAll("\x1b[2J") catch {};
    std.io.getStdOut().writeAll("\x1b[H") catch {};
    std.builtin.default_panic(msg, error_return_trace);
}

const Point = struct {
    x: u32,
    y: u32,
    
    fn init(x:u32, y:u32) Point {           // constuct a point
        return Point{.x=x, .y=y};
    }
    
    fn tile(p:Point) Point {                // use a 4x4 tile (testing shows this to be the optimal size) 
        return Point{.x=p.x>>2, .y=p.y>>2};
    }
};

const Cell = struct {
    p: Point,                               // point for this cell
    n: ?*Cell,                              // pointer for the next cell in the same hash chain
    v: u8,                                  // value used to caculate next generation
    
    fn init(p:Point, n:?*Cell, v:u8) Cell {
        return Cell{.p=Point{.x=p.x, .y=p.y}, .n=n, .v=v};
    }
};

const Hash = struct {
    hash:[]?*Cell,              // pointers into the cells arraylist (2^order x 2^order hash table)
    static: []bool,             // flag if 4x4 area is static
    index:fn (u32, u32) u32,    // hash function to use, population dependent
    order:u32,                  // hash size is 2^(order+order)
       
    fn init(size:usize) !Hash {
                    
        var self:Hash = undefined;
        
// log2 of the population from the last iteration.  The ammount of memory used is a tradeoff
// between the length of the hash/heap chains and the time taken to clear the hash array.
        
        switch (std.math.log2(size)) {                  // allows number of cells to reach the hash size before uping the order
         0...11 => self = Hash { .hash=undefined, 
                                 .static=undefined,
                                 .index = i_64,
                                 .order = 6 },
        12...13 => self = Hash { .hash=undefined, 
                                 .static=undefined,
                                 .index = i_128,
                                 .order = 7 },
        14...15 => self = Hash { .hash=undefined,
                                 .static=undefined,
                                 .index = i_256, 
                                 .order = 8 },
        16...17 => self = Hash { .hash=undefined,
                                 .static=undefined,
                                 .index = i_512,
                                 .order = 9 },
        18...19 => self = Hash { .hash=undefined,
                                 .static=undefined,
                                 .index = i_1024, 
                                 .order = 10, },
        20...21 => self = Hash { .hash=undefined,
                                 .static=undefined,
                                 .index = i_2048,
                                 .order = 11 },
           else => self = Hash { .hash=undefined,
                                 .static=undefined,
                                 .index = i_4096,
                                 .order = 12 },
        }
        
        // mark all tiles as static to start with          
        // for (self.static) |*t| t.* = true;           // from valgrind, only @memset uses the os memset
        // std.mem.set(bool,self.static,true);
        //self.static = try allocator.alloc(bool,shl(usize,1,2*self.order));
        //@memset(@ptrCast([*]u8,self.static),1,std.math.shl(usize,1,2*self.order)*@sizeOf(bool));
        
        return self;
    }
    
    fn assign(self:*Hash,s:Hash) !void {
        if (self.order != s.order) {
            self.order = s.order;
            self.index = s.index;
            allocator.free(self.hash);
            self.hash = try allocator.alloc(?*Cell,std.math.shl(usize,1,2*self.order));
        }
        // for (self.hash) |*c| c.* = null;                // from valgrind, only @memset is using the os memset call
        // std.mem.set(?*Cell,self.hash,null);
        @memset(@ptrCast([*]u8,self.hash),0,@sizeOf(?*Cell)*std.math.shl(usize,1,2*self.order));
        self.static = s.static;
    }
    
    fn takeStatic(self:*Hash,s:*Hash) !void {
        if (self.order != s.order) {
            allocator.free(s.static);
            s.static = try allocator.alloc(bool,std.math.shl(usize,1,2*self.order));
        } 
        self.static = s.static;
        // mark all tiles as static to start with          
        // for (self.static) |*t| t.* = true;           // from valgrind, only @memset uses the os memset
        // std.mem.set(bool,self.static,true);
        @memset(@ptrCast([*]u8,self.static),1,@sizeOf(bool)*std.math.shl(usize,1,2*self.order));
    }
      
    fn deinit(self:Hash) void {
        allocator.free(self.hash);
        allocator.free(self.static);
    }
        
    fn setActive(self:*Hash,p:Point) void { // Collisions ignored here, they just cause more tiles to be flagged active
         var t = Point.tile(p);
         const x = p.x & 0x03;   // 4x4 tiles are optimal                
         const y = p.y & 0x03;
                                 self.static[self.index(t.x, t.y)] = false;
         t.x +%= 1;              if (x==3         ) self.static[self.index(t.x, t.y)] = false;
                     t.y +%= 1;  if (x==3 and y==3) self.static[self.index(t.x, t.y)] = false;
         t.x -%= 1;              if (         y==3) self.static[self.index(t.x, t.y)] = false;
         t.x -%= 1;              if (x==0 and y==3) self.static[self.index(t.x, t.y)] = false;
                     t.y -%= 1;  if (x==0         ) self.static[self.index(t.x, t.y)] = false;
                     t.y -%= 1;  if (x==0 and y==0) self.static[self.index(t.x, t.y)] = false;
         t.x +%= 1;              if (         y==0) self.static[self.index(t.x, t.y)] = false;
         t.x +%= 1;              if (x==3 and y==0) self.static[self.index(t.x, t.y)] = false;
   }              

// use the middle bits of the square of the coord to create the index.  No need
// to add a seed since this is not used for q sequence (see: Middle Square Weyl)
// valgrind shows the low 32bits of the 64bit product is saved.  So we use the
// high bits from the 32bits to generate the index.  
 
// passing x, y instead of a point lets the compiler generate beter code (~25% faster) and speed counts here
 
    fn i_64(x:u32, y:u32) u32 { 
        return (( x*%x >> 26) | 
                ( y*%y >> 26 << 6));     // compiler 0.71 generates faster code using left shift vs a bit mask.
    } 
 
    fn i_128(x:u32, y:u32) u32 { 
        return (( x*%x >> 25) | 
                ( y*%y >> 25 << 7));     
    }
    
    fn i_256(x:u32, y:u32) u32 { 
        return (( x*%x >> 24) | 
                ( y*%y >> 24 << 8)); 
    }
    
    fn i_512(x:u32, y:u32) u32 {  
         return (( x*%x >> 23) | 
                 ( y*%y >> 23 << 9)); 
    }

    fn i_1024(x:u32, y:u32) u32 { 
        return (( x*%x >> 22) |
                ( y*%y >> 22 << 10));
    }

    fn i_2048(x:u32, y:u32) u32 { 
        return (( x*%x >> 21) |
                ( y*%y >> 21 << 11));
    }
    
    fn i_4096(x:u32, y:u32) u32 {  
        return (( x*%x >> 20) |
                ( y*%y >> 20 << 12));
    }

    // find a Cell in the heap and increment its value, if not known, link it in and set its initial value
    
    fn addCell(self:*Hash, p:Point) void { 
        
        const x = p.x;
        const y = p.y;

        const h = self.index(x,y);  // zig does not have 2D dynamic arrays so we fake it...
        
        var i = self.hash[h];       // ***1 Points to the current Cell or null
        
        while (i) |c| {
            if (x == c.p.x and y == c.p.y) {
                 c.v += 10;                                         // ***2
                 if (c.v < 13) check.appendAssumeCapacity(c);       // ***3 if not added a potential birth, add it now
                 return;
            }
            i = c.n;          // advance to the next cell
        }
        var c = cells.addOneAssumeCapacity();
        c.* = Cell.init(Point{.x=x, .y=y}, self.hash[h], 10);  // ***4 cell not in heap so add it and        
        self.hash[h] = c;                                      // ***1 link it into the head of the list
        check.appendAssumeCapacity(c);                         // ***3 add to check list
        return;
    }
    
    fn addNear(self:*Hash, p:Point) void { 
        
        const x = p.x;
        const y = p.y;
        
        if (self.static[self.index(x>>2, y>>2)])
            return;

        const h = self.index(x,y);  // zig does not have 2D dynamic arrays so we fake it...
        
        var i = self.hash[h];       // Points to the current Cell or null
        while (i) |c| {
            if (x == c.p.x and y == c.p.y) {
                 c.v += 1;                                          // ***
                 if (c.v == 3) check.appendAssumeCapacity(c);       // potential birth
                 return;
            }
            i = c.n;          // advance to the next cell
        }
        var c = cells.addOneAssumeCapacity();
        c.* = Cell.init(Point{.x=x, .y=y}, self.hash[h], 1);    // cell not in heap so add it and        
        self.hash[h] = c;                                       // link it into the head of the list ***
        return;
    }
    
};

fn sum(v:[16]i64, t:isize) i64 {                        // tool used by autotracking 
  var i:u32 = 0; var s:i64 = 0;
  while (i < t) : (i += 1) s += v[i];
  return s;
}

const origin:u32 = 1_000_000_000;                       // about 1/4 of max int which is (near) optimal when both index & tile hashes are considered

var gpa = (std.heap.GeneralPurposeAllocator(.{}){});
const allocator = &gpa.allocator;
// const allocator = std.heap.page_allocator;

var alive = std.ArrayList(Point).init(allocator);       // alive cells, static cell stay in this list       
var check = std.ArrayList(*Cell).init(allocator);       // cells that may change during the next iteration
var cells = std.ArrayList(Cell).init(allocator);        // could be part of Hash structure, deallocation is easier this way

var grid:Hash = undefined;                              // the current hash containing cells and the static tiles mask array
var newgrid:Hash = undefined;                           // what will be come the next grid hash

// const some_strings = [_][]const u8{"some string", "some other string"};

//  std.sort.sort(Point, alive.items, {}, Point_lt);

//  fn Point_lt(_ctx: void, a: Point, b: Point) bool {
//      return switch (std.math.order(a.y, b.y)) {
//          .lt => true,
//          .eq => a.x < b.x,
//          .gt => false,
//      };
//  }

pub fn main() !void {
    
    defer alive.deinit();               // make sure to cleanup the arrayList(s)
    defer check.deinit();
    defer cells.deinit();
    defer grid.deinit();                // this also cleans up newgrid's storage
    
    const stdout = std.io.getStdOut().writer();
    
    try display.init(allocator);            // setup zbox display
    defer display.deinit();                 
    try display.setTimeout(0);
 
    try display.handleSignalInput();
 
    try display.cursorHide();               // hide the cursor
    defer display.cursorShow() catch {};
 
    var size = try display.size();
 
    var cols:u32 = @intCast(u32,size.width);
    var rows:u32 = @intCast(u32,size.height);
    
    var screen = try display.Buffer.init(allocator, size.height, size.width);
    defer screen.deinit();
    
    var xl:i64 = origin;
    var xh:i64 = 0;   
    var yl:i64 = origin; 
    var yh:i64 = 0;

// rle pattern decoding
    var X:u32 = origin;
    var Y:u32 = origin;
    var count:u32 = 0;
    for (pattern) |c| {
        switch (c) {
            'b' => {if (count==0) {X+=1;} else {X+=count; count=0;}},
            'o' => {if (count==0) {count=1;} while (count>0):(count-=1) {try alive.append(Point.init(X,Y)); X+=1;}},
      '0'...'9' => {count=count*10+(c-'0');},
            '$' => {X=origin; if (count==0) {Y+=1;} else {Y+=count; count=0;}},
            '!' => {break;},
          else  => {},
        }
        if (X>xh) xh=X;
    }
    yh=Y;
    
// generation, births & deaths
    var gen: u32 = 0;
    var s:u32 = 0;         // update display even 2^s generations
    var b:u32 = 0;
    var d:u32 = 0;
    
// starting center of activity 
    var cbx:i64 = @divTrunc(xh-@intCast(i64,origin),2)+origin; 
    var cby:i64 = @divTrunc(yh-@intCast(i64,origin),2)+origin;

// used to track activity for autotracking
    var t:isize = 1;                                   // number of generations used for autotracking, if negitive autotracking is disabled
    var dx = [16]i64{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var ix = [16]i64{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var dy = [16]i64{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var iy = [16]i64{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var mx:i64 = 1;
    var my:i64 = 1;
    var z:usize = 0;
    var inc:i64 = 20;

// set initial display winow
    xl = cbx - cols/2;
    xh = xl + cols - 1;  
    yl = cby - rows/2; 
    yh = yl + rows - 2;

            
// initial grid. The cells arrayList is sized so it will not grow during a calcuation so pointers are stable                                                                                                    

    grid = try Hash.init(9*alive.items.len+9);      // this initializes grid.static
    grid.hash = try allocator.alloc(?*Cell,1);      // initialize with dummy allocations  
    grid.static = try allocator.alloc(bool,1);  
    
    newgrid = try Hash.init(9*alive.items.len+9);   // create newgrid too
    
    grid.order = 0;     // this forces grid.assign & newgrid.takeStatic to reallocate storage for hash and static.
    
    try newgrid.takeStatic(&grid);
    for (alive.items) |p| { newgrid.setActive(p); }   // set all tiles active for the first generation
    
    try check.ensureCapacity(alive.items.len*3+3);    // prepare for main loop
    try check.resize(alive.items.len+1);
    b = @intCast(u32,alive.items.len+1);              // everything is a birth at the start
        
    var ogen:u32 = 0;                                 // info for rate calculations
    var rtime:i64 = std.time.milliTimestamp()+1_000;  
    var rate:usize = 0;
    var limit:usize = 8192;
    var delay:usize = 0;
    
    var tDisp:?*std.Thread = null;                    // thread for display updating
    
// main event/life loop  

    while (try display.nextEvent()) |e| {
        
        var i:usize = 0;
        
        // process user input
        switch (e) {
            .up     => { cby += 2*inc; if (t>0) t = -t; },      // manually position the display window
            .down   => { cby -= 2*inc; if (t>0) t = -t; },
            .left   => { cbx += 2*inc; if (t>0) t = -t; },
            .right  => { cbx -= 2*inc; if (t>0) t = -t; },
            .escape => { if (tDisp) |tD| tD.wait(); return; },  // quit
             .other => |data| {   const eql = std.mem.eql;
                                  if (eql(u8,"t",data)) {
                                      if (t>0) { 
                                          t = @rem(t,6)+1;   // 2, 3 & 4 are the most interesting for tracking
                                      } else 
                                          t = -t; 
                                      if (z >= t) 
                                          z = 0; 
                                  } 
                                  if (eql(u8,"s",data)) limit = if (limit>1) limit/2 else limit;        // limit generation rate
                                  if (eql(u8,"f",data)) limit = if (limit<16384) limit*2 else limit;
                                  if (eql(u8,"+",data)) s += 1;                                         // update every 2^s generation
                                  if (eql(u8,"-",data)) s = if (s>0) s-1 else s;
                                  if (eql(u8,"q",data)) { if (tDisp) |tD| tD.wait(); return; }          // quit
                             },
              else => {},
        }
        
        // switch focus of center of activity as per user
        if (t<0) {
            xl = cbx - cols/2;                       
            xh = xl + cols - 1;
            yl = cby - rows/2;
            yh = yl + rows - 2;
        }
        
        try grid.assign(newgrid);                       // assign newgrid to grid (if order changes reallocate hash storage)
        
        try cells.ensureCapacity(check.items.len*9);    // 9 will always work, we might be able to get away with a lower multiplier
        try cells.resize(0);                            // arrayList length to 0 without releasing any storage
        
        try check.ensureCapacity(std.math.max((b+d)*9,5*check.items.len/4));    // resize the list of cells that might change state
        try check.resize(0);
        
        if (tDisp) |tD| tD.wait();          // optionly wait for thread to finish before (possibily) changing anything to do with the display
 
        // update the size of screen buffer
        size = try display.size();
        if (size.width != cols or size.height != rows) {
            try screen.resize(size.height, size.width);
            cols = @intCast(u32,size.width);
            rows = @intCast(u32,size.height);
            xl = cbx - cols/2; 
            xh = xl + cols - 1;
            yl = cby - rows/2;              
            yh = yl + rows - 2;
        }
        screen.clear();                                 // clear the internal screen display buffer
        
// populate hash & heap from alive list

        var pop = alive.items.len+1;                    // remember the population
        
        while (i < alive.items.len) {                   // add cells to the hash to enable next generation calculation
            
            var p = alive.items[i];                     // extract the point                                    
            
            if (grid.static[grid.index(p.x>>2, p.y>>2)])
                i +=1                                       // keep static cells in alive list - they are stable
            else {
                grid.addCell(p);                            // add to heap 
                _ = alive.swapRemove(i);                    // remove active cells from alive list
            }                                         

            // add effect of the cell on the surrounding area if point is not on/in a static tile
            
            p.x +%= 1;              grid.addNear(p);  
                        p.y +%= 1;  grid.addNear(p);
            p.x -%= 1;              grid.addNear(p);
            p.x -%= 1;              grid.addNear(p);
                        p.y -%= 1;  grid.addNear(p);
                        p.y -%= 1;  grid.addNear(p);
            p.x +%= 1;              grid.addNear(p);
            p.x +%= 1;              grid.addNear(p);
            
            // if cell is within the display window update the screen buffer
            
            if (p.x >= xl and p.x <= xh and p.y >= yl and p.y <= yh) {
                screen.cellRef(@intCast(usize,p.y-yl+1),@intCast(usize,p.x-xl)).char = 'O';
            }
        }
        
// adjust delay to limit rate as user requests.  Results are approximate 

        if (std.time.milliTimestamp() >= rtime) { 
            rtime = std.time.milliTimestamp()+1_000;
            rate = gen-ogen;
            ogen = gen;
            const a = rate*1_000_000_000/(if (500_000_000>delay*rate) 1_000_000_000-delay*rate else 1);  // rate without delay (if any)
            if (a>limit)
                delay = 1_000_000_000/limit-1_000_000_000/a
            else
                delay = 0;
        }
        
// show the results for this generation (y,x coords)

        var tt = if (delay>0) ">" else " ";    // needed due to 0.71 compiler buglet with if in print argscd
        
        _ = try screen.cursorAt(0,0).writer().print("generation {}({}) population {}({}) births {} deaths {} rate{s}{}/s  heap({}) {}/{}  window({}) {},{}",.{gen, std.math.shl(u32,1,s), pop, pop-alive.items.len+1, b, d, tt, rate, grid.order, cells.items.len+1, check.items.len+1, t, xl-origin, yl-origin});
         
        // doing the screen update, display.push(screen); in another thread alows overlap and yields faster rates.
        tDisp = if (gen%std.math.shl(u32,1,s)==0) try std.Thread.spawn(display.push, screen) else null;     // update display every 2^s generations
        
        if (gen == 0)
            std.time.sleep(2_000_000_000);      // briefly show the starting pattern
        if (delay>0)
            std.time.sleep(delay);              // we calcuate delay to limit the rate

        gen += 1;

// track births and deaths and info so we can center the display on active Cells
        
        b = 0;
        d = 0;
                       
        newgrid = try Hash.init(cells.items.len+1);     // newgrid hash fn based on size
        try newgrid.takeStatic(&grid);                  // if order save, reuse static array from grid otherwise reallocate it
        
        try alive.ensureCapacity(alive.items.len+check.items.len+2);   // alive now just contains living points on/in static areas
        
        for (check.items) |c| {                     // we could scan all cells but check is much smaller (25-35% of cells)
            const v = c.v;
            if (v == 12 or v == 13) {               // if active cell survives
                alive.appendAssumeCapacity(c.p);
                continue;
            }
            if (v == 3) {                           // birth so add to alive list & flag tile(s) as active
                alive.appendAssumeCapacity(c.p);        
                newgrid.setActive(c.p);
                if (c.p.x > cbx) ix[z] += 1 else dx[z] += 1;           // info for auto tracking of activity (births)
                if (c.p.y > cby) iy[z] += 1 else dy[z] += 1;
                b += 1;
                continue;
            } 
            if (v > 9 ) {                          // cell dies mark tile(s) as active
                    newgrid.setActive(c.p);
                    if (c.p.x > cbx) ix[z] -= 1 else dx[z] -= 1;       // info for auto tracking of activity (deaths)
                    if (c.p.y > cby) iy[z] -= 1 else dy[z] -= 1;
                    d += 1;
            }
        }
                                       
        // higher rates yield smaller increments 
        inc = std.math.max(16-std.math.log2(@intCast(i64,rate+1)),1);
        
        // if there are enough |births-deaths| left or right of cbx adjust to eventually move the display window.
        if (t>0) {
           if (std.math.absCast(sum(ix,t)) > std.math.absCast(sum(dx,t))) cbx += inc else cbx -= inc;
        }
            
        // if there are enough |births-deaths| above or below of cby adjust to eventually move the display window
        if (t>0) {
            if (std.math.absCast(sum(iy,t)) > std.math.absCast(sum(dy,t))) cby += inc else cby -= inc;
        }
        
        // keep a history so short cycle patterns with non symetric birth & deaths will be ignored for tracking
        if (t!=0) 
            z = (z+1)%std.math.absCast(t);
        
        // clear counters for tracking info in the next generation
        dx[z] = 0;
        ix[z] = 0;
        dy[z] = 0;
        iy[z] = 0;
            
        // switch focus of "center of activity" is moving off display window
        if (t>0 and z==0) {
            if (std.math.absCast(xl - cbx + cols/2) > 4*cols/5) {
                xl = cbx - cols/2;                       
                xh = xl + cols - 1;
            }
            if (std.math.absCast(yl - cby + rows/2) > 4*rows/5) {
                yl = cby - rows/2;
                yh = yl + rows - 2;
            }
        }
        
    }
    
}

// add rle encoded patterns 

const p_chaotic1 =
\\9bobo$8bo$9bo2bo$11b3o8$2bo$2ob2o$2ob2o$2o$2b2obo$3bo2bo$3bo2bo$4b2o!
;

const p_chaotic2 =
\\23bo$21b2ob2o$21b2ob2o$21b2o$23b2obo$24bo2bo$24bo2bo$25b2o11$bobo$o$bo2bo$3b3o!
;                       

const p_1_700_000m =
\\7bobo$6bo$7bo2bo$9b3o7$3o2$bo$b2o25b2o$2b2o24bo$o2b2o!
;

const p_95_206_595m =
\\bbbbbbbobooboobo$
\\bbbboboobbobbobb$
\\bbobbboobboobboo$
\\booobbbooooooobb$
\\oobobbooobobbboo$
\\bobobbobobooobbb$
\\obobbobboobbobob$
\\boobbobbobbooobo$
\\bbbobboboooobobb$
\\ooboobbbobobbbob$
\\obbbobobboobbbbo$
\\bbobbbobbooooobb$
\\oobooooobboooooo$
\\booooobbooobobob$
\\boooobooobboooob$
\\oboobbobooboobbb!
;

const p_52513m =
\\4b2o$5bo$2bobo$2bo10$4bobo$5bo$5bo5$b2o$b2o5$4b2o$4bobo$o6bo$bo2bo2bo
\\$2bo4bo$o5bo$bo3bo$2b3o!
;

const p_pony_express =
\\5o4bob2ob2o$2bob3o3bobobo$2b3obo5bob2o$bobobobob2obob2o$bo3b6ob2obo$o
\\5b2ob2o2b2o$2bo2bobobob2o$ob2obobob2o2bo$o4b3o$b2ob3o2bo2bo$2obo2bob2o
\\2b3o$bobob2obo2bo2b2o$b2o9b2o$ob3o4bobo2b2o$b3o2b2o2b2o3bo$obob3o3bobo!
;

const p_c5_puffer_p1450 =
\\3o$3bo$2o2bo$2obob2o$2o2bo2bo$bobo3bo$2bob2obo$4bobo$3b4o$3b5o$3bo3b2o
\\20b3o$6bo2bo22bo$7bo2bo18b2o2bo$11bo17b2obob2o$9bob2o2b3o11b2o2bo2bo$
\\10bob3o3bo11bobo3bo$12b2obo2bo12bob2obo$12b4obobo13bobo$11b3o2bobobo
\\11b4o16bo$15bo5bo10b5o15b2o$16b4obo10bo3b2o16bo$17b3obo13bo2bo12b2ob3o
\\$36bo2bo10bo3bob2o$40bo13b3obo$38bob2o2b3o4b2obobob2o$39bob3o3bo5bob2o
\\bo$41b2obo2bo10bo$41b4obobo$40b3o2bobobo3bo5bo$44bo5bo3bo4bo$45b4obo6b
\\o2bo$46b3obo10bo$62b2o3bo$65b4o$61bo7bo$66b5o$66bobobo$62bo4b5o$63bo2b
\\o5bo$67bo2bob2o$67bo2bo$69bo6$62bo$62b2o$64bo$61b2ob3o$60bo3bob2o$64b
\\3obo$61b2obobob2o$63bob2obo$68bo2$63bo5bo$64bo4bo$67bo2bo$71bo$72b2o3b
\\o$75b4o$71bo7bo$76b5o$76bobobo$72bo4b5o$73bo2bo5bo$77bo2bob2o$77bo2bo$
\\29b2o48bo$28bobo$30bo!
;

const p_noahs_ark =
\\9bobo$10b2o$10bo6bo$16bo$16b3o$20b2o$20bobo$20bo2$o$b2o$2o5$3b2o$2bobo
\\$4bo2$5b3o$5bo$6bo!
;

const p_hacksaw =
\\17b2o180b$18bo180b$91bo107b$91bobo105b$94b2o6b2o95b$52b2o24bo15b2o3bo
\\4bo94b$53bo23b2o15b2o3b2o4bo93b$34b2o17bobo5b2o13b2o13bobo11bo9bo83b$
\\33bobo18b2o5b3o11b3o13bo13bo8b2o83b$23b2o7b3o12bo15b2obo9b2o26bo94b$
\\23bo7b3o13b4o12bo2bo10b2o23b2o95b$16b3o13b3o4bobo6b4o11b2obo11bo120b$
\\15bo3bo13bobo3b2o7bo2bo9b3o135b$14bo5bo13b2o4bo7b4o9b2o136b$15bo3bo27b
\\4o4b2o17b2o123b$16b3o28bo7bobo16bo124b$16b3o38bo141b$57b2o140b$40b2o9b
\\2o64b2o80b$39bo2bo7bo2bo63bo81b$39b3o9b3o61bobo81b$14b3o25b9o64b2o82b$
\\13b2ob2o23bo2b5o2bo147b$13b2ob2o23b2o2b3o2b2o134bo12b$13b5o169bo11b$
\\12b2o3b2o163bo4bo11b$46bo136b5o11b$47bo151b$43bo3bo12bo138b$44b4o13bo
\\137b$56bo4bo123b2o12b$57b5o120b3ob2o11b$177b3o3b4o12b$184b2o13b$15bo
\\183b$15b2o182b$67b2o115bo14b$66bobo116bo13b$9bobo40bo12b3o8b2o101bo5bo
\\13b$7bo3bo40b4o8b3o10bo102b6o13b$2o5bo10b2o3b2o28b4o8b3o24bo106b$o5bo
\\10bobo3bo2bo15bo10bo2bo9bobo18b3ob2o3bo102b$7bo11bo7bo7bo6b2o9b4o10b2o
\\18b4o4b2o102b$7bo3bo15bo6b2o16b4o35b2o106b$9bobo15bo24bo146b$23bo2bo
\\38b2o16b2o114b$23b2o40bo16bobo114b$81b3o115b$81b2o79bo36b$84b2o77bo35b
\\$83b3o71bo5bo35b$158b6o35b2$84bo114b$83b2o114b2$57bo126b2o13b$56b2o
\\122b4ob2o12b$45b2o8b2o11bo26bo84b6o13b$45bo8b3o9bobo26b2o84b4o12bob$
\\55b2o8bobo12bo54b5o58bo$56b2o2b2o2bo2bo11b2o14bo38bo4bo54bo3bo$57bo2bo
\\4bobo26bobo42bo55b4o$66bobo25bo2bo40bo20b4o27b3o6b$68bo26bo2bo59bo3bo
\\25b2ob2o6b$162bo21b3o3b3o6b$95bo65bo33b4o$95b2o97bo3bo$172b2o24bo$171b
\\4o22bob$171b2ob2o23b$66b2o105b2o6b6o12b$65b3o27bo73bo10bo5bo12b$55b2o
\\5bob2o12bo15b2o71bobo16bo12b$55bo6bo2bo12b2o29b2o58bo15bo13b$62bob2o
\\13b2o27bo64b2o24b$65b3o11b3o11bo13bo9b2o52b2ob2o23b$66b2o11b2o10bobo
\\13bo10bo17b2o33b4o24b$78b2o9b2o16bo27bo2bo33b2o25b$78bo10b2o17bo29bo
\\60b$89b2o18b2o27bo22b6o32b$91bobo41b2obo21bo5bo32b$93bo42bo29bo32b$
\\149b2obo2bo9bo33b$148b2o6bo42b$137bo12bobo3bo42b$136b2o15b4o42b4$168bo
\\30b$137bo29b2o30b$137b2o12bo14b2o8b2o21b$125bo23bobo13b3o9bo21b$125bob
\\o20bobo15b2o31b$114b2o12b2o9b2o6bo2bo16b2o30b$114bo13b2o9bo8bobo17bo
\\30b$128b2o6b2o6b2o3bobo47b$125bobo7b3o7bo5bo47b$125bo10b2o61b$139bo59b
\\$139b2o!
;

const p_cord_puller =
\\28b3o67b$27bo3bo66b$26bo4bo8b2o3b3o50b$26bo2bobo7b4o55b$26b2obobo6bo3b
\\2o54b$28b2obo2bo4b2obobo53b$18b3o9b2o2bo63b$17bo2bo10b3o13bo6b2o42b$
\\16bo4bo22bo2bo6bo43b$16bo2b3o23b3o50b$16bo5bo75b$17b7o74b$23bo74b$23bo
\\74b$21b2o75b$62b2o34b$62bo35b2$24b3obo69b$24b3obo69b$25bo8b2o62b$26bo
\\3b3ob2o62b$27bo6bo63b$28bobobobo35b2o26b$29bo40bo9bo17b$61bo16b3o17b$
\\2b3o55bobo14bo20b$bo3bo53b2ob2o13b2o19b$o4bo53b2ob2o34b$o2bobo52b3o37b
\\$2obobo52b3o3bo33b$2b2obo2bo50b2o37b$4b2o2bo50bobo36b$5b3o64b2o3b2o19b
\\$72bobobobo19b$73b5o20b$74b3o21b$75bo22b3$47b2o49b$45b6o47b$44b6o48b$
\\43bo6bo26b2o19b$44b3o30bo20b$8b2o35b2o31b3o17b$8bo39bo8bo22bo17b$53b2o
\\2b2ob3o35b$53bo5b4o35b$57b2o39b2$35bo15bo29bo2bo13b$34bobo12b3o28bo3b
\\2o2b2o8b$16b2o15b2ob2o10bo31bo7bo9b$16bo16b2ob2o10b2o19bo11b4o8b2o3b$
\\32b3o32b3o23bo4b$32b3o3bo27bo12bo18b$33b2o31b2o3bo6b2o18b$33bobo35b3o
\\4bobo17b$74bo23b$73b2o23b$24b2o17b2o3b2o48b$24bo27b3o43b$43bo5bo4bo6b
\\2o3b2o30b$53bo8b5o31b$44b2ob2o14b3o32b$46bo17bo8b2o3b2o12b5ob$58b3o12b
\\o5bo11bob3obo$58bo33bo3bob$48bo10bo14bo3bo14b3o2b$47bobo25b3o16bo3b$
\\46bo3bo41b2o4b$46b5o40bobo4b$45b2o3b2o39bobo4b$46b5o41bo5b$47b3o11b3o
\\34b$48bo49b$61bobo14bo10b2obob2o2b$60b5o11b2ob2o8bo5bo2b$59b2o3b2o24bo
\\3bo3b$59b2o3b2o9bo5bo9b3o4b2$75b2o3b2o16b3$48b2o48b$48bo49b2$61b2o28b
\\2o5b$61bo29bo6b2$78b2o18b$78bo!
;

const p_acorn =
\\bo5b$3bo3b$2o2b3o!
;

const p_2_engine_cordership = 
\\19b2o$19b4o$19bob2o2$20bo$19b2o$19b3o$21bo$33b2o$33b2o7$36bo$35b2o$34b
\\o3bo$35b2o2bo$40bo$37bobo$38bo$38bo$38b2o$38b2o3$13bo10bo$12b5o5bob2o
\\11bo$11bo10bo3bo9bo$12b2o8b3obo9b2o$13b2o9b2o12bo$2o13bo21b3o$2o35b3o
\\7$8b2o$8b2o11b2o$19b2o2bo$24bo3bo$18bo5bo3bo$19bo2b2o3bobo$20b3o5bo$
\\28bo!
;

const p_glider_making_switch_engine =
\\bobo24b$o27b$bo2bo23b$3b3o22b$26b2o$26b2o!
;

const p_slow_puffer_1 =
\\76b2o4b$75b2ob4o$76b6o$77b4ob$64b3o15b$63b5o14b$62b2ob3o14b$52b2o9b2o
\\17b$51b2ob4o24b$52b6o24b$53b4o25b3$44b2o36b$43b2ob2o26b2o6b$44b4o24bo
\\4bo4b$45b2o24bo10b$24b6o41bo5bo4b$24bo5bo40b6o5b$24bo57b$25bo4bo51b$
\\27b2o53b2$54b4o24b$53b6o23b$52b2ob4o23b$3bo49b2o27b$bo3bo76b$o81b$o4bo
\\76b$5o77b3$20bo61b$b2o10b2obo2bobo60b$2ob3o6bobob4obo60b$b4o3b3obo69b$
\\2b2o8bobob4obo60b$13b2obo2bobo60b$5b2o13bo61b$3bo4bo73b$2bo79b$2bo5bo
\\73b$2b6o74b3$53b2o27b$52b2ob4o23b$53b6o23b$54b4o24b2$27b2o53b$25bo4bo
\\51b$24bo57b$24bo5bo40b6o5b$24b6o41bo5bo4b$45b2o24bo10b$44b4o24bo4bo4b$
\\43b2ob2o26b2o6b$44b2o36b3$53b4o25b$52b6o24b$51b2ob4o24b$52b2o9b2o17b$
\\62b2ob3o14b$63b5o14b$64b3o15b$77b4ob$76b6o$75b2ob4o$76b2o!
;

const p_rake_sp2 =
\\o$4bo9b2o$2bo3bo6b2ob3o83b2o15b2o$bo12b5o55b5o22b4o13b2ob4o$bo4bo8b3o56bo4b
\\o20b2ob2o14b6o$b5o68bo26b2o17b4o$75bo3bo$77bo$21bo$2b2o10b2obo2bobo98b2o$b
\\2ob3o6bobob4obo97bo2bo$2b4o3b3obo106bobo$3b2o8bobob4obo97b2o$14b2obo2bobo
\\97bo$6b2o13bo96bobo$4bo4bo107b2ob2o$3bo76b4o34bobo$3bo5bo69b6o34bo$3b6o6b3o
\\60b2ob4o$14b5o60b2o$13b2ob3o$14b2o3$88b2o$87b2ob4o$88b6o$89b4o4$103b2o$102b
\\2ob4o$103b6o$104b4o41$180bo$179bo$179b3o!
;

const p_52444M =
\\11bo$10bob2o$9b2o11$11bobo$12bo$12bo10$15bo$13b2o$8b2o4bo$9b2o$10bo6bo
\\$17b2o4$bo$b2o$obo!
;

const p_birthday_puffer =
\\101bo2$81b2o$80bobo$56b3o22bo$2o$2o8bo$4bo4bobo11bo41b2o$4bo4bobo10bob
\\o24bo15b2o$4bo5bo11b2o24bobo$48bo2bo$6b3o40b2o33b2o$68bo15b2o$68bo$68b
\\o57b3o4$26bo78b2o18b2o$26bo71b2o5b2o18b2o$26bo71b2o32b2o$132b2o3$107b
\\2o$107b2o$124b2o$30b3o90bo2bo$41b2o80bo2bo30bo$41b2o81b2o31bo$157bo2$
\\190bo$189bobo$48b2o37bo101bobo$48b2o36bobo101bo$33bo32bo19bobo$32bobo
\\30bobo19bo$32b2o32b2o$b2o156bo$obo155bobo29b2o$2o157b2o29b2o$112b2o6b
\\2o3b2o$36b2o73bo2bo5b2o3b2o50b2o$36bobo73b2o63bobo$19b2o16b2o139bo$19b
\\2o130b2o$130b2o19b2o$84bo45b2o$11b2o70bobo49b2o$11b2o70bobo29b2o7b2o9b
\\2o$78b3o3bo30bobo5bo2bo$43b2o71b2o6b2o$42bo2bo22b2o21b3o$43b2o22bo2bo$
\\68bobo$69bo$95bo$61b3o31bo43b2o$39b2o54bo43b2o14b2o$39b2o40bo73b2o$80b
\\obo84bo$48bo31b2o84bobo$47bobo17b3o97bo$48b2o2$65bo110b3o$65bo34bo39bo
\\$53b2o10bo33b3o18b3o16bobo$53b2o43b5o36b2o$97b3ob2o$33b2o52bo9b2ob2o
\\46b2o$32bobo51bobo10bo13bo31b2o3bo$32b2o23bo28b2o24bobo29b4obo$56b3o
\\53bo2bo33b2o$55b2ob2o53b2o28bob3o5b2o$55bo3b2o6b2o74b5obo4bo$57bob2o6b
\\2o82bo17b2o$53bo3bobo91bo16b2o20b3o$53bo3b2o66bo43bobobo$54b2o68bobo
\\19bo7bo15b2ob2o$43b2o55b2o23bo18b2o8bo15b2obo$43b2o14bo40b2o43b2o8bo
\\16bo16b2o$57b2ob2o127b2o$80b2o8bo90b2o13b2o$56bobo21b2o8bo12b2o38bo37b
\\2o13b2o$56bo3bo29bo8b2o2b2o37bobo$56b2o2bo38b2o41bobo$57b3o83bo25bo$
\\58bo16bobo74bo15bobo$76b2o74bo15bo$76bo75bo16bo3bo$221bo$171bobo47bo$
\\172bo17b3o28bo2$254bo$84bo49b2o117bobo$83bobo48bobo11bo30b2o66bo5bobo$
\\83bo2bo48b2o10bobo28bobo65bobo5bo$81bo3bo61bobo30b2o64bobo$80bo67bo24b
\\o7bo65bo$81bobo68bo17b2obo7b2o$88b2o16bo29bo14bobo23b2o2bobo39bo18b2o$
\\76b2o10b2o15bobo27bobo13b2o16bo2bo3bobo5bo37bobo16bo2bo9b2o$76b2o27b2o
\\28b2o39b3obo42b2o17b2o10b2o$173bobo4bo4bo3b2o$87bo83bo4bo2b3obobo3b2o
\\59bo$86bo85bo5b2o70bo$85b3o85bo2b3o71bo$85bo92bo36b2o$90b2o42b2o40bo
\\17b2o19b2o$89b2obo32bo8b2o39b3o16b2o48b2o$90bobo31bobo72b2o43b2o$91bo
\\32b2o62b2o9b2o$180b2o5bo2bo$82bo97b2o6b2o$82b2o61bo8b2o$82b3o60bo8b2o$
\\85b2o58bo84bo$84b3o19b2o121bobo$69b2o4bo11bo17bo2bo120bo2bo$69b2o4b2o
\\3bo3b4o18b2o38b2o82b2o$77b6o3b2o12bo16bo28b2o$75b2ob2o3b2obo13bo15bobo
\\$75bo4bo17b3o15bobo109b2o$80bo2bo12bo20bo109bo2bo$92bo2b3o65b2o63bobo$
\\65bo27bo11bo57b2o64bo$64bobo14b2o3b2o3bo5bo6bobo$64bobo13bobo3bobo3b3o
\\2bo6bobo102b2o$65bo14bo7bo6b2o8bo102bobo$80bo3bo3bo28bo66b3o22bo$81bo
\\5bo12b2o6bo7bobo$82bo3bo12bo2bo4bobo6bobo19bo59bo$83b3o14b2o4bo2bo2b2o
\\3bo14bo4bobo53b2o2bobo$107b2o3b2o18bo4bobo53b2o2bobo$132bo5bo6b2o51bo
\\5bo$145b2o56bobo$96b2o27b2o7b3o66bobo5b2o$95bobo7b3o16bobo51b3o19b2o2b
\\2o4bo2bo21bo$94bobo16bo9bobo74b2ob3o5b2o13b4o3b3o$73b3o19bo17bo10bo66b
\\3o4b2o4b2o18bo3b3o3bo19b3o$113bo83b2o5b2o9b3o6bo5b2o$86b2o101bo5bob3o
\\14bo3bo5b2obo$86b2o21b3o77bo5bo27bo$189bo5bo9b2o7b2ob2o5bo28b2o$205b2o
\\4b2o3bo7bo5b3o20b2o$179bo11b3o17b2o16b6o25b2o$178bobo47bo2b2obo25b2o$
\\178b2o48bo2bobo$226bob2obob3o$226b3o$200bo36bo$199bobo31bo$158b3o39b2o
\\30bo5bo$227bo5bo$227b3o3bobo28b2o$227bo2bo6b2o15b3o7b2o$227bo2b2o2bo$
\\227b4o4b3o8bo$185b2o41b2o7bo8bo$185b2o37b2o20bo$224b2o$199bo$160b2o36b
\\obo$160b2o8bo28b2o29bo$132b2o30bo4bobo11bo46bo$132b2o11bo18bo4bobo10bo
\\bo11bo33bo$144bobo17bo5bo11b2o11bobo$128b2o15b2o49b2o42b2o6b2o3b2o$
\\127bo2bo35b3o70bo2bo5b2o3b2o$128b2o110b2o39bo$199b2o18bo60bobo$199b2o
\\18bo61b2o$132b2o85bo38b2o$131bo2bo54bo22bo45b2o$132b2o54bobo20bobo49b
\\2o$188b2o21bobo29b2o7b2o9b2o$206b3o3bo30bobo5bo2bo$220bo23b2o6b2o38b2o
\\$219bobo56b2o12b2o$220b2o56b2o5$277b3o$225b2ob2o14bo32b4o19b2o$197b3o
\\25bo3bo13b3o6b2o25b3o18b2o$226b3o14b3o6b2o25bobo$226b3o10b2o6bo23bo4b
\\2obobo$237bo2bo5bobo26bo3b2o$236bobobo4bo$223bo11b3obo6bobo$222bobo10b
\\2o35bo4bo$222b2o13bo2bo32b3o3b3o$192b2o45b2o61b3o$192b2o8bo36bo16bobo
\\20bobo20bobo$161b2o33bo4bobo11bo29bo9bo2bo21bo21b3o$160bobo33bo4bobo
\\10bobo27bobo8bo2b2o$160b2o34bo5bo11b2o31bo7b5o20b2o16b2o$238b2o3b2obo
\\9b3o3b2o15bo2bo$198b3o36bobo7bo9bo21bo2bo15bo$238bo7b2obob2o26bo3bo12b
\\obo$179b2o66bo3b2o27bobo14bobo$179b2o64b2o6bo27bo15bobo13bo$246bob5obo
\\38b2o3bobo11b2o$221bo32bo33b2o3b2o5bo11bobo$171b2o47bobo24b2o7bo31b2o
\\8bobo12bo$171b2o47b2o27b2o4bo42b2o12bobo$249bo4b2o56bobo$248bo3bo$248b
\\3o$248bo45b5o11b5o$259b2o35b3o10bob4o$259b2o47bo$309b2o2$312b3o7$255bo
\\$254bobo$254b2o$224b2o$224b2o8bo$193b2o33bo4bobo11bo24bo$192bobo33bo4b
\\obo10bobo22bobo$192b2o34bo5bo11b2o24b2o2$230b3o2$211b2o$211b2o$283b2o$
\\253bo15b2o12b2o$203b2o47bobo14b2o$203b2o47b2o2$265b2o$265b2o$270b2o2b
\\2o$274b3o3b2obo7b2o$269bo10bo3b2o5b2o$276bobo2bo4b2o$269bo2bob4o6bo$
\\263b2o5b3ob3o$263b2o7$271b2o16bo$271b2o13b5o$286b3ob2o$281b2o4b4o3bo$
\\280b2o7bob3obo$281b3o4b2ob3ob2o$281b3o5b2ob4o$291bo6$225bo$223bobo$
\\224b2o62$289bo$287bobo$288b2o62$353bo$351bobo$352b2o!
;

const p_c5_diagoonal_puffer =
\\82bo2b$81b2o2b$80bo4b$78b3ob2ob$77b2obo3bo$76bob3o4b$75b2obobob2ob$76b
\\ob2obo3b$76bo8b2$53bo21bo5bo3b$52b2o21bo4bo4b$51bo22bo2bo7b$49b3ob2o
\\18bo11b$48b2obo3bo11bo3b2o12b$47bob3o14b4o15b$46b2obobob2o10bo7bo11b$
\\47bob2obo11b5o16b$47bo16bobobo16b$30b2o31b5o4bo12b$30b2o14bo5bo9bo5bo
\\2bo13b$29bo2bo13bo4bo9b2obo2bo17b$26b2obo2bo12bo2bo15bo2bo17b$32bo11bo
\\20bo19b$24b2o3bo2bo5bo3b2o41b$24b2o5bo5b4o44b$25bob5o4bo7bo40b$26bo8b
\\5o45b$35bobobo45b$34b5o4bo41b$23b3o7bo5bo2bo42b$23bo8b2obo2bo46b$21b2o
\\12bo2bo46b$15b2o4bo14bo48b$15b3o3bo63b$13bo4bo66b$13bo3bo67b$17bo67b$
\\12b2obobo67b$10b2o5bo67b$10b2o4b2o67b$12b4o69b2$25b2o58b$24b2o59b$26bo
\\58b3$20b2o63b$20b2o63b$19bo2bo62b$16b2obo2bo62b$22bo62b$14b2o3bo2bo62b
\\$14b2o5bo63b$15bob5o63b$16bo68b3$13b3o69b$13bo71b$11b2o72b$5b2o4bo73b$
\\5b3o3bo73b$3bo4bo76b$3bo3bo77b$7bo77b$2b2obobo77b$2o5bo77b$2o4b2o77b$
\\2b4o!
;

const p_bubblegum =
\\9bo11bo$8b3o9b3o$10bo9bo$6bob2o11b2obo$6bo4b3o3b3o4bo$5bob3ob3o3b3ob3o
\\bo2$4b3ob4obo3bob4ob3o$4b2o7bo3bo7b2o$4b3o2bob2o5b2obo2b3o2$9bo2bo5bo
\\2bo$9bo11bo$7b2o2bobo3bobo2b2o$7bo3b3o3b3o3bo$5b2o4bo2bobo2bo4b2o$3bob
\\2obob2o2bobo2b2obob2obo$2b2obo3bo3bo3bo3bo3bob2o$bobo3b2o13b2o3bobo$b
\\2o8bo7bo8b2o$2bo7b3o5b3o7bo$10b2obo3bob2o$2o2b2o5b3o3b3o5b2o2b2o$obo3b
\\o5b2o3b2o5bo3bobo$4bob2o15b2obo$8bo13bo$bo5b3o11b3o5bo$7b2o13b2o$3bo
\\23bo$5b2o17b2o$5b6o9b6o$6bobo13bobo$2b3o4b2o4bo4b2o4b3o$2b2o4b3o3b3o3b
\\3o4b2o$3b2obo6bo3bo6bob2o$12bobobobo$11bob2ob2obo$11bob5obo$9b2o9b2o$
\\8b2o11b2o$8bo13bo2$6bobo13bobo$9bo11bo$5bo3bo11bo3bo$5bo4bo9bo4bo$5bo
\\4bo9bo4bo$6bo17bo$8b3o9b3o$8bo13bo2$8bo13bo2$10bo9bo$9b3o7b3o$10b2o7b
\\2o$10b2o7b2o$7bo2bo9bo2bo$7bobobo7bobobo$11bo7bo3$8b3o9b3o2$9bo11bo$9b
\\o11bo$9bo11bo2$6bo5bo5bo5bo$5bobo3bobo3bobo3bobo$5b2o5b2o3b2o5b2o!
;  

const p_p720_dirty_puffer =
\\40bo9bo48bo9bo$38b3ob3oboobboo46boobboob3ob3o$34booboobbo4boobboboo4b
\\oo30boo4boobobboo4bobbooboo$34boobbo3boobobbobbobboobboboo26boobobboo
\\bbobbobboboo3bobboo$33bobbo14boo4bobbob3o20b3obobbo4boo14bobbo$55boobb
\\3o4b3o12b3o4b3obboo$59bob3obobobo10bobobob3obo$30bo15bo13b4obobobo10bo
\\bobob4o13bo15bo$29boo15boo10bobbo4bobo12bobo4bobbo10boo15boo$11bo7b4o
\\5bobb5o4boo4boboboo7bo30bo7boobobo4boo4b5obbo5b4o7bo$4boob3ob3o5bobob
\\oobo4bobb3o3booboobboo3bo14bo14bo14bo3boobbooboo3b3obbo4boboobobo5b3ob
\\3oboo$4boo4bobbooboobbo4boo3b5o4bo3boo3bo4bo13bo14bo13bo4bo3boo3bo4b5o
\\3boo4bobbooboobbo4boo$3bobboboo3bobboo6bo3bobboo3bobbobboboobo5bo42bo
\\5boboobobbobbo3boobbo3bo6boobbo3boobobbo$15bo20b4obo7b3oboo13b3o8b3o
\\13boob3o7bob4o20bo$49bobobobo15boobooboo15bobobobo$53bob3obo8boo4boo4b
\\oo8bob3obo$53bo5b3o8boob4oboo8b3o5bo$7boo18boo5bo19bob3obboo7boo6boo7b
\\oobb3obo19bo5boo18boo$4booboboo9boo6boo3boobooboob3obo16bo10boo10bo16b
\\ob3oboobooboo3boo6boo9booboboo$b4obbo4boob3oboobbobooboo3boobboboo4bob
\\oboo7boo3boobo7boo7boboo3boo7boobobo4boobobboo3booboobobboob3oboo4bobb
\\4o$o4bo6boobob3o4bobobb4obo4bo3bo5boo4bobboboob3obo5bobbo5bob3oboobobb
\\o4boo5bo3bo4bob4obbobo4b3oboboo6bo4bo$boo7bobbobo3bobobbobo5bo8bo7boo
\\4b3o6bo3bo5boo5bo3bo6b3o4boo7bo8bo5bobobbobo3bobobbo7boo$17bo11bo3bob
\\oo6booboo7boboboboboo8bobbo8boobobobobo7booboo6boobo3bo11bo$32booboo5b
\\o3boo3boobbo7bobobb3o3boo3b3obbobo7bobboo3boo3bo5booboo$51b4o3boobo3bo
\\bobboboobboobobbobo3boboo3b4o$23boo28boobo5booboo3boboboobobo3booboo5b
\\oboo28boo$11boboo7bob3o38boob5o4b5oboo38b3obo7boobo$7b3obooboboo3boo3b
\\oo17bo19bo4bo3boo3bo4bo19bo17boo3boo3booboboob3o$6bo6boobb5obobbobbo5b
\\ob3ob3ob4o17bo16bo17b4ob3ob3obo5bobbobbob5obboo6bo$7boo3bo3bo3bo6bobbo
\\3boob3o3boobboob3o12b5ob3obb3ob5o12b3oboobboo3b3oboo3bobbo6bo3bo3bo3b
\\oo$19bo10bobbo3bobboo11bo3bo3booboobb3ob6ob3obbooboo3bo3bo11boobbo3bo
\\bbo10bo$31b3obo8b3o3b3o3booboobo8bo6bo8bobooboo3b3o3b3o8bob3o$29boobo
\\11boob4oboo10boo18boo10boob4oboo11boboo$14boobobb3o10boo10bob3o3bobbo
\\14b8o14bobbo3b3obo10boo$11boobooboo4bo29bo19b4o19bo31b3obboboo$11bobbo
\\bo6b3o47b4o50bo4boobooboo$5boo4boo5boobobboobooboo5bo27b3o57b3o6bobobb
\\o$5booboo12bobobo3boboobb4o5bo3b3o8booboobobo3boboobo5b3o27bo5booboob
\\oobboboo5boo4boo$4bo3boo17bobbo4bo3boo3bobobo6boo3boo5bo3boobooboo3bob
\\obooboo8b3o3bo5b4obboobo3bobobo12booboo$8boo25b3o3bobo4bo4b3obobb5o7bo
\\4bo5bo5boo3boo6bobobo3boo3bo4bobbo17boo3bo$23boo10b3obobobo3b3obboo3b
\\oo27b5obbob3o4bo4bobo3b3o25boo$22bobbo6bobb3o9bobbobboboboobboo29boo3b
\\oobb3o3bobobob3o10boo$8boo9boobo3bo5b3o7boobooboobobbo3bo29boobboobobo
\\bbobbo9b3obbo6bobbo$5booboo9boo7b6o5b4o6boboboobb3obbo29bo3bobbobooboo
\\boo7b3o5bo3boboo9boo$bb4obboo4boobboboob6obbobbo3bo5bo4bob3o4bobobo25b
\\obb3obboobobo6b4o5b6o7boo9booboo$bo4bo4booboobbo6bo3bo6boo5bo3b3o3bobb
\\oo30bobobo4b3obo4bo5bo3bobbobb6oboobobboo4boobb4o$bboo7boo3bobo3bo14bo
\\6bo3booboo40boobbo3b3o3bo5boo6bo3bo6bobbooboo4bo4bo$11boo5bo79booboo3b
\\o6bo14bo3bobo3boo7boo$18boboo110bo5boo$89boo38boobo$89booboo$83boo4boo
\\bb4o$83booboo4bo4bo$82bo3boo7boo$86boo!
;

// this eventually crashes us - pop grows very fast.
const p_max =
\\18bo8b$17b3o7b$12b3o4b2o6b$11bo2b3o2bob2o4b$10bo3bobo2bobo5b$10bo4bobo
\\bobob2o2b$12bo4bobo3b2o2b$4o5bobo4bo3bob3o2b$o3b2obob3ob2o9b2ob$o5b2o
\\5bo13b$bo2b2obo2bo2bob2o10b$7bobobobobobo5b4o$bo2b2obo2bo2bo2b2obob2o
\\3bo$o5b2o3bobobo3b2o5bo$o3b2obob2o2bo2bo2bob2o2bob$4o5bobobobobobo7b$
\\10b2obo2bo2bob2o2bob$13bo5b2o5bo$b2o9b2ob3obob2o3bo$2b3obo3bo4bobo5b4o
\\$2b2o3bobo4bo12b$2b2obobobobo4bo10b$5bobo2bobo3bo10b$4b2obo2b3o2bo11b$
\\6b2o4b3o12b$7b3o17b$8bo!
;

const p_explore =
\\80$872bo$846b4o29b2o7b4o$837b2o6b2o2bo14b2o12bo2bo6bo3bo$837b2o5b2o2bo
\\15b2o11b2o2bo10bo$845bo2bo29bo2bo4bob2obo$846b2o31bo6b3o2$846b2o31bo6b
\\3o$845bo2bo29bo2bo4bob2o$844b2o2bo15b2o11b2o2bo8bo$845b2o2bo14b2o12bo
\\2bo6b2o$846b4o29b2o7bo6$899bo$898b2o$851b2o24b2o19bobo$827b2o22b2o24b
\\2o$828b2o$827bo3$787bo$786b2o157b4o$785b3obo9b2o128b2o14bo2b2o$753bo2b
\\o27b2o13b2o128b2o15bo2b2o$756bo7b3o18b2o42bobo114bo2bo9b2o$752bo9bo4bo
\\18bo42b2o46b3o3b3o61b2o8b2ob2o14b2o$752b2o8bo5bo61bo45bo2bo3bo2bo14bo
\\55bo2bo15b2o$758bo8bo18bo93bobo19b2o43b2o8bo2bo$755b2o8b2o18b2o57b2o5b
\\2o27bobo18b2o43bo2bo8b2o$784b2o13b2o42bo2bo3bo2bo26bobo46b2o15bo2b2o$
\\755b2o8b2o18b3obo9b2o43bo2bobo2bo23bo2bo3bo2bo42b2o14bo2b2o8b2o$758bo
\\8bo18b2o59bobo27bo7bo59b4o8bo2bo$752b2o8bo5bo18bo57b3ob3o105bo2bo15b2o
\\$752bo9bo4bo75b3o5b3o103b2ob2o14b2o$756bo7b3o17bo58b2o7b2o105b2o$753bo
\\2bo28bo57b2o7b2o68bo$783b3o58bob2ob2obo68b2o$844b3o3b3o68bobo18bo$804b
\\2o39bo5bo90bobo$805b2o135b2o$804bo$844b2o5b2o24b2o5b2o$844b2o5b2o24b2o
\\5b2o4$796bo134bo$794bobo134b3o$795b2o137bo$793b2o138bobo$793b2o138bo$
\\792bobo7$796bo$794b2o$795b2o$935bobo$936b2o$936bo7$956b2o$955b2o$770bo
\\186bo$770b2o$769bobo7$968bo$732b2o5b2o226b2o20b2o5b2o$732b2o5b2o226bob
\\o19b2o5b2o$758b2o$759b2o$758bo7$979b2o$978b2o$747bo232bo$222b2o11b2o
\\510b2o240b2o5b2o584b2o11b2o$221bo2bo2b2ob2o2bo2bo508bobo239bo2bo3bo2bo
\\582bo2bo2b2ob2o2bo2bo$221bobo4bobo4bobo753b2ob2o585bobo4bobo4bobo$222b
\\o5bobo5bo494b2obo3bob2o248bobobobo585bo5bobo5bo$225b2obobob2o497bo2bo
\\3bo2bo248bobobobo588b2obobob2o$225bo2bobo2bo498b3o3b3o247bo9bo586bo2bo
\\bo2bo$222bo4bo3bo4bo750bo11bo582bo4bo3bo4bo$222b5o5b5o1345b5o5b5o$730b
\\o260b2ob2o$222b5o5b5o752bo2bobo2bo584b5o5b5o$222bo4bo3bo4bo750b2obob3o
\\b2o584bo4bo3bo4bo$225bo2bobo2bo21b2o729b4ob5o566b2o21bo2bobo2bo$225b2o
\\bobob2o21b2o729bob2ob2obo567b2o21b2obobob2o$209b2o11bo5bobo5bo748b2o7b
\\2o586bo5bobo5bo11b2o$208bo2bo2b2ob2o2bobo4bobo4bobo747b2o7b2o585bobo4b
\\obo4bobo2b2ob2o2bo2bo$208bobo4bobo4bobo2b2ob2o2bo2bo498bo5bo242b3o5b3o
\\585bo2bo2b2ob2o2bobo4bobo4bobo$209bo5bobo5bo11b2o498b3o3b3o243b3ob3o
\\588b2o11bo5bobo5bo$212b2obobob2o513b2obo3bob2o244bobo606b2obobob2o$
\\212bo2bobo2bo765bo2bobo2bo603bo2bobo2bo$209bo4bo3bo4bo39b2o720bo2bo3bo
\\2bo558b2o39bo4bo3bo4bo$209b5o5b5o39b2o472bo3bo244b2o5b2o559b2o39b5o5b
\\5o$737bo3bo$209b5o5b5o167b2o1033b2o167b5o5b5o$209bo4bo3bo4bo167bobo
\\1031bobo167bo4bo3bo4bo$212bo2bobo2bo172bo4b2o1019b2o4bo172bo2bobo2bo$
\\212b2obobob2o168b4ob2o2bo2bo1015bo2bo2b2ob4o168b2obobob2o$209bo5bobo5b
\\o165bo2bobobobob2o1015b2obobobobo2bo165bo5bobo5bo$208bobo4bobo4bobo
\\167bobobobo1021bobobobo167bobo4bobo4bobo$208bo2bo2b2ob2o2bo2bo168b2obo
\\bo1021bobob2o168bo2bo2b2ob2o2bo2bo$209b2o11b2o173bo1023bo173b2o11b2o$
\\479b2o250b2o13b2o128bo105b2o13b2o339b2o$383b2o94b2o5b2o243b2o2b2o5b2o
\\2b2o129bo104b2o2b2o5b2o2b2o332b2o5b2o94b2o$384bo7b2o92b2o247b2o5b2o
\\131b3o108b2o5b2o336b2o92b2o7bo$384bobo5b2o1031b2o5bobo$385b2o1045b2o$
\\455b2o27b2o847b2o27b2o$455b2o27b2o847b2o27b2o$490b2o835b2o$490b2o835b
\\2o$449b2o917b2o$449b2o917b2o$395b2o16bo39b2o909b2o39bo16b2o$350b2o43bo
\\17b3o37b2o909b2o37b3o17bo43b2o$349bobo44b3o17bo985bo17b3o44bobo$343b2o
\\4bo48bo16bobo983bobo16bo48bo4b2o$341bo2bo2b2ob4o61bobo983bobo61b4ob2o
\\2bo2bo$341b2obobobobo2bo62bo31b2o919b2o31bo62bo2bobobobob2o$344bobobob
\\o97b2o919b2o97bobobobo$226b2o116bobob2o1119b2obobo116b2o$226b2o117bo
\\122bo3b2o871b2o3bo122bo117b2o$467bobo3bo871bo3bobo$358b2o71b2o34b2o3bo
\\873bo3b2o34b2o71b2o$349b2o7bo72b2o38bo875bo38b2o72bo7b2o$349b2o5bobo
\\108b5obo871bob5o108bobo5b2o$356b2o109bo4bobo869bobo4bo109b2o$469bo2bob
\\o869bobo2bo$411b2o55b2o3bo7b2o853b2o7bo3b2o55b2o$410bobo68b2o853b2o68b
\\obo$410bo997bo$408bobo7b2o979b2o7bobo$408b2o8b2o979b2o8b2o$346b2o1123b
\\2o$347bo78b2obo959bob2o78bo$344b3o79b2ob3o474bo5bo474b3ob2o79b3o$344bo
\\87bo473bo5bo473bo87bo$426b2ob3o474b2o3b2o474b3ob2o$427bobo959bobo$427b
\\obo472b3o2b2ob2o2b3o472bobo$428bo475bobobobobobo475bo$906b2o3b2o$429bo
\\959bo$427b3o476b2o3b2o476b3o$426bo33b2o8b2o432bobobobobobo432b2o8b2o
\\33bo$426b2o32b2o8bobo429b3o2b2ob2o2b3o429bobo8b2o32b2o$418b2o51bo9b2o
\\853b2o9bo51b2o$418b2o31b2obo25bo2bo422b2o3b2o422bo2bo25bob2o31b2o$451b
\\ob2o26b2o423bo5bo423b2o26b2obo$334b2o570bo5bo570b2o$334b2o1147b2o$474b
\\o869bo$402b2o70b3o865b3o70b2o$403bo73bo863bo73bo$402bo31bo41b2o863b2o
\\41bo31bo$361b2o39b2o28b3o13bo26bo867bo26bo13b3o28b2o39b2o$361b2o68bo
\\16b3o24b3o863b3o24b3o16bo68b2o$431b2o18bo26bo861bo26bo18b2o$334b2o114b
\\2o25b2o861b2o25b2o114b2o$333bo2bo1145bo2bo$333bobo1147bobo$334bo7b2o
\\51b2o1025b2o51b2o7bo$342b2o51b2o77bo869bo77b2o51b2o$473bobo867bobo$
\\434b2o38bo869bo38b2o$434bobo945bobo$436bo945bo$436b2o943b2o$398b2o
\\1019b2o$378b2o19bo36b4o939b4o36bo19b2o$378bobo17bo25b2o3b2o5bo2bo939bo
\\2bo5b2o3b2o25bo17bobo$380bo17b2o24b2o3b2o8bobo935bobo8b2o3b2o24b2o17bo
\\$380b2o58b2o935b2o58b2o$427b4o957b4o$426bo3bo957bo3bo$356bo69b2o963b2o
\\69bo$355bobo53b2o993b2o53bobo$279bo75b2o55bo993bo55b2o75bo$279b3o130bo
\\b2o987b2obo130b3o$282bo130bo2bo985bo2bo130bo$281b2o131b2o47b2o889b2o
\\47b2o131b2o$429b2o32bo891bo32b2o$429b2o22b2o3b2o4b3o885b3o4b2o3b2o22b
\\2o$273b2o176bo2bo4bo6bo885bo6bo4bo2bo176b2o$273bo104b2o71b3o5bobo895bo
\\bo5b3o71b2o104bo$270b2obo104bobo79b2o895b2o79bobo104bob2o$270bo2b3o4b
\\2o98bo57bo3b2o3b2obob4o907b4obob2o3b2o3bo57bo98b2o4b3o2bo$271b2o3bo3b
\\2o84b2o12b2o55bobo3bo3bob2obo2bo907bo2bob2obo3bo3bobo55b2o12b2o84b2o3b
\\o3b2o$273b4o89b2o68bobo3bo933bo3bobo68b2o89b4o$273bo15b2o141b2obobo3bo
\\935bo3bobob2o141b2o15bo$274b3o12bobo2b2o136b2obo2b4obo931bob4o2bob2o
\\136b2o2bobo12b3o$277bo13bo2bo83b2o56bobo3bobo929bobo3bobo56b2o83bo2bo
\\13bo$272b5o14b3o2bo81bobo51b2ob2o2bo2bobo929bobo2bo2b2ob2o51bobo81bo2b
\\3o14b5o$272bo21b3o83bo52bobo2b2o3bo931bo3b2o2bobo52bo83b3o21bo$274bo
\\18bo86b2o39b2o10bobo947bobo10b2o39b2o86bo18bo$273b2o18b2o126b2o11bo
\\949bo11b2o126b2o18b2o7$283b2o1249b2o$282bobo5b2o1235b2o5bobo$282bo7b2o
\\1235b2o7bo$281b2o1253b2o2$295bo1227bo$291b2obobo1225bobob2o$290bobobob
\\o1225bobobobo$287bo2bobobobob2o1219b2obobobobo2bo$287b4ob2o2bo2bo1219b
\\o2bo2b2ob4o$291bo4b2o1223b2o4bo$289bobo1235bobo$289b2o1237b2o46$413b3o
\\987b3o2$417bo983bo$413bo3b2o12bo955bo12b2o3bo$415bobo13b2o953b2o13bobo
\\$412b3o16bobo951bobo16b3o$414bo989bo$430b2o955b2o$413b2o16b2o953b2o16b
\\2o$414b2o14bo2bo951bo2bo14b2o$414bo15b3o5b2o939b2o5b3o15bo$414b2o22b2o
\\939b2o22b2o$413b2o989b2o5$399b3o1015b3o$399b3o27b2o337b2o279b2o337b2o
\\27b3o$398bo3bo25bo2bo14b2o320bobo277bobo320b2o14bo2bo25bo3bo$399b2ob3o
\\23bo2b2o9bo2bob2o321bo4b2o265b2o4bo321b2obo2bo9b2o2bo23b3ob2o$399b2o4b
\\o23bo3bo8bo5b2o316b4ob2o2bo2bo261bo2bo2b2ob4o316b2o5bo8bo3bo23bo4b2o$
\\402bo2bo23bo12bobob3o317bo2bobobobob2o261b2obobobobo2bo317b3obobo12bo
\\23bo2bo$403b2o25bo2b2o11b2o321bobobobo267bobobobo321b2o11b2o2bo25b2o$
\\431bo3bo10b2o322b2obobo267bobob2o322b2o10bo3bo$433bobo338bo269bo338bob
\\o$432bo953bo$432bo327b2o295b2o327bo$427b3obo329bo7b2o277b2o7bo329bob3o
\\$425b2o8bo325bobo5b2o277b2o5bobo325bo8b2o$425bo6b3o327b2o291b2o327b3o
\\6bo$426b2o3bo955bo3b2o$427bob2o957b2obo$425b4o961b4o$425b3o963b3o$405b
\\2o13b2o975b2o13b2o$405b2o13b2o975b2o13b2o$772b2o271b2o$261b2o154bo354b
\\o273bo354bo154b2o$260bobo154bo2bo352b3o267b3o352bo2bo154bobo$254b2o4bo
\\158b2o354bo267bo354b2o158bo4b2o$252bo2bo2b2ob4o1289b4ob2o2bo2bo$252b2o
\\bobobobo2bo513b2o5bobo243bobo5b2o513bo2bobobobob2o$255bobobobo151b2o
\\362bobo6b2o243b2o6bobo362b2o151bobobobo$255bobob2o152b2o356b2o4bo8bo
\\245bo8bo4b2o356b2o152b2obobo$256bo512bo2bo2b2ob4o255b4ob2o2bo2bo512bo$
\\769b2obobobobo2bo255bo2bobobobob2o$269b2o501bobobobo261bobobobo501b2o$
\\260b2o7bo502bobob2o263b2obobo502bo7b2o$260b2o5bobo503bo271bo503bobo5b
\\2o$267b2o1281b2o$786b2o243b2o$777b2o7bo245bo7b2o$777b2o5bobo245bobo5b
\\2o$784b2o247b2o2$264b2o1287b2o$257b2o4b2o1289b2o4b2o$258bo6bo1287bo6bo
\\$255b3o1303b3o$255bo526bo21bo209bo21bo526bo$244bo529b2o5b2o11b2o9b2o
\\205b2o9b2o11b2o5b2o529bo$244bobo4b2o522bo5bobo10bo9b2o207b2o9bo10bobo
\\5bo522b2o4bobo$244b2o5bobo518b3o21bo225bo21b3o518bobo5b2o$253bo4b2o
\\512bo2b3o14b5o225b5o14b3o2bo512b2o4bo$249b4ob2o2bo2bo512bo2bo13bo235bo
\\13bo2bo512bo2bo2b2ob4o$249bo2bobobobob2o511b2o2bobo12b3o229b3o12bobo2b
\\2o511b2obobobobo2bo$252bobobobo519b2o15bo227bo15b2o519bobobobo$253b2ob
\\obo499bobo31b4o227b4o31bobo499bobob2o$257bo500b2o27b2o3bo3b2o223b2o3bo
\\3b2o27b2o500bo$759bo27b2o4b3o2bo221bo2b3o4b2o27bo$243b2o550bob2o221b2o
\\bo550b2o$244bo7b2o541bo227bo541b2o7bo$244bobo5b2o540b2o227b2o540b2o5bo
\\bo$245b2o1325b2o$284bo1249bo$283b2o501b2o243b2o501b2o$283bobo438b2o60b
\\o245bo60b2o438bobo$260bobo462b2o46b2o12b3o239b3o12b2o46b2o462bobo$261b
\\2o461bo47bobo14bo32bobo169bobo32bo14bobo47bo461b2o$261bo512bo48b2o169b
\\2o48bo512bo$224bo10b2o18b2o566bo171bo566b2o18b2o10bo$224bobo9bo18bo
\\532b2o239b2o532bo18bo9bobo$224b2o8bo21b3o528bobo239bobo528b3o21bo8b2o$
\\234b5o14b3o2bo522b2o4bo243bo4b2o522bo2b3o14b5o$239bo13bo2bo522bo2bo2b
\\2ob4o235b4ob2o2bo2bo522bo2bo13bo$236b3o12bobo2b2o521b2obobobobo2bo235b
\\o2bobobobob2o521b2o2bobo12b3o$235bo15b2o529bobobobo241bobobobo529b2o
\\15bo$235b4o7b3o533bobob2o243b2obobo533b3o7b4o$233b2o3bo5b2ob2o534bo
\\251bo534b2ob2o5bo3b2o$232bo2b3o8bo1325bo8b3o2bo$232b2obo560b2o223b2o
\\560bob2o$235bo551b2o7bo31b2o159b2o31bo7b2o551bo$235b2o550b2o5bobo30bob
\\o159bobo30bobo5b2o550b2o$302b2o490b2o25b2o4bo163bo4b2o25b2o490b2o$301b
\\2o403bo112bo2bo2b2ob4o155b4ob2o2bo2bo112bo403b2o$243b2o58bo402b2o111b
\\2obobobobo2bo155bo2bobobobob2o111b2o402bo58b2o$244bo460bobo46b3o65bobo
\\bobo161bobobobo65b3o46bobo460bo$241b3o36bobo473bo65bobob2o163b2obobo
\\65bo473bobo36b3o$241bo39b2o240bo231bo22bo44bo171bo44bo22bo231bo240b2o
\\39bo$281bo240bobo251b2o263b2o251bobo240bo$522b2o253b2o5b2o18b2o30b2o
\\143b2o30b2o18b2o5b2o253b2o$241b2o542bo18bo22b2o7bo145bo7b2o22bo18bo
\\542b2o$241bobo538b3o9bo11bo20b2o5bobo145bobo5b2o20bo11bo9b3o538bobo$
\\243bo4b2o532bo2b3o6b2o6b5o27b2o147b2o27b5o6b2o6b3o2bo532b2o4bo$239b4ob
\\2o2bo2bo532bo2bo7b2o4bo215bo4b2o7bo2bo532bo2bo2b2ob4o$239bo2bobobobob
\\2o531b2o2bobo6b3o2b4o209b4o2b3o6bobo2b2o531b2obobobobo2bo$242bobobobo
\\539b2o6b3o3bo2bo207bo2bo3b3o6b2o539bobobobo$243b2obobo546b2o2b7o207b7o
\\2b2o546bobob2o$247bo550b2o2bo3b2o203b2o3bo2b2o550bo$520b2o277b2o2bobo
\\2bo201bo2bobo2b2o277b2o$233b2o285b2o281bobob2o7bo7b2o18b2o127b2o18b2o
\\7bo7b2obobo281b2o285b2o$201b2o31bo570bo8b2o9bo18bo129bo18bo9b2o8bo570b
\\o31b2o$201bobo30bobo567b2o9b2o5b3o21bo125bo21b3o5b2o9b2o567bobo30bobo$
\\203bo4b2o25b2o5b3o442b2o23bo109bo2b3o14b5o10bobo99bobo10b5o14b3o2bo
\\109bo23b2o442b3o5b2o25b2o4bo$199b4ob2o2bo2bo29bo3bo442b2o22bobo21b2o
\\86bo2bo13bo16b2o99b2o16bo13bo2bo86b2o21bobo22b2o442bo3bo29bo2bo2b2ob4o
\\$199bo2bobobobob2o28bo5bo53bo386bo24b2o21bobo58b2o25b2o2bobo12b3o13bo
\\101bo13b3o12bobo2b2o25b2o58bobo21b2o24bo386bo53bo5bo28b2obobobobo2bo$
\\202bobobobo32bo3bo55bo435bo58bo31b2o15bo127bo15b2o31bo58bo435bo55bo3bo
\\32bobobobo$203b2obobo33b3o54b3o495b3o42b4o127b4o42b3o495b3o54b3o33bobo
\\b2o$207bo591bo37b2o3bo3b2o123b2o3bo3b2o37bo591bo$328b2o507b2o4b3o2bo
\\121bo2b3o4b2o507b2o$193b2o30b2o18b2o81bobo449b2o63bob2o121b2obo63b2o
\\449bobo81b2o18b2o30b2o$194bo7b2o22bo18bo82bo452b2o62bo127bo62b2o452bo
\\82bo18bo22b2o7bo$194bobo5b2o20bo21b3o531bo63b2o127b2o63bo531b3o21bo20b
\\2o5bobo$195b2o27b5o14b3o2bo578b2o161b2o578bo2b3o14b5o27b2o$229bo13bo2b
\\o36b2o541bobo161bobo541b2o36bo2bo13bo$226b3o12bobo2b2o35bobo542bo7b2o
\\143b2o7bo542bobo35b2o2bobo12b3o$225bo15b2o40bo552bo145bo552bo40b2o15bo
\\$225b4o608b3o139b3o608b4o$176bo46b2o3bo3b2o605bo139bo605b2o3bo3b2o46bo
\\$175bo46bo2b3o4b2o562bobo221bobo562b2o4b3o2bo46bo$175b3o7b2o18b2o15b2o
\\bo570b2o223b2o570bob2o15b2o18b2o7b3o$186bo18bo19bo13b3o452bo102bo40b2o
\\36bo65bo36b2o40bo102bo452b3o13bo19bo18bo$184bo10b2o9b3o16b2o12bo453bo
\\143bobo37b2o61b2o37bobo143bo453bo12b2o16b3o9b2o10bo$184b5o5bobo6b3o2bo
\\7bobo21bo452b3o21b3o111b2o4bo38b2o63b2o38bo4b2o111b3o21b3o452bo21bobo
\\7bo2b3o6bobo5b5o$189bo6bo6bo2bo10b2o500bo21bobo85bo2bo2b2ob4o135b4ob2o
\\2bo2bo85bobo21bo500b2o10bo2bo6bo6bo$186b2obo2bo8bobo2b2o9bo15b2o483bo
\\22b2o86b2obobobobo2bo135bo2bobobobob2o86b2o22bo483b2o15bo9b2o2bobo8bo
\\2bob2o$185bo15b2o31bo85bo421bo89bobobobo141bobobobo89bo421bo85bo31b2o
\\15bo$185b2o3bo3b2o35b3o87b2o162bo66bo110b2o167bobob2o143b2obobo167b2o
\\110bo66bo162b2o87b3o35b2o3bo3b2o$183b2o7bo38bo88b2o163b2o64b2o109bobo
\\168bo151bo168bobo109b2o64b2o163b2o88bo38bo7b2o$182bo2bob2ob3o291bobo
\\64bobo110bo234bo19bo234bo110bobo64bobo291b3ob2obo2bo$182b2obo651bo8b2o
\\49b3o19b3o49b2o8bo651bob2o$185bo650b3o7bo49bo25bo49bo7b3o650bo$185b2o
\\648b5o4bobo49b2o23b2o49bobo4b5o648b2o$301b3o530bo5bo3b2o127b2o3bo5bo
\\530b3o$301bo531b2o2bo2b2o135b2o2bo2b2o531bo$193b2o107bo529b3obobob3o
\\61b2o7b2o61b3obobob3o529bo107b2o$194bo638b2o2bo2b2o63bo7bo63b2o2bo2b2o
\\638bo$191b3o585bo23b2o35bo64bob2ob2obo64bo35b2o23bo585b3o$191bo585b2o
\\23bobo34bo53bobo7b3o2bobo2b3o7bobo53bo34bobo23b2o585bo$284bo493b2o24bo
\\87bo2bo6bo3b2o3b2o3bo6bo2bo87bo24b2o493bo$282bobo73b3o314bo158b2o18b2o
\\36bo2bo6b4o7b4o6bo2bo36b2o18b2o158bo314b3o73bobo$191b2o17b2o49bo21b2o
\\73bo316bobo157bo18bo33b2o3bo11bo7bo11bo3b2o33bo18bo157bobo316bo73b2o
\\21bo49b2o17b2o$191bobo16bobo47b2o97bo315b2o46bo108b3o21bo30bobo12b3o9b
\\3o12bobo30bo21b3o108bo46b2o315bo97b2o47bobo16bobo$193bo4b2o10bo27bo21b
\\obo459bo109bo2b3o14b5o30bo13bo15bo13bo30b5o14b3o2bo109bo459bobo21bo27b
\\o10b2o4bo$189b4ob2o2bo2bo37bo482b3o109bo2bo13bo34b2o14b5o5b5o14b2o34bo
\\13bo2bo109b3o482bo37bo2bo2b2ob4o$149bobo37bo2bobobobob2o35b3o593b2o2bo
\\bo12b3o51bo5bo51b3o12bobo2b2o593b3o35b2obobobobo2bo37bobo$149b2o41bobo
\\bobo141bo303b3o191b2o15bo48bo9bo48bo15b2o191b3o303bo141bobobobo41b2o$
\\150bo42b2obobo142b2o303bo205b4o48b2o7b2o48b4o205bo303b2o142bobob2o42bo
\\$197bo142b2o303bo196b2o3b2o3bo3b2o103b2o3bo3b2o3b2o196bo303b2o142bo$
\\131bo711b2o2b2o4b3o2bo101bo2b3o4b2o2b2o711bo$131b3o49b2o657bo12bob2o
\\101b2obo12bo657b2o49b3o$134bo49bo670bo107bo670bo49bo$133b2o49bobo6bo
\\432b2o226b2o107b2o226b2o432bo6bobo49b2o$185b2o5b3o432bo563bo432b3o5b2o
\\$191b5o429bo567bo429b5o$125b2o7bo55b2o3b2o428b5o14b2o200b2o123b2o200b
\\2o14b5o428b2o3b2o55bo7b2o$125bo8b2o55b5o434bo13bo2bo111bo24b2o23bo36bo
\\125bo36bo23b2o24bo111bo2bo13bo434b5o55b2o8bo$122b2obo6b2ob4o53b3o432b
\\3o12bobob2o111bobo23b2o22bobo35b3o119b3o35bobo22b2o23bobo111b2obobo12b
\\3o432b3o53b4ob2o6bob2o$122bo2b4obo2b2o2b2o54bo183b2o247bo15b2obo113b2o
\\23bo24b2o38bo119bo38b2o24bo23b2o113bob2o15bo247b2o183bo54b2o2b2o2bob4o
\\2bo$123b2o7b2o2bob2o188b2o47bobo246b4o15bo527bo15b4o246bobo47b2o188b2o
\\bo2b2o7b2o$125b3o2bo2bobo2bo36b2o18b2o106bobo21b2o48bo246b2o3bo3b2o10b
\\3o523b3o10b2o3bo3b2o246bo48b2o21bobo106b2o18b2o36bo2bobo2bo2b3o$125bo
\\6b2o4bo2b2o33bo18bo108b2o23bo293bo2b3o4b2o13bo521bo13b2o4b3o2bo293bo
\\23b2o108bo18bo33b2o2bo4b2o6bo$126b3o12bobo30bo21b3o32b2o71bo318b2obo
\\20b2o17b2o483b2o17b2o20bob2o318bo71b2o32b3o21bo30bobo12b3o$129bo4bo8bo
\\30b5o14b3o2bo31b2o26bo367bo14b2o24bo206bo69bo206bo24b2o14bo367bo26b2o
\\31bo2b3o14b5o30bo8bo4bo$124b5o5bo2bo5b2o34bo13bo2bo35bo26bo366b2o13bob
\\o21bo208bobo65bobo208bo21bobo13b2o366bo26bo35bo2bo13bo34b2o5bo2bo5b5o$
\\124bo10bobo38b3o12bobo2b2o59b3o381bo23b5o14b2o188b2o67b2o188b2o14b5o
\\23bo381b3o59b2o2bobo12b3o38bobo10bo$126bo48bo15b2o477bo13bo2bo11bo124b
\\o169bo124bo11bo2bo13bo477b2o15bo48bo$125b2o48b4o455b2o31b3o12bobob2o
\\10bo125b2o167b2o125bo10b2obobo12b3o31b2o455b4o48b2o$173b2o3bo3b2o451bo
\\30bo15b2obo12b3o122bobo167bobo122b3o12bob2o15bo30bo451b2o3bo3b2o$172bo
\\2b3o4b2o29bo418b3o22b2o7b4o15bo447bo15b4o7b2o22b3o418bo29b2o4b3o2bo$
\\172b2obo38b2o416bo17b2o5bobo4b2o3bo3b2o10b3o443b3o10b2o3bo3b2o4bobo5b
\\2o17bo416b2o38bob2o$175bo37b2o435b2o7bo3bo2b3o4b2o13bo441bo13b2o4b3o2b
\\o3bo7b2o435b2o37bo$175b2o226b2o254b2o2b2obo20b2o441b2o20bob2o2b2o254b
\\2o226b2o$403bo262bo485bo262bo$405bo240bo19b2o123bo235bo123b2o19bo240bo
\\$183b2o200b2o14b5o239bobob2o89bobo47bo237bo47bobo89b2obobo239b5o14b2o
\\200b2o$184bo198bo2bo13bo244bobobobo88b2o48b3o233b3o48b2o88bobobobo244b
\\o13bo2bo198bo$181b3o11b3o185b2obobo12b3o238b2obobobobo2bo19b2o65bo335b
\\o65b2o19bo2bobobobob2o238b3o12bobob2o185b3o11b3o$181bo13bo189bob2o15bo
\\237bo2bo2b2ob4o20bo467bo20b4ob2o2bo2bo237bo15b2obo189bo13bo$196bo188bo
\\15b4o239b2o4bo21b3o22b2o421b2o22b3o21bo4b2o239b4o15bo188bo$250bo72bobo
\\57b3o10b2o3bo3b2o243bobo19bo17b2o5bobo419bobo5b2o17bo19bobo243b2o3bo3b
\\2o10b3o57bobo72bo$249b2o73b2o56bo13b2o4b3o2bo243b2o37b2o7bo156bo105bo
\\156bo7b2o37b2o243bo2b3o4b2o13bo56b2o73b2o$249bobo72bo38b2o17b2o20bob2o
\\291b2o57b3o94bo107bo94b3o57b2o291b2obo20b2o17b2o38bo72bobo$363bo24bo
\\15bo355bo94b3o103b3o94bo355bo15bo24bo$365bo22b2o13b2o281bo72bo299bo72b
\\o281b2o13b2o22bo$345b2o14b5o21bobo295bobob2o437b2obobo295bobo21b5o14b
\\2o$343bo2bo13bo324bobobobo435bobobobo324bo13bo2bo$343b2obobo12b3o31b2o
\\285b2obobobobo2bo429bo2bobobobob2o285b2o31b3o12bobob2o$283bo61bob2o15b
\\o30bo286bo2bo2b2ob4o429b4ob2o2bo2bo286bo30bo15b2obo61bo$281bobo61bo15b
\\4o7b2o22b3o285b2o4bo437bo4b2o285b3o22b2o7b4o15bo61bobo$282b2o59b3o10b
\\2o3bo3b2o4bobo5b2o17bo291bobo433bobo291bo17b2o5bobo4b2o3bo3b2o10b3o59b
\\2o$342bo13b2o4b3o2bo3bo7b2o310b2o433b2o310b2o7bo3bo2b3o4b2o13bo$342b2o
\\20bob2o2b2o1075b2o2b2obo20b2o$364bo407bo273bo407bo$363b2o19bo387bobo
\\269bobo387bo19b2o$380b2obobo386b2o271b2o386bobob2o$379bobobobo1047bobo
\\bobo$355b2o19bo2bobobobob2o1041b2obobobobo2bo19b2o$355bo20b4ob2o2bo2bo
\\1041bo2bo2b2ob4o20bo$268b2o62b2o22b3o21bo4b2o329bobo381bobo329b2o4bo
\\21b3o22b2o62b2o$267b2o62bobo5b2o17bo19bobo335b2o119bo143bo119b2o335bob
\\o19bo17b2o5bobo62b2o$269bo61bo7b2o37b2o337bo71bo47bobo139bobo47bo71bo
\\337b2o37b2o7bo61bo$330b2o344b2o111b2o46b2o141b2o46b2o111b2o344b2o$677b
\\o110bobo237bobo110bo$344bo330bo467bo330bo$340b2obobo329b5o14b2o427b2o
\\14b5o329bobob2o$339bobobobo334bo13bo2bo36b3o345b3o36bo2bo13bo334bobobo
\\bo$336bo2bobobobob2o296b3o29b3o12bobob2o38bo345bo38b2obobo12b3o29b3o
\\296b2obobobobo2bo$336b4ob2o2bo2bo296bo30bo15b2obo39bo347bo39bob2o15bo
\\30bo296bo2bo2b2ob4o$302bobo35bo4b2o299bo29b4o15bo427bo15b4o29bo299b2o
\\4bo35bobo$253bobo47b2o33bobo79b3o251b2o3bo3b2o10b3o423b3o10b2o3bo3b2o
\\251b3o79bobo33b2o47bobo$254b2o47bo34b2o82bo250bo2b3o4b2o13bo421bo13b2o
\\4b3o2bo250bo82b2o34bo47b2o$254bo166bo251b2obo20b2o17b2o383b2o17b2o20bo
\\b2o251bo166bo$676bo40bo383bo40bo$676b2o37bo387bo37b2o$715b5o14b2o347b
\\2o14b5o$720bo13bo2bo343bo2bo13bo$684b2o31b3o12bobob2o343b2obobo12b3o
\\31b2o$685bo30bo15b2obo347bob2o15bo30bo$682b3o22b2o7b4o15bo347bo15b4o7b
\\2o22b3o$682bo17b2o5bobo4b2o3bo3b2o10b3o32b2o275b2o32b3o10b2o3bo3b2o4bo
\\bo5b2o17bo$450b2o248b2o7bo3bo2b3o4b2o13bo32b2o273b2o32bo13b2o4b3o2bo3b
\\o7b2o248b2o$353b2o95bobo256b2o2b2obo20b2o31bo277bo31b2o20bob2o2b2o256b
\\obo95b2o$353bo98bo4b2o257bo15bo353bo15bo257b2o4bo98bo$355bo92b4ob2o2bo
\\2bo235bo19b2o13b2o353b2o13b2o19bo235bo2bo2b2ob4o92bo$244b2o48b2o39b2o
\\14b5o92bo2bobobobob2o234bobob2o30bobo351bobo30b2obobo234b2obobobobo2bo
\\92b5o14b2o39b2o48b2o$244bobo47bobo36bo2bo13bo100bobobobo237bobobobo
\\415bobobobo237bobobobo100bo13bo2bo36bobo47bobo$244bo49bo38b2obobo12b3o
\\98b2obobo234b2obobobobo2bo19b2o367b2o19bo2bobobobob2o234bobob2o98b3o
\\12bobob2o38bo49bo$335bob2o15bo101bo235bo2bo2b2ob4o20bo367bo20b4ob2o2bo
\\2bo235bo101bo15b2obo$322bobo10bo15b4o339b2o4bo21b3o22b2o321b2o22b3o21b
\\o4b2o339b4o15bo10bobo$323b2o8b3o10b2o3bo3b2o85b2o256bobo19bo17b2o5bobo
\\319bobo5b2o17bo19bobo256b2o85b2o3bo3b2o10b3o8b2o$323bo8bo13b2o4b3o2bo
\\85bo7b2o248b2o37b2o7bo319bo7b2o37b2o248b2o7bo85bo2b3o4b2o13bo8bo$313b
\\2o17b2o20bob2o85bobo5b2o296b2o317b2o296b2o5bobo85b2obo20b2o17b2o$204bo
\\bo106bo40bo89b2o927b2o89bo40bo106bobo$205b2o108bo37b2o381bo345bo381b2o
\\37bo108b2o$205bo89b2o14b5o419bobob2o337b2obobo419b5o14b2o89bo$281bo11b
\\o2bo13bo424bobobobo335bobobobo424bo13bo2bo11bo$279bobo11b2obobo12b3o
\\31b2o385b2obobobobo2bo329bo2bobobobob2o385b2o31b3o12bobob2o11bobo$280b
\\2o13bob2o15bo30bo102b2o282bo2bo2b2ob4o329b4ob2o2bo2bo282b2o102bo30bo
\\15b2obo13b2o$295bo15b4o7b2o22b3o100b2o283b2o4bo337bo4b2o283b2o100b3o
\\22b2o7b4o15bo$293b3o10b2o3bo3b2o4bobo5b2o17bo85b2o12bo5b2o284bobo30b2o
\\269b2o30bobo284b2o5bo12b2o85bo17b2o5bobo4b2o3bo3b2o10b3o$292bo13b2o4b
\\3o2bo3bo7b2o104bo18bo286b2o30bo271bo30b2o286bo18bo104b2o7bo3bo2b3o4b2o
\\13bo$292b2o20bob2o2b2o111bo21b3o313bobo271bobo313b3o21bo111b2o2b2obo
\\20b2o$314bo118b5o14b3o2bo301bo11b2o10bo251bo10b2o11bo301bo2b3o14b5o
\\118bo$297b3o13b2o19bo103bo13bo2bo302b3o22b3o247b3o22b3o302bo2bo13bo
\\103bo19b2o13b3o$264b2o33bo30b2obobo99b3o12bobo2b2o300b2ob2o3bo20bo245b
\\o20bo3b2ob2o300b2o2bobo12b3o99bobob2o30bo33b2o$264bobo31bo30bobobobo
\\98bo15b2o304b2o6bobo18b2o245b2o18bobo6b2o304b2o15bo98bobobobo30bo31bob
\\o$264bo40b2o19bo2bobobobob2o95b4o312b2o48b2o215b2o48b2o312b4o95b2obobo
\\bobo2bo19b2o40bo$305bo20b4ob2o2bo2bo93b2o3bo3b2o28bo278b2o4b3o41bo217b
\\o41b3o4b2o278bo28b2o3bo3b2o93bo2bo2b2ob4o20bo$282b2o22b3o21bo4b2o94bo
\\2b3o4b2o29b2o284bo38b2obo217bob2o38bo284b2o29b2o4b3o2bo94b2o4bo21b3o
\\22b2o$281bobo5b2o17bo19bobo100b2obo36b2o323bo2bo219bo2bo323b2o36bob2o
\\100bobo19bo17b2o5bobo$281bo7b2o37b2o104bo362b2o221b2o362bo104b2o37b2o
\\7bo$280b2o152b2o323bob2o19b2o251b2o19b2obo323b2o152b2o$759bo2bo19b2o
\\251b2o19bo2bo$294bo464b3o295b3o464bo$273bo16b2obobo146b2o931b2o146bobo
\\b2o16bo$273bo15bobobobo147bo9b3o907b3o9bo147bobobobo15bo$272bo13bo2bob
\\obobob2o141b3o10bo911bo10b3o141b2obobobobo2bo13bo$286b4ob2o2bo2bo141bo
\\13bo315b2o3bo267bo3b2o315bo13bo141bo2bo2b2ob4o$232bo44bo12bo4b2o473bo
\\3bobo265bobo3bo473b2o4bo12bo44bo$230bobo23b2o20bo9bobo480bo3bobob2o
\\257b2obobo3bo480bobo9bo20b2o23bobo$231b2o24bo19bo10b2o150b2o320b2o8bo
\\4bob2o257b2obo4bo8b2o320b2o150b2o10bo19bo24b2o$257bobo180bobo319bo7bob
\\5o265b5obo7bo319bobo180bobo$247bo10b2o182bo4b2o314b3o3bobo4bob2obob2o
\\249b2obob2obo4bobo3b3o314b2o4bo182b2o10bo$245b3o190b4ob2o2bo2bo314bo4b
\\o2b2obo2bob2obo249bob2obo2bob2o2bo4bo314bo2bo2b2ob4o190b3o$244bo193bo
\\2bobobobob2o320b2obob2o12b2o235b2o12b2obob2o320b2obobobobo2bo193bo$
\\244b2o195bobobobo342b2o235b2o342bobobobo195b2o$229b2o31bo16b2o161b2obo
\\bo923bobob2o161b2o16bo31b2o$230bo29b2obo15b2o165bo925bo165b2o15bob2o
\\29bo$230bob2o24b2obob2o1289b2obob2o24b2obo$231bo2bo25bo171b2o951b2o
\\171bo25bo2bo$232b2o22bobo141b2o31bo7b2o301bobo325bobo301b2o7bo31b2o
\\141bobo22b2o$237bo2bo159bobo30bobo5b2o301b2o327b2o301b2o5bobo30bobo
\\159bo2bo$235b2o4b2o13b2o144bo4b2o25b2o309bo327bo309b2o25b2o4bo144b2o
\\13b2o4b2o$237bo2bo157b4ob2o2bo2bo61b2o871b2o61bo2bo2b2ob4o157bo2bo$
\\240b2ob2o153bo2bobobobob2o38bo22bobo869bobo22bo38b2obobobobo2bo153b2ob
\\2o$242b2ob2o154bobobobo39bobo22bo873bo22bobo39bobobobo154b2ob2o$240bo
\\2bo158b2obobo40b2o919b2o40bobob2o158bo2bo$238b3o3b3o8bo3b2o145bo1005bo
\\145b2o3bo8b3o3b3o$240bo13bobo3bo240bobo811bobo240bo3bobo13bo$240b2obo
\\6b2obobo3bo132b2o30b2o18b2o56b2o811b2o56b2o18b2o30b2o132bo3bobob2o6bob
\\2o$241bobo6b2obo4bo8b2o124bo31bo18bo57bo813bo57bo18bo31bo124b2o8bo4bob
\\2o6bobo$242bo11b5obo7bo124bobo27bo21b3o923b3o21bo27bobo124bo7bob5o11bo
\\$246b2obob2obo4bobo3b3o126b2o6bo20b5o14b3o2bo923bo2b3o14b5o20bo6b2o
\\126b3o3bobo4bob2obob2o$246bob2obo2bob2o2bo4bo136bo25bo13bo2bo927bo2bo
\\13bo25bo136bo4bo2b2obo2bob2obo$239b2o12b2obob2o20bo120bobo21b3o12bobo
\\2b2o925b2o2bobo12b3o21bobo120bo20b2obob2o12b2o$239b2o40bo120b2o20bo10b
\\2o3b2o935b2o3b2o10bo20b2o120bo40b2o$279b3o120b2o20b4o6b2obo943bob2o6b
\\4o20b2o120b3o$422b2o3bo5bo3bo943bo3bo5bo3b2o$335b2o84bo2b3o7b3o290bo
\\363bo290b3o7b3o2bo84b2o$336b2o46b2o18b2o15b2obo10bo289b2o365b2o289bo
\\10bob2o15b2o18b2o46b2o$335bo49bo18bo19bo301b2o363b2o301bo19bo18bo49bo$
\\383bo21b3o16b2o281b2o401b2o281b2o16b3o21bo$383b5o14b3o2bo82b3o213b2o
\\403b2o213b3o82bo2b3o14b5o$388bo13bo2bo60bobo21bo217bo401bo217bo21bobo
\\60bo2bo13bo$385b3o12bobo2b2o25b2o33b2o22bo835bo22b2o33b2o25b2o2bobo12b
\\3o$384bo15b2o31bo33bo883bo33bo31b2o15bo$384b4o42b3o88bo775bo88b3o42b4o
\\$382b2o3bo3b2o37bo91bo773bo91bo37b2o3bo3b2o$381bo2b3o4b2o127b3o773b3o
\\127b2o4b3o2bo$381b2obo13b2o1019b2o13bob2o$384bo13bobo1017bobo13bo$384b
\\2o12bo1021bo12b2o$451b2o913b2o$451bobo911bobo$300bo91b2o57bo915bo57b2o
\\91bo$301bo91bo1031bo91bo$299b3o3b2o83b3o1033b3o83b2o3b3o$304b2o84bo
\\1037bo84b2o$306bo1205bo2$390b2o117b2o797b2o117b2o$390bobo116bobo795bob
\\o116bobo$392bo4b2o110bo799bo110b2o4bo$388b4ob2o2bo2bo1017bo2bo2b2ob4o$
\\388bo2bobobobob2o1017b2obobobobo2bo$391bobobobo1023bobobobo$392b2obobo
\\1023bobob2o$396bo93bobo208b3o411b3o208bobo93bo$416b3o72b2o210bo411bo
\\210b2o72b3o$382b2o32bo74bo210bo413bo210bo74bo32b2o$383bo7b2o24bo127bo
\\727bo127bo24b2o7bo$383bobo5b2o76b3o74bo725bo74b3o76b2o5bobo$384b2o83bo
\\74b3o725b3o74bo83b2o$470bo877bo$324bo1169bo$323b2o1169b2o$323bobo1167b
\\obo3$374b2o18b2o1027b2o18b2o$375bo18bo1029bo18bo$373bo21b3o1023b3o21bo
\\$373b5o14b3o2bo1023bo2b3o14b5o$378bo13bo2bo1027bo2bo13bo$375b3o12bobo
\\2b2o10bobo999bobo10b2o2bobo12b3o$374bo15b2o16b2o999b2o16b2o15bo$374b4o
\\30bo1001bo30b4o$372b2o3bo3b2o298b3o451b3o298b2o3bo3b2o$371bo2b3o4b2o
\\300bo451bo300b2o4b3o2bo$371b2obo307bo453bo307bob2o$374bo1069bo$374b2o
\\1067b2o$441b2o933b2o$342b2o96b2o935b2o96b2o$341b2o39b2o58bo192b2o545b
\\2o192bo58b2o39b2o$343bo39bo10b2o239b2o12b2obob2o507b2obob2o12b2o239b2o
\\10bo39bo$380b3o10b2o247bob2obo2bob2o2bo4bo495bo4bo2b2obo2bob2obo247b2o
\\10b3o$364b2o14bo14bo246b2obob2obo4bobo3b3o491b3o3bobo4bob2obob2o246bo
\\14bo14b2o$364b2o284b5obo7bo489bo7bob5o284b2o$646b2obo4bo8b2o489b2o8bo
\\4bob2o$646b2obobo3bo507bo3bobob2o$549b3o98bobo3bo505bo3bobo98b3o$427bo
\\121bo101bo3b2o505b2o3bo101bo121bo$428bo121bo717bo121bo$426b3o221b2o
\\515b2o221b3o$650bobo513bobo$650bo517bo$596bo46b2o529b2o46bo$594b3o46b
\\2o529b2o46b3o$350b2o241bo34b2o35b3o483b3o35b2o34bo241b2o$349bobo108bo
\\132b2o32bo2bo33bo2bo483bo2bo33bo2bo32b2o132bo108bobo$349bo109b2o165bob
\\2o33bo4b2o479b2o4bo33b2obo165b2o109bo$348b2o109bobo164bo35b2o4b2o5b2o
\\465b2o5b2o4b2o35bo164bobo109b2o$601b2o22b2o34bob4ob2o5b2o465b2o5b2ob4o
\\bo34b2o22b2o$602bo37b2o19b2o3b2o483b2o3b2o19b2o37bo$388bobo211bob2o34b
\\o537bo34b2obo211bobo$349bo39b2o186b2o15b2o4b3o2bo35b3o531b3o35bo2b3o4b
\\2o15b2o186b2o39bo$348bobo2b2o34bo187bo16b2o3bo3b2o38bo10b2o507b2o10bo
\\38b2o3bo3b2o16bo187bo34b2o2bobo$347bobo2bobo14b2o196b2o10bo19b4o50bobo
\\507bobo50b4o19bo10b2o196b2o14bobo2bobo$347bo2b2o17bo48b2o139b2o5b3o6b
\\5o5b2o15bo50bo30b2o447b2o30bo50bo15b2o5b5o6b3o5b2o139b2o48bo17b2o2bo$
\\348bobo19b3o44b2o138bo2bo6bobo4bo9bobo12b3o50b2o30bobo445bobo30b2o50b
\\3o12bobo9bo4bobo6bo2bo138b2o44b3o19bobo$347b2obo2bo18bo46bo100b2o35b2o
\\bobo3b4o5b3o6bo13bo87bo4b2o433b2o4bo87bo13bo6b3o5b4o3bobob2o35b2o100bo
\\46bo18bo2bob2o$350bobobo164b2o38bob2o3b3ob2o6bo4b2o14b5o78b4ob2o2bo2bo
\\429bo2bo2b2ob4o78b5o14b2o4bo6b2ob3o3b2obo38b2o164bobobo$347b4o2bo167bo
\\37bo5bo2bobo2b6o24bo78bo2bobobobob2o429b2obobobobo2bo78bo24b6o2bobo2bo
\\5bo37bo167bo2b4o$347bo3b2o204b3o5bo2bo2bob3o3b2o20bo83bobobobo435bobob
\\obo83bo20b2o3b3obo2bo2bo5b3o204b2o3bo$349bo206bo8b2o3bo2bo2b3o2bo19b2o
\\83b2obobo435bobob2o83b2o19bo2b3o2bo2bo3b2o8bo206bo$348b2ob2o98bo85b2o
\\17b2o12b2o6bob2o108bo437bo108b2obo6b2o12b2o17b2o85bo98b2ob2o$351b2o99b
\\o84bo26bo2b3o8bo661bo8b3o2bo26bo84bo99b2o$348b2o100b3o86bo24bo4bo7b2o
\\97b2o463b2o97b2o7bo4bo24bo86b3o100b2o$348bo10b2o117b2o23bo15b2o14b5o
\\14bo122bo7b2o37b2o367b2o37b2o7bo122bo14b5o14b2o15bo23b2o117b2o10bo$
\\349bo9b2o7b2o107b2o25b2o11bo2bo13bo20bo10bo3bo106bobo5b2o17bo19bobo
\\365bobo19bo17b2o5bobo106bo3bo10bo20bo13bo2bo11b2o25b2o107b2o7b2o9bo$
\\348b2o18bo110bo23b2o12b2obobo12b3o15b3o14bo107b2o22b3o21bo4b2o353b2o4b
\\o21b3o22b2o107bo14b3o15b3o12bobob2o12b2o23bo110bo18b2o$366bobo150bob2o
\\15bo30bo131bo20b4ob2o2bo2bo349bo2bo2b2ob4o20bo131bo30bo15b2obo150bobo$
\\366b2o39bo111bo15b4o7b2o22b3o128b2o19bo2bobobobob2o349b2obobobobo2bo
\\19b2o128b3o22b2o7b4o15bo111bo39b2o$408b2o107b3o10b2o3bo3b2o4bobo5b2o
\\17bo152bobobobo355bobobobo152bo17b2o5bobo4b2o3bo3b2o10b3o107b2o$407b2o
\\107bo13b2o4b3o2bo3bo7b2o22bobo146b2obobo355bobob2o146bobo22b2o7bo3bo2b
\\3o4b2o13bo107b2o$516b2o20bob2o2b2o31b2o31b2o97b2o19bo357bo19b2o97b2o
\\31b2o31b2o2b2obo20b2o$346b2o190bo39bo32b2o97bo397bo97b2o32bo39bo190b2o
\\$346b2o88b3o82bo15b2o19bo51bo77b2o20bob2o2b2o383b2o2b2obo20b2o77bo51bo
\\19b2o15bo82b3o88b2o$436bo84b2o31b2obobo94bo33bo13b2o4b3o2bo3bo7b2o365b
\\2o7bo3bo2b3o4b2o13bo33bo94bobob2o31b2o84bo$437bo82bobo30bobobobo94bobo
\\32b3o10b2o3bo3b2o4bobo5b2o17bo329bo17b2o5bobo4b2o3bo3b2o10b3o32bobo94b
\\obobobo30bobo82bo$529b2o19bo2bobobobob2o91b2o35bo15b4o7b2o22b3o329b3o
\\22b2o7b4o15bo35b2o91b2obobobobo2bo19b2o$529bo20b4ob2o2bo2bo128bob2o15b
\\o16b2o12bo335bo12b2o16bo15b2obo128bo2bo2b2ob4o20bo$362bo143b2o22b3o21b
\\o4b2o114b2o12b2obobo12b3o16b3o12b2o333b2o12b3o16b3o12bobob2o12b2o114b
\\2o4bo21b3o22b2o143bo$361bobo141bobo5b2o17bo19bobo121b2o11bo2bo13bo20bo
\\363bo20bo13bo2bo11b2o121bobo19bo17b2o5bobo141bobo$361bobo141bo7b2o37b
\\2o121bo15b2o14b5o395b5o14b2o15bo121b2o37b2o7bo141bobo$362bo141b2o205bo
\\37b2o317b2o37bo205b2o141bo$363b3o343bo40bo317bo40bo343b3o$365bo152bo
\\190b2o17b2o20bob2o311b2obo20b2o17b2o190bo152bo$514b2obobo208bo14b3ob2o
\\bo2bo311bo2bob2ob3o14bo208bobob2o$513bobobobo209b3o11bo7b2o313b2o7bo
\\11b3o209bobobobo$510bo2bobobobob2o208bo8b2o3bo3b2o317b2o3bo3b2o8bo208b
\\2obobobobo2bo$425bobo82b4ob2o2bo2bo208bob2o15bo317bo15b2obo208bo2bo2b
\\2ob4o82bobo$426b2o86bo4b2o39bo168b2obobo8bo2bob2o319b2obo2bo8bobob2o
\\168bo39b2o4bo86b2o$426bo85bobo43b2o169bo2bo6bo6bo325bo6bo6bo2bo169b2o
\\43bobo85bo$512b2o45b2o170b2o6bobo5b5o315b5o5bobo6b2o170b2o45b2o$590b2o
\\147b2o10bo315bo10b2o147b2o$591b2o156bo319bo156b2o$590bo158b2o317b2o
\\158bo$634bo549bo$387b2o245bobo545bobo245b2o$386b2o246b2o547b2o246b2o$
\\388bo1041bo$513bo141b2o505b2o141bo$512b2o142b2o21bo459bo21b2o142b2o$
\\512bobo140bo23bobo455bobo23bo140bobo$527b2o150b2o457b2o150b2o$490bobo
\\34bo763bo34bobo$491b2o36bo170b2o415b2o170bo36b2o$491bo17b2o14b5o171b2o
\\31b2o347b2o31b2o171b5o14b2o17bo$444bo62bo2bo13bo175bo33bobo345bobo33bo
\\175bo13bo2bo62bo$445b2o60b2obobo12b3o208bo4b2o333b2o4bo208b3o12bobob2o
\\60b2o$444b2o63bob2o15bo11bobo189b4ob2o2bo2bo329bo2bo2b2ob4o189bobo11bo
\\15b2obo63b2o$509bo15b4o11b2o190bo2bobobobob2o329b2obobobobo2bo190b2o
\\11b4o15bo$473b2o32b3o10b2o3bo3b2o10bo193bobobobo335bobobobo193bo10b2o
\\3bo3b2o10b3o32b2o$473bobo30bo13b2o4b3o2bo204b2obobo335bobob2o204bo2b3o
\\4b2o13bo30bobo$473bo13b2o17b2o20bob2o208bo337bo208b2obo20b2o17b2o13bo$
\\487bo40bo40b3o675b3o40bo40bo$489bo37b2o42bo154b2o363b2o154bo42b2o37bo$
\\469b2o14b5o80bo156bo7b2o37b2o267b2o37b2o7bo156bo80b5o14b2o$467bo2bo13b
\\o242bobo5b2o17bo19bobo265bobo19bo17b2o5bobo242bo13bo2bo$467b2obobo12b
\\3o21b2o8b2o207b2o22b3o21bo4b2o253b2o4bo21b3o22b2o207b2o8b2o21b3o12bobo
\\b2o$469bob2o15bo16bo2b2o9bo231bo20b4ob2o2bo2bo249bo2bo2b2ob4o20bo231bo
\\9b2o2bo16bo15b2obo$469bo15b4o7b2o7b4o11b3o228b2o19bo2bo3bobob2o249b2ob
\\obo3bo2bo19b2o228b3o11b4o7b2o7b4o15bo$411b2o54b3o10b2o3bo3b2o4bobo8b2o
\\14bo111b3o139b2obobo255bobob2o139b3o111bo14b2o8bobo4b2o3bo3b2o10b3o54b
\\2o$410b2o54bo13b2o4b3o2bo3bo8bob2o128bo139b2obobo255bobob2o139bo128b2o
\\bo8bo3bo2b3o4b2o13bo54b2o$412bo53b2o20bob2o2b2o7b3o102bo26bo123b2o19bo
\\257bo19b2o123bo26bo102b3o7b2o2b2obo20b2o53bo$488bo14bobo100b2o152bo
\\297bo152b2o100bobo14bo$487b2o16bob2o98b2o129b2o20bob2o2b2o283b2o2b2obo
\\20b2o129b2o98b2obo16b2o$464bo39b4obo219bo8bo13b2o4b3o2bo3bo6bobo265bob
\\o6bo3bo2b3o4b2o13bo8bo219bob4o39bo$462bobo37b2obobobo13bo130bo74b2o8b
\\3o10b2o3bo3b2o4bobo5b2o17bo229bo17b2o5bobo4b2o3bo3b2o10b3o8b2o74bo130b
\\o13bobobob2o37bobo$463b2o14b2o19bo4bobobob2o8b2o129b2o74bobo10bo15b4o
\\7b2o22b3o229b3o22b2o7b4o15bo10bobo74b2o129b2o8b2obobobo4bo19b2o14b2o$
\\479bo20b4ob2o2bo2bo9b2o129b2o86bob2o15bo20bo9bo235bo9bo20bo15b2obo86b
\\2o129b2o9bo2bo2b2ob4o20bo$456b2o22b3o21bo4b2o228b2obobo12b3o22b2o7b2o
\\233b2o7b2o22b3o12bobob2o228b2o4bo21b3o22b2o$455bobo5b2o17bo19bobo234bo
\\2bo13bo24b2o253b2o24bo13bo2bo234bobo19bo17b2o5bobo$455bo7b2o37b2o237b
\\2o14b5o295b5o14b2o237b2o37b2o7bo$454b2o291bo13bo37b2o217b2o37bo13bo
\\291b2o$747bobo9bo40bo217bo40bo9bobo$468bo278b2o10b2o17b2o20bob2o211b2o
\\bo20b2o17b2o10b2o278bo$464b2obobo308bo13b2o4b3o2bo211bo2b3o4b2o13bo
\\308bobob2o$463bobobobo309b3o10b2o3bo3b2o213b2o3bo3b2o10b3o309bobobobo$
\\460bo2bobobobob2o308bo15b4o217b4o15bo308b2obobobobo2bo$460b4ob2o2bo2bo
\\104bo203bob2o15bo217bo15b2obo203bo104bo2bo2b2ob4o$429b3o32bo4b2o106b3o
\\85b3o111b2obobo12b3o219b3o12bobob2o111b3o85b3o106b2o4bo32b3o$429bo32bo
\\bo115bo86bo111bo2bo13bo225bo13bo2bo111bo86bo115bobo32bo$430bo31b2o115b
\\2o85bo114b2o14b5o215b5o14b2o114bo85b2o115b2o31bo$801bo215bo$586bo174b
\\3o35bo219bo35b3o174bo$571b2o13bobo121b2o51bo35b2o217b2o35bo51b2o121bob
\\o13b2o$503bo67bo14b2o46bobo74b2o49bo293bo49b2o74bobo46b2o14bo67bo$503b
\\obo62b2obo62b2o74bo397bo74b2o62bob2o62bobo$503b2o63bo2b3o4b2o55bo147bo
\\251bo147bo55b2o4b3o2bo63b2o$569b2o3bo3b2o201b2o253b2o201b2o3bo3b2o$
\\521b2o48b4o207b2o251b2o207b4o48b2o$522bo48bo15b2o641b2o15bo48bo$520bo
\\51b3o12bobo2b2o631b2o2bobo12b3o51bo$520b5o14b2o34bo13bo2bo633bo2bo13bo
\\34b2o14b5o$525bo13bo30b5o14b3o2bo131bobo361bobo131bo2b3o14b5o30bo13bo$
\\522b3o12bobo30bo21b3o131b2o363b2o131b3o21bo30bobo12b3o$521bo15b2o33bo
\\18bo135bo363bo135bo18bo33b2o15bo$521b4o46b2o18b2o633b2o18b2o46b4o$519b
\\2o3bo3b2o759b2o3bo3b2o$518bo2b3o4b2o759b2o4b3o2bo$518b2obo67b2o54b3o
\\523b3o54b2o67bob2o$521bo66bo2bo55bo523bo55bo2bo66bo$521b2o64b2ob2o54bo
\\525bo54b2ob2o64b2o$588bobo637bobo$581b2o6bo639bo6b2o$529b2o49bobo32bo
\\587bo32bobo49b2o$530bo49bo33bo589bo33bo49bo$527b3o49b2o33b3o585b3o33b
\\2o49b3o$527bo763bo$593bo631bo$468bo10bo109b2obobo629bobob2o109bo10bo$
\\468b3o8bobo64b2o40bobobobo89b2o48b2o347b2o48b2o89bobobobo40b2o64bobo8b
\\3o$471bo7b2o65bobo36bo2bobobobob2o85bobo49b2o345b2o49bobo85b2obobobobo
\\2bo36bobo65b2o7bo$470b2o74bo38b4ob2o2bo2bo87bo48bo349bo48bo87bo2bo2b2o
\\b4o38bo74b2o$589bo4b2o110bobo401bobo110b2o4bo$587bobo116b2o403b2o116bo
\\bo$587b2o118bo403bo118b2o3$587bo643bo$480b2o105b3o35bo567bo35b3o105b2o
\\$473b2o5bobo107bo34b2o565b2o34bo107bobo5b2o$473b2o7bo106b2o33bobo565bo
\\bo33b2o106bo7b2o$482b2o851b2o2$469bo111b2o9bo633bo9b2o111bo$468bobob2o
\\107bo9b3o631b3o9bo107b2obobo$468bobobobo103b2obo8b5o148bobo327bobo148b
\\5o8bob2o103bobobobo$465b2obobobobo2bo100bo2b3o5b2o3b2o147b2o329b2o147b
\\2o3b2o5b3o2bo100bo2bobobobob2o$465bo2bo2b2ob4o101b2o3bo3b3o3b3o30bo
\\116bo329bo116bo30b3o3b3o3bo3b2o101b4ob2o2bo2bo$467b2o4bo107b4o4b2o3b3o
\\30b3o559b3o30b3o3b2o4b4o107bo4b2o$473bobo90b2o13bo8b5ob3o31bo33b3o47b
\\2o387b2o47b3o33bo31b3ob5o8bo13b2o90bobo$474b2o90bobo13b3o6b3o3bobo2b2o
\\25b2o35bo48b2o385b2o48bo35b2o25b2o2bobo3b3o6b3o13bobo90b2o$566bo18bo6b
\\o6bo2bo62bo48bo389bo48bo62bo2bo6bo6bo18bo$580b5o14b3o2bo609bo2b3o14b5o
\\$580bo21b3o16b2o573b2o16b3o21bo$582bo18bo19bo575bo19bo18bo$581b2o18b2o
\\15b2obo575bob2o15b2o18b2o$618bo2b3o4b2o2bobo549bobo2b2o4b3o2bo$606b2o
\\11b2o3bo3b2o2b2o551b2o2b2o3bo3b2o11b2o$607b2o12b4o8bo551bo8b4o12b2o$
\\606bo14bo15b2o541b2o15bo14bo$622b3o12bobo2b2o531b2o2bobo12b3o$625bo13b
\\o2bo533bo2bo13bo$591b2o27b5o14b3o2bo529bo2b3o14b5o27b2o$590bobo5b2o20b
\\o21b3o529b3o21bo20b2o5bobo$590bo7b2o22bo18bo535bo18bo22b2o7bo$589b2o
\\30b2o18b2o80bo371bo80b2o18b2o30b2o$722bo373bo$603bo118b3o369b3o118bo$
\\599b2obobo609bobob2o$598bobobobo39b3o525b3o39bobobobo$587b2o6bo2bobobo
\\bob2o38bo46b3o427b3o46bo38b2obobobobo2bo6b2o$586b2o7b4ob2o2bo2bo37bo
\\49bo427bo49bo37bo2bo2b2ob4o7b2o$588bo10bo4b2o25b2o61bo429bo61b2o25b2o
\\4bo10bo$597bobo30bobo5b2o539b2o5bobo30bobo$597b2o31bo8bo539bo8bo31b2o$
\\629b2o557b2o2$643bo531bo$639b2obobo529bobob2o$638bobobobo529bobobobo$
\\635bo2bo3bobob2o523b2obobo3bo2bo$635b4ob2o2bo2bo523bo2bo2b2ob4o$639bo
\\4b2o527b2o4bo$637bobo539bobo$637b2o541b2o$703bo411bo$702bo413bo$637bo
\\64b3o409b3o64bo$637b3o35b2o465b2o35b3o$640bo33bobo465bobo33bo$639b2o
\\35bo465bo35b2o2$647bo523bo$631b2o12b2o525b2o12b2o$631bo14b2o523b2o14bo
\\$628b2obo555bob2o$628bo2b3o4b2o539b2o4b3o2bo$614b2o13b2o3bo3b2o539b2o
\\3bo3b2o13b2o$614bobo14b4o549b4o14bobo$614bo16bo15b2o521b2o15bo16bo$
\\632b3o12bobo2b2o511b2o2bobo12b3o$635bo13bo2bo513bo2bo13bo$630b5o14b3o
\\2bo509bo2b3o14b5o$630bo21b3o509b3o21bo$632bo18bo515bo18bo$631b2o18b2o
\\513b2o18b2o2$656b3o501b3o$658bo501bo$657bo503bo3$641b2o533b2o$640bobo
\\5b2o519b2o5bobo$640bo7b2o519b2o7bo$639b2o537b2o2$634b2o17bo511bo17b2o$
\\634bobo12b2obobo509bobob2o12bobo$634bo13bobobobo509bobobobo13bo$645bo
\\2bobobobob2o503b2obobobobo2bo$645b4ob2o2bo2bo503bo2bo2b2ob4o$649bo4b2o
\\507b2o4bo$647bobo519bobo$647b2o521b2o2$651bo515bo$651b3o511b3o$654bo
\\509bo$653b2o509b2o3$655b2o505b2o$654bo2bo503bo2bo2$655b3o503b3o$663b2o
\\489b2o$663bobo487bobo$665bo487bo$665b2o485b2o2$652bo513bo$651bobob2o
\\505b2obobo$651bobobobo503bobobobo$648b2obobobobo2bo497bo2bobobobob2o$
\\648bo2bo2b2ob4o497b4ob2o2bo2bo$650b2o4bo505bo4b2o$656bobo501bobo$657b
\\2o501b2o!
;
