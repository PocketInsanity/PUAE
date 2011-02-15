/*
 * UAE - The Un*x Amiga Emulator
 *
 * Interface to the Cocoa Mac OS X GUI
 *
 * Copyright 1996 Bernd Schmidt
 * Copyright 2004,2010 Steven J. Saunders
 *           2010 Mustafa TUFAN
 */
#include <stdlib.h>
#include <stdarg.h>

#include "sysconfig.h"
#include "sysdeps.h"

#include "uae.h"
#include "options.h"
#include "gui.h"
#include "inputdevice.h"
#include "disk.h"
#include "ar.h"

#include "custom.h"
#include "xwin.h"
#include "drawing.h"

#ifdef USE_SDL
#include "SDL.h"
#endif

// MacOSX < 10.5
#ifndef NSINTEGER_DEFINED
#define NSINTEGER_DEFINED
#ifdef __LP64__ || NS_BUILD_32_LIKE_64
typedef long           NSInteger;
typedef unsigned long  NSUInteger;
#define NSIntegerMin   LONG_MIN
#define NSIntegerMax   LONG_MAX
#define NSUIntegerMax  ULONG_MAX
#else
typedef int            NSInteger;
typedef unsigned int   NSUInteger;
#define NSIntegerMin   INT_MIN
#define NSIntegerMax   INT_MAX
#define NSUIntegerMax  UINT_MAX
#endif
#endif


static unsigned long memsizes[] = {
        /* 0 */ 0,  
        /* 1 */ 0x00040000, /* 256K */
        /* 2 */ 0x00080000, /* 512K */
        /* 3 */ 0x00100000, /* 1M */
        /* 4 */ 0x00200000, /* 2M */
        /* 5 */ 0x00400000, /* 4M */
        /* 6 */ 0x00800000, /* 8M */
        /* 7 */ 0x01000000, /* 16M */
        /* 8 */ 0x02000000, /* 32M */
        /* 9 */ 0x04000000, /* 64M */
        /* 10*/ 0x08000000, //128M
        /* 11*/ 0x10000000, //256M
        /* 12*/ 0x20000000, //512M
        /* 13*/ 0x40000000, //1GB
        /* 14*/ 0x00180000, //1.5MB
        /* 15*/ 0x001C0000, //1.8MB
        /* 16*/ 0x80000000, //2GB
        /* 17*/ 0x18000000, //384M
        /* 18*/ 0x30000000, //768M
        /* 19*/ 0x60000000, //1.5GB
        /* 20*/ 0xA8000000, //2.5GB
        /* 21*/ 0xC0000000, //3GB
};

//----------

#import <Cocoa/Cocoa.h>

/* The GTK GUI code seems to use 255 as max path length. Not sure why it 
 * doesn't use MAX_DPATH... but we will follow its example.
 */
#define COCOA_GUI_MAX_PATH 255

/* These prototypes aren't declared in the sdlgfx header for some reason */
extern void toggle_fullscreen (int mode);
extern int is_fullscreen (void);

/* Defined in SDLmain.m */
extern NSString *getApplicationName(void);

/* Prototypes */
int ensureNotFullscreen (void);
void restoreFullscreen (void);
void lossyASCIICopy (char *buffer, NSString *source, size_t maxLength);

/* Globals */
static BOOL wasFullscreen = NO; // used by ensureNotFullscreen() and restoreFullscreen()

/* Objective-C class for an object to respond to events */
@interface PuaeGui : NSObject
{
    NSString *applicationName;
    NSArray *diskImageTypes;
}
+ (id) sharedInstance;
- (void)createMenus;
- (void)createMenuItemInMenu:(NSMenu *)menu withTitle:(NSString *)title action:(SEL)anAction tag:(int)tag;
- (void)createMenuItemInMenu:(NSMenu *)menu withTitle:(NSString *)title action:(SEL)anAction tag:(int)tag
    keyEquivalent:(NSString *)keyEquiv keyEquivalentMask:(NSUInteger)mask;
- (BOOL)validateMenuItem:(id <NSMenuItem>)item;
- (void)insertDisk:(id)sender;
- (void)ejectDisk:(id)sender;
- (void)ejectAllDisks:(id)sender;
- (void)changePort0:(id)sender;
- (void)changePort1:(id)sender;
- (void)swapGamePorts:(id)sender;
- (void)displayOpenPanelForInsertIntoDriveNumber:(int)driveNumber;
- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)resetAmiga:(id)sender;
- (void)pauseAmiga:(id)sender;
#ifdef ACTION_REPLAY
- (void)actionReplayFreeze:(id)sender;
#endif
- (void)grabMouse:(id)sender;
- (void)goFullscreen:(id)sender;
- (void)toggleInhibitDisplay:(id)sender;
- (void)changeChipMem:(id)sender;
- (void)changeBogoMem:(id)sender;
- (void)changeFastMem:(id)sender;
- (void)changeZ3FastMem:(id)sender;
- (void)changeZ3ChipMem:(id)sender;
- (void)changeGfxMem:(id)sender;
- (void)changeCPU:(id)sender;
- (void)changeCPUSpeed:(id)sender;
- (void)changeFPU:(id)sender;
@end

@implementation PuaeGui

+ (id) sharedInstance
{
    static id sharedInstance = nil;

    if (sharedInstance == nil) sharedInstance = [[self alloc] init];

    return sharedInstance;
}

-(PuaeGui *) init
{
    self = [super init];

    if (self) {
        applicationName = [[NSString alloc] initWithString:getApplicationName()];
        diskImageTypes =[[NSArray alloc] initWithObjects:@"adf", @"adz",
            @"zip", @"dms", @"fdi", 
#ifdef CAPS        
            @"ipf",
#endif
            nil]; // Note: Use lowercase for these
    }

    return self;
}

-(void) dealloc
{
    [applicationName release];
    [diskImageTypes release];
    [super dealloc];
}

-(NSArray *) diskImageTypes
{
    return diskImageTypes;
}

-(NSString *)applicationName
{
    return applicationName;
}

- (void)createMenus
{
    int driveNumber;
    NSMenuItem *menuItem;
    NSString *menuTitle;

	// Create a menu for manipulating the emulated amiga
	NSMenu *vAmigaMenu = [[NSMenu alloc] initWithTitle:@"PUAE"];
	
	[self createMenuItemInMenu:vAmigaMenu withTitle:@"Reset" action:@selector(resetAmiga:) tag:0];
	[self createMenuItemInMenu:vAmigaMenu withTitle:@"Hard Reset" action:@selector(resetAmiga:) tag:1];
//	[self createMenuItemInMenu:vAmigaMenu withTitle:@"Hebe" action:@selector(hebeHebe:) tag:0];
//	[self createMenuItemInMenu:vAmigaMenu withTitle:@"Pause" action:@selector(pauseAmiga:) tag:0];
	
#ifdef ACTION_REPLAY
	[self createMenuItemInMenu:vAmigaMenu
                     withTitle:@"Action Replay Freeze"
                        action:@selector(actionReplayFreeze:)
                           tag:0];
#endif

	[vAmigaMenu addItem:[NSMenuItem separatorItem]];
	
	// Add menu items for inserting into floppy drives 1 - 4
	NSMenu *insertFloppyMenu = [[NSMenu alloc] initWithTitle:@"Insert Floppy"];
	
	for (driveNumber=0; driveNumber<4; driveNumber++) {
        [self createMenuItemInMenu:insertFloppyMenu
                         withTitle:[NSString stringWithFormat:@"DF%d...",driveNumber]
                            action:@selector(insertDisk:)
                               tag:driveNumber];
    }

	menuItem = [[NSMenuItem alloc] initWithTitle:@"Insert Floppy" action:nil keyEquivalent:@""];
	[menuItem setSubmenu:insertFloppyMenu];
	[vAmigaMenu addItem:menuItem];
	[menuItem release];
	
	[insertFloppyMenu release];
	
	// Add menu items for ejecting from floppy drives 1 - 4
	NSMenu *ejectFloppyMenu = [[NSMenu alloc] initWithTitle:@"Eject Floppy"];
	
	[self createMenuItemInMenu:ejectFloppyMenu withTitle:@"All" action:@selector(ejectAllDisks:) tag:0];
	
	[ejectFloppyMenu addItem:[NSMenuItem separatorItem]];
	
	for (driveNumber=0; driveNumber<4; driveNumber++) {
        [self createMenuItemInMenu:ejectFloppyMenu
                         withTitle:[NSString stringWithFormat:@"DF%d",driveNumber]
                            action:@selector(ejectDisk:)
                               tag:driveNumber];
    }

	menuItem = [[NSMenuItem alloc] initWithTitle:@"Eject Floppy" action:nil keyEquivalent:@""];
	[menuItem setSubmenu:ejectFloppyMenu];
	[vAmigaMenu addItem:menuItem];
	[menuItem release];
	
	[ejectFloppyMenu release];

	menuItem = [[NSMenuItem alloc] initWithTitle:@"PUAE" action:nil keyEquivalent:@""];
	[menuItem setSubmenu:vAmigaMenu];

	[[NSApp mainMenu] insertItem:menuItem atIndex:1];
	
	[menuItem release];
	[vAmigaMenu release];

	// MEM MENU START
	NSMenu *memMenu = [[NSMenu alloc] initWithTitle:@"Memory"];

		NSMenu *chipMenu = [[NSMenu alloc] initWithTitle:@"Chip Mem"];
			[self createMenuItemInMenu:chipMenu withTitle:@"256 KB" action:@selector(changeChipMem:) tag:1];
			[self createMenuItemInMenu:chipMenu withTitle:@"512 KB" action:@selector(changeChipMem:) tag:2];
			[self createMenuItemInMenu:chipMenu withTitle:@"1 MB" action:@selector(changeChipMem:) tag:3];
			[self createMenuItemInMenu:chipMenu withTitle:@"1.5 MB" action:@selector(changeChipMem:) tag:14];
			[self createMenuItemInMenu:chipMenu withTitle:@"2 MB" action:@selector(changeChipMem:) tag:4];
			[self createMenuItemInMenu:chipMenu withTitle:@"4 MB" action:@selector(changeChipMem:) tag:5];
			[self createMenuItemInMenu:chipMenu withTitle:@"8 MB" action:@selector(changeChipMem:) tag:6];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"Chip Mem" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:chipMenu];
		[memMenu addItem:menuItem];
		[menuItem release];

		NSMenu *bogoMenu = [[NSMenu alloc] initWithTitle:@"Bogo Mem"];
			[self createMenuItemInMenu:bogoMenu withTitle:@"None" action:@selector(changeBogoMem:) tag:0];
			[self createMenuItemInMenu:bogoMenu withTitle:@"512 KB" action:@selector(changeBogoMem:) tag:2];
			[self createMenuItemInMenu:bogoMenu withTitle:@"1 MB" action:@selector(changeBogoMem:) tag:3];
			[self createMenuItemInMenu:bogoMenu withTitle:@"1.5 MB" action:@selector(changeBogoMem:) tag:14];
			[self createMenuItemInMenu:bogoMenu withTitle:@"1.8 MB" action:@selector(changeBogoMem:) tag:15];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"Bogo Mem" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:bogoMenu];
		[memMenu addItem:menuItem];
		[menuItem release];

		NSMenu *fastMenu = [[NSMenu alloc] initWithTitle:@"Fast Mem"];
			[self createMenuItemInMenu:fastMenu withTitle:@"None" action:@selector(changeFastMem:) tag:0];
			[self createMenuItemInMenu:fastMenu withTitle:@"1 MB" action:@selector(changeFastMem:) tag:3];
			[self createMenuItemInMenu:fastMenu withTitle:@"2 MB" action:@selector(changeFastMem:) tag:4];
			[self createMenuItemInMenu:fastMenu withTitle:@"4 MB" action:@selector(changeFastMem:) tag:5];
			[self createMenuItemInMenu:fastMenu withTitle:@"8 MB" action:@selector(changeFastMem:) tag:6];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"Fast Mem" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:fastMenu];
		[memMenu addItem:menuItem];
		[menuItem release];

		NSMenu *z3fastMenu = [[NSMenu alloc] initWithTitle:@"Z3 Fast Mem"];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"None" action:@selector(changeZ3FastMem:) tag:0];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"1 MB" action:@selector(changeZ3FastMem:) tag:3];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"2 MB" action:@selector(changeZ3FastMem:) tag:4];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"4 MB" action:@selector(changeZ3FastMem:) tag:5];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"8 MB" action:@selector(changeZ3FastMem:) tag:6];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"16 MB" action:@selector(changeZ3FastMem:) tag:7];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"32 MB" action:@selector(changeZ3FastMem:) tag:8];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"64 MB" action:@selector(changeZ3FastMem:) tag:9];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"128 MB" action:@selector(changeZ3FastMem:) tag:10];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"256 MB" action:@selector(changeZ3FastMem:) tag:11];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"384 MB" action:@selector(changeZ3FastMem:) tag:17];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"512 MB" action:@selector(changeZ3FastMem:) tag:12];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"768 MB" action:@selector(changeZ3FastMem:) tag:18];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"1 GB" action:@selector(changeZ3FastMem:) tag:13];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"1.5 GB" action:@selector(changeZ3FastMem:) tag:19];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"2 GB" action:@selector(changeZ3FastMem:) tag:16];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"2.5 GB" action:@selector(changeZ3FastMem:) tag:20];
			[self createMenuItemInMenu:z3fastMenu withTitle:@"3 GB" action:@selector(changeZ3FastMem:) tag:21];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"Z3 Fast Mem" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:z3fastMenu];
		[memMenu addItem:menuItem];
		[menuItem release];

		NSMenu *z3chipMenu = [[NSMenu alloc] initWithTitle:@"Z3 Chip Mem"];
			[self createMenuItemInMenu:z3chipMenu withTitle:@"None" action:@selector(changeZ3ChipMem:) tag:0];
			[self createMenuItemInMenu:z3chipMenu withTitle:@"16 MB" action:@selector(changeZ3ChipMem:) tag:7];
			[self createMenuItemInMenu:z3chipMenu withTitle:@"32 MB" action:@selector(changeZ3ChipMem:) tag:8];
			[self createMenuItemInMenu:z3chipMenu withTitle:@"64 MB" action:@selector(changeZ3ChipMem:) tag:9];
			[self createMenuItemInMenu:z3chipMenu withTitle:@"128 MB" action:@selector(changeZ3ChipMem:) tag:10];
			[self createMenuItemInMenu:z3chipMenu withTitle:@"256 MB" action:@selector(changeZ3ChipMem:) tag:11];
			[self createMenuItemInMenu:z3chipMenu withTitle:@"512 MB" action:@selector(changeZ3ChipMem:) tag:12];
			[self createMenuItemInMenu:z3chipMenu withTitle:@"1 GB" action:@selector(changeZ3ChipMem:) tag:13];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"Z3 Chip Mem" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:z3chipMenu];
		[memMenu addItem:menuItem];
		[menuItem release];

		NSMenu *gfxMenu = [[NSMenu alloc] initWithTitle:@"Gfx Mem"];
			[self createMenuItemInMenu:gfxMenu withTitle:@"None" action:@selector(changeGfxMem:) tag:0];
			[self createMenuItemInMenu:gfxMenu withTitle:@"1 MB" action:@selector(changeGfxMem:) tag:3];
			[self createMenuItemInMenu:gfxMenu withTitle:@"2 MB" action:@selector(changeGfxMem:) tag:4];
			[self createMenuItemInMenu:gfxMenu withTitle:@"4 MB" action:@selector(changeGfxMem:) tag:5];
			[self createMenuItemInMenu:gfxMenu withTitle:@"8 MB" action:@selector(changeGfxMem:) tag:6];
			[self createMenuItemInMenu:gfxMenu withTitle:@"16 MB" action:@selector(changeGfxMem:) tag:7];
			[self createMenuItemInMenu:gfxMenu withTitle:@"32 MB" action:@selector(changeGfxMem:) tag:8];
			[self createMenuItemInMenu:gfxMenu withTitle:@"64 MB" action:@selector(changeGfxMem:) tag:9];
			[self createMenuItemInMenu:gfxMenu withTitle:@"128 MB" action:@selector(changeGfxMem:) tag:10];
			[self createMenuItemInMenu:gfxMenu withTitle:@"256 MB" action:@selector(changeGfxMem:) tag:11];
			[self createMenuItemInMenu:gfxMenu withTitle:@"512 MB" action:@selector(changeGfxMem:) tag:12];
			[self createMenuItemInMenu:gfxMenu withTitle:@"1 GB" action:@selector(changeGfxMem:) tag:13];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"Gfx Mem" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:gfxMenu];
		[memMenu addItem:menuItem];
		[menuItem release];

	menuItem = [[NSMenuItem alloc] initWithTitle:@"Memory" action:nil keyEquivalent:@""];
	[menuItem setSubmenu:memMenu];
	[[NSApp mainMenu] insertItem:menuItem atIndex:2];
	[memMenu release];
	[menuItem release];
	// MEM MENU END

	// CHIPSET MENU START
	NSMenu *systemMenu = [[NSMenu alloc] initWithTitle:@"System"];

		NSMenu *cpuMenu = [[NSMenu alloc] initWithTitle:@"CPU"];
			[self createMenuItemInMenu:cpuMenu withTitle:@"68000" action:@selector(changeCPU:) tag:0];
			[self createMenuItemInMenu:cpuMenu withTitle:@"68010" action:@selector(changeCPU:) tag:1];
			[self createMenuItemInMenu:cpuMenu withTitle:@"68020" action:@selector(changeCPU:) tag:2];
			[self createMenuItemInMenu:cpuMenu withTitle:@"68030" action:@selector(changeCPU:) tag:3];
			[self createMenuItemInMenu:cpuMenu withTitle:@"68040" action:@selector(changeCPU:) tag:4];
			[self createMenuItemInMenu:cpuMenu withTitle:@"68060" action:@selector(changeCPU:) tag:6];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"CPU" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:cpuMenu];
		[systemMenu addItem:menuItem];
		[menuItem release];

		NSMenu *cpuspeedMenu = [[NSMenu alloc] initWithTitle:@"CPU Speed"];
			[self createMenuItemInMenu:cpuspeedMenu withTitle:@"Fastest Possible but maintain chipset timing" action:@selector(changeCPUSpeed:) tag:0];
			[self createMenuItemInMenu:cpuspeedMenu withTitle:@"Approximate A500/A1200 Cycle Exact" action:@selector(changeCPUSpeed:) tag:1];
			[self createMenuItemInMenu:cpuspeedMenu withTitle:@"Cycle Exact" action:@selector(changeCPUSpeed:) tag:2];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"CPU Speed" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:cpuspeedMenu];
		[systemMenu addItem:menuItem];
		[menuItem release];

		NSMenu *fpuMenu = [[NSMenu alloc] initWithTitle:@"FPU"];
			[self createMenuItemInMenu:fpuMenu withTitle:@"None" action:@selector(changeFPU:) tag:0];
			[self createMenuItemInMenu:fpuMenu withTitle:@"68881" action:@selector(changeFPU:) tag:1];
			[self createMenuItemInMenu:fpuMenu withTitle:@"68882" action:@selector(changeFPU:) tag:2];
			[self createMenuItemInMenu:fpuMenu withTitle:@"CPU Internal" action:@selector(changeFPU:) tag:3];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"FPU" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:fpuMenu];
		[systemMenu addItem:menuItem];
		[menuItem release];

		NSMenu *chipsetMenu = [[NSMenu alloc] initWithTitle:@"Chipset"];
			[self createMenuItemInMenu:chipsetMenu withTitle:@"OCS" action:@selector(changeChipset:) tag:0];
			[self createMenuItemInMenu:chipsetMenu withTitle:@"ECS Agnus" action:@selector(changeChipset:) tag:1];
			[self createMenuItemInMenu:chipsetMenu withTitle:@"ECS Denise" action:@selector(changeChipset:) tag:2];
			[self createMenuItemInMenu:chipsetMenu withTitle:@"ECS Full" action:@selector(changeChipset:) tag:3];
			[self createMenuItemInMenu:chipsetMenu withTitle:@"AGA" action:@selector(changeChipset:) tag:4];
		menuItem = [[NSMenuItem alloc] initWithTitle:@"Chipset" action:nil keyEquivalent:@""];
		[menuItem setSubmenu:chipsetMenu];
		[systemMenu addItem:menuItem];
		[menuItem release];

	menuItem = [[NSMenuItem alloc] initWithTitle:@"System" action:nil keyEquivalent:@""];
	[menuItem setSubmenu:systemMenu];
	[[NSApp mainMenu] insertItem:menuItem atIndex:3];
	[systemMenu release];
	[menuItem release];
	// CHIPSET MENU END

	// Create a menu for changing aspects of emulator control
	NSMenu *controlMenu = [[NSMenu alloc] initWithTitle:@"Control"];

	NSMenu *portMenu = [[NSMenu alloc] initWithTitle:@"Game Port 0"];

    [self createMenuItemInMenu:portMenu withTitle:@"None" action:@selector(changePort0:) tag:JSEM_END];
    [self createMenuItemInMenu:portMenu withTitle:@"Joystick 0" action:@selector(changePort0:) tag:JSEM_JOYS];
    [self createMenuItemInMenu:portMenu withTitle:@"Joystick 1" action:@selector(changePort0:) tag:JSEM_JOYS+1];
    [self createMenuItemInMenu:portMenu withTitle:@"Mouse" action:@selector(changePort0:) tag:JSEM_MICE];
    [self createMenuItemInMenu:portMenu withTitle:@"Keyboard Layout A (NumPad, 0 & 5 = Fire)" action:@selector(changePort0:) tag:JSEM_KBDLAYOUT];
    [self createMenuItemInMenu:portMenu withTitle:@"Keyboard Layout B (Cursor, RCtrl & Alt = Fire)" action:@selector(changePort0:) tag:JSEM_KBDLAYOUT+1];
    [self createMenuItemInMenu:portMenu withTitle:@"Keyboard Layout C (WASD, LAlt = Fire)" action:@selector(changePort0:) tag:JSEM_KBDLAYOUT+2];
#ifdef ARCADE
    [self createMenuItemInMenu:portMenu withTitle:@"X-Arcade (Left)" action:@selector(changePort0:) tag:JSEM_KBDLAYOUT+3];
    [self createMenuItemInMenu:portMenu withTitle:@"X-Arcade (Right)" action:@selector(changePort0:) tag:JSEM_KBDLAYOUT+4];
#endif

    menuItem = [[NSMenuItem alloc] initWithTitle:@"Game Port 0" action:nil keyEquivalent:@""];
    [menuItem setSubmenu:portMenu];
    [controlMenu addItem:menuItem];
    [menuItem release];

	[portMenu release];
	
	portMenu = [[NSMenu alloc] initWithTitle:@"Game Port 1"];

    [self createMenuItemInMenu:portMenu withTitle:@"None" action:@selector(changePort1:) tag:JSEM_END];
    [self createMenuItemInMenu:portMenu withTitle:@"Joystick 0" action:@selector(changePort1:) tag:JSEM_JOYS];
    [self createMenuItemInMenu:portMenu withTitle:@"Joystick 1" action:@selector(changePort1:) tag:JSEM_JOYS+1];
    [self createMenuItemInMenu:portMenu withTitle:@"Mouse" action:@selector(changePort1:) tag:JSEM_MICE];
    [self createMenuItemInMenu:portMenu withTitle:@"Keyboard Layout A (NumPad, 0 & 5 = Fire)" action:@selector(changePort1:) tag:JSEM_KBDLAYOUT];
    [self createMenuItemInMenu:portMenu withTitle:@"Keyboard Layout B (Cursor, RCtrl & Alt = Fire)" action:@selector(changePort1:) tag:JSEM_KBDLAYOUT+1];
    [self createMenuItemInMenu:portMenu withTitle:@"Keyboard Layout C (WASD, LAlt = Fire)" action:@selector(changePort1:) tag:JSEM_KBDLAYOUT+2];
#ifdef ARCADE
    [self createMenuItemInMenu:portMenu withTitle:@"X-Arcade (Left)" action:@selector(changePort1:) tag:JSEM_KBDLAYOUT+3];
    [self createMenuItemInMenu:portMenu withTitle:@"X-Arcade (Right)" action:@selector(changePort1:) tag:JSEM_KBDLAYOUT+4];
#endif

    menuItem = [[NSMenuItem alloc] initWithTitle:@"Game Port 1" action:nil keyEquivalent:@""];
    [menuItem setSubmenu:portMenu];
    [controlMenu addItem:menuItem];
    [menuItem release];

	[portMenu release];

	[self createMenuItemInMenu:controlMenu withTitle:@"Swap Port 0 and 1" action:@selector(swapGamePorts:) tag:0];

	[controlMenu addItem:[NSMenuItem separatorItem]];
	
	[self createMenuItemInMenu:controlMenu withTitle:@"Grab Mouse" action:@selector(grabMouse:) tag:0 
		keyEquivalent:@"g" keyEquivalentMask:NSCommandKeyMask|NSAlternateKeyMask];
	
    menuItem = [[NSMenuItem alloc] initWithTitle:@"Control" action:nil keyEquivalent:@""];
    [menuItem setSubmenu:controlMenu];

    [[NSApp mainMenu] insertItem:menuItem atIndex:4];

    [controlMenu release];
    [menuItem release];

	// Create a menu for changing aspects of emulator control
    NSMenu *displayMenu = [[NSMenu alloc] initWithTitle:@"Display"];

	[self createMenuItemInMenu:displayMenu withTitle:@"Fullscreen" action:@selector(goFullscreen:) tag:0 
		keyEquivalent:@"s" keyEquivalentMask:NSCommandKeyMask|NSAlternateKeyMask];
		
	[self createMenuItemInMenu:displayMenu withTitle:@"Inhibit" action:@selector(toggleInhibitDisplay:) tag:0];
	
	menuItem = [[NSMenuItem alloc] initWithTitle:@"Display" action:nil keyEquivalent:@""];
    [menuItem setSubmenu:displayMenu];

    [[NSApp mainMenu] insertItem:menuItem atIndex:5];

	[displayMenu release];
	[menuItem release];
}

- (void)createMenuItemInMenu:(NSMenu *)menu withTitle:(NSString *)title action:(SEL)anAction tag:(int)tag
{
	[self createMenuItemInMenu:menu withTitle:title action:anAction tag:tag
		keyEquivalent:@"" keyEquivalentMask:NSCommandKeyMask];
}

- (void)createMenuItemInMenu:(NSMenu *)menu withTitle:(NSString *)title action:(SEL)anAction tag:(int)tag
    keyEquivalent:(NSString *)keyEquiv keyEquivalentMask:(NSUInteger)mask
{
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title action:anAction keyEquivalent:keyEquiv];
	[menuItem setKeyEquivalentModifierMask:mask];
    [menuItem setTag:tag];
    [menuItem setTarget:self];
    [menu addItem:menuItem];
    [menuItem release];
}

- (BOOL)validateMenuItem:(id <NSMenuItem>)item
{
	NSMenuItem *menuItem = (NSMenuItem *)item;
	
	BOOL canSetHidden = [menuItem respondsToSelector:@selector(setHidden:)];
	
    SEL menuAction = [menuItem action];
    int tag = [menuItem tag];

    // Disabled drives can't have disks inserted or ejected
    if ((menuAction == @selector(insertDisk:)) || (menuAction == @selector(ejectDisk:))) {
		if (gui_data.drive_disabled[tag]) {
			//if (canSetHidden) [menuItem setHidden:YES];
			return NO;
		} else {
			//if (canSetHidden) [menuItem setHidden:NO];
		}
	}
        
    // Eject DFx should be disabled if there's no disk in DFx
	if (menuAction == @selector(ejectDisk:)) {
		if (disk_empty(tag)) {
			[menuItem setTitle:[NSString stringWithFormat:@"DF%d",tag]];
			return NO;
		}
		
		// There's a disk in the drive, show its name in the menu item
		NSString *diskImage = [[NSString stringWithCString:gui_data.df[tag] encoding:NSASCIIStringEncoding] lastPathComponent];
		[menuItem setTitle:[NSString stringWithFormat:@"DF%d (%@)",tag,diskImage]];
		//if (canSetHidden) [menuItem setHidden:NO];
		return YES;
	}

    // The current settings for the joystick/mouse ports should be indicated
    if (menuAction == @selector(changePort0:)) {
        if (currprefs.jports[0].id == tag) [menuItem setState:NSOnState];
        else [menuItem setState:NSOffState];

        // and joystick options should be unavailable if there are no joysticks
        if (((tag == JSEM_JOYS) || (tag == (JSEM_JOYS+1)))) {
			if ((tag - JSEM_JOYS) >= inputdevice_get_device_total (IDTYPE_JOYSTICK))
				return NO;
		}

        // and we should not allow both ports to be set to the same setting
        if ((tag != JSEM_END) && (currprefs.jports[1].id == tag))
            return NO;

        return YES;
    }

	// Repeat the above for Port 1
	if (menuAction == @selector(changePort1:)) {
		if (currprefs.jports[1].id == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];

		if (((tag == JSEM_JOYS) || (tag == (JSEM_JOYS+1)))) {
			if ((tag - JSEM_JOYS) >= inputdevice_get_device_total (IDTYPE_JOYSTICK))
				return NO;
		}

		if ((tag != JSEM_END) && (currprefs.jports[0].id == tag))
			return NO;

		return YES;
	}

	long mem_size, v;
	if (menuAction == @selector(changeChipMem:)) {
		mem_size = 0;
	        switch (currprefs.chipmem_size) {
		        case 0x00040000: mem_size = 1; break;
		        case 0x00080000: mem_size = 2; break;
		        case 0x00100000: mem_size = 3; break;
		        case 0x00180000: mem_size = 14; break;
		        case 0x00200000: mem_size = 4; break;
		        case 0x00400000: mem_size = 5; break;
		        case 0x00800000: mem_size = 6; break;
        	}
		if (mem_size == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeBogoMem:)) {
		mem_size = 0;
	        switch (currprefs.bogomem_size) {
		        case 0x00000000: mem_size = 0; break;
        		case 0x00080000: mem_size = 2; break;
	        	case 0x00100000: mem_size = 3; break;
        		case 0x00180000: mem_size = 14; break;
		        case 0x001C0000: mem_size = 15; break;
	        }
		if (mem_size == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeFastMem:)) {
		mem_size = 0;
        	switch (currprefs.fastmem_size) {
		        case 0x00000000: mem_size = 0; break;
		        case 0x00100000: mem_size = 3; break;
	        	case 0x00200000: mem_size = 4; break;
		        case 0x00400000: mem_size = 5; break;
		        case 0x00800000: mem_size = 6; break;
	        }
		if (mem_size == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeZ3FastMem:)) {
		mem_size = 0;
        	v = currprefs.z3fastmem_size + currprefs.z3fastmem2_size;
	        if      (v < 0x00100000)
        	        mem_size = 0;
	        else if (v < 0x00200000)
        	        mem_size = 3;
	        else if (v < 0x00400000)
        	        mem_size = 4;
	        else if (v < 0x00800000)
        	        mem_size = 5;
	        else if (v < 0x01000000)
        	        mem_size = 6;
	        else if (v < 0x02000000)
        	        mem_size = 7;
	        else if (v < 0x04000000)
        	        mem_size = 8;
	        else if (v < 0x08000000)
        	        mem_size = 9;
	        else if (v < 0x10000000)
        	        mem_size = 10;
	        else if (v < 0x18000000)
        	        mem_size = 11;
	        else if (v < 0x20000000)
        	        mem_size = 17;
	        else if (v < 0x30000000)
        	        mem_size = 12;
	        else if (v < 0x40000000) // 1GB
        	        mem_size = 18;
	        else if (v < 0x60000000) // 1.5GB
        	        mem_size = 13;
	        else if (v < 0x80000000) // 2GB
        	        mem_size = 19;
	        else if (v < 0xA8000000) // 2.5GB
        	        mem_size = 16;
	        else if (v < 0xC0000000) // 3GB
                	mem_size = 20;
        	else
	                mem_size = 21;

		if (mem_size == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeZ3ChipMem:)) {
		mem_size = 0;
        	v = currprefs.z3chipmem_size;
	        if (v < 0x01000000)
        	        mem_size = 0;
	        else if (v < 0x02000000)
        	        mem_size = 7;
	        else if (v < 0x04000000)
        	        mem_size = 8;
	        else if (v < 0x08000000)
        	        mem_size = 9;
	        else if (v < 0x10000000)
        	        mem_size = 10;
	        else if (v < 0x20000000)
        	        mem_size = 11;
	        else if (v < 0x40000000)
                	mem_size = 12;
        	else
	                mem_size = 13;

		if (mem_size == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeGfxMem:)) {
	        mem_size = 0;
	        switch (currprefs.gfxmem_size) {
        		case 0x00000000: mem_size = 0; break;
	        	case 0x00100000: mem_size = 3; break;
		        case 0x00200000: mem_size = 4; break;
        		case 0x00400000: mem_size = 5; break;
	        	case 0x00800000: mem_size = 6; break;
	        	case 0x01000000: mem_size = 7; break;
		        case 0x02000000: mem_size = 8; break;
        		case 0x04000000: mem_size = 9; break;
	        	case 0x08000000: mem_size = 10; break;
		        case 0x10000000: mem_size = 11; break;
	        	case 0x20000000: mem_size = 12; break;
	        	case 0x40000000: mem_size = 13; break;
	        }
		if (mem_size == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeChipset:)) {
		v = 0;
        	switch (currprefs.chipset_mask) {
		        case 0: v = 0; break;
        		case 1: v = 1; break;
	        	case 2: v = 2; break;
        		case 3: v = 3; break;
		        case 4: v = 4; break;
        		case 7: v = 4; break;
	        }
		if (v == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeCPU:)) {
		v = (currprefs.cpu_model - 68000) / 10;
		if (v == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeCPUSpeed:)) {
		if (currprefs.cpu_cycle_exact == 1) {
			v = 2;
		} else {
			if (currprefs.m68k_speed == -1) v = 0;
			if (currprefs.m68k_speed == 0) v = 1;
		}
		if (v == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(changeFPU:)) {
		v = currprefs.fpu_model == 0 ? 0 : (currprefs.fpu_model == 68881 ? 1 : (currprefs.fpu_model == 68882 ? 2 : 3));
		if (v == tag) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}
	
	if (menuAction == @selector(pauseAmiga:)) {
		if (pause_emulation)
			[menuItem setTitle:@"Resume"];
		else
			[menuItem setTitle:@"Pause"];
		
		return YES;
	}
	
	if (menuAction == @selector(toggleInhibitDisplay:)) {
		if (inhibit_frame) [menuItem setState:NSOnState];
		else [menuItem setState:NSOffState];
	}

	if (menuAction == @selector(actionReplayFreeze:)) 
		return ( (hrtmon_flag == ACTION_REPLAY_IDLE) || (action_replay_flag == ACTION_REPLAY_IDLE) );
	
    return YES;
}

// Invoked when the user selects one of the 'Insert DFx:' menu items
- (void)insertDisk:(id)sender
{
    [self displayOpenPanelForInsertIntoDriveNumber:[((NSMenuItem*)sender) tag]];
}

// Invoked when the user selects one of the 'Eject DFx:' menu items
- (void)ejectDisk:(id)sender
{
    disk_eject([((NSMenuItem*)sender) tag]);
}

// Invoked when the user selects "Eject All Disks"
- (void)ejectAllDisks:(id)sender
{
	int i;
	for (i=0; i<4; i++)
		if ((!gui_data.drive_disabled[i]) && (!disk_empty(i)))
			disk_eject(i);
}

// Invoked when the user selects an option from the 'Port 0' menu
- (void)changePort0:(id)sender
{
    changed_prefs.jports[0].id = [((NSMenuItem*)sender) tag];

    if( changed_prefs.jports[0].id != currprefs.jports[0].id )
        inputdevice_config_change();
}

// Invoked when the user selects an option from the 'Port 1' menu
- (void)changePort1:(id)sender
{
    changed_prefs.jports[1].id = [((NSMenuItem*)sender) tag];

	if (changed_prefs.jports[1].id != currprefs.jports[1].id) {
		inputdevice_updateconfig (&changed_prefs);
		inputdevice_config_change();
	}
}

- (void)swapGamePorts:(id)sender
{
	changed_prefs.jports[0].id = currprefs.jports[1].id;
	changed_prefs.jports[1].id = currprefs.jports[0].id;
	inputdevice_config_change();
}

- (void)displayOpenPanelForInsertIntoDriveNumber:(int)driveNumber
{
    ensureNotFullscreen();

    NSOpenPanel *oPanel = [NSOpenPanel openPanel];
    [oPanel setTitle:[NSString stringWithFormat:@"%@: Insert Disk Image",applicationName]];

    // Make sure setMessage (OS X 10.3+) is available before calling it
    if ([oPanel respondsToSelector:@selector(setMessage:)])
        [oPanel setMessage:[NSString stringWithFormat:@"Select a Disk Image for DF%d:", driveNumber]];

    [oPanel setPrompt:@"Choose"];
    NSString *contextInfo = [[NSString alloc] initWithFormat:@"%d",driveNumber];

	// Recall the path of the disk image that was loaded last time 
	NSString *nsfloppypath = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastUsedDiskImagePath"];
	
	/* If the configuration includes a setting for the "floppy_path" attribute
	 * start the OpenPanel in that directory.. but only the first time.
	 */
	static int run_once = 0;
	if (!run_once) {
		run_once++;
		
		const char *floppy_path = currprefs.path_floppy.path[driveNumber];
		
		if (floppy_path != NULL) {
			char homedir[MAX_PATH];
			snprintf(homedir, MAX_PATH, "%s/", getenv("HOME"));
			
			/* The default value for floppy_path is "$HOME/". We only want to use it if the
			 * user provided an actual value though, so we don't use it if it equals "$HOME/"
			 */
			if (strncmp(floppy_path, homedir, MAX_PATH) != 0)
				nsfloppypath = [NSString stringWithCString:floppy_path encoding:NSASCIIStringEncoding];
		}
	}

    [oPanel beginSheetForDirectory:nsfloppypath file:nil
                             types:diskImageTypes
                    modalForWindow:[NSApp mainWindow]
                     modalDelegate:self
                    didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
                       contextInfo:contextInfo];
}

// Called when a floppy selection panel ended
- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
#if 0 // This currently breaks
    restoreFullscreen();
#endif

	if (returnCode != NSOKButton) return;

	int drive = [((NSString*)contextInfo) intValue];
	[((NSString*)contextInfo) release];

	if ((drive >= 0) && (drive < 4)) {
		NSArray *files = [sheet filenames];
		NSString *file = [files objectAtIndex:0];
		
		lossyASCIICopy (changed_prefs.floppyslots[drive].df, file, COCOA_GUI_MAX_PATH);
		
		// Save the path of this disk image so that future open panels can start in the same directory
		[[NSUserDefaults standardUserDefaults] setObject:[file stringByDeletingLastPathComponent] forKey:@"LastUsedDiskImagePath"];
	}
}

- (void)hebeHebe:(id)sender
{
	NSRect frame = NSMakeRect(100, 100, 200, 200);
	NSUInteger styleMask;
	NSRect rect = [NSWindow contentRectForFrameRect:frame styleMask:styleMask];
	NSWindow * window = [[NSWindow alloc] initWithContentRect:rect styleMask:styleMask backing:NSBackingStoreBuffered defer:false];
	[window center];
	[window makeKeyAndOrderFront: window];

/*	NSTabViewItem* item=[[NSTabViewItem alloc] initWithIdentifier:identifier];
	[item setLabel:label];
	[item setView:newView];
	[tabView addTabViewItem:item];*/
}

- (void)resetAmiga:(id)sender
{
	uae_reset([((NSMenuItem *)sender) tag]);
}

- (void)pauseAmiga:(id)sender
{
	pausemode(-1); // Found in inputdevice.c -- toggles pause mode when arg is -1
}

#ifdef ACTION_REPLAY
- (void)actionReplayFreeze:(id)sender
{
	action_replay_freeze();
}
#endif

- (void)grabMouse:(id)sender
{
	toggle_mousegrab ();
}

- (void)goFullscreen:(id)sender
{
	toggle_fullscreen(0);
}

- (void)toggleInhibitDisplay:(id)sender
{
	toggle_inhibit_frame (IHF_SCROLLLOCK);
}

// chip mem
- (void)changeChipMem:(id)sender
{
	changed_prefs.chipmem_size = memsizes[[((NSMenuItem*)sender) tag]];
        if (changed_prefs.chipmem_size > 0x200000)
                changed_prefs.fastmem_size = 0;
}

// bogo mem
- (void)changeBogoMem:(id)sender
{
	changed_prefs.bogomem_size = memsizes[[((NSMenuItem*)sender) tag]];
}

// fast mem
- (void)changeFastMem:(id)sender
{
	changed_prefs.fastmem_size = memsizes[[((NSMenuItem*)sender) tag]];
}

// z3 fast mem
- (void)changeZ3FastMem:(id)sender
{
	changed_prefs.z3fastmem_size = memsizes[[((NSMenuItem*)sender) tag]];
}

// z3 chip mem
- (void)changeZ3ChipMem:(id)sender
{
	changed_prefs.z3chipmem_size = memsizes[[((NSMenuItem*)sender) tag]];
}

// gfx mem
- (void)changeGfxMem:(id)sender
{
	changed_prefs.gfxmem_size = memsizes[[((NSMenuItem*)sender) tag]];
}

// chipset
- (void)changeChipset:(id)sender
{
	changed_prefs.chipset_mask = [((NSMenuItem*)sender) tag];
}

// cpu
- (void)changeCPU:(id)sender
{
	unsigned int newcpu, newfpu;
	newcpu = 68000 + ([((NSMenuItem*)sender) tag] * 10);
	newfpu = changed_prefs.fpu_model;
	changed_prefs.cpu_model = newcpu;

        switch (newcpu) {
        case 68000:
        case 68010:
                changed_prefs.fpu_model = newfpu == 0 ? 0 : (newfpu == 2 ? 68882 : 68881);
                if (changed_prefs.cpu_compatible || changed_prefs.cpu_cycle_exact)
                        changed_prefs.fpu_model = 0;
                changed_prefs.address_space_24 = 1;
                if (newcpu == 0 && changed_prefs.cpu_cycle_exact)
                        changed_prefs.m68k_speed = 0;
                break;
        case 68020:
                changed_prefs.fpu_model = newfpu == 0 ? 0 : (newfpu == 2 ? 68882 : 68881);
                break;
        case 68030:
                changed_prefs.address_space_24 = 0;
                changed_prefs.fpu_model = newfpu == 0 ? 0 : (newfpu == 2 ? 68882 : 68881);
                break;
        case 68040:
                changed_prefs.fpu_model = newfpu ? 68040 : 0;
                changed_prefs.address_space_24 = 0;
                if (changed_prefs.fpu_model)
                        changed_prefs.fpu_model = 68040;
                break;
        case 68060:
                changed_prefs.fpu_model = newfpu ? 68060 : 0;
                changed_prefs.address_space_24 = 0;
                break;
        }


}

// cpu speed
- (void)changeCPUSpeed:(id)sender
{
	unsigned int v;
	v = [((NSMenuItem*)sender) tag];
	if (v == 0) {
		changed_prefs.m68k_speed = -1;
		changed_prefs.cpu_cycle_exact = 0;
	}
	if (v == 1) {
		changed_prefs.m68k_speed = 0;
		changed_prefs.cpu_cycle_exact = 0;
	}
	if (v == 2) {
		changed_prefs.m68k_speed = 0;
		changed_prefs.cpu_cycle_exact = 1;
	}
}

// fpu
- (void)changeFPU:(id)sender
{
	unsigned int v;
	v = [((NSMenuItem*)sender) tag];
/*	if (v == 1) v = 68881;
	if (v == 2) v = 68882;*/
	changed_prefs.fpu_model = v;
}
@end

/*
 * Revert to windowed mode if in fullscreen mode. Returns 1 if the
 * mode was initially fullscreen and was successfully changed. 0 otherwise.
 */
int ensureNotFullscreen (void)
{
    int result = 0;

    if (is_fullscreen ()) {
		toggle_fullscreen (0);

		if (is_fullscreen ())
			write_log ("Cannot activate GUI in full-screen mode\n");
		else {
		  result = 1;
		  wasFullscreen = YES;
        }
        }
#ifdef USE_SDL
    // Un-hide the mouse
    SDL_ShowCursor(SDL_ENABLE);
#endif

    return result;
}

void restoreFullscreen (void)
{
#ifdef USE_SDL
    // Re-hide the mouse
    SDL_ShowCursor(SDL_DISABLE);
#endif

    if ((!is_fullscreen ()) && (wasFullscreen == YES))
        toggle_fullscreen(0);

    wasFullscreen = NO;
}

/* Make a null-terminated copy of the source NSString into buffer using lossy
 * ASCII conversion. (Apple deprecated the 'lossyCString' method in NSString)
 */
void lossyASCIICopy (char *buffer, NSString *source, size_t maxLength)
{
	if (source == nil) {
		buffer[0] = '\0';
		return;
	}
	
	NSData *data = [source dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	
	if (data == nil) {
		buffer[0] = '\0';
		return;
	}
	
	[data getBytes:buffer length:maxLength];
	
	/* Ensure null termination */
	NSUInteger len = [data length];
	buffer[(len >= maxLength) ? (maxLength - 1) : len] = '\0';
}

/* This function is called from od-macosx/main.m
 * WARNING: This gets called *before* real_main(...)!
 */
void cocoa_gui_early_setup (void)
{
	[[PuaeGui sharedInstance] createMenus];
}

int gui_init (void)
{
}

int gui_update (void)
{
    return 0;
}

void gui_exit (void)
{
}

void gui_fps (int fps, int idle)
{
    gui_data.fps  = fps;
    gui_data.idle = idle;
}

void gui_flicker_led (int led, int unitnum, int status)
{
}

void gui_led (int led, int on)
{
}

void gui_filename (int num, const char *name)
{
}

static void getline (char *p)
{
}

void gui_handle_events (void)
{
}

void gui_display (int shortcut)
{
    int result;

    if ((shortcut >= 0) && (shortcut < 4)) {
        [[PuaeGui sharedInstance] displayOpenPanelForInsertIntoDriveNumber:shortcut];
    }
}

void gui_message (const char *format,...)
{
    char msg[2048];
    va_list parms;

    ensureNotFullscreen ();

    va_start (parms,format);
    vsprintf (msg, format, parms);
    va_end (parms);

    NSRunAlertPanel(nil, [NSString stringWithCString:msg encoding:NSASCIIStringEncoding], nil, nil, nil);

    write_log ("%s", msg);

    restoreFullscreen ();
}
void gui_disk_image_change (int unitnum, const TCHAR *name, bool writeprotected) {}
void gui_lock (void) {}
void gui_unlock (void) {}

static int guijoybutton[MAX_JPORTS];
static int guijoyaxis[MAX_JPORTS][4];
static bool guijoychange;

void gui_gameport_button_change (int port, int button, int onoff)
{
        //write_log ("%d %d %d\n", port, button, onoff);
#ifdef RETROPLATFORM
        int mask = 0;
        if (button == JOYBUTTON_CD32_PLAY)
                mask = RP_JOYSTICK_BUTTON5;
        if (button == JOYBUTTON_CD32_RWD)
                mask = RP_JOYSTICK_BUTTON6;
        if (button == JOYBUTTON_CD32_FFW)
                mask = RP_JOYSTICK_BUTTON7;
        if (button == JOYBUTTON_CD32_GREEN)
                mask = RP_JOYSTICK_BUTTON4;
        if (button == JOYBUTTON_3 || button == JOYBUTTON_CD32_YELLOW)
                mask = RP_JOYSTICK_BUTTON3;
        if (button == JOYBUTTON_1 || button == JOYBUTTON_CD32_RED)
                mask = RP_JOYSTICK_BUTTON1;
        if (button == JOYBUTTON_2 || button == JOYBUTTON_CD32_BLUE)
                mask = RP_JOYSTICK_BUTTON2;
        rp_update_gameport (port, mask, onoff);
#endif
        if (onoff)
                guijoybutton[port] |= 1 << button;
        else
                guijoybutton[port] &= ~(1 << button);
        guijoychange = true;
}

void gui_gameport_axis_change (int port, int axis, int state, int max)
{
        int onoff = state ? 100 : 0;
        if (axis < 0 || axis > 3)
                return;
        if (max < 0) {
                if (guijoyaxis[port][axis] == 0)
                        return;
                if (guijoyaxis[port][axis] > 0)
                        guijoyaxis[port][axis]--;
        } else {
                if (state > max)
                        state = max;
                if (state < 0)
                        state = 0;
                guijoyaxis[port][axis] = max ? state * 127 / max : onoff;
#ifdef RETROPLATFORM
                if (axis == DIR_LEFT_BIT)
                        rp_update_gameport (port, RP_JOYSTICK_LEFT, onoff);
                if (axis == DIR_RIGHT_BIT)
                        rp_update_gameport (port, DIR_RIGHT_BIT, onoff);
                if (axis == DIR_UP_BIT)
                        rp_update_gameport (port, DIR_UP_BIT, onoff);
                if (axis == DIR_DOWN_BIT)
                        rp_update_gameport (port, DIR_DOWN_BIT, onoff);
#endif
        }
        guijoychange = true;
}
