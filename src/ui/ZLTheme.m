#import "ZLTheme.h"

static UIColor *ZLColor(unsigned rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0
                            blue:(rgb & 0xff) / 255.0 alpha:1];
}

UIColor *ZLBackgroundColor(void) {
    return ZLColor(0x000000);
}

UIColor *ZLSurfaceColor(void) {
    return ZLColor(0x1a1a1a);
}

UIColor *ZLTextColor(void) {
    return ZLColor(0xffffff);
}

UIColor *ZLSecondaryTextColor(void) {
    return ZLColor(0x9a9a9a);
}

UIColor *ZLAccentColor(void) {
    return ZLColor(0xf5a524);
}

UIFont *ZLFont(CGFloat size) {
    return [UIFont fontWithName:@"Karla-Regular" size:size] ?: [UIFont systemFontOfSize:size];
}

UIFont *ZLBoldFont(CGFloat size) {
    return [UIFont fontWithName:@"Karla-Bold" size:size] ?: [UIFont boldSystemFontOfSize:size];
}

void ZLApplyTheme(void) {
    UIColor *bar = ZLColor(0x111111);
    [[UINavigationBar appearance] setTintColor:bar];
    [[UINavigationBar appearance] setTitleTextAttributes:@{ UITextAttributeFont: ZLBoldFont(20) }];
    [[UISearchBar appearance] setTintColor:bar];
    [[UIToolbar appearance] setTintColor:bar];
    [[UITabBar appearance] setTintColor:bar];
    [[UITabBar appearance] setSelectedImageTintColor:ZLAccentColor()];
    [[UISegmentedControl appearance] setTintColor:ZLColor(0x333333)];
    [[UISwitch appearance] setOnTintColor:ZLAccentColor()];
    [[UIRefreshControl appearance] setTintColor:ZLTextColor()];
}
