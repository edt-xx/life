Author Ed Tomlinson (2021), released under the GPL V3 license.

This program is an implementation of life as create by John H. Conway.  

change the pattern to one of the included patterns and rebuild, 

set the directory use for zbox in build.zig

update the pattern to animated and the number of threads to use in build.zig

zig build -Drelease-fast run
or
zig build -Drelease-safe run (about 10% slower)

zbox can be cloned from: https://github.com/jessrud/zbox.git

generation 299198(2) population 77132(11719) births 3217 deaths 3228 rate 260/s  heap(8) 61286/16841  window(16) -11402,-11587(4)

The title line tells us this is generation 200198 and the (2) that we are displaying every second generation ( see +, - ).
The population is 77132 cells with (11719) cells considered active (a birth or death near the cell in the last generation).
birth and deaths as per the rules of life.
Generations per second.  If the rate is limited (see <, >) you will see rate> indicating we can run faster.
We are using a heap size of 2^8 x 2^8 with 61286 entries and we need to check 16841 cells for the next generation.
window(16) tells us we slowed down updating the display window's position by 16 times - causes the display jump around less (see [, ]).
x,y(4) tells us autotracking is enabled (t) and the effect of distant births and death on autotracking is reduced.
x,y(-4) would tell us autotracking is disabled, use cursor keys to move window or t to restart autotracking.
The last two numbers are the window position.

    <, >    : limits the generation rate, < halves the rate and > doubles it (when limited you will see rate>xxx/s )

    +, -    : only show every nth generation.  + doubles n, - halves n (generation xxxx(n) ...)

    [, ]    : slow down [, or speed up ], the rate at which autotracking moves the display window

    cursor  : allow manual positioning of the window using cursor keys (window(-autotracking) ...)
    keys

    t       : if manual tracking is enabled, disable it (x,y(autotracking)...), if disabled, cycle t thru 1..6, decreasing 
              the area evaluated for active cells as t is increased.

    w       : toggle window postion and tracking.  Patterns often have two interesting areas, this lets you toggle between them.

    esc, q  : will exit the program

The algorithm used here was developed in the late 70s or early 80s.  I first implemented it on an OSI superboard II using 
Basic and 6502 assembly.  This was before algorithms like hash life were discovered.  I've been using it when I want to learn a 
new language environment.  This version was started to learn basic zig, then valgrind and oprofile came into the picture and let 
me get a better idea of how zig compiles and where the program was spending its time.

This algorithm is nothing special by todays standards, it does not use SIMD or the GPU for speed.  It does use threading when
updating the display and for the generation update.  Its been a good learning tool.

How it works.  We have an N x N array of pointers to cells.  The indexes to the array is a hash based on the x, y cords of the cell.
Each cell has a pointer to another cell.  So we have an array of lists of cells where hash(x,y) are the same.  We size the array
depending on how loaded it becomes, at near 100% ( eg. N x N is near 2^(N+N)) we increase N.  We use this structure to sum the 
effects of cells on each other.  We also track 4 x 4 areas ( eg hash(x/4, y/4)) flagging each area static if births or deaths occur 
in the area.  Any cells in a static area survive into the next generation.  We still have to add the effect of these cell on cells 
in ajoining non static areas.  The effect of all this is to drasticly limit the number of cells we need to work with.  Once we finsh 
processing the alive arraylist (processAlive), we start a thread to update the display and others to process the cells list 
(processCells) to update the alive[] lists for the next generation.  To make being thread safe easier we keep alive[Threads] lists
of alive points.  ProcessCells is designed to be thread safe, and just as important, it balances the alive lists and updates the 
static 4x4 area flags when we find a birth or death.  It also gathers data to allow autotracking of activity. 

The way the cells are added in AddCell and AddNear is interesting.  At the start of the process we record the cells head of list.
If the cell does not exist in the list we try to add it.  In the multithreaded case, another thread may have already done this, 
and will have updated the head of list,  the @cmpxchgStrong detects this, which case we just retry with the new head of list.
Typically this happen a few times per generation.  The process would also work with @cmpxchgWeak, but I do not see much, if any,
differences in benchmarks.  (currently it uses Strong - speed is about the same it might be using a little less CPU).

Sometimes optimization is not at all obvious.  It is possible to create a list of cells that might contain a birth or death while
processing the alive lists.  This gives us a subset of cells to check usually containing 25-35% of cells.  Normally this would 
help since scanning less is good.  However because we spend most of our time in processAlive in addCell and addNear the overhead 
to track these cells actually ends up costing us 2-5%.  I added this optimization before the addition of the static cell logic.
which reduces the number of cells to process by about 70-90%, that changed the balance so the checkList was no longer helping.
