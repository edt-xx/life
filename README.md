Author Ed Tomlinson (2021), released under the GPL V3 license.

This program is an implementation of life as created by John H. Conway.  

change the pattern to one of the included patterns and rebuild, 

zig build-exe -O ReleaseFast --pkg-begin zbox ../zbox/src/box.zig --pkg-end life.zig

zbox can be cloned from: https://github.com/jessrud/zbox.git

A title line with:

generation 299(2) population 7713(1179) births 317 deaths 328 rate 260/s  heap(8) 6126/1681  window(2) -112,-187

generation 299(2) say it is generation 299 and the (2) says we are showing every second generation (see +, -)
population is 7713 cells with (1179) cells considered active (birth or death near the cell)
birth and deaths as per the rules of life ( B3/S23 in life terms )
rate in generations per second.  If you see rate> then life can go faster (see s, f)
heap is of size of 2^8 x 2^8 with 6126 entries and we need to check 1681 cells for the next generation.
window(2) tells us autotracking is enabled ( t ) and it is using 2 generations for tracking info.  
window(-2) would tell us autotracking is disabled, use cursor keys to move window or t to restart autotracking
the last two numbers are the window position.

s, f        : limits the generation rate, s halves the rate and f doubles it (when limited you will see rate>xxx/s )
+, -        : only show every nth generation.  + doubles n, - halves n (generation xxxx(n) ...)
cursor keys : allow manual positioning of the window using cursor keys (window(-autotracking generations) ...)
t           : if manual tracking is enabled, disable it, if disabled toggle the number of generations used for autotracking
esc, q      : will exit the program

The algorithm used here was developed in the late 70s or early 80s.  I first implemented it on an OSI superboard II
using Basic and 6502 assembly.  This was before algorythms like hash life were discovered.  I've been using it when 
I want to learn a new language environment.  This version was started to learn basic zig, then valgrind came into the 
picture and let me get a  better idea of how zig compiles and where the program was spending its time.

This algorythm is nothing special by todays standards, its not super fast, it does not use SIMD or the GPU for speed, 
nor does it make much use of multiple CPUs.  As a learning exercise its been interesting though.



