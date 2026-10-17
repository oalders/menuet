#import <Cocoa/Cocoa.h>

#import "NSImage+Resize.h"
#import "menuet.h"

void itemClicked(const char *);
void notificationRespond(const char *, const char *);
const char *children(const char *);
void menuClosed(const char *);
bool hideStartup();
bool runningAtStartup();
void toggleStartup();
void shutdownWait();
bool hasStatusItemClickHandler();
bool hasStatusItemOptionClickHandler();
bool hasAnyStatusItemClickHandler();
void statusItemClicked();
void statusItemOptionClicked();

NSStatusItem *_statusItem;

@class MenuetMenu;
MenuetMenu *_rootMenu;

@interface MenuetMenu : NSMenu <NSMenuDelegate>

@property(nonatomic, copy) NSString *unique;
@property(nonatomic, assign) BOOL root;
@property(nonatomic, assign) BOOL open;

@end

@implementation MenuetMenu
- (id)init {
	self = [super init];
	if (self) {
		self.delegate = self;
		self.autoenablesItems = false;
	}
	return self;
}

- (void)refreshVisibleMenus {
	if (!self.open) {
		return;
	}
	[self menuWillOpen:self];
	for (NSMenuItem *item in self.itemArray) {
		MenuetMenu *menu = (MenuetMenu *)item.submenu;
		if (menu != NULL) {
			[menu refreshVisibleMenus];
		}
	}
}

- (void)populate:(NSArray *)items {
	for (int i = 0; i < items.count; i++) {
		NSMenuItem *item = nil;
		if (i < self.numberOfItems) {
			item = [self itemAtIndex:i];
		}
		NSDictionary *dict = [items objectAtIndex:i];
		NSString *type = dict[@"Type"];
		if ([type isEqualTo:@"separator"]) {
			if (!item || !item.isSeparatorItem) {
				[self insertItem:[NSMenuItem separatorItem] atIndex:i];
			}
			continue;
		}
		NSString *unique = dict[@"Unique"];
		NSString *text = dict[@"Text"];
		NSString *imageName = dict[@"Image"];
		NSNumber *fontSize = dict[@"FontSize"];
		NSNumber *fontWeight = dict[@"FontWeight"];
		BOOL state = [dict[@"State"] boolValue];
		BOOL hasChildren = [dict[@"HasChildren"] boolValue];
		BOOL clickable = [dict[@"Clickable"] boolValue];
		if (!item || item.isSeparatorItem) {
			item =
				[self insertItemWithTitle:@"" action:nil keyEquivalent:@"" atIndex:i];
		}
		NSMutableDictionary *attributes = [NSMutableDictionary new];
		float size = fontSize.floatValue;
		if (fontSize == 0) {
			size = 14;
		}
		attributes[NSFontAttributeName] =
			[NSFont monospacedDigitSystemFontOfSize:size
			 weight:fontWeight.floatValue];
		item.attributedTitle =
			[[NSMutableAttributedString alloc] initWithString:text
			 attributes:attributes];
		item.target = self;
		if (clickable) {
			item.action = @selector(press:);
			item.representedObject = unique;
		} else {
			item.action = nil;
			item.representedObject = nil;
		}
		if (state) {
			item.state = NSControlStateValueOn;
		} else {
			item.state = NSControlStateValueOff;
		}
		if (hasChildren) {
			if (!item.submenu) {
				item.submenu = [MenuetMenu new];
			}
			MenuetMenu *menu = (MenuetMenu *)item.submenu;
			menu.unique = unique;
		} else if (item.submenu) {
			item.submenu = nil;
		}
		item.enabled = clickable || hasChildren;
		item.image = [NSImage imageFromName:imageName withHeight:16];
	}
	while (self.numberOfItems > items.count) {
		[self removeItemAtIndex:self.numberOfItems - 1];
	}
}

// The documentation says not to make changes here, but it seems to work.
// submenuAction does not appear to be called, and menuNeedsUpdate is only
// called once per tracking session.
- (void)menuWillOpen:(MenuetMenu *)menu {
	if (self.root) {
		// For the root menu, we generate a new unique every time it's opened. Go
		// handles all other unique generation.
		self.unique = [[[[NSProcessInfo processInfo] globallyUniqueString]
		                substringFromIndex:51] stringByAppendingString:@":root"];
	}
	const char *str = children(self.unique.UTF8String);
	NSArray *items = @[];
	if (str != NULL) {
		items = [NSJSONSerialization
		         JSONObjectWithData:[[NSString stringWithUTF8String:str]
		                             dataUsingEncoding:NSUTF8StringEncoding]
		         options:0
		         error:nil];
		free((char *)str);
	}
	if (self.root) {
		items = [items arrayByAddingObjectsFromArray:@[
				 @{@"Type" : @"separator",
				   @"Clickable" : @YES},
		]];
		if (!hideStartup()) {
			items = [items arrayByAddingObjectsFromArray:@[
					@{@"Text" : @"Start at Login",
					@"Clickable" : @YES},
			]];
		}
		items = [items arrayByAddingObjectsFromArray:@[
				 @{@"Text" : @"Quit",
				   @"Clickable" : @YES},
		]];
	}
	[self populate:items];
	if (self.root) {
		NSMenuItem *item = nil;
		if (!hideStartup()) {
			item = [self itemAtIndex:items.count - 2];
			item.action = @selector(toggleStartup:);
			if (runningAtStartup()) {
				item.state = NSControlStateValueOn;
			} else {
				item.state = NSControlStateValueOff;
			}
		}
		item = [self itemAtIndex:items.count - 1];
		item.action = @selector(prepareShutdown:);
	}
	self.open = YES;
}

- (void)menuDidClose:(MenuetMenu *)menu {
	self.open = NO;
	menuClosed(self.unique.UTF8String);
	if (self.root && hasAnyStatusItemClickHandler()) {
		_statusItem.menu = nil;
	}
}

- (void)press:(id)sender {
	NSString *callback = [sender representedObject];
	itemClicked(callback.UTF8String);
}

- (void)toggleStartup:(id)sender {
	toggleStartup();
}

- (void)prepareShutdown:(id)sender {
	shutdownWait();
	[NSApp terminate: nil];
}

@end

@interface MenuetAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSUserNotificationCenterDelegate>

- (void)statusItemClicked:(id)sender;

@end

void setState(const char *jsonString) {
	NSDictionary *state = [NSJSONSerialization
	                       JSONObjectWithData:[[NSString stringWithUTF8String:jsonString]
	                                           dataUsingEncoding:NSUTF8StringEncoding]
	                       options:0
	                       error:nil];
	dispatch_async(dispatch_get_main_queue(), ^{
		CGFloat fontSize = 14;
		NSNumber *fontSizeNum = state[@"FontSize"];
		if (fontSizeNum != nil && [fontSizeNum floatValue] > 0) {
			fontSize = [fontSizeNum floatValue];
		}
		_statusItem.button.attributedTitle = [[NSAttributedString alloc]
		                                      initWithString:state[@"Title"]
		                                      attributes:@{
		                                              NSFontAttributeName :
		                                              [NSFont monospacedDigitSystemFontOfSize:fontSize
		                                               weight:NSFontWeightRegular]
		}];
		NSString *imageName = state[@"Image"];
		NSImage *image = [NSImage imageFromName:imageName withHeight:22];
		_statusItem.button.image = image;
		NSNumber *templateImage = state[@"TemplateImage"];
		if (templateImage != nil) {
			_statusItem.button.image.template = [templateImage boolValue];
		} else {
			_statusItem.button.image.template = true;
		}
		_statusItem.button.imagePosition = NSImageLeft;
		BOOL isDark = NO;
		NSAppearance *appearance = _statusItem.button.effectiveAppearance;
		if (appearance != nil) {
			NSString *bestMatch = [appearance bestMatchFromAppearancesWithNames:@[
				NSAppearanceNameAqua, NSAppearanceNameDarkAqua
			]];
			isDark = [bestMatch isEqualToString:NSAppearanceNameDarkAqua];
		}
		CGColorRef borderColor = isDark
			? [[NSColor colorWithWhite:1.0 alpha:0.4] CGColor]
			: [[NSColor colorWithWhite:0.0 alpha:0.4] CGColor];
		_statusItem.button.layer.cornerRadius = 4.0;
		_statusItem.button.layer.borderWidth = 1.0;
		_statusItem.button.layer.borderColor = borderColor;
	});
}

void menuChanged() {
        dispatch_async(dispatch_get_main_queue(), ^{
		[_rootMenu refreshVisibleMenus];
	});
}

void createAndRunApplication() {
        [NSAutoreleasePool new];
        NSApplication *a = NSApplication.sharedApplication;
        MenuetAppDelegate *d = [MenuetAppDelegate new];
        [a setDelegate:d];
        [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:d];
        [a setActivationPolicy:NSApplicationActivationPolicyAccessory];
        _statusItem = [[NSStatusBar systemStatusBar]
                       statusItemWithLength:NSVariableStatusItemLength];
        _rootMenu = [MenuetMenu new];
        _rootMenu.root = true;
        [(NSButtonCell *)_statusItem.button.cell setHighlightsBy:NSNoCellMask];
        _statusItem.button.wantsLayer = YES;
        if (hasAnyStatusItemClickHandler()) {
                // Left-click goes to statusItemClicked:, which calls the Go
                // handler for that click or falls back to opening the menu
                _statusItem.button.target = d;
                _statusItem.button.action = @selector(statusItemClicked:);
                [_statusItem.button sendActionOn:NSEventMaskLeftMouseUp];
        } else {
                // Default: any click opens the menu
                _statusItem.menu = _rootMenu;
        }
        [a run];
}

@implementation MenuetAppDelegate

- (void)statusItemClicked:(id)sender {
        NSEvent *event = [NSApp currentEvent];
        if (event.modifierFlags & NSEventModifierFlagOption) {
                if (hasStatusItemOptionClickHandler()) {
                        statusItemOptionClicked();
                        return;
                }
        } else if (hasStatusItemClickHandler()) {
                statusItemClicked();
                return;
        }
        // No handler for this click: show the menu
        _statusItem.menu = _rootMenu;
        dispatch_async(dispatch_get_main_queue(), ^{
                [_statusItem.button performClick:nil];
        });
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
        (NSApplication *)sender {
        return NSTerminateNow;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
        if (notification.activationType == NSUserNotificationActivationTypeReplied) {
                NSString* userResponse = notification.response.string;
                notificationRespond(notification.identifier.UTF8String, userResponse.UTF8String);
	} else {
                notificationRespond(notification.identifier.UTF8String, @"".UTF8String);
	}
}

@end
