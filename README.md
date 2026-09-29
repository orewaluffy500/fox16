# Fox16

This is my first large ZIG project.

I tried to make a CPU emulator, But I don't know shi about CPUs so it's kind of a CPU emulator simulator.

Sorry if you were here to find some LC-3 thing or something.

While developing this project I learned a LOT about ZIG, I used to hate ZIG for it's constantly changing standard library but now I've come to actually like it,

Not love it still (i still dont like managing ownership).

The CPU has 128 registers and a 128 KB stack.
It's 16-bit meaning the minimum value for an integer is 0 and the maximum is 65,536

I wrote some docs which just explain how to write raw machine code for it. I'm still developing the assembler.

The assembler is definitely the most fun part because this is the first time i've made a lexer and stuff in something other than C#.