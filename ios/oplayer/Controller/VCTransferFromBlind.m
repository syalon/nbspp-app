//
//  VCTransferFromBlind.m
//  oplayer
//
//  Created by SYALON on 13-10-23.
//
//

#import "VCTransferFromBlind.h"
#import "VCStealthTransferHelper.h"
#import "ViewBlindInputOutputItemCell.h"
#import "ViewEmptyInfoCell.h"

#import "VCSelectBlindBalance.h"
#import "VCSearchNetwork.h"
#import "VCBlindOutputAddOne.h"
#import "ViewTipsInfoCell.h"

#import "GrapheneSerializer.h"
#import "GraphenePublicKey.h"
#import "GraphenePrivateKey.h"

enum
{
    kVcSecBlindOutput = 0,  //  隐私输出
    kVcSecAddOne,           //  新增按钮
    kVcSecToAccount,        //  目标账号
    kVcSecBalance,          //  转账总数量、可用数量、广播手续费
    kVcSecSubmit,           //  提交按钮
    kVcSecTips,             //  提示信息
    
    kvcSecMax
};

enum
{
    kVcSubInputTotalAmount = 0,
    kVcSubNetworkFee,
    
    kVcSubMax
};

@interface VCTransferFromBlind ()
{
    WsPromiseObject*            _result_promise;
    NSDictionary*               _curr_blind_asset;      //  当前选择的隐私收据关联的资产（所有隐私收据必须资产相同），收据列表为空时资产为 nil。
    
    UITableViewBase*            _mainTableView;
    
    ViewTipsInfoCell*           _cell_tips;
    ViewEmptyInfoCell*          _cell_add_one;
    ViewBlockLabel*             _lbCommit;
    
    NSMutableArray*             _data_array_blind_input;
    NSDictionary*               _to_account;
}

@end

@implementation VCTransferFromBlind

-(void)dealloc
{
    _result_promise = nil;
    _curr_blind_asset = nil;
    if (_mainTableView){
        [[IntervalManager sharedIntervalManager] releaseLock:_mainTableView];
        _mainTableView.delegate = nil;
        _mainTableView = nil;
    }
    _cell_tips = nil;
    _cell_add_one = nil;
    _lbCommit = nil;
    _to_account = nil;
}

- (id)initWithBlindBalance:(id)blind_balance result_promise:(WsPromiseObject*)result_promise
{
    self = [super init];
    if (self) {
        //@"real_to_key": @"TEST71jaNWV7ZfsBRUSJk6JfxSzEB7gvcS7nSftbnFVDeyk6m3xj53",  //  仅显示用
        //@"one_time_key": @"TEST71jaNWV7ZfsBRUSJk6JfxSzEB7gvcS7nSftbnFVDeyk6m3xj53", //  转账用
        //@"to": @"TEST71jaNWV7ZfsBRUSJk6JfxSzEB7gvcS7nSftbnFVDeyk6m3xj53",           //  没用到
        //@"decrypted_memo": @{
        //    @"amount": @{@"asset_id": @"1.3.0", @"amount": @12300000},              //  转账用，显示用。
        //    @"blinding_factor": @"",                                                //  转账用
        //    @"commitment": @"",                                                     //  转账用
        //    @"check": @331,                                                         //  导入check用，显示用。
        //}
        _to_account = nil;
        _result_promise = result_promise;
        _data_array_blind_input = [NSMutableArray array];
        _curr_blind_asset = nil;
        if (blind_balance) {
            [self onSelectBlindBalanceDone:@[blind_balance]];
        }
    }
    return self;
}

- (void)refreshView
{
    [_mainTableView reloadData];
}

- (NSString*)genTransferTipsMessage
{
    //    return [_opExtraArgs objectForKey:@"kMsgTips"] ?: @"";
    return @"【温馨提示】\n隐私转账可同时转出多个隐私余额到指定公共账号。";
}

//- (void)onRightButtonClicked
//{
//    VCBlindBalance* vc = [[VCBlindBalance alloc] init];
//    //  TODO:6.0 lang
//    [self pushViewController:vc vctitle:@"隐私资产" backtitle:kVcDefaultBackTitleName];
//}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    ThemeManager* theme = [ThemeManager sharedThemeManager];
    self.view.backgroundColor = theme.appBackColor;
    
    //  TODO:6.0 icon
    //    [self showRightImageButton:@"iconProposal" action:@selector(onRightButtonClicked) color:theme.textColorNormal];
    
    //  UI - 列表
    CGRect rect = [self rectWithoutNavi];
    _mainTableView = [[UITableViewBase alloc] initWithFrame:rect style:UITableViewStyleGrouped];
    _mainTableView.delegate = self;
    _mainTableView.dataSource = self;
    _mainTableView.separatorStyle = UITableViewCellSeparatorStyleNone;  //  REMARK：不显示cell间的横线。
    _mainTableView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_mainTableView];
    
    //  UI - 提示信息
    _cell_tips = [[ViewTipsInfoCell alloc] initWithText:[self genTransferTipsMessage]];
    _cell_tips.hideBottomLine = YES;
    _cell_tips.hideTopLine = YES;
    _cell_tips.backgroundColor = [UIColor clearColor];
    
    //  TODO:6.0
    _cell_add_one = [[ViewEmptyInfoCell alloc] initWithText:@"选择收据" iconName:@"iconAdd"];
    _cell_add_one.showCustomBottomLine = YES;
    _cell_add_one.accessoryType = UITableViewCellAccessoryNone;
    _cell_add_one.selectionStyle = UITableViewCellSelectionStyleBlue;
    _cell_add_one.userInteractionEnabled = YES;
    _cell_add_one.imgIcon.tintColor = theme.textColorHighlight;
    _cell_add_one.lbText.textColor = theme.textColorHighlight;
    
    _lbCommit = [self createCellLableButton:@"隐私转出"];
}

#pragma mark- TableView delegate method
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return kvcSecMax;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case kVcSecBlindOutput:
            //  title + all blind output
            return 1 + [_data_array_blind_input count];
        case kVcSecToAccount:
            return 2;
        case kVcSecBalance:
            return kVcSubMax;
        default:
            break;
    }
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case kVcSecBlindOutput:
        {
            if (indexPath.row == 0) {
                return 28.0f;   //  title
            } else {
                return 32.0f;
            }
        }
            break;
        case kVcSecToAccount:
            if (indexPath.row == 0) {
                return 28.0f;
            }
            break;
        case kVcSecBalance:
            return 28.0f;       //  TODO:6.0
        case kVcSecTips:
            return [_cell_tips calcCellDynamicHeight:tableView.layoutMargins.left];
        default:
            break;
    }
    return tableView.rowHeight;
}

/**
 *  调整Header和Footer高度。REMARK：header和footer VIEW 不能为空，否则高度设置无效。
 */
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kVcSecAddOne:
            return 0.01f;
        case kVcSecBalance:
            return 0.01f;
        default:
            break;
    }
    return 10.0f;
}
- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @" ";
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 10.0f;
}
- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @" ";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ThemeManager* theme = [ThemeManager sharedThemeManager];
    
    switch (indexPath.section) {
        case kVcSecBlindOutput:
        {
            static NSString* identify = @"id_blind_output_info";
            ViewBlindInputOutputItemCell* cell = (ViewBlindInputOutputItemCell*)[tableView dequeueReusableCellWithIdentifier:identify];
            if (!cell)
            {
                cell = [[ViewBlindInputOutputItemCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                           reuseIdentifier:identify
                                                                        vc:self
                                                                    action:@selector(onButtonClicked_InputRemove:)];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.accessoryType = UITableViewCellAccessoryNone;
            }
            cell.showCustomBottomLine = NO;
            cell.itemType = kBlindItemTypeInput;
            [cell setTagData:indexPath.row];
            if (indexPath.row == 0) {
                [cell setItem:@{@"title":@YES, @"num":@([_data_array_blind_input count])}];
            } else {
                [cell setItem:[_data_array_blind_input objectAtIndex:indexPath.row - 1]];
            }
            return cell;
        }
            break;
        case kVcSecToAccount:
        {
            if (indexPath.row == 0) {
                UITableViewCellBase* cell = [[UITableViewCellBase alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
                cell.backgroundColor = [UIColor clearColor];
                cell.hideBottomLine = YES;
                cell.accessoryType = UITableViewCellAccessoryNone;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.textLabel.text = NSLocalizedString(@"kVcAssetOpCellTitleIssueTargetAccount", @"目标账户");
                cell.textLabel.font = [UIFont systemFontOfSize:13.0f];
                cell.textLabel.textColor = theme.textColorMain;
                return cell;
            } else {
                UITableViewCellBase* cell = [[UITableViewCellBase alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
                cell.backgroundColor = [UIColor clearColor];
                cell.accessoryType = UITableViewCellAccessoryNone;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.showCustomBottomLine = YES;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleBlue;
                if (_to_account) {
                    cell.textLabel.textColor = theme.buyColor;
                    cell.textLabel.text = [_to_account objectForKey:@"name"];
                    cell.detailTextLabel.font = [UIFont systemFontOfSize:14.0f];
                    cell.detailTextLabel.textColor = theme.textColorMain;
                    cell.detailTextLabel.text = [_to_account objectForKey:@"id"];
                } else {
                    cell.textLabel.textColor = theme.textColorGray;
                    cell.textLabel.text = NSLocalizedString(@"kVcAssetOpCellValueIssueTargetAccountDefault", @"请选择目标账户");
                    cell.detailTextLabel.text = @"";
                }
                return cell;
            }
        }
            break;
        case kVcSecBalance:
        {
            UITableViewCellBase* cell = [[UITableViewCellBase alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
            cell.backgroundColor = [UIColor clearColor];
            cell.textLabel.textColor = theme.textColorGray;
            cell.detailTextLabel.textColor = theme.textColorNormal;
            cell.textLabel.font = [UIFont systemFontOfSize:13.0f];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.hideTopLine = YES;
            cell.hideBottomLine = YES;
            
            switch (indexPath.row) {
                case kVcSubInputTotalAmount:
                {
                    cell.textLabel.text = @"收据总金额";
                    if (_curr_blind_asset) {
                        id str_amount = [OrgUtils formatFloatValue:[self calcBlindInputTotalAmount] usesGroupingSeparator:NO];
                        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", str_amount, _curr_blind_asset[@"symbol"]];
                    } else {
                        cell.detailTextLabel.text = @"--";
                    }
                }
                    break;
                case kVcSubNetworkFee:
                {
                    cell.textLabel.text = @"广播手续费";
                    id n_fee = [[ChainObjectManager sharedChainObjectManager] getNetworkCurrentFee:ebo_transfer_from_blind
                                                                                             kbyte:nil
                                                                                               day:nil
                                                                                            output:nil];
                    if (n_fee) {
                        id str_amount = [OrgUtils formatFloatValue:n_fee usesGroupingSeparator:NO];
                        if (_curr_blind_asset) {
                            //  TODO:6.0 非 BTS 需要汇率换算 待处理
                            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", str_amount, _curr_blind_asset[@"symbol"]];
                        } else {
                            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@",
                                                         str_amount,
                                                         [ChainObjectManager sharedChainObjectManager].grapheneCoreAssetSymbol];
                        }
                    } else {
                        cell.detailTextLabel.text = @"未知";
                    }
                }
                    break;
                default:
                    break;
            }
            return cell;
        }
            break;
            
        case kVcSecTips:
            return _cell_tips;
            
        case kVcSecAddOne:
            return _cell_add_one;
            
        case kVcSecSubmit:
        {
            UITableViewCellBase* cell = [[UITableViewCellBase alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.backgroundColor = [UIColor clearColor];
            [self addLabelButtonToCell:_lbCommit cell:cell leftEdge:tableView.layoutMargins.left];
            return cell;
        }
            break;
        default:
            break;
    }
    //  not reached.
    return nil;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [[IntervalManager sharedIntervalManager] callBodyWithFixedInterval:tableView body:^{
        switch (indexPath.section) {
            case kVcSecToAccount:
            {
                if (indexPath.row == 1) {
                    VCSearchNetwork* vc = [[VCSearchNetwork alloc] initWithSearchType:enstAccount callback:^(id account_info) {
                        if (account_info){
                            _to_account = account_info;
                            [_mainTableView reloadData];
                        }
                    }];
                    [self pushViewController:vc
                                     vctitle:NSLocalizedString(@"kVcTitleSelectToAccount", @"搜索目标帐号")
                                   backtitle:kVcDefaultBackTitleName];
                }
            }
                break;
            case kVcSecAddOne:
                [self onAddOneClicked];
                break;
            case kVcSecSubmit:
                [self onSubmitClicked];
                break;
            default:
                break;
        }
    }];
}

/**
 *  事件 - 移除某个隐私输入收据
 */
- (void)onButtonClicked_InputRemove:(UIButton*)button
{
    [_data_array_blind_input removeObjectAtIndex:button.tag - 1];
    [_mainTableView reloadData];
}

- (void)onSelectBlindBalanceDone:(id)new_blind_balance_array
{
    assert(new_blind_balance_array);
    [_data_array_blind_input removeAllObjects];
    [_data_array_blind_input addObjectsFromArray:new_blind_balance_array];
    //  TODO:6.0 更新asset
    
    if ([_data_array_blind_input count] > 0) {
        id amount = [[[_data_array_blind_input firstObject] objectForKey:@"decrypted_memo"] objectForKey:@"amount"];
        _curr_blind_asset = [[ChainObjectManager sharedChainObjectManager] getChainObjectByID:[amount objectForKey:@"asset_id"]];
    } else {
        _curr_blind_asset = nil;
    }
}

- (void)onAddOneClicked
{
    //  TODO:6.0 添加 收据
    
    //    //  限制最大隐私输出数量
    //    int allow_maximum_blind_output = 10;
    //    if ([_data_array_blind_input count] >= allow_maximum_blind_output) {
    //        //  TODO:6.0 lang
    //        [OrgUtils makeToast:[NSString stringWithFormat:@"最多只能添加 %@ 个隐私输出。", @(allow_maximum_blind_output)]];
    //        return;
    //    }
    //
    
    [VCStealthTransferHelper processSelectReceipts:self callback:^(id new_blind_balance_array) {
        assert(new_blind_balance_array);
        //  添加
        [self onSelectBlindBalanceDone:new_blind_balance_array];
        //  刷新
        [_mainTableView reloadData];
    }];
}


- (NSDecimalNumber*)calcBlindInputTotalAmount
{
    ChainObjectManager* chainMgr = [ChainObjectManager sharedChainObjectManager];
    NSDecimalNumber* n_total = [NSDecimalNumber zero];
    for (id blind_balance in _data_array_blind_input) {
        id decrypted_memo = [blind_balance objectForKey:@"decrypted_memo"];
        id amount = [decrypted_memo objectForKey:@"amount"];
        id asset = [chainMgr getChainObjectByID:[amount objectForKey:@"asset_id"]];
        assert(asset);
        id n_amount = [NSDecimalNumber decimalNumberWithMantissa:[[amount objectForKey:@"amount"] unsignedLongLongValue]
                                                        exponent:-[[asset objectForKey:@"precision"] integerValue]
                                                      isNegative:NO];
        n_total = [n_total decimalNumberByAdding:n_amount];
    }
    return n_total;
}

- (void)onSubmitClicked
{
    if ([_data_array_blind_input count] <= 0) {
        [OrgUtils makeToast:@"请添加要转出的隐私收据信息。"];
        return;
    }
    
    if (!_to_account) {
        [OrgUtils makeToast:@"请选择要转出的目标账号。"];
        return;
    }
    
    NSDecimalNumber* n_total = [self calcBlindInputTotalAmount];
    if ([n_total compare:[NSDecimalNumber zero]] <= 0) {
        [OrgUtils makeToast:@"无效收据，余额信息为空。"];
        return;
    }
    
    id decrypted_memo = [[_data_array_blind_input firstObject] objectForKey:@"decrypted_memo"];
    assert(decrypted_memo);
    id asset_id = [[decrypted_memo objectForKey:@"amount"] objectForKey:@"asset_id"];
    id asset = [[ChainObjectManager sharedChainObjectManager] getChainObjectByID:asset_id];
    id n_fee = [[ChainObjectManager sharedChainObjectManager] getNetworkCurrentFee:ebo_transfer_from_blind kbyte:nil day:nil output:nil];
    
    if ([n_total compare:n_fee] <= 0) {
        [OrgUtils makeToast:@"收据金额太低，不足以支付手续费。"];
        return;
    }
    
    //  解锁钱包
    [self GuardWalletUnlocked:NO body:^(BOOL unlocked) {
        if (unlocked) {
            [self transferFromBlindCore:_data_array_blind_input asset:asset n_total:n_total n_fee:n_fee];
        }
    }];
}

- (void)transferFromBlindCore:(NSArray*)blind_balance_array asset:(id)asset n_total:(id)n_total n_fee:(id)n_fee
{
    assert(blind_balance_array && [blind_balance_array count] > 0);
    
    //  根据隐私收据生成 blind_input 参数。同时返回所有相关盲因子以及签名KEY。
    id sign_keys = [NSMutableDictionary dictionary];
    id input_blinding_factors = [NSMutableArray array];
    id inputs = [VCStealthTransferHelper genBlindInputs:blind_balance_array
                                output_blinding_factors:input_blinding_factors
                                              sign_keys:sign_keys];
    
    //  所有盲因子求和
    id blinding_factor = [VCStealthTransferHelper blindSum:input_blinding_factors];
    
    //  构造OP
    NSInteger precision = [[asset objectForKey:@"precision"] integerValue];
    id n_transfer_amount = [n_total decimalNumberBySubtracting:n_fee];
    id transfer_amount = [NSString stringWithFormat:@"%@", [n_transfer_amount decimalNumberByMultiplyingByPowerOf10:precision]];
    id fee_amount = [NSString stringWithFormat:@"%@", [n_fee decimalNumberByMultiplyingByPowerOf10:precision]];
    
    id op = @{
        @"fee":@{@"asset_id":asset[@"id"], @"amount":@([fee_amount unsignedLongLongValue])},
        @"amount":@{@"asset_id":asset[@"id"], @"amount":@([transfer_amount unsignedLongLongValue])},
        @"to":_to_account[@"id"],
        @"blinding_factor":blinding_factor,
        @"inputs":inputs
    };
    
    [self showBlockViewWithTitle:NSLocalizedString(@"kTipsBeRequesting", @"请求中...")];
    
    //  REMARK：该操作不涉及账号，不需要处理提案的情况。仅n个私钥签名即可。
    [[[[BitsharesClientManager sharedBitsharesClientManager] transferFromBlind:op signPriKeyHash:sign_keys] then:^id(id data) {
        NSLog(@"%@", data);
        [self hideBlockView];
        [OrgUtils makeToast:@"转出成功。"];
        //  删除已提取的收据。
        AppCacheManager* pAppCahce = [AppCacheManager sharedAppCacheManager];
        for (id blind_balance in blind_balance_array) {
            [pAppCahce removeBlindBalance:blind_balance];
        }
        [pAppCahce saveStealthReceiptToFile];
        return nil;
    }] catch:^id(id error) {
        [self hideBlockView];
        [OrgUtils showGrapheneError:error];
        return nil;
    }];
}

@end