// The colors and the font of the app: black and white, as in ZettaStream,
// with the amber light of the logo as the accent. The controls stay the stock
// iOS 6 controls. See docs/decisions.md.

#import <UIKit/UIKit.h>

UIColor *ZLBackgroundColor(void);  // Black, behind the content
UIColor *ZLSurfaceColor(void);     // A dark grey, for cells and cards
UIColor *ZLTextColor(void);        // White
UIColor *ZLSecondaryTextColor(void);
UIColor *ZLAccentColor(void);      // Amber

// Karla, the font of ZettaStream. The system font when Karla is missing.
UIFont *ZLFont(CGFloat size);
UIFont *ZLBoldFont(CGFloat size);

// Sets the tint of the bars of the app. Call it before the first window shows.
void ZLApplyTheme(void);
