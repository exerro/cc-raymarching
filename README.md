
# ComputerCraft Raymarching Demo

This is a one-file raymarching demo, showing off ~real-time 3D rendering using
sphere tracing to render 3D geometry.

![](https://i.imgur.com/HXbwXNt.png)

You can move around using WASD + space + shift, and turn using arrow keys.

It's not the most readable code due to some heavy micro-optimisation, and
there's definitely no use for this with libraries. The main purpose is to make
something pretty looking and see how performant something like this can be.

At low resolutions, ~50x20, it can render in real time. At higher resolutions,
~200x75, it seriously struggles to get a frame out every second. This is kind of
understandable once you appreciate what's going on:

* Each pixel is shaded by performing a ray marching step capped at 100
  iterations, for each subpixel. At 200x75 resolution, this is up to 9 million
  distance function samples per frame. Once a collision is detected, the normal
  is estimated, and the subpixel is lit based on the dot product of its normal
  and the global direction.
* The whole framebuffer is mapped to a macro-pixel format, where groups of
  subpixels are reduced to two target colours which are registered in a global
  colour set.
* The colour set is used to quantize the fully dynamic colour values into 16
  approximations of the whole framebuffer, at which point the macro-pixel
  framebuffer is mapped from linear colour values to colour palette indices.
* Each line of the framebuffer is blitted to the screen.

Some things would be significantly quicker with a static palette, or with some
temporal optimisation for palette generation, but I'll leave that to future me
to have fun with :)
