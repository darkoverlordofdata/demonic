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
import("tonestacks.lib");
import("tubes.lib");
import("webaudio.lib");


process = preamp : preamp2
    :> tone
    : hgroup("[3] Distortion", tubescreamer <: fuzz)
    // : tubescreamer
    :> temper
	// <: fuzz
    // :> temper
	// <: phaser
	// : flanger
    <: hgroup("[4] Modulation", phaser : flanger)
	: chorus
    : reverb
	:> amplifier;



//======================================================
//
//	preamp
//
//			a clean preamp with no gui,   
//			flat freq response
//======================================================
preamp = environment {
	/* Fixed bass and treble frequencies. You might want to tune these for your
	setup. */

	bass_freq	= 300;
	treble_freq	= 1200;

    bass_gain = 0;
    treble_gain = 0;
	gain		= 1.0;
	bal		= 0.0;
	
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
	preamp_process = hgroup("[0] Preamp", preamp, preamp);



}.preamp_process;

preamp2 = environment {
	/* The main program. */
    preamp = hgroup("[1]preamp: 6C16", stage1 : stage2)
    with {

        stage1 = T1_6C16 : *(preamp) : fi.lowpass(1,6531.0) : T2_6C16 : *(preamp) 
        with {
            preamp = vslider("[0] Pregain [style:knob]",-6,-20,20,0.1) : ba.db2linear : si.smoo;
        };

        stage2 = fi.lowpass(1,6531.0) : T3_6C16 : *(gain) 
        with {
            gain = vslider("[1] Gain [style:knob]",-6,-20.0,20.0,0.1) : ba.db2linear : si.smoo;
        };
    };

	preamp2_process = hgroup("[0] Preamp", preamp, preamp);

}.preamp2_process;

//======================================================
//
//	tone
//
//			select amplifier tone to emulate  
//
//======================================================
tone = environment {

    tone_group(x) = hgroup("[0] Tone ", x);

    tone_process = tone_group(ba.selectmulti(ma.SR/100, (tbassman, tmesa, ttwin, tprinceton,
                                                        tjcm800, tjcm2000, tjtm45, tmlead, tm2199,
                                                        tac30, tac15, tsoldano, tsovtek, tpeavey,
                                                        tibanez, troland, tampeg, tampeg_rev, 
                                                        tbogner, tgroove, tcrunch, tfender_blues,
                                                        tfender_default, tfender_deville, tgibsen), 
    nentry("[1] Emulation [style:menu{'bassman':0;'mesa':1;'twin':2;'princeton':3;
                                    'jcm800':4;'jcm2000':5;'jtm45':6;'mlead':7;'m2199':8;
                                    'ac30':9; 'ac15':10; 'soldano':11; 'sovtek':12; 'peavey':13;
                                    'ibanez':14; 'roland':15; 'ampeg':16; 'ampeg_rev':17;
                                    'bogner':18; 'groove':19; 'crunch':20, 'fender_blues':21;
                                    'fender_default':22; 'fender_deville':23; 'gibsen':24}]"
                                    , 0, 0, 2, 1)))
    with {
        tbassman = bassman(t, m, l);                /* 59 Bassman 5F6-A */
        tmesa = mesa(t, m, l);                      /* Mesa Boogie Mark */
        ttwin = twin(t, m, l);                      /* 69 Twin Reverb AA270 */
        tprinceton = princeton(t, m, l);            /* 64 Princeton AA1164 */
        tjcm800 = jcm800(t, m, l);                  /* 59/81 JCM-800 Lead 100 2203 */
        tjcm2000 = jcm2000(t, m, l);                /* 81 2000 Lead */
        tjtm45 = jtm45(t, m, l);                    /* JTM 45 */
        tmlead = mlead(t, m, l);                    /* 67 Major Lead 200 */
        tm2199 = m2199(t, m, l);                    /* undated M2199 30W solid state */
        tac30 = ac30(t, m, l);                      /* 59/86 AC-30 */
        tac15 = ac15(t, m, l);                      /* VOX AC-15 */
        tsoldano = soldano(t, m, l);                /* Soldano SLO 100 */
        tsovtek = sovtek(t, m, l);                  /* MIG 100 H*/
        tpeavey = peavey(t, m, l);                  /* c20*/
        tibanez = ibanez(t, m, l);                  /* gx20 */
        troland = roland(t, m, l);                  /* Cube 60 */
        tampeg = ampeg(t, m, l);                    /* VL 501 */
        tampeg_rev = ampeg_rev(t, m, l);            /* reverbrocket*/
        tbogner = bogner(t, m, l);                  /* Triple Giant Preamp  */
        tgroove = groove(t, m, l);                  /* Trio Preamp  */
        tcrunch = crunch(t, m, l);                  /* Hughes&Kettner  */
        tfender_blues = fender_blues(t, m, l);      /* Fender blues junior  */
        tfender_default = fender_default(t, m, l);  /* Fender   */
        tfender_deville = fender_deville(t, m, l);  /* Fender Hot Rod  */
        tgibsen = gibsen(t, m, l);                  /* gs12 reverbrocket   */
        t = hslider("[2] Treble [style:knob]",0.5,0,1,0.01);
        m = hslider("[3] Middle [style:knob]",0.5,0,1,0.01);
        l = hslider("[4] Bass [style:knob]",0.5,0,1,0.01);
    };
}.tone_process;

//======================================================
//
//	amplifier
//
//		based on https://github.com/micbuffa/FaustPowerAmp  
//
//======================================================
amplifier = environment {

	amplifier_group(x) = hgroup("[1] PowerAmp", x);

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
		presence = peaking2(2000, p1gain, 1, 1) : peaking2(4000, p1gain, 1, 1);
		gainNFL = hslider("[5] Negative gain[name:Level][style:knob]", -0.4, -0.8, 1, 0.01) :  si.smoo;
	};

	// Our main processing block.
	main = *(masterVolume) :(+ : waveshaper : fi.dcblocker) ~ feedbackCircuit : gain 
	with {
		// This explicit gain multiplier of 4.0 accounts for the loss of gain that
		// occurs from oversampling by a factor of 2, and for the loss of gain that
		// occurs from the prefilter and modulation step. Then we apply the output
		// level parameter.
		gain = *(4.0) : *(plevel);
		masterVolume = hslider("[6] Master Volume[name:MV][style:knob]", 1, 0, 4, 0.1)  : si.smoo;
	};

	// And the overall process declaration.
	amplifier_process = amplifier_group(ba.bypass_fade(ma.SR/10, checkbox("[7] Bypass"), main)); 

}.amplifier_process;

// https://github.com/creativeintent/temper/blob/master/Dsp/temper.dsp
temper = environment {
	temper_group(x) = hgroup("[2] Temper", x);

    // Pre-filter parameters
    pfilterfc = hslider("[5] Cutoff [style:knob]", 20000, 100, 20000, 1.0);
    pfilterq = hslider("[6] Resonance [style:knob]", 1.0, 1.0, 8, 0.001) : si.smooth(0.995);

    // Distortion parameters
    pdrive = hslider("[0] Drive [style:knob]", 4.0, -10.0, 10.0, 0.001) : si.smooth(0.995);
    psat = hslider("[1] Saturation [style:knob]", 1.0, 0.0, 1.0, 0.001) : si.smooth(0.995);
    pcurve = hslider("[2] Curve [style:knob]", 1.0, 0.1, 4.0, 0.001) : si.smooth(0.995);

    // Output parameters
    pfeedback = hslider("[3] Feedback [style:knob]", -60, -60, -24, 1) : ba.db2linear : si.smooth(0.995);
    plevel = hslider("[4] Level [style:knob]", -11, -24, 24, 1) : ba.db2linear : si.smooth(0.995);

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
	temper_process = temper_group(ba.bypass_fade(ma.SR/10, 1-int(checkbox("[7] Enable")), (filter : main))); 


}.temper_process;

/****************************************************************************************
 * 1-dimensional function tables for nonlinear interpolation
****************************************************************************************/
nonlininterpolation(table, low, high, step, size, x) = ts9(low, step, size, table, x),inverse(x) : ccopysign;

//-- Interpolate value from table
ts9(low, step, size, table, x) = interpolation(table, getCoef(low, step, size, x), 
                                 nonlinindex(low, step, x) : boundIndex(size));

//-- Calculate non linear index
nonlinindex(low, step, x) = (abs(x)/(3.0 + abs(x)) - low) * step;

//--Get interpolation factor
getCoef(low, step, size, x) = boundFactor(size, nonlinindex(low, step, x), nonlinindex(low, step, x) : boundIndex(size));

/********* Faust Version of ts9nonlin.cc, generated by tools/ts9sim.py ****************/

ts9comp = nonlininterpolation(ts9table, low, high, step, size) 
with {

// Characteristics of the wavetable
low = 0.0;
high = 0.970874;
step = 101.97;
size = 99; // (real size = 100, set the actual size at 100-1 for interpolation to work at the last point)
    
ts9table = waveform{0.0,-0.0296990148227,-0.0599780676992,-0.0908231643281,-0.122163239629,
    -0.15376009788,-0.184938007182,-0.214177260107,-0.239335434213,-0.259232575019,
    -0.274433909887,-0.286183308354,-0.29553854444,-0.303222323477,-0.309706249977,
    -0.315301338712,-0.320218440785,-0.324604982281,-0.328567120703,-0.332183356975,
    -0.335513124719,-0.33860236542,-0.34148724693,-0.344196707008,-0.346754233717,
    -0.34917913798,-0.351487480543,-0.35369275887,-0.355806424152,-0.357838275995,
    -0.359796767655,-0.361689244919,-0.363522135105,-0.365301098113,-0.367031148289,
    -0.368716753588,-0.370361916943,-0.371970243537,-0.373544996828,-0.375089145544,
    -0.376605403346,-0.378096262548,-0.379564022938,-0.381010816596,-0.382438629377,
    -0.383849319643,-0.385244634694,-0.386626225283,-0.387995658543,-0.389354429565,
    -0.39070397188,-0.392045667012,-0.393380853288,-0.39471083403,-0.396036885269,
    -0.397360263098,-0.398682210753,-0.400003965547,-0.401326765733,-0.402651857394,
    -0.403980501471,-0.405313980999,-0.406653608692,-0.40800073496,-0.409356756504,
    -0.410723125631,-0.412101360439,-0.413493056085,-0.414899897347,-0.416323672745,
    -0.417766290556,-0.419229797097,-0.420716397759,-0.422228481377,-0.423768648654,
    -0.425339745558,-0.426944902828,-0.428587583057,-0.430271637224,-0.432001373102,
    -0.433781638746,-0.435617925286,-0.437516494692,-0.439484540257,-0.441530390423,
    -0.443663770898,-0.445896146322,-0.448241172434,-0.450715304661,-0.453338632988,
    -0.45613605235,-0.45913894467,-0.46238766699,-0.465935359011,-0.469854010456,
    -0.474244617411,-0.479255257451,-0.48511588606,-0.492212726244,-0.501272723631
    };
};
/****************************************************************************************/

/****************************************************************************************
*    declare id       "ts9sim";
*    declare name     "Tube Screamer";
*    declare category "Distortion";
*
**  based on a circuit diagram of the Ibanez TS-9 and
**  a mathematical analysis published by Tamás Kenéz
****************************************************************************************/

tubescreamer = environment {

    tubescreamer_group(x) = hgroup("[3] TubeScreamer",x);
    ts9sim = ts9nonlin : lowpassfilter : *(gain) 
    with {
            

        R1 = 4700;
        R2 = 51000 + 500000 * tubescreamer_group(hslider("[0] Drive[name:Drive][style:knob]", 0.5, 0, 1, 0.01));
        C = 0.047 * 1e-6;
        a1 = (R1 + R2) * C * 2 * ma.SR;
        a2 = R1 * C * 2 * ma.SR;
        B0 = (1 + a1) / (1 + a2);
        B1 = (1 - a1) / (1 + a2);
        A1 = (1 - a2) / (1 + a2);
        X2 = fi.tf1(B0, B1, A1);

        ts9nonlin = _ <: _ ,(X2,_ : - : ts9comp) : - :> _;
    
        fc = tubescreamer_group(hslider("[1] Tone[log][name:Tone][style:knob]", 400, 100, 1000, 1.03));
        lowpassfilter = fi.lowpass(1,fc);
        gain = tubescreamer_group(hslider("[2] Level[name:Level][style:knob]", -16, -20, 4, 0.1)) : ba.db2linear : si.smoo;



    };
    byp = tubescreamer_group(1-int(checkbox("[3] Enable")));
	tubescreamer_process = ba.bypass1(byp, ts9sim);
}.tubescreamer_process;

/* A simple waveshaping effect. */
//https://github.com/grame-cncm/faust/blob/master-dev/tools/faust2pd/examples/synth/fuzz.dsp

// declare name "fuzz -- a simple distortion effect";
// declare author "Bram de Jong (from musicdsp.org)";
// declare version "1.0";

// import("music.lib");
// import("stdfaust.lib");

fuzz = environment {
	fuzz_group(x) = hgroup("[3] Fuzz ", x);

	dist	= fuzz_group(hslider("[0] Distortion [style:knob]", 12, 0, 100, 0.1));	// distortion parameter
	gain	= fuzz_group(hslider("[1] Gain [style:knob]", 3, -96, 96, 0.1));		// output gain (dB)
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


	phaser2_process = ba.bypass2(pbp,phaser2_stereo)
	with{
		phaser2_group(x) = hgroup("[4] Phaser ", x);

		invert = 0; //meter_group(checkbox("[1] Invert Internal Phaser Sum"));
		vibr = 0; //meter_group(checkbox("[2] Vibrato Mode")); // In this mode you can hear any "Doppler"

		phaser2_stereo = *(level),*(level) :
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
}.phaser2_process;

//======================================================
//
//	flanger
//  
//		flange effect
//
//======================================================
flanger = environment {

    flanger_group(x) = hgroup("[5] Flanger ", x);

    level           = 1;
    freq			= flanger_group(hslider("[0] Freq [style:knob]", 2, 0, 10, 0.01));
    dtime           = 0.002;
    depth			= flanger_group(hslider("[1] Depth [style:knob]", 0.5, 0, 1, 0.001));
    feedback		= flanger_group(hslider("[2] Feedback [style:knob]", 0.1, 0, 1, 0.001));
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


