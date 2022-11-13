// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.0;
pragma abicoder v2;

import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";

contract ClientStrategy {
    struct Strategy {
        address base;
        address target;
        uint64[][2] fib;
        uint8[5] fibDiv;
        uint128[20] timeStamps;
        uint64 sma;
    }
    Strategy public currentStrategy;
    address internal constant routerAddress =
        0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    IUniswapV2Router02 public uniswap;
    address public immutable usdcAddress =
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public immutable feeToken =
        0xF91C49506bc1925667cd16bA5128f3ca7192Af80;
    address public immutable creator;
    address public immutable factory;
    uint256 public ts;

    constructor(
        address _factory,
        address _creator,
        address _base,
        address _target,
        uint64[][2] memory _fib,
        uint8[5] memory _fibDiv,
        uint128[20] memory _timeStamps,
        uint64 _sma
    ) {
        uniswap = IUniswapV2Router02(routerAddress);
        creator = _creator;
        factory = _factory;
        currentStrategy = Strategy(
            _base,
            _target,
            _fib,
            _fibDiv,
            _timeStamps,
            _sma
        );

        ts = 0;
    }

    receive() external payable {}

    function swap(uint256 _amount, address[] memory _path) internal {
        uint256 deadline = block.timestamp + 15; // using 'now' for convenience, for mainnet pass deadline from frontend!
        uint256[] memory response = getEstimatedTargetforBase(_amount, _path);
        uint256 amountOutMin = response[response.length - 1] -
            response[response.length - 1] /
            50;
        if (currentStrategy.base == uniswap.WETH()) {
            uniswap.swapExactETHForTokens{value: _amount}(
                amountOutMin,
                _path,
                address(this),
                deadline
            );
        } else if (currentStrategy.target == uniswap.WETH()) {
            uniswap.swapExactTokensForETH(
                _amount,
                amountOutMin,
                _path,
                address(this),
                deadline
            );
        } else {
            uniswap.swapExactTokensForTokens(
                _amount,
                amountOutMin,
                _path,
                address(this),
                deadline
            );
        }

        ts = block.timestamp;
    }

    function initiate() external {
        require(ping(), "Invalid Time");
        require(balance(feeToken) >= 1 * (10**17), "Deposit More GEM");
        ERC20 target = ERC20(currentStrategy.target);
        address[] memory path0;
        path0[0] = currentStrategy.target;
        path0[1] = usdcAddress;
        uint256[] memory prices = uniswap.getAmountsOut(
            1 * (10**target.decimals()),
            path0
        );
        address tokenIn;
        uint64[] memory fibonacci;
        if (prices[prices.length - 1] > currentStrategy.sma) {
            tokenIn = currentStrategy.base;
            fibonacci = currentStrategy.fib[0];
        } else {
            tokenIn = currentStrategy.target;
            fibonacci = currentStrategy.fib[1];
        }

        uint256 currentBalance = balance(tokenIn);
        IERC20 feeContract = IERC20(feeToken);
        feeContract.transfer(msg.sender, 1 * (10**17));
        uint8 divide;
        for (uint256 i = 0; i < fibonacci.length - 1; i++) {
            if (
                fibonacci[i] < currentBalance &&
                fibonacci[i + 1] > currentBalance
            ) {
                divide = currentStrategy.fibDiv[i];
            }
        }
        address tokenOut = tokenIn == currentStrategy.base
            ? currentStrategy.target
            : currentStrategy.base;
        uint256 amountIn = currentBalance / divide;

        swap(amountIn, getPathForBasetoTarget(tokenOut, tokenIn));
    }

    function timestamp() public view returns (uint256) {
        return block.timestamp;
    }

    function getEstimatedTargetforBase(uint256 _base, address[] memory _path)
        public
        view
        returns (uint256[] memory)
    {
        return uniswap.getAmountsOut(_base, _path);
    }

    function getPathForBasetoTarget(address _tokenOut, address _tokenIn)
        public
        pure
        returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = _tokenOut;
        path[1] = _tokenIn;
        return path;
    }

    function updateTokens(address _base, address _target) external {
        require(msg.sender == creator, "Only The Creator Can Update Tokens");
        currentStrategy.base = _base;
        currentStrategy.target = _target;
    }

    function updateStrategy(
        address _base,
        address _target,
        uint64[][2] memory _fib,
        uint8[5] memory _fibDiv,
        uint128[20] memory _timeStamps,
        uint64 _sma
    ) external {
        require(
            msg.sender == creator,
            "Only The Creator Can Update The Contract Strategy"
        );
        currentStrategy = Strategy(
            _base,
            _target,
            _fib,
            _fibDiv,
            _timeStamps,
            _sma
        );
    }

    function ping() public view returns (bool) {
        bool go = false;
        for (uint256 i = 0; i < currentStrategy.timeStamps.length; i++) {
            if (
                currentStrategy.timeStamps[i] < block.timestamp &&
                (currentStrategy.timeStamps[i] + 3600) > block.timestamp &&
                (block.timestamp - ts) > 86400
            ) {
                go = true;
            }
        }
        return go;
    }

    function getStrategy() external view returns (Strategy memory strategy) {
        return currentStrategy;
    }

    function withdrawToken(address _tokenContract, uint256 _amount) external {
        require(msg.sender == creator, "Unauthorized");
        require(balance(_tokenContract) >= _amount, "Contract Balance Too Low");
        address payable to = payable(creator);
        IERC20 tokenContract = IERC20(_tokenContract);
        uint256 fee = _amount / 200;
        payFee(_tokenContract, fee);
        uint256 amount = _amount - fee;
        tokenContract.transfer(to, amount);
    }

    function withdrawEth(uint256 _amount) public payable {
        require(msg.sender == creator, "Unauthorized");
        require(ethBalance() >= _amount, "Contract Balance Too Low");
        address payable to = payable(creator);
        uint256 fee = _amount / 200;
        payEthFee(fee);
        uint256 amount = _amount - fee;
        (bool sent, bytes memory data) = to.call{value: amount}("");
        require(sent, "Failed To Send");
    }

    function payFee(address _tokenContract, uint256 _fee) internal {
        address payable feeAddress = payable(factory);
        IERC20 tokenContract = IERC20(_tokenContract);
        tokenContract.transfer(feeAddress, _fee);
    }

    function payEthFee(uint256 _fee) internal {
        address payable feeAddress = payable(factory);
        (bool sent, bytes memory data) = feeAddress.call{value: _fee}("");
        require(sent, "Failed To Send");
    }

    function balance(address _tokenContract) public view returns (uint256 bal) {
        IERC20 tokenContract = IERC20(_tokenContract);
        bal = tokenContract.balanceOf(address(this));
    }

    function ethBalance() public view returns (uint256 bal) {
        bal = address(this).balance;
    }
}
