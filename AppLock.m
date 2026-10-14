#import <UIKit/UIKit.h>

static NSString *const ALKRequiredPIN = @"930809";

@interface ALKLockViewController : UIViewController <UITextFieldDelegate>
@property(nonatomic, strong) UITextField *pinField;
@property(nonatomic, copy) void (^unlockHandler)(void);
@end

@implementation ALKLockViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:0.055 green:0.063 blue:0.082 alpha:1.0];

    UILabel *icon = [[UILabel alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.text = @"🔒";
    icon.font = [UIFont systemFontOfSize:52.0];
    icon.textAlignment = NSTextAlignmentCenter;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"AppLock";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:28.0];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *message = [[UILabel alloc] init];
    message.translatesAutoresizingMaskIntoConstraints = NO;
    message.text = @"请输入 PIN 码以继续使用";
    message.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    message.font = [UIFont systemFontOfSize:16.0];
    message.textAlignment = NSTextAlignmentCenter;

    self.pinField = [[UITextField alloc] init];
    self.pinField.translatesAutoresizingMaskIntoConstraints = NO;
    self.pinField.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    self.pinField.textColor = UIColor.whiteColor;
    self.pinField.tintColor = UIColor.whiteColor;
    self.pinField.layer.cornerRadius = 12.0;
    self.pinField.layer.borderWidth = 1.0;
    self.pinField.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.pinField.font = [UIFont monospacedDigitSystemFontOfSize:24.0 weight:UIFontWeightMedium];
    self.pinField.textAlignment = NSTextAlignmentCenter;
    self.pinField.keyboardType = UIKeyboardTypeNumberPad;
    self.pinField.secureTextEntry = YES;
    self.pinField.placeholder = @"6 位 PIN 码";
    self.pinField.delegate = self;
    [self.pinField addTarget:self action:@selector(pinChanged:) forControlEvents:UIControlEventEditingChanged];
    self.pinField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:@"6 位 PIN 码"
            attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.55 alpha:1.0]}];

    UIButton *unlockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    unlockButton.translatesAutoresizingMaskIntoConstraints = NO;
    unlockButton.backgroundColor = [UIColor colorWithRed:0.17 green:0.48 blue:0.96 alpha:1.0];
    unlockButton.layer.cornerRadius = 12.0;
    unlockButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [unlockButton setTitle:@"解锁" forState:UIControlStateNormal];
    [unlockButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [unlockButton addTarget:self action:@selector(validatePIN) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, message, self.pinField, unlockButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 16.0;
    [stack setCustomSpacing:8.0 afterView:title];
    [stack setCustomSpacing:28.0 afterView:message];
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-25.0],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32.0],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:360.0],
        [self.pinField.heightAnchor constraintEqualToConstant:54.0],
        [unlockButton.heightAnchor constraintEqualToConstant:52.0]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.pinField becomeFirstResponder];
}

- (void)resetForLock {
    self.pinField.text = @"";
    if (self.view.window != nil) {
        [self.pinField becomeFirstResponder];
    }
}

- (void)pinChanged:(UITextField *)field {
    if (field.text.length > 6) {
        field.text = [field.text substringToIndex:6];
    }
}

- (BOOL)textField:(UITextField *)textField
shouldChangeCharactersInRange:(NSRange)range
replacementString:(NSString *)string {
    NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([string rangeOfCharacterFromSet:notDigits].location != NSNotFound) {
        return NO;
    }
    NSUInteger newLength = textField.text.length - range.length + string.length;
    return newLength <= 6;
}

- (void)validatePIN {
    if ([self.pinField.text isEqualToString:ALKRequiredPIN]) {
        self.pinField.text = @"";
        if (self.unlockHandler != nil) {
            self.unlockHandler();
        }
        return;
    }

    self.pinField.text = @"";
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"PIN码验证失败"
                         message:@"PIN码错误，禁止使用此应用。"
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"重新输入"
                                            style:UIAlertActionStyleDefault
                                          handler:^(__unused UIAlertAction *action) {
        [weakSelf.pinField becomeFirstResponder];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface ALKLockController : NSObject
@property(nonatomic, strong) UIWindow *lockWindow;
@property(nonatomic, strong) ALKLockViewController *lockViewController;
@property(nonatomic, weak) UIWindow *previousKeyWindow;
@property(nonatomic, assign) BOOL unlocked;
@end


@implementation ALKLockController

+ (instancetype)sharedController {
    static ALKLockController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[self alloc] init];
    });
    return controller;
}

- (void)start {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(applicationDidBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(applicationWillResignActive:)
                   name:UIApplicationWillResignActiveNotification object:nil];

    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        [self showLock];
    }
}

- (UIWindowScene *)activeWindowScene API_AVAILABLE(ios(13.0)) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:UIWindowScene.class]) {
            return (UIWindowScene *)scene;
        }
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (UIWindow *)makeLockWindow {
    UIWindow *window;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self activeWindowScene];
        window = scene != nil ? [[UIWindow alloc] initWithWindowScene:scene]
                              : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    } else {
        window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }

    ALKLockViewController *viewController = [[ALKLockViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    viewController.unlockHandler = ^{
        [weakSelf unlock];
    };
    window.rootViewController = viewController;
    window.windowLevel = UIWindowLevelAlert + 100.0;
    window.backgroundColor = UIColor.blackColor;
    self.lockViewController = viewController;
    return window;
}

- (UIWindow *)currentKeyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow && window != self.lockWindow) {
                    return window;
                }
            }
        }
    }
    // KVC keeps compatibility with apps that do not use scenes without invoking
    // UIApplication.keyWindow, which is deprecated in modern SDKs.
    return [UIApplication.sharedApplication valueForKey:@"keyWindow"];
}

- (void)applicationDidBecomeActive:(__unused NSNotification *)notification {
    if (!self.unlocked) {
        [self showLock];
    }
}

- (void)applicationWillResignActive:(__unused NSNotification *)notification {
    self.unlocked = NO;
    [self showLock];
}

- (void)showLock {
    NSAssert(NSThread.isMainThread, @"AppLock UI must run on the main thread");
    self.unlocked = NO;

    if (self.lockWindow == nil) {
        self.previousKeyWindow = [self currentKeyWindow];
        self.lockWindow = [self makeLockWindow];
    }
    [self.lockViewController resetForLock];
    self.lockWindow.hidden = NO;
    [self.lockWindow makeKeyAndVisible];
}

- (void)unlock {
    self.unlocked = YES;
    [self.lockViewController.pinField resignFirstResponder];
    self.lockWindow.hidden = YES;
    [self.previousKeyWindow makeKeyWindow];
}

@end

__attribute__((constructor)) static void AppLockInitialize(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ALKLockController sharedController] start];
    });
}
