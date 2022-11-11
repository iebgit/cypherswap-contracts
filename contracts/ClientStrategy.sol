// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;
import "https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol";
import "https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/ISwapRouter.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Factory.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint128);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function decimals() external view returns (uint8);

    function approve(address spender, uint256 amount) external returns (bool);
}

contract ClientStrategy {
    struct Strategy {
        uint24 poolFee;
        // higher the index, greater the timestamp: int48 timestamps = [...timestamps]
        uint256[] timeStamps;
        // higher the index, greater the amount allocated to the trade: uint64 fib = [[sma, price4, price3, price2, price1, 0],[sma, price1 , price2, price3, price4, infinite]]
        uint64[][6] fib;
        // amount to divide balance based on fib range
        uint8[5] fibDiv;
        // sma is usually 20 week but can also be 20 day. 20 week is for weekly trades and 20 day is for daily trades
        uint64 sma;
        // mode will determine whether a trade is unidirectional or bidirectional
        bool mode;
        address base;
        address target;
    }

    address public constant routerAddress =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant factoryAddress =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant feeAddress =
        0x9D7E757488578Fe756987d9AAA5412aF2C1B659e;
    address private constant feeToken =
        0xF91C49506bc1925667cd16bA5128f3ca7192Af80;
    ISwapRouter public immutable swapRouter = ISwapRouter(routerAddress);
    Strategy public currentStrategy;
    address public immutable pool;
    address public immutable creator;
    uint256 ts;

    constructor(
        address _base,
        address _target,
        uint64[][6] memory _fib,
        uint8[5] memory _fibDiv,
        uint24 _poolFee,
        uint256[] memory _timeStamps,
        uint64 _sma,
        bool _mode
    ) {
        currentStrategy = Strategy(
            _poolFee,
            _timeStamps,
            _fib,
            _fibDiv,
            _sma,
            _mode,
            _base,
            _target
        );
        creator = payable(msg.sender);

        address _pool = IUniswapV3Factory(factoryAddress).getPool(
            _target,
            _base,
            _poolFee
        );
        require(_pool != address(0), "pool doesn't exist");

        pool = _pool;
    }

    function swapExactInputSingle(address token, uint128 amountIn)
        private
        returns (uint256 amountOut)
    {
        require(
            token == currentStrategy.base || token == currentStrategy.target,
            "invalid token"
        );
        require(ping(), "invalid time");
        uint256 amount = estimateAmountOut(token, amountIn, 100);
        uint256 amountOutMinimum = amount - (amount / 50);
        address out;
        token == currentStrategy.target
            ? out = currentStrategy.base
            : out = currentStrategy.target;

        IERC20 tokenContract = IERC20(token);
        tokenContract.approve(address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: token,
                tokenOut: out,
                fee: currentStrategy.poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);

        ts = block.timestamp;
    }

    function estimateAmountOut(
        address tokenIn,
        uint128 amountIn,
        uint32 secondsAgo
    ) private view returns (uint256 amountOut) {
        require(
            tokenIn == currentStrategy.target ||
                tokenIn == currentStrategy.base,
            "invalid token"
        );
        address tokenOut = tokenIn == currentStrategy.target
            ? currentStrategy.base
            : currentStrategy.target;

        // (int24 tick, ) = OracleLibrary.consult(pool, secondsAgo);

        // Code copied from OracleLibrary.sol, consult()
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        // int56 since tick * time = int24 * uint32
        // 56 = 24 + 32
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
            secondsAgos
        );

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(tickCumulativesDelta / secondsAgo);
        // Always round to negative infinity
        /*
        int doesn't round down when it is negative
        int56 a = -3
        -3 / 10 = -3.3333... so round down to -4
        but we get
        a / 10 = -3
        so if tickCumulativeDelta < 0 and division has remainder, then round
        down
        */
        if (
            tickCumulativesDelta < 0 && (tickCumulativesDelta % secondsAgo != 0)
        ) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            amountIn,
            tokenIn,
            tokenOut
        );
    }

    function withdrawToken(address _tokenContract, uint256 _amount) external {
        require(msg.sender == creator, "only creator can withdraw");
        require(balance(_tokenContract) > _amount, "wallet balance is too low");
        IERC20 tokenContract = IERC20(_tokenContract);
        // 0.5% withdraw fee goes to hardcoded feeAddress
        uint256 feeAmount = _amount / 200;
        uint256 amount = _amount - feeAmount;
        tokenContract.transfer(feeAddress, feeAmount);
        tokenContract.transfer(msg.sender, amount);
    }

    function balance(address _tokenContract) public view returns (uint128 bal) {
        IERC20 tokenContract = IERC20(_tokenContract);
        bal = tokenContract.balanceOf(address(this));
    }

    function ping() public view returns (bool go) {
        go = false;
        for (uint256 i = 0; i < currentStrategy.timeStamps.length; i++) {
            if (
                currentStrategy.timeStamps[i] < block.timestamp &&
                (currentStrategy.timeStamps[i] + 3600) > block.timestamp &&
                (block.timestamp - ts) > 86400
            ) {
                go = true;
                return go;
            }
        }
        return go;
    }

    function getStrategy() external view returns (Strategy memory strategy) {
        return currentStrategy;
    }

    function updateStrategy(
        uint64[][6] memory _fib,
        uint8[5] memory _fibDiv,
        uint24 _poolFee,
        uint256[] memory _timeStamps,
        uint64 _sma,
        bool _mode
    ) external {
        require(
            msg.sender == creator,
            "only creator can update contract strategy"
        );
        currentStrategy = Strategy(
            _poolFee,
            _timeStamps,
            _fib,
            _fibDiv,
            _sma,
            _mode,
            currentStrategy.base,
            currentStrategy.target
        );
    }

    function updateTokens(address _base, address _target) external {
        require(msg.sender == creator, "only creator can update tokens");
        currentStrategy = Strategy(
            currentStrategy.poolFee,
            currentStrategy.timeStamps,
            currentStrategy.fib,
            currentStrategy.fibDiv,
            currentStrategy.sma,
            currentStrategy.mode,
            _base,
            _target
        );
    }

    function initiate() external returns (uint256 amountOut) {
        require(ping(), "invalid time");
        require(balance(feeToken) >= 1 * (10**17));
        IERC20 target = IERC20(currentStrategy.target);
        uint128 decimals = target.decimals();
        uint128 exp = 10;
        uint128 targetAmount = 1 * (exp**decimals);
        uint256 currentWETHPrice = estimateAmountOut(
            currentStrategy.target,
            targetAmount,
            100
        );
        address tokenIn;
        uint64[] memory fibonacci;
        if (currentWETHPrice > currentStrategy.sma) {
            tokenIn = currentStrategy.target;
            fibonacci = currentStrategy.fib[0];
        } else {
            tokenIn = currentStrategy.base;
            fibonacci = currentStrategy.fib[1];
        }
        uint128 currentBalance = balance(tokenIn);
        IERC20 feeContract = IERC20(feeToken);
        // 0.5% withdraw fee goes to hardcoded feeAddress
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

        uint128 amountIn = currentBalance / divide;
        amountOut = swapExactInputSingle(tokenIn, amountIn);
        return amountOut;
    }
}
