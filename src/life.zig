const std = @import("std");
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
const Threads:maxIndex = build_options.Threads; // Threads to use from build.zig
const staticSize = build_options.staticSize;    // static tiles are staticSize x staticSize.  Must be a power of 2.
const chunkSize = build_options.chunkSize;      // number of cells to use when balancing alive arrays.
const numChunks = build_options.numChunks;      // initial memory allocations for cells and alive[Threads] arrayLists
const origin = build_options.origin;            // number is so important, it position cells for middle squares to work well
const coord = u32;                              // size of x & y coords
const maxIndex = u32;                           // Maximum index usable in cells (limits population to about std.math.maxInt(maxIndex)/8)

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
    x: coord align(8),
    y: coord,
};

const Area = struct {
    p: Point,               // starting center point
    x: coord,               // x in 'static' area
    y: coord,               // y in 'static' area
    f: bool,                // is area active?
    
    const m = staticSize-1;
    
    const itr = [_]@TypeOf(xa_0){xa_0, ya_1, xs_2, xs_3, ys_4, ys_5, xa_6, xa_7};
    
    const Self=@This();
    
    fn center(self: *Self) bool {
        self.x = self.p.x&m;
        self.y = self.p.y&m;
        self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)];
        return self.f;
    }
    
    fn xa_0(self: *Self) bool {        
        self.p.x +%= 1;
        if (self.x==Self.m) self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)];
        return self.f;
    } 
    
    fn ya_1(self: *Self) bool { 
        self.p.y +%= 1;
        if (self.y==Self.m) self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)]; 
        return self.f;
    }    

    fn xs_2(self: *Self) bool { 
        self.p.x -%= 1;
        if (self.x==Self.m) self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)];
        return self.f;
    }    
    
    fn xs_3(self: *Self) bool {
        self.p.x -%= 1;
        if (self.x==0) self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)];
        return self.f;
    }    
    
    fn ys_4(self: *Self) bool {
        self.p.y -%= 1;
        if (self.y==Self.m) self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)];
        return self.f;
    }  
    
    fn ys_5(self: *Self) bool {
        self.p.y -%= 1;
        if (self.y==0) self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)];
        return self.f;
    }  
    
    fn xa_6(self: *Self) bool { 
        self.p.x +%= 1; 
        if (self.x==0) self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)];
        return self.f;
    } 
    
    fn xa_7(self: *Self) bool {
        self.p.x +%= 1;
        if (self.x==Self.m) self.f = grid.active[grid.index(self.p.x|m, self.p.y|m)];
        return self.f;
    } 
};

const Cell = packed struct {    
    p: Point align(16),         // point for this cell
    n: maxIndex,                // pointer for the next cell in the same hash chain
    v: u8,                      // cells value
};

var theSize:usize = 0;
                 
const Hash = struct {
    hash: []maxIndex,           // pointers into the cells arraylist (2^order x 2^order hash table)
    active: []bool,             // flag if 4x4 area is static
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
                     .order = o, 
                     .shift = @intCast(u5,31-o+1),          // 32-o fails with a comiplier error...  
                   };        
    }
    
    fn assign(self:*Hash,s:Hash) !void {
        if (self.order != s.order) {
            self.order = s.order;
            self.shift = s.shift;
            allocator.free(self.hash);
            self.hash = try allocator.alloc(maxIndex,@as(u32,1)<<2*self.order);
        }
        // clear the hash table pointers
        
        // from valgrind, only @memset is using the os memset call
        // for (self.hash) |*c| c.* = null;                
        // std.mem.set(?*Cell,self.hash,null);
        @memset(@ptrCast([*]u8,self.hash),0,@sizeOf(maxIndex)*@as(u32,1)<<2*self.order);
        self.active = s.active;
    }
    
    fn takeStatic(self:*Hash,s:*Hash) !void { 
        if (self.order != s.order) {
            allocator.free(s.active);            
            s.active = try allocator.alloc(bool,@as(u32,1)<<2*self.order);                  // this is accessed via hashing so making it smaller 
        }                                                                                   // causes more collision and its slower
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
        
    fn setActive(self:*Hash,p:Point) callconv(.Inline) void {   // Collisions are ignored here, more tiles will be flagged as active which is okay
         
         const i = staticSize;                                  // global is not faster, must be 2^N
         const m:coord = staticSize-1;                                // 2^N-1 is a binary mask of N ones.
        
         var t = Point{.x=p.x|m, .y=p.y|m};                     // using a const for t and var tx=t.x, ty=t.y is slower
                                                                // using masks instead of shifting is also faster         
         const x = p.x & m;                  
         const y = p.y & m;   // 4x4 tiles are optimal, 2x2 and 8x8 also work but not as well      

         self.active[self.index(t.x, t.y)] = true;
         
         if (x==m         ) self.active[self.index(t.x+%i, t.y   )] = true;     // this is faster than iterating around the point
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

    fn index(self:Hash, x:u32, y:u32) callconv(.Inline) u32 {   // this faster than bitCast a point to u64 and hashing with that value
        return (( x*%x >> self.shift) ^                         
                ( y*%y >> self.shift << self.order)); 
    }  
    
// find a Cell in the heap and increment its value, if not known, link it in and set its initial value
 
    fn addCell(self:*Hash, p:Point, v:u8) callconv(.Inline) void { 
        
        const h = &self.hash[self.index(p.x, p.y)];     // zig does not have 2D dynamic arrays so we fake it... (using const x=p.x etc is no faster)
        
        var i:maxIndex = h.*;                           // index of the current Cell, 0 implies EOL
            
        while (true) {                                  // loop until we have added or updated the cell
            
            const head = i;                             // save the current index at the head of the hash chain (h), for linking & retries
        
            while (i!=0) {                              // using index(s) is faster (and smaller) than using pointers
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
                i = @cmpxchgStrong(maxIndex, h, head, iCells, .Release, .Monotonic) orelse {    // weak iis not measurabily faster                               
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
                                                             
var tg:isize = 1;                                            // number of generations used for autotracking, if negitive autotracking is disabled
var tg_:isize = 1;                                           // alternate toggle (for w command)
var zn:usize = 0;                                            // generation of next display window switch
                                                             
var b:u32 = 0;                                               // births and deaths
var d:u32 = 0;    
    
var gpa = std.heap.GeneralPurposeAllocator(.{}) {};          
const allocator = &gpa.allocator;

var alive = [_]std.ArrayList(Point){undefined} ** Threads;   // alive cells, static cell stay in this list       
var check = std.ArrayList(*Cell).init(allocator);            // cells that may change during the next iteration
var cells = std.ArrayList(Cell).init(allocator);             // could be part of Hash structure, deallocation is easier this way

var grid:Hash = undefined;                                   // the current hash containing cells and the static tiles mask array
var newgrid:Hash = undefined;                                // what will be come the next grid hash
                
var cellsLen=[_]u32{undefined} ** Threads;                   // array to record iCells values when exiting threads
var work:std.Thread.Mutex = std.Thread.Mutex{};              // start processing mutex
var fini:std.Thread.Mutex = std.Thread.Mutex{};              // prevent a thread from finishing before we see its working/displaying
var begin:std.Thread.Condition = std.Thread.Condition{};     // avoid busy waits when staring work
var done:std.Thread.Condition = std.Thread.Condition{};      // avoid busy waits when waiting for work to finish
var working:u32 = 1;                                         // active processing threads
var checking = processAlive;                                 // controls what processing is done
var going:bool = true;                                       // false when quitting

var disp:std.Thread.Mutex = std.Thread.Mutex{};              // display mutex
var push:std.Thread.Condition = std.Thread.Condition{};      // used to signal display thread to start
var pushing:?*display.Buffer = null;                         // buffer to push or null

threadlocal var iCells:maxIndex = undefined;                 // index to cells thead partition

var cellsMax:u32 = 0;                                        // largest length of the cellLen subarrays
var staticMax:u32 = 0;

pub fn pushScreen(_:void) void {                             // Thread for display (lazy) updates

    var dw = disp.acquire();                                 // we own this mutex
    while (going) { 
        pushing = null;                                      // tell main loop we are ready to display (mutex is held when pushing is updated)
        push.wait(&disp);                                    // wait for signal from main loop
        if (pushing) |pushIt|                                // main loop sets pushing with the buffer to push to the display
            display.push(pushIt.*) catch unreachable;
    }
    dw.release();
} 

pub fn worker(t:maxIndex) void {                            // worker threads for generation updates use this function
    
    while (going) {                                             
                                                              
        const w = work.acquire();                           // block waiting for work
        working += 1;                                       // we need to start Thread-1 workers counting from 1
        if (working>Threads) begin.signal();                // tell main thread when workers are started
        w.release();
         
        if (going) checking(t);                             // call worker function
                                                              
        const f = fini.acquire();                           // worker is now finished
        working -= 1;                                   
        if (working==0) done.signal();                      // tell main we are done, will only reach 0 if main thread is waiting
        f.release(); 
    }
}

pub fn processAlive(t:maxIndex) void {          // process cells in alive[t] adding to cells 
                                                                                                  
    const list = &alive[t];                     // extacting x and y and using them does not add more speed here
    
    iCells = if (t!=0) t else Threads;          // threadlocal vars, we trade memory for thread safey and speed
                                                // and treat the arrayList as dynamic arrays
    var i:u32 = 0;

    while (i < list.items.len) {                // add cells to the hash to enable next generation calculation
            
        var a = Area{ .p=list.items[i], .x=undefined, .y=undefined, .f=undefined };  // add point to surround
        
        // if cell is within the display window update the screen buffer        
        if (a.p.y > yl and a.p.y <= yh and a.p.x >= xl and a.p.x <= xh) {   // p.y > yl to avoid writing on the status line
            screen.cellRef(a.p.y-yl, a.p.x-xl).char = 'O';
        }
                           
        if (a.center()) {                                   // finish Area setup, returning active flag
            list.items[i] = list.items[list.items.len-1];
            list.items.len -= 1;                            // swap and remove last item (optimized list.swapRemove(i); )
            grid.addCell(a.p,10);                           // add the effect of the cell
        } else {
            i += 1;                                                     // keep static cells in alive list - they are stable 
            if (a.x > 0 and a.x < Area.m and a.y > 0 and a.y < Area.m)        
               continue;                                                // no effect if in center of static area
        }
            
        // add effect of the cell on its neighbours in an active areas 
             
        comptime var j = 0;                                 // comptime is atleast 12% faster
        inline while (j<8) : (j+=1) {
            if (Area.itr[j](&a)) grid.addCell(a.p,1);
        }
    } 
    cellsLen[t] = iCells;                                   // save the size of the cell partition for this thread
}
    
pub fn processCells(t:maxIndex) void {     // this only gets called in threaded mode when checkMax exceed the cellsThreading threshold
    
    alive[t].ensureCapacity(staticMax+cellsMax/Threads/2) catch unreachable;

    const sub:u32 = @as(u32,0b00001000_00000000_00000000) >> @intCast(u5,std.math.absCast(tg));  // 2^20 shifted by abs(tg), larger tg smaller area. 
    
    var _ix:i32 = 0;    // use local copies so tracking works (the updates can race and, if it happens too often, tracking fails)
    var _iy:i32 = 0;
    var _dx:i32 = 0;
    var _dy:i32 = 0;    
        
    var k:u32 = t;                      // thread to use for this chunk (think of cells as 2D [Threads,m] with m different for each thread)
    var i:u32 = k;                      // thread index into cells, used to loop through a chunk's cells for a given thread [k,i]
    var l:u32 = 0;                      // number of chunks finished (m exceeded) for k(th) thread
    var p:u32 = Threads*chunkSize;      // start of next chunk [0, Threads*chunkSize*n] where n is 0,1,2,...
    var h=[_]bool{true} ** Threads;     // false when thread's partition is finished (count l once...)
    
    while (l < Threads) : ({ k = (k+1)%Threads; i = p+k; p += Threads*chunkSize; }) {        
        //if (t==0) std.debug.print("{} {} {}: ",.{k, cellsLen[k], p});
        while (h[k] and i < p) : (i += Threads) {
            if (i>=cellsLen[k]) {
                l += 1;
                h[k] = false;
                break;
            }
            const c = cells.items[i];
            if (c.v < 10) {                           
                if (c.v == 3) { 
                    std.debug.assert(alive[t].items.len < alive[t].capacity);
                    alive[t].appendAssumeCapacity(c.p);                         // birth so add to alive list & flag tile(s) as active
                    newgrid.setActive(c.p);       
                    if (c.p.x > cbx) {
                        const tmp = c.p.x-cbx;
                        if (tmp < sub and tmp > 0)                              // the tmp > 0 is so stable patterns do not drift with autotracking
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

pub fn ReturnOf(comptime func: anytype) type {
    return switch (@typeInfo(@TypeOf(func))) {
        .Fn, .BoundFn => |fn_info| fn_info.return_type.?,
        else => unreachable,
    };
}

pub fn main() !void {
    
    var t:maxIndex = 0;                     // used for iterating up to Threads
    
    while (t<Threads) : ( t+=1 ) {
        alive[t] = std.ArrayList(Point).init(allocator);
        defer alive[t].deinit();                            
    }                                       // make sure to cleanup the arrayList(s)
                  
    defer cells.deinit();
    try cells.ensureCapacity((8+Threads)*chunkSize*numChunks);
    
    defer grid.deinit();                    // this also cleans up newgrid's storage
    
    const stdout = std.io.getStdOut().writer();
    
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
    
    var X:coord = origin;
    var Y:coord = origin;
    var count:coord = 0;
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
    grid.hash = try allocator.alloc(maxIndex,1);    // initialize with dummy allocations for .takeStatic and .assign to free
    grid.active = try allocator.alloc(bool,1);  
    
    newgrid = try Hash.init(9*pop);                 // set the order for the generation
    
    grid.order = 0;                                 // this forces grid.assign & newgrid.takeStatic to reallocate storage for hash and static.    
    try newgrid.takeStatic(&grid);
    
    t = 0;
    while (t<Threads) : ( t+=1 ) {                  // for all threads   
        for (alive[t].items) |p|                    // set all tiles active for the first generation
            { newgrid.setActive(p); }   
        try alive[t].ensureCapacity(chunkSize*numChunks);
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
           
    var w = work.acquire();                         // block processing/check update theads
    
    t = 0;                                              
    while (t<Threads) : ( t+=1 ) {                  // start the workers
        _ = try std.Thread.spawn(worker,t);         
    }
    _ = try std.Thread.spawn(pushScreen,{});        // start display thread
    
    var f:ReturnOf(fini.acquire) = undefined;       // used to stop worker from registering a completion before we see the start
 
// main event/life loop  
   
     while (going) {
                  
        var i:u32 = 0;                                       // var for loops
        
        try grid.assign(newgrid);                            // assign newgrid to grid (if order changes reallocate hash storage)
        
        cells.clearRetainingCapacity();                      // will help when resizing an empty arrayList avoids a mem.copy
        try cells.ensureCapacity((pop-static)*(8+Threads));  
        cells.expandToCapacity();                            // arrayList length to max

// populate hash & heap from alive lists
        
        pop = Threads;                                       // sum to get the population
        t = 0;                                          
        while (t<Threads) : ( t+=1 ) {
            pop += @intCast(u32,alive[t].items.len);
        }
            
        checking = processAlive;                             // tell worker to use processAlive
                                                            
        f = fini.acquire();                                  // block completions so a quickly finishing thread is seen
        begin.wait(&work);                                   // release work mutex and wait for worker to signal all started
        f.release();                                         // allow completions
         
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
                                                            
        f = fini.acquire();                                 
        if (working > 1) {                                   // wait for all worker threads to finish
            working -= 1;                                    // only signal if we are waiting
            done.wait(&fini);
            working += 1;
        }
        f.release();
        
        yl = yl_;                                            // restore saved yl (can be used to stop screen updates)
        
        if (!going) {
           w.release();                                      // quit, we need to doing this when workers are waiting
           if (pushing==null) push.signal();                 // make sure display thread also ends
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
        
        f = fini.acquire();                                 // wait for all worker threads to start
        begin.wait(&work);                                  // release work mutex and wait for workers to start and signal
        f.release();                                        // let threads record completions
        
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
                
                _ = try screen.cursorAt(0,0).writer().print("generation {}({}) population {}({}) births {} deaths {} rate{s}{}/s  heap({}) {} window({}) {},{} ±{}  {d:<5.0}", .{gen, std.math.shl(u32,1,s), pop, pop-static, bb, dd, tt, rate, grid.order, cellsMax, sRate, @intCast(i64,xl)-origin, @intCast(i64,yl)-origin, gg, r10k});
            } 
              
            if (pushing==null and gen%std.math.shl(u32,1,s)==0) {     // can we display and do we want to?
            
                const dw = disp.acquire();
                pushing = screen;                   // update with new buffer to push
                push.signal();                      // signal display pushing thread to start
                dw.release();
                
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
        
        f = fini.acquire();                                         // wait for all worker threads to finish
        if (working > 1) {
            working -= 1;
            done.wait(&fini);
            working += 1;
        }
        f.release();
                
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
