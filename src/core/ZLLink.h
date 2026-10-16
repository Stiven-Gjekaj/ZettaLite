// Reads a zettalite:// link from another app or from a Safari bookmarklet.
// zettalite://play?url=URL&title=TEXT plays URL. The value of url is
// percent-encoded.

#import <Foundation/Foundation.h>

@interface ZLLink : NSObject
@property (nonatomic, strong) NSURL *mediaURL;
@property (nonatomic, copy) NSString *title;
@end

// Returns nil for a link that the app does not know.
ZLLink *ZLParseLink(NSURL *url);

// Reads the text that a person pastes. Returns an http or https URL, or nil.
NSURL *ZLMediaURLFromText(NSString *text);
