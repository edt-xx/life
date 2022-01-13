const std = @import("std");
//const tracy = @import("tracy");
const display = @import("zbox");
const build_options = @import("build_options");
                                                                           
// Author Ed Tomlinson (2021), released under the GPL V3 license.
//
// This program is an implementation of life as create by John H. Conway.  
//
// change the pattern to one of the included patterns and rebuild, 
//
// set the directory use for zbox in build.zig 
//
// update the pattern to animated and the number of threads to use in build.zig 
// 
// zig build -Drelease-fast run 
// or 
// zig build -Drelease-safe run  (about 10% slower) 
// or
// zig build -Drelease-fast -Dtarget=x86_64-linux-gnu -Dcpu=baseline   (generic linux build)
//
// zbox can be cloned from: https://github.com/jessrud/zbox.git
//
// generation 299198(2) population 77132(11719) births 3217 deaths 3228 rate 260/s  heap(8) 61286/16841  window(4) -11402,-11587 ±2048
//
// The title line tells us this is generation 200198 and the (2) that we are displaying every second generation ( see +, - )
// the population is 77132 cells with (11719) cells considered active (a birth or death near the cell in the last generation)
// birth and deaths as per the rules of life  
// generations per second.  If the rate is limited (see s, f) you will see rate> indicating we can run faster.
// we are using a heap size of 2^8 x 2^8 with 61286 entries and we need to check 16841 cells for the next generation.
// window(16) tells us we slowed down updating the display window's position by 16 times - causes the display jump around less (see [, ]).
// x,y the current display window origin
// ±n shows how wide an area is considered for autotracking.  To disable autotracking use the cursor keys (±0), to enable use (t or T).
//
// <, >        : limits the generation rate, < halves the rate and > doubles it (when limited you will see rate>xxx/s )
//
// +, -        : only show every nth generation.  + doubles n, - halves n (generation xxxx(n) ...)
//
// [, ]        : how fast the autotracking position can move, bigger is slower
//
// cursor keys : allow manual positioning of the window using cursor keys (±0)
//
// t,T         : if autotracking is disabled enabled it, if enabled decrease area monitored for tracking (t) or increase area (T) (±n). 
//
// w           : toggle window position and tracking.  Often patterns have two interesting areas.  This allows switching between them.
//
// esc, q      : will exit the program
//
// The algorithm used here was developed in the late 70s or early 80s.  I first implemented it on an OSI superboard II using 
// Basic and 6502 assembly.  This was before algorithms like hash life were discovered.  I've been using it when I want to learn a 
// new language environment.  This version was started to learn basic zig, then valgrind came into the picture and let me get a  
// better idea of how zig compiles and where the program was spending its time.  
//
// This algorithm is nothing special by todays standards, it does not use SIMD or the GPU for speed.  It does use threading when
// updating the display and for the generation update.  Its been a good learning tool.
//
// How it works.  We have an N x N array of pointers to cells.  The indexes to the array is a hash based on the x, y cords of the cell.
// Each cell has a pointer to another cell.  So we have a lists of cells where hash(x,y) are the same.  We size the array depending on how
// loaded it becomes, at near 100% ( eg. N x N is near 2^(N+N)) we increase N.  We use this structure to sum the effects of cells on each
// other.  We also track 4 x 4 areas ( eg hash(x|3, y|3)) flagging each area static if no births or deaths occur in the area.  Any cells
// in a static area survive into the next generation.  We still have to add the effect of these cell on any cell in an ajoining non 
// static area.  The effect of all this is to drasticly limit the number of cells we need to work with.  Once we finsh processing 
// the alive arraylist (processAlive), we start a thread to update the display and more to process the cells list (processCells) to 
// update the alive[] lists for the next generation.  To make being thread safe easier we keep alive[threads] lists of alive points.  
// ProcessCells in designed to be thread safe, and just as important, it balances the alive lists and updates the static 4x4 area flags
// when we find a birth or death.  It also gathers data to allow autotracking of activity. 
//
// The way the cells are added in AddCell and AddNear is interesting.  At the start of the process we record the cells head of list.
// If the cell does not exist in the list we try to add it.  In the multithreaded case, another thread may have already done this, 
// and will have updated the head of list,  the @cmpxchgStrong detects this, which case we just retry with the new head of list.  
// Typically this happen a few times per generation.  The process would also work with @cmpxchgWeak, but I do not see much, if any,
// differences in benchmarks.  (currently it uses Strong - speed is about the same might be using a little less CPU).
//
// Sometimes optimization is not at all obvious.  It is possibe to create a list of cells that might contain a birth or death while
// processing the alive lists.  This gives us a subset of cells to check usually containing 25-35% of cells.  Normally this would 
// help since scanning less is good.  However because we spend most of our time in processAlive in addCell and addNear the overhead 
// to track these cells actually ends up costing us 2-5%.  I used this optimization before the addition of the static cell logic.
// which reduces the number of cells to process by about 70-90%, that changed the balance so the checkList was no longer helping.
//
// What AtomicOrder is required?  I was pointed at: https://en.cppreference.com/w/c/atomic/memory_order
// which I've found to be a very good guide.  Using this it seems that for what we do here .Release will suffice as quoted below:
//
// Release sequence
// If some atomic is store-released and several other threads perform read-modify-write operations on that atomic, a 
// "release sequence" is formed: all threads that perform the read-modify-writes to the same atomic synchronize with the first thread
// and each other even if they have no memory_order_release semantics. This makes single producer - multiple consumers situations 
// possible without imposing unnecessary synchronization between individual consumer threads.
//
// set the pattern to run in ../build.zig

const pattern = build_options.pattern;          // get setting from build.zig
const Threads:MaxIndex = build_options.Threads; // Threads to use from build.zig
const staticSize = build_options.staticSize;    // static tiles are staticSize x staticSize.  Must be a power of 2.
const chunkSize = build_options.chunkSize;      // number of cells to use when balancing alive arrays.
const numChunks = build_options.numChunks;      // initial memory allocations for cells and alive[Threads] arrayLists
const origin = build_options.origin;            // number is so important, it position cells for middle squares to work well
const Coord = u32;                              // size of x & y coords
const MaxIndex = u32;                           // Maximum index usable in cells (limits population to about std.math.maxInt(maxIndex)/8)
const timeOut = std.math.maxInt(u64);           // Time out in ns for Futex wait

// with p_95_206_595mS on an i7-4770k at 3.5GHz (4 cores, 8 hyperthreads)
//
// Threads  gen         rate    cpu
// 1        100,000     440s    15%
// 2        100,000     430s    27%     using rmw in addCell and addNear seems to be the reason for this
// 3        100,000     540/s   37%
// 4        100,000     580/s   47%
// 5        100,100     640/s   57%
// 6        100,000     710/s   67%
// 7        100,000     830/s   75%
// 8        100,000     740/s   75%     The update threads + display thread > CPU threads so we take longer in processCells/displayUqpdate
//
// operf with 6 threads reports (anything over 1%):
//
//CPU: Intel Haswell microarchitecture, speed 4000 MHz (estimated)
//Counted CPU_CLK_UNHALTED events (Clock cycles when not halted) with a unit mask of 0x00 (No unit mask) count 100000
//samples  %        symbol name
//15881082 81.1178  processAlive
//3088177  15.7739  processCells
//479568    2.4495  worker

const print = std.debug.print;

fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    display.deinit();
    std.io.getStdOut().writeAll("\x1b[2J") catch {};
    std.io.getStdOut().writeAll("\x1b[H") catch {};
    std.builtin.default_panic(msg, error_return_trace);
}

const Point = packed struct {   // cell coords (packed so we can bitCast a Point to a u64)
    x: Coord align(16),
    y: Coord,
    
    const m = staticSize-1;
    
    const active = [_]@TypeOf(middle){lowerLeftA, lowerA, lowerRightA, leftA, middleA, rightA, topLeftA,  topA, topRightA};
//  const active = [_]@TypeOf(middle){other,      other,        other, other, middleA,  other,    other, other, other};         // try with small l2 cache
    const static = [_]@TypeOf(middle){lowerLeft,  lower,   lowerRight,  left,  middle,  right,  topLeft,   top, topRight};
//  const static = [_]@TypeOf(middle){other,      other,        other, other,  middle,  other,    other, other, other};
     
    const Self = @This();
    
    fn middle(_: *Self) void {
    }
      
    fn lower(p: *Self) void {      // .{ysc,  xs_,  xa2 }
        const list =  .{ysc,  .{xs_,  xa2 }};
        if (list[0](p)) {
           grid.addCell(p.*,1);
           inline for (list[1]) |next| {
                next(p);
                grid.addCell(p.*,1);
           }
        }
    }
    
    fn left(p: *Self) void {       // .{xsc,  ys_,  ya2 }
        const list = .{xsc,  .{ys_,  ya2 }};
        if (list[0](p)) {
           grid.addCell(p.*,1);
           inline for (list[1]) |next| {
                next(p);
                grid.addCell(p.*,1);
           }
        }     
    }   
    
    fn right(p: *Self) void {      // .{xac,  ys_,  ya2 }
        const list = .{xac,  .{ys_,  ya2 }};
        if (list[0](p)) {
           grid.addCell(p.*,1);
           inline for (list[1]) |next| {
                next(p);
                grid.addCell(p.*,1);
           }
        }       
    }
    
    fn top(p: *Self) void {        // .{yac,  xs_,  xa2 }
        const list = .{yac,  .{xs_,  xa2 }};
        if (list[0](p)) {
           grid.addCell(p.*,1);
           inline for (list[1]) |next| {
                next(p);
                grid.addCell(p.*,1);
           }
        }       
    }
    
    fn lowerLeft(p: *Self) void {
        inline for (.{ .{ysc, .{xa_}}, .{xs2c, .{}}, .{yac, .{ya_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } else 
                inline for (list[1]) |next| {
                    next(p);
                }
        }
    }
    
    fn lowerRight(p: *Self) void {
        inline for (.{ .{xac,  .{ya_}}, .{ys2c, .{}}, .{xsc, .{xs_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } else 
                inline for (list[1]) |next| {
                    next(p);
                }
        }
    }
    
    fn topLeft(p: *Self) void {
        inline for (.{ .{xsc, .{ys_}}, .{ya2c, .{}}, .{xac, .{xa_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } else 
                inline for (list[1]) |next| {
                    next(p);
                }
        }
    }
    
    fn topRight(p: *Self) void {
        inline for (.{ .{yac, .{xs_}}, .{xa2c, .{}}, .{ysc, .{ys_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } else 
                inline for (list[1]) |next| {
                    next(p);
                }
        }
    }
    
    // const mA  = [_]vec{xa_, ya_, xs_, xs_, ys_, ys_, xa_, xa_ };
    fn middleA(p: *Self) void {
        inline for (.{xa_, ya_, xs_, xs_, ys_, ys_, xa_, xa_ }) |next| {
            next(p);
            grid.addCell(p.*,1);
        }            
    }
    
     // const mA  = [_]vec{xa_, ya_, xs_, xs_, ys_, ys_, xa_, xa_ };
    fn other(p: *Self) void {
        inline for (.{xa_, ya_, xs_, xs_, ys_, ys_, xa_, xa_ }) |next| {
            next(p);
            if (grid.active[grid.index(p.x|m, p.y|m)])
                grid.addCell(p.*,1);
        }            
    }
    
    // const bA  = [_]vec{xst, ya_, xa_, xa_, ys_, ysc, xs_, xs_ }; 
    fn lowerA(p: *Self) void {
        inline for ( .{ .{xst, .{ya_, xa_, xa_, ys_}}, .{ysc, .{xs_, xs_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } 
        }
    } 
    
    // const lA  = [_]vec{yat, xa_, ys_, ys_, xs_, xsc, ya_, ya_ }; 
    fn leftA(p: *Self) void {
        inline for ( .{ .{yat, .{xa_, ys_, ys_, xs_}}, .{xsc, .{ya_, ya_ }} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } 
        }
    } 
    
    // const rA  = [_]vec{yst, xs_, ya_, ya_, xa_, xac, ys_, ys_ };
    fn rightA(p: *Self) void {
        inline for ( .{ .{yst, .{xs_, ya_, ya_, xa_}}, .{xac, .{ys_, ys_ }} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } 
        }
    } 
 
    // const tA  = [_]vec{xst, ys_, xa_, xa_, ya_, yac, xs_, xs_ }; 
    fn topA(p: *Self) void {
        inline for ( .{ .{xst, .{ys_, xa_, xa_, ya_}}, .{yac, .{xs_, xs_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } 
        }
    }
    
    // const blA = [_]vec{yat, xa_, ys_, ysc, xs_, xsc, yac, ya_ }; 
    fn lowerLeftA(p: *Self) void {
        inline for (.{ .{yat, .{xa_, ys_}}, .{ysc, .{xs_}}, .{xsc, .{}}, .{yac, .{ya_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } else {
                inline for (list[1]) |next| {
                    next(p);
                }
            }
        }
    }
    
    // const brA = [_]vec{xst, ya_, xa_, xac, ys_, ysc, xsc, xs_ };
    fn lowerRightA(p: *Self) void {
        inline for (.{ .{xst, .{ya_, xa_}}, .{xac, .{ys_}}, .{ysc, .{}}, .{xsc, .{xs_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } else {
                inline for (list[1]) |next| {
                    next(p);
                }
            }
        }
    }
 
    // const tlA = [_]vec{xat, ys_, xs_, xsc, ya_, yac, xac, xa_ };
    fn topLeftA(p: *Self) void {
        inline for (.{ .{xat, .{ys_, xs_}}, .{xsc, .{ya_}}, .{yac, .{}}, .{xac, .{xa_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } else {
                inline for (list[1]) |next| {
                    next(p);
                }
            }
        }
    }
 
    // const trA = [_]vec{yst, xs_, ya_, yac, ya_, yac, xsc, xs_ };
    fn topRightA(p: *Self) void {
        inline for (.{ .{yst, .{xs_, ya_}}, .{yac, .{xa_}}, .{xac, .{}}, .{ysc, .{ys_}} }) |list| {
            if (list[0](p)) {
               grid.addCell(p.*,1);
               inline for (list[1]) |next| {
                    next(p);
                    grid.addCell(p.*,1);
               }
            } else {
                inline for (list[1]) |next| {
                    next(p);
                }
            }
        }
    }
        
    fn xa_(p: *Self) callconv(.Inline) void {
        p.x +%= 1;   
    } 

    fn xat(p: *Self) callconv(.Inline) bool {
        p.x +%= 1;
        return true;
    } 
    
    fn xac(p: *Self) callconv(.Inline) bool { 
        p.x +%= 1;
        return grid.active[grid.index(p.x|m, p.y|m)];
    }  

    fn xa2(p: *Self) callconv(.Inline) void {            
        p.x +%= 2;   
    }  

    fn xa2c(p: *Self) callconv(.Inline) bool {            
        p.x +%= 2;     
        return grid.active[grid.index(p.x|m, p.y|m)];
    }  

    fn xs_(p: *Self) callconv(.Inline) void { 
        p.x -%= 1;
    }

    fn xst(p: *Self) callconv(.Inline) bool { 
        p.x -%= 1;
        return true;
    }
    
    fn xsc(p: *Self) callconv(.Inline) bool { 
        p.x -%= 1;
        return grid.active[grid.index(p.x|m, p.y|m)];
    }  

    fn xs2c(p: *Self) callconv(.Inline) bool { 
        p.x -%= 2;
        return grid.active[grid.index(p.x|m, p.y|m)];
    }  

    fn ya_(p: *Self) callconv(.Inline) void { 
        p.y +%= 1;
    }

    fn yat(p: *Self) callconv(.Inline) bool { 
        p.y +%= 1;
        return true;
    }

    fn yac(p: *Self) callconv(.Inline) bool {
        p.y +%= 1;
        return grid.active[grid.index(p.x|m, p.y|m)];
    } 

    fn ya2(p: *Self) callconv(.Inline) void { 
        p.y +%= 2;
    }

    fn ya2c(p: *Self) callconv(.Inline) bool {
        p.y +%= 2;
        return grid.active[grid.index(p.x|m, p.y|m)];
    } 

    fn ys_(p: *Self) callconv(.Inline) void {
        p.y -%= 1;
    }  

    fn yst(p: *Self) callconv(.Inline) bool {
        p.y -%= 1;
        return true;
    } 
    
    fn ysc(p: *Self) callconv(.Inline) bool {
        p.y -%= 1;
        return grid.active[grid.index(p.x|m, p.y|m)];
    } 

    fn ys2c(p: *Self) callconv(.Inline) bool {
        p.y -%= 2;
        return grid.active[grid.index(p.x|m, p.y|m)];
    } 
    
};


//    // const mA  = [_]vec{xa_, ya_, xs_, xs_, ys_, ys_, xa_, xa_ };
//    // const bA  = [_]vec{xs_, ya_, xa_, xa_, ys_, ysc, xs_, xs_ };                      
//    // const lA  = [_]vec{ya_, xa_, ys_, ys_, xs_, xsc, ya_, ya_ };              
//    // const rA  = [_]vec{ys_, xs_, ya_, ya_, xa_, xac, ys_, ys_ };  
//    // const tA  = [_]vec{xs_, ys_, xa_, xa_, ya_, yac, xs_, xs_ };  
//    // const blA = [_]vec{ya_, xa_, ys_, ysc, xs_, xsc, yac, ya_ }; 
//    // const brA = [_]vec{xs_, ya_, xa_, xac, ys_, ysc, xsc, xs_ };
//    // const tlA = [_]vec{xa_, ys_, xs_, xsc, ya_, yac, xac, xa_ };
//    // const trA = [_]vec{ys_, xs_, ya_, yac, ya_, yac, xsc, xs_ };
//                 
//    //const mI = [_]vec{};                                                 // skip (25% of a 4x4 area)
//    //const bI  = [_]vec{ysc,  xs_,  xa2 };                                // 1 test, three checks (12.5% or 4x4 area)
//    //const lI  = [_]vec{xsc,  ys_,  ya2 };                                // 1 test, three checks (12.5% or 4x4 area)
//    //const rI  = [_]vec{xac,  ys_,  ya2 };                                // 1 test, three checks (12.5% or 4x4 area)
//    //const tI  = [_]vec{yac,  xs_,  xa2 };                                // 1 test, three checks (12.5% or 4x4 area)
//    //const blI = [_]vec{ysc,  xa_,  xs2c, yac,  ya_ };                    // 3 tests, 5 checks (6.25% of 4x4 area)  
//    //const brI = [_]vec{xac,  ya_,  ys2c, xsc,  xs_ };                    // 3 tests, 5 checks (6.25% of 4x4 area)
//    //const tlI = [_]vec{xsc,  ys_,  ya2c, xac,  xa_ };                    // 3 tests, 5 checks (6.25% of 4x4 area)
//    //const trI = [_]vec{yac,  xs_,  xa2c, ysc,  ys_ };                    // 3 tests, 5 checks (6.25% of 4x4 area)


const Cell = packed struct {    
    p: Point,                   // point for this cell
    n: MaxIndex,                // index for the next cell in the same hash chain (index is faster than using pointers)
    v: u8,                      // cells value
};

var theSize:usize = 0;
                 
const Hash = struct {
    hash: []MaxIndex,           // pointers into the cells arraylist (2^order x 2^order hash table)
    active: []bool,             // flag if 4x4 area is static
//    mask:u32,
    order:u5,                   // hash size is 2^(order+order), u5 for << and >> with usize and a var
    shift:u5,                   // avoid a subtraction in index 
       
    fn init(size:usize) !Hash {
                    
// log2 of the population from the last iteration.  The ammount of memory used is a tradeoff
// between the length of the hash/heap chains and the time taken to clear the hash array.
        
        if (size < theSize/2 or size > theSize)             // reduce order bouncing and (re)allocates
            theSize = size;
        
        const o = @intCast(u5,std.math.clamp(31-@clz(@TypeOf(theSize),theSize+1)/2+1, 6, 12));
        
        return Hash{ .hash=undefined, 
                     .active=undefined,
//                     .mask=(@as(u32,1)<<o)-1,
                     .order = o, 
                     .shift = @intCast(u5,31-o+1),          // 32-o fails with a comiplier error...  
                   };        
    }
    
    fn assign(self:*Hash,s:Hash) !void {
        if (self.order != s.order) {
            self.order = s.order;
            self.shift = s.shift;
//            self.mask = s.mask;
            allocator.free(self.hash);
            self.hash = try allocator.alloc(MaxIndex,@as(u32,1)<<2*self.order);
        }
        // clear the hash table pointers
        
        // from valgrind, only @memset is using the os memset call
        // for (self.hash) |*c| c.* = null;                
        // std.mem.set(?*Cell,self.hash,null);
        @memset(@ptrCast([*]u8,self.hash),0,@sizeOf(MaxIndex)*@as(u32,1)<<2*self.order);
        self.active = s.active;
    }
    
    fn takeStatic(self:*Hash,s:*Hash) !void { 
        if (self.order != s.order) {
            allocator.free(s.active);            
            s.active = try allocator.alloc(bool,@as(u32,1)<<2*self.order); // this is accessed via hashing so making it smaller 
        }                                                                  // causes more collision and its slower
        self.active = s.active;
        // mark all tiles as static to start
        // from valgrind, only @memset uses the os memset
        // for (self.active) |*t| t.* = false;           
        // std.mem.set(bool,self.active,false);
        @memset(@ptrCast([*]u8,self.active),0,@sizeOf(bool)*@as(u32,1)<<2*self.order);
    }
      
    fn deinit(self:Hash) void {
        allocator.free(self.hash);
        allocator.free(self.active);
    }
     
    // Collisions are ignored here, more tiles will be flagged as active which is okay
    fn setActive(self:*Hash,p:Point) callconv(.Inline) void {   
    
         //const ttt = tracy.trace(@src());
         //defer ttt.end();
         
         const i = staticSize;                                  // global is not faster, must be 2^N
         const m:Coord = staticSize-1;                          // 2^N-1 is a binary mask of N ones.
         //const mask = @bitCast(u64,Point{.x=m, .y=m});
         //const t = @bitCast(Point,@bitCast(u64,p)|mask);
         //const a = @bitCast(Point,@bitCast(u64,p)&mask);
        
         var t = Point{.x=p.x|m, .y=p.y|m};                     // using a const for t and var tx=t.x, ty=t.y is slower
                                                                // using masks instead of shifting is also faster         
         const x = p.x & m;                  
         const y = p.y & m;   // 4x4 tiles are optimal, 2x2 and 8x8 also work but not as well      

         self.active[self.index(t.x, t.y)] = true;
         
         if (x==m         ) self.active[self.index(t.x+%i, t.y   )] = true;     // faster than iterating around the point
         if (x==m and y==m) self.active[self.index(t.x+%i, t.y+%i)] = true;     // as we do with the Area struct
         if (         y==m) self.active[self.index(t.x   , t.y+%i)] = true;
         if (x==0 and y==m) self.active[self.index(t.x-%i, t.y+%i)] = true;
         if (x==0         ) self.active[self.index(t.x-%i, t.y   )] = true;
         if (x==0 and y==0) self.active[self.index(t.x-%i, t.y-%i)] = true;
         if (         y==0) self.active[self.index(t.x   , t.y-%i)] = true;
         if (x==m and y==0) self.active[self.index(t.x+%i, t.y-%i)] = true;
   }              

// use the middle bits of the square of the coord to create the index.  No need
// to add a seed since this is not used for a sequence (see: Middle Square Weyl)
// valgrind shows the low 32bits of the 64bit product is saved.  So we use the
// high bits from the 32bits to generate the index.  
 
// passing x, y instead of a point lets the compiler generate beter code (~25% faster) and speed counts here

    fn index(self:Hash, x:u32, y:u32) callconv(.Inline) u32 {   // faster than bitCast a point to u64 and hashing with that
        return (( x*%x >> self.shift) ^                         
                ( y*%y >> self.shift << self.order)); 
    } 
    
//  fn index(self:Hash, x:u32, y:u32) callconv(.Inline) u32 {   // only use if there is no hw multiply
//      return (( x & self.mask) ^                         
//              ( y & self.mask << self.order)); 
//  }  
    
// find a Cell in the heap and increment its value, if not known, link it in and set its initial value
 
    //fn addCell(self:*Hash, p:Point, v:u8) callconv(.Inline) void {
    fn addCell(self:*Hash, p:Point, v:u8) void {
    
        //const ttt = tracy.trace(@src());
        //defer ttt.end();
        
        const h = &self.hash[self.index(p.x, p.y)];     // zig does not have 2D dynamic arrays so we fake it... 
                                                        // (using const x=p.x etc is no faster)
        var i:MaxIndex = h.*;                           // index of the current Cell, 0 implies EOL
            
        while (true) {                                  // loop until we have added or updated the cell
            
            const head = i;                             // save index at the head of the hash chain (h), for linking & retries
        
            while (i!=0) {                              // using an index is faster (and smaller) than using pointers
                const c = &cells.items[i];                 
                if (@bitCast(u64,p) == @bitCast(u64,c.p)) {     // is this our target cell? (@bitCast(u64... is faster)
                    if (Threads == 1)
                        c.v += v                        // add value to existing cell
                    else
                        _ = @atomicRmw(u8,&c.v,.Add,v,.Monotonic);
                    return;
                }
                i = c.n;
            }
            cells.items[iCells] = Cell{.p=p, .n=head, .v=v};    // cell not in heap, add it.  Note iCells is threadlocal.
            if (Threads == 1) {
                h.* = iCells;                                                                   // link to head of list
                iCells += Threads;                                                              // commit the cell
                std.debug.assert(iCells < cells.capacity);
                return;
            } else {
                i = @cmpxchgStrong(MaxIndex, h, head, iCells, .Release, .Monotonic) orelse {    // weak not measurabily faster                               
                    iCells += Threads;                                                          // commit the cell
                    std.debug.assert(iCells < cells.capacity);
                    return;
                };
            }
        }
    }
    
};

var screen:*display.Buffer = undefined;

var cbx:u32 = undefined;                                     // starting center of activity 
var cby:u32 = undefined;                                     
var cbx_:u32 = undefined;                                    // alternate center of activity (toggle with w) 
var cby_:u32 = undefined;                                    
                                                             
var xl:u32 = origin;                                         // window at origin to start, size to be set
var xh:u32 = 0;                                              
var yl:u32 = origin;                                         
var yh:u32 = 0;                                              
                                                             
const Track = 11;                                            // ±262144k to ±256
                                                             
var dx:i32 = 0;                                              // used to track activity for autotracking
var ix:i32 = 0;                                              
var dy:i32 = 0;                                              
var iy:i32 = 0;                                              
                                                             
var tg:isize = 1;                                            // generations for autotracking, if negitive it is disabled
var tg_:isize = 1;                                           // alternate toggle (for w command)
var zn:usize = 0;                                            // generation of next display window switch
                                                             
var b:u32 = 0;                                               // births and deaths
var d:u32 = 0;    
    
var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
const allocator = gpa.allocator();

//const allocator = std.heap.c_allocator;

var alive = [_]std.ArrayList(Point){undefined} ** Threads;   // alive cells, static cell stay in this list       

var cells = std.ArrayList(Cell).init(allocator);             // could be part of Hash structure, deallocation is easier this way

var grid:Hash = undefined;                                   // hash containing cells and the static tiles mask array
var newgrid:Hash = undefined;                                // what will be come the next grid hash
                
var cellsLen=[_]u32{undefined} ** Threads;                   // array to record iCells values when exiting threads

var work = std.atomic.Atomic(u32).init(1);                   // threads waiting to start working wait here
var fini = std.atomic.Atomic(u32).init(1);                   // thread done working wait here

var ready = std.atomic.Atomic(u32).init(1);                  // used to notify main thread when all worker threads are ready
var done = std.atomic.Atomic(u32).init(1);                   // used to notify main thread when all worker threads are done

var working = std.atomic.Atomic(u32).init(0);                // active worker threads

var checking = processAlive;                                 // controls what processing is done by worker threads

var going:bool = true;                                       // false when quitting

var disp = std.atomic.Atomic(u32).init(1);                   // used to notify display thread to start
var pushing:?*display.Buffer = null;                         // buffer to push or null

threadlocal var iCells:MaxIndex = undefined;                 // index to cells thead partitionthreadlocal var flag:bool = undefined;

var cellsMax:u32 = 0;                                        // largest length of the cellLen subarrays
var staticMax:u32 = 0;

pub fn pushScreen() void {                                   // Thread for display (lazy) updates

    //const ttt = tracy.trace(@src());
    //defer ttt.end();  
    
    while (going) { 
        pushing = null;                                               // tell main loop we are ready to display
        
        std.Thread.Futex.wait(&disp,1,timeOut) catch unreachable;     // wait for main thread to wake us
        disp.store(1,.Release);
        
        if (pushing) |pushIt|                                // main loop sets pushing with the buffer to push to the display
            display.push(pushIt.*) catch unreachable;
    }
} 

pub fn worker(t:MaxIndex) void {                            // worker threads for generation updates use this function
 
    while (going) {                                             
                                                              
        if (working.fetchAdd(1, .AcqRel) == Threads-1) {    // notify main thread when all workers are ready
            ready.store(0, .Release);
            std.Thread.Futex.wake(&ready,1);
        }
        std.Thread.Futex.wait(&work,1,timeOut) catch unreachable;  // wait for main thread to wake us

        if (going) checking(t);                              // call worker function
                                                              
        if (working.fetchSub(1, .AcqRel) == 1) {             // notify main thead when workers are all doen
            done.store(0, .Release);
            std.Thread.Futex.wake(&done,1);
        }
        std.Thread.Futex.wait(&fini,1,timeOut) catch unreachable;  // wait for main thread to wake us
    }
}

pub fn processAlive(t:MaxIndex) void {          // process cells in alive[t] adding to cells 

    //const ttt = tracy.trace(@src());
    //defer ttt.end();
    
    const yw = [_]u8{0} ++ ([_]u8{3}**(staticSize-2)) ++ [_]u8{6};
    const xw = [_]u8{0} ++ ([_]u8{1}**(staticSize-2)) ++ [_]u8{2};
                                                                                                          
    const list = &alive[t];                     // extacting x and y and using them does not add more speed here
    const m = staticSize-1;
    
    iCells = if (t!=0) t else Threads;          // Zero indicates a EOL.  Threadlocal var, we trade memory for thread safey 
                                                // and speed treating the arrayList as a group of dynamic arrays.
    var i:u32 = 0;

    while (i < list.items.len) {                // add cells to the hash to enable next generation calculation
            
        var p = list.items[i];                  // add point to surrounding area
        
        // if cell is within the display window update the screen buffer        
        if (p.y > yl and p.y <= yh and p.x >= xl and p.x <= xh) {   // p.y > yl to avoid writing on the status line
            screen.cellRef(p.y-yl, p.x-xl).char = 'O';
        }
      
        const x = p.x&m;
        const y = p.y&m;      
      
        if (grid.active[grid.index(p.x|m, p.y|m)]) {        // active flag
                                                            
            list.items[i] = list.items[list.items.len-1];   // swap and remove last item ( optimized list.swapRemove(i); )
            list.items.len -= 1;
            
            grid.addCell(p,10);                             // add the effects of the cell

            //Point.otherA(&p);
            Point.active[yw[y]+xw[x]](&p);

        } else {
        
            i += 1;                                         // keep static cells in alive list - they are stable, but may have effects 
            
            Point.static[yw[y]+xw[x]](&p);
            
        }
    }     
    cellsLen[t] = iCells;                                   // save the size of the cell partition for this thread
}
    
pub fn processCells(t:MaxIndex) void {     // gets called in threaded mode when checkMax exceed the cellsThreading threshold

    //const ttt = tracy.trace(@src());
    //defer ttt.end();
            
    alive[t].ensureTotalCapacity(staticMax+cellsMax/Threads/2) catch unreachable;

    const sub:u32 = @as(u32,0b00001000_00000000_00000000) >> @intCast(u5,std.math.absCast(tg));  // 2^20 shifted by abs(tg), larger tg smaller area. 
    
    var _ix:i32 = 0;    // use local copies so tracking works (the updates can race and, if it happens too often, tracking fails)
    var _iy:i32 = 0;
    var _dx:i32 = 0;
    var _dy:i32 = 0;    
        
    var k:u32 = t;                      // thread to use for this chunk (think of cells as 2D [Threads,m] with m different for each thread)
    var i:u32 = k;                      // thread index into cells, used to loop through a chunk's cells for a given thread [k,i], [k,i+Threads...]
    var l:u32 = Threads;                // number of chunks running (m exceeded) for k(th) thread
    var p:u32 = Threads*chunkSize;      // start of next chunk [0, Threads*chunkSize*n] where n is 0,1,2,...
    var h=[_]bool{false} ** Threads;    // true when thread's partition is finished (count once...)
    
    while (l > 0) : ({ k = (k+1)%Threads; i = p+k; p += Threads*chunkSize; }) {        
        if (h[k]) 
            continue;
        while (i < p) : (i += Threads) {
            if (i>=cellsLen[k]) {
                l -= 1;
                h[k] = true;
                break;
            }
            const c = cells.items[i];
            if (c.v < 10) {                           
                if (c.v == 3) { 
                    std.debug.assert(alive[t].items.len < alive[t].capacity);
                    
                    alive[t].appendAssumeCapacity(c.p);             // birth so add to alive list & flag tile(s) as active
                    newgrid.setActive(c.p);       
                    if (c.p.x > cbx) {
                        const tmp = c.p.x-cbx;
                        if (tmp < sub and tmp > 0)                  // tmp>0 so stable patterns do not drift with autotracking
                            _ix +=  @intCast(i32,@clz(u32,tmp));
                    } else {
                        const tmp = cbx-c.p.x;
                        if (tmp < sub and tmp > 0) 
                            _dx +=  @intCast(i32,@clz(u32,tmp));
                    }
                    if (c.p.y > cby) {
                        const tmp = c.p.y-cby;
                        if (tmp < sub and tmp > 0) 
                            _iy +=  @intCast(i32,@clz(u32,tmp));
                    } else {
                        const tmp = cby-c.p.y;
                        if (tmp < sub and tmp > 0) 
                            _dy +=  @intCast(i32,@clz(u32,tmp));
                    }
                    b += 1;                                                     // can race, not critical 
                }
            } else
                if (c.v == 12 or c.v == 13) {                                   // active cell that survives
                    std.debug.assert(alive[t].items.len < alive[t].capacity);
                    alive[t].appendAssumeCapacity(c.p);
                } else {
                    newgrid.setActive(c.p);                             
                    if (c.p.x > cbx) {
                        const tmp = c.p.x-cbx;
                        if (tmp < sub and tmp > 0) 
                            _ix -=  @intCast(i32,@clz(u32,tmp));
                    } else {
                        const tmp = cbx-c.p.x;
                        if (tmp < sub and tmp > 0) 
                            _dx -=  @intCast(i32,@clz(u32,tmp));
                    }
                    if (c.p.y > cby) {
                        const tmp = c.p.y-cby;
                        if (tmp < sub and tmp > 0) 
                            _iy -=  @intCast(i32,@clz(u32,tmp));
                    } else {
                        const tmp = cby-c.p.y;
                        if (tmp < sub and tmp > 0) 
                            _dy -=  @intCast(i32,@clz(u32,tmp));
                    }
                    d += 1;                                                     // can race, not critical 
                }            
        }
    }
    ix += _ix;            // if this races once in a blue moon its okay
    iy += _iy;
    dx += _dx;
    dy += _dy;
}

// pub fn ReturnOf(comptime func: anytype) type {
//     return switch (@typeInfo(@TypeOf(func))) {
//         .Fn, .BoundFn => |fn_info| fn_info.return_type.?,
//         else => unreachable,
//     };
// }

pub fn main() !void {
    
    var t:MaxIndex = 0;                     // used for iterating up to Threads
    
    while (t<Threads) : ( t+=1 ) {
        alive[t] = std.ArrayList(Point).init(allocator);
        defer alive[t].deinit();                            
    }                                       // make sure to cleanup the arrayList(s)
                  
    defer cells.deinit();
    try cells.ensureTotalCapacity((8+Threads)*chunkSize*numChunks);
    
    defer grid.deinit();                    // this also cleans up newgrid's storage
    
    //const stdout = std.io.getStdOut().writer();
    
    try display.init(allocator);            // setup zbox display
    defer display.deinit();
    errdefer  display.deinit();
    try display.setTimeout(0);              // do not wait for keypresses
 
    try display.handleSignalInput();
 
    try display.cursorHide();               // hide the cursor
    defer display.cursorShow() catch {};
    errdefer display.cursorShow() catch {};
    
    try display.clear();                    // be sure to start with a clean display
 
    var size = try display.size();
 
    var cols:u32 = @intCast(u32,size.width);
    var rows:u32 = @intCast(u32,size.height);
    
    var s0 = try display.Buffer.init(allocator, size.height, size.width);
    defer s0.deinit();
    var s1 = try display.Buffer.init(allocator, size.height, size.width);
    defer s1.deinit(); 
   
    var gen: u32 = 0;           // generation
    var pop:u32 = 0;            // poputlation
    var static:u32 = 0;         // static cells                        
    
// rle pattern decoding 
    
    var X:Coord = origin;
    var Y:Coord = origin;
    var count:Coord = 0;
    t = 0;
    for (pattern) |c| {
        switch (c) {
            'b' => {if (count==0) {X+=1;} else {X+=count; count=0;}},
            'o' => {
                        if (count==0) count=1;
                        while (count>0):(count-=1) {
                            if (Threads != 1) {
                                if (alive[t].items.len & 0xf == 0) {
                                    t = if (t<Threads-1) t+1 else 0; 
                                }
                            }
                            try alive[t].append(Point{.x=X, .y=Y}); X+=1; pop+=1; 
                        }
                    },
      '0'...'9' => {count=count*10+(c-'0');},
            '$' => {X=origin; if (count==0) {Y+=1;} else {Y+=count; count=0;}},
            '!' => {break;},
          else  => {},
        }
        if (X>xh) xh=X;
    }
    yh=Y;
    
// set initial display window
    
    var s:u32 = 0;                                  // update display even 2^s generations        
    var inc:u32 = 20;                               // max ammount to move the display window at a time
    
    cbx = (xh-origin)/2+origin;                     // starting center of activity 
    cby = (yh-origin)/2+origin;
    cbx_ = cbx;                                     // and the alternate (for w command)
    cby_ = cby;
    
    xl = cbx - cols/2;                              // starting display window
    xh = xl + cols - 1;  
    yl = cby - rows/2; 
    yh = yl + rows - 1;
    var yl_:u32 = yl;                               // saved yl, used to optimize screen updated
    
    screen = &s0;                                   // starting buffer
    screen.clear();
            
// initial grid. The cells arrayList is sized so it will not grow during a calcuation so pointers are stable                                                                                                    

    grid = try Hash.init(9*pop);                    // this sets the order of the Hash (no allocations are done)
    grid.hash = try allocator.alloc(MaxIndex,1);    // initialize with dummy allocations for .takeStatic and .assign to free
    grid.active = try allocator.alloc(bool,1);  
    
    newgrid = try Hash.init(9*pop);                 // set the order for the generation
    
    grid.order = 0;                                 // this forces grid.assign & newgrid.takeStatic to reallocate storage for hash and static.    
    try newgrid.takeStatic(&grid);
    
    t = 0;
    while (t<Threads) : ( t+=1 ) {                  // for all threads   
        for (alive[t].items) |p|                    // set all tiles active for the first generation
            { newgrid.setActive(p); }   
        try alive[t].ensureTotalCapacity(chunkSize*numChunks);
    }
    b = @intCast(u32,pop);                          // everything is a birth at the start
    
    var ogen:u32 = 0;                               // info for rate calculations
    var rate:usize = 1;
    var rtime:i64 = std.time.milliTimestamp()+1_000;
    var rk:f32 = 0;
    var pk:f32 = 0;
    var r10k:f32 = 0;
    var limit:usize = 65536;                        // optimistic rate limit
    var sRate:usize = 1;
    var sRate_ = sRate;
    var delay:usize = 0;
           
    t = 0;                                              
    while (t<Threads) : ( t+=1 ) {                            // start the workers
        const h = try std.Thread.spawn(.{},worker,.{t});         
        h.detach();                                           // or h.join() to wait
    }
    
    {
        const h = try std.Thread.spawn(.{},pushScreen,.{});   // start display thread
        h.detach();
    }
 
// main event/life loop  
   
     while (going) {
                  
        //var i:u32 = 0;                                       // var for loops
        
        try grid.assign(newgrid);                            // assign newgrid to grid (if order changes reallocate hash storage)
        
        cells.clearRetainingCapacity();                      // will help when resizing an empty arrayList avoids a mem.copy
        try cells.ensureTotalCapacity((pop-static)*(8+Threads));  
        cells.expandToCapacity();                            // arrayList length to max

// populate hash & heap from alive lists
        
        pop = Threads;                                       // sum to get the population
        t = 0;                                          
        while (t<Threads) : ( t+=1 ) {
            pop += @intCast(u32,alive[t].items.len);
        }
            
        checking = processAlive;                             // tell workers to use processAlive
                                                            
        std.Thread.Futex.wait(&ready,1,timeOut) catch unreachable;   // wait for workers to be ready
        ready.store(1,.Release);                                     // enable waits at ready (worker disables them before waking this thread)
        
                                                             // start the workers.
        fini.store(1,.Release);                              // enable waits on fini, 
        work.store(0,.Release);                              // disable new waits on work & 
        std.Thread.Futex.wake(&work,Threads+1);              // wake all workers waiting on work
         
        {                                                    
            const e = (try display.nextEvent()).?;           // get and process any user input
            switch (e) {
                .up     => { cby += inc; zn=gen; if (tg>0) tg = -tg; },  // manually position the display window
                .down   => { cby -= inc; zn=gen; if (tg>0) tg = -tg; },
                .left   => { cbx += inc; zn=gen; if (tg>0) tg = -tg; },
                .right  => { cbx -= inc; zn=gen; if (tg>0) tg = -tg; },
                .escape => { going=false; },                       
                .other => |data| { 
                                    const eql = std.mem.eql;
                                    if (eql(u8,"t",data) or eql(u8,"T",data)) {
                                        if (tg>0) {
                                            tg += if (eql(u8,"T",data)) @as(i32,-1) else 1;
                                            tg = if (tg > Track) Track else if (tg == 0) 1 else tg;
                                        } else 
                                            tg = -tg; 
                                    } 
                                    if (eql(u8,"<",data)) limit = if (limit>1) limit/2 else limit;        // limit generation rate
                                    if (eql(u8,">",data)) limit = if (limit<16384) limit*2 else limit;
                                    if (eql(u8,"[",data)) sRate = if (sRate>1) sRate/2 else sRate;        // how fast screen window moves
                                    if (eql(u8,"]",data)) sRate = if (sRate<64) sRate*2 else sRate;
                                    if (eql(u8,"w",data)) { const t1=cbx; cbx=cbx_; cbx_=t1;              // toggle active window
                                                            const t2=cby; cby=cby_; cby_=t2; 
                                                            const t3=tg;  tg=tg_;   tg_=t3;
                                                            const t4=sRate; sRate=sRate_; sRate_=t4;
                                                            zn = gen;
                                                        } 
                                    if (eql(u8,"+",data)) s += 1;                                         // update every 2^s generation
                                    if (eql(u8,"-",data)) s = if (s>0) s-1 else s;
                                    if (eql(u8,"q",data) or eql(u8,"Q",data)) { going=false; }     
                                },
                else => {},
            }
            
        }
                                                            
        std.Thread.Futex.wait(&done,1,timeOut) catch unreachable;   // wait till all workers are done
        done.store(1,.Release);                                     // enable waits at done (worker disables them before waking this thread)
        
        work.store(1,.Release);                             // tell workers to enter ready state
        fini.store(0,.Release);
        std.Thread.Futex.wake(&fini,Threads+1);
        
        yl = yl_;                                           // restore saved yl (can be used to stop screen updates)
        
        if (!going) {
            work.store(0,.Release);                         // unblock work and wake anything waiting so they can finish cleanly
            std.Thread.Futex.wake(&work,Threads+1);
            if (pushing==null) {
                disp.store(0,.Release);
                std.Thread.Futex.wake(&disp,1);             // make sure display thread also ends
            }
            return;  
        }
                
        // gather stats needed for display and sizing cells, check and alive[] arrayLists
        cellsMax = 0;
        static = 0;
        staticMax = 0;        
        t = 0;                                          
        while (t<Threads) : ( t+=1 ) {  
            static += @intCast(u32,alive[t].items.len);                             
            staticMax = std.math.max(staticMax,@intCast(u32,alive[t].items.len));
            cellsMax = std.math.max(cellsMax,cellsLen[t]);
        } 
        
// track births and deaths and info so we can center the display on active Cells
        
        const bb = b;                                       // save for screen update
        const dd = d;
        b = 0;                                              // zero for processCells
        d = 0;
                       
        newgrid = try Hash.init(cellsMax);                  // newgrid hash fn based on size (use cellsMax to get the order correct)
        try newgrid.takeStatic(&grid);                      // if same order, reuse static array from grid otherwise reallocate it
                  
        checking = processCells;                            // tell worker to use processCells  
        
        std.Thread.Futex.wait(&ready,1,timeOut) catch unreachable;      // wait for workers to enter ready state
        ready.store(1,.Release);
        
        fini.store(1,.Release);                             // start the workers
        work.store(0,.Release);
        std.Thread.Futex.wake(&work,Threads+1);
                
        {                                                   // use this thread too, at least a little
                     
            if (std.time.milliTimestamp() >= rtime) {       // adjust delay to limit rate as user requests.  Results are approximate
                rtime = std.time.milliTimestamp()+1_000;
                rate = gen-ogen;
                ogen = gen;

                const a = rate*1_000_000_000/(if (500_000_000>delay*rate) 1_000_000_000-delay*rate else 1);     // rate without delay (if any)
                if (a>limit)                                                                                    // if allows "a" to converge on limit
                    delay = 1_000_000_000/limit-1_000_000_000/a
                else
                    delay = 0;
                
                const rr = @intToFloat(f32,(rate*1_000_000_000)/(1_000_000_000-delay*rate));                    // first order kalman predictor
                if (rk!=0) {            
                    const kk = pk/(pk+0.4);                 // kalman gain                 
                    rk += kk*(rr-rk);                       // rate prediction
                    pk = (1-kk)*pk + 0.1;                   // error covariance
                } else {
                    rk = rr;                                // initial prediction
                    pk = rr*rr;                             // and error 
                }

            }
            
            // show the results for this generation (y,x coords)

            { 
                const tt = if (delay>0) ">" else " ";                                                           // needed due compiler buglet with if in print 
                const gg = if (tg<0) 0 else @as(i32,0b00001000_00000000_00000000) >> @intCast(u5,tg);
                if (gen%10000 == 0) {
                    r10k = rk;
                } 
                
                _ = try screen.cursorAt(0,0).writer().print("generation {}({}) population {}({}) births {d:<6} deaths {d:<6} rate{s}{}/s  heap({}) {} window({}) {},{} ±{}  {d:<5.0}", .{gen, std.math.shl(u32,1,s), pop, pop-static, bb, dd, tt, rate, grid.order, cellsMax, sRate, @intCast(i64,xl)-origin, @intCast(i64,yl)-origin, gg, r10k});
            } 
              
            if (pushing==null and gen%std.math.shl(u32,1,s)==0) {     // can we display and do we want to?
            
                pushing = screen;                   // update with new buffer to push
                disp.store(0,.Release);
                std.Thread.Futex.wake(&disp,1);
                 
                if (screen == &s0)                  // switch to alternate buffer for next display cycle
                    screen = &s1
                else 
                    screen = &s0;
                    
                if (gen == 0)                       // briefly show the starting pattern
                    std.time.sleep(1_000_000_000);                          
            }

            gen += 1;
                           
            if (tg<0) {                             // switch focus of center of activity as per user or autotracking
                xl = cbx - cols/2;                       
                xh = xl + cols - 1;
                yl = cby - rows/2;
                yh = yl + rows - 1;
            } else if (gen>=zn) {
                if (std.math.absCast(xl +% cols/2 -% cbx) > 2*cols/3)  {
                    xl = cbx - cols/2;                       
                    xh = xl + cols - 1;
                }
                if (std.math.absCast(yl +% rows/2 -% cby) > 2*rows/3)  {
                    yl = cby - rows/2;
                    yh = yl + rows - 1;    
                }
                zn = gen+sRate*rate/std.math.clamp(62-@clz(@TypeOf(rate),rate+1),1,10);    // 1/10 second above 8192/s down to 1s at 8/s
            }
            
            // update the size of screen buffer
            size = try display.size();
            if (size.width != screen.width or size.height != screen.height)
                try screen.resize(size.height, size.width);
            if (size.width != cols or size.height != rows) {
                cols = @intCast(u32,size.width);
                rows = @intCast(u32,size.height);
                xl = cbx - cols/2; 
                xh = xl + cols - 1;
                yl = cby - rows/2;              
                yh = yl + rows - 1;
            }
            
            // clear the internal screen display buffer
            yl_ = yl;                                               // save yl incase we set it to maxInt
            if (gen%std.math.shl(u32,1,s)==0)
                screen.clear()                                      // prep buffer
            else 
                yl = std.math.maxInt(u32);                          // ignore buffer (add nothing to screen buffer)
                
            // higher rates yield smaller increments 
            inc = std.math.max(@clz(@TypeOf(rate),rate+1)-16,1);    // move autotracking faster with lower rates
            
        }
        
        std.Thread.Futex.wait(&done,1,timeOut) catch unreachable;   // wait for all workers to be done
        done.store(1,.Release);                                     // reenable waits at done
        
        work.store(1,.Release);                                     // tell workers to get ready
        fini.store(0,.Release);
        std.Thread.Futex.wake(&fini,Threads+1);
                
        if (delay>0)                                                // delay to limit the rate
            std.time.sleep(delay);                       
                            
        // adjust cbx for an eventually move of the display window.
        if (tg>0) {
            dx = std.math.absInt(dx) catch unreachable;
            ix = std.math.absInt(ix) catch unreachable;
            if (std.math.absCast(ix-dx) >= inc) {                   
                if (ix > dx) 
                    cbx += inc
                else if (ix < dx) 
                    cbx -= inc;
            }
        }
            
        // adjust cby for an eventually move of the display window.
        if (tg>0) {
            dy = std.math.absInt(dy) catch unreachable;
            iy = std.math.absInt(iy) catch unreachable;
            if (std.math.absCast(iy-dy) >= inc) {
                if (iy > dy) 
                    cby += inc
                else if (iy < dy) 
                    cby -= inc;
            }            
        }
               
        // clear counters for tracking info in the next generation
        dx = 0;
        ix = 0;
        dy = 0;
        iy = 0;
        
    }
    
}
