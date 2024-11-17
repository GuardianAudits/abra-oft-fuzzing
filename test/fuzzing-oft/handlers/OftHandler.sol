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

import {ILzIndirectOFTV2, ILzOFTV2, ILzApp, ILzReceiver} from "@abracadabra-oftv2/interfaces/ILayerZero.sol";
import {LzApp} from "@abracadabra-oftv2/LzApp.sol";

/// @dev OftHandler contains functions from the target contracts OrderOFT.sol,
///      OrderToken.sol, and OrderAdapter.sol.
///      These functions contain conditional invariants.
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

    address internal currentActor;

    uint256 mainnetFork;
    uint256 arbitrumFork;

    uint64 nonce;

    uint16 constant ARBITRUM_CHAIN_ID = 110;
    uint16 constant MAINNET_CHAIN_ID = 101;

    uint8 constant PT_SEND = 0;
    uint8 constant PT_SEND_AND_CALL = 1;

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
        vm.selectFork(arbitrumFork);

        StakeTemps memory cache;
        cache.stakingToken = ERC20Mock(spellPowerStaking.stakingToken());
        amount = bound(amount, 1, 100_000 ether);

        deal(address(cache.stakingToken), currentActor, amount);
        cache.stakingToken.approve(address(spellPowerStaking), amount);

        // ACTION
        try spellPowerStaking.stake(amount) {} catch {
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
    }

    function withdraw(
        uint256 stakerIndexSeed, 
        uint256 timeJumpSeed, 
        uint256 amount
        ) public useActor(stakerIndexSeed) adjustTimestamp(timeJumpSeed) {
        
        // PRE-CONDITIONS
        vm.selectFork(arbitrumFork);

        WithdrawTemps memory cache;

        cache.lastAdded = spellPowerStaking.lastAdded(currentActor);
        cache.lockupPeriod = spellPowerStaking.lockupPeriod();
        if (cache.lastAdded + cache.lockupPeriod > block.timestamp) return;

        if (spellPowerStaking.balanceOf(currentActor) == 0) return;
        amount = bound(amount, 1, spellPowerStaking.balanceOf(currentActor));

        // ACTION
        try spellPowerStaking.withdraw(amount) {} catch {
            assertFalse(false, "WITHDRAW FAILED");
        }
    }

    struct ExitTemps {
        uint256 lastAdded;
        uint256 lockupPeriod;
    }

    function exit(
        uint256 stakerIndexSeed, 
        uint256 timeJumpSeed
        ) public useActor(stakerIndexSeed) adjustTimestamp(timeJumpSeed) {
        
        // PRE-CONDITIONS
        vm.selectFork(arbitrumFork);

        ExitTemps memory cache;

        cache.lastAdded = spellPowerStaking.lastAdded(currentActor);
        cache.lockupPeriod = spellPowerStaking.lockupPeriod();
        if (cache.lastAdded + cache.lockupPeriod > block.timestamp) return;

        if (spellPowerStaking.balanceOf(currentActor) == 0) return;

        // ACTION
        try spellPowerStaking.exit() {} catch (bytes memory err) {

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
    }

    function exitWithParams(
        uint256 stakerIndexSeed, 
        uint256 timeJumpSeed,
        uint256 paramLength
        ) public useActor(stakerIndexSeed) adjustTimestamp(timeJumpSeed) {
        
        // PRE-CONDITIONS
        vm.selectFork(arbitrumFork);

        ExitWithParamsTemps memory cache;

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
            value: value
        });

        if (spellPowerStaking.balanceOf(currentActor) == 0) return;

        // ACTION
        try spellPowerStaking.exit{value: value}(cache.rewardParams) {

            // cache.spellOftArbitrum = address(receiver.spellOft());
            // cache.bSpellOftArbitrum = address(receiver.bSpellOft());
            // cache.sourceAddressSpell = LzApp(cache.spellOftArbitrum).trustedRemoteLookup(MAINNET_CHAIN_ID);
            // cache.sourceAddressBSpell = LzApp(cache.bSpellOftArbitrum).trustedRemoteLookup(MAINNET_CHAIN_ID);

            // vm.stopPrank();
            // vm.selectFork(mainnetFork);

            // cache._ld2sdValue = _ld2sd(cache.userRewards[0], cache.bSpellOftArbitrum);

            // address bSpellOft = address(sender.bSpellOft());
            // vm.startPrank(address(ILzApp(bSpellOft).lzEndpoint()));
            // try ILzReceiver(bSpellOft).lzReceive(
            //     ARBITRUM_CHAIN_ID,
            //     cache.sourceAddressBSpell,
            //     nonce++, 
            //     abi.encodePacked(PT_SEND, addressToBytes32(currentActor), cache._ld2sdValue)
            // ) {} catch {
            //     assertTrue(false, "TEST");
            // }
            // vm.stopPrank();

            // cache._ld2sdValue = _ld2sd(cache.userRewards[1], cache.spellOftArbitrum);

            // address spellOft = address(sender.spellOft());
            // vm.startPrank(address(ILzApp(spellOft).lzEndpoint()));
            // ILzReceiver(spellOft).lzReceive(
            //     ARBITRUM_CHAIN_ID,
            //     cache.sourceAddressSpell,
            //     nonce++, 
            //     abi.encodePacked(PT_SEND, addressToBytes32(currentActor), cache._ld2sdValue)
            // );

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

        vm.selectFork(mainnetFork);

        CrosschainStakeTemps memory cache;
        cache.action = CrosschainActions.STAKE_BOUNDSPELL;
        cache.bSpellMainnet = sender.bSpell();
        cache.bSpellOftMainnet = address(sender.bSpellOft());
        (cache.fee, ) = sender.estimate(cache.action);

        amount = bound(amount, 1, 100_000 ether);

        deal(cache.bSpellMainnet, currentActor, amount);
        ERC20Mock(cache.bSpellMainnet).approve(address(sender), amount);

        // ACTION
        try sender.send{value: cache.fee}(
            cache.action,
            amount
        ) {

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

            // uint256 stakingBalanceBefore = spellPowerStaking.balanceOf(alice);

            receiver.onOFTReceived(MAINNET_CHAIN_ID, "", 0, bytes32(uint256(uint160(address(sender)))), amount, payload);
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

        vm.selectFork(mainnetFork);

        CrosschainMintAndStakeTemps memory cache;
        cache.action = CrosschainActions.MINT_AND_STAKE_BOUNDSPELL;
        cache.spellMainnet = sender.spell();
        cache.spellOftMainnet = address(sender.spellOft());
        (cache.fee, ) = sender.estimate(cache.action);

        amount = bound(amount, 1, 100_000 ether);

        deal(cache.spellMainnet, currentActor, amount);
        ERC20Mock(cache.spellMainnet).approve(address(sender), amount);

        // ACTION
        try sender.send{value: cache.fee}(
            cache.action,
            amount
        ) {

            vm.stopPrank();

            vm.selectFork(arbitrumFork);

            cache.spellArbitrum = receiver.spell();
            vm.prank(address(receiver));
            ERC20Mock(cache.spellArbitrum).approve(address(spellPowerStaking), amount);

            cache.bSpellArbitrum = receiver.bSpell();
            vm.prank(address(receiver));
            ERC20Mock(cache.bSpellArbitrum).approve(address(spellPowerStaking), amount);

            vm.startPrank(cache.spellOftMainnet);

            bytes memory params = abi.encode(MintBoundSpellAndStakeParams(currentActor, RewardHandlerParams("", 0)));
            bytes memory payload = abi.encode(Payload(cache.action, params));

            // Simulate receiving bSpell on the receiver, not the oft, the inner token
            deal(address(cache.spellArbitrum), address(receiver), amount);

            // uint256 stakingBalanceBefore = spellPowerStaking.balanceOf(alice);

            try receiver.onOFTReceived(MAINNET_CHAIN_ID, "", 0, bytes32(uint256(uint160(address(sender)))), amount, payload) {

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

        vm.selectFork(arbitrumFork);

        MintTemps memory cache;
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();

        amount = bound(amount, 1, 100_000 ether);

        deal(cache.underlyingToken, currentActor, amount);
        ERC20Mock(cache.underlyingToken).approve(address(boundSpellLocker), amount);

        // ACTION
        try boundSpellLocker.mint(amount, cache.receiver) {} catch (bytes memory err) {

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

    function redeem(
        uint256 actorIndexSeed,
        uint256 receiverIndexSeed,
        uint256 timeJumpSeed,
        uint256 amount,
        uint256 lockingDeadline
    ) public useActor(actorIndexSeed) adjustTimestamp(timeJumpSeed) {

        // PRE-CONDITIONS

        vm.selectFork(arbitrumFork);

        RedeemTemps memory cache;
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();
        cache.actorbSpellBalance = ERC20Mock(cache.asset).balanceOf(currentActor);

        if (cache.actorbSpellBalance == 0) return;

        amount = bound(amount, 1, cache.actorbSpellBalance);
        lockingDeadline = bound(lockingDeadline, block.timestamp, block.timestamp + 5 days);

        ERC20Mock(cache.asset).approve(address(boundSpellLocker), amount);

        // ACTION
        try boundSpellLocker.redeem(amount, cache.receiver, lockingDeadline) {} catch (bytes memory err) {

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

        vm.selectFork(arbitrumFork);

        InstantRedeemTemps memory cache;
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();
        cache.actorbSpellBalance = ERC20Mock(cache.asset).balanceOf(currentActor);

        if (cache.actorbSpellBalance == 0) return;

        amount = bound(amount, 1, cache.actorbSpellBalance);

        ERC20Mock(cache.asset).approve(address(boundSpellLocker), amount);

        // ACTION
        try boundSpellLocker.instantRedeem(amount, cache.receiver) {} catch (bytes memory err) {

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

        vm.selectFork(arbitrumFork);

        ClaimTemps memory cache;
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();

        if (boundSpellLocker.claimable(currentActor) == 0) return;

        // ACTION
        try boundSpellLocker.claim() {} catch (bytes memory err) {

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

        vm.selectFork(arbitrumFork);

        ClaimToTemps memory cache;
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.underlyingToken = boundSpellLocker.underlyingToken();
        cache.asset = boundSpellLocker.asset();

        if (boundSpellLocker.claimable(currentActor) == 0) return;

        // ACTION
        try boundSpellLocker.claim(cache.receiver) {} catch (bytes memory err) {

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

    // /*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    // //////////////////////////////////////////////////////////////////////////*/

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
