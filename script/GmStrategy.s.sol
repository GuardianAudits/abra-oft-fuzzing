// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "utils/BaseScript.sol";
import {GmStrategy} from "/strategies/GmStrategy.sol";
import {PrivateMultiRewardsStaking} from "/staking/PrivateMultiRewardsStaking.sol";

contract GmStrategyScript is BaseScript {
    address degenBox;
    address exchangeRouter;
    address reader;
    address syntheticsRouter;
    address safe;
    address usdc;
    address arb;
    address gelatoProxy;
    address zeroXAggregator;

    function deploy()
        public
        returns (
            GmStrategy gmARBStrategy,
            GmStrategy gmETHStrategy,
            GmStrategy gmBTCStrategy,
            GmStrategy gmSOLStrategy,
            GmStrategy gmLINKStrategy
        )
    {
        vm.startBroadcast();

        if (block.chainid != ChainId.Arbitrum) {
            revert("Only Arbitrum");
        }

        degenBox = toolkit.getAddress("degenBox");
        exchangeRouter = toolkit.getAddress("gmx.v2.exchangeRouter");
        reader = toolkit.getAddress("gmx.v2.reader");
        syntheticsRouter = toolkit.getAddress("gmx.v2.syntheticsRouter");
        safe = toolkit.getAddress("safe.ops");
        usdc = toolkit.getAddress("usdc");
        arb = toolkit.getAddress("arb");
        gelatoProxy = toolkit.getAddress("safe.devOps.gelatoProxy");
        zeroXAggregator = toolkit.getAddress("aggregators.zeroXExchangeProxy");

        gmARBStrategy = _deployMarketStrategy("GmARB", toolkit.getAddress("gmx.v2.gmARB"), arb, usdc);
        gmETHStrategy = _deployMarketStrategy("GmETH", toolkit.getAddress("gmx.v2.gmETH"), usdc, address(0));
        gmBTCStrategy = _deployMarketStrategy("GmBTC", toolkit.getAddress("gmx.v2.gmBTC"), usdc, address(0));
        gmSOLStrategy = _deployMarketStrategy("GmSOL", toolkit.getAddress("gmx.v2.gmSOL"), usdc, address(0));
        gmLINKStrategy = _deployMarketStrategy("GmLINK", toolkit.getAddress("gmx.v2.gmLINK"), usdc, address(0));

        vm.stopBroadcast();
    }

    function _deployMarketStrategy(
        string memory name,
        address market,
        address marketInputToken,
        address marketInputToken2
    ) private returns (GmStrategy strategy) {
        require(marketInputToken != address(0), "invalid marketInputToken");
        require(market != address(0), "invalid market");

        PrivateMultiRewardsStaking staking = PrivateMultiRewardsStaking(
            deploy(
                string.concat(name, "_Strategy_Staking"),
                "PrivateMultiRewardsStaking.sol:PrivateMultiRewardsStaking",
                abi.encode(market, tx.origin)
            )
        );

        strategy = GmStrategy(
            payable(
                deploy(
                    string.concat(name, "_Strategy"),
                    "GmStrategy.sol:GmStrategy",
                    abi.encode(market, degenBox, exchangeRouter, reader, syntheticsRouter, safe, staking)
                )
            )
        );

        if (staking.owner() == tx.origin) {
            staking.addReward(arb, 7 days);
            staking.setAuthorized(address(strategy), true);
        }

        strategy.setStrategyExecutor(gelatoProxy, true);
        strategy.setTokenApproval(marketInputToken, syntheticsRouter, type(uint256).max);

        if (marketInputToken2 != address(0)) {
            strategy.setTokenApproval(marketInputToken2, syntheticsRouter, type(uint256).max);
        }

        if (!testing()) {
            strategy.setExchange(zeroXAggregator);
            strategy.setTokenApproval(arb, zeroXAggregator, type(uint256).max);
            strategy.transferOwnership(safe, true, false);

            if (staking.owner() != safe) {
                staking.transferOwnership(safe);
            }
        }
    }
}
