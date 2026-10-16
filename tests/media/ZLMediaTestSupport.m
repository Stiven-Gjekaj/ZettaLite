#import "ZLMediaTestSupport.h"

static NSString *ZLFixturesPath(void) {
    return [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"fixtures"];
}

NSData *ZLFixture(NSString *name) {
    return [NSData dataWithContentsOfFile:[ZLFixturesPath() stringByAppendingPathComponent:name]];
}

ZLTestServer *ZLFixtureServer(void) {
    ZLTestServer *server = [ZLTestServer new];
    if (![server start]) return nil;
    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *folder in @[ @"", @"dash" ]) {
        NSString *path = [ZLFixturesPath() stringByAppendingPathComponent:folder];
        for (NSString *name in [files contentsOfDirectoryAtPath:path error:NULL]) {
            NSData *data = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:name]];
            if (!data) continue;
            NSString *route = folder.length ? [NSString stringWithFormat:@"/%@/%@", folder, name] : [@"/" stringByAppendingString:name];
            [server serve:data at:route type:@"application/octet-stream"];
        }
    }
    return server;
}

NSURL *ZLFixtureURL(ZLTestServer *server, NSString *name) {
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/%@", server.port, name]];
}
