// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Forge imports
import "forge-std/console.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";

import {TimestampStore} from "../stores/TimestampStore.sol";
import "utils/BaseTest.sol";

import "script/BoundSpellCrosschainActions.s.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

import {ILzOFTV2} from "@abracadabra-oftv2/interfaces/ILayerZero.sol";
import {BoundSpellActionSender, BoundSpellActionReceiver, CrosschainActions, MintBoundSpellAndStakeParams, StakeBoundSpellParams, Payload} from "src/periphery/BoundSpellCrosschainActions.sol";
import {SpellPowerStaking} from "src/staking/SpellPowerStaking.sol";
import {TokenLocker} from "src/periphery/TokenLocker.sol";
import {RewardHandlerParams} from "src/staking/MultiRewards.sol";
import {MultiRewardsClaimingHandler} from "src/periphery/MultiRewardsClaimingHandler.sol";

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {OwnableOperators} from "/mixins/OwnableOperators.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {OftHandler} from "../handlers/OftHandler.sol";

interface ILzBaseOFTV2 is ILzOFTV2 {
    function innerToken() external view returns (address);
}

// forgefmt: disable-start
/**************************************************************************************************************************************/
/*** Invariant Tests                                                                                                                ***/
/***************************************************************************************************************************************

    * OT-01: Total Supply of ORDER should always be 1,000,000,000

/**************************************************************************************************************************************/
/*** OftInvariant configures an OFT system that contains 10 endpoints.                                                             ***/
/*** The system contains the OrderToken, as well as, its OFT adapter.                                                               ***/
/*** The rest of the endpoints are connected to OrderOFT Instances.                                                                 ***/
/*** It also contains global invariants.                                                                                            ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end

contract OftInvariant is StdInvariant, BaseTest {
    using SafeTransferLib for address;
    /*//////////////////////////////////////////////////////////////////////////
                            BASE INVARIANT VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    address user0 = vm.addr(uint256(keccak256("User0")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));
    address[] users = [user0, user1, user2, user3, user4, user5];

    uint256 public constant INIT_MINT = 1_000_000_000 ether;
    uint128 public constant RECEIVE_GAS = 200000;
    uint128 public constant COMPOSE_GAS = 500000;
    uint128 public constant VALUE = 0;

    BoundSpellActionSender sender;
    BoundSpellActionReceiver receiver;
    SpellPowerStaking spellPowerStaking;
    TokenLocker boundSpellLocker;
    BoundSpellCrosschainActionsScript script;
    MultiRewardsClaimingHandler rewardHandler;

    OftHandler oftHandler;

    struct ChainTokens {
        address spell;
        address bSpell;
        ILzOFTV2 spellOft;
        ILzOFTV2 bSpellOft;
    }

    mapping(uint16 => ChainTokens) public chainTokens;
    ERC20Mock public rewardToken;

    uint256 constant ARBITRUM_BLOCK = 274770423;
    uint256 constant MAINNET_BLOCK = 21194005;

    uint16 constant ARBITRUM_CHAIN_ID = 110;
    uint16 constant MAINNET_CHAIN_ID = 101;

    uint256 mainnetFork;
    uint256 arbitrumFork;

    uint256 initialBalance = 100 ether;

    // @dev Reference to the timestamp store, which is needed for simulating the passage of time.
    TimestampStore timestampStore;

    /*//////////////////////////////////////////////////////////////////////////
                                     MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier useCurrentTimestamp() {
        vm.warp(timestampStore.currentTimestamp());
        _;
    }

    event Debug(string a, uint256 b);

    /*//////////////////////////////////////////////////////////////////////////
                                    SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public override {

        _deployCrosschain();
        _deployRewards();
        _deployInvariantInfra();
    }

    // function invariantOrderTokenBalanceSum() external {
    //     assertEq(
    //         token.totalSupply(),
    //         1_000_000_000 ether,
    //         "OT-01: Total Supply of ORDER should always be 1,000,000,000"
    //     );
    // }

    // function invariantDeployment() public {
    //     // Test sender deployment on Mainnet
    //     vm.selectFork(mainnetFork);
    //     assertEq(address(sender.spellOft()), address(chainTokens[MAINNET_CHAIN_ID].spellOft), "spellOft is not correct on Mainnet");
    //     assertEq(address(sender.bSpellOft()), address(chainTokens[MAINNET_CHAIN_ID].bSpellOft), "bSpellOft is not correct on Mainnet");
    //     assertEq(sender.spell(), address(chainTokens[MAINNET_CHAIN_ID].spell), "spell is not correct on Mainnet");
    //     assertEq(sender.bSpell(), address(chainTokens[MAINNET_CHAIN_ID].bSpell), "bSpellV2 is not correct on Mainnet");

    //     // Test receiver deployment on Arbitrum
    //     vm.selectFork(arbitrumFork);
    //     assertEq(address(receiver.spellOft()), address(chainTokens[ARBITRUM_CHAIN_ID].spellOft), "spellOft is not correct on Arbitrum");
    //     assertEq(address(receiver.bSpellOft()), address(chainTokens[ARBITRUM_CHAIN_ID].bSpellOft), "bSpellOft is not correct on Arbitrum");
    //     // assertEq(receiver.spell(), address(chainTokens[ARBITRUM_CHAIN_ID].spell), "spell is not correct on Arbitrum");
    //     assertEq(receiver.bSpell(), address(chainTokens[ARBITRUM_CHAIN_ID].bSpell), "bSpellV2 is not correct on Arbitrum");
    //     assertEq(address(receiver.spellPowerStaking()), address(spellPowerStaking), "spellPowerStaking is not correct on Arbitrum");
    //     assertEq(address(receiver.boundSpellLocker()), address(boundSpellLocker), "boundSpellLocker is not correct on Arbitrum");
    // }

    function invariant_LOCK_01() public useCurrentTimestamp {
        assertTrue(boundSpellLocker.remainingEpochTime() != 0, "LOCK-01: TockenLocker.remainingEpochTime() should never return 0");
    }

    function _deployCrosschain() internal {
        // Create forks
        mainnetFork = fork(ChainId.Mainnet, MAINNET_BLOCK);
        arbitrumFork = fork(ChainId.Arbitrum, ARBITRUM_BLOCK);

        // Start with Mainnet fork for sender setup
        vm.selectFork(mainnetFork);

        timestampStore = new TimestampStore();
        emit Debug("Timestampstore", timestampStore.currentTimestamp());

        vm.makePersistent(address(timestampStore));

        vm.deal(address(this), 1000000 ether);
        vm.deal(user0, 1000 ether);
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);
        vm.deal(user4, 1000 ether);
        vm.deal(user5, 1000 ether);

        super.setUp();
        script = new BoundSpellCrosschainActionsScript();

        script.setTesting(true);

        // Deploy sender on Mainnet
        address deployedContract = script.deploy();
        sender = BoundSpellActionSender(deployedContract);

        assertNotEq(address(sender), address(0), "sender is not deployed");

        // Setup Mainnet-specific contracts
        chainTokens[MAINNET_CHAIN_ID] = ChainTokens({
            spell: ILzBaseOFTV2(toolkit.getAddress("spell.oftv2")).innerToken(),
            bSpell: ILzBaseOFTV2(toolkit.getAddress("bspell.oftv2")).innerToken(),
            spellOft: ILzOFTV2(toolkit.getAddress("spell.oftv2")),
            bSpellOft: ILzOFTV2(toolkit.getAddress("bspell.oftv2"))
        });

        // Switch to Arbitrum fork for receiver setup
        vm.selectFork(arbitrumFork);

        vm.deal(address(this), 1000000 ether);
        vm.deal(user0, 1000 ether);
        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);
        vm.deal(user4, 1000 ether);
        vm.deal(user5, 1000 ether);

        script = new BoundSpellCrosschainActionsScript();

        // Deploy receiver on Arbitrum
        deployedContract = script.deploy();
        receiver = BoundSpellActionReceiver(deployedContract);

        assertNotEq(address(receiver), address(0), "receiver is not deployed");
        assertEq(receiver.remoteSender(), bytes32(uint256(uint160(address(sender)))), "remoteSender is not correct on Arbitrum");

        // Setup Arbitrum-specific contracts
        chainTokens[ARBITRUM_CHAIN_ID] = ChainTokens({
            spell: ILzBaseOFTV2(toolkit.getAddress("spell.oftv2")).innerToken(),
            bSpell: ILzBaseOFTV2(toolkit.getAddress("bspell.oftv2")).innerToken(),
            spellOft: ILzOFTV2(toolkit.getAddress("spell.oftv2")),
            bSpellOft: ILzOFTV2(toolkit.getAddress("bspell.oftv2"))
        });

        spellPowerStaking = SpellPowerStaking(toolkit.getAddress("bSpell.staking"));
        boundSpellLocker = TokenLocker(toolkit.getAddress("bSpell.locker"));

        // set the receiver contract as an operator for spellPowerStaking and boundSpellLocker
        pushPrank(spellPowerStaking.owner());
        OwnableRoles(address(spellPowerStaking)).grantRoles(address(receiver), spellPowerStaking.ROLE_OPERATOR());
        popPrank();

        pushPrank(boundSpellLocker.owner());
        OwnableOperators(address(boundSpellLocker)).setOperator(address(receiver), true);
        popPrank();

        SpellPowerStaking stakingImpl = new SpellPowerStaking(address(chainTokens[ARBITRUM_CHAIN_ID].bSpell), address(0));
        pushPrank(spellPowerStaking.owner());
        spellPowerStaking.upgradeToAndCall(address(stakingImpl), "");
        popPrank();
    }

    function _deployInvariantInfra() internal {

        oftHandler = new OftHandler(
            sender,
            receiver,
            spellPowerStaking,
            boundSpellLocker,
            rewardHandler,
            mainnetFork,
            arbitrumFork,
            timestampStore
        );

        targetContract(address(oftHandler));

        // Selectors to target.
        bytes4[] memory oftSelectors = new bytes4[](11);

        oftSelectors[0] = oftHandler.stake.selector;
        oftSelectors[1] = oftHandler.withdraw.selector;
        oftSelectors[2] = oftHandler.exit.selector;
        oftSelectors[3] = oftHandler.exitWithParams.selector;
        oftSelectors[4] = oftHandler.crosschainStake.selector;
        oftSelectors[5] = oftHandler.crosschainMintAndStake.selector;
        oftSelectors[6] = oftHandler.mint.selector;
        oftSelectors[7] = oftHandler.redeem.selector;
        oftSelectors[8] = oftHandler.instantRedeem.selector;
        oftSelectors[9] = oftHandler.claim.selector;
        oftSelectors[10] = oftHandler.claimTo.selector;

        targetSelector(FuzzSelector({ addr: address(oftHandler), selectors: oftSelectors }));
    }

    function _deployRewards() internal {

        vm.selectFork(arbitrumFork);

        rewardToken = new ERC20Mock("Reward Token", "RWD");
        rewardHandler = new MultiRewardsClaimingHandler(address(this));

        vm.prank(spellPowerStaking.owner());
        spellPowerStaking.setRewardHandler(address(rewardHandler));

        rewardHandler.setOperator(address(spellPowerStaking), true);
        rewardHandler.setRewardInfo(address(rewardToken), ILzOFTV2(address(0))); // ARB is not OFTv2
        rewardHandler.setRewardInfo(chainTokens[ARBITRUM_CHAIN_ID].spell, chainTokens[ARBITRUM_CHAIN_ID].spellOft);
        rewardHandler.setRewardInfo(chainTokens[ARBITRUM_CHAIN_ID].bSpell, chainTokens[ARBITRUM_CHAIN_ID].bSpellOft);

        vm.startPrank(spellPowerStaking.owner());
        spellPowerStaking.addReward(address(rewardToken), 60 days);
        spellPowerStaking.addReward(chainTokens[ARBITRUM_CHAIN_ID].spell, 60 days);
        // spellPowerStaking.addReward(chainTokens[ARBITRUM_CHAIN_ID].bSpell, 60 days);
        vm.stopPrank();

        uint256 amount = 10 ether;

        vm.startPrank(address(receiver));
        deal(address(rewardToken), address(receiver), amount);
        address(rewardToken).safeApprove(address(spellPowerStaking), amount);
        spellPowerStaking.notifyRewardAmount(address(rewardToken), amount);

        deal(chainTokens[ARBITRUM_CHAIN_ID].spell, address(receiver), amount);
        chainTokens[ARBITRUM_CHAIN_ID].spell.safeApprove(address(spellPowerStaking), amount);
        spellPowerStaking.notifyRewardAmount(chainTokens[ARBITRUM_CHAIN_ID].spell, amount);

        deal(chainTokens[ARBITRUM_CHAIN_ID].bSpell, address(receiver), amount);
        chainTokens[ARBITRUM_CHAIN_ID].bSpell.safeApprove(address(spellPowerStaking), amount);
        spellPowerStaking.notifyRewardAmount(chainTokens[ARBITRUM_CHAIN_ID].bSpell, amount);
        vm.stopPrank();

        emit Debug("timestamp1", block.timestamp);

        address[] memory persistentContracts = new address[](4);
        persistentContracts[0] = address(spellPowerStaking);
        persistentContracts[0] = address(boundSpellLocker);
        persistentContracts[0] = address(rewardHandler);
        persistentContracts[0] = address(timestampStore);

        vm.makePersistent(
            address(spellPowerStaking),
            address(boundSpellLocker),
            address(rewardHandler)
        );
    }
}
