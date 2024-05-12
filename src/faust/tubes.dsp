declare name "phaser";
declare version "0.0";
declare author "JOS, revised by RM";
declare description "Phaser demo application.";

import("stdfaust.lib");

process = amplifier;

amplifier = environment {

    amplifier_process = component("tubes.lib").T1_12AX7 : *(preamp):
      fi.lowpass(1,6531.0) : component("tubes.lib").T2_12AX7 : *(preamp):
      fi.lowpass(1,6531.0) : component("tubes.lib").T3_12AX7 : *(gain) with {
      preamp = hslider("Pregain",-6,-20,20,0.1) : ba.db2linear : si.smooth(0.999);
      gain  = hslider("Gain", -6, -20.0, 20.0, 0.1) : ba.db2linear : si.smooth(0.999);
    };
}.amplifier_process;