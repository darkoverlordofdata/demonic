declare name "Demonic";
declare version "0.9-beta";
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


process = _,_ : +
	: amplifier
	: spectral_analyzer
	: flanger
	: chorus
  	: reverb;

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
	pdrive = hslider("Drive gain[style:knob]", 4.0, -10.0, 10.0, 0.001) : si.smooth(0.995);
	psat = hslider("Saturation dry wet[style:knob]", 1.0, 0.0, 1.0, 0.001) : si.smooth(0.995);
	pcurve = hslider("Curve k[style:knob]", 1.0, 0.1, 4.0, 0.001) : si.smooth(0.995);

	// Output parameters
	plevel = hslider("Level[style:knob]", -3, -24, 24, 1) : ba.db2linear : si.smooth(0.995);

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
		p1gain = hslider("Presence[name:p1Gain][style:knob]", 0, -15, 15, 0.1);
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
		masterVolume = hslider("Master Volume[name:MV][style:knob]", 1, 0, 4, 0.1)  : si.smoo;
	};

	// And the overall process declaration.
	poweramp =  main;

	finalPWAMono = hgroup("PowerAmp FAUST / WebAudio",ba.bypass_fade(ma.SR/10, checkbox("bypass"), poweramp)); 

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


	// Created from flange.dsp 2015/06/21
	flanger_mono(dmax,curdel,depth,fb,invert,lfoshape)
		= _ <: _, (-:de.fdelay(dmax,curdel)) ~ *(fb) : _, *(select2(invert,depth,0-depth)) : + : *(1/(1+depth)); // ideal for dc and reinforced sinusoids (in-phase summed signals)

	flanger_process = ba.bypass1(fbp,flanger_mono_gui);

	// Kill the groups to save vertical space:
	meter_group(x) = flsg(x);
	ctl_group(x) = flkg(x);
	del_group(x) = flkg(x);

	flangeview = lfo(freq);

	flanger_mono_gui = attach(flangeview) : flanger_mono(dmax,curdel,depth,fb,invert,lfoshape);

	sinlfo(freq) = (1 + os.oscrs(freq))/2;
	trilfo(freq) = 1.0-abs(os.saw1(freq));
	lfo(f) = (lfoshape * trilfo(f)) + ((1-lfoshape) * sinlfo(f));

	dmax = 2048;
	odflange = 44; // ~1 ms at 44.1 kHz = min delay
	dflange  = ((dmax-1)-odflange)*del_group(hslider("[1] Delay [midi:ctrl 50][style:knob]", 0.22, 0, 1, 1));
	freq     = ctl_group(vslider("[1] Rate [midi:ctrl 51] [unit:Hz] [style:knob]", 0.5, 0, 10, 0.01)) : si.smooth(ba.tau2pole(freqT60/6.91));

	freqT60  = 0.15661;
	depth    = ctl_group(vslider("[3] Depth [midi:ctrl 52] [style:knob]", .75, 0, 1, 0.001)) : si.smooth(ba.tau2pole(depthT60/6.91));

	depthT60 = 0.15661;
	fb       = ctl_group(vslider("[5] Feedback [midi:ctrl 53] [style:knob]", 0, -0.995, 0.99, 0.001)) : si.smooth(ba.tau2pole(fbT60/6.91));

	fbT60    = 0.15661;
	lfoshape = ctl_group(vslider("[7] Waveshape [midi:ctrl 54] [style:knob]", 0, 0, 1, 0.001));
	curdel   = odflange+dflange*lfo(freq);


	fbp = 1-int(flsg(checkbox("[0] Enable")));

	invert = flsg(checkbox("[1] Invert"));

}.flanger_process;

//======================================================
//
//	chorus
//
//======================================================
chorus = environment {

	voices = 8; // MUST BE EVEN
	chorus_process = ba.bypass1to2(cbp,chorus_mono(dmax,curdel,rate,sigma,do2,voices));

	dmax = 8192;
	curdel = dmax * ckg(vslider("[0] Delay [midi:ctrl 55] [style:knob]", 0.5, 0, 1, 1)) : si.smooth(0.999);
	rateMax = 7.0; // Hz
	rateMin = 0.01;
	rateT60 = 0.15661;
	rate = ckg(vslider("[1] Rate [midi:ctrl 56] [unit:Hz] [style:knob]", 0.5, rateMin, rateMax, 0.0001))
		: si.smooth(ba.tau2pole(rateT60/6.91));

	depth = ckg(vslider("[4] Depth [midi:ctrl 57] [style:knob]", 0.5, 0, 1, 0.001)) : si.smooth(ba.tau2pole(depthT60/6.91));

	depthT60 = 0.15661;
	delayPerVoice = 0.5*curdel/voices;
	sigma = delayPerVoice * ckg(vslider("[6] Deviation [midi:ctrl 58] [style:knob]",0.5,0,1,0.001)) : si.smooth(0.999);

	periodic = 1;

	do2 = depth;   // use when depth=1 means "multivibrato" effect (no original => all are modulated)
	cbp = 1-int(csg(checkbox("Enable")));

	chorus_mono(dmax,curdel,rate,sigma,do2,voices)
		= _ <: (*(1-do2)<:_,_),(*(do2) <: par(i,voices,voice(i)) :> _,_) : ro.interleave(2,2) : +,+
		with {
			angle(i) = 2*ma.PI*(i/2)/voices + (i%2)*ma.PI/2;
			voice(i) = de.fdelay(dmax,min(dmax,del(i))) * cos(angle(i));
			del(i) = curdel*(i+1)/voices + dev(i);
			rates(i) = rate/float(i+1);
			dev(i) = sigma * os.oscp(rates(i),i*2*ma.PI/voices);
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

	dampSlider      = rkg(vslider("Damp [midi:ctrl 3] [style:knob]",0.5, 0, 1, 0.025))*scaledamp;
	roomsizeSlider  = rkg(vslider("RoomSize [midi:ctrl 4] [style:knob]", 0.5, 0, 1, 0.025))*scaleroom + offsetroom;
	wetSlider       = rkg(vslider("Wet [midi:ctrl 79] [style:knob]", 0.3333, 0, 1, 0.025));
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

	monoReverbToStereo(fb1, fb2, damp, spread)
	= + <: monoReverb(fb1, fb2, damp, 0) <: _,_;
	stereoReverb(fb1, fb2, damp, spread)
	= + <:  monoReverb(fb1, fb2, damp, 0), monoReverb(fb1, fb2, damp, spread);
	monoToStereoReverb(fb1, fb2, damp, spread)
	= _ <: monoReverb(fb1, fb2, damp, 0), monoReverb(fb1, fb2, damp, spread);

	// fxctrl : add an input gain and a wet-dry control to a stereo FX
	//----------------------------------------------------------------

	fxctrl(g,w,Fx) =  _,_ <: (*(g),*(g) : Fx : *(w),*(w)), *(1-w), *(1-w) +> _,_;

	rbp = 1-int(rsg(checkbox("[0] Enable")));

	// Freeverb
	//---------
	freeverb = fxctrl(fixedgain, wetSlider, monoReverbToStereo(combfeed, allpassfeed, dampSlider, stereospread));

	freeverb_process = ba.bypass2(rbp,freeverb);

}.freeverb_process;


spectral_analyzer = environment {

	//----------------------`(dm.)mth_octave_spectral_level`----------------------
	// Demonstrate mth_octave_spectral_level in a standalone GUI.
	//
	// #### Usage
	// ```
	// _ : mth_octave_spectral_level(BandsPerOctave) : _
	// _ : spectral_level_demo : _ // 2/3 octave
	// ```
	//------------------------------------------------------------
	declare mth_octave_spectral_level author "Julius O. Smith III and Yann Orlarey";
	declare mth_octave_spectral_level licence "MIT";


	mth_octave_spectral_level(BPO) =  an.mth_octave_spectral_level_default(M,ftop,N,tau,dB_offset)
	with{
		M = BPO;
		// ftop = 16000;
		ftop = 2000;
		// Noct = 10; // number of octaves down from ftop
		Noct = 5; // number of octaves down from ftop
		// Lowest band-edge is at ftop*2^(-Noct+2) = 62.5 Hz when ftop=16 kHz:
		N = int(Noct*M); // without 'int()', segmentation fault observed for M=1.67
		// ctl_group(x)  = hgroup("[1] SPECTRUM ANALYZER CONTROLS", x);
		tau = sagg(hslider("[0] Level Averaging Time [unit:ms] [scale:log]
			[tooltip: band-level averaging time in milliseconds]",
		100,1,10000,1)) * 0.001;
		dB_offset = sagc(hslider("[1] Level dB Offset [unit:dB]
		[tooltip: Level offset in decibels]",
		50,-50,100,1));
	};

	spectral_process = mth_octave_spectral_level(2);
}.spectral_process;

tone = environment {
	import("math.lib");
	import("music.lib");

	/* Fixed bass and treble frequencies. You might want to tune these for your
	setup. */

	bass_freq	= 300;
	treble_freq	= 1200;

	/* Bass and treble gain controls in dB. The range of +/-20 corresponds to a
	boost/cut factor of 10. */

	bass_gain	= hslider("bass", 0, -20, 20, 0.1);
	treble_gain	= hslider("treble", 0, -20, 20, 0.1);

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

	/* The tone control. We simply run a low and a high shelf in series here. */

	tone		= low_shelf(bass_freq,bass_gain)
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

	tone_process = 
			hgroup("[0] clean", vgroup("[1] tone", tone, tone) );



}.tone_process;

/**
 * Layout
 * 
 */
flg(x) = hgroup("[0] Flanger",x);
flkg(x) = flg(hgroup("[0] Knobs",x));
flsg(x) = flg(hgroup("[1] Switches",x));


chg(x) = hgroup("[1] Chorus",x);
ckg(x) = chg(hgroup("[0] Knobs",x));
csg(x) = chg(hgroup("[1] Switches",x));

rg(x) = hgroup("[2] Reverb",x);
rkg(x) = rg(hgroup("[0] Knobs",x));
rsg(x) = rg(hgroup("[1] Switches",x));

sag(x) = hgroup("[4] Spectrum Analyzer", x);
sagg(x) = sag(vgroup("[0] Graph", x));
sagc(x) = sag(vgroup("[1] Control", x));



