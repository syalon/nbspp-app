//
//  VCMinerRelationData.m
//  oplayer
//
//  Created by SYALON on 13-10-23.
//
//

#import "VCMinerRelationData.h"
#import "ViewMinerRelationDataCell.h"
#import "ViewMinerRelationDataHeaderCell.h"
#import "ViewEmptyInfoCell.h"

enum
{
    kVcSecHeader = 0,           //  统计数据
    kVcSecRefList,              //  推荐详细列表
    
    kVcSecMax
};

@interface VCMinerRelationData ()
{
    NSString*                           _asset_id;
    
    UITableViewBase*                    _mainTableView;
    ViewEmptyInfoCell*                  _cellNoData;
    
    ViewMinerRelationDataHeaderCell*    _header;            //  顶部统计数据
    NSDictionary*                       _headerData;        //  顶部统计数据
    NSMutableArray*                     _dataArray;
}

@end

@implementation VCMinerRelationData

-(void)dealloc
{
    if (_mainTableView){
        [[IntervalManager sharedIntervalManager] releaseLock:_mainTableView];
        _mainTableView.delegate = nil;
        _mainTableView = nil;
    }
    _cellNoData = nil;
    _dataArray = nil;
    
    _headerData = nil;
    _asset_id = nil;
}

- (id)initWithAsset:(id)asset_id
{
    self = [super init];
    if (self) {
        // Custom initialization
        assert([[WalletManager sharedWalletManager] isWalletExist]);
        assert(asset_id);
        _asset_id = [asset_id copy];
        _headerData = nil;
        _dataArray = [NSMutableArray array];
    }
    return self;
}

- (id)scanRecentMiningReward:(id)data_history reward_account:(id)reward_account reward_asset:(id)reward_asset
{
    assert(reward_account && reward_asset);
    //  REMARK：定期锁仓挖矿根据vb对象发奖，同一个账号可能存在多个转账记录，需要把同block_num的所有记录一起计算。
    id data_array_history = [NSMutableArray array];
    NSInteger first_block_num = 0;
    if (data_history && [data_history count] > 0){
        for (id history in data_history) {
            id op = [history objectForKey:@"op"];
            if ([[op firstObject] integerValue] == ebo_transfer){
                id opdata =  [op lastObject];
                if ([reward_account isEqualToString:[opdata objectForKey:@"from"]] &&
                    [reward_asset isEqualToString:[[opdata objectForKey:@"amount"] objectForKey:@"asset_id"]]) {
                    if ([data_array_history count] <= 0) {
                        //  记录第一条记录
                        [data_array_history addObject:history];
                        first_block_num = [[history objectForKey:@"block_num"] integerValue];
                    } else {
                        if ([[history objectForKey:@"block_num"] integerValue] == first_block_num) {
                            //  记录其他同区块的记录
                            [data_array_history addObject:history];
                        } else {
                            //  区块号不同了，则说明已经不是同一批转账记录了。
                            break;
                        }
                    }
                }
            }
        }
    }
    return [data_array_history count] > 0 ? data_array_history : nil;
}

/*
 *  (private) 查询最近的挖矿奖励和推荐奖励数据。
 */
- (WsPromise*)queryLatestRewardData:(NSString*)account_id is_miner:(BOOL)is_miner
{
    assert(account_id);
    
    SettingManager* settingMgr = [SettingManager sharedSettingManager];
    ChainObjectManager* chainMgr = [ChainObjectManager sharedChainObjectManager];
    
    //  MINER 或 SCNY 发奖账号
    id reward_account = [settingMgr getAppParameters:is_miner ? @"reward_account_miner" : @"reward_account_scny"];
    //  发奖资产ID
    id reward_asset = [settingMgr getAppParameters:@"mining_reward_asset"];
    //  推荐挖矿发奖账号
    id reward_account_shares = [settingMgr getAppParameters:is_miner ? @"reward_account_shares_miner" : @"reward_account_shares_scny"];
    assert(reward_account && reward_asset && reward_account_shares);
    
    GrapheneApi* api_history = [[GrapheneConnectionManager sharedGrapheneConnectionManager] any_connection].api_history;
    id stop = [NSString stringWithFormat:@"1.%@.0", @(ebot_operation_history)];
    id start = [NSString stringWithFormat:@"1.%@.%@", @(ebot_operation_history), @(0)];
    
    return [[api_history exec:@"get_account_history" params:@[account_id, stop, @100, start]] then:^id(id data_history) {
        id reward_history_mining = [self scanRecentMiningReward:data_history reward_account:reward_account reward_asset:reward_asset];
        id reward_history_shares = [self scanRecentMiningReward:data_history reward_account:reward_account_shares reward_asset:reward_asset];
        
        NSMutableDictionary* reward_hash = [NSMutableDictionary dictionary];
        NSMutableDictionary* block_num_hash = [NSMutableDictionary dictionary];
        if (reward_history_mining) {
            [block_num_hash setObject:@YES forKey:[[reward_history_mining firstObject] objectForKey:@"block_num"]];
        }
        if (reward_history_shares) {
            [block_num_hash setObject:@YES forKey:[[reward_history_shares firstObject] objectForKey:@"block_num"]];
        }
        
        if ([block_num_hash count] > 0) {
            return [[chainMgr queryAllBlockHeaderInfos:[block_num_hash allKeys] skipQueryCache:NO] then:^id(id data) {
                if (reward_history_mining) {
                    id block_header = [chainMgr getBlockHeaderInfoByBlockNumber:[[reward_history_mining firstObject] objectForKey:@"block_num"]];
                    assert(block_header);
                    [reward_hash setObject:@{@"history":reward_history_mining, @"header":block_header} forKey:@"mining"];
                }
                if (reward_history_shares) {
                    id block_header = [chainMgr getBlockHeaderInfoByBlockNumber:[[reward_history_shares firstObject] objectForKey:@"block_num"]];
                    assert(block_header);
                    [reward_hash setObject:@{@"history":reward_history_shares, @"header":block_header} forKey:@"shares"];
                }
                //  返回奖励数据
                return [reward_hash copy];
            }];
        } else {
            //  没有任何挖矿奖励
            return [reward_hash copy];
        }
    }];
}

/*
 *  (private) 查询推荐数据（需要登录）。REMARK：不支持多签账号。
 */
- (WsPromise*)queryAccountRelationData:(id)op_account is_miner:(BOOL)is_miner login:(BOOL)login
{
    assert(op_account);
    WalletManager* walletMgr = [WalletManager sharedWalletManager];
    if (login) {
        assert(![walletMgr isLocked]);
        id sign_keys = [walletMgr getSignKeys:[op_account objectForKey:@"active"]];
        assert([sign_keys count] == 1);
        id active_wif_key = [[walletMgr getGraphenePrivateKeyByPublicKey:[sign_keys firstObject]] toWifString];
        return [[[NbWalletAPI sharedNbWalletAPI] login:op_account[@"name"]
                                    active_private_key:active_wif_key] then:^id(id data) {
            if (!data || [data objectForKey:@"error"]) {
                return [WsPromise resolve:@{@"error":NSLocalizedString(@"kMinerApiErrServerOrNetwork", @"推荐数据服务器或网络异常，请稍后再试。")}];
            } else {
                return [[NbWalletAPI sharedNbWalletAPI] queryRelation:op_account[@"id"] is_miner:is_miner];
            }
        }];
    } else {
        return [[NbWalletAPI sharedNbWalletAPI] queryRelation:op_account[@"id"] is_miner:is_miner];
    }
}

- (void)queryAllData
{
    id op_account = [[[WalletManager sharedWalletManager] getWalletAccountInfo] objectForKey:@"account"];
    assert(op_account);
    id account_id = op_account[@"id"];
    
    [self showBlockViewWithTitle:NSLocalizedString(@"kTipsBeRequesting", @"请求中...")];
    
    BOOL is_miner = [_asset_id isEqualToString:@"1.3.23"];  //  TODO:MINER立即值
    
    //  查询推荐关系
    id p1 = [self queryAccountRelationData:op_account is_miner:is_miner login:NO];
    
    //  查询收益数据（最近的NCN转账明细）
    id p2 = [self queryLatestRewardData:account_id is_miner:is_miner];
    
    [[[WsPromise all:@[p1, p2]] then:^id(id data_array) {
        id data_relation = [data_array objectAtIndex:0];
        id data_reward_hash = [data_array objectAtIndex:1];
        if (!data_relation || [data_relation objectForKey:@"error"]) {
            [self hideBlockView];
            //  第一次查询失败的情况
            if ([WalletManager isMultiSignPermission:op_account[@"active"]]) {
                //  多签账号不支持
                [OrgUtils makeToast:NSLocalizedString(@"kMinerApiErrNotSupportedMultiAccount", @"多签账号不支持查看推荐数据。")];
            } else {
                //  非多签账号 解锁后重新查询。
                [self GuardWalletUnlocked:YES body:^(BOOL unlocked) {
                    if (unlocked) {
                        [self showBlockViewWithTitle:NSLocalizedString(@"kTipsBeRequesting", @"请求中...")];
                        [[self queryAccountRelationData:op_account is_miner:is_miner login:YES] then:^id(id data_relation2) {
                            if (!data_relation2 || [data_relation2 objectForKey:@"error"]) {
                                [self hideBlockView];
                                [OrgUtils makeToast:NSLocalizedString(@"kMinerApiErrServerOrNetwork", @"推荐数据服务器或网络异常，请稍后再试。")];
                            } else {
                                [self onQueryResponsed:data_relation2 data_reward_hash:data_reward_hash];
                                [self hideBlockView];
                            }
                            return nil;
                        }];
                    }
                }];
            }
        } else {
            [self onQueryResponsed:data_relation data_reward_hash:data_reward_hash];
            [self hideBlockView];
        }
        return nil;;
    }] catch:^id(id error) {
        [self hideBlockView];
        [OrgUtils makeToast:NSLocalizedString(@"tip_network_error", @"网络异常，请稍后再试。")];
        return nil;;
    }];
}

- (void)onQueryResponsed:(id)data_miner data_reward_hash:(id)data_reward_hash
{
    id data_miner_items = [data_miner objectForKey:@"data"];
    
    //  clear
    [_dataArray removeAllObjects];
    
    //  推荐关系列表
    double total_amount = 0;
    if (data_miner_items && [data_miner_items isKindOfClass:[NSArray class]] && [data_miner_items count] > 0) {
        for (id item in data_miner_items) {
            [_dataArray addObject:item];
            total_amount += [[item objectForKey:@"slave_hold"] doubleValue];
        }
    }
    
    //  生成统计数据
    _headerData = @{
        @"total_account": @([_dataArray count]),
        @"total_amount": @(total_amount),
        @"data_reward_hash": data_reward_hash ?: @{},
    };
    
    //  动态设置UI的可见性
    _cellNoData.hidden = [_dataArray count] > 0;
    [_mainTableView reloadData];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [ThemeManager sharedThemeManager].appBackColor;
    
    // Do any additional setup after loading the view.
    CGRect rect = [self rectWithoutNaviAndPageBar];
    
    _mainTableView = [[UITableViewBase alloc] initWithFrame:rect style:UITableViewStylePlain];
    _mainTableView.delegate = self;
    _mainTableView.dataSource = self;
    _mainTableView.backgroundColor = [UIColor clearColor];
    _mainTableView.separatorStyle = UITableViewCellSeparatorStyleNone;  //  REMARK：不显示cell间的横线。
    [self.view addSubview:_mainTableView];
    
    //  UI - 顶部统计数据
    _header = [[ViewMinerRelationDataHeaderCell alloc] init];
    
    //  UI - 空列表
    _cellNoData = [[ViewEmptyInfoCell alloc] initWithText:NSLocalizedString(@"kMinerSharesDataNoAnyShares", @"没有任何推荐数据") iconName:nil];
    _cellNoData.hideTopLine = YES;
    _cellNoData.hideBottomLine = YES;
    _cellNoData.hidden = YES;
    
    //  查询数据
    [self queryAllData];
}

#pragma mark- TableView delegate method
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kVcSecMax;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == kVcSecHeader) {
        return 1;
    }
    
    NSInteger n = [_dataArray count];
    if (n > 0){
        //  rows + title
        return n;
    }else{
        //  Empty Cell
        return 1;
    }
}


- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == kVcSecHeader) {
        return 12.0f;
    } else {
        return 12 + 44.0f;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section == kVcSecHeader){
        return [[UIView alloc] init];
    }else{
        CGFloat fWidth = self.view.bounds.size.width;
        CGFloat xOffset = tableView.layoutMargins.left;
        UIView* myView = [[UIView alloc] init];
        myView.backgroundColor = [ThemeManager sharedThemeManager].appBackColor;
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(xOffset, 12, fWidth - xOffset * 2, 44.0f)];
        titleLabel.textColor = [ThemeManager sharedThemeManager].textColorHighlight;
        titleLabel.backgroundColor = [UIColor clearColor];
        titleLabel.font = [UIFont boldSystemFontOfSize:16];
        titleLabel.text = NSLocalizedString(@"kMinerSharesDataShareItemsTitle", @"推荐明细");
        [myView addSubview:titleLabel];
        
        return myView;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kVcSecHeader) {
        return 8 + 24.0f * 4 + 8;
    } else {
        if ([_dataArray count] <= 0) {
            //  Empty Cell
            return 60.0f;
        } else {
            return tableView.rowHeight;
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL is_miner = [_asset_id isEqualToString:@"1.3.23"];  //  TODO:MINER立即值
    
    if (indexPath.section == kVcSecHeader) {
        _header.is_miner = is_miner;
        _header.item = _headerData;
        return _header;
    }
    
    if ([_dataArray count] <= 0) {
        return _cellNoData;
    }
    
    static NSString* identify = @"id_miner_relation_data";
    
    ViewMinerRelationDataCell* cell = (ViewMinerRelationDataCell *)[tableView dequeueReusableCellWithIdentifier:identify];
    if (!cell)
    {
        cell = [[ViewMinerRelationDataCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identify];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.backgroundColor = [UIColor clearColor];
    }
    cell.showCustomBottomLine = YES;
    cell.is_miner = is_miner;
    [cell setItem:[_dataArray objectAtIndex:indexPath.row]];
    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
