// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.0;
pragma abicoder v2;

import "./ClientStrategy.sol";

contract StrategyFactory {
    ClientStrategy[] public strategies;
    address[] public clients;
    address public immutable stratagem =
        0xF91C49506bc1925667cd16bA5128f3ca7192Af80;
    address public immutable creator;

    constructor() {
        creator = msg.sender;
    }

    function createClientStrategy(
        address _base,
        address _target,
        uint64[][2] memory _fib,
        uint8[5] memory _fibDiv,
        uint128[20] memory _timeStamps,
        uint64 _sma
    ) external returns (ClientStrategy newStrategy) {
        ClientStrategy strategy = new ClientStrategy(
            creator,
            msg.sender,
            _base,
            _target,
            _fib,
            _fibDiv,
            _timeStamps,
            _sma
        );
        IERC20 tokenContract = IERC20(stratagem);
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

    function balance() public view returns (uint256 bal) {
        IERC20 tokenContract = IERC20(stratagem);
        bal = tokenContract.balanceOf(address(this));
    }
}
