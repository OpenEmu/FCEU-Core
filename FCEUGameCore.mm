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
#include "src/emufile.h"
#include "src/cart.h"
#include "zlib.h"

extern uint8 *XBuf;
static uint32_t palette[256];

@interface FCEUGameCore () <OENESSystemResponderClient>
{
    uint32_t *videoBuffer;
    uint8_t *pXBuf;
    int32_t *soundBuffer;
    int32_t soundSize;
    uint32_t pad;
    uint32_t arkanoid[3];
    uint32_t zapper[3];
    uint32_t hypershot[4];
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
    pad = 0;
    memset(arkanoid, 0, sizeof(arkanoid));
    memset(zapper, 0, sizeof(zapper));
    memset(hypershot, 0, sizeof(hypershot));

    //newppu = 0 default off, set 1 to enable

    FCEUI_Initialize();

    NSURL *batterySavesDirectory = [NSURL fileURLWithPath:[self batterySavesDirectoryPath]];
    [[NSFileManager defaultManager] createDirectoryAtURL:batterySavesDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    //FCEUI_SetBaseDirectory([[self biosDirectoryPath] UTF8String]); unused for now
    FCEUI_SetDirOverride(FCEUIOD_NV, strdup([[batterySavesDirectory path] UTF8String]));

    FCEUI_SetSoundVolume(256);
    FCEUI_Sound(48000);

    FCEUGI *FCEUGameInfo;
    FCEUGameInfo = FCEUI_LoadGame([path UTF8String], 1, false);

    if(!FCEUGameInfo)
        return NO;

    //NSLog(@"FPS: %d", FCEUI_GetDesiredFPS() >> 24); // Hz

    FCEUI_SetInput(0, SI_GAMEPAD, &pad, 0); // Controllers 1 and 3

    if(FCEUGameInfo->input[1] == SI_ZAPPER)
        FCEUI_SetInput(1, SI_ZAPPER, &zapper, 0);
    else if(FCEUGameInfo->input[1] == SI_ARKANOID)
        FCEUI_SetInput(1, SI_ARKANOID, &arkanoid, 0);
    else
        FCEUI_SetInput(1, SI_GAMEPAD, &pad, 0); // Controllers 2 and 4

    if(FCEUGameInfo->inputfc == SIFC_SHADOW)
        FCEUI_SetInputFC(SIFC_SHADOW, &hypershot, 0);
    else if(FCEUGameInfo->inputfc == SIFC_ARKANOID)
        FCEUI_SetInputFC(SIFC_ARKANOID, &arkanoid, 0);

    extern uint32_t iNESGameCRC32;
    NSString *cartCRC32 = [NSString stringWithFormat:@"%08x", iNESGameCRC32];
    // Headerless cart data
    NSArray *fourscoreGames = @[@"1ebb5b42", // Bomberman II (USA)
                                //@"eac38105", // Championship Bowling (USA)
                                @"f99e37eb", // Chris Evert & Ivan Lendl in Top Players' Tennis (USA)
                                //@"c7f0c457", // Crash 'n' the Boys - Street Challenge (USA)
                                @"48b8ee58", // Four Players' Tennis (Europe)
                                @"27ca0679", // Danny Sullivan's Indy Heat (Europe)
                                @"c1b43207", // Danny Sullivan's Indy Heat (USA)
                                @"79f688bc", // Gauntlet II (Europe)
                                @"1b71ccdb", // Gauntlet II (USA)
                                @"1352f1b9", // Greg Norman's Golf Power (USA)
                                @"2e6ee98d", // Harlem Globetrotters (USA)
                                @"05104517", // Ivan 'Ironman' Stewart's Super Off Road (Europe)
                                @"4b041b6b", // Ivan 'Ironman' Stewart's Super Off Road (USA)
                                @"f54b34bd", // Kings of the Beach - Professional Beach Volleyball (USA)
                                @"c6c2edb5", // Magic Johnson's Fast Break (USA)
                                @"0939852f", // M.U.L.E. (USA)
                                @"2f698c4d", // Monster Truck Rally (USA)
                                @"b9b4d9e0", // NES Play Action Football (USA)
                                @"da2cb59a", // Nightmare on Elm Street, A (USA)
                                @"8da6667d", // Nintendo World Cup (Europe)
                                @"7c16f819", // Nintendo World Cup (Europe) (Rev A)
                                @"7f08d0d9", // Nintendo World Cup (Europe) (Rev B)
                                @"a22657fa", // Nintendo World Cup (USA)
                                @"308da987", // R.C. Pro-Am II (Europe)
                                @"9edd2159", // R.C. Pro-Am II (USA)
                                @"8fa6e92c", // Rackets & Rivals (Europe)
                                @"ad0394f0", // Roundball - 2-on-2 Challenge (Europe)
                                @"6e4dcfd2", // Roundball - 2-on-2 Challenge (USA)
                                @"0abdd5ca", // Spot - The Video Game (Japan)
                                @"cfae9dfa", // Spot - The Video Game (USA)
                                @"0b8f8128", // Smash T.V. (Europe)
                                @"6ee94d32", // Smash T.V. (USA)
                                @"cf4487a2", // Super Jeopardy! (USA)
                                @"c05a63b2", // Super Spike V'Ball (Europe)
                                @"e840fd21", // Super Spike V'Ball (USA)
                                @"407d6ffd", // Super Spike V'Ball + Nintendo World Cup (USA)
                                @"213cb3fb", // U.S. Championship V'Ball (Japan)
                                @"d7077d96", // U.S. Championship V'Ball (Japan) (Beta)
                                @"d153caf6", // Swords and Serpents (Europe)
                                @"46135141", // Swords and Serpents (France)
                                @"3417ec46", // Swords and Serpents (USA)
                                @"73298c87", // Super Mario Bros. + Tetris + Nintendo World Cup (Europe)
                                @"f46ef39a"  // Super Mario Bros. + Tetris + Nintendo World Cup (Europe) (Rev A)
                                ];

    // Most 3-4 player Famicom games need to set '4 player mode' in the expansion port
    NSArray *famicom4Player = @[@"c39b3bb2", // Bakutoushi Patton-Kun (Japan) (FDS)
                                @"9992f445", // Championship Bowling (Japan)
                                @"3e470fe0", // Downtown - Nekketsu Koushinkyoku - Soreyuke Daiundoukai (Japan)
                                @"4f032933", // Ike Ike! Nekketsu Hockey-bu - Subette Koronde Dairantou (Japan)
                                @"4b5177e9", // Kunio-kun no Nekketsu Soccer League (Japan)
                                @"9f03b11f", // Moero TwinBee - Cinnamon Hakase o Sukue! (Japan)
                                @"13205221", // Moero TwinBee - Cinnamon Hakase wo Sukue! (Japan) (FDS)
                                @"37e24797", // Nekketsu Kakutou Densetsu (Japan)
                                @"62c67984", // Nekketsu Koukou Dodgeball-bu (Japan)
                                @"88062d9a", // Nekketsu! Street Basket - Ganbare Dunk Heroes (Japan)
                                @"689971f9", // Super Dodge Ball (USA) (3-4p with Game Genie code GEUOLZZA)
                                @"4ff17864", // Super Dodge Ball (USA) (patched) http://www.romhacking.net/hacks/71/
                                @"b1b16b8a"  // Wit's (Japan)
                                ];

    if([fourscoreGames containsObject:cartCRC32])
        FCEUI_SetInputFourscore(true);

    if([famicom4Player containsObject:cartCRC32])
        FCEUI_SetInputFC(SIFC_4PLAYER, &pad, 0);

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

- (NSData *)serializeStateWithError:(NSError **)outError
{
    std::vector<u8> byteVector;
    EMUFILE *emuFile = new EMUFILE_MEMORY(&byteVector);
    NSData *data = nil;
    
    if(FCEUSS_SaveMS(emuFile, Z_NO_COMPRESSION))
    {
        const void *bytes = (const void *)(&byteVector[0]);
        NSUInteger length = byteVector.size();
        
        data = [NSData dataWithBytes:bytes length:length];
    }
    
    delete emuFile;
    return data;
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError **)outError
{
    u8 *bytes = (u8 *)[state bytes];
    size_t length = [state length];
    std::vector<u8> byteVector(bytes, bytes + length);
    EMUFILE *emuFile = new EMUFILE_MEMORY(&byteVector);
    
    BOOL result = FCEUSS_LoadFP(emuFile, SSLOADPARAM_NOBACKUP);
    
    delete emuFile;
    
    return result;
}

# pragma mark - Input

const int NESMap[] = {JOY_UP, JOY_DOWN, JOY_LEFT, JOY_RIGHT, JOY_A, JOY_B, JOY_START, JOY_SELECT};
- (oneway void)didPushNESButton:(OENESButton)button forPlayer:(NSUInteger)player;
{
    int playerShift = 0;
    switch (player) {
        case 1:
            playerShift = 0;
            break;
        case 2:
            playerShift = 8;
            break;
        case 3:
            playerShift = 16;
            break;
        case 4:
            playerShift = 24;
            break;
    }

    pad |= NESMap[button] << playerShift;
}

- (oneway void)didReleaseNESButton:(OENESButton)button forPlayer:(NSUInteger)player;
{
    int playerShift = 0;
    switch (player) {
        case 1:
            playerShift = 0;
            break;
        case 2:
            playerShift = 8;
            break;
        case 3:
            playerShift = 16;
            break;
        case 4:
            playerShift = 24;
            break;
    }

    pad &= ~(NESMap[button] << playerShift);
}

- (oneway void)didTriggerGunAtPoint:(OEIntPoint)aPoint
{
    [self mouseMovedAtPoint:aPoint];

    arkanoid[2] = 1;

    zapper[0] = aPoint.x * 0.800000;
    zapper[1] = aPoint.y;
    zapper[2] = 1;

    hypershot[0] = aPoint.x * 0.800000;
    hypershot[1] = aPoint.y;
    hypershot[2] = 1;
}

- (oneway void)didReleaseTrigger
{
    arkanoid[2] = 0;
    zapper[2] = 0;
    hypershot[2] = 0;
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)aPoint
{
    arkanoid[0] = aPoint.x * 0.800000;
}

- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point
{
    hypershot[3] = 1; // "move" button
}

- (oneway void)rightMouseUp;
{
    hypershot[3] = 0;
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
