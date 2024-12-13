// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {BoundSpellActionSender, BoundSpellActionReceiver, CrosschainActions, MintBoundSpellAndStakeParams, StakeBoundSpellParams, Payload} from "src/periphery/BoundSpellCrosschainActions.sol";
import {SpellPowerStaking} from "src/staking/SpellPowerStaking.sol";
import {TokenAmount, RewardHandlerParams} from "src/staking/MultiRewards.sol";
import {TokenLocker} from "src/periphery/TokenLocker.sol";
import {MultiRewardsClaimingHandler, MultiRewardsClaimingHandlerParam} from "src/periphery/MultiRewardsClaimingHandler.sol";

import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {ERC20} from "@solady/tokens/ERC20.sol";
import {TimestampStore} from "../stores/TimestampStore.sol";

import {ILzIndirectOFTV2, ILzOFTV2, ILzApp, ILzReceiver, ILzBaseOFTV2} from "@abracadabra-oftv2/interfaces/ILayerZero.sol";
import {LzApp} from "@abracadabra-oftv2/LzApp.sol";

contract OftHandler is Test {
    
    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    BoundSpellActionSender sender;
    BoundSpellActionReceiver receiver;
    SpellPowerStaking spellPowerStaking;
    TokenLocker boundSpellLocker;
    MultiRewardsClaimingHandler rewardHandler;

    TimestampStore timestampStore;

    /*//////////////////////////////////////////////////////////////////////////
                                   HANDLER VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    address user0 = vm.addr(uint256(keccak256("User0")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));

    address feeCollector = 0x60C801e2dfd6298E6080214b3d680C8f8d698F48;

    address internal currentActor;
    address internal storageCopySpell;
    address internal storageCopyBSpell;

    uint256 mainnetFork;
    uint256 arbitrumFork;

    uint64 nonce;

    uint16 constant ARBITRUM_CHAIN_ID = 110;
    uint16 constant MAINNET_CHAIN_ID = 101;

    uint8 constant PT_SEND = 0;
    uint8 constant PT_SEND_AND_CALL = 1;

    uint256 public constant BIPS = 10000;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address[6] users;

    struct BeforeAfter {
        uint256 test;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier adjustTimestamp(uint256 timeJumpSeed) {
        uint256 timeJump = _bound(timeJumpSeed, 1 days, 10 days);
        timestampStore.increaseCurrentTimestamp(timeJump);
        vm.warp(timestampStore.currentTimestamp());
        _;
    }

    /// @dev Selects the actor which is to be the msg.sender.
    modifier useActor(uint256 actorIndexSeed) {
        currentActor = users[bound(actorIndexSeed, 0, users.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event Debug(string a);
    event DebugUint(string a, uint256 b);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(
        BoundSpellActionSender _sender,
        BoundSpellActionReceiver _receiver,
        SpellPowerStaking _spellPowerStaking,
        TokenLocker _boundSpellLocker,
        MultiRewardsClaimingHandler _rewardHandler,
        uint256 _mainnetFork,
        uint256 _arbitrumFork,
        TimestampStore _timestampStore
    ) {
        sender = _sender;
        receiver = _receiver;
        spellPowerStaking = _spellPowerStaking;
        boundSpellLocker = _boundSpellLocker;
        rewardHandler = _rewardHandler;

        timestampStore = _timestampStore;

        mainnetFork = _mainnetFork;
        arbitrumFork = _arbitrumFork;

        users[0] = user0;
        users[1] = user1;
        users[2] = user2;
        users[3] = user3;
        users[4] = user4;
        users[5] = user5;
    }

    /*//////////////////////////////////////////////////////////////////////////
                        TARGET FUNCTIONS SPELL POWER STAKING
    //////////////////////////////////////////////////////////////////////////*/

    // forgefmt: disable-start
    /**************************************************************************************************************************************/
    /*** Invariant Tests for function approve                                                                                           ***/
    /***************************************************************************************************************************************

        * OT-02: Allowance Matches Approved Amount

    /**************************************************************************************************************************************/
    /*** Assertions that must be true when a user calls approve                                                                         ***/
    /**************************************************************************************************************************************/
    // forgefmt: disable-end

    struct StakeTemps {
        ERC20Mock stakingToken;
    }

    function stake(
        uint256 stakerIndexSeed, 
        uint256 timeJumpSeed, 
        uint256 amount
        ) public useActor(stakerIndexSeed) adjustTimestamp(timeJumpSeed) {
        
        // PRE-CONDITIONS
        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        StakeTemps memory cache;
        cache.stakingToken = ERC20Mock(spellPowerStaking.stakingToken());
        amount = bound(amount, 1, 100_000 ether);

        deal(address(cache.stakingToken), currentActor, amount);
        cache.stakingToken.approve(address(spellPowerStaking), amount);

        uint256 stakingBalanceBefore = spellPowerStaking.balanceOf(currentActor);
        uint256 spellPowerStakingBalanceBefore = cache.stakingToken.balanceOf(address(spellPowerStaking));

        // ACTION
        try spellPowerStaking.stake(amount) {

            // POST-CONDITIONS

            uint256 stakingBalanceAfter = spellPowerStaking.balanceOf(currentActor);
            uint256 spellPowerStakingBalanceAfter = cache.stakingToken.balanceOf(address(spellPowerStaking));

            assertEq(
                stakingBalanceAfter,
                stakingBalanceBefore + amount,
                "ABRA-03: User staking balance on arbitrum should increase by amount"
            );

            assertNotEq(
                spellPowerStaking.lastAdded(currentActor),
                0,
                "ABRA-04: User last added time should not be 0"
            );

            assertEq(
                spellPowerStakingBalanceAfter,
                spellPowerStakingBalanceBefore + amount,
                "ABRA-05: bSpell balance of spellPowerStaking should increase by amount"
            );
        } catch {
            assertFalse(false, "STAKE FAILED");
        }
    }

    // forgefmt: disable-start
    /**************************************************************************************************************************************/
    /*** Invariant Tests for functions transfer and transferFrom                                                                        ***/
    /***************************************************************************************************************************************

        * OT-03: ERC20 Balance Changes By Amount For Sender And Receiver Upon Transfer
        * OT-04: ERC20 Balance Remains The Same Upon Self-Transfer
        * OT-05: ERC20 Total Supply Remains The Same Upon Transfer

    /**************************************************************************************************************************************/
    /*** Assertions that must be true when a user calls transfer or transferFrom                                                        ***/
    /**************************************************************************************************************************************/
    // forgefmt: disable-end

    struct WithdrawTemps {
        uint256 lastAdded;
        uint256 lockupPeriod;
        ERC20Mock stakingToken;
    }

    function withdraw(
        uint256 stakerIndexSeed, 
        uint256 timeJumpSeed, 
        uint256 amount
        ) public useActor(stakerIndexSeed) adjustTimestamp(timeJumpSeed) {
        
        // PRE-CONDITIONS
        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        WithdrawTemps memory cache;
        cache.stakingToken = ERC20Mock(spellPowerStaking.stakingToken());
        cache.lastAdded = spellPowerStaking.lastAdded(currentActor);
        cache.lockupPeriod = spellPowerStaking.lockupPeriod();
        if (cache.lastAdded + cache.lockupPeriod > block.timestamp) return;

        if (spellPowerStaking.balanceOf(currentActor) == 0) return;
        amount = bound(amount, 1, spellPowerStaking.balanceOf(currentActor));

        uint256 stakingBalanceBefore = spellPowerStaking.balanceOf(currentActor);
        uint256 stakingTokenBalanceBefore = cache.stakingToken.balanceOf(address(spellPowerStaking));
        uint256 stakingTokenBalanceBeforeUser = cache.stakingToken.balanceOf(address(currentActor));

        // ACTION
        try spellPowerStaking.withdraw(amount) {

            uint256 stakingBalanceAfter = spellPowerStaking.balanceOf(currentActor);
            uint256 stakingTokenBalanceAfter = cache.stakingToken.balanceOf(address(spellPowerStaking));
            uint256 stakingTokenBalanceAfterUser = cache.stakingToken.balanceOf(address(currentActor));

            assertEq(
                stakingBalanceAfter,
                stakingBalanceBefore - amount,
                "ABRA-03: User staking balance on arbitrum should increase by amount"
            );

            assertEq(
                stakingTokenBalanceAfter,
                stakingTokenBalanceBefore - amount,
                "ABRA-06: bSpell balance of spellPowerStaking should decrease by amount"
            );

            assertEq(
                stakingTokenBalanceAfterUser,
                stakingTokenBalanceBeforeUser + amount,
                "ABRA-07: bSpell balance of user should increase by amount"
            );
        } catch {
            assertFalse(false, "WITHDRAW FAILED");
        }
    }

    struct ExitTemps {
        uint256 lastAdded;
        uint256 lockupPeriod;
        uint256 amount;
        uint256 stakingTokenEarned;
        address[] rewardTokens;
        uint256[] earned;
        uint256[] rewardTokenBalanceBefore;
        ERC20Mock stakingToken;
    }

    function exit(
        uint256 stakerIndexSeed, 
        uint256 timeJumpSeed
        ) public useActor(stakerIndexSeed) adjustTimestamp(timeJumpSeed) {
        
        // PRE-CONDITIONS
        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        ExitTemps memory cache;
        cache.stakingToken = ERC20Mock(spellPowerStaking.stakingToken());
        cache.lastAdded = spellPowerStaking.lastAdded(currentActor);
        cache.lockupPeriod = spellPowerStaking.lockupPeriod();
        if (cache.lastAdded + cache.lockupPeriod > block.timestamp) return;

        if (spellPowerStaking.balanceOf(currentActor) == 0) return;
        cache.amount = spellPowerStaking.balanceOf(currentActor);

        uint256 stakingBalanceBefore = spellPowerStaking.balanceOf(currentActor);
        uint256 stakingTokenBalanceBefore = cache.stakingToken.balanceOf(address(spellPowerStaking));
        uint256 stakingTokenBalanceBeforeUser = cache.stakingToken.balanceOf(address(currentActor));

        cache.rewardTokens = new address[](spellPowerStaking.getRewardTokenLength());
        cache.earned = new uint256[](cache.rewardTokens.length);
        cache.rewardTokenBalanceBefore = new uint256[](cache.rewardTokens.length);
        for (uint i; i < cache.rewardTokens.length; i++) {
            cache.rewardTokens[i] = spellPowerStaking.rewardTokens(i);
            cache.earned[i] = spellPowerStaking.earned(currentActor, cache.rewardTokens[i]);
            cache.rewardTokenBalanceBefore[i] = ERC20(cache.rewardTokens[i]).balanceOf(currentActor);

            if (address(cache.stakingToken) == cache.rewardTokens[i]) {
                cache.stakingTokenEarned = cache.earned[i];
            }
        }

        // ACTION
        try spellPowerStaking.exit() {

            // POST-CONDITIONS
            uint256 stakingBalanceAfter = spellPowerStaking.balanceOf(currentActor);
            uint256 stakingTokenBalanceAfter = cache.stakingToken.balanceOf(address(spellPowerStaking));
            uint256 stakingTokenBalanceAfterUser = cache.stakingToken.balanceOf(address(currentActor));

            assertEq(
                stakingBalanceAfter,
                stakingBalanceBefore - cache.amount,
                "ABRA-03: User staking balance on arbitrum should increase by amount"
            );

            assertEq(
                stakingTokenBalanceAfter,
                stakingTokenBalanceBefore - cache.amount - cache.stakingTokenEarned,
                "ABRA-06: bSpell balance of spellPowerStaking should decrease by amount and earned staking tokens"
            );

            assertEq(
                stakingTokenBalanceAfterUser,
                stakingTokenBalanceBeforeUser + cache.amount + cache.stakingTokenEarned,
                "ABRA-07: bSpell balance of user should increase by amount and earned staking tokens"
            );

            for (uint rewardToken; rewardToken < cache.rewardTokens.length; rewardToken++) {

                if (address(cache.stakingToken) == cache.rewardTokens[rewardToken]) {
                    assertEq(
                        ERC20(cache.rewardTokens[rewardToken]).balanceOf(currentActor),
                        cache.rewardTokenBalanceBefore[rewardToken] + cache.earned[rewardToken] + cache.amount,
                        "ABRA-08: User should have received earned rewardToken"
                    );
                } else {
                    assertEq(
                        ERC20(cache.rewardTokens[rewardToken]).balanceOf(currentActor),
                        cache.rewardTokenBalanceBefore[rewardToken] + cache.earned[rewardToken],
                        "ABRA-08: User should have received earned rewardToken"
                    );
                }
            }

        } catch (bytes memory err) {

            // @audit Fails because MultiRewards doesn't have enough rewardToken

            bytes4[1] memory errors =
                [SafeTransferLib.TransferFailed.selector];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assertTrue(expected, "EXIT FAILED");
        }
    }

    struct ExitWithParamsTemps {
        uint256 lastAdded;
        uint256 lockupPeriod;
        MultiRewardsClaimingHandlerParam[] params;
        uint256[] userRewards;
        RewardHandlerParams rewardParams;
        address spellOftArbitrum;
        address bSpellOftArbitrum;
        bytes sourceAddressSpell;
        bytes sourceAddressBSpell;
        uint64 _ld2sdValue;
        uint256 amount;
        uint256 stakingTokenEarned;
        address[] rewardTokens;
        uint256[] earned;
        uint256[] rewardTokenBalanceBefore;
        ERC20Mock stakingToken;
    }

    function exitWithParams(
        uint256 stakerIndexSeed, 
        uint256 timeJumpSeed,
        uint256 paramLength
        ) public useActor(stakerIndexSeed) adjustTimestamp(timeJumpSeed) {
        
        // PRE-CONDITIONS
        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        ExitWithParamsTemps memory cache;
        cache.stakingToken = ERC20Mock(spellPowerStaking.stakingToken());
        cache.lastAdded = spellPowerStaking.lastAdded(currentActor);
        cache.lockupPeriod = spellPowerStaking.lockupPeriod();
        if (cache.lastAdded + cache.lockupPeriod > block.timestamp) return;

        paramLength = spellPowerStaking.getRewardTokenLength();
        cache.params = new MultiRewardsClaimingHandlerParam[](paramLength);

        cache.userRewards = new uint256[](2);

        uint value;
        uint rewardIndex;
        for (uint i = 0; i < paramLength; i++) {
            address rewardToken_ = spellPowerStaking.rewardTokens(i);

            MultiRewardsClaimingHandlerParam memory tempParams;
            uint fee;

            if (rewardToken_ == spellPowerStaking.rewardTokens(0) || rewardToken_ == spellPowerStaking.rewardTokens(2)) {
                tempParams = MultiRewardsClaimingHandlerParam({
                    fee: 0,
                    gas: 0,
                    dstChainId: 0
                });
            } else {
                (fee, , tempParams) = rewardHandler.estimateBridgingFee(
                    rewardToken_,
                    MAINNET_CHAIN_ID
                );

                cache.userRewards[rewardIndex] = spellPowerStaking.earned(currentActor, rewardToken_);
                rewardIndex++;
            }
            cache.params[i] = tempParams;
            value += fee;
        }

        cache.rewardParams = RewardHandlerParams({
            data: abi.encode(cache.params),
            refundTo: currentActor,
            value: value
        });

        if (spellPowerStaking.balanceOf(currentActor) == 0) return;
        cache.amount = spellPowerStaking.balanceOf(currentActor);

        uint256 stakingBalanceBefore = spellPowerStaking.balanceOf(currentActor);
        uint256 stakingTokenBalanceBefore = cache.stakingToken.balanceOf(address(spellPowerStaking));
        uint256 stakingTokenBalanceBeforeUser = cache.stakingToken.balanceOf(address(currentActor));

        cache.rewardTokens = new address[](spellPowerStaking.getRewardTokenLength());
        cache.earned = new uint256[](cache.rewardTokens.length);
        cache.rewardTokenBalanceBefore = new uint256[](cache.rewardTokens.length);
        for (uint i; i < cache.rewardTokens.length; i++) {
            cache.rewardTokens[i] = spellPowerStaking.rewardTokens(i);
            cache.earned[i] = spellPowerStaking.earned(currentActor, cache.rewardTokens[i]);

            if (cache.rewardTokens[i] == ILzBaseOFTV2(address(receiver.bSpellOft())).innerToken()) {
                cache.rewardTokenBalanceBefore[i] = ERC20(cache.rewardTokens[i]).balanceOf(address(receiver.bSpellOft()));
            } else if (cache.rewardTokens[i] == ILzBaseOFTV2(address(receiver.spellOft())).innerToken()) {
                cache.rewardTokenBalanceBefore[i] = ERC20(cache.rewardTokens[i]).balanceOf(address(receiver.spellOft()));
            } else {
                cache.rewardTokenBalanceBefore[i] = ERC20(cache.rewardTokens[i]).balanceOf(address(currentActor));
            }

            if (address(cache.stakingToken) == cache.rewardTokens[i]) {
                cache.stakingTokenEarned = cache.earned[i];
            }
        }

        // ACTION
        try spellPowerStaking.exit{value: value}(currentActor, cache.rewardParams) {

            // POST-CONDITIONS
            uint256 stakingBalanceAfter = spellPowerStaking.balanceOf(currentActor);
            uint256 stakingTokenBalanceAfter = cache.stakingToken.balanceOf(address(spellPowerStaking));
            uint256 stakingTokenBalanceAfterUser = cache.stakingToken.balanceOf(address(currentActor));

            assertEq(
                stakingBalanceAfter,
                stakingBalanceBefore - cache.amount,
                "ABRA-03: User staking balance on arbitrum should increase by amount"
            );

            assertEq(
                stakingTokenBalanceAfter,
                stakingTokenBalanceBefore - cache.amount - cache.stakingTokenEarned,
                "ABRA-06: bSpell balance of spellPowerStaking should decrease by amount and earned staking tokens"
            );

            assertEq(
                stakingTokenBalanceAfterUser,
                stakingTokenBalanceBeforeUser + cache.amount,
                "ABRA-07: bSpell balance of user should increase by amount"
            );

            for (uint rewardToken; rewardToken < cache.rewardTokens.length; rewardToken++) {
                if (cache.rewardTokens[rewardToken] == ILzBaseOFTV2(address(receiver.bSpellOft())).innerToken()) {
                    assertEq(
                        ERC20(cache.rewardTokens[rewardToken]).balanceOf(address(receiver.bSpellOft())),
                        cache.rewardTokenBalanceBefore[rewardToken] + uint256(_ld2sd(cache.earned[rewardToken], address(receiver.bSpellOft()))) * 10e9,
                        "ABRA-08: User should have received earned rewardToken"
                    );     
                } else if (cache.rewardTokens[rewardToken] == ILzBaseOFTV2(address(receiver.spellOft())).innerToken()) {
                    assertEq(
                        ERC20(cache.rewardTokens[rewardToken]).balanceOf(address(receiver.spellOft())),
                        0,
                        "ABRA-08: User should have received earned rewardToken"
                    ); 
                } else {
                    assertEq(
                        ERC20(cache.rewardTokens[rewardToken]).balanceOf(address(currentActor)),
                        cache.rewardTokenBalanceBefore[rewardToken] + cache.earned[rewardToken],
                        "ABRA-08: User should have received earned rewardToken"
                    );            
                }
            }
        } catch (bytes memory err) {

            // @audit Fails because MultiRewards doesn't have enough rewardToken

            bytes4[1] memory errors =
                [SafeTransferLib.TransferFailed.selector];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assertTrue(expected, "EXIT WITH PARAMS FAILED");
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                        TARGET FUNCTIONS BOUND SPELL CC ACTIONS
    //////////////////////////////////////////////////////////////////////////*/

    struct CrosschainStakeTemps {
        CrosschainActions action;
        uint256 fee;
        address bSpellMainnet;
        address bSpellOftMainnet;
        address bSpellArbitrum;
    }

    function crosschainStake(
        uint256 actorIndexSeed, 
        uint256 timeJumpSeed,
        uint256 amount
    ) public useActor(actorIndexSeed) adjustTimestamp(timeJumpSeed) {

        // PRE-CONDITIONS

        if (vm.activeFork() != mainnetFork) {
            vm.selectFork(mainnetFork);
        }

        CrosschainStakeTemps memory cache;
        cache.action = CrosschainActions.STAKE_BOUNDSPELL;
        cache.bSpellMainnet = sender.bSpell();
        cache.bSpellOftMainnet = address(sender.bSpellOft());
        (cache.fee, ) = sender.estimate(cache.action);

        amount = bound(amount, 1, 100_000 ether);

        deal(cache.bSpellMainnet, currentActor, amount);
        ERC20Mock(cache.bSpellMainnet).approve(address(sender), amount);

        uint256 bSpellBalanceBefore = ERC20(cache.bSpellMainnet).balanceOf(currentActor);

        // ACTION
        try sender.send{value: cache.fee}(
            cache.action,
            amount
        ) {

            // POST-CONDITIONS (SOURCE CHAIN)

            uint256 bSpellBalanceAfter= ERC20(cache.bSpellMainnet).balanceOf(currentActor);

            assertEq(
                bSpellBalanceAfter,
                bSpellBalanceBefore - amount,
                "ABRA-09: Mainnet bSpell user balance should decrease by amount"
            );

            vm.stopPrank();

            vm.selectFork(arbitrumFork);

            cache.bSpellArbitrum = receiver.bSpell();
            vm.prank(address(receiver));
            ERC20Mock(cache.bSpellArbitrum).approve(address(spellPowerStaking), amount);

            vm.startPrank(cache.bSpellOftMainnet);

            bytes memory params = abi.encode(StakeBoundSpellParams(currentActor));
            bytes memory payload = abi.encode(Payload(cache.action, params));

            // Simulate receiving bSpell on the receiver, not the oft, the inner token
            deal(address(cache.bSpellArbitrum), address(receiver), amount);

            uint256 stakingBalanceBefore = spellPowerStaking.balanceOf(currentActor);
            uint256 spellPowerStakingBalanceBefore = ERC20(cache.bSpellArbitrum).balanceOf(address(spellPowerStaking));

            receiver.onOFTReceived(MAINNET_CHAIN_ID, "", 0, bytes32(uint256(uint160(address(sender)))), amount, payload);

            // POST-CONDITIONS (DST CHAIN)

            uint256 stakingBalanceAfter = spellPowerStaking.balanceOf(currentActor);
            uint256 spellPowerStakingBalanceAfter = ERC20(cache.bSpellArbitrum).balanceOf(address(spellPowerStaking));

            assertEq(
                stakingBalanceAfter,
                stakingBalanceBefore + amount,
                "ABRA-03: User staking balance on arbitrum should increase by amount"
            );

            assertNotEq(
                spellPowerStaking.lastAdded(currentActor),
                0,
                "ABRA-04: User last added time should not be 0"
            );

            assertEq(
                spellPowerStakingBalanceAfter,
                spellPowerStakingBalanceBefore + amount,
                "ABRA-05: bSpell balance of spellPowerStaking should increase by amount"
            );
        } catch {
            assertTrue(false, "CROSSCHAIN STAKE FAILED");
        }
    }

    struct CrosschainMintAndStakeTemps {
        CrosschainActions action;
        uint256 fee;
        address spellMainnet;
        address spellOftMainnet;
        address spellArbitrum;
        address bSpellArbitrum;
    }

    function crosschainMintAndStake(
        uint256 actorIndexSeed, 
        uint256 timeJumpSeed,
        uint256 amount
    ) public useActor(actorIndexSeed) adjustTimestamp(timeJumpSeed) {

        // PRE-CONDITIONS

        if (vm.activeFork() != mainnetFork) {
            vm.selectFork(mainnetFork);
        }

        CrosschainMintAndStakeTemps memory cache;
        cache.action = CrosschainActions.MINT_AND_STAKE_BOUNDSPELL;
        cache.spellMainnet = sender.spell();
        cache.spellOftMainnet = address(sender.spellOft());
        (cache.fee, ) = sender.estimate(cache.action);

        amount = bound(amount, 1, 100_000 ether);

        deal(cache.spellMainnet, currentActor, amount);
        ERC20Mock(cache.spellMainnet).approve(address(sender), amount);

        uint256 spellBalanceBefore = ERC20(cache.spellMainnet).balanceOf(currentActor);

        // ACTION
        try sender.send{value: cache.fee}(
            cache.action,
            amount
        ) {

            // POST-CONDITIONS (SOURCE CHAIN)

            uint256 spellBalanceAfter= ERC20(cache.spellMainnet).balanceOf(currentActor);

            assertEq(
                spellBalanceAfter,
                spellBalanceBefore - amount,
                "ABRA-09: Mainnet bSpell user balance should decrease by amount"
            );

            vm.stopPrank();

            vm.selectFork(arbitrumFork);

            cache.spellArbitrum = receiver.spell();
            vm.prank(address(receiver));
            ERC20Mock(cache.spellArbitrum).approve(address(spellPowerStaking), amount);

            cache.bSpellArbitrum = receiver.bSpell();
            vm.prank(address(receiver));
            ERC20Mock(cache.bSpellArbitrum).approve(address(spellPowerStaking), amount);

            vm.startPrank(cache.spellOftMainnet);

            bytes memory params = abi.encode(MintBoundSpellAndStakeParams(currentActor));
            bytes memory payload = abi.encode(Payload(cache.action, params));

            // Simulate receiving bSpell on the receiver, not the oft, the inner token
            deal(address(cache.spellArbitrum), address(receiver), amount);

            uint256 stakingBalanceBefore = spellPowerStaking.balanceOf(currentActor);
            uint256 spellPowerStakingBalanceBefore = ERC20(cache.bSpellArbitrum).balanceOf(address(spellPowerStaking));

            try receiver.onOFTReceived(MAINNET_CHAIN_ID, "", 0, bytes32(uint256(uint160(address(sender)))), amount, payload) {

                // POST-CONDITIONS (DST CHAIN)

                uint256 stakingBalanceAfter = spellPowerStaking.balanceOf(currentActor);
                uint256 spellPowerStakingBalanceAfter = ERC20(cache.bSpellArbitrum).balanceOf(address(spellPowerStaking));

                assertEq(
                    stakingBalanceAfter,
                    stakingBalanceBefore + amount,
                    "ABRA-03: User staking balance on arbitrum should increase by amount"
                );

                assertNotEq(
                    spellPowerStaking.lastAdded(currentActor),
                    0,
                    "ABRA-04: User last added time should not be 0"
                );

                assertEq(
                    spellPowerStakingBalanceAfter,
                    spellPowerStakingBalanceBefore + amount,
                    "ABRA-05: bSpell balance of spellPowerStaking should increase by amount"
                );

                invariant_ABRA_02(currentActor);

            } catch (bytes memory err) {

                bytes4[1] memory errors =
                    [ERC20.TotalSupplyOverflow.selector];

                bool expected = false;
                for (uint256 i = 0; i < errors.length; i++) {
                    if (errors[i] == bytes4(err)) {
                        expected = true;
                        break;
                    }
                }
                assertTrue(expected, "ON OFT RECEIVED FAILED");
            }

        } catch {
            assertTrue(false, "CROSSCHAIN MINT AND STAKE FAILED");
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                        TARGET FUNCTIONS TOKEN LOCKER
    //////////////////////////////////////////////////////////////////////////*/

    struct MintTemps {
        address receiver;
        address underlyingToken;
        address asset;
    }

    function mint(
        uint256 actorIndexSeed,
        uint256 receiverIndexSeed,
        uint256 timeJumpSeed,
        uint256 amount
    ) public useActor(actorIndexSeed) adjustTimestamp(timeJumpSeed) {

        // PRE-CONDITIONS

        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        MintTemps memory cache;
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();

        amount = bound(amount, 1, 100_000 ether);

        deal(cache.underlyingToken, currentActor, amount);
        ERC20Mock(cache.underlyingToken).approve(address(boundSpellLocker), amount);

        uint256 underlyingBalanceBefore = ERC20(cache.underlyingToken).balanceOf(currentActor);
        uint256 assetBalanceBefore = ERC20(cache.asset).balanceOf(cache.receiver);
        uint256 totalSupplyBefore = ERC20(cache.asset).totalSupply();

        // ACTION
        try boundSpellLocker.mint(amount, cache.receiver) {

            // POST-CONDITIONS
            uint256 underlyingBalanceAfter = ERC20(cache.underlyingToken).balanceOf(currentActor);
            uint256 assetBalanceAfter = ERC20(cache.asset).balanceOf(cache.receiver);
            uint256 totalSupplyAfter = ERC20(cache.asset).totalSupply();

            assertEq(
                underlyingBalanceAfter,
                underlyingBalanceBefore - amount,
                "ABRA-10: Sender underlying balance should decrease when minting bSpell"
            );

            assertEq(
                assetBalanceAfter,
                assetBalanceBefore + amount,
                "ABRA-11: Receiver asset balance should increase when minting bSpell"
            );

            assertEq(
                totalSupplyAfter,
                totalSupplyBefore + amount,
                "ABRA-12: Total supply of asset should increase when minting bSpell"
            );

            invariant_ABRA_02(currentActor);

        } catch (bytes memory err) {

            bytes4[1] memory errors =
                [ERC20.TotalSupplyOverflow.selector];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assertTrue(expected, "TOKEN LOCKER MINT FAILED");
        }
    }

    struct RedeemTemps {
        address receiver;
        address underlyingToken;
        address asset;
        uint256 actorbSpellBalance;
    }

    struct RedeemBeforeAfter {
        uint256 totalSupply;
        uint256 senderAssetBalance;
        uint256 receiverUnderlyingBalance;
        uint256 lockerAssetBalance;
        uint256 feeCollectorAssetBalance;
        uint256 claimable;
    }

    function redeem(
        uint256 actorIndexSeed,
        uint256 receiverIndexSeed,
        uint256 timeJumpSeed,
        uint256 amount,
        uint256 lockingDeadline
    ) public useActor(actorIndexSeed) adjustTimestamp(timeJumpSeed) {

        // PRE-CONDITIONS

        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        RedeemTemps memory cache;
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();
        cache.actorbSpellBalance = ERC20(cache.asset).balanceOf(currentActor);

        if (cache.actorbSpellBalance == 0) return;

        amount = bound(amount, 1, cache.actorbSpellBalance);
        lockingDeadline = bound(lockingDeadline, block.timestamp, block.timestamp + 5 days);

        ERC20(cache.asset).approve(address(boundSpellLocker), amount);

        RedeemBeforeAfter memory _before;
        _before.totalSupply = ERC20(cache.asset).totalSupply();
        amount = amount > _before.totalSupply ? bound(amount, 1, _before.totalSupply) : amount;

        _before.senderAssetBalance = ERC20(cache.asset).balanceOf(currentActor);
        _before.receiverUnderlyingBalance = ERC20(cache.underlyingToken).balanceOf(cache.receiver);
        _before.lockerAssetBalance = ERC20(cache.asset).balanceOf(address(boundSpellLocker));
        _before.feeCollectorAssetBalance = ERC20(cache.asset).balanceOf(feeCollector);
        _before.claimable = boundSpellLocker.claimable(currentActor);

        // ACTION
        try boundSpellLocker.redeem(amount, cache.receiver, lockingDeadline) {

            // POST-CONDITIONS
            RedeemBeforeAfter memory _after;
            _after.totalSupply = ERC20(cache.asset).totalSupply();
            _after.senderAssetBalance = ERC20(cache.asset).balanceOf(currentActor);
            _after.receiverUnderlyingBalance = ERC20(cache.underlyingToken).balanceOf(cache.receiver);
            _after.lockerAssetBalance = ERC20(cache.asset).balanceOf(address(boundSpellLocker));
            _after.feeCollectorAssetBalance = ERC20(cache.asset).balanceOf(feeCollector);

            assertEq(
                _after.totalSupply,
                _before.totalSupply - amount,
                "ABRA-13: Total supply of asset should decrease when redeeming bSpell"
            );

            // Check that bSpell tokens were transferred from Alice
            assertEq(
                _after.senderAssetBalance, 
                _before.senderAssetBalance - amount, 
                "ABRA-14: Sender bSpell balance should decrease when redeeming"
                );
            assertEq(
                _after.lockerAssetBalance,
                0, 
                "ABRA-15: Locker should not hold any bSpell"
                );

            if (_before.claimable > 0) {
                assertEq(
                    _after.receiverUnderlyingBalance,
                    _before.receiverUnderlyingBalance + _before.claimable,
                    "ABRA-16: Receiver underlying balance should increase by claimable when redeeming bSpell"
                );
            }

            invariant_ABRA_02(currentActor);

        } catch (bytes memory err) {

            // @audit Fails because TokenLocker doesn't have enough spell

            bytes4[1] memory errors =
                [SafeTransferLib.TransferFailed.selector];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assertTrue(expected, "TOKEN LOCKER REDEEM FAILED");
        }
    }

    struct InstantRedeemTemps {
        address receiver;
        address underlyingToken;
        address asset;
        uint256 actorbSpellBalance;
    }

    function instantRedeem(
        uint256 actorIndexSeed,
        uint256 receiverIndexSeed,
        uint256 timeJumpSeed,
        uint256 amount
    ) public useActor(actorIndexSeed) adjustTimestamp(timeJumpSeed) {

        // PRE-CONDITIONS

        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        InstantRedeemTemps memory cache;
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();
        cache.actorbSpellBalance = ERC20Mock(cache.asset).balanceOf(currentActor);

        if (cache.actorbSpellBalance == 0) return;

        amount = bound(amount, 1, cache.actorbSpellBalance);

        ERC20Mock(cache.asset).approve(address(boundSpellLocker), amount);

        RedeemBeforeAfter memory _before;
        _before.totalSupply = ERC20(cache.asset).totalSupply();
        amount = amount > _before.totalSupply ? bound(amount, 1, _before.totalSupply) : amount;

        _before.senderAssetBalance = ERC20(cache.asset).balanceOf(currentActor);
        _before.receiverUnderlyingBalance = ERC20(cache.underlyingToken).balanceOf(cache.receiver);
        _before.lockerAssetBalance = ERC20(cache.asset).balanceOf(address(boundSpellLocker));
        _before.feeCollectorAssetBalance = ERC20(cache.asset).balanceOf(feeCollector);
        _before.claimable = boundSpellLocker.claimable(currentActor);

        // ACTION
        try boundSpellLocker.instantRedeem(amount, cache.receiver) {

            // POST-CONDITIONS
            RedeemBeforeAfter memory _after;
            _after.totalSupply = ERC20(cache.asset).totalSupply();
            _after.senderAssetBalance = ERC20(cache.asset).balanceOf(currentActor);
            _after.receiverUnderlyingBalance = ERC20(cache.underlyingToken).balanceOf(cache.receiver);
            _after.lockerAssetBalance = ERC20(cache.asset).balanceOf(address(boundSpellLocker));
            _after.feeCollectorAssetBalance = ERC20(cache.asset).balanceOf(feeCollector);

            (uint256 immediateBips, uint256 burnBips, ) = boundSpellLocker.instantRedeemParams();
            uint256 immediateAmount = (amount * immediateBips) / BIPS;
            uint256 burnAmount = (amount * burnBips) / BIPS;
            uint256 fees = amount - immediateAmount - burnAmount;

            assertEq(
                _after.totalSupply,
                _before.totalSupply + fees - amount,
                "ABRA-17: Total supply of asset should increase by the difference between fees and amount when instantRedeeming bSpell"
            );
            assertEq(
                _after.senderAssetBalance, 
                _before.senderAssetBalance - amount, 
                "ABRA-14: Sender bSpell balance should decrease when redeeming"
                );
            assertEq(
                _after.lockerAssetBalance,
                0, 
                "ABRA-15: Locker should not hold any bSpell"
                );
            assertEq(
                _after.receiverUnderlyingBalance, 
                _before.receiverUnderlyingBalance + immediateAmount + _before.claimable, 
                "ABRA-18: Receiver underlying balance should increase by immediateAmount and claimable when instantRedeeming bSpell"
                );
            assertEq(
                _after.feeCollectorAssetBalance, 
                _before.feeCollectorAssetBalance + fees, 
                "ABRA-19: FeeCollector balance of bSpell should increase by feeAmount when instantRedeeming"
                );

            invariant_ABRA_02(currentActor);

        } catch (bytes memory err) {

            // @audit Fails because TokenLocker doesn't have enough underlying token (TransferFailed)

            bytes4[2] memory errors =
                [
                    SafeTransferLib.TransferFailed.selector,
                    ERC20.TotalSupplyOverflow.selector
                ];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assertTrue(expected, "TOKEN LOCKER INSTANT REDEEM FAILED");
        }
    }

    struct ClaimTemps {
        address underlyingToken;
        address asset;
    }

    function claim(
        uint256 actorIndexSeed,
        uint256 timeJumpSeed
    ) public useActor(actorIndexSeed) adjustTimestamp(timeJumpSeed) {

        // PRE-CONDITIONS

        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        ClaimTemps memory cache;
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();

        uint256 claimable = boundSpellLocker.claimable(currentActor);
        if (claimable == 0) return;
        uint256 receiverSpellBalanceBefore = ERC20(cache.underlyingToken).balanceOf(currentActor);

        // ACTION
        try boundSpellLocker.claim() {

            // POST-CONDITIONS

            uint256 receiverSpellBalanceAfter = ERC20(cache.underlyingToken).balanceOf(currentActor);

            assertEq(
                receiverSpellBalanceAfter,
                receiverSpellBalanceBefore + claimable,
                "ABRA-20: User should have received claimable tokens when calling claim"
            );
            invariant_ABRA_02(currentActor);

        } catch (bytes memory err) {

            // @audit Fails because TokenLocker doesn't have enough spell

            bytes4[1] memory errors =
                [SafeTransferLib.TransferFailed.selector];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assertTrue(expected, "TOKEN LOCKER CLAIM FAILED");
        }
    }

    struct ClaimToTemps {
        address receiver;
        address underlyingToken;
        address asset;
    }

    function claimTo(
        uint256 actorIndexSeed,
        uint256 receiverIndexSeed,
        uint256 timeJumpSeed
    ) public useActor(actorIndexSeed) adjustTimestamp(timeJumpSeed) {

        // PRE-CONDITIONS

        if (vm.activeFork() != arbitrumFork) {
            vm.selectFork(arbitrumFork);
        }

        ClaimToTemps memory cache;
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();

        uint256 claimable = boundSpellLocker.claimable(currentActor);
        if (claimable == 0) return;
        uint256 receiverSpellBalanceBefore = ERC20(cache.underlyingToken).balanceOf(cache.receiver);

        // ACTION
        try boundSpellLocker.claim(cache.receiver) {

            // POST-CONDITIONS

            uint256 receiverSpellBalanceAfter = ERC20(cache.underlyingToken).balanceOf(cache.receiver);

            assertEq(
                receiverSpellBalanceAfter,
                receiverSpellBalanceBefore + claimable,
                "ABRA-21: Receiver should have received claimable tokens when calling claimTo"
            );

            invariant_ABRA_02(currentActor);

        } catch (bytes memory err) {

            // @audit Fails because TokenLocker doesn't have enough spell

            bytes4[1] memory errors =
                [SafeTransferLib.TransferFailed.selector];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            assertTrue(expected, "TOKEN LOCKER CLAIM TO FAILED");
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     INVARIANTS
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_ABRA_02(address user) internal view {

        TokenLocker.LockedBalance[] memory userLocks = boundSpellLocker.userLocks(user);

        if (userLocks.length == 0) return;

        uint256 latestUnlockTime;
        uint256 latestUnlockIndex;
        for (uint i; i < userLocks.length; i++) {
            if (userLocks[i].unlockTime < latestUnlockTime) {
                continue;
            } else {
                latestUnlockTime = userLocks[i].unlockTime;
                latestUnlockIndex = i;
            }
        }

        assertEq(
            userLocks[latestUnlockIndex].amount,
            userLocks[boundSpellLocker.lastLockIndex(user)].amount,
            "ABRA-02: lastLockIndex for the user always corresponds to the lock with the latest unlock time or there are no locks & the lastLockIndex is nonzero"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function randomAddress(uint256 seed) internal view returns (address) {
        return users[_bound(seed, 0, users.length - 1)];
    }

    function _ld2sd(uint _amount, address oft) internal view virtual returns (uint64) {
        uint amountSD = _amount / ILzIndirectOFTV2(oft).ld2sdRate();
        // if(amountSD > type(uint64).max) return 0;
        return uint64(amountSD);
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function bytesToAddress(bytes32 _byte) internal pure returns (address) {
        return address(uint160(uint256(_byte)));
    }
}
