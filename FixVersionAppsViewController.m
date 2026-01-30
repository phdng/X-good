#import "FixVersionAppsViewController.h"
#import <objc/runtime.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *applicationIdentifier;
@end

@interface FixVersionAppsViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, strong) NSUserDefaults *securitySettings;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedBundleIDs;
@property (nonatomic, strong) NSArray<NSDictionary *> *installedApps;
@property (nonatomic, strong) NSArray<NSDictionary *> *filteredApps;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation FixVersionAppsViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _securitySettings = [[NSUserDefaults alloc] initWithSuiteName:@"com.weaponx.securitySettings"];
        NSArray *saved = [_securitySettings objectForKey:@"fixVersionApps"];
        if ([saved isKindOfClass:[NSArray class]]) {
            _selectedBundleIDs = [NSMutableSet setWithArray:(NSArray *)saved];
        } else {
            _selectedBundleIDs = [NSMutableSet set];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Fix Version Apps";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(doneTapped)];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Search apps";
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],

        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor]
    ]];

    [self loadInstalledApps];
}

- (void)doneTapped {
    NSArray *toSave = [[self.selectedBundleIDs allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [self.securitySettings setObject:toSave forKey:@"fixVersionApps"];
    [self.securitySettings synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.hydra.projectx.fixVersionAppsChanged"
                                                        object:nil
                                                      userInfo:@{ @"count": @(toSave.count) }];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)loadInstalledApps {
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass || ![wsClass respondsToSelector:@selector(defaultWorkspace)]) {
        self.installedApps = @[];
        self.filteredApps = self.installedApps;
        [self.tableView reloadData];
        return;
    }

    LSApplicationWorkspace *workspace = [wsClass performSelector:@selector(defaultWorkspace)];
    NSArray *installed = [workspace allInstalledApplications] ?: @[];
    NSMutableArray *apps = [NSMutableArray array];

    for (id obj in installed) {
        if (![obj isKindOfClass:NSClassFromString(@"LSApplicationProxy")]) {
            // Still try KVC access
        }
        NSString *name = [obj valueForKey:@"localizedName"];
        NSString *bundleID = [obj valueForKey:@"bundleIdentifier"];
        if (!bundleID.length) bundleID = [obj valueForKey:@"applicationIdentifier"];
        if (!name.length) name = @"Unknown";
        if (!bundleID.length) continue;

        // Skip the app itself
        if ([bundleID isEqualToString:@"com.hydra.projectx"]) continue;

        [apps addObject:@{ @"name": name, @"bundleID": bundleID }];
    }

    self.installedApps = [apps sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"]];
    }];
    self.filteredApps = self.installedApps;
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"FixVersionAppCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"FixVersionAppCell"];
    }
    NSDictionary *app = self.filteredApps[indexPath.row];
    NSString *name = app[@"name"];
    NSString *bundleID = app[@"bundleID"];

    cell.textLabel.text = name;
    cell.detailTextLabel.text = bundleID;
    cell.accessoryType = [self.selectedBundleIDs containsObject:bundleID] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *app = self.filteredApps[indexPath.row];
    NSString *bundleID = app[@"bundleID"];
    if (!bundleID.length) return;

    if ([self.selectedBundleIDs containsObject:bundleID]) {
        [self.selectedBundleIDs removeObject:bundleID];
    } else {
        [self.selectedBundleIDs addObject:bundleID];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredApps = self.installedApps;
    } else {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *bindings) {
            NSString *n = app[@"name"];
            NSString *b = app[@"bundleID"];
            return [n localizedCaseInsensitiveContainsString:searchText] || [b localizedCaseInsensitiveContainsString:searchText];
        }];
        self.filteredApps = [self.installedApps filteredArrayUsingPredicate:p];
    }
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end
