#import "GMailinator.h"
#import <objc/objc-runtime.h>
#import <Carbon/Carbon.h>
#import <AppKit/AppKit.h>

NSBundle *GetGMailinatorBundle(void)
{
    return [NSBundle bundleForClass:[GMailinator class]];
}

@implementation GMailinator

+ (void)initialize {
    [GMailinator registerBundle];
}

/**
 * Helper method to setup a class from Mail to use our custom methods instead of they common
 * keyDown:.
 */
+ (void)setupClass:(Class)cls swappingKeyDownWith:(SEL)overrideSelector {
    if (cls == nil) return;

    // Helper methods
    SEL performSelector = @selector(performSelectorOnMessageViewer:basedOnEvent:);
    SEL getShortcutSelector = @selector(getShortcutRemappedEventFor:);
    Method performMethod = class_getInstanceMethod(self, performSelector);
    Method getShortcutMethod = class_getInstanceMethod(self, getShortcutSelector);

    // Swapped methods
    SEL originalSelector = @selector(keyDown:);
    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method overrideMethod = class_getInstanceMethod(self, overrideSelector);

    // Swap keyDow with the given method
    class_addMethod(cls,
                    overrideSelector,
                    method_getImplementation(originalMethod),
                    method_getTypeEncoding(originalMethod));
    class_replaceMethod(cls,
                        originalSelector,
                        method_getImplementation(overrideMethod),
                        method_getTypeEncoding(overrideMethod));
    // Add helper methods
    class_addMethod(cls,
                    performSelector,
                    method_getImplementation(performMethod),
                    method_getTypeEncoding(performMethod));
    class_addMethod(cls,
                    getShortcutSelector,
                    method_getImplementation(getShortcutMethod),
                    method_getTypeEncoding(getShortcutMethod));
}

+ (void)load {
    [self setupClass:NSClassFromString(@"MailTableView")
 swappingKeyDownWith:@selector(overrideMailKeyDown:)];

    // this class does not exist on newer versions of Mail
//    [self setupClass:NSClassFromString(@"MessagesTableView")
// swappingKeyDownWith:@selector(overrideMessagesKeyDown:)];

    [self setupClass:NSClassFromString(@"MessageViewer")
 swappingKeyDownWith:@selector(overrideMessagesKeyDown:)];
}

+ (void)registerBundle {
    Class mailBundleClass = NSClassFromString(@"MVMailBundle");
    if(class_getClassMethod(mailBundleClass, @selector(registerBundle)))
        [mailBundleClass performSelector:@selector(registerBundle)];
}

/**
 * This method is where we perform known selectors on the message viewer. This is prefferable
 * over the shortcut proxy since a user could change their shortcuts, unfortunately there is no
 * documentation on which selectors the MessageViewer on Mail we could use.
 */
- (BOOL)performSelectorOnMessageViewer:(id)messageViewer basedOnEvent:(NSEvent*)event {
    unichar key = [[event characters] characterAtIndex:0];
    BOOL performed = YES;

    switch (key) {
        case 'd': {
            [messageViewer performSelector:@selector(deleteMessages:) withObject:nil];
            break;
        }
        case 'e': {
            [messageViewer performSelector:@selector(archiveMessages:) withObject:nil];
            break;
        }
        default:
            performed = NO;
    }
    return performed;
}

/**
 * This method is a proxy for shortcuts. We receive the Gmail key presses and translate it to normal
 * Mail shortcuts. Althoug this is the easiest way to remap shortcuts it shouldn't be the primary
 * way since a user could remap the entire set of shortcuts and have weird behavior using this
 * plugin. Also there is the fact that some modifiers cannot be remapped, for instanse Alt+Up/Down
 * can be used to go to next and previous message on a thread, but when we remap them here, the
 * generated shortcut is the same as going to the beginning or end of the message list.
 */
-(NSEvent*)getShortcutRemappedEventFor:(NSEvent*)event {
    unichar key = [[event characters] characterAtIndex:0];
    NSEvent *newEvent = event;
    CGEventRef cgEvent = NULL;

    switch (key) {
        case 'j': { // next message (down)
            cgEvent = CGEventCreateKeyboardEvent(NULL, kVK_DownArrow, true);
            newEvent = [NSEvent eventWithCGEvent: cgEvent];
            break;
        }
        case 'J': { // expand selection to next message (down)
            cgEvent = CGEventCreateKeyboardEvent(NULL, kVK_DownArrow, true);
            CGEventSetFlags(cgEvent, kCGEventFlagMaskShift);
            newEvent = [NSEvent eventWithCGEvent: cgEvent];
            break;
        }
        case 'k': { // previous message (up)
            cgEvent = CGEventCreateKeyboardEvent(NULL, kVK_UpArrow, true);
            newEvent = [NSEvent eventWithCGEvent: cgEvent];
            break;
        }
        case 'K': { // expand selection to previous message (up)
            cgEvent = CGEventCreateKeyboardEvent(NULL, kVK_UpArrow, true);
            CGEventSetFlags(cgEvent, kCGEventFlagMaskShift);
            newEvent = [NSEvent eventWithCGEvent: cgEvent];
            break;
        }
    }

    if (cgEvent != NULL) {
        // prevent memory leak from the temporary CGEvent
        CFRelease(cgEvent);
    }

    return newEvent;
}

- (void)overrideMailKeyDown:(NSEvent*)event {
    id tableViewManager = [self performSelector:@selector(delegate)];
    id messageListViewController = [tableViewManager performSelector:@selector(delegate)];
    
    // NOTE: backwards compatibility. In 10.11 and earlier, tableViewManager.delegate.delegate was already the message viewer.
    id messageViewer
        = [messageListViewController respondsToSelector:@selector(messageViewer)]
        ? [messageListViewController performSelector:@selector(messageViewer)]
        : messageListViewController;

    if (! [self performSelectorOnMessageViewer:messageViewer basedOnEvent:event]) {
        [self overrideMailKeyDown:[self getShortcutRemappedEventFor:event]];
    }
}

- (void)overrideMessagesKeyDown:(NSEvent*)event {
    if (! [self performSelectorOnMessageViewer:self basedOnEvent:event]) {
        [self overrideMessagesKeyDown:[self getShortcutRemappedEventFor:event]];
    }
}

@end
