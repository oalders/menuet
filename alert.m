#import <Cocoa/Cocoa.h>

#import "alert.h"
#import "EditableNSTextField.h"

void alertClicked(int, const char *);

void showAlert(const char *jsonString) {
	NSDictionary *jsonDict = [NSJSONSerialization
	                          JSONObjectWithData:[[NSString stringWithUTF8String:jsonString]
	                                              dataUsingEncoding:NSUTF8StringEncoding]
	                          options:0
	                          error:nil];

	dispatch_async(dispatch_get_main_queue(), ^{
		NSAlert *alert = [NSAlert new];
		alert.messageText = jsonDict[@"MessageText"];
		alert.informativeText = jsonDict[@"InformativeText"];
		NSArray *buttons = jsonDict[@"Buttons"];
		if (![buttons isEqualTo:NSNull.null] && buttons.count > 0) {
		        for (NSString *label in buttons) {
		                [alert addButtonWithTitle:label];
			}
		}
		NSView *accessoryView;
		NSArray *inputs = jsonDict[@"Inputs"];
		NSArray *inputValues = jsonDict[@"InputValues"];
		BOOL hasInputValues = ![inputValues isEqualTo:NSNull.null] && inputValues.count > 0;
		BOOL hasInputs = ![inputs isEqualTo:NSNull.null] && inputs.count > 0;
		int inputCount = hasInputValues ? (int)inputValues.count : (hasInputs ? (int)inputs.count : 0);
		if (inputCount > 0) {
		        hasInputs = YES;
		        BOOL first = false;
		        int y = 30 * inputCount;
		        accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, y)];
		        for (int i = 0; i < inputCount; i++) {
		                y -= 30;
		                EditableNSTextField *textfield =
					[[EditableNSTextField alloc] initWithFrame:NSMakeRect(0, y, 200, 25)];
		                if (hasInputValues && i < (int)inputValues.count) {
		                        [textfield setStringValue:inputValues[i]];
		                }
		                if (![inputs isEqualTo:NSNull.null] && i < (int)inputs.count) {
		                        [textfield setPlaceholderString:inputs[i]];
		                }
		                [accessoryView addSubview:textfield];
		                if (!first) {
		                        [alert.window setInitialFirstResponder:textfield];
		                        first = true;
				}
			}
		        [alert setAccessoryView:accessoryView];
		}

		[NSApp activateIgnoringOtherApps:YES];
		NSInteger resp = [alert runModal];
		NSMutableArray *values = [NSMutableArray new];
		if (hasInputs) {
		        for (NSView *subview in accessoryView.subviews) {
		                if (![subview isKindOfClass:[EditableNSTextField class]]) {
		                        continue;
				}
		                [values addObject:((EditableNSTextField *)subview).stringValue];
			}
		}
		NSData *jsonData =
			[NSJSONSerialization dataWithJSONObject:values options:0 error:nil];
		NSString *jsonString =
			[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
		alertClicked(resp - NSAlertFirstButtonReturn, jsonString.UTF8String);
	});
}
