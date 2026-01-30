pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/IntentVault.sol";

contract IntentVaultTest is Test {
    IntentVault vault;
    address owner;
    address protocol1;
    address protocol2;
    address tokenA;

    function setUp() public {
        owner = address(this);
        protocol1 = address(0x1111);
        protocol2 = address(0x2222);
        tokenA = address(0x3333);

        vault = new IntentVault(address(0x1234)); // Mock entryPoint
    }

    function test_OwnerIsSet() public {
        assertEq(vault.owner(), owner);
    }

    function test_SetSpendingCap() public {
        vault.setSpendingCap(tokenA, 1000e18);
        assertEq(vault.getSpendingCap(tokenA), 1000e18);
    }

    function test_GetRemainingSpendingCap() public {
        vault.setSpendingCap(tokenA, 1000e18);
        assertEq(vault.getRemainingSpendingCap(tokenA), 1000e18);
    }

    function test_ApproveProtocol() public {
        vault.approveProtocol(protocol1);
        assertEq(vault.isApprovedProtocol(protocol1), true);
    }

    function test_RevokeProtocol() public {
        vault.approveProtocol(protocol1);
        vault.revokeProtocol(protocol1);
        assertEq(vault.isApprovedProtocol(protocol1), false);
    }

    function test_PauseVault() public {
        assertEq(vault.isPaused(), false);
        vault.pause();
        assertEq(vault.isPaused(), true);
    }

    function test_UnpauseVault() public {
        vault.pause();
        vault.unpause();
        assertEq(vault.isPaused(), false);
    }

    function test_RecordSpendingReturnsError() public {
        vault.approveProtocol(protocol1);
        vault.setSpendingCap(tokenA, 100e18);
        
        vm.prank(protocol1);
        vault.recordSpending(tokenA, 50e18);
        assertEq(vault.getRemainingSpendingCap(tokenA), 50e18);
    }

    function test_CannotRecordSpendingWhenPaused() public {
        vault.approveProtocol(protocol1);
        vault.setSpendingCap(tokenA, 100e18);
        vault.pause();
        
        vm.prank(protocol1);
        vm.expectRevert("Vault is paused");
        vault.recordSpending(tokenA, 50e18);
    }

    function test_CannotRecordSpendingFromUnauthorizedProtocol() public {
        vault.setSpendingCap(tokenA, 100e18);
        
        vm.prank(protocol1);
        vm.expectRevert("Protocol not approved");
        vault.recordSpending(tokenA, 50e18);
    }

    function test_CannotExceedSpendingCap() public {
        vault.approveProtocol(protocol1);
        vault.setSpendingCap(tokenA, 100e18);
        
        vm.prank(protocol1);
        vault.recordSpending(tokenA, 100e18);
        
        vm.prank(protocol1);
        vm.expectRevert("Spending cap exceeded");
        vault.recordSpending(tokenA, 1e18);
    }

    function test_ResetSpendingTracker() public {
        vault.approveProtocol(protocol1);
        vault.setSpendingCap(tokenA, 100e18);
        
        vm.prank(protocol1);
        vault.recordSpending(tokenA, 50e18);
        
        assertEq(vault.getRemainingSpendingCap(tokenA), 50e18);
        vault.resetSpendingTracker(tokenA);
        assertEq(vault.getRemainingSpendingCap(tokenA), 100e18);
    }

    function test_OnlyOwnerCanPause() public {
        vm.prank(protocol1);
        vm.expectRevert("Only owner");
        vault.pause();
    }

    function test_OnlyOwnerCanApproveProtocol() public {
        vm.prank(protocol1);
        vm.expectRevert("Only owner");
        vault.approveProtocol(protocol2);
    }

    function test_ExecuteAsEntryPoint() public {
        // Mock entryPoint
        address entryPoint = address(0x1234);
        vm.prank(entryPoint);
        vault.execute(address(0x5678), 0, abi.encodeWithSignature("someFunc()"));
        // Since it's a mock, just check no revert
    }

    function test_ExecuteBatch() public {
        address entryPoint = address(0x1234);
        address[] memory dest = new address[](1);
        uint256[] memory value = new uint256[](1);
        bytes[] memory func = new bytes[](1);
        dest[0] = address(0x5678);
        value[0] = 0;
        func[0] = abi.encodeWithSignature("someFunc()");

        vm.prank(entryPoint);
        vault.executeBatch(dest, value, func);
    }
}
