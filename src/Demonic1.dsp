declare name "Demonic";
declare version "0.9.3-beta";
declare author "darkoverlordofdata";
declare description "Practice Amp";
declare license "BSD-2-Clause";
declare copyright "(c)DarkOverlordOfData 2021";
/*

________                               .__        
\______ \   ____   _____   ____   ____ |__| ____  
 |    |  \_/ __ \ /     \ /  _ \ /    \|  |/ ___\ 
 |    `   \  ___/|  Y Y  (  <_> )   |  \  \  \___ 
/_______  /\___  >__|_|  /\____/|___|  /__|\___  >
        \/     \/      \/            \/        \/ 

*/
import("stdfaust.lib");
import("music.lib");


process = preamp
	: fuzz
	: phaser
	: flanger
	: chorus
    : reverb
	:> amplifier
	: temper;

//======================================================
//
//	amplifier
//
//		based on https://github.com/micbuffa/FaustPowerAmp  
//
//======================================================
amplifier = environment {

	// Modified version of https://github.com/creativeintent/temper/blob/master/Dsp/temper.dsp
	// Adapted for PowerAmp simulation (addition of presence filter, param adaptation, small changes...)

	// Distortion parameters
	pdrive = hslider("[0] Drive gain[style:knob]", 4.0, -10.0, 10.0, 0.001) : si.smooth(0.995);
	psat = hslider("[1] Saturation dry wet[style:knob]", 1.0, 0.0, 1.0, 0.001) : si.smooth(0.995);
	pcurve = hslider("[2] Curve k[style:knob]", 1.0, 0.1, 4.0, 0.001) : si.smooth(0.995);

	// Output parameters
	plevel = hslider("[3] Level[style:knob]", -3, -24, 24, 1) : ba.db2linear : si.smooth(0.995);

	// A fairly standard wave shaping curve; we use this to shape the input signal
	// before modulating the filter coefficients by this signal. Which shaping curve
	// we use here is pretty unimportant; as long as we can introduce higher harmonics,
	// the coefficient modulation will react. Which harmonics we introduce here seems
	// to affect the resulting sound pretty minimally.
	//
	// Also note here that we use an approximation of the `tanh` function for computational
	// improvement. See `https://www.musicdsp.org/showone.php?id=238`.
	tanh(x) = x * (27 + x * x) / (27 + 9 * x * x);
	transfer(x) = tanh(pcurve * x) / tanh(pcurve);

	// The allpass filter is stable for `|m(x)| <= 1`, but should not linger
	// near +/-1.0 for very long. We therefore clamp the driven signal with a tanh
	// function to ensure smooth coefficient calculation. We also here introduce
	// a modulated DC offset in the signal before the curve.
	drive(x) = x : *(pdrive) : +(fol(x)) : max(-3) : min(3) 
	with {
		fol = an.amp_follower(0.04);
	};

	// Our modulated filter is an allpass with coefficients governed by the input
	// signal applied through our wave shaper. Before the filter, we mix the dry
	// input signal with the raw waveshaper output according to the `psat` parameter.
	// Note the constant gain coefficient on the waveshaper; that number is to offset
	// the global gain from the waveshaper to make sure the shaping process stays
	// under unity gain. The maximum differential gain of the waveshaper can be found
	// by evaluating the derivative of the transfer function at x0 where x0 is the
	// steepest part of the slope. Here that number is ~4, so we multiply by ~1/4.
	waveshaper(x) = x <: _, tap(x) : *(1.0 - psat), *(psat) : + : fi.tf1(b0(x), b1(x), a1(x)) 
	with {
		b0(x) = m(x);
		b1(x) = 1.0;
		a1(x) = m(x);
		m(x) = drive(x) : transfer : *(0.24);
		tap(x) = m(x);
	};

	// A fork of the `tf2s` function from the standard filter library which uses a
	// smoothing function after the `tan` computation to move that expensive call
	// outside of the inner loop of the filter function.
	tf2s(b2,b1,b0,a1,a0,w1) = fi.tf2(b0d,b1d,b2d,a1d,a2d)
	with {
		c   = 1/tan(w1*0.5/ma.SR) : si.smooth(0.995); // bilinear-transform scale-factor
		csq = c*c;
		d   = a0 + a1 * c + csq;
		b0d = (b0 + b1 * c + b2 * csq)/d;
		b1d = 2 * (b0 - b2 * csq)/d;
		b2d = (b0 - b1 * c + b2 * csq)/d;
		a1d = 2 * (a0 - csq)/d;
		a2d = (a0 - a1*c + csq)/d;
	};

	// A fork of the `resonlp` function from the standard filter library which uses
	// a local `tf2s` implementation.
	resonlp(fc,Q,gain) = tf2s(b2,b1,b0,a1,a0,wc)
	with {
		wc = 2*ma.PI*fc;
		a1 = 1/Q;
		a0 = 1;
		b2 = 0;
		b1 = 0;
		b0 = gain;
	};



	feedbackCircuit = presence:*(gainNFL) 
	with {
		p1gain = hslider("[4] Presence[name:p1Gain][style:knob]", 0, -15, 15, 0.1);
		wa = library("webaudio.lib");
		presence = wa.peaking2(2000, p1gain, 1, 1) : wa.peaking2(4000, p1gain, 1, 1);
		gainNFL = hslider("Negative gain[name:Level][style:knob]", -0.4, -0.8, 1, 0.01) :  si.smoo;
	};

	// Our main processing block.
	main = *(masterVolume) :(+ : waveshaper : fi.dcblocker) ~ feedbackCircuit : gain 
	with {
		// This explicit gain multiplier of 4.0 accounts for the loss of gain that
		// occurs from oversampling by a factor of 2, and for the loss of gain that
		// occurs from the prefilter and modulation step. Then we apply the output
		// level parameter.
		gain = *(4.0) : *(plevel);
		masterVolume = hslider("[5] Master Volume[name:MV][style:knob]", 1, 0, 4, 0.1)  : si.smoo;
	};

	// And the overall process declaration.
	poweramp =  main;

	finalPWAMono = hgroup("[1] PowerAmp",ba.bypass_fade(ma.SR/10, checkbox("[6] Bypass"), poweramp)); 

	amp_process = finalPWAMono;

}.amp_process;


//======================================================
//
//	flanger
//  
//		flange effect
//
//======================================================
flanger = environment {

    flanger_group(x) = hgroup("[5] Flanger ", x);

    //level			= hslider("level", 1, 0, 1, 0.01);
    level           = 1;
    freq			= flanger_group(hslider("[0] Freq [style:knob]", 2, 0, 10, 0.01));
    //dtime			= hslider("delay", 0.002, 0, 0.04, 0.001);
    dtime           = 0.002;
    depth			= flanger_group(hslider("[1] Depth [style:knob]", 0.5, 0, 1, 0.001));
    feedback		= flanger_group(hslider("[2] Feedback [style:knob]", 0.1, 0, 1, 0.001));
    //stereo			= hslider("stereo", 1, 0, 1, 0.001);
    stereo          = 1;
    byp 	        = flanger_group(1-int(checkbox("[3] Enable")));

    tblosc(n,f,freq,mod)	= (1-d)*rdtable(n,wave,i&(n-1)) +
                d*rdtable(n,wave,(i+1)&(n-1))
    with {
        wave		= time*(2.0*PI)/n : f;
        phase		= freq/SR : (+ : decimal) ~ _;
        modphase	= decimal(phase+mod/(2*PI))*n;
        i		= int(floor(modphase));
        d		= decimal(modphase);
    };

    triangle(t)		= ((0<=t) & (t<=PI))*((2*t-PI)/PI) +
                ((PI<t) & (t<=2*PI))*((3*PI-2*t)/PI);

    flanger(dtime,freq,level,feedback,depth,phase,x)
                = (x+(loop(x)*level))/(1+level)
    with {
        t	= SR*dtime/2*(1+depth*tblosc(1<<16, triangle, freq, phase));
        loop	= (+ : fdelay(1<<16, t)) ~ *(feedback);
    };

    flanger_process			= ba.bypass2(byp, (left, right))
    with {
        left	= flanger(dtime,freq,level,feedback,depth,0);
        right	= flanger(dtime,freq,level,feedback,depth,stereo*PI);
    };
}.flanger_process;


//======================================================
//
//	chorus
//
//======================================================

/* Stereo chorus. */
//https://github.com/grame-cncm/faust/blob/master-dev/tools/faust2pd/examples/synth/chorus.dsp

// declare name "chorus -- stereo chorus effect";
// declare author "Albert Graef";
// declare version "1.0";

// import("music.lib");
// process = chorus;

chorus = environment {
	chorus_group(x) = hgroup("[6] Chorus ", x);

    level	= chorus_group(hslider("[0] Level [style:knob]", 0.5, 0, 1, 0.01));
    freq	= chorus_group(hslider("[1] Freq [style:knob]", 3, 0, 10, 0.01));
    dtime	= chorus_group(hslider("[2] Delay [style:knob]", 0.025, 0, 0.2, 0.001));
    depth	= chorus_group(hslider("[3] Depth [style:knob]", 0.02, 0, 1, 0.001));
	byp 	= chorus_group(1-int(checkbox("[4] Enable")));



    tblosc(n,f,freq,mod)	= (1-d)*rdtable(n,wave,i&(n-1)) +
                d*rdtable(n,wave,(i+1)&(n-1))
    with {
        wave	 	= time*(2.0*PI)/n : f;
        phase		= freq/SR : (+ : decimal) ~ _;
        modphase	= decimal(phase+mod/(2*PI))*n;
        i		= int(floor(modphase));
        d		= decimal(modphase);
    };

    chorus(dtime,freq,depth,phase,x)
                = x+level*fdelay(1<<16, t, x)
    with {
        t		= SR*dtime/2*(1+depth*tblosc(1<<16, sin, freq, phase));
    };

    chorus_process			= ba.bypass2(byp, (left, right))
    with {
        left		= chorus(dtime,freq,depth,0);
        right		= chorus(dtime,freq,depth,PI/2);
    };
}.chorus_process;

//======================================================
//
//	Freeverb
//
// 		Faster version using fixed delays (20% gain)
//
//======================================================
reverb = environment {


    reverb_group(x) = hgroup("[7] Reverb",x);

	// import("stdfaust.lib");

	// declare name        "freeverb";
	// declare version     "1.0";
	// declare author      "Grame";
	// declare license     "BSD";
	// declare copyright   "(c) GRAME 2006 and MoForte Inc. 2017";
	// declare reference   "https://ccrma.stanford.edu/~jos/pasp/Freeverb.html";

	// Constant Parameters
	//--------------------

	fixedgain   = 0.015; //value of the gain of fxctrl
	scalewet    = 3.0;
	scaledry    = 2.0;
	scaledamp   = 0.4;
	scaleroom   = 0.28;
	offsetroom  = 0.7;
	initialroom = 0.5;
	initialdamp = 0.5;
	initialwet  = 1.0/scalewet;
	initialdry  = 0;
	initialwidth= 1.0;
	initialmode = 0.0;
	freezemode  = 0.5;
	stereospread= 23;
	allpassfeed = 0.5; //feedback of the delays used in allpass filters

	// Filter Parameters
	//------------------

	combtuningL1    = 1116;
	combtuningL2    = 1188;
	combtuningL3    = 1277;
	combtuningL4    = 1356;
	combtuningL5    = 1422;
	combtuningL6    = 1491;
	combtuningL7    = 1557;
	combtuningL8    = 1617;

	allpasstuningL1 = 556;
	allpasstuningL2 = 441;
	allpasstuningL3 = 341;
	allpasstuningL4 = 225;

	// Control Sliders
	//--------------------
	// Damp : filters the high frequencies of the echoes (especially active for great values of RoomSize)
	// RoomSize : size of the reverberation room
	// Dry : original signal
	// Wet : reverberated signal

	dampSlider      = reverb_group(hslider("[0] Damp [midi:ctrl 3] [style:knob]",0.5, 0, 1, 0.025))*scaledamp;
	roomsizeSlider  = reverb_group(hslider("[1] RoomSize [midi:ctrl 4] [style:knob]", 0.5, 0, 1, 0.025))*scaleroom + offsetroom;
	wetSlider       = reverb_group(hslider("[2]] Wet [midi:ctrl 79] [style:knob]", 0.3333, 0, 1, 0.025));
	combfeed        = roomsizeSlider;

	// Comb and Allpass filters
	//-------------------------

	allpass(dt,fb) = (_,_ <: (*(fb),_:+:@(dt)), -) ~ _ : (!,_);

	comb(dt, fb, damp) = (+:@(dt)) ~ (*(1-damp) : (+ ~ *(damp)) : *(fb));

	// Reverb components
	//------------------

	monoReverb(fb1, fb2, damp, spread)
		= _ <:  comb(combtuningL1+spread, fb1, damp),
			comb(combtuningL2+spread, fb1, damp),
			comb(combtuningL3+spread, fb1, damp),
			comb(combtuningL4+spread, fb1, damp),
			comb(combtuningL5+spread, fb1, damp),
			comb(combtuningL6+spread, fb1, damp),
			comb(combtuningL7+spread, fb1, damp),
			comb(combtuningL8+spread, fb1, damp)
		+>
			allpass (allpasstuningL1+spread, fb2)
		:   allpass (allpasstuningL2+spread, fb2)
		:   allpass (allpasstuningL3+spread, fb2)
		:   allpass (allpasstuningL4+spread, fb2)
		;

	stereoReverb(fb1, fb2, damp, spread)
		= + <: 	monoReverb(fb1, fb2, damp, 0), monoReverb(fb1, fb2, damp, spread);

	// fxctrl : add an input gain and a wet-dry control to a stereo FX
	//----------------------------------------------------------------

	fxctrl(g,w,Fx) =  _,_ <: (*(g),*(g) : Fx : *(w),*(w)), *(1-w), *(1-w) +> _,_;

	rbp = 1-int(reverb_group(checkbox("[3] Enable")));

	// Freeverb
	//---------
	freeverb = fxctrl(fixedgain, wetSlider, stereoReverb(combfeed, allpassfeed, dampSlider, stereospread));

	freeverb_process = ba.bypass2(rbp,freeverb);

}.freeverb_process;


preamp = environment {
	import("math.lib");
	import("music.lib");

	/* Fixed bass and treble frequencies. You might want to tune these for your
	setup. */

	bass_freq	= 300;
	treble_freq	= 1200;

	/* Bass and treble gain controls in dB. The range of +/-20 corresponds to a
	boost/cut factor of 10. */

	bass_gain	= hslider("Bass", 0, -20, 20, 0.1);
	treble_gain	= hslider("Treble", 0, -20, 20, 0.1);

	/* Gain and balance controls. */

	gain		= 0.0; //db2linear(hslider("gain", 0, -96, 96, 0.1));
	bal		= 0.0;//= hslider("balance", 0, -1, 1, 0.001);

	/* Balance a stereo signal by attenuating the left channel if balance is on
	the right and vice versa. I found that a linear control works best here. */

	balance		= *(1-max(0,bal)), *(1-max(0,0-bal));

	/* Generic biquad filter. */

	filter(b0,b1,b2,a0,a1,a2)	= f : (+ ~ g)
	with {
		f(x)	= (b0/a0)*x+(b1/a0)*x'+(b2/a0)*x'';
		g(y)	= 0-(a1/a0)*y-(a2/a0)*y';
	};

	/* Low and high shelf filters, straight from Robert Bristow-Johnson's "Audio
	EQ Cookbook", see http://www.musicdsp.org/files/Audio-EQ-Cookbook.txt. f0
	is the shelf midpoint frequency, g the desired gain in dB. S is the shelf
	slope parameter, we always set that to 1 here. */

	low_shelf(f0,g)		= filter(b0,b1,b2,a0,a1,a2)
	with {
		S  = 1;
		A  = pow(10,g/40);
		w0 = 2*PI*f0/SR;
		alpha = sin(w0)/2 * sqrt( (A + 1/A)*(1/S - 1) + 2 );

		b0 =    A*( (A+1) - (A-1)*cos(w0) + 2*sqrt(A)*alpha );
		b1 =  2*A*( (A-1) - (A+1)*cos(w0)                   );
		b2 =    A*( (A+1) - (A-1)*cos(w0) - 2*sqrt(A)*alpha );
		a0 =        (A+1) + (A-1)*cos(w0) + 2*sqrt(A)*alpha;
		a1 =   -2*( (A-1) + (A+1)*cos(w0)                   );
		a2 =        (A+1) + (A-1)*cos(w0) - 2*sqrt(A)*alpha;
	};

	high_shelf(f0,g)	= filter(b0,b1,b2,a0,a1,a2)
	with {
		S  = 1;
		A  = pow(10,g/40);
		w0 = 2*PI*f0/SR;
		alpha = sin(w0)/2 * sqrt( (A + 1/A)*(1/S - 1) + 2 );

		b0 =    A*( (A+1) + (A-1)*cos(w0) + 2*sqrt(A)*alpha );
		b1 = -2*A*( (A-1) + (A+1)*cos(w0)                   );
		b2 =    A*( (A+1) + (A-1)*cos(w0) - 2*sqrt(A)*alpha );
		a0 =        (A+1) - (A-1)*cos(w0) + 2*sqrt(A)*alpha;
		a1 =    2*( (A-1) - (A+1)*cos(w0)                   );
		a2 =        (A+1) - (A-1)*cos(w0) - 2*sqrt(A)*alpha;
	};

	/* The preamp control. We simply run a low and a high shelf in series here. */

	preamp		= low_shelf(bass_freq,bass_gain)
			: high_shelf(treble_freq,treble_gain);

	/* Envelop follower. This is basically a 1 pole LP with configurable attack/
	release time. The result is converted to dB. You have to set the desired
	attack/release time in seconds using the t parameter below. */

	t		= 0.1;			// attack/release time in seconds
	g		= exp(-1/(SR*t));	// corresponding gain factor

	env		= abs : *(1-g) : + ~ *(g) : linear2db;

	/* Use this if you want the RMS instead. Note that this doesn't really
	calculate an RMS value (you'd need an FIR for that), but in practice our
	simple 1 pole IIR filter works just as well. */

	rms		= sqr : *(1-g) : + ~ *(g) : sqrt : linear2db;
	sqr(x)		= x*x;

	/* The dB meters for left and right channel. These are passive controls. */

	left_meter(x)	= attach(x, env(x) : hbargraph("left", -96, 10));
	right_meter(x)	= attach(x, env(x) : hbargraph("right", -96, 10));

	/* The main program. */

	preamp_process = 
			hgroup("[0] Preamp", preamp, preamp) ;
			// hgroup("[0] clean", vgroup("[1] preamp", preamp, preamp) );



}.preamp_process;

// https://github.com/creativeintent/temper/blob/master/Dsp/temper.dsp
temper = environment {
    // Pre-filter parameters
    pfilterfc = hslider("Cutoff [style:knob]", 20000, 100, 20000, 1.0);
    pfilterq = hslider("Resonance [style:knob]", 1.0, 1.0, 8, 0.001) : si.smooth(0.995);

    // Distortion parameters
    pdrive = hslider("[0] Drive [style:knob]", 4.0, -10.0, 10.0, 0.001) : si.smooth(0.995);
    psat = hslider("[1] Saturation [style:knob]", 1.0, 0.0, 1.0, 0.001) : si.smooth(0.995);
    pcurve = hslider("[2] Curve [style:knob]", 1.0, 0.1, 4.0, 0.001) : si.smooth(0.995);

    // Output parameters
    pfeedback = hslider("[3] Feedback [style:knob]", -60, -60, -24, 1) : ba.db2linear : si.smooth(0.995);
    plevel = hslider("[4] Level [style:knob]", -3, -24, 24, 1) : ba.db2linear : si.smooth(0.995);

    // A fairly standard wave shaping curve; we use this to shape the input signal
    // before modulating the filter coefficients by this signal. Which shaping curve
    // we use here is pretty unimportant; as long as we can introduce higher harmonics,
    // the coefficient modulation will react. Which harmonics we introduce here seems
    // to affect the resulting sound pretty minimally.
    //
    // Also note here that we use an approximation of the `tanh` function for computational
    // improvement. See `http://www.musicdsp.org/showone.php?id=238`.
    tanh(x) = x * (27 + x * x) / (27 + 9 * x * x);
    transfer(x) = tanh(pcurve * x) / tanh(pcurve);

    // The allpass filter is stable for `|m(x)| <= 1`, but should not linger
    // near +/-1.0 for very long. We therefore clamp the driven signal with a tanh
    // function to ensure smooth coefficient calculation. We also here introduce
    // a modulated DC offset in the signal before the curve.
    drive(x) = x : *(pdrive) : +(fol(x)) : max(-3) : min(3) with {
        fol = an.amp_follower(0.04);
    };

    // Our modulated filter is an allpass with coefficients governed by the input
    // signal applied through our wave shaper. Before the filter, we mix the dry
    // input signal with the raw waveshaper output according to the `psat` parameter.
    // Note the constant gain coefficient on the waveshaper; that number is to offset
    // the global gain from the waveshaper to make sure the shaping process stays
    // under unity gain. The maximum differential gain of the waveshaper can be found
    // by evaluating the derivative of the transfer function at x0 where x0 is the
    // steepest part of the slope. Here that number is ~4, so we multiply by ~1/4.
    modfilter(x) = x <: _, tap(x) : *(1.0 - psat), *(psat) : + : fi.tf1(b0(x), b1(x), a1(x)) with {
        b0(x) = m(x);
        b1(x) = 1.0;
        a1(x) = m(x);
        m(x) = drive(x) : transfer : *(0.24);
        tap(x) = m(x);
    };

    // A fork of the `tf2s` function from the standard filter library which uses a
    // smoothing function after the `tan` computation to move that expensive call
    // outside of the inner loop of the filter function.
    tf2s(b2,b1,b0,a1,a0,w1) = fi.tf2(b0d,b1d,b2d,a1d,a2d)
    with {
        c   = 1/tan(w1*0.5/ma.SR) : si.smooth(0.995); // bilinear-transform scale-factor
        csq = c*c;
        d   = a0 + a1 * c + csq;
        b0d = (b0 + b1 * c + b2 * csq)/d;
        b1d = 2 * (b0 - b2 * csq)/d;
        b2d = (b0 - b1 * c + b2 * csq)/d;
        a1d = 2 * (a0 - csq)/d;
        a2d = (a0 - a1*c + csq)/d;
    };

    // A fork of the `resonlp` function from the standard filter library which uses
    // a local `tf2s` implementation.
    resonlp(fc,Q,gain) = tf2s(b2,b1,b0,a1,a0,wc)
    with {
        wc = 2*ma.PI*fc;
        a1 = 1/Q;
        a0 = 1;
        b2 = 0;
        b1 = 0;
        b0 = gain;
    };

    // We have a resonant lowpass filter at the beginning of our signal chain
    // to control what part of the input signal becomes the modulating signal.
    filter = resonlp(pfilterfc, pfilterq, 1.0);

    // Our main processing block.
    main = (+ : modfilter : fi.dcblocker) ~ *(pfeedback) : gain with {
        // This explicit gain multiplier of 4.0 accounts for the loss of gain that
        // occurs from oversampling by a factor of 2, and for the loss of gain that
        // occurs from the prefilter and modulation step. Then we apply the output
        // level parameter.
        gain = *(4.0) : *(plevel);
    };

    // And the overall process declaration.
    poweramp = filter : main;    

	finalPWAMono = hgroup("[2] Temper",ba.bypass_fade(ma.SR/10, checkbox("[5] Bypass"), poweramp)); 

	temper_process = finalPWAMono;


}.temper_process;


/* A simple waveshaping effect. */
//https://github.com/grame-cncm/faust/blob/master-dev/tools/faust2pd/examples/synth/fuzz.dsp

// declare name "fuzz -- a simple distortion effect";
// declare author "Bram de Jong (from musicdsp.org)";
// declare version "1.0";

// import("music.lib");
// import("stdfaust.lib");

fuzz = environment {
	fuzz_group(x) = hgroup("[3] Fuzz ", x);

	dist	= fuzz_group(hslider("[0] distortion", 12, 0, 100, 0.1));	// distortion parameter
	gain	= fuzz_group(hslider("[1] gain", 3, -96, 96, 0.1));		// output gain (dB)
	byp 	= fuzz_group(1-int(checkbox("[2] Enable")));

	// the waveshaping function
	f(a,x)	= x*(abs(x) + a)/(x*x + (a-1)*abs(x) + 1);

	// gain correction factor to compensate for distortion
	g(a)	= 1/sqrt(a+1);

	fuzz_process	= ba.bypass2(byp, (out, out))

	with { 
		out(x) = db2linear(gain)*g(dist)*f(db2linear(dist),x); 
	};
}.fuzz_process;

// declare name "phaser";
// declare version "0.0";
// declare author "JOS, revised by RM";
// declare description "Phaser demo application.";

// import("stdfaust.lib");

// process = phaser2_demo;

// //-------------------------`(dm.)phaser2_demo`---------------------------
// // Phaser effect demo application.
// //
// // #### Usage
// //
// // ```
// // _,_ : phaser2_demo : _,_
// // ```
// //------------------------------------------------------------
// declare phaser2_demo author "Julius O. Smith III";
// declare phaser2_demo licence "MIT";

phaser = environment {


	phaser2_demo = ba.bypass2(pbp,phaser2_stereo_demo)
	with{
		phaser2_group(x) = hgroup("[4] Phaser ", x);

		invert = 0; //meter_group(checkbox("[1] Invert Internal Phaser Sum"));
		vibr = 0; //meter_group(checkbox("[2] Vibrato Mode")); // In this mode you can hear any "Doppler"

		phaser2_stereo_demo = *(level),*(level) :
			pf.phaser2_stereo(Notches,width,frqmin,fratio,frqmax,speed,mdepth,fb,invert);

		Notches = 4; // Compile-time parameter: 2 is typical for analog phaser stomp-boxes

		speed  = phaser2_group(hslider("[0] Speed [unit:Hz] [style:knob]", 0.5, 0, 5, 0.001));

		depth = 1;
		fb = 0.5;

		width = 1000;
		frqmin = 100;
		frqmax = 800;
		fratio = 1.5;

		level = 0 : ba.db2linear;
		pbp 	= phaser2_group(1-int(checkbox("[1] Enable")));

		mdepth = select2(vibr,depth,2); // Improve "ease of use"
	};
}.phaser2_demo;
