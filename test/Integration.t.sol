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

/**
 * @title PausedVaultTest
 * @notice Tests for paused vault edge cases
 */
contract PausedVaultTest is IntegrationTestBase {

    function test_CannotExecuteFlowWhenVaultPaused() public {
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

        // Pause the vault
        vm.prank(user1);
        vault1.pause();

        // Execution should fail
        bool success = executor.executeFlow(flowId);
        assertFalse(success);

        // Verify no execution was recorded
        assertEq(registry.getFlow(flowId).executionCount, 0);
    }

    function test_CanExecuteAfterVaultUnpaused() public {
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

        // Pause and then unpause the vault
        vm.startPrank(user1);
        vault1.pause();
        vault1.unpause();
        vm.stopPrank();

        // Execution should succeed
        bool success = executor.executeFlow(flowId);
        assertTrue(success);
    }

    function test_CanExecuteCheckReturnsPausedStatus() public {
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

        // Pause the vault
        vm.prank(user1);
        vault1.pause();

        // Check should return paused status
        (bool canExecute, string memory reason) = executor.canExecuteFlow(flowId);
        assertFalse(canExecute);
        assertEq(reason, "Vault is paused");
    }

    function test_PausedVaultDoesNotAffectOtherVaults() public {
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

        // Pause only vault1
        vm.prank(user1);
        vault1.pause();

        // Vault1's flow should fail
        bool success1 = executor.executeFlow(flowId1);
        assertFalse(success1);

        // Vault2's flow should succeed
        bool success2 = executor.executeFlow(flowId2);
        assertTrue(success2);
    }

    function test_VaultPauseDuringExecution() public {
        // This test verifies that if a vault is paused mid-transaction,
        // the action will fail with the appropriate error
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

        // First execution should succeed
        bool success = executor.executeFlow(flowId);
        assertTrue(success);

        // Pause vault
        vm.prank(user1);
        vault1.pause();

        // Second execution should fail
        success = executor.executeFlow(flowId);
        assertFalse(success);
    }
}

/**
 * @title ExpiredDeadlineTest
 * @notice Tests for expired deadline edge cases
 */
contract ExpiredDeadlineTest is IntegrationTestBase {

    function test_CannotExecuteWithExpiredDeadline() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));

        // Set deadline in the past
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp - 1 // Already expired
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execution should fail due to expired deadline
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_DeadlineExpiresAfterFlowCreation() public {
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            deadline
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Warp time past deadline
        vm.warp(deadline + 1);

        // Execution should fail due to expired deadline
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_ExecutionSucceedsBeforeDeadline() public {
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            deadline
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Warp time but stay before deadline
        vm.warp(deadline - 1);

        // Update trigger data for new time
        uint256 newDayOfWeek = (block.timestamp / 1 days) % 7;
        uint256 newTimeOfDay = block.timestamp % 1 days;

        // Create new flow with updated time
        bytes memory newTriggerData = _createTimeTriggerData(newDayOfWeek, newTimeOfDay, 0);
        vm.prank(address(vault1));
        uint256 newFlowId = registry.createFlow(1, 0, newTriggerData, conditionData, actionData);

        // Execution should succeed
        bool success = executor.executeFlow(newFlowId);
        assertTrue(success);
    }

    function test_DeadlineExactlyAtBlockTimestamp() public {
        // Deadline equal to block.timestamp should fail (requires > not >=)
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp // Exactly at current time
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Should fail because deadline must be > block.timestamp
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_LongDeadlineStillWorks() public {
        // Test with a very long deadline (1 year)
        uint256 deadline = block.timestamp + 365 days;

        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            deadline
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        bool success = executor.executeFlow(flowId);
        assertTrue(success);
    }
}

/**
 * @title FailedExecutionHandlingTest
 * @notice Tests for various failure scenarios and error handling
 */
contract FailedExecutionHandlingTest is IntegrationTestBase {

    function test_ExecutionFailsWithInactiveFlow() public {
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

        // Deactivate flow
        vm.prank(address(vault1));
        registry.updateFlowStatus(flowId, false);

        // Execution should revert
        vm.expectRevert("Flow is not active");
        executor.executeFlow(flowId);
    }

    function test_ExecutionFailsWhenTriggerNotMet() public {
        // Set price below target
        priceFeed.setPrice(50e18);

        // Create flow with price trigger (execute when price >= 100)
        bytes memory triggerData = _createPriceTriggerData(address(priceFeed), 100e18, true);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(2, 100e18, triggerData, conditionData, actionData);

        // Execution should fail
        bool success = executor.executeFlow(flowId);
        assertFalse(success);

        // No execution recorded
        assertEq(registry.getFlow(flowId).executionCount, 0);
    }

    function test_ExecutionFailsWhenConditionNotMet() public {
        // Burn tokens to fail condition check
        tokenA.burn(address(vault1), INITIAL_BALANCE - 10e18);

        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        // Require 100 tokens but vault only has 10
        bytes memory conditionData = _createConditionData(100e18, address(tokenA));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execution should fail due to condition
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_ExecutionFailsWithInsufficientBalance() public {
        // Burn most tokens
        tokenA.burn(address(vault1), INITIAL_BALANCE - 10e18);

        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        // Try to swap more than available
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            100e18, // More than the 10e18 available
            90e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execution should fail
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_ExecutionFailsWithInvalidTokens() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        // Use zero address for token
        bytes memory actionData = _createSwapActionData(
            address(0), // Invalid token
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execution should fail
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_ExecutionFailsWithZeroAmount() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            0, // Zero amount
            0,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execution should fail
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_ExecutionFailsWithNoActionData() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = ""; // Empty action data

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execution should fail
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_FailedExecutionDoesNotUpdateState() public {
        // Set price below target to cause trigger failure
        priceFeed.setPrice(50e18);

        bytes memory triggerData = _createPriceTriggerData(address(priceFeed), 100e18, true);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(2, 100e18, triggerData, conditionData, actionData);

        uint256 balanceBefore = tokenA.balanceOf(address(vault1));

        // Execution fails
        bool success = executor.executeFlow(flowId);
        assertFalse(success);

        // Balance unchanged
        assertEq(tokenA.balanceOf(address(vault1)), balanceBefore);

        // Execution count unchanged
        assertEq(registry.getFlow(flowId).executionCount, 0);
        assertEq(registry.getFlow(flowId).lastExecutedAt, 0);
    }
}

/**
 * @title SpendingCapIntegrationTest
 * @notice Tests for spending cap enforcement during flow execution
 */
contract SpendingCapIntegrationTest is IntegrationTestBase {

    function test_ExecutionRespectsSpendingCap() public {
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

        // Execute flow
        executor.executeFlow(flowId);

        // Verify spending was recorded
        uint256 remaining = vault1.getRemainingSpendingCap(address(tokenA));
        assertEq(remaining, SPENDING_CAP - SWAP_AMOUNT);
    }

    function test_ExecutionFailsWhenSpendingCapExceeded() public {
        // First, set a very low spending cap
        vm.prank(user1);
        vault1.setSpendingCap(address(tokenA), 50e18);

        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        // Try to spend 100e18 when cap is 50e18
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            100e18,
            99e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Execution should fail due to spending cap
        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }

    function test_MultipleExecutionsTrackCumulativeSpending() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            100e18,
            99e18,
            block.timestamp + 1 hours
        );

        // Create multiple flows
        vm.startPrank(address(vault1));
        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        vm.stopPrank();

        // Execute first flow
        executor.executeFlow(flowId1);
        assertEq(vault1.getRemainingSpendingCap(address(tokenA)), SPENDING_CAP - 100e18);

        // Execute second flow
        executor.executeFlow(flowId2);
        assertEq(vault1.getRemainingSpendingCap(address(tokenA)), SPENDING_CAP - 200e18);
    }

    function test_SpendingCapResetAllowsNewExecutions() public {
        // Set low spending cap
        vm.prank(user1);
        vault1.setSpendingCap(address(tokenA), 100e18);

        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            100e18,
            99e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // First execution succeeds
        bool success = executor.executeFlow(flowId);
        assertTrue(success);

        // Second execution fails (cap exhausted)
        vm.prank(address(vault1));
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        success = executor.executeFlow(flowId2);
        assertFalse(success);

        // Reset spending tracker
        vm.prank(user1);
        vault1.resetSpendingTracker(address(tokenA));

        // Now execution should succeed again
        vm.prank(address(vault1));
        uint256 flowId3 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        success = executor.executeFlow(flowId3);
        assertTrue(success);
    }

    function test_DifferentTokensHaveSeparateCaps() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));

        // Swap tokenA
        bytes memory actionDataA = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actionDataA);

        executor.executeFlow(flowId);

        // TokenA cap reduced, tokenB cap unchanged
        assertEq(vault1.getRemainingSpendingCap(address(tokenA)), SPENDING_CAP - SWAP_AMOUNT);
        assertEq(vault1.getRemainingSpendingCap(address(tokenB)), SPENDING_CAP);
    }

    function test_SpendingCapEdgeCase_ExactCapAmount() public {
        // Set cap exactly equal to swap amount
        vm.prank(user1);
        vault1.setSpendingCap(address(tokenA), SWAP_AMOUNT);

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

        // Should succeed - exact cap
        bool success = executor.executeFlow(flowId);
        assertTrue(success);

        // Cap should now be 0
        assertEq(vault1.getRemainingSpendingCap(address(tokenA)), 0);
    }
}

/**
 * @title RateLimiterIntegrationTest
 * @notice Tests for rate limiting during flow execution
 */
contract RateLimiterIntegrationTest is IntegrationTestBase {

    function test_RateLimiterTracksExecutions() public {
        // Set execution limit
        rateLimiter.setExecutionLimitPerDay(address(vault1), 2);

        // Record execution
        rateLimiter.recordExecution(address(vault1), 1);

        // Verify last execution time
        assertEq(rateLimiter.getLastExecutionTime(address(vault1), 1), block.timestamp);
    }

    function test_RateLimiterBlocksRapidExecution() public {
        // Set execution limit to 2 per day (12 hour intervals)
        rateLimiter.setExecutionLimitPerDay(address(vault1), 2);

        // First execution allowed
        assertTrue(rateLimiter.canExecute(address(vault1), 1));

        // Record first execution
        rateLimiter.recordExecution(address(vault1), 1);

        // Immediate second execution blocked
        assertFalse(rateLimiter.canExecute(address(vault1), 1));
    }

    function test_RateLimiterAllowsAfterInterval() public {
        // Set execution limit to 2 per day (12 hour intervals)
        rateLimiter.setExecutionLimitPerDay(address(vault1), 2);

        // Record execution
        rateLimiter.recordExecution(address(vault1), 1);

        // Warp 12 hours + 1 second
        vm.warp(block.timestamp + 12 hours + 1);

        // Should be allowed now
        assertTrue(rateLimiter.canExecute(address(vault1), 1));
    }

    function test_RateLimiterDifferentFlowsIndependent() public {
        rateLimiter.setExecutionLimitPerDay(address(vault1), 2);

        // Record execution for flow 1
        rateLimiter.recordExecution(address(vault1), 1);

        // Flow 1 blocked
        assertFalse(rateLimiter.canExecute(address(vault1), 1));

        // Flow 2 still allowed
        assertTrue(rateLimiter.canExecute(address(vault1), 2));
    }

    function test_RateLimiterDifferentVaultsIndependent() public {
        rateLimiter.setExecutionLimitPerDay(address(vault1), 2);
        rateLimiter.setExecutionLimitPerDay(address(vault2), 2);

        // Record execution for vault1
        rateLimiter.recordExecution(address(vault1), 1);

        // Vault1 flow 1 blocked
        assertFalse(rateLimiter.canExecute(address(vault1), 1));

        // Vault2 flow 1 still allowed
        assertTrue(rateLimiter.canExecute(address(vault2), 1));
    }

    function test_RateLimiterMinimumInterval() public {
        // Set 4 executions per day
        rateLimiter.setExecutionLimitPerDay(address(vault1), 4);

        // Minimum interval should be 6 hours
        assertEq(rateLimiter.getMinimumInterval(address(vault1)), 6 hours);
    }

    function test_RateLimiterHighFrequencyLimit() public {
        // Set 24 executions per day (1 per hour)
        rateLimiter.setExecutionLimitPerDay(address(vault1), 24);

        // Minimum interval should be 1 hour
        assertEq(rateLimiter.getMinimumInterval(address(vault1)), 1 hours);

        // Record execution
        rateLimiter.recordExecution(address(vault1), 1);

        // Blocked immediately
        assertFalse(rateLimiter.canExecute(address(vault1), 1));

        // Warp 1 hour
        vm.warp(block.timestamp + 1 hours);

        // Now allowed
        assertTrue(rateLimiter.canExecute(address(vault1), 1));
    }

    function test_RateLimiterFirstExecutionAlwaysAllowed() public {
        rateLimiter.setExecutionLimitPerDay(address(vault1), 1);

        // First execution always allowed (lastExecution == 0)
        assertTrue(rateLimiter.canExecute(address(vault1), 1));
    }

    function test_RateLimiterMultipleFlowsConcurrent() public {
        rateLimiter.setExecutionLimitPerDay(address(vault1), 2);

        // Execute multiple different flows
        rateLimiter.recordExecution(address(vault1), 1);
        rateLimiter.recordExecution(address(vault1), 2);
        rateLimiter.recordExecution(address(vault1), 3);

        // All should be blocked for rapid re-execution
        assertFalse(rateLimiter.canExecute(address(vault1), 1));
        assertFalse(rateLimiter.canExecute(address(vault1), 2));
        assertFalse(rateLimiter.canExecute(address(vault1), 3));

        // But a new flow is still allowed
        assertTrue(rateLimiter.canExecute(address(vault1), 4));
    }
}

/**
 * @title FlowStatusUpdateTest
 * @notice Tests for flow activation/deactivation scenarios
 */
contract FlowStatusUpdateTest is IntegrationTestBase {

    function test_DeactivateFlowPreventsExecution() public {
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

        // Deactivate flow
        vm.prank(address(vault1));
        registry.updateFlowStatus(flowId, false);

        // Verify flow is inactive
        assertFalse(registry.getFlow(flowId).active);

        // Execution should fail
        vm.expectRevert("Flow is not active");
        executor.executeFlow(flowId);
    }

    function test_ReactivateFlowAllowsExecution() public {
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

        // Deactivate and then reactivate
        vm.startPrank(address(vault1));
        registry.updateFlowStatus(flowId, false);
        registry.updateFlowStatus(flowId, true);
        vm.stopPrank();

        // Execution should succeed
        bool success = executor.executeFlow(flowId);
        assertTrue(success);
    }

    function test_FlowStatusToggle() public {
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

        // Toggle multiple times
        vm.startPrank(address(vault1));

        registry.updateFlowStatus(flowId, false);
        assertFalse(registry.getFlow(flowId).active);

        registry.updateFlowStatus(flowId, true);
        assertTrue(registry.getFlow(flowId).active);

        registry.updateFlowStatus(flowId, false);
        assertFalse(registry.getFlow(flowId).active);

        vm.stopPrank();
    }

    function test_StatusUpdateEmitsEvent() public {
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

        vm.prank(address(vault1));
        vm.expectEmit(true, false, false, true);
        emit IIntentRegistry.FlowStatusUpdated(flowId, false);
        registry.updateFlowStatus(flowId, false);
    }

    function test_DeactivatedFlowMaintainsData() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(50e18, address(tokenA));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            SWAP_AMOUNT,
            SWAP_AMOUNT - 1e18,
            block.timestamp + 1 hours
        );

        vm.prank(address(vault1));
        uint256 flowId = registry.createFlow(1, 100e18, triggerData, conditionData, actionData);

        // Execute once
        executor.executeFlow(flowId);

        // Deactivate
        vm.prank(address(vault1));
        registry.updateFlowStatus(flowId, false);

        // Verify data is preserved
        IIntentRegistry.IntentFlow memory flow = registry.getFlow(flowId);
        assertEq(flow.user, address(vault1));
        assertEq(flow.triggerType, 1);
        assertEq(flow.triggerValue, 100e18);
        assertEq(flow.executionCount, 1);
        assertGt(flow.lastExecutedAt, 0);
        assertFalse(flow.active);
    }
}

/**
 * @title MultipleFlowsPerUserTest
 * @notice Tests for users with multiple flows
 */
contract MultipleFlowsPerUserTest is IntegrationTestBase {

    function test_UserCanCreateMultipleFlows() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            10e18,
            9e18,
            block.timestamp + 1 hours
        );

        vm.startPrank(address(vault1));

        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId3 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId4 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId5 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        vm.stopPrank();

        // Verify all flows created
        uint256[] memory userFlows = registry.getUserFlows(address(vault1));
        assertEq(userFlows.length, 5);

        // Verify flow IDs
        assertEq(userFlows[0], flowId1);
        assertEq(userFlows[1], flowId2);
        assertEq(userFlows[2], flowId3);
        assertEq(userFlows[3], flowId4);
        assertEq(userFlows[4], flowId5);
    }

    function test_ExecuteOnlyEligibleFlows() public {
        // Create flows with different triggers
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            10e18,
            9e18,
            block.timestamp + 1 hours
        );

        // Flow 1: Time trigger (will be met)
        bytes memory triggerData1 = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);

        // Flow 2: Price trigger below current price (will NOT be met)
        priceFeed.setPrice(100e18);
        bytes memory triggerData2 = _createPriceTriggerData(address(priceFeed), 150e18, true);

        // Flow 3: Price trigger above current price (will be met)
        bytes memory triggerData3 = _createPriceTriggerData(address(priceFeed), 50e18, true);

        vm.startPrank(address(vault1));
        uint256 flowId1 = registry.createFlow(1, 0, triggerData1, conditionData, actionData);
        uint256 flowId2 = registry.createFlow(2, 150e18, triggerData2, conditionData, actionData);
        uint256 flowId3 = registry.createFlow(2, 50e18, triggerData3, conditionData, actionData);
        vm.stopPrank();

        // Execute all flows
        bool success1 = executor.executeFlow(flowId1);
        bool success2 = executor.executeFlow(flowId2);
        bool success3 = executor.executeFlow(flowId3);

        // Only flows 1 and 3 should succeed
        assertTrue(success1);
        assertFalse(success2);
        assertTrue(success3);

        // Verify execution counts
        assertEq(registry.getFlow(flowId1).executionCount, 1);
        assertEq(registry.getFlow(flowId2).executionCount, 0);
        assertEq(registry.getFlow(flowId3).executionCount, 1);
    }

    function test_MixedActiveInactiveFlows() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            10e18,
            9e18,
            block.timestamp + 1 hours
        );

        vm.startPrank(address(vault1));
        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId3 = registry.createFlow(1, 0, triggerData, conditionData, actionData);

        // Deactivate flow 2
        registry.updateFlowStatus(flowId2, false);
        vm.stopPrank();

        // Execute flows
        bool success1 = executor.executeFlow(flowId1);
        vm.expectRevert("Flow is not active");
        executor.executeFlow(flowId2);
        bool success3 = executor.executeFlow(flowId3);

        assertTrue(success1);
        assertTrue(success3);
    }

    function test_FlowsWithDifferentConditions() public {
        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            10e18,
            9e18,
            block.timestamp + 1 hours
        );

        // Flow 1: No condition
        bytes memory conditionData1 = _createConditionData(0, address(0));

        // Flow 2: Requires 50 tokens (will be met)
        bytes memory conditionData2 = _createConditionData(50e18, address(tokenA));

        // Flow 3: Requires more tokens than available
        bytes memory conditionData3 = _createConditionData(INITIAL_BALANCE + 1, address(tokenA));

        vm.startPrank(address(vault1));
        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData1, actionData);
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData2, actionData);
        uint256 flowId3 = registry.createFlow(1, 0, triggerData, conditionData3, actionData);
        vm.stopPrank();

        // Execute
        bool success1 = executor.executeFlow(flowId1);
        bool success2 = executor.executeFlow(flowId2);
        bool success3 = executor.executeFlow(flowId3);

        assertTrue(success1);
        assertTrue(success2);
        assertFalse(success3);
    }

    function test_CumulativeSpendingAcrossFlows() public {
        // Set lower cap to test cumulative spending
        vm.prank(user1);
        vault1.setSpendingCap(address(tokenA), 250e18);

        bytes memory triggerData = _createTimeTriggerData(_getCurrentDayOfWeek(), _getCurrentTimeOfDay(), 0);
        bytes memory conditionData = _createConditionData(0, address(0));
        bytes memory actionData = _createSwapActionData(
            address(tokenA),
            address(tokenB),
            100e18,
            99e18,
            block.timestamp + 1 hours
        );

        vm.startPrank(address(vault1));
        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        uint256 flowId3 = registry.createFlow(1, 0, triggerData, conditionData, actionData);
        vm.stopPrank();

        // First two should succeed (200e18 total)
        assertTrue(executor.executeFlow(flowId1));
        assertTrue(executor.executeFlow(flowId2));

        // Third should fail (would exceed 250e18 cap)
        assertFalse(executor.executeFlow(flowId3));

        // Verify remaining cap
        assertEq(vault1.getRemainingSpendingCap(address(tokenA)), 50e18);
    }
}
