/*
 Copyright (c) 2015, OpenEmu Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "FCEUGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>
#import "OENESSystemResponderClient.h"
#import <OpenGL/gl.h>

#include "src/fceu.h"
#include "src/driver.h"
#include "src/palette.h"
#include "src/state.h"

extern uint8 *XBuf;
static uint32_t palette[256];

@interface FCEUGameCore () <OENESSystemResponderClient>
{
    uint32_t *videoBuffer;
    uint8_t *pXBuf;
    int32_t *soundBuffer;
    int32_t soundSize;
    uint32_t pad[2][OENESButtonCount];
}

@end

@implementation FCEUGameCore

static __weak FCEUGameCore *_current;

- (id)init
{
    if((self = [super init]))
    {
        videoBuffer = (uint32_t *)malloc(256 * 240 * 4);
    }

	_current = self;

	return self;
}

- (void)dealloc
{
    free(videoBuffer);
}

# pragma mark - Execution

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    memset(pad, 0, sizeof(uint32_t) * OENESButtonCount);

    //newppu = 0 default off, set 1 to enable

    FCEUI_Initialize();

    //FCEUI_SetBaseDirectory([[self biosDirectoryPath] UTF8String]); unused for now
    FCEUI_SetDirOverride(FCEUIOD_NV, strdup([[self batterySavesDirectoryPath] UTF8String]));

    FCEUI_SetSoundVolume(256);
    FCEUI_Sound(48000);

    FCEUGI *FCEUGameInfo;
    FCEUGameInfo = FCEUI_LoadGame([path UTF8String], 1, false);

    if(!FCEUGameInfo)
        return NO;

    //NSLog(@"FPS: %d", FCEUI_GetDesiredFPS() >> 24); // Hz

    FCEUI_SetInput(0, SI_GAMEPAD, &pad[0], 0);
    FCEUI_SetInput(1, SI_GAMEPAD, &pad[1], 0);

    FCEU_ResetPalette();

    return YES;
}

- (void)executeFrame
{
    [self executeFrameSkippingFrame:NO];
}

- (void)executeFrameSkippingFrame:(BOOL)skip
{
    pXBuf = 0;
    soundSize = 0;

    FCEUI_Emulate(&pXBuf, &soundBuffer, &soundSize, 0);

    pXBuf = XBuf;
    for (unsigned y = 0; y < 240; y++)
        for (unsigned x = 0; x < 256; x++, pXBuf++)
            videoBuffer[y * 256 + x] = palette[*pXBuf];

    for (int i = 0; i < soundSize; i++)
        soundBuffer[i] = (soundBuffer[i] << 16) | (soundBuffer[i] & 0xffff);

    [[self ringBufferAtIndex:0] write:soundBuffer maxLength:soundSize << 2];
}

- (void)resetEmulation
{
    ResetNES();
}

- (void)stopEmulation
{
    FCEUI_CloseGame();
    FCEUI_Kill();

    [super stopEmulation];
}

- (NSTimeInterval)frameInterval
{
    return FCEUI_GetDesiredFPS() / 16777216.0;
}

# pragma mark - Video

- (const void *)videoBuffer
{
    return videoBuffer;
}

- (OEIntRect)screenRect
{
    return OEIntRectMake(0, 0, 256, 240);
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(256, 240);
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_INT_8_8_8_8_REV;
}

- (GLenum)internalPixelFormat
{
    return GL_RGB8;
}

# pragma mark - Audio

- (double)audioSampleRate
{
    return FSettings.SndRate;
}

- (NSUInteger)channelCount
{
    return 2;
}

# pragma mark - Save States

- (BOOL)saveStateToFileAtPath:(NSString *)fileName
{
    FCEUSS_Save([fileName UTF8String], false);
    return YES;
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    int success = FCEUSS_Load([fileName UTF8String], false);
    if(block) block(success==1, nil);
}

# pragma mark - Input

const int NESMap[] = {JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT, JOY_A, JOY_B, JOY_START, JOY_SELECT};
- (oneway void)didPushNESButton:(OENESButton)button forPlayer:(NSUInteger)player;
{
    int playerShift = player != 1 ? 8 : 0;

    pad[player - 1][0] |= NESMap[button] << playerShift;
}

- (oneway void)didReleaseNESButton:(OENESButton)button forPlayer:(NSUInteger)player;
{
    int playerShift = player != 1 ? 8 : 0;

    pad[player - 1][0] &= ~NESMap[button] << playerShift;
}

// FCEUX internal functions and stubs
void FCEUD_SetPalette(unsigned char index, unsigned char r, unsigned char g, unsigned char b)
{
    palette[index] = ( r << 16 ) | ( g << 8 ) | b;
}

void FCEUD_GetPalette(unsigned char i, unsigned char *r, unsigned char *g, unsigned char *b) {}
uint64 FCEUD_GetTime(void) {return 0;}
uint64 FCEUD_GetTimeFreq(void) {return 0;}
const char *GetKeyboard(void) {return "";}
bool turbo = false;
int closeFinishedMovie = 0;
int FCEUD_ShowStatusIcon(void) {return 0;}
int FCEUD_SendData(void *data, uint32 len) {return 1;}
int FCEUD_RecvData(void *data, uint32 len) {return 1;}
FILE *FCEUD_UTF8fopen(const char *fn, const char *mode)
{
    return fopen(fn, mode);
}
EMUFILE_FILE *FCEUD_UTF8_fstream(const char *fn, const char *m)
{
    std::ios_base::openmode mode = std::ios_base::binary;
    if(!strcmp(m,"r") || !strcmp(m,"rb"))
        mode |= std::ios_base::in;
    else if(!strcmp(m,"w") || !strcmp(m,"wb"))
        mode |= std::ios_base::out | std::ios_base::trunc;
    else if(!strcmp(m,"a") || !strcmp(m,"ab"))
        mode |= std::ios_base::out | std::ios_base::app;
    else if(!strcmp(m,"r+") || !strcmp(m,"r+b"))
        mode |= std::ios_base::in | std::ios_base::out;
    else if(!strcmp(m,"w+") || !strcmp(m,"w+b"))
        mode |= std::ios_base::in | std::ios_base::out | std::ios_base::trunc;
    else if(!strcmp(m,"a+") || !strcmp(m,"a+b"))
        mode |= std::ios_base::in | std::ios_base::out | std::ios_base::app;
    return new EMUFILE_FILE(fn, m);
    //return new std::fstream(fn,mode);
}
void FCEUD_NetplayText(uint8 *text) {};
void FCEUD_NetworkClose(void) {}
void FCEUD_VideoChanged (void) {}
bool FCEUD_ShouldDrawInputAids() {return false;}
bool FCEUD_PauseAfterPlayback() {return false;}
void FCEUI_AviVideoUpdate(const unsigned char* buffer) {}
bool FCEUI_AviEnableHUDrecording() {return false;}
bool FCEUI_AviIsRecording(void) {return false;}
bool FCEUI_AviDisableMovieMessages() {return true;}
FCEUFILE *FCEUD_OpenArchiveIndex(ArchiveScanRecord &asr, std::string &fname, int innerIndex) {return 0;}
FCEUFILE *FCEUD_OpenArchive(ArchiveScanRecord &asr, std::string &fname, std::string *innerFilename) {return 0;}
ArchiveScanRecord FCEUD_ScanArchive(std::string fname) { return ArchiveScanRecord(); }
void FCEUD_PrintError(const char *s)
{
    NSLog(@"FCEUX error: %s", s);
}
void FCEUD_Message(const char *s)
{
    NSLog(@"FCEUX message: %s", s);
}

@end
