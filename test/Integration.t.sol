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

/**
 * @title FlowLifecycleTest
 * @notice Tests for complete flow lifecycle: creation → trigger → condition → execution
 */
contract FlowLifecycleTest is IntegrationTestBase {

    function test_CompleteFlowLifecycle_TimeTrigger() public {
        // Step 1: Create flow with time trigger
        uint256 dayOfWeek = _getCurrentDayOfWeek();
        uint256 timeOfDay = _getCurrentTimeOfDay();

        bytes memory triggerData = _createTimeTriggerData(dayOfWeek, timeOfDay, 0);
        bytes memory conditionData = _createConditionData(50e18, address(tokenA));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18, // Allow 1% slippage
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Step 2: Verify flow was created
        IIntentRegistry.IntentFlow memory flow = registry.getFlow(flowId);
        assertEq(flow.user, address(vault1));
        assertEq(flow.triggerType, 1);
        assertTrue(flow.active);
        assertEq(flow.executionCount, 0);

        // Step 3: Check flow can be executed
        (bool canExecute, string memory reason) = executor.canExecuteFlow(flowId);
        assertTrue(canExecute, reason);

        // Step 4: Execute the flow
        uint256 balanceBefore = tokenA.balanceOf(address(vault1));
        bool success = executor.executeFlow(flowId);
        assertTrue(success);

        // Step 5: Verify execution results
        uint256 balanceAfter = tokenA.balanceOf(address(vault1));
        assertEq(balanceBefore - balanceAfter, SWAP_AMOUNT);

        // Step 6: Verify execution was recorded
        flow = registry.getFlow(flowId);
        assertEq(flow.executionCount, 1);
        assertGt(flow.lastExecutedAt, 0);
    }

    function test_CompleteFlowLifecycle_PriceTrigger() public {
        // Step 1: Set price above target
        priceFeed.setPrice(150e18);

        // Step 2: Create flow with price trigger (execute when price >= 100)
        bytes memory triggerData = _createPriceTriggerData(address(priceFeed), 100e18, true);
        bytes memory conditionData = _createConditionData(50e18, address(tokenA));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(2, 100e18, triggerData, conditionData, actionData);

        // Step 3: Execute flow
        bool success = executor.executeFlow(flowId);
        assertTrue(success);

        // Step 4: Verify execution recorded
        IIntentRegistry.IntentFlow memory flow = registry.getFlow(flowId);
        assertEq(flow.executionCount, 1);
    }

    function test_FlowCreationEmitsEvent() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        vm.expectEmit(true, true, false, true);
        emit IIntentRegistry.FlowCreated(1, address(vault1), 1, 0);
        registry.createFlow(1, 0, triggerData, conditionData, actionData);
    }

    function test_FlowExecutionUpdatesState() public {
        // Create and execute flow
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execute multiple times (need to warp time for time trigger)
        executor.executeFlow(flowId);

        IIntentRegistry.IntentFlow memory flow = registry.getFlow(flowId);
        assertEq(flow.executionCount, 1);
        assertEq(flow.lastExecutedAt, block.timestamp);
    }

    function test_FlowWithNoConditionData() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = ""; // Empty condition
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        bool success = executor.executeFlow(flowId);
        assertTrue(success);
    }
}

/**
 * @title MultiUserScenarioTest
 * @notice Tests for multi-user scenarios and flow isolation
 */
contract MultiUserScenarioTest is IntegrationTestBase {

    function test_MultipleUsersCreateIndependentFlows() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        // User 1 creates flow
        vm.prank(address(vault1));
        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // User 2 creates flow
        vm.prank(address(vault2));
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // User 3 creates flow
        vm.prank(address(vault3));
        uint256 flowId3 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Verify each user has their own flow
        assertEq(registry.getFlow(flowId1).user, address(vault1));
        assertEq(registry.getFlow(flowId2).user, address(vault2));
        assertEq(registry.getFlow(flowId3).user, address(vault3));

        // Verify flow IDs are sequential
        assertEq(flowId1, 1);
        assertEq(flowId2, 2);
        assertEq(flowId3, 3);
    }

    function test_UserFlowsAreSeparate() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        // User 1 creates 2 flows
        vm.startPrank(address(vault1));
        registry.createFlow(1, 0, triggerData, conditionData, actionData);
        registry.createFlow(1, 0, triggerData, conditionData, actionData);
        vm.stopPrank();

        // User 2 creates 1 flow
        vm.prank(address(vault2));
        registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Verify user flows
        uint256[] memory user1Flows = registry.getUserFlows(address(vault1));
        uint256[] memory user2Flows = registry.getUserFlows(address(vault2));

        assertEq(user1Flows.length, 2);
        assertEq(user2Flows.length, 1);
    }

    function test_OneUserExecutionDoesNotAffectAnother() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        // Both users create flows
        vm.prank(address(vault1));
        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        vm.prank(address(vault2));
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Record initial balances
        uint256 vault1BalanceBefore = tokenA.balanceOf(address(vault1));
        uint256 vault2BalanceBefore = tokenA.balanceOf(address(vault2));

        // Execute only user 1's flow
        executor.executeFlow(flowId1);

        // Verify only user 1's balance changed
        assertEq(tokenA.balanceOf(address(vault1)), vault1BalanceBefore - SWAP_AMOUNT);
        assertEq(tokenA.balanceOf(address(vault2)), vault2BalanceBefore);

        // Verify only user 1's flow execution count updated
        assertEq(registry.getFlow(flowId1).executionCount, 1);
        assertEq(registry.getFlow(flowId2).executionCount, 0);
    }

    function test_MultipleUsersCanExecuteSimultaneously() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        // All users create flows
        vm.prank(address(vault1));
        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        vm.prank(address(vault2));
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        vm.prank(address(vault3));
        uint256 flowId3 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execute all flows
        bool success1 = executor.executeFlow(flowId1);
        bool success2 = executor.executeFlow(flowId2);
        bool success3 = executor.executeFlow(flowId3);

        assertTrue(success1);
        assertTrue(success2);
        assertTrue(success3);

        // Verify all executions recorded
        assertEq(registry.getFlow(flowId1).executionCount, 1);
        assertEq(registry.getFlow(flowId2).executionCount, 1);
        assertEq(registry.getFlow(flowId3).executionCount, 1);
    }

    function test_OnlyFlowOwnerCanUpdateStatus() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        // User 1 creates flow
        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // User 2 tries to update user 1's flow - should fail
        vm.prank(address(vault2));
        vm.expectRevert("Only flow owner can update");
        registry.updateFlowStatus(flowId, false);

        // User 1 can update their own flow
        vm.prank(address(vault1));
        registry.updateFlowStatus(flowId, false);

        assertFalse(registry.getFlow(flowId).active);
    }
}
