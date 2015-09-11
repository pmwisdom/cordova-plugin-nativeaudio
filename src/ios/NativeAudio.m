//
//
//  NativeAudio.m
//  NativeAudio
//
//  Created by Sidney Bofah on 2014-06-26.
//

#import "NativeAudio.h"
#import "CDVFile.h"
#import <AVFoundation/AVAudioSession.h>

#define DOCUMENTS_SCHEME_PREFIX @"documents://"
#define HTTP_SCHEME_PREFIX @"http://"
#define HTTPS_SCHEME_PREFIX @"https://"
#define CDVFILE_PREFIX @"cdvfile://"
#define RECORDING_WAV @"wav"

@implementation NativeAudio

NSString* ERROR_ASSETPATH_INCORRECT = @"(NATIVE AUDIO) Asset not found.";
NSString* ERROR_REFERENCE_EXISTS = @"(NATIVE AUDIO) Asset reference already exists.";
NSString* ERROR_REFERENCE_MISSING = @"(NATIVE AUDIO) Asset reference does not exist.";
NSString* ERROR_TYPE_RESTRICTED = @"(NATIVE AUDIO) Action restricted to assets loaded using preloadComplex().";
NSString* ERROR_VOLUME_NIL = @"(NATIVE AUDIO) Volume cannot be empty.";
NSString* ERROR_VOLUME_FORMAT = @"(NATIVE AUDIO) Volume is declared as float between 0.0 - 1.0";

NSString* INFO_ASSET_LOADED = @"(NATIVE AUDIO) Asset loaded.";
NSString* INFO_ASSET_UNLOADED = @"(NATIVE AUDIO) Asset unloaded.";
NSString* INFO_PLAYBACK_PLAY = @"(NATIVE AUDIO) Play";
NSString* INFO_PLAYBACK_STOP = @"(NATIVE AUDIO) Stop";
NSString* INFO_PLAYBACK_LOOP = @"(NATIVE AUDIO) Loop.";
NSString* INFO_VOLUME_CHANGED = @"(NATIVE AUDIO) Volume changed.";


- (void)pluginInitialize
{
    
    //    AudioSessionInitialize(NULL, NULL, nil , nil);
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    NSError *setCategoryError = nil;
    
    //Allows the application to mix its audio with audio from other apps.
    //    if (![session setCategory:AVAudioSessionCategoryAmbient
    //                  withOptions:AVAudioSessionCategoryOptionMixWithOthers
    //                        error:&setCategoryError]) {
    //
    //        NSLog (@"Error setting audio session category.");
    //        return;
    //    }
    
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    
    [session setActive: YES error: nil];
}

// Maps a url for a resource path for playing
// "Naked" resource paths are assumed to be from the www folder as its base
- (NSURL*)urlForPlaying:(NSString*)resourcePath
{
    NSURL* resourceURL = nil;
    NSString* filePath = nil;
    
    // first try to find HTTP:// or Documents:// resources
    
    if ([resourcePath hasPrefix:HTTP_SCHEME_PREFIX] || [resourcePath hasPrefix:HTTPS_SCHEME_PREFIX]) {
        // if it is a http url, use it
        NSLog(@"Will use resource '%@' from the Internet.", resourcePath);
        resourceURL = [NSURL URLWithString:resourcePath];
    } else if ([resourcePath hasPrefix:DOCUMENTS_SCHEME_PREFIX]) {
        NSString* docsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        filePath = [resourcePath stringByReplacingOccurrencesOfString:DOCUMENTS_SCHEME_PREFIX withString:[NSString stringWithFormat:@"%@/", docsPath]];
        NSLog(@"Will use resource '%@' from the documents folder with path = %@", resourcePath, filePath);
    } else if ([resourcePath hasPrefix:CDVFILE_PREFIX]) {
        CDVFile *filePlugin = [self.commandDelegate getCommandInstance:@"File"];
        CDVFilesystemURL *url = [CDVFilesystemURL fileSystemURLWithString:resourcePath];
        filePath = [filePlugin filesystemPathForURL:url];
        if (filePath == nil) {
            resourceURL = [NSURL URLWithString:resourcePath];
        }
    } else {
        // attempt to find file path in www directory or LocalFileSystem.TEMPORARY directory
        filePath = [self.commandDelegate pathForResource:resourcePath];
        if (filePath == nil) {
            // see if this exists in the documents/temp directory from a previous recording
            NSString* testPath = [NSString stringWithFormat:@"%@/%@", [NSTemporaryDirectory()stringByStandardizingPath], resourcePath];
            if ([[NSFileManager defaultManager] fileExistsAtPath:testPath]) {
                // inefficient as existence will be checked again below but only way to determine if file exists from previous recording
                filePath = testPath;
                NSLog(@"Will attempt to use file resource from LocalFileSystem.TEMPORARY directory");
            } else {
                // attempt to use path provided
                filePath = resourcePath;
                NSLog(@"Will attempt to use file resource '%@'", filePath);
            }
        } else {
            NSLog(@"Found resource '%@' in the web folder.", filePath);
        }
    }
    // if the resourcePath resolved to a file path, check that file exists
    if (filePath != nil) {
        // create resourceURL
        resourceURL = [NSURL fileURLWithPath:filePath];
        // try to access file
        NSFileManager* fMgr = [NSFileManager defaultManager];
        if (![fMgr fileExistsAtPath:filePath]) {
            resourceURL = nil;
            NSLog(@"Unknown resource '%@'", resourcePath);
        }
    }
    
    return resourceURL;
}

- (void) preloadSimple:(CDVInvokedUrlCommand *)command
{
    
    NSString *callbackId = command.callbackId;
    NSArray* arguments = command.arguments;
    NSString *audioID = [arguments objectAtIndex:0];
    NSString *assetPath = [arguments objectAtIndex:1];
    
    if(audioMapping == nil) {
        audioMapping = [NSMutableDictionary dictionary];
    }
    
    NSNumber* existingReference = audioMapping[audioID];
    
    [self.commandDelegate runInBackground:^{
        if (existingReference == nil) {
            
            NSString* basePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"www"];
            NSString* path = [NSString stringWithFormat:@"%@", assetPath];
            NSString* pathFromWWW = [NSString stringWithFormat:@"%@/%@", basePath, assetPath];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath : path]) {
                
                NSURL *pathURL = [NSURL fileURLWithPath : path];
                CFURLRef soundFileURLRef = (CFURLRef) CFBridgingRetain(pathURL);
                SystemSoundID soundID;
                AudioServicesCreateSystemSoundID(soundFileURLRef, &soundID);
                audioMapping[audioID] = [NSNumber numberWithInt:soundID];
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_ASSET_LOADED, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
                
            } else if ([[NSFileManager defaultManager] fileExistsAtPath : pathFromWWW]) {
                NSURL *pathURL = [NSURL fileURLWithPath : pathFromWWW];
                CFURLRef        soundFileURLRef = (CFURLRef) CFBridgingRetain(pathURL);
                SystemSoundID soundID;
                AudioServicesCreateSystemSoundID(soundFileURLRef, &soundID);
                audioMapping[audioID] = [NSNumber numberWithInt:soundID];
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_ASSET_LOADED, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
                
            } else {
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_ASSETPATH_INCORRECT, assetPath];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
            }
        } else {
            
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_EXISTS, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        }
        
    }];
    
    
}

- (void) preloadComplex:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    NSArray* arguments = command.arguments;
    NSString *audioID = [arguments objectAtIndex:0];
    NSString *assetPath = [arguments objectAtIndex:1];
    
    NSNumber *volume = nil;
    if ( [arguments count] > 2 ) {
        volume = [arguments objectAtIndex:2];
        if([volume isEqual:nil]) {
            volume = [NSNumber numberWithFloat:1.0f];
        }
    } else {
        volume = [NSNumber numberWithFloat:1.0f];
    }
    
    NSNumber *voices = nil;
    if ( [arguments count] > 3 ) {
        voices = [arguments objectAtIndex:3];
        if([voices isEqual:nil]) {
            voices = [NSNumber numberWithInt:1];
        }
    } else {
        voices = [NSNumber numberWithInt:1];
    }
    
    NSNumber *delay = nil;
    if ( [arguments count] > 4 && [arguments objectAtIndex:4] != [NSNull null])
    {
        // The delay is determines how fast the asset is
        // faded in and out
        delay = [arguments objectAtIndex:4];
    }
    
    if(audioMapping == nil) {
        audioMapping = [NSMutableDictionary dictionary];
    }
    
    NSNumber* existingReference = audioMapping[audioID];
    
    [self.commandDelegate runInBackground:^{
        if (existingReference == nil) {
            
            if ([[NSFileManager defaultManager] fileExistsAtPath : assetPath]) {
                NSURL *path = [self urlForPlaying:assetPath];
                
                NativeAudioAsset* asset = [[NativeAudioAsset alloc] initWithPath:path
                                                                      withVoices:voices
                                                                      withVolume:volume
                                                                   withFadeDelay:delay];
                
                audioMapping[audioID] = asset;
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_ASSET_LOADED, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
                
            } else {
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_ASSETPATH_INCORRECT, assetPath];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
            }
        } else {
            
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_EXISTS, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        }
        
    }];
}

- (void) play:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    NSArray* arguments = command.arguments;
    NSString *audioID = [arguments objectAtIndex:0];
    
    [self.commandDelegate runInBackground:^{
        if (audioMapping) {
            NSObject* asset = audioMapping[audioID];
            
            if (asset != nil){
                if ([asset isKindOfClass:[NativeAudioAsset class]]) {
                    NativeAudioAsset *_asset = (NativeAudioAsset*) asset;
                    // Music assets are faded in
                    [_asset play];
                    
                    NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_PLAYBACK_PLAY, audioID];
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
                    
                } else if ( [asset isKindOfClass:[NSNumber class]] ) {
                    NSNumber *_asset = (NSNumber*) asset;
                    AudioServicesPlaySystemSound([_asset intValue]);
                    
                    NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_PLAYBACK_PLAY, audioID];
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
                    
                }
            } else {
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
            }
            
        } else {
            
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        }
    }];
}

- (void) stop:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    NSArray* arguments = command.arguments;
    NSString *audioID = [arguments objectAtIndex:0];
    
    if ( audioMapping ) {
        NSObject* asset = audioMapping[audioID];
        
        if (asset != nil){
            
            if ([asset isKindOfClass:[NativeAudioAsset class]]) {
                NativeAudioAsset *_asset = (NativeAudioAsset*) asset;
                // Music assets are faded out
                [_asset stopWithFade];
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_PLAYBACK_STOP, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
                
            } else if ( [asset isKindOfClass:[NSNumber class]] ) {
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_TYPE_RESTRICTED, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
                
            }
            
        } else {
            
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        }
    } else {
        NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];    }
}

- (void) loop:(CDVInvokedUrlCommand *)command
{
    
    NSString *callbackId = command.callbackId;
    NSArray* arguments = command.arguments;
    NSString *audioID = [arguments objectAtIndex:0];
    
    
    if ( audioMapping ) {
        NSObject* asset = audioMapping[audioID];
        
        if (asset != nil){
            
            
            if ([asset isKindOfClass:[NativeAudioAsset class]]) {
                NativeAudioAsset *_asset = (NativeAudioAsset*) asset;
                [_asset loop];
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_PLAYBACK_LOOP, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
                
            } else if ( [asset isKindOfClass:[NSNumber class]] ) {
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_TYPE_RESTRICTED, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
            }
            
            else {
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
            }
        } else {
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        };
    }
}

- (void) unload:(CDVInvokedUrlCommand *)command
{
    
    NSString *callbackId = command.callbackId;
    NSArray* arguments = command.arguments;
    NSString *audioID = [arguments objectAtIndex:0];
    
    if ( audioMapping ) {
        NSObject* asset = audioMapping[audioID];
        
        if (asset != nil){
            
            
            if ([asset isKindOfClass:[NativeAudioAsset class]]) {
                NativeAudioAsset *_asset = (NativeAudioAsset*) asset;
                [_asset unload];
            } else if ( [asset isKindOfClass:[NSNumber class]] ) {
                NSNumber *_asset = (NSNumber*) asset;
                AudioServicesDisposeSystemSoundID([_asset intValue]);
            }
            
        } else {
            
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        }
        
        [audioMapping removeObjectForKey: audioID];
        
        NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_ASSET_UNLOADED, audioID];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
    } else {
        NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
    }
    
}

- (void) setVolumeForComplexAsset:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    NSArray* arguments = command.arguments;
    NSString *audioID = [arguments objectAtIndex:0];
    NSNumber *volume = nil;
    
    if ( [arguments count] > 1 ) {
        
        volume = [arguments objectAtIndex:1];
        
        if([volume isEqual:nil]) {
            
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_VOLUME_NIL, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        }
    } else if (([volume floatValue] < 0.0f) || ([volume floatValue] > 1.0f)) {
        
        NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_VOLUME_FORMAT, audioID];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
    }
    
    if ( audioMapping ) {
        NSObject* asset = [audioMapping objectForKey: audioID];
        
        if (asset != nil){
            
            if ([asset isKindOfClass:[NativeAudioAsset class]]) {
                NativeAudioAsset *_asset = (NativeAudioAsset*) asset;
                [_asset setVolume:volume];
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", INFO_VOLUME_CHANGED, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString: RESULT] callbackId:callbackId];
                
            } else if ( [asset isKindOfClass:[NSNumber class]] ) {
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_TYPE_RESTRICTED, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
                
            }
            
        } else {
            
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        }
    } else {
        NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];    }
}

- (void) sendCompleteCallback:(NSString*)forId {
    NSString* callbackId = self->completeCallbacks[forId];
    if (callbackId) {
        NSDictionary* RESULT = [NSDictionary dictionaryWithObject:forId forKey:@"id"];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:RESULT] callbackId:callbackId];
        [self->completeCallbacks removeObjectForKey:forId];
    }
}

static void (mySystemSoundCompletionProc)(SystemSoundID ssID,void* clientData)
{
    NativeAudio* nativeAudio = (__bridge NativeAudio*)(clientData);
    NSNumber *idAsNum = [NSNumber numberWithInt:ssID];
    NSArray *temp = [nativeAudio->audioMapping allKeysForObject:idAsNum];
    NSString *audioID = [temp lastObject];
    
    [nativeAudio sendCompleteCallback:audioID];
    
    // Cleanup, these cb are one-shots
    AudioServicesRemoveSystemSoundCompletion(ssID);
}

- (void) addCompleteListener:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = command.callbackId;
    NSArray* arguments = command.arguments;
    NSString *audioID = [arguments objectAtIndex:0];
    
    [self.commandDelegate runInBackground:^{
        if (audioMapping) {
            
            NSObject* asset = audioMapping[audioID];
            
            if (asset != nil){
                
                if(completeCallbacks == nil) {
                    completeCallbacks = [NSMutableDictionary dictionary];
                }
                completeCallbacks[audioID] = command.callbackId;
                
                if ([asset isKindOfClass:[NativeAudioAsset class]]) {
                    NativeAudioAsset *_asset = (NativeAudioAsset*) asset;
                    [_asset setCallbackAndId:^(NSString* audioID) {
                        [self sendCompleteCallback:audioID];
                    } audioId:audioID];
                    
                } else if ( [asset isKindOfClass:[NSNumber class]] ) {
                    NSNumber *_asset = (NSNumber*) asset;
                    AudioServicesAddSystemSoundCompletion([_asset intValue],
                                                          NULL,
                                                          NULL,
                                                          mySystemSoundCompletionProc,
                                                          (__bridge void *)(self));
                }
            } else {
                
                NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
            }
            
        } else {
            
            NSString *RESULT = [NSString stringWithFormat:@"%@ (%@)", ERROR_REFERENCE_MISSING, audioID];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString: RESULT] callbackId:callbackId];
        }
    }];
}

@end