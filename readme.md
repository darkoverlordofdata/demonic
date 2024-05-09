# Dark Overlord of Data's Demonic Practice Amp

A practice guitar amp that runs in your browser

Written for my Chromebook

built and tested using [Faust IDE](https://faustide.grame.fr/index.html)

to install/run visit https://darkoverlordofdata.com/demonic

This is not a modeling amp. You cannot select tubes and cabinets. Though there are functions in faust to do this, the convolution math required is slow in faust, and in the browser, it's slow enough to be prohibitive, there is just too much latency.

So we have a mythical amp, called the Demonic. It's based on faust example code.
I'm triming out the over-abundant dials to match real world products.

Stage 1 is a clean pre-amp, that allows you to adjust tone and volume.
Stage 2 is PowerAmp, wich allows adjusting feedback and presence.
Stage 2 is Temper, an alternate warm distortion amp.
Effect 1 is Fuzz
Effect 2 is Phaser
Effect 3 is Flanger
Effect 4 is Chorus
Effect 5 is Reverb





At present you can adjust tone, and select Amplifier, Flanger, Chorus, and Reverb. You can play with knobs and dials.
My main use case is that I can practice along side youtube as well as various tablature playback sites such as ultimate-guitar:

todo
* visualization panel?
* add metronome

### compatability

* Inspiron - XUbuntu 22.04  - Chrome Browser / Firefox / Edge
* Inspiron - ChromeOS Flex 
* Chromebook - Lenovo Duet 2
* Android Phone (LG K51)

Tested with Behringer Guitar Link USB Interface UC6102
On linux, disable jackd if running, it will work better

USBC to USB converter required for phone. It also loads slow.

### usage

![alt use-case](https://github.com/darkoverlordofdata/demonic/blob/main/use-case-1.png?raw=true)

### icon credit

https://icon-library.com/icon/guitar-amp-icon-4.html



### license
BSD-2-Clause License

Copyright (c) 2021 Bruce Davidson &lt;darkoverlordofdata@gmail.com&gt;



