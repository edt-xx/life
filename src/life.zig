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
// zig build -Drelease-safe run (about 10% slower) 
//
// zbox can be cloned from: https://github.com/jessrud/zbox.git
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
//
// +, -        : only show every nth generation.  + doubles n, - halves n (generation xxxx(n) ...)
//
// cursor keys : allow manual positioning of the window using cursor keys (window(-autotracking generations) ...)
//
// t           : if manual tracking enabled, disable, if disabled, cycle t thru 1..6, decreasing the area evaluated for active cells. 
//               window is 1024k (t=1) to 32k (t=6).
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
// other.  We also track 4 x 4 areas ( eg hash(x/4, y/4)) flagging each area static if no births or deaths occur in the area.  Any cells
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
// to track these cells actually ends up costing us 2-5%.  I added this optimization before the addition of the static cell logic.
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
const Threads = build_options.Threads;          // Threads to use from build.zig
const staticSize = build_options.staticSize;    // active consists of staticSize x staticSize tiles.  Must be a power of 2.

const cellsThreading = 1_000;               // Condition vars and -lpthread (std.Thread.Condition linux impl is buggy) removes spinloops. 

// with p_95_206_595mS on an i7-4770k at 3.5GHz (4 cores, 8 threads)
//
// Threads  gen         rate    cpu
// 1        100,000     330s    15%
// 2        100,000     290/s   27%     using rmw in addCell and addNear seems to be the reason for this decrease
// 3        100,000     400/s   38%
// 4        100,000     440/s   46%
// 5        100,100     470/s   57%
// 6        100,000     520/s   67%
// 7        100,000     550/s   73%
// 8        100,000     500/s   68%     The update threads + display thread > CPU threads so we take longer in processCells/displayUqpdate
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

const Point = struct {
    x: u32,
    y: u32,
};

const Cell = struct {    
    n: ?*Cell,                              // pointer for the next cell in the same hash chain
    p: Point,                               // point for this cell
    v: u8,                                  // cells value
};

var theSize:usize = 0;
                 
const Hash = struct {
    hash:[]?*Cell,              // pointers into the cells arraylist (2^order x 2^order hash table)
    static: []bool,             // flag if 4x4 area is static
    order:u5,                   // hash size is 2^(order+order), u5 for << and >> with usize and a var
    shift:u5,                   // avoid a subtraction in index
       
    fn init(size:usize) !Hash {
                    
        var self:Hash = undefined;
        
// log2 of the population from the last iteration.  The ammount of memory used is a tradeoff
// between the length of the hash/heap chains and the time taken to clear the hash array.
        
        if (size < theSize/2 or size > theSize)         // reduce order bouncing and (re)allocates
            theSize = size;
        
        // const o = @intCast(u5,std.math.clamp(std.math.log2(theSize)/2+1, 6, 12));
        const o = @intCast(u5,std.math.clamp(31-@clz(@TypeOf(theSize),theSize)/2+1, 6, 12));
        
        return Hash{ .hash=undefined, 
                     .static=undefined,
                     .order = o, 
                     .shift = @intCast(u5,31-o+1),      // 32-o fails with a comiplier error...
                   };        
    }
    
    fn assign(self:*Hash,s:Hash) !void {
        if (self.order != s.order) {
            self.order = s.order;
            self.shift = s.shift;
            allocator.free(self.hash);
            self.hash = try allocator.alloc(?*Cell,@as(u32,1)<<2*self.order);
        }
        // clear the hash table pointers
        
        // from valgrind, only @memset is using the os memset call
        // for (self.hash) |*c| c.* = null;                
        // std.mem.set(?*Cell,self.hash,null);
        @memset(@ptrCast([*]u8,self.hash),0,@sizeOf(?*Cell)*@as(u32,1)<<2*self.order);
        self.static = s.static;
    }
    
    fn takeStatic(self:*Hash,s:*Hash) !void { 
        if (self.order != s.order) {
            allocator.free(s.static);            
            s.static = try allocator.alloc(bool,@as(u32,1)<<2*self.order);                  // this is accessed via hashing so making it
        }                                                                                   // smaller causes more collision and is slower
        self.static = s.static;
        // mark all tiles as static to start
        // from valgrind, only @memset uses the os memset
        // for (self.static) |*t| t.* = true;           
        // std.mem.set(bool,self.static,true);
        @memset(@ptrCast([*]u8,self.static),1,@sizeOf(bool)*@as(u32,1)<<2*self.order);
    }
      
    fn deinit(self:Hash) void {
        allocator.free(self.hash);
        allocator.free(self.static);
    }
        
    fn setActive(self:*Hash,p:Point) callconv(.Inline) void {   // Collisions are ignored here, more tiles will be flagged as active which is okay
         
         const i = staticSize;                                  // global is not faster
         const m = staticSize-1;
        
         var t = Point{.x=p.x|m, .y=p.y|m};                     // using a const for t and var tx=t.x, ty=t.y is slower
                                                                // using masks instead of shifting is also faster         
         const x = p.x & m;                  
         const y = p.y & m;   // 4x4 tiles are optimal, 2x2 and 8x8 also work but not as well      

         self.static[self.index(t.x, t.y)] = false;
         
         if (x==m         ) self.static[self.index(t.x+%i, t.y   )] = false;
         if (x==m and y==m) self.static[self.index(t.x+%i, t.y+%i)] = false;
         if (         y==m) self.static[self.index(t.x   , t.y+%i)] = false;
         if (x==0 and y==m) self.static[self.index(t.x-%i, t.y+%i)] = false;
         if (x==0         ) self.static[self.index(t.x-%i, t.y   )] = false;
         if (x==0 and y==0) self.static[self.index(t.x-%i, t.y-%i)] = false;
         if (         y==0) self.static[self.index(t.x   , t.y-%i)] = false;
         if (x==m and y==0) self.static[self.index(t.x+%i, t.y-%i)] = false;
   }              

// use the middle bits of the square of the coord to create the index.  No need
// to add a seed since this is not used for a sequence (see: Middle Square Weyl)
// valgrind shows the low 32bits of the 64bit product is saved.  So we use the
// high bits from the 32bits to generate the index.  
 
// passing x, y instead of a point lets the compiler generate beter code (~25% faster) and speed counts here
 
    fn index(self:Hash, x:u32, y:u32) callconv(.Inline) u32 {   // compiler 0.71 generates better code using left shift vs a bit mask.
        return (( x*%x >> self.shift) | 
                ( y*%y >> self.shift << self.order));     
    } 
 
// find a Cell in the heap and increment its value, if not known, link it in and set its initial value
    
    fn addCell(self:*Hash, p:Point) void { 
        
        //const x = p.x;
        //const y = p.y;

        const h = self.index(p.x,p.y);      // zig does not have 2D dynamic arrays so we fake it...
        
        var i:?*Cell = self.hash[h];        // Points to the current Cell or null
                       
        while (true) {
            
            const head = i;
            
            while (i) |c| {
                if (p.y == c.p.y and p.x == c.p.x) {
                    if (Threads == 1) 
                        c.v += 10
                    else
                        _ = @atomicRmw(u8, &c.v, .Add, 10, .Monotonic);
                    //if (v > 2) return;                         
                    //check.items[iCheck] = c;                   // potential survivor, add to checklist if not already done for births
                    //iCheck += Threads;
                    return;
                }
                i = c.n;          // advance to the next cell
            }
            cells.items[iCells] = Cell{.p=p, .n=head, .v=10};     // cell not in heap, add it.  Note iCells is threadlocal.             
            if (Threads == 1) {
                self.hash[h] = &cells.items[iCells];
                //check.items[iCheck] = &cells.items[iCells];     // add to check list
                iCells += Threads;
                std.debug.assert(iCells < cellsMax);
                //iCheck += Threads;
                return;
            } else {
                i = @cmpxchgStrong(?*Cell, &self.hash[h], head, &cells.items[iCells], .Release, .Monotonic) orelse {                    
                    //check.items[iCheck] = &cells.items[iCells];  // add to check list
                    //iCheck += Threads;
                    iCells += Threads;                             // commit the Cell
                    std.debug.assert(iCells < cellsMax);
                    return;
                };
            }            
        }
    }
    
// find a Cell in the heap and increment its value, if not known, link it in and set its initial value
 
    fn addNear(self:*Hash, p:Point) void { 
        
        //const x = p.x;                    // no faster using x & y
        //const y = p.y;
        
        const h = self.index(p.x,p.y);      // zig does not have 2D dynamic arrays so we fake it...
        
        var i:?*Cell = self.hash[h];        // ***1 Points to the current Cell or null
            
        while (true) {
            
            const head = i;
        
            while (i) |c| {
                if (p.y == c.p.y and p.x == c.p.x) {
                    if (Threads == 1)
                        c.v += 1
                    else
                        _ = @atomicRmw(u8,&c.v,.Add,1,.Monotonic); 
                    //if (v != 2) return;            // v+1 is not 3, this is not a possible birth                            
                    //check.items[iCheck] = c;       // potential birth, add to checklist
                    //iCheck += Threads;
                    return;
                }
                i = c.n;          // advance to the next cel
            }
            cells.items[iCells] = Cell{.p=p, .n=head, .v=1};  // cell not in heap, add it.  Note iCells is threadlocal.
            if (Threads == 1) {
                self.hash[h] = &cells.items[iCells];
                iCells += Threads;
                std.debug.assert(iCells < cellsMax);
                return;
            } else {
                i = @cmpxchgStrong(?*Cell, &self.hash[h], head, &cells.items[iCells], .Release, .Monotonic) orelse {                                   
                    iCells += Threads;
                    std.debug.assert(iCells < cellsMax);
                    return;
                };
            }
        }
    }
    
};

//fn sum(bmd:[Track]i32, t:isize) i32 {                        // tool used by autotracking (bmd = births - deaths)
//  var i:u32 = 0; var s:i32 = 0;
//  while (i < t) : (i += 1) s += std.math.absInt(bmd[i]) catch unreachable;
//  return s;
//}

 var screen:display.Buffer = undefined;

const origin:u32 = 1_000_000_000;                           // about 1/4 of max int which is (near) optimal when both index & tile hashes are considered

var cbx:u32 = undefined;                                    // starting center of activity 
var cby:u32 = undefined;
var cbx_:u32 = undefined;                                   // alternate center of activity (toggle with w) 
var cby_:u32 = undefined;

var xl:u32 = origin;                                        // window at origin to start, size to be set
var xh:u32 = 0;   
var yl:u32 = origin; 
var yh:u32 = 0;
             
const Track = 6;

var dx:i32 = 0;                                             // used to track activity for autotracking
var ix:i32 = 0;
var dy:i32 = 0;
var iy:i32 = 0;

var tg:isize = 1;                                           // number of generations used for autotracking, if negitive autotracking is disabled
var tg_:isize = 1;                                          // alternate toggle
//var zg:usize = 0;                                           // index for history
var zn:usize = 0;                                           // generation of next display window switch

var b:u32 = 0;                                              // births and deaths
var d:u32 = 0;    
    
var gpa = (std.heap.GeneralPurposeAllocator(.{}){});
const allocator = &gpa.allocator;

var alive = [_]std.ArrayList(Point){undefined} ** Threads;   // alive cells, static cell stay in this list       
var check = std.ArrayList(*Cell).init(allocator);            // cells that may change during the next iteration
var cells = std.ArrayList(Cell).init(allocator);             // could be part of Hash structure, deallocation is easier this way

var grid:Hash = undefined;                                   // the current hash containing cells and the static tiles mask array
var newgrid:Hash = undefined;                                // what will be come the next grid hash

// const some_strings = [_][]const u8{"some string", "some other string"};

//  std.sort.sort(Point, alive.items, {}, Point_lt);

//  fn Point_lt(_ctx: void, a: Point, b: Point) bool {
//      return switch (std.math.order(a.y, b.y)) {
//          .lt => true,
//          .eq => a.x < b.x,
//          .gt => false,
//      };
//  }

//var checkLen=[_]usize{undefined} ** Threads;                      
var cellsLen=[_]u32{undefined} ** Threads;                     // array to record iCells values when exiting threads
var work:std.Thread.Mutex = std.Thread.Mutex{};                // start processing mutex
var disp_work:std.Thread.Mutex = std.Thread.Mutex{};           // start display mutex
var fini:std.Thread.Mutex = std.Thread.Mutex{};                // prevent a thread from finishing before we see its working/displaying
var begin:std.Thread.Condition = std.Thread.Condition{};       // avoid busy waits when staring work
var done:std.Thread.Condition = std.Thread.Condition{};        // avoid busy waits when waiting for work to finish
var working:u32 = 1;                                           // active processing threads
var displaying:u32 = 1;                                        // active display threads
var checking:bool = false;                                     // controls what processing is done
var going:bool = true;                                            // false when quitting

//qthreadlocal var iCheck:usize = undefined;                   // Index into the check and cell subarrays
threadlocal var iCells:u32 = undefined;

var cellsMax:u32 = 0;                                         // largest length of the cellLen subarrays
//var checkMax:usize = 0;

pub fn worker(t:u32) void {
    
    var trigger:*std.Thread.Mutex = undefined;                 // choose mutex to trigger 
    var counter:*u32 = undefined;                              // and counter to use
    if (t==0) {                                                
        trigger = &disp_work;                                  // there are other, more generalized, ways to set this up
        counter = &displaying;                                 // here I went for the easiest
    } else {                                                   
        trigger = &work;                                       
        counter = &working;                                    
    }                                                          
                                                               
    while (going) {                                             
        {                                                      
            const w = trigger.acquire();                       // block waiting for work
            _ = @atomicRmw(u32, counter, .Add, 1, .AcqRel);    // we are now working
            w.release();
            begin.signal();                                    // tell main to check counter
        } 
        if (going) {
            if (t==0)                                              // depending on the thread & checking, do the work
                display.push(screen) catch {} 
            else if (checking)                                     
                processCells(t)                                    
            else                                                   
                processAlive(t); 
        }
        {                                                      
            const f = fini.acquire();                          // work is now finished
            _ = @atomicRmw(u32, counter, .Sub, 1, .AcqRel);    // no longer working
            f.release(); 
            done.signal();                                     // tell main to check counter
        }
    }
}

pub fn processAlive(t:u32) void {
    
    const m = staticSize-1;
    
    var list = &alive[t];                   // extacting x and y and using them does not add more speed here
    
    // iCheck = t;                          
    iCells = t;                             // threadlocal vars, we trade memory for thread safey and speed
                                            // and treat the arrayList as dynamic arrays
    var i:u32 = 0;

    while (i < list.items.len) {            // add cells to the hash to enable next generation calculation
        
        var p = list.items[i];              // extract the point                                     
        
        if (grid.static[grid.index(p.x|m, p.y|m)])
            i += 1                                     // keep static cells in alive list - they are stable
        else {
            grid.addCell(p);  
            _ = list.swapRemove(i);         // this is why we use alive[] instead of the method used with check and cells...
        }                                         

        // add effect of the cell on the surrounding area, if not in a static area
        
        p.x +%= 1;              if (!grid.static[grid.index(p.x|m, p.y|m)]) grid.addNear(p);   // doing static check here and
                    p.y +%= 1;  if (!grid.static[grid.index(p.x|m, p.y|m)]) grid.addNear(p);   // not in addNear call saves ~2%
        p.x -%= 1;              if (!grid.static[grid.index(p.x|m, p.y|m)]) grid.addNear(p);
        p.x -%= 1;              if (!grid.static[grid.index(p.x|m, p.y|m)]) grid.addNear(p);
                    p.y -%= 1;  if (!grid.static[grid.index(p.x|m, p.y|m)]) grid.addNear(p);
                    p.y -%= 1;  if (!grid.static[grid.index(p.x|m, p.y|m)]) grid.addNear(p);
        p.x +%= 1;              if (!grid.static[grid.index(p.x|m, p.y|m)]) grid.addNear(p);
        p.x +%= 1;              if (!grid.static[grid.index(p.x|m, p.y|m)]) grid.addNear(p);
        
        // if cell is within the display window update the screen buffer
        
        if (p.x >= xl and p.x <= xh and p.y >= yl and p.y <= yh) {
            screen.cellRef(p.y-yl+1,p.x-xl).char = 'O';
        }        
    }    
    //std.debug.assert(iCheck < check.capacity);  // do some safely checks, just in case...
    //checkLen[t] = iCheck;                       // save the sizes of the check and cell arraylist sublists
    cellsLen[t] = iCells;  
}
    
pub fn processCells(t:u32) void {     // this only gets called in threaded mode when checkMax exceed the cellsThreading threshold

    var _ix:i32 = 0;    // use local copies so tracking works (the updates can race and when it happens to often tracking fails)
    var _iy:i32 = 0;
    var _dx:i32 = 0;
    var _dy:i32 = 0;
    
    var sub:u32 = 0;
    if (tg>0)
        sub = @intCast(u32,11+tg)
    else
        sub = @intCast(u32,11-tg);
    
    var k:u32 = 0;                                         // loop thru cells arraylist
    while (k < Threads) : (k+=1) {
        var i:u32 = k + Threads*t;
        while (i < cellsLen[k]) : (i+=Threads*Threads) {   // scan all cells in a thread safe way that balances the alive[] lists
            const c = cells.items[i];
            //const v = c.v;
            if (c.v < 10) {
                if (c.v == 3) {                                         // birth so add to alive list & flag tile(s) as active
                    alive[t].appendAssumeCapacity(c.p);
                    newgrid.setActive(c.p);
                    if (c.p.x > cbx) {                                  // info for auto tracking of activity (births)
                        _ix +=  @intCast(i32,std.math.max(@clz(u32,c.p.x-cbx)-sub,0));
                    } else if (c.p.x < cbx) {
                        _dx +=  @intCast(i32,std.math.max(@clz(u32,cbx-c.p.x)-sub,0)); 
                    }
                    if (c.p.y > cby) { 
                        _iy +=  @intCast(i32,std.math.max(@clz(u32,c.p.y-cby)-sub,0));
                    } else if (c.p.y < cby) { 
                        _dy +=  @intCast(i32,std.math.max(@clz(u32,cby-c.p.y)-sub,0)); 
                    } 
                    b += 1;                                             // can race, not critical 
                }
            } else
                if (c.v == 12 or c.v == 13)                             // active cell that survives
                    alive[t].appendAssumeCapacity(c.p)
                else {
                    newgrid.setActive(c.p);
                    if (c.p.x > cbx) {                                  // info for auto tracking of activity (deaths)
                        _ix -=  @intCast(i32,std.math.max(@clz(u32,c.p.x-cbx)-sub,0));
                    } else if (c.p.x < cbx) {
                        _dx -=  @intCast(i32,std.math.max(@clz(u32,cbx-c.p.x)-sub,0)); 
                    }
                    if (c.p.y > cby) { 
                        _iy -=  @intCast(i32,std.math.max(@clz(u32,c.p.y-cby)-sub,0));
                    } else if (c.p.y < cby) { 
                        _dy -=  @intCast(i32,std.math.max(@clz(u32,cby-c.p.y)-sub,0)); 
                    } 
                    d += 1;                                             // can race, not critical 
                }
        }
    }
    ix += _ix;           // if this races once in a blue moon its okay
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
    
    var t:u32 = 0;                          // used for iterating up to Threads
    
    while (t<Threads) : ( t+=1 ) {
        alive[t] = std.ArrayList(Point).init(allocator);
        defer alive[t].deinit();
    }                                       // make sure to cleanup the arrayList(s)
    //defer check.deinit();               
    defer cells.deinit();
    defer grid.deinit();                    // this also cleans up newgrid's storage
    
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
    
    screen = try display.Buffer.init(allocator, size.height, size.width);
    defer screen.deinit();

// rle pattern decoding
    var pop:u32 = 0;
    var X:u32 = origin;
    var Y:u32 = origin;
    var count:u32 = 0;
    t = 0;
    for (pattern) |c| {
        switch (c) {
            'b' => {if (count==0) {X+=1;} else {X+=count; count=0;}},
            'o' => {
                        if (count==0) count=1;
                        while (count>0):(count-=1) {
                            if (Threads != 1) {
                                if (alive[t].items.len & 0x3 == 0) {
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
    
// generation, births & deaths
    var gen: u32 = 0;
    var s:u32 = 0;          // update display even 2^s generations
    var static:u32 = 0;     // cells that do not change from gen to gen
    
    var inc:u32 = 20;                                   // max ammount to move the display window at a time

// set initial display window

    cbx = (xh-origin)/2+origin;                         // starting center of activity 
    cby = (yh-origin)/2+origin;
    cbx_ = cbx;                                         // and the alternate
    cby_ = cby;
    
    xl = cbx - cols/2;                                  // starting window
    xh = xl + cols - 1;  
    yl = cby - rows/2; 
    yh = yl + rows - 2;
            
// initial grid. The cells arrayList is sized so it will not grow during a calcuation so pointers are stable                                                                                                    

    grid = try Hash.init(9*pop);                    // this sets the order of the Hash
    grid.hash = try allocator.alloc(?*Cell,1);      // initialize with dummy allocations  
    grid.static = try allocator.alloc(bool,1);  
    
    newgrid = try Hash.init(9*pop);                 // set the order for the generation
    
    grid.order = 0;     // this forces grid.assign & newgrid.takeStatic to reallocate storage for hash and static.
    
    try newgrid.takeStatic(&grid);
    
    t = 0;
    while (t<Threads) : ( t+=1 ) {
        for (alive[t].items) |p| { newgrid.setActive(p); }   // set all tiles active for the first generation
    }
    
    //try check.ensureCapacity(pop*6+3);    // prepare for main loop
    //checkMax = check.capacity-1; 
    //try check.resize(checkMax);           // allow access to all allocated items
        
    b = @intCast(u32,pop);                  // everything is a birth at the start
    
    var ogen:u32 = 0;                                   // info for rate calculations
    var rtime:i64 = std.time.milliTimestamp()+1_000;  
    var rate:usize = 1;
    var limit:usize = 65536;                             // optimistic rate limit
    var delay:usize = 0;
           
    var dw = disp_work.acquire();                       // block display update thread
    var w = work.acquire();                             // block processing/check update theads
    t = 0;                                              
    while (t<Threads) : ( t+=1 ) {                      // start the, blocked, workers
        _ = try std.Thread.spawn(worker,t);         
    }                                                
    var f:ReturnOf(fini.acquire) = undefined;           // used to stop worker from registering a completion before we see the start
 
// main event/life loop  

    // var nnn:usize = 0;
    // var ddd:i128 = 0;

     while (try display.nextEvent()) |e| {
          
        var i:u32 = 0;
        
        // process user input
        switch (e) {
            .up     => { cby += inc; zn=gen; if (tg>0) tg = -tg; },  // manually position the display window
            .down   => { cby -= inc; zn=gen; if (tg>0) tg = -tg; },
            .left   => { cbx += inc; zn=gen; if (tg>0) tg = -tg; },
            .right  => { cbx -= inc; zn=gen; if (tg>0) tg = -tg; },
            .escape => { going=false; dw.release(); w.release();                                 // quit
                         while (@atomicLoad(u32,&displaying,.Acquire)>1) { done.wait(&fini); } 
                         return; 
                       },                       
             .other => |data| {   const eql = std.mem.eql;
                                  if (eql(u8,"t",data)) {
                                      zn=gen;
                                      if (tg>0) { 
                                          tg = @rem(tg,Track)+1;    // 2, 3 & 4 are the most interesting for tracking
                                      } else 
                                          tg = -tg; 
                                      //if (zg >= tg) 
                                      //    zg = 0; 
                                  } 
                                  if (eql(u8,"s",data) or eql(u8,",",data)) limit = if (limit>1) limit/2 else limit;     // limit generation rate
                                  if (eql(u8,"f",data) or eql(u8,".",data)) limit = if (limit<16384) limit*2 else limit;
                                  if (eql(u8,"w",data)) { const t1=cbx; cbx=cbx_; cbx_=t1; 
                                                          const t2=cby; cby=cby_; cby_=t2; 
                                                          const t3=tg;  tg=tg_;   tg_=t3;
                                                          zn = gen;
                                                        } 
                                  if (eql(u8,"+",data)) s += 1;                                                          // update every 2^s generation
                                  if (eql(u8,"-",data)) s = if (s>0) s-1 else s;
                                  if (eql(u8,"q",data)) { going=false; dw.release(); w.release();                                 // quit
                                                          while (@atomicLoad(u32,&displaying,.Acquire)>1) { done.wait(&fini); } 
                                                          return; 
                                                        }     
                             },
              else => {},
        }
        
        // switch focus of center of activity as per user
         if (tg<0) {
             xl = cbx - cols/2;                       
             xh = xl + cols - 1;
             yl = cby - rows/2;
             yh = yl + rows - 2;
         }
        
        try grid.assign(newgrid);                            // assign newgrid to grid (if order changes reallocate hash storage)
        
        try cells.ensureCapacity((pop-static)*(8+Threads));  // too small causes wierd SIGSEGV errors as Threads increases - 'fun' debugging exercise...
        try cells.resize(cells.capacity-1);                  // arrayList length to max
        cellsMax = @intCast(u32,cells.capacity);
        
        //try check.ensureCapacity(std.math.max((b+d)*9*Threads,5*checkMax/4));    // resize the list of cells that might change state
        //try check.resize(check.capacity-1);
        
        // wait for thread to finish before (possibily) changing anything to do with the display
        
        if (gen%std.math.shl(u32,1,s)==0) {
            //const tmp:i128 = std.time.nanoTimestamp();
            f = fini.acquire();
            while (@atomicLoad(u32,&displaying,.Monotonic)>1) {    // wait for display worker thread, usually its done before we get here
                done.wait(&fini);
            }
            f.release();
            //ddd=(std.time.nanoTimestamp()-tmp);
        }
 
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
         screen.clear();                                     // clear the internal screen display buffer    

// populate hash & heap from alive list
        
        // bbb = 0;   // debugging - count of the number of time we retry a cell update
        
        pop = 0;                                            // sum to get the population
        t = 0;                                          
        while (t<Threads) : ( t+=1 ) {
            pop += @intCast(u32,alive[t].items.len)+1;
        }
        
        // nnn += 1;
        // _ = try screen.cursorAt(3,0).writer().print("release working {}",.{nnn});
        
        checking = false;
        
        if (Threads > 1) {
            f = fini.acquire();                                        // block completions so a quickly finishing thread is seen
            while (@atomicLoad(u32,&working,.Monotonic)<Threads) {     // wait for all worker threads to wake each other
                begin.wait(&work);                                     // release work mutex and wait for worker to signal 
            }
            f.release();                                               // allow completions
        }
                    
        processAlive(0);                                               // Use our existing thread. 
        
        if (Threads > 1) {
            f = fini.acquire();
            while (@atomicLoad(u32,&working,.Monotonic)>1) {           // wait for all worker threads to finish
                done.wait(&fini);
            }
            f.release();
        }
        
        //checkMax = 0;
        cellsMax = 0;
        static = 0;
        
        // gather stats needed for display and sizing cells, check and alive[] arrayLists
        t = 0;                                          
        while (t<Threads) : ( t+=1 ) {  
            static += @intCast(u32,alive[t].items.len);
            //checkMax = std.math.max(checkMax,checkLen[t]);
            cellsMax = std.math.max(cellsMax,cellsLen[t]);
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

        var tt = if (delay>0) ">" else " ";    // needed due to 0.71 compiler buglet with if in print args
        
        _ = try screen.cursorAt(0,0).writer().print("generation {}({}) population {}({}) births {} deaths {} rate{s}{}/s  heap({}) {} window({}) {},{}",.{gen, std.math.shl(u32,1,s), pop, pop-static, b, d, tt, rate, grid.order, cellsMax, tg, @intCast(i64,xl)-origin, @intCast(i64,yl)-origin});
        
        //_ = try screen.cursorAt(1,0).writer().print("debug {} {} {}, {} {} {}, {} {} {}, {} {}",.{alive[0].items.len,cellsLen[0]/3,checkLen[0]/3,alive[1].items.len,cellsLen[1]/3,checkLen[1]/3,alive[2].items.len,cellsLen[2]/3,checkLen[2]/3,bbb,ddd});
        
        // doing the screen update, display.push(screen); in another thread alows overlap and yields faster rates. 
        
        if ((gen+1)%std.math.shl(u32,1,s)==0) {                     // update display every 2^s generations
            f=fini.acquire();
            while (@atomicLoad(u32,&displaying,.Monotonic)<2) {     // wait for worker thread
                begin.wait(&disp_work);                             // release disp_work mutex and wait for worker to signal
            }
            f.release();
        }
                
        if (gen == 0)
            std.time.sleep(1_000_000_000);      // briefly show the starting pattern
        if (delay>0)
            std.time.sleep(delay);              // we calcuate delay to limit the rate
            
        gen += 1;

// track births and deaths and info so we can center the display on active Cells
        
        b = 0;
        d = 0;
                       
        newgrid = try Hash.init(cellsMax);                  // newgrid hash fn based on size (get the order correct)
        try newgrid.takeStatic(&grid);                      // if order save, reuse static array from grid otherwise reallocate it
        
        t = 0;                                              // make sure the alive[] arraylists can grow
        while (t<Threads) : ( t+=1 ) {
            try alive[t].ensureCapacity(alive[t].items.len+cellsMax/2+2);
        }

        if (cellsMax > cellsThreading and Threads>1) {                   
            
            checking = true;                                            // tell worker to use processCells  
            
            f = fini.acquire();
            while (@atomicLoad(u32,&working,.Monotonic)<Threads) {      // wait for all worker threads to wake each other
                begin.wait(&work);                                      // release work mutex and wait for worker to signal
            }
            f.release();                                                // let threads record completions
            
            processCells(0);                                            // use this thread too
            
            f = fini.acquire();
            while (@atomicLoad(u32,&working,.Monotonic)>1) {            // wait for all worker threads to finish
                done.wait(&fini);
            }
            f.release();
        } else {
            t = 0;                                                      // in most cases this is the faster option
            while (t<Threads) : (t+=1) 
                processCells(t);
        }            
                                       
        // higher rates yield smaller increments 
        inc = std.math.max(@clz(@TypeOf(rate),rate+1)-16,1);            // increase increment as we slow down
        
        // adjust cbx for an eventually move of the display window.
        
        if (tg>0) {
            dx = @intCast(i32,std.math.absCast(dx));
            ix = @intCast(i32,std.math.absCast(ix));
            if (std.math.absCast(ix-dx) >= inc) {                   
                if (ix > dx) 
                    cbx += inc
                else if (ix < dx) 
                    cbx -= inc;
            }
        }
            
        // adjust cby for an eventually move of the display window.
        if (tg>0) {
            dy = @intCast(i32,std.math.absCast(dy));
            iy = @intCast(i32,std.math.absCast(iy));
            if (std.math.absCast(iy-dy) >= inc) {
                if (iy > dy) 
                    cby += inc
                else if (iy < dy) 
                    cby -= inc;
            }            
        }
        
        // keep a history so short cycle patterns with non symetric birth & deaths will be ignored for tracking
        // if (tg!=0)
        //    zg = gen%std.math.absCast(tg);
        
        // clear counters for tracking info in the next generation
        dx = 0;
        ix = 0;
        dy = 0;
        iy = 0;
            
        // switch focus of "center of activity" is moving off display window
        if (tg>0 and gen>=zn) {
            if (std.math.absCast(xl +% cols/2 -% cbx) > 4*cols/5)  {
                xl = cbx - cols/2;                       
                xh = xl + cols - 1;
            }
            if (std.math.absCast(yl +% rows/2 -% cby) > 4*rows/5)  {
                yl = cby - rows/2;
                yh = yl + rows - 2;     // allow for the title line
            }
            zn = gen+rate/std.math.clamp(62-@clz(@TypeOf(rate),rate+1),1,10);    // 1/10 second above 8192/s down to 1s at 8/s
        }
        
    }
    
}
