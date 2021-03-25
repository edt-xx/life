Author Ed Tomlinson (2021), released under the GPL V3 license.

This program is an implementation of life as create by John H. Conway.  

change the pattern to one of the included patterns and rebuild, 

zig build-exe -O ReleaseFast --pkg-begin zbox ../zbox/src/box.zig --pkg-end life.zig

zbox can be cloned from: https://github.com/jessrud/zbox.git

generation 299198(2) population 77132(11719) births 3217 deaths 3228 rate 260/s  heap(8) 61286/16841  window(2) -11402,-11587

The title line tells us this is generation 200198 and the (2) that we are displaying every second generation ( see +, - )
the population is 77132 cells with (11719) cells considered active (a birth or death near the cell in the last generation)
birth and deaths as per the rules of life  
generations per second.  If the rate is limited (see s, f) you will see rate> indicating we can run faster.
we are using a heap size of 2^8 x 2^8 with 61286 entries and we need to check 16841 cells for the next generation.
window(2) tells us autotracking is enabled ( t ) and it is using 2 generations for tracking info.  
window(-2) would tell us autotracking is disabled, use cursor keys to move window or t to restart autotracking
the last two numbers are the window position.

    s, f        : limits the generation rate, s halves the rate and f doubles it (when limited you will see rate>xxx/s )
    +, -        : only show every nth generation.  + doubles n, - halves n (generation xxxx(n) ...)
    cursor keys : allow manual positioning of the window using cursor keys (window(-autotracking generations) ...)
    t           : if manual tracking is enabled, disable it, if disabled toggle the number of generations used for autotracking
    esc, q      : will exit the program

The algorithm used here was developed in the late 70s or early 80s.  I first implemented it on an OSI superboard II using 
Basic and 6502 assembly.  This was before algorithms like hash life were discovered.  I've been using it when I want to learn a 
new language environment.  This version was started to learn basic zig, then valgrind came into the picture and let me get a  
better idea of how zig compiles and where the program was spending its time.  

This algorithm is nothing special by todays standards, it does not use SIMD or the GPU for speed.  It does use threading when
updating the display and for the generation update.  Its been a good learning tool.
