// SPDX-License-Identifier: GPL-2.0-or-later
// 0x44648Fa5D1FDDE1354F5fb072cceF8A91D6eA219
pragma solidity =0.7.6;
pragma abicoder v2;

import "./ClientStrategy.sol";

contract StrategyFactory {
    ClientStrategy[] public strategies;
    address[] public clients;
    address public constant strategem =
        0xF91C49506bc1925667cd16bA5128f3ca7192Af80;

    constructor() {}

    function createClientStrategy(
        address _base,
        address _target,
        uint64[][6] memory _fib,
        uint8[5] memory _fibDiv,
        uint24 _poolFee,
        uint256[] memory _timeStamps,
        uint64 _sma,
        bool _mode
    ) external returns (ClientStrategy newStrategy) {
        ClientStrategy strategy = new ClientStrategy(
            _base,
            _target,
            _fib,
            _fibDiv,
            _poolFee,
            _timeStamps,
            _sma,
            _mode
        );
        IERC20 tokenContract = IERC20(strategem);
        clients.push(msg.sender);
        strategies.push(strategy);
        tokenContract.transfer(address(strategy), 1 * (10**18));
        return strategy;
    }

    function getClientStrategy(address client)
        public
        view
        returns (ClientStrategy strategy)
    {
        for (uint256 x; x < strategies.length; x++) {
            if (client == clients[x]) {
                return strategies[x];
            }
        }
    }
}
