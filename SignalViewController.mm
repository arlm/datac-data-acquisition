//
// Copyright (C) 2011, Brad Howes. All rights reserved.
//

#import "AppDelegate.h"
#import "DataCapture.h"
#import "IndicatorButton.h"
#import "IndicatorLight.h"
#import "SampleRecorder.h"
#import "SignalDetector.h"
#import "SignalViewController.h"
#import "UserSettings.h"
#import "VertexBufferManager.h"

@interface SignalViewController(Private)

- (void)handleSingleTapGesture:(UITapGestureRecognizer*)recognizer;
- (void)handlePanGesture:(UIPanGestureRecognizer *)recognizer;
- (void)updateSignalStats:(NSNotification*)notification;
- (void)switchStateChanged:(SwitchDetector *)sender;
- (void)adaptViewToOrientation;

@end

@implementation SignalViewController

@synthesize appDelegate, sampleView, powerIndicator, connectedIndicator, recordIndicator;
@synthesize xMinLabel, xMaxLabel, yPos05Label, yZeroLabel, yNeg05Label;
@synthesize peaks, rpms, peakFormatter, rpmFormatter, lastPeakValue, lastRpmValue;

//
// Maximum age of audio samples we can show at one go. Since we capture at 44.1kHz, that means 44.1k
// OpenGL vertices or 2 88.2k floats.
//
static const CGFloat kXMaxMax = 1.0;

-(void)viewDidLoad 
{
    NSLog(@"SignalViewController.viewDidLoad");
    [super viewDidLoad];

    sampleView.delegate = self;
    self.view.autoresizesSubviews = YES;
    self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    //
    // Register for notification when the DataCapture properties emittingPowerSignal and pluggedIn
    // change so we can update our display appropriately.
    //
    vertexBufferManager = appDelegate.vertexBufferManager;

    [appDelegate.dataCapture addObserver:self forKeyPath:NSStringFromSelector(@selector(emittingPowerSignal)) options:0 context:nil];
    [appDelegate.dataCapture addObserver:self forKeyPath:NSStringFromSelector(@selector(pluggedIn)) options:0 context:nil];

    appDelegate.switchDetector.delegate = self;

    self.peakFormatter = [[[NSNumberFormatter alloc] init] autorelease];
    [peakFormatter setNumberStyle:NSNumberFormatterDecimalStyle];

    self.rpmFormatter = [[[NSNumberFormatter alloc] init] autorelease];
    [rpmFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [rpmFormatter setPositiveFormat:@"##0.0k"];

    //
    // Set widgets so that they will appear behind the graph view when we rotate to the landscape view.
    //
    powerIndicator.layer.zPosition = -1;
    connectedIndicator.layer.zPosition = -1;
    recordIndicator.layer.zPosition = -1;

    recordIndicator.light.onState = kYellow;
    recordIndicator.light.blinkingInterval = 0.20;

    powerIndicator.on = NO;
    connectedIndicator.on = NO;
    recordIndicator.on = NO;

    //
    // Install single-tap gesture to freeze the display.
    //
    UITapGestureRecognizer* stgr = [[[UITapGestureRecognizer alloc]
									 initWithTarget:self action:@selector(handleSingleTapGesture:)] 
				       autorelease];
    [sampleView addGestureRecognizer:stgr];

    //
    // Install a 1 and 2 finger pan guesture to change the x scale (1 finger) and to change the 
    // signal detector level (2 finger)
    //
    UIPanGestureRecognizer* pgr = [[[UIPanGestureRecognizer alloc] 
									initWithTarget:self action:@selector(handlePanGesture:)]
				      autorelease];
    pgr.minimumNumberOfTouches = 1;
    pgr.maximumNumberOfTouches = 2;
    [sampleView addGestureRecognizer:pgr];

    //
    // Register for notification when the signal detector updates its rate estimates.
    //
    [[NSNotificationCenter defaultCenter] addObserver:self 
					     selector:@selector(updateSignalStats:)
						 name:kSignalDetectorCounterUpdateNotification
					       object:nil];

    [self setXMax:[[NSUserDefaults standardUserDefaults] floatForKey:kSettingsXMaxKey]];
}

- (void)viewDidUnload
{
    NSLog(@"SignalViewController.viewDidUnload");
    [self stop];
    self.peakFormatter = nil;
    self.rpmFormatter = nil;
    [super viewDidUnload];
}

- (void)dealloc {
    self.peakFormatter = nil;
    self.rpmFormatter = nil;
    [super dealloc];
}

- (void)start
{
    if (! [sampleView isAnimating]) {
	[self updateFromSettings];
	[sampleView startAnimation];
    }
}

- (void)stop
{
    if ([sampleView isAnimating]) {
	[sampleView stopAnimation];
    }
}

- (void)updateFromSettings
{
    Float32 rate = 1.0 / [[NSUserDefaults standardUserDefaults] floatForKey:kSettingsSignalDisplayUpdateRateKey];
    if (rate != sampleView.animationInterval) {
	sampleView.animationInterval = rate;
	if (sampleView.animationTimer != nil) {
	    [sampleView stopAnimation];
	    [sampleView startAnimation];
	}
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    NSLog(@"SignalViewController.viewWillAppear");
    [self adaptViewToOrientation];
    [self start];
    peaks.text = [peakFormatter stringFromNumber:lastPeakValue];
    rpms.text = [rpmFormatter stringFromNumber:lastRpmValue];
    [super viewWillAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
    NSLog(@"SignalViewController.viewWillDisappear");
    [self stop];
    [super viewWillDisappear:animated];
}

- (IBAction)togglePower {
    NSLog(@"togglePower");
    powerIndicator.on = ! powerIndicator.on;
    [appDelegate.dataCapture setEmittingPowerSignal: powerIndicator.on];
}

- (IBAction)toggleRecord {
    NSLog(@"toggleRecord");
    recordIndicator.on = ! recordIndicator.on;
    if (recordIndicator.on == YES) {
	[appDelegate startRecording];
    }
    else {
	[appDelegate stopRecording];
    }
}

- (void)setXMax:(GLfloat)value
{
    xMax = value;
    xMaxLabel.text = [NSString stringWithFormat:@"%5.4gs",value];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    //
    // !!! Be careful - this may be running in a thread other than the main one.
    //
    if ([keyPath isEqual:@"emittingPowerSignal"]) {
	powerIndicator.on = appDelegate.dataCapture.emittingPowerSignal;
    }
    else if ([keyPath isEqual:@"pluggedIn"]) {
	connectedIndicator.on = appDelegate.dataCapture.pluggedIn;
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

- (void)didReceiveMemoryWarning {
    NSLog(@"Memory Warning");
    [super didReceiveMemoryWarning];
}

- (void)updateSignalStats:(NSNotification*)notification
{
    NSDictionary* userInfo = [notification userInfo];
    self.lastPeakValue = [userInfo objectForKey:kSignalDetectorCounterKey];
    self.lastRpmValue = [userInfo objectForKey:kSignalDetectorRPMKey];
    if ([sampleView isAnimating]) {
	peaks.text = [peakFormatter stringFromNumber:lastPeakValue];
	rpms.text = [rpmFormatter stringFromNumber:lastRpmValue];
    }
}

- (void)switchStateChanged:(SwitchDetector *)sender
{
    [self toggleRecord];
}

- (void)drawView:(SampleView*)sender
{
    glClear(GL_COLOR_BUFFER_BIT);

    //
    // Set scaling for the floating-point samples
    //
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrthof(0.0f, xMax, -1.0f, 1.0, -1.0f, 1.0f);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    //
    // Draw three horizontal values at Y = -0.5, 0.0, and +0.5
    //
    GLfloat xAxis[ 12 ];
    glVertexPointer(2, GL_FLOAT, 0, xAxis);

    xAxis[0] = 0.0;
    xAxis[1] = 0.0;
    xAxis[2] = xMax;
    xAxis[3] = 0.0;

    xAxis[4] = 0.0;
    xAxis[5] = 0.5;
    xAxis[6] = xMax;
    xAxis[7] = 0.5;

    xAxis[8] = 0.0;
    xAxis[9] = -0.5;
    xAxis[10] = xMax;
    xAxis[11] = -0.5;

    glColor4f(.5, .5, .5, 1.);
    glLineWidth(0.5);
    glDrawArrays(GL_LINES, 0, 6);

    glColor4f(0., 1., 0., 1.);
    glLineWidth(1.25);
    glPushMatrix();
    [vertexBufferManager drawVerticesStartingAt:xMin forSpan:xMax];
    glPopMatrix();

    xAxis[1] = appDelegate.signalDetector.level;
    xAxis[3] = xAxis[1];
    glLineWidth(1.0);
    glColor4f(1., 0., 0., 0.5);
    glVertexPointer(2, GL_FLOAT, 0, xAxis);
    glDrawArrays(GL_LINES, 0, 2);
}

- (void)handleSingleTapGesture:(UITapGestureRecognizer*)recognizer
{
    vertexBufferManager.frozen = ! vertexBufferManager.frozen;
}

- (void)handlePanGesture:(UIPanGestureRecognizer*)recognizer
{
    CGPoint translate = [recognizer translationInView:sampleView];
    CGPoint velocity = [recognizer velocityInView:sampleView];

    CGFloat width = sampleView.window.bounds.size.width;
    CGFloat height = sampleView.window.bounds.size.height;

    if (recognizer.state == UIGestureRecognizerStateBegan) {
	if (recognizer.numberOfTouches == 1) {
	    panHorizontal = YES;
	    panStart = xMax / kXMaxMax * width;
	}
	else if (recognizer.numberOfTouches == 2) {
	    panHorizontal = NO;
	    panStart = (appDelegate.signalDetector.level) * height / 2;
	}
    }
    else {
	if (panHorizontal == YES) {
	    GLfloat newXMax = (panStart + translate.x) / width * kXMaxMax;
	    if (newXMax > kXMaxMax) newXMax = kXMaxMax;
	    if (newXMax < 0.001) newXMax = 0.001;
	    [self setXMax: newXMax];
	    if (recognizer.state == UIGestureRecognizerStateEnded) {
		[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:newXMax] forKey:kSettingsXMaxKey];
	    }
	}
	else {
	    Float32 newLevel = (panStart - translate.y) / ( height / 2 );
	    if (newLevel > 1.0) newLevel = 1.0;
	    if (newLevel < 0.0) newLevel = 0.0;
	    appDelegate.signalDetector.level = newLevel;
	    if (recognizer.state == UIGestureRecognizerStateEnded) {
		[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:newLevel]
							  forKey:kSettingsSignalDetectorLevelKey];
	    }
	}
    }
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
    [self adaptViewToOrientation];
}

- (void)adaptViewToOrientation
{
    SInt32 offset = sampleView.frame.origin.y;
    SInt32 height = sampleView.frame.size.height;
    yPos05Label.center = CGPointMake(yPos05Label.center.x, offset + 0.25 * height + yPos05Label.bounds.size.height * 0.5 + 1);
    yZeroLabel.center = CGPointMake(yZeroLabel.center.x, offset + 0.5 * height + yZeroLabel.bounds.size.height * 0.5 + 1);
    yNeg05Label.center = CGPointMake(yNeg05Label.center.x, offset + 0.75 * height + yNeg05Label.bounds.size.height * 0.5 + 1);
}

@end
