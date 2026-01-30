#import "KeychainGroupsViewController.h"

#import "AppEntitlementsReader.h"

static NSString *PXKeychainWipeEnabledKey(NSString *bundleID) {
    return [NSString stringWithFormat:@"dataCleanerKeychainWipeEnabled_%@", bundleID ?: @""];
}

static NSString *PXKeychainWipeGroupsKey(NSString *bundleID) {
    return [NSString stringWithFormat:@"dataCleanerKeychainWipeGroups_%@", bundleID ?: @""];
}

@interface KeychainGroupsViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSArray<NSString *> *groups;
@property (nonatomic, strong) NSArray<NSString *> *filteredGroups;
@property (nonatomic, strong) NSMutableSet<NSString *> *selected;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *footerLabel;
@end

@implementation KeychainGroupsViewController

- (instancetype)initWithBundleID:(NSString *)bundleID {
    self = [super init];
    if (self) {
        _bundleID = [bundleID copy] ?: @"";
        _defaults = [NSUserDefaults standardUserDefaults];
        _groups = @[];
        _filteredGroups = @[];
        _selected = [NSMutableSet set];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Keychain Groups";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveTapped)];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"All"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(selectAllTapped)];

    UIBarButtonItem *noneItem = [[UIBarButtonItem alloc] initWithTitle:@"None"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(selectNoneTapped)];
    self.toolbarItems = @[noneItem];
    [self.navigationController setToolbarHidden:NO animated:NO];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"Search group";
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.footerLabel = [[UILabel alloc] init];
    self.footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.footerLabel.numberOfLines = 2;
    self.footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    self.footerLabel.textColor = [UIColor secondaryLabelColor];
    self.footerLabel.text = @"Selected groups will be wiped on Clear Data.\nThis may sign you out of shared services.";
    [self.view addSubview:self.footerLabel];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],

        [self.footerLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.footerLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.footerLabel.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],

        [self.tableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.footerLabel.topAnchor constant:-8],
    ]];

    [self loadGroups];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        [self.navigationController setToolbarHidden:YES animated:NO];
    }
}

- (void)loadGroups {
    NSError *err = nil;
    AppEntitlementsReader *reader = [[AppEntitlementsReader alloc] init];
    NSArray<NSString *> *groups = [reader keychainAccessGroupsForBundleID:self.bundleID error:&err];
    if (!groups.count) {
        self.groups = @[];
        self.filteredGroups = self.groups;
        [self.selected removeAllObjects];
        self.footerLabel.text = err ? [NSString stringWithFormat:@"Failed to read entitlements: %@", err.localizedDescription]
                               : @"No keychain-access-groups found for this app.";
        self.navigationItem.rightBarButtonItem.enabled = NO;
        [self.tableView reloadData];
        return;
    }

    self.groups = groups;
    self.filteredGroups = self.groups;
    self.navigationItem.rightBarButtonItem.enabled = YES;

    // Default selection: ALL groups.
    NSArray *saved = [self.defaults objectForKey:PXKeychainWipeGroupsKey(self.bundleID)];
    if ([saved isKindOfClass:[NSArray class]] && [(NSArray *)saved count] > 0) {
        for (id v in (NSArray *)saved) {
            if ([v isKindOfClass:[NSString class]]) {
                [self.selected addObject:(NSString *)v];
            }
        }
    } else {
        [self.selected addObjectsFromArray:self.groups];
    }
    [self.tableView reloadData];
}

- (void)selectAllTapped {
    [self.selected removeAllObjects];
    [self.selected addObjectsFromArray:self.groups];
    [self.tableView reloadData];
}

- (void)selectNoneTapped {
    [self.selected removeAllObjects];
    [self.tableView reloadData];
}

- (void)saveTapped {
    NSArray<NSString *> *sorted = [[self.selected allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [self.defaults setBool:YES forKey:PXKeychainWipeEnabledKey(self.bundleID)];
    [self.defaults setObject:sorted forKey:PXKeychainWipeGroupsKey(self.bundleID)];
    [self.defaults synchronize];

    if (self.onSave) {
        self.onSave();
    }
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredGroups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KeychainGroupCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"KeychainGroupCell"];
        cell.textLabel.numberOfLines = 1;
        cell.detailTextLabel.numberOfLines = 1;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    }
    NSString *group = self.filteredGroups[indexPath.row];
    cell.textLabel.text = group;
    cell.detailTextLabel.text = [self.selected containsObject:group] ? @"Selected" : @"";
    cell.accessoryType = [self.selected containsObject:group] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *group = self.filteredGroups[indexPath.row];
    if (!group.length) return;
    if ([self.selected containsObject:group]) {
        [self.selected removeObject:group];
    } else {
        [self.selected addObject:group];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - UISearchBar

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredGroups = self.groups;
    } else {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(NSString *group, NSDictionary *bindings) {
            return [group localizedCaseInsensitiveContainsString:searchText];
        }];
        self.filteredGroups = [self.groups filteredArrayUsingPredicate:p];
    }
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end
