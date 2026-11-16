// IOS26Phone - giao diện Phone kiểu iOS 26 cho iOS 15/16 (rootless)
// Tên class của Apple khác nhau theo bản iOS -> toàn bộ hook dùng khớp theo TÊN (NameHas),
// bật kDebug để xem class thực tế trong syslog rồi sửa danh sách key cho khớp máy bạn.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL kPhone = NO, kInCall = NO;
static const BOOL kDebug = NO;
static NSString *const kUnifiedKey = @"IOS26PhoneUnified";

static UITabBarController *gTBC;
static NSArray *gAll;           // 5 tab gốc: Ưa thích, Gần đây, Danh bạ, Bàn phím, Thư thoại
static NSInteger gFilter = 0;   // 0 = tất cả, 1 = nhỡ

#pragma mark - Helpers

static BOOL isUnified(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:kUnifiedKey]; }
static NSString *L(NSString *vi, NSString *en) {
    NSString *lang = [NSLocale preferredLanguages].firstObject ?: @"en";
    return [lang hasPrefix:@"vi"] ? vi : en;
}
static BOOL NameHas(id o, NSArray<NSString *> *keys) {
    if (!o) return NO;
    NSString *n = NSStringFromClass([o class]);
    for (NSString *k in keys) if ([n containsString:k]) return YES;
    return NO;
}
static UIColor *Dyn(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}
static UIColor *ButtonFill(void) { return Dyn([UIColor colorWithWhite:0.975 alpha:1], [UIColor colorWithWhite:0.17 alpha:1]); }
static void Shadow(CALayer *l, float op, CGFloat r, CGFloat y) {
    l.shadowColor = UIColor.blackColor.CGColor; l.shadowOpacity = op;
    l.shadowRadius = r; l.shadowOffset = CGSizeMake(0, y);
}
static void Circle(UIView *v) {
    v.layer.cornerRadius = MIN(v.bounds.size.width, v.bounds.size.height) / 2;
}
static void FindAll(UIView *v, Class c, NSMutableArray *out) {
    for (UIView *s in v.subviews) { if ([s isKindOfClass:c]) [out addObject:s]; FindAll(s, c, out); }
}
static NSString *FirstLabelText(UIView *v) {
    NSMutableArray *a = [NSMutableArray array]; FindAll(v, UILabel.class, a);
    for (UILabel *l in a) if (l.text.length > 1 || (l.text.length == 1 && ![l.text isEqualToString:@"A"])) return l.text;
    return nil;
}

static UIImage *InitialsAvatar(NSString *name, CGFloat d) {
    NSArray *w = [[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                  componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableString *ini = [NSMutableString string];
    if ([w.firstObject length]) [ini appendString:[[w.firstObject substringToIndex:1] uppercaseString]];
    if (w.count > 1 && [w.lastObject length]) [ini appendString:[[w.lastObject substringToIndex:1] uppercaseString]];
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        CGContextRef g = c.CGContext;
        CGContextAddEllipseInRect(g, CGRectMake(0, 0, d, d)); CGContextClip(g);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        NSArray *cols = @[(id)[UIColor colorWithRed:.68 green:.72 blue:.90 alpha:1].CGColor,
                          (id)[UIColor colorWithRed:.46 green:.50 blue:.78 alpha:1].CGColor];
        CGGradientRef gr = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)cols, NULL);
        CGContextDrawLinearGradient(g, gr, CGPointMake(0, 0), CGPointMake(0, d), 0);
        CGGradientRelease(gr); CGColorSpaceRelease(cs);
        NSDictionary *at = @{NSFontAttributeName:[UIFont systemFontOfSize:d*0.38 weight:UIFontWeightSemibold],
                             NSForegroundColorAttributeName:UIColor.whiteColor};
        CGSize s = [ini sizeWithAttributes:at];
        [ini drawAtPoint:CGPointMake((d-s.width)/2, (d-s.height)/2) withAttributes:at];
    }];
}

// Hình minh họa điện thoại trong menu (Cổ điển / Hợp nhất)
static UIImage *PhoneIllustration(BOOL unified, BOOL selected) {
    CGSize sz = CGSizeMake(44, 84);
    UIColor *line = selected ? UIColor.systemBlueColor : UIColor.grayColor;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:sz] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [line setStroke]; [[UIColor colorWithWhite:.96 alpha:1] setFill];
        UIBezierPath *b = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,2,40,80) cornerRadius:8];
        b.lineWidth = 2; [b fill]; [b stroke];
        [line setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(16,6,12,4) cornerRadius:2] fill];
        [[UIColor colorWithWhite:.85 alpha:1] setFill];
        if (unified) { for (int r=0;r<2;r++) for (int i=0;i<4;i++)
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(6+i*9, 14+r*9, 7, 7) cornerRadius:2] fill]; }
        for (int i=0;i<(unified?3:5);i++)
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(6, (unified?36:16)+i*8, 32, 5) cornerRadius:2] fill];
        [line setFill];
        for (int i=0;i<(unified?4:5);i++)
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(8+i*(unified?8:6.5), 74, 4, 4)] fill];
    }];
}

#pragma mark - Chế độ Cổ điển / Hợp nhất

static void UpdateSearchButton(void);
static void ApplyMode(void) {
    if (!gTBC || gAll.count < 5) return;
    BOOL u = isUnified();
    NSArray *vcs = u ? @[gAll[1], gAll[2], gAll[3]] : gAll;   // hợp nhất: Cuộc gọi, Danh bạ, Bàn phím
    UIViewController *sel = gTBC.selectedViewController;
    [gTBC setViewControllers:vcs animated:NO];
    gTBC.selectedViewController = [vcs containsObject:sel] ? sel : vcs[0];
    [gTBC.tabBar setNeedsLayout];
    UpdateSearchButton();
}

@interface I26Helper : NSObject <UISearchBarDelegate>
+ (instancetype)shared;
- (void)searchTapped;
@end
@implementation I26Helper
+ (instancetype)shared { static I26Helper *h; static dispatch_once_t t; dispatch_once(&t, ^{ h = [I26Helper new]; }); return h; }
- (void)searchTapped {
    if (gAll.count < 5) return;
    UIViewController *contacts = gAll[2];
    gTBC.selectedViewController = contacts;
    UIViewController *top = [contacts isKindOfClass:UINavigationController.class] ? ((UINavigationController *)contacts).topViewController : contacts;
    UISearchController *sc = top.navigationItem.searchController;
    dispatch_async(dispatch_get_main_queue(), ^{ sc.active = YES; [sc.searchBar becomeFirstResponder]; });
}
- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)sb { [self searchTapped]; return NO; } // thanh tìm kiếm ở Gần đây -> tìm trong Danh bạ
@end

static void UpdateSearchButton(void) {
    UIButton *b = (UIButton *)[gTBC.view viewWithTag:26100];
    if (!isUnified()) { b.hidden = YES; return; }
    if (!b) {
        b = [UIButton buttonWithType:UIButtonTypeSystem]; b.tag = 26100;
        [b setImage:[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
        b.tintColor = UIColor.labelColor; b.backgroundColor = ButtonFill();
        b.layer.cornerRadius = 32; Shadow(b.layer, .12, 12, 4);
        [b addTarget:[I26Helper shared] action:@selector(searchTapped) forControlEvents:UIControlEventTouchUpInside];
        [gTBC.view addSubview:b];
    }
    b.hidden = NO;
    CGRect v = gTBC.view.bounds; CGFloat bottom = v.size.height - gTBC.view.safeAreaInsets.bottom + 6;
    b.frame = CGRectMake(v.size.width - 16 - 64, bottom - 64 - 14 + 14, 64, 64);
    [gTBC.view bringSubviewToFront:b];
}

#pragma mark - Gần đây: nút 3 sọc + menu

static const void *kSegKey = &kSegKey, *kDoneKey = &kDoneKey;

static void RefreshMenu(UIViewController *vc);
static UIMenu *BuildMenu(UIViewController *vc) {
    BOOL u = isUnified();
    UIAction *classic = [UIAction actionWithTitle:L(@"Cổ điển", @"Classic") image:PhoneIllustration(NO, !u) identifier:nil handler:^(UIAction *a) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kUnifiedKey]; ApplyMode(); RefreshMenu(vc); }];
    UIAction *unif = [UIAction actionWithTitle:L(@"Hợp nhất", @"Unified") image:PhoneIllustration(YES, u) identifier:nil handler:^(UIAction *a) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kUnifiedKey]; ApplyMode(); RefreshMenu(vc); }];
    classic.state = u ? UIMenuElementStateOff : UIMenuElementStateOn;
    unif.state    = u ? UIMenuElementStateOn  : UIMenuElementStateOff;
    UIMenu *modes = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[classic, unif]];

    void (^setFilter)(NSInteger) = ^(NSInteger i) {
        gFilter = i;
        UISegmentedControl *seg = objc_getAssociatedObject(vc, kSegKey);
        if (seg.numberOfSegments > i) { seg.selectedSegmentIndex = i; [seg sendActionsForControlEvents:UIControlEventValueChanged]; }
        RefreshMenu(vc);
    };
    UIAction *all = [UIAction actionWithTitle:L(@"Cuộc gọi", @"Calls") image:[UIImage systemImageNamed:@"phone"] identifier:nil handler:^(UIAction *a) { setFilter(0); }];
    UIAction *missed = [UIAction actionWithTitle:L(@"Cuộc gọi nhỡ", @"Missed") image:[UIImage systemImageNamed:@"phone.arrow.down.left"] identifier:nil handler:^(UIAction *a) { setFilter(1); }];
    UIAction *vm = [UIAction actionWithTitle:L(@"Thư thoại", @"Voicemail") image:[UIImage systemImageNamed:@"voicemail"] identifier:nil handler:^(UIAction *a) {
        if (gAll.count >= 5) { UIViewController *v = gAll[4]; if (!v.parentViewController) [vc presentViewController:v animated:YES completion:nil]; else gTBC.selectedViewController = v; } }];
    all.state = gFilter == 0 ? UIMenuElementStateOn : UIMenuElementStateOff;
    missed.state = gFilter == 1 ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIAction *manage = [UIAction actionWithTitle:L(@"Quản lý bộ lọc", @"Manage Filters") image:nil identifier:nil handler:^(UIAction *a) {
        UIAlertController *al = [UIAlertController alertControllerWithTitle:L(@"Bộ lọc", @"Filters") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [al addAction:[UIAlertAction actionWithTitle:L(@"Tất cả", @"All") style:0 handler:^(id x){ setFilter(0); }]];
        [al addAction:[UIAlertAction actionWithTitle:L(@"Nhỡ", @"Missed") style:0 handler:^(id x){ setFilter(1); }]];
        [al addAction:[UIAlertAction actionWithTitle:L(@"Hủy", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:al animated:YES completion:nil]; }];
    UIMenu *filters = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[all, missed, vm]];
    UIMenu *mg = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[manage]];
    return [UIMenu menuWithTitle:@"" children:@[modes, filters, mg]];
}
static void RefreshMenu(UIViewController *vc) { vc.navigationItem.rightBarButtonItem.menu = BuildMenu(vc); }

static void ConfigureRecents(UIViewController *vc) {
    if (objc_getAssociatedObject(vc, kDoneKey)) return;
    objc_setAssociatedObject(vc, kDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UINavigationItem *ni = vc.navigationItem;
    if ([ni.titleView isKindOfClass:UISegmentedControl.class]) {       // giữ lại Tất cả/Nhỡ để menu điều khiển
        objc_setAssociatedObject(vc, kSegKey, ni.titleView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ni.titleView = nil;
    }
    vc.title = L(@"Gần đây", @"Recents");
    vc.navigationController.navigationBar.prefersLargeTitles = YES;
    ni.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    ni.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"] menu:BuildMenu(vc)];
    UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
    sc.searchBar.placeholder = L(@"Tìm kiếm", @"Search");
    sc.searchBar.delegate = [I26Helper shared];
    ni.searchController = sc; ni.hidesSearchBarWhenScrolling = NO;
}

#pragma mark - Cell: avatar, thông tin, thẻ chi tiết liên hệ

static UITableView *TableOf(UIView *v) { while (v && ![v isKindOfClass:UITableView.class]) v = v.superview; return (UITableView *)v; }

static void StyleListCell(UITableViewCell *c) {
    UIView *cv = c.contentView; NSString *name = FirstLabelText(cv);
    if (!name.length) return;
    CGFloat d = 44, pad = 16, shift = d + 12;
    UIImageView *iv = (UIImageView *)[cv viewWithTag:26001];
    if (!iv) { iv = [UIImageView new]; iv.tag = 26001; iv.clipsToBounds = YES; iv.layer.cornerRadius = d/2; [cv addSubview:iv]; }
    iv.image = InitialsAvatar(name, d);
    iv.frame = CGRectMake(pad, (cv.bounds.size.height - d)/2, d, d);
    for (UIView *s in cv.subviews) {
        if (s == iv || [s isKindOfClass:UIButton.class]) continue;
        if (s.frame.origin.x < 60 && s.frame.size.width > 40) { CGRect f = s.frame; f.origin.x += shift; f.size.width -= shift; s.frame = f; }
    }
    NSMutableArray *btns = [NSMutableArray array]; FindAll(c, UIButton.class, btns);   // nút (i) tròn xám
    for (UIButton *b in btns) { b.backgroundColor = Dyn([UIColor colorWithWhite:.95 alpha:1], [UIColor colorWithWhite:.2 alpha:1]); Circle(b); }
}

static void StyleDetailCell(UITableViewCell *c) {
    UITableView *tv = TableOf(c); NSIndexPath *ip = [tv indexPathForCell:c]; if (!ip) return;
    NSInteger n = [tv numberOfRowsInSection:ip.section];
    c.backgroundColor = Dyn(UIColor.whiteColor, [UIColor colorWithWhite:.11 alpha:1]);
    c.layer.cornerRadius = 26; c.clipsToBounds = YES;
    CACornerMask m = 0;
    if (ip.row == 0) m |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    if (ip.row == n-1) m |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    c.layer.maskedCorners = m;
    CGRect f = c.frame; if (f.origin.x < 8) { f.origin.x = 16; f.size.width = tv.bounds.size.width - 32; c.frame = f; }
}

%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    if (!kPhone) return;
    UITableView *tv = TableOf(self); id del = tv.delegate ?: tv.dataSource;
    if (NameHas(del, @[@"ContactListViewController", @"Recents"]) || NameHas(self, @[@"Recents"])) StyleListCell(self);
    else if (NameHas(del, @[@"ContactViewController", @"ContactContentViewController"])) StyleDetailCell(self);
}
%end

#pragma mark - Hook chung cho UIViewController (khớp theo tên)

%hook UIViewController
- (void)viewDidLoad {
    %orig;
    if (kDebug) NSLog(@"[I26] VC %@", NSStringFromClass([self class]));
    if (kPhone) {
        if (NameHas(self, @[@"RecentsViewController", @"RecentsTableViewController"])) ConfigureRecents(self);
        if (NameHas(self, @[@"ContactContentViewController", @"ContactViewController"]))
            self.view.backgroundColor = Dyn([UIColor colorWithWhite:.95 alpha:1], UIColor.blackColor);
    }
}
- (void)viewDidLayoutSubviews {
    %orig;
    if (!kInCall || !NameHas(self, @[@"AudioCallViewController", @"InCallRootViewController", @"CallViewController"])) return;
    CAGradientLayer *g = nil;
    for (CALayer *l in self.view.layer.sublayers) if ([l.name isEqualToString:@"i26grad"]) g = (CAGradientLayer *)l;
    if (!g) {
        g = [CAGradientLayer layer]; g.name = @"i26grad";
        g.colors = @[(id)[UIColor colorWithRed:.30 green:.33 blue:.18 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:.14 green:.22 blue:.55 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:.28 green:.22 blue:.27 alpha:1].CGColor];
        g.locations = @[@0, @0.55, @1];
        [self.view.layer insertSublayer:g atIndex:0];
    }
    g.frame = self.view.bounds;
    NSMutableArray *labels = [NSMutableArray array]; FindAll(self.view, UILabel.class, labels);
    for (UILabel *l in labels) {
        if (!l.text.length || [l convertRect:l.bounds toView:self.view].origin.y > self.view.bounds.size.height * 0.4) continue;
        BOOL status = [l.text hasSuffix:@"…"] || [l.text hasSuffix:@"..."];
        l.font = [UIFont systemFontOfSize:status ? 30 : 52 weight:UIFontWeightBold];
        l.textColor = status ? [UIColor colorWithWhite:1 alpha:.6] : UIColor.whiteColor;
        l.textAlignment = NSTextAlignmentCenter; l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = .5;
    }
}
- (void)viewDidAppear:(BOOL)a {
    %orig;
    if (kPhone && [self isKindOfClass:UITabBarController.class]) {
        UITabBarController *t = (UITabBarController *)self;
        if (!gTBC && t.viewControllers.count == 5) { gTBC = t; gAll = [t.viewControllers copy]; }
        if (t == gTBC) ApplyMode();
    }
}
%end

#pragma mark - Bàn phím số, nút gọi, tab bar, search bar, nút liên hệ, nút trong cuộc gọi

%hook TPNumberPadButton
- (void)layoutSubviews {
    %orig;
    self.backgroundColor = ButtonFill(); Circle(self); Shadow(self.layer, .10, 14, 5);
    for (UIView *s in self.subviews) if (NameHas(s, @[@"Circle", @"Backdrop"])) s.hidden = YES;
}
%end

%hook PHBottomBarButton
- (void)layoutSubviews {
    %orig;
    self.backgroundColor = [UIColor colorWithRed:.204 green:.78 blue:.349 alpha:1]; Circle(self); Shadow(self.layer, .15, 10, 4);
}
%end

%hook UITabBar
- (void)setFrame:(CGRect)f {
    if (kPhone && f.size.width > 250 && f.size.height > 40) {   // thanh nổi dạng viên thuốc
        CGFloat right = isUnified() ? 16 + 64 + 10 : 16, h = 64;
        f = CGRectMake(16, CGRectGetMaxY(f) - h - 14 - 0, f.size.width - 16 - right, h);
    }
    %orig(f);
}
- (void)didMoveToWindow {
    %orig;
    if (!kPhone) return;
    UITabBarAppearance *a = [UITabBarAppearance new]; [a configureWithTransparentBackground];
    self.standardAppearance = a; self.scrollEdgeAppearance = a;
    self.backgroundColor = Dyn([UIColor colorWithWhite:1 alpha:.92], [UIColor colorWithWhite:.12 alpha:.92]);
    self.layer.cornerRadius = 32; Shadow(self.layer, .12, 16, 5);
}
%end

%hook UISearchBar
- (void)didMoveToWindow {
    %orig;
    if (!kPhone) return;
    UITextField *tf = self.searchTextField;
    tf.backgroundColor = Dyn(UIColor.whiteColor, [UIColor colorWithWhite:.15 alpha:1]);
    tf.layer.cornerRadius = 22; tf.clipsToBounds = YES;
}
%end

%hook UIButton
- (void)layoutSubviews {
    %orig;
    if (kPhone && NameHas(self, @[@"ContactAction", @"ActionButton"])) {          // 4 nút tròn: nhắn tin, gọi, video, mail
        self.backgroundColor = Dyn([UIColor colorWithWhite:.9 alpha:1], [UIColor colorWithWhite:.2 alpha:1]); Circle(self);
    }
    if (kInCall && NameHas(self, @[@"CallControl", @"InCallButton", @"PHInCall", @"ControlButton"])) {   // lưới nút 2x3
        if (![self.backgroundColor isEqual:UIColor.redColor]) self.backgroundColor = [UIColor colorWithWhite:1 alpha:.18];
        Circle(self);
    }
}
%end

%ctor {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    kPhone  = [bid isEqualToString:@"com.apple.mobilephone"];
    kInCall = [bid isEqualToString:@"com.apple.InCallService"];
    %init;
}
