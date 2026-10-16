// Helpers for the media tests. They operate on the phone, where
// scripts/test.sh puts the media files in fixtures/.

#import <Foundation/Foundation.h>
#import "ZLTestServer.h"

// The data of a file in fixtures/, or nil.
NSData *ZLFixture(NSString *name);
// Serves each file of fixtures/ at /<name>, and each file of fixtures/dash/
// at /dash/<name>. Returns the server, or nil.
ZLTestServer *ZLFixtureServer(void);
NSURL *ZLFixtureURL(ZLTestServer *server, NSString *name);
