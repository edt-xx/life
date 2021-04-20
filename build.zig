const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    
    const exe = b.addExecutable("life", "src/life.zig");    
    
    exe.addBuildOption([]const u8,"pattern",p_850_000m);
    
//  p_95_206_595m       // pattern used in benchmarking (corder ship, non symetric, terminating)
//  p_19_659_494m       // symetric quasi-crystal coorder ship reaction
//  p_1_700_000m        // my current favorite pattern, use cursor keys and watch at -n,-n where n<1400 or so.
//  p_850_000m          // at about 450k a glider starts towards the engines, at 650k it destroys them, at 750k ash is penitrated
//  p_max               // fastest growth possible
//  p_52513m            // longest running mesuthelah currently known (march 2021)
    
    exe.addBuildOption(u32,"Threads",7);                        // threads excluding display update thread
    exe.addBuildOption(u32,"staticSize",4);                     // size of static tiles, must be a power of 2 (4 is optimal)
    
    exe.addPackagePath("zbox","../zbox/src/box.zig");
    exe.linkSystemLibrary("pthread");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    //exe.setBuildMode(std.builtin.Mode.ReleaseFast);       // to hard code ReleaseFast...
    exe.setOutputDir(".");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

// add rle encoded patterns 

const p_chaotic1 =
\\9bobo$8bo$9bo2bo$11b3o8$2bo$2ob2o$2ob2o$2o$2b2obo$3bo2bo$3bo2bo$4b2o!
;

const p_chaotic2 =
\\23bo$21b2ob2o$21b2ob2o$21b2o$23b2obo$24bo2bo$24bo2bo$25b2o11$bobo$o$bo2bo$3b3o!
;                       
 
// nonsymetric quasicrystal switch engine reaction
// by 1300k geneations the switch engines have be stopped, the residual gliders keep the ash active till about 1700k.
const p_1_700_000m =
\\7bobo$6bo$7bo2bo$9b3o7$3o2$bo$b2o25b2o$2b2o24bo$o2b2o!
;

// another nonsymetric quasicrystal switch engine reaction
// at about generation 450k a glider starts towards the switch engines, at about 650k it stops them.  At about 750k
// the residual gliders break thru the ash and the last of them exit the ash around 850k
const p_850_000m =
\\7bobo$6bo$7bo2bo$9b3o7$3o2$bo$b2o$2b2o$o2b2o6$38b2o$38bo!
;

const p_95_206_595m =   // nonsymetric quasicrystal coorder ship reaction
//x = 16, y = 16, rule = 23/3
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

// When we hit memory limits, this will abort - pop grows very fast.
const p_max =
\\18bo8b$17b3o7b$12b3o4b2o6b$11bo2b3o2bob2o4b$10bo3bobo2bobo5b$10bo4bobo
\\bobob2o2b$12bo4bobo3b2o2b$4o5bobo4bo3bob3o2b$o3b2obob3ob2o9b2ob$o5b2o
\\5bo13b$bo2b2obo2bo2bob2o10b$7bobobobobobo5b4o$bo2b2obo2bo2bo2b2obob2o
\\3bo$o5b2o3bobobo3b2o5bo$o3b2obob2o2bo2bo2bob2o2bob$4o5bobobobobobo7b$
\\10b2obo2bo2bob2o2bob$13bo5b2o5bo$b2o9b2ob3obob2o3bo$2b3obo3bo4bobo5b4o
\\$2b2o3bobo4bo12b$2b2obobobobo4bo10b$5bobo2bobo3bo10b$4b2obo2b3o2bo11b$
\\6b2o4b3o12b$7b3o17b$8bo!
;

const p_19_659_494m =                    // symetric quasicrystal coorder ship reaction
\\bboooboobobboooooooobboboobooobb$
\\bbobboobbbobobbbbbbobobbboobbobb$
\\ooobbbbboobbobboobbobboobbbbbooo$
\\obbbbooooobbboboobobbbooooobbbbo$
\\obbbobbobobboobbbboobbobobbobbbo$
\\bobobobboobbboboobobbboobbobobob$
\\oobobbbbbbobboooooobbobbbbbboboo$
\\obboobbboobooobbbboooboobbboobbo$
\\bbooboboooobooobbooobooooboboobb$
\\oboooobooobbboboobobbboooboooobo$
\\bobbbbobobbbobbbbbbobbbobobbbbob$
\\bbbbbbbobbbbbobbbbobbbbbobbbbbbb$
\\ooobobboobobooboobooboboobbobooo$
\\obboooooooboooooooooobooooooobbo$
\\obbbbbobobbbbobbbbobbbbobobbbbbo$
\\obooboobbobboobbbboobbobbooboobo$
\\obooboobbobboobbbboobbobbooboobo$
\\obbbbbobobbbbobbbbobbbbobobbbbbo$
\\obboooooooboooooooooobooooooobbo$
\\ooobobboobobooboobooboboobbobooo$
\\bbbbbbbobbbbbobbbbobbbbbobbbbbbb$
\\bobbbbobobbbobbbbbbobbbobobbbbob$
\\oboooobooobbboboobobbboooboooobo$
\\bbooboboooobooobbooobooooboboobb$
\\obboobbboobooobbbboooboobbboobbo$
\\oobobbbbbbobboooooobbobbbbbboboo$
\\bobobobboobbboboobobbboobbobobob$
\\obbbobbobobboobbbboobbobobbobbbo$
\\obbbbooooobbboboobobbbooooobbbbo$
\\ooobbbbboobbobboobbobboobbbbbooo$
\\bbobboobbbobobbbbbbobobbboobbobb$
\\bboooboobobboooooooobboboobooobb!
;

const p_5_931_548m =                     // symetric quasicrystal coorder ship reaction
\\obbbbooboobbooobbooobbooboobbbbo$
\\bbbobobobbbobbboobbbobbbobobobbb$
\\bbbobbbobbboooboobooobbbobbbobbb$
\\booboobboboobooooooboobobbooboob$
\\bbboobbboobbbbboobbbbboobbboobbb$
\\oobobbbbboooboooooobooobbbbboboo$
\\obbbbbbobboboobooboobobbobbbbbbo$
\\boobbboobobooboooobooboboobbboob$
\\obboobbboobbooobbooobboobbboobbo$
\\obbboobooobbooobbooobboooboobbbo$
\\bbboboobbbbbobboobbobbbbboobobbb$
\\booobobobbbobobbbbobobbbobobooob$
\\obobbboooooboobbbboobooooobbbobo$
\\obooboobooboooobbooooboobooboobo$
\\obbobobooobbboboobobbbooobobobbo$
\\booooooobbobbbobbobbbobbooooooob$
\\booooooobbobbbobbobbbobbooooooob$
\\obbobobooobbboboobobbbooobobobbo$
\\obooboobooboooobbooooboobooboobo$
\\obobbboooooboobbbboobooooobbbobo$
\\booobobobbbobobbbbobobbbobobooob$
\\bbboboobbbbbobboobbobbbbboobobbb$
\\obbboobooobbooobbooobboooboobbbo$
\\obboobbboobbooobbooobboobbboobbo$
\\boobbboobobooboooobooboboobbboob$
\\obbbbbbobboboobooboobobbobbbbbbo$
\\oobobbbbboooboooooobooobbbbboboo$
\\bbboobbboobbbbboobbbbboobbboobbb$
\\booboobboboobooooooboobobbooboob$
\\bbbobbbobbboooboobooobbbobbbobbb$
\\bbbobobobbbobbboobbbobbbobobobbb$
\\obbbbooboobbooobbooobbooboobbbbo!
;

const p_2_230_963m =                     // symetric quasicrystal coorder ship reaction
\\obobbobbboooboobboobooobbbobbobo$
\\bboobooboboooooooooooobobooboobb$
\\oobboooboooboooooooobooobooobboo$
\\bobbobbboboobboooobboobobbbobbob$
\\bboobboobbbbbboooobbbbbboobboobb$
\\ooobbboboobbbobbbbobbboobobbbooo$
\\boobooobooboboooooobobooboooboob$
\\bbbbobbbbboobbboobbboobbbbbobbbb$
\\boooboobboooobboobboooobboobooob$
\\obobboobobbbbobbbbobbbboboobbobo$
\\oooobbboobooobobboboooboobbboooo$
\\oobobbooobobbbbbbbbbbobooobboboo$
\\boobbbbbobobooobbooobobobbbbboob$
\\ooobboobbobbobbbbbbobbobboobbooo$
\\ooooobobbboboboooobobobbbobooooo$
\\boooobooobbbbboooobbbbboooboooob$
\\boooobooobbbbboooobbbbboooboooob$
\\ooooobobbboboboooobobobbbobooooo$
\\ooobboobbobbobbbbbbobbobboobbooo$
\\boobbbbbobobooobbooobobobbbbboob$
\\oobobbooobobbbbbbbbbbobooobboboo$
\\oooobbboobooobobboboooboobbboooo$
\\obobboobobbbbobbbbobbbboboobbobo$
\\boooboobboooobboobboooobboobooob$
\\bbbbobbbbboobbboobbboobbbbbobbbb$
\\boobooobooboboooooobobooboooboob$
\\ooobbboboobbbobbbbobbboobobbbooo$
\\bboobboobbbbbboooobbbbbboobboobb$
\\bobbobbboboobboooobboobobbbobbob$
\\oobboooboooboooooooobooobooobboo$
\\bboobooboboooooooooooobobooboobb$
\\obobbobbboooboobboobooobbbobbobo!
;

//#N Caber tosser 1
//#O Dean Hickerson
//#C A smaller version of the first caber tosser found. Uses a 7-engine 
//#C Cordership. Originally found on May 1, 1991, smaller form found on 
//#C September 2, 1994.
//#C www.conwaylife.com/wiki/index.php?title=Caber_tosser_1
//x = 145, y = 114, rule = 23/3
const caber_tosser = 
\\31bo113b$32bob2obobo105b$26b3o3b4o3bo105b$32bo2b2ob2o105b$31bo113b$29b
\\3o113b$29b3o17b2o94b$49bo95b3$14bo130b$14bo130b$14bo130b$17b2o126b$17b
\\2o38b2o86b$12bo3b3o38bo87b$13b3o129b$14bo130b$13b2o130b$13b3o129b$15bo
\\8bo120b$13bo8b2ob2o118b$15bo9b2o7bo30b2o78b$13b3o6b3o10b2o28bo79b$24bo
\\3bo5b2o109b$23bo3bo117b$5bo18b3obo116b$6bob2obobo12b2o117b$3o3b4o3bo
\\11bobo117b$6bo2b2ob2o12bo26b2o2bo87b$5bo19b2o29bobo86b$3b3o20bo28bo89b
\\$3b3o21bo117b$57b2o86b2$58b2o85b$57bo87b$55b2ob2o85b$58b2o85b$43bo12bo
\\88b$43bo101b$45bo5bo93b$44bo6bobo91b$43bo3bo2bo94b$3b2o39bo2bobob2o92b
\\$3bo45bob2o92b7$11b2o132b$11bo133b2$27b2o2bo113b$30bobo112b$29bo115b2$
\\31b2o112b$19b2o124b$19bo12b2o111b$31bo113b$29b2ob2o111b$32b2o111b$30bo
\\114b3$27b2o116b$27bo117b14$122bo22b$121bobo21b$121b2obo7b2o11b$121b2ob
\\2o6bobo10b$121b2obob3o6bo9b$111b2o8bobo2bo2bo2bo2bo8bo$110bobo9bo4b2o
\\6bo7b2o$110bo21bobo10b$109b2o21b2o11b6$93b2o15bo34b$94bo15bo34b$110bo
\\34b2$81bo22b2o39b$81bobo20bo40b$70b2o12b2o9b2o5bobo20bobo17b$70bo13b2o
\\9bo6b2o19bo3bo17b$84b2o6b2o17b2o10bo12b2o7b$81bobo7b3o17bo2bo7bo14bo7b
\\$81bo10b2o21bo7bo21b$95bo19bo7bo3bo17b$95b2o18bo9bobo17b$104b2o5bo2bo
\\30b$103bobo5b2o32b$103bo41b$102b2o!
;

