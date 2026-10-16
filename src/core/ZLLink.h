// Reads a zettalite:// link from another app or from a Safari bookmarklet.
//   zettalite://play?url=URL&title=TEXT&t=SECONDS  plays URL from SECONDS
//   zettalite://title?type=TYPE&id=ID              opens the page of a title
//   zettalite://watch?type=TYPE&id=ID              plays the best stream of a title or an episode
//   zettalite://search?q=TEXT                      searches in all addons
//   zettalite://tab?name=NAME                      opens a tab: home, search, library, live, settings
// Each value is percent-encoded.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ZLLinkKind) {
    ZLLinkPlay,
    ZLLinkTitle,
    ZLLinkWatch,
    ZLLinkSearch,
    ZLLinkTab,
};

@interface ZLLink : NSObject
@property (nonatomic) ZLLinkKind kind;
@property (nonatomic, strong) NSURL *mediaURL;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) double startTime;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *text;  // The search text or the name of the tab.
@end

// Returns nil for a link that the app does not know.
ZLLink *ZLParseLink(NSURL *url);

// Reads the text that a person pastes. Returns an http or https URL, or nil.
NSURL *ZLMediaURLFromText(NSString *text);
