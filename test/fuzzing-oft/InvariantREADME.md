# Overview

Abracadabra engaged Guardian Audits for an in-depth security review of their OFT Staking Contracts. This comprehensive evaluation, conducted from Nov 12th to Nov 18th, 2024, included the development of a specialized fuzzing suite to uncover complex logical errors in various protocol states. This suite, an integral part of the audit, was created during the review period and successfully delivered upon the audit's conclusion.

# Contents

This fuzzing suite was created for the scope below, and updated for remediations at `147db99b584c45bb7e80fad3e785f4faec7d8171`. The fuzzing suite primarily targets the core functionality found in `BoundSpellStakingActions.sol`, `SpellPowerStaking.sol`, `TokenLocker.sol`, and `MultiRewardsClaimingHandler.sol`.

### Testing Methodology

The testing architecture leverages mainnet forking to maintain protocol-accurate parameters and state conditions. This approach allows for:

- Real-world state validation
- Production-equivalent parameter testing
- Accurate simulation of complex DeFi interactions

All properties tested can be found below in this readme.

## NOTE ABOUT SOURCE CODE

Due to the issue of `_getRewardsFor DOS` the recommended fix was added to allow for further coverage of the codebase

`MultiRewardsClaimingHandler.sol::notifyRewards`
```diff
function notifyRewards(
        address _to,
        address _refundTo,
        TokenAmount[] memory _rewards,
        bytes memory _data
    ) external payable onlyOperators {
        MultiRewardsClaimingHandlerParam[] memory _params = abi.decode(_data, (MultiRewardsClaimingHandlerParam[]));

        if (_params.length != _rewards.length) {
            revert ErrInvalidParams();
        }

        for (uint256 i = 0; i < _rewards.length; i++) {
            address token = _rewards[i].token;
            uint256 amount = _rewards[i].amount;
            ILzOFTV2 oft = tokenOfts[token];
            MultiRewardsClaimingHandlerParam memory param = _params[i];

+            if (amount == 0) continue;

            // local reward claiming when the destination is the local chain
            if (param.dstChainId == LOCAL_CHAIN_ID) {
                token.safeTransfer(_to, amount);
                continue;
            }

            if (param.fee > address(this).balance) {
                revert ErrNotEnoughNativeTokenToCoverFee();
            }

            ILzCommonOFT.LzCallParams memory lzCallParams = ILzCommonOFT.LzCallParams({
                refundAddress: payable(_refundTo),
                zroPaymentAddress: address(0),
                adapterParams: abi.encodePacked(MESSAGE_VERSION, uint256(param.gas))
            });

            oft.sendFrom{value: param.fee}(
                address(this), // 'from' address to send tokens
                param.dstChainId, // remote LayerZero chainId
                bytes32(uint256(uint160(address(_to)))), // recipient address
                amount, // amount of tokens to send (in wei)
                lzCallParams
            );
        }
    }
```

## Setup

1. Install libs

```sh
bun install / yarn install
```

Make a copy of `.env.defaults` to `.env` and set the desired parameters. This file is git ignored.

## Usage 

2. Run Foundry
`forge test --match-contract OftInvariant -vvvvv --show-progress`

# Scope

Repo: https://github.com/GuardianAudits/abra-oft-fuzzing


Branch: `abra-suite`

Commit: `1e8b997f6187d87e104a33a4f161fd7f6120d385`

#List of assertions
| Invariant ID | Invariant Description                                                                                 | Passed | Remediations | Run Count |
| ------------ | ----------------------------------------------------------------------------------------------------- | ------ | ------------ | --------- |
| ABRA-01    | TokenLocker.remainingEpochTime() should never return 0                          | ✅     |    ✅       | 10m       |
| ABRA-02    | lastLockIndex for the user always corresponds to the lock with the latest unlock time or there are no locks & the lastLockIndex is nonzero          | ✅     |    ✅      | 10m       |
| ABRA-03    | User staking balance on arbitrum should increase by amount                      | ✅     |      ✅      | 10m       |
| ABRA-04    | User last added time should not be 0        | ❌     |     ✅       | 10m       |
| ABRA-05     | bSpell balance of spellPowerStaking should increase by amount                              | ✅     |     ✅       | 10m       |
| ABRA-06     | bSpell balance of spellPowerStaking should decrease by amount                                                   | ✅     |     ✅       | 10m       |
| ABRA-07     | bSpell balance of user should increase by amount                                                 | ✅     |      ✅      | 10m       |
| ABRA-08     | User should have received earned rewardToken                                                 | ✅     |     ✅       | 10m       |
| ABRA-09     | Mainnet bSpell user balance should decrease by amount                                                 | ✅     |     ✅       | 10m       |
| ABRA-10     | Sender underlying balance should decrease when minting bSpell                                                 | ✅     |     ✅       | 10m       |
| ABRA-11     | Receiver asset balance should increase when minting bSpell                                                 | ✅     |      ✅      | 10m       |
| ABRA-12     | Total supply of asset should increase when minting bSpell                                                | ✅     |      ✅      | 10m       |
| ABRA-13     | Total supply of asset should decrease when redeeming bSpell                                                 | ✅     |      ✅      | 10m       |
| ABRA-14     | Sender bSpell balance should decrease when redeeming                                                 | ✅     |      ✅      | 10m       |
| ABRA-15    | Locker should not hold any bSpell                                | ✅     |      ✅      | 10m       |
| ABRA-16    | Receiver underlying balance should increase by claimable when redeeming bSpell                                                   | ✅     |      ✅      | 10m       |
| ABRA-17    | Total supply of asset should increase by the difference between fees and amount when instantRedeeming bSpell | ✅     |      ✅      | 10m       |
| ABRA-18    | Receiver underlying balance should increase by immediateAmount and claimable when instantRedeeming bSpell | ✅     |     ✅       | 10m       |
| ABRA-19    | FeeCollector balance of bSpell should increase by feeAmount when instantRedeeming | ✅     |     ✅       | 10m       |
| ABRA-20    | User should have received claimable tokens when calling claim | ✅     |     ✅       | 10m       |
| ABRA-21    | Receiver should have received claimable tokens when calling claimTo | ✅     |     ✅       | 10m       |
