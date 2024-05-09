//-------------------------`(dm.)flanger_demo`---------------------------
// Flanger effect application.
//
// #### Usage
//
// ```
// _,_ : flanger_demo : _,_
// ```
//------------------------------------------------------------
declare flanger_demo author "Julius O. Smith III";
declare flanger_demo licence "MIT";

flanger_demo = ba.bypass2(fbp,flanger_stereo_demo)
with{
    flanger_group(x) = vgroup("FLANGER
        [tooltip: Reference: https://ccrma.stanford.edu/~jos/pasp/Flanging.html]", x);
    meter_group(x) = flanger_group(hgroup("[0]", x));
    ctl_group(x) = flanger_group(hgroup("[1]", x));
    del_group(x) = flanger_group(hgroup("[2] Delay Controls", x));
    lvl_group(x) = flanger_group(hgroup("[3]", x));

    fbp = meter_group(checkbox("[0] Bypass    [tooltip: When this is checked, the flanger
        has no effect]"));
    invert = meter_group(checkbox("[1] Invert Flange Sum"));

    // FIXME: This should be an amplitude-response display:
    flangeview = lfor(freq) + lfol(freq) : meter_group(hbargraph("[2] Flange LFO
        [style: led] [tooltip: Display sum of flange delays]", -1.5,+1.5));

    flanger_stereo_demo(x,y) = attach(x,flangeview),y :
        *(level),*(level) : pf.flanger_stereo(dmax,curdel1,curdel2,depth,fb,invert);

    lfol = os.oscrs;
    lfor = os.oscrc;

    dmax = 2048;
    dflange = 0.001 * ma.SR *
        del_group(hslider("[1] Flange Delay [unit:ms] [style:knob]", 10, 0, 20, 0.001));
    odflange = 0.001 * ma.SR *
    del_group(hslider("[2] Delay Offset [unit:ms] [style:knob]", 1, 0, 20, 0.001));
    freq   = ctl_group(hslider("[1] Speed [unit:Hz] [style:knob]", 0.5, 0, 10, 0.01));
    depth  = ctl_group(hslider("[2] Depth [style:knob]", 1, 0, 1, 0.001));
    fb     = ctl_group(hslider("[3] Feedback [style:knob]", 0, -0.999, 0.999, 0.001));
    level  = lvl_group(hslider("Flanger Output Level [unit:dB]", 0, -60, 10, 0.1)) :
        ba.db2linear;
    curdel1 = odflange+dflange*(1 + lfol(freq))/2;
    curdel2 = odflange+dflange*(1 + lfor(freq))/2;
};
