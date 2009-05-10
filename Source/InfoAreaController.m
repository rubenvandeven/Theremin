//
//  InfoAreaController.m
//  Theremin
//
//  Created by Patrik Weiskircher on 10.02.07.
//  Copyright 2007 Patrik Weiskircher. All rights reserved.
//

#import "InfoAreaController.h"
#import "WindowController.h"
#import "MusicServerClient.h"
#import "PreferencesController.h"
#import "Song.h"
#import "NSStringAdditions.h"



@implementation InfoAreaController
- (id) init {
	self = [super init];
	if (self != nil) {
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(clientCurrentSongChanged:)
													 name:nMusicServerClientCurrentSongChanged
												   object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(clientConnecting:)
													 name:nMusicServerClientConnecting
												   object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(clientConnected:)
													 name:nMusicServerClientConnected
												   object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(clientDisconnected:)
													 name:nMusicServerClientDisconnected
												   object:nil];
		
		_growlMessenger = [[GrowlMessenger alloc] initWithDelegate:self];
	}
	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_growlMessenger release];
	[super dealloc];
}

- (void) growlMessengerNotificationWasClicked:(GrowlMessenger *)aGrowlMessenger {
	[NSApp activateIgnoringOtherApps:YES];
	[[WindowController instance] showPlayerWindow:self];
}

- (void) updateWithTimer:(NSTimer *)timer {
	[timer release];
	mInfoAreaUpdateTimer = nil;
	[self update];
}

- (void) scheduleUpdate {
	if (mInfoAreaUpdateTimer) {
		[mInfoAreaUpdateTimer invalidate];
		[mInfoAreaUpdateTimer release];
	}
	mInfoAreaUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(updateWithTimer:) userInfo:nil repeats:NO] retain];
}

- (void) update {
	WindowController *wc = [WindowController instance];
	if ([[wc musicClient] isConnected] == YES) {
		if ([wc currentPlayerState] == eStateStopped) {
			[mTitle setStringValue:NSLocalizedString(@"Not playing.", @"Info Area Status Text")];
			[mArtist setStringValue:@""];
			[mAlbum setStringValue:@""];
			[self updateSeekBarWithTotalTime:0];
			[self updateSeekBarWithElapsedTime:0];
			[mLastNotifiedSongIdentifier release], mLastNotifiedSongIdentifier = nil;
		} else if ([mCurrentSong valid]) {
			if ([mCurrentSong title] == nil || [[mCurrentSong title] length] == 0) {
				if ([mCurrentSong file] && [[mCurrentSong file] length])
					[mTitle setStringValue:[[mCurrentSong file] lastPathComponent]];
				else
					[mTitle setStringValue:@""];
			} else {
				[mTitle setStringValue:[mCurrentSong title]];
			}
			
			if ([mCurrentSong artist])
				[mArtist setStringValue:[mCurrentSong artist]];
			else
				[mArtist setStringValue:@""];
			
			if ([mCurrentSong album])
				[mAlbum setStringValue:[mCurrentSong album]];
			else
				[mAlbum setStringValue:@""];

		} else {
			[mTitle setStringValue:@""];
			[mArtist setStringValue:@""];
			[mAlbum setStringValue:@""];
		}
	} else {
		[mTitle setStringValue:NSLocalizedString(@"Not connected.", @"Info Area Status Text")];
		[mArtist setStringValue:@""];
		[mAlbum setStringValue:@""];

		[self updateSeekBarWithTotalTime:0];
		[self updateSeekBarWithElapsedTime:0];
	}
}

- (void) updateSeekBarWithTotalTime:(int)total {
	_total = total;
	[mSeekSlider setMinValue:0];
	[mSeekSlider setMaxValue:total];
}

- (void) updateSeekBarWithElapsedTime:(int)elapsed {
	int remaining = _total - elapsed;
	
	[mElapsedTime setStringValue:[NSString convertSecondsToTime:elapsed andIsValid:NULL]];
	
	BOOL isValid = NO;
	NSString *tmp = [NSString convertSecondsToTime:remaining andIsValid:&isValid];
	[mRemainingTime setStringValue:[NSString stringWithFormat:@"%c%@", isValid == YES ? '-' : ' ', tmp]];
	
	[mSeekSlider setIntValue:elapsed];
}

- (void) updateSeekBarWithSongLength:(int)songLength andElapsedTime:(int)elapsed {
	int remaining = songLength - elapsed;
	
	[mElapsedTime setStringValue:[NSString convertSecondsToTime:elapsed andIsValid:NULL]];
	
	BOOL isValid = NO;
	NSString *tmp = [NSString convertSecondsToTime:remaining andIsValid:&isValid];
	[mRemainingTime setStringValue:[NSString stringWithFormat:@"%c%@", isValid == YES ? '-' : ' ', tmp]];
	
	[mSeekSlider setMinValue:0];
	[mSeekSlider setMaxValue:songLength];
	[mSeekSlider setIntValue:elapsed];
}

- (void) clientCurrentSongChanged:(NSNotification *)notification {
	[mCurrentSong release];
	mCurrentSong = [[[notification userInfo] objectForKey:dSong] retain];	
	
	[self scheduleUpdate];
	
	if ([[WindowController instance] currentPlayerState] == eStatePlaying) {
		[_growlMessenger currentSongChanged:mCurrentSong];
	}
}

- (void) clientConnecting:(NSNotification *)notification {
	// if it takes longer than 0.5 seconds to connect, show that we are trying to connect
	mProgressIndicatorStartTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5
																	 target:self
																   selector:@selector(progressIndicatorStartTimerTriggered:)
																   userInfo:nil
																	repeats:NO] retain];
}

- (void) clientConnected:(NSNotification *)notification {
	if (mProgressIndicatorStartTimer != nil) {
		[mProgressIndicatorStartTimer invalidate];
		[mProgressIndicatorStartTimer release];
		mProgressIndicatorStartTimer = nil;
	}
	[mProgressIndicator stopAnimation:self];
	[mProgressLabel setStringValue:@""];
	[self scheduleUpdate];
}

- (void) clientDisconnected:(NSNotification *)notification {
	if (mProgressIndicatorStartTimer != nil) {
		[mProgressIndicatorStartTimer invalidate];
		[mProgressIndicatorStartTimer release];
		mProgressIndicatorStartTimer = nil;
	}
	[mProgressIndicator stopAnimation:self];
	[mProgressLabel setStringValue:[[notification userInfo] objectForKey:dDisconnectReason]];	
	[self scheduleUpdate];
}


- (void) progressIndicatorStartTimerTriggered:(NSTimer *)timer {
	// the timer is released in the connect/disconnect notification
	[mProgressLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Connecting to %@", @"Info Area Status Indicator"), [[[[WindowController instance] preferences] currentProfile] hostname]]];
	[mProgressIndicator startAnimation:self];
}

@end
