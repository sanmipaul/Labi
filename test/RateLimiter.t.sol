pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/RateLimiter.sol";

contract RateLimiterTest is Test {
    RateLimiter rateLimiter;
    address vault;
    address vault2;

    function setUp() public {
        rateLimiter = new RateLimiter();
        vault = address(0x1111);
        vault2 = address(0x2222);
    }

    function test_SetExecutionLimit() public {
        rateLimiter.setExecutionLimitPerDay(vault, 5);
        assertEq(rateLimiter.executionLimitPerDay(vault), 5);
    }

    function test_CanExecuteFirstTime() public {
        rateLimiter.setExecutionLimitPerDay(vault, 5);
        bool canExecute = rateLimiter.canExecute(vault, 1);
        assertTrue(canExecute);
    }

    function test_CannotExecuteBeforeMinInterval() public {
        rateLimiter.setExecutionLimitPerDay(vault, 2);
        
        rateLimiter.recordExecution(vault, 1);
        
        bool canExecute = rateLimiter.canExecute(vault, 1);
        assertFalse(canExecute);
    }

    function test_CanExecuteAfterMinInterval() public {
        rateLimiter.setExecutionLimitPerDay(vault, 2);
        
        rateLimiter.recordExecution(vault, 1);
        
        vm.warp(block.timestamp + 12 hours + 1 seconds);
        
        bool canExecute = rateLimiter.canExecute(vault, 1);
        assertTrue(canExecute);
    }

    function test_GetMinimumInterval() public {
        rateLimiter.setExecutionLimitPerDay(vault, 2);
        uint256 minInterval = rateLimiter.getMinimumInterval(vault);
        assertEq(minInterval, 12 hours);
    }

    function test_MultipleFlowsIndependentTracking() public {
        rateLimiter.setExecutionLimitPerDay(vault, 5);
        
        rateLimiter.recordExecution(vault, 1);
        rateLimiter.recordExecution(vault, 2);
        
        bool canExecuteFlow1 = rateLimiter.canExecute(vault, 1);
        bool canExecuteFlow2 = rateLimiter.canExecute(vault, 2);
        
        assertFalse(canExecuteFlow1);
        assertFalse(canExecuteFlow2);
    }

    function test_GetLastExecutionTime() public {
        rateLimiter.recordExecution(vault, 1);
        uint256 lastExecution = rateLimiter.getLastExecutionTime(vault, 1);
        assertEq(lastExecution, block.timestamp);
    }

    function test_MultipleVaultsIndependent() public {
        rateLimiter.setExecutionLimitPerDay(vault, 5);
        rateLimiter.setExecutionLimitPerDay(vault2, 10);
        
        assertEq(rateLimiter.executionLimitPerDay(vault), 5);
        assertEq(rateLimiter.executionLimitPerDay(vault2), 10);
    }

    function test_InvalidVaultAddressRejected() public {
        vm.expectRevert("Invalid vault address");
        rateLimiter.setExecutionLimitPerDay(address(0), 5);
    }

    function test_ZeroLimitRejected() public {
        vm.expectRevert("Limit must be greater than zero");
        rateLimiter.setExecutionLimitPerDay(vault, 0);
    }

    function test_RecordExecutionWithInvalidVault() public {
        vm.expectRevert("Invalid vault address");
        rateLimiter.recordExecution(address(0), 1);
    }
}
