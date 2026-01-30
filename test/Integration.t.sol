// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/IntentRegistry.sol";
import "../src/IntentVault.sol";
import "../src/FlowExecutor.sol";
import "../src/RateLimiter.sol";
import "../src/triggers/TimeTrigger.sol";
import "../src/triggers/PriceTrigger.sol";
import "../src/actions/SwapAction.sol";

/**
 * @title MockERC20
 * @notice Mock ERC20 token for integration testing
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @title MockPriceFeed
 * @notice Mock Chainlink price feed for testing price triggers
 */
contract MockPriceFeed {
    int256 private price;
    uint8 private _decimals = 18;

    function setPrice(int256 _price) external {
        price = _price;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

/**
 * @title MockUniswapRouter
 * @notice Mock Uniswap V2 Router for testing swap actions
 */
contract MockUniswapRouter {
    uint256 public swapRate = 1e18; // 1:1 by default

    function setSwapRate(uint256 _rate) external {
        swapRate = _rate;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Deadline expired");
        require(path.length >= 2, "Invalid path");

        // Calculate output based on swap rate
        uint256 amountOut = (amountIn * swapRate) / 1e18;
        require(amountOut >= amountOutMin, "Insufficient output amount");

        // Transfer input tokens from sender
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Mint output tokens to recipient
        MockERC20(path[path.length - 1]).mint(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }
}

/**
 * @title MockSwapAction
 * @notice Mock SwapAction that uses MockUniswapRouter for testing
 */
contract MockSwapAction {
    address public uniswapRouter;

    constructor(address _router) {
        uniswapRouter = _router;
    }

    function actionType() external pure returns (uint8) {
        return 1;
    }

    function execute(address vault, bytes calldata actionData) external returns (bool) {
        require(vault != address(0), "Invalid vault");
        require(IIntentVault(vault).isApprovedProtocol(msg.sender), "Protocol not approved");
        require(!IIntentVault(vault).isPaused(), "Vault is paused");

        (
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOutMin,
            uint256 deadline
        ) = abi.decode(actionData, (address, address, uint256, uint256, uint256));

        require(tokenIn != address(0) && tokenOut != address(0), "Invalid tokens");
        require(amountIn > 0, "Invalid amount");
        require(deadline > block.timestamp, "Deadline expired");

        uint256 remainingCap = IIntentVault(vault).getRemainingSpendingCap(tokenIn);
        require(remainingCap >= amountIn, "Spending cap exceeded");

        MockERC20(tokenIn).transferFrom(vault, address(this), amountIn);
        MockERC20(tokenIn).approve(uniswapRouter, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = MockUniswapRouter(uniswapRouter).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            vault,
            deadline
        );

        IIntentVault(vault).recordSpending(tokenIn, amountIn);

        return amounts[1] >= amountOutMin;
    }
}

/**
 * @title IntegrationTestBase
 * @notice Base contract for all integration tests with shared setup
 */
contract IntegrationTestBase is Test {
    // Core contracts
    IntentRegistry public registry;
    FlowExecutor public executor;
    RateLimiter public rateLimiter;

    // Trigger contracts
    TimeTrigger public timeTrigger;
    PriceTrigger public priceTrigger;

    // Mock contracts
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockPriceFeed public priceFeed;
    MockUniswapRouter public uniswapRouter;
    MockSwapAction public swapAction;

    // Test users
    address public user1;
    address public user2;
    address public user3;

    // Test vaults
    IntentVault public vault1;
    IntentVault public vault2;
    IntentVault public vault3;

    // Common test values
    uint256 constant INITIAL_BALANCE = 10000e18;
    uint256 constant SPENDING_CAP = 1000e18;
    uint256 constant SWAP_AMOUNT = 100e18;

    function setUp() public virtual {
        // Setup test users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy mock tokens
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");

        // Deploy mock price feed
        priceFeed = new MockPriceFeed();
        priceFeed.setPrice(100e18);

        // Deploy mock uniswap router
        uniswapRouter = new MockUniswapRouter();

        // Deploy mock swap action
        swapAction = new MockSwapAction(address(uniswapRouter));

        // Deploy core contracts
        registry = new IntentRegistry();
        executor = new FlowExecutor(address(registry));
        rateLimiter = new RateLimiter();

        // Deploy trigger contracts
        timeTrigger = new TimeTrigger();
        priceTrigger = new PriceTrigger();

        // Register triggers
        executor.registerTrigger(1, address(timeTrigger));
        executor.registerTrigger(2, address(priceTrigger));

        // Register action
        executor.registerAction(1, address(swapAction));

        // Setup vaults for each user
        vm.prank(user1);
        vault1 = new IntentVault();

        vm.prank(user2);
        vault2 = new IntentVault();

        vm.prank(user3);
        vault3 = new IntentVault();

        // Fund vaults with tokens
        _fundVault(address(vault1), INITIAL_BALANCE);
        _fundVault(address(vault2), INITIAL_BALANCE);
        _fundVault(address(vault3), INITIAL_BALANCE);

        // Setup spending caps
        _setupVaultSpendingCap(vault1, user1);
        _setupVaultSpendingCap(vault2, user2);
        _setupVaultSpendingCap(vault3, user3);
    }

    function _fundVault(address vault, uint256 amount) internal {
        tokenA.mint(vault, amount);
        tokenB.mint(vault, amount);
    }

    function _setupVaultSpendingCap(IntentVault vault, address owner) internal {
        vm.startPrank(owner);
        vault.setSpendingCap(address(tokenA), SPENDING_CAP);
        vault.setSpendingCap(address(tokenB), SPENDING_CAP);
        vault.approveProtocol(address(executor));
        vm.stopPrank();

        // Approve swap action to transfer tokens from vault
        vm.prank(address(vault));
        tokenA.approve(address(swapAction), type(uint256).max);
    }

    function _getCurrentDayOfWeek() internal view returns (uint256) {
        return (block.timestamp / 1 days) % 7;
    }

    function _getCurrentTimeOfDay() internal view returns (uint256) {
        return block.timestamp % 1 days;
    }

    function _createTimeTriggerData(uint256 dayOfWeek, uint256 timeOfDay, uint256 lastExecution)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(dayOfWeek, timeOfDay, lastExecution);
    }

    function _createPriceTriggerData(address feed, uint256 targetPrice, bool isAbove)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(feed, targetPrice, isAbove);
    }

    function _createConditionData(uint256 minBalance, address token)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(minBalance, token);
    }

    function _createSwapActionData(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) internal pure returns (bytes memory) {
        return abi.encode(tokenIn, tokenOut, amountIn, amountOutMin, deadline);
    }
}
