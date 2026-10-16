// A small log file for the diagnostics. It keeps the newest lines in
// Library/Caches/ZettaLite/log.txt.

#import <Foundation/Foundation.h>

void ZLLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

// The text of the log, for the diagnostics screen.
NSString *ZLLogText(void);
