// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SafeSweepReactive} from "../src/SafeSweepReactive.sol";
import {SafeSweepVault} from "../src/SafeSweepVault.sol";
import {MockSystem} from "./mocks/MockSystem.sol";
import {MockCallbackProxy} from "./mocks/MockCallbackProxy.sol";
import {RejectEther} from "./mocks/RejectEther.sol";
import {ReentrantSafeWallet} from "./mocks/ReentrantSafeWallet.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AbstractPayer} from "@reactive/src/base/AbstractPayer.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";

interface Vm {
    function deal(address account, uint256 newBalance) external;
    function prank(address msgSender) external;
    function expectRevert(bytes4 revertData) external;
    function expectRevert(bytes calldata revertData) external;
    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

contract SafeSweepTest {
    error AssertionFailed();

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 internal constant ORIGIN_CHAIN_ID = 11155111;
    uint256 internal constant DESTINATION_CHAIN_ID = 11155111;
    address internal constant GUARDIAN = address(0xBEEF);
    address payable internal constant SAFE_WALLET = payable(address(0xCAFE));
    bytes32 internal constant INCIDENT_ID = keccak256("safesweep-test-incident");

    MockSystem internal system;
    MockCallbackProxy internal callbackProxy;
    SafeSweepReactive internal reactive;
    SafeSweepVault internal vault;

    function setUp() public {
        MockSystem mockSystemImplementation = new MockSystem();
        vm.etch(SYSTEM, address(mockSystemImplementation).code);
        system = MockSystem(payable(SYSTEM));

        callbackProxy = new MockCallbackProxy();
        reactive = new SafeSweepReactive();
        vault = new SafeSweepVault(IPayable(payable(address(callbackProxy))), address(reactive), GUARDIAN, SAFE_WALLET);

        reactive.configure(ORIGIN_CHAIN_ID, address(vault), DESTINATION_CHAIN_ID, address(vault));
    }

    function testConfigureSubscribesToPanicEvent() public view {
        _assertEq(system.lastSubscriber(), address(reactive));
        _assertEq(system.lastSubscriptionChainId(), ORIGIN_CHAIN_ID);
        _assertEq(system.lastSubscriptionContract(), address(vault));
        _assertEq(system.lastSubscriptionTopic0(), reactive.PANIC_TOPIC_0());
    }

    function testConfigureRejectsZeroOriginChainId() public {
        SafeSweepReactive freshReactive = new SafeSweepReactive();
        vm.expectRevert(SafeSweepReactive.ZeroChainId.selector);
        freshReactive.configure(0, address(vault), DESTINATION_CHAIN_ID, address(vault));
    }

    function testConfigureRejectsZeroDestinationChainId() public {
        SafeSweepReactive freshReactive = new SafeSweepReactive();
        vm.expectRevert(SafeSweepReactive.ZeroChainId.selector);
        freshReactive.configure(ORIGIN_CHAIN_ID, address(vault), 0, address(vault));
    }

    function testConfigureIsOneShot() public {
        vm.expectRevert(SafeSweepReactive.AlreadyConfigured.selector);
        reactive.configure(ORIGIN_CHAIN_ID, address(vault), DESTINATION_CHAIN_ID, address(vault));
    }

    function testOnlyOwnerCanConfigureReactive() public {
        SafeSweepReactive freshReactive = new SafeSweepReactive();

        vm.prank(address(0xBAD));
        vm.expectRevert(SafeSweepReactive.NotOwner.selector);
        freshReactive.configure(ORIGIN_CHAIN_ID, address(vault), DESTINATION_CHAIN_ID, address(vault));
    }

    function testVaultAcceptsNativeDeposits() public {
        vm.deal(address(this), 1 ether);

        (bool ok,) = address(vault).call{value: 1 ether}("");

        _assertTrue(ok);
        _assertEq(address(vault).balance, 1 ether);
    }

    function testOnlyGuardianCanPanic() public {
        vm.expectRevert(SafeSweepVault.NotGuardian.selector);
        vault.panic(INCIDENT_ID);

        vm.prank(GUARDIAN);
        vault.panic(INCIDENT_ID);
    }

    function testPanicDoesNotMoveFunds() public {
        vm.deal(address(vault), 10 ether);
        uint256 safeBefore = SAFE_WALLET.balance;

        vm.prank(GUARDIAN);
        vault.panic(INCIDENT_ID);

        _assertEq(address(vault).balance, 10 ether);
        _assertEq(SAFE_WALLET.balance, safeBefore);
        _assertFalse(vault.swept());
    }

    function testGuardianCannotRedirectSafeWallet() public {
        address safeBefore = vault.safeWallet();

        vm.prank(GUARDIAN);
        vault.panic(INCIDENT_ID);

        _assertEq(vault.safeWallet(), safeBefore);
        _assertEq(vault.safeWallet(), SAFE_WALLET);
    }

    function testDirectSweepCallIsRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(callbackProxy))
        );
        vault.sweep(address(reactive), INCIDENT_ID);
    }

    function testDirectFeePaymentCallIsRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), address(callbackProxy))
        );
        vault.pay(1);
    }

    function testProtectedBalanceCannotBeSpentViaPublicCoverDebt() public {
        vm.deal(address(vault), 10 ether);
        callbackProxy.setDebt(address(vault), 1 ether);

        (bool ok,) = address(vault).call(abi.encodeWithSignature("coverDebt()"));

        _assertFalse(ok);
        _assertEq(address(vault).balance, 10 ether);
        _assertEq(callbackProxy.debt(address(vault)), 1 ether);
    }

    function testWrongReactiveSenderIsRejected() public {
        address wrongReactive = address(0xDEAD);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, wrongReactive, address(reactive))
        );
        callbackProxy.deliver(vault, wrongReactive, INCIDENT_ID);
    }

    function testAuthenticatedCallbackSweepsEntireBalance() public {
        vm.deal(address(vault), 10 ether);
        vm.deal(SAFE_WALLET, 1 ether);
        uint256 safeBefore = SAFE_WALLET.balance;

        callbackProxy.deliver(vault, address(reactive), INCIDENT_ID);

        _assertTrue(vault.swept());
        _assertEq(address(vault).balance, 0);
        _assertEq(SAFE_WALLET.balance, safeBefore + 10 ether);
    }

    function testSecondSweepIsRejected() public {
        vm.deal(address(vault), 10 ether);
        callbackProxy.deliver(vault, address(reactive), INCIDENT_ID);

        vm.expectRevert(SafeSweepVault.AlreadySwept.selector);
        callbackProxy.deliver(vault, address(reactive), INCIDENT_ID);
    }

    function testDepositsAfterSweepAreRejected() public {
        vm.deal(address(vault), 10 ether);
        callbackProxy.deliver(vault, address(reactive), INCIDENT_ID);
        vm.deal(address(this), 1 ether);

        (bool ok,) = address(vault).call{value: 1 ether}("");
        _assertFalse(ok);
        _assertEq(address(vault).balance, 0);
    }

    function testPanicAfterSweepIsRejected() public {
        vm.deal(address(vault), 10 ether);
        callbackProxy.deliver(vault, address(reactive), INCIDENT_ID);

        vm.prank(GUARDIAN);
        vm.expectRevert(SafeSweepVault.AlreadySwept.selector);
        vault.panic(INCIDENT_ID);
    }

    function testReactiveRequestsExpectedCallback() public {
        IReactive.LogRecord memory log_ = _panicLog(INCIDENT_ID);

        vm.prank(SYSTEM);
        reactive.react(log_);

        _assertEq(system.callbackCount(), 1);
        _assertEq(system.lastCallbackRequester(), address(reactive));
        _assertEq(system.lastCallbackChainId(), DESTINATION_CHAIN_ID);
        _assertEq(system.lastCallbackRecipient(), address(vault));
        _assertEq(uint256(system.lastCallbackGasLimit()), 350_000);
        _assertEq(
            keccak256(system.lastCallbackPayload()),
            keccak256(abi.encodeWithSignature("sweep(address,bytes32)", address(0), INCIDENT_ID))
        );
    }

    function testDuplicateReactiveLogRequestsOnlyOneCallback() public {
        IReactive.LogRecord memory log_ = _panicLog(INCIDENT_ID);

        vm.prank(SYSTEM);
        reactive.react(log_);
        vm.prank(SYSTEM);
        reactive.react(log_);

        _assertEq(system.callbackCount(), 1);
        bytes32 eventKey = keccak256(abi.encode(log_.chainId, log_.txHash, log_.logIndex));
        _assertTrue(reactive.processedEvents(eventKey));
    }

    function testUnexpectedReactiveLogFallsThroughWithoutCallback() public {
        IReactive.LogRecord memory log_ = _panicLog(INCIDENT_ID);
        log_.contractAddress = address(0x1234);

        vm.prank(SYSTEM);
        reactive.react(log_);

        _assertEq(system.callbackCount(), 0);
    }

    function testReactRejectsUnauthorizedCaller() public {
        IReactive.LogRecord memory log_ = _panicLog(INCIDENT_ID);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM));
        reactive.react(log_);
    }

    function testZeroReactiveAddressIsRejected() public {
        vm.expectRevert(SafeSweepVault.ZeroAddress.selector);
        new SafeSweepVault(IPayable(payable(address(callbackProxy))), address(0), GUARDIAN, SAFE_WALLET);
    }

    function testZeroGuardianIsRejected() public {
        vm.expectRevert(SafeSweepVault.ZeroAddress.selector);
        new SafeSweepVault(IPayable(payable(address(callbackProxy))), address(reactive), address(0), SAFE_WALLET);
    }

    function testZeroSafeWalletIsRejected() public {
        vm.expectRevert(SafeSweepVault.ZeroAddress.selector);
        new SafeSweepVault(IPayable(payable(address(callbackProxy))), address(reactive), GUARDIAN, payable(address(0)));
    }

    function testZeroCallbackProxyIsRejected() public {
        vm.expectRevert(SafeSweepVault.ZeroAddress.selector);
        new SafeSweepVault(IPayable(payable(address(0))), address(reactive), GUARDIAN, SAFE_WALLET);
    }

    function testRejectingSafeWalletRollsBackSweep() public {
        RejectEther rejector = new RejectEther();
        SafeSweepVault rejectingVault = new SafeSweepVault(
            IPayable(payable(address(callbackProxy))), address(reactive), GUARDIAN, payable(address(rejector))
        );
        vm.deal(address(rejectingVault), 10 ether);

        vm.expectRevert(SafeSweepVault.SweepFailed.selector);
        callbackProxy.deliver(rejectingVault, address(reactive), INCIDENT_ID);

        _assertFalse(rejectingVault.swept());
        _assertEq(address(rejectingVault).balance, 10 ether);
        _assertEq(address(rejector).balance, 0);
    }

    function testReentrantSafeWalletCannotSweepTwice() public {
        ReentrantSafeWallet recipient = new ReentrantSafeWallet();
        SafeSweepVault reentrantVault = new SafeSweepVault(
            IPayable(payable(address(callbackProxy))), address(reactive), GUARDIAN, payable(address(recipient))
        );
        recipient.configure(callbackProxy, reentrantVault, address(reactive), INCIDENT_ID);
        vm.deal(address(reentrantVault), 10 ether);

        callbackProxy.deliver(reentrantVault, address(reactive), INCIDENT_ID);

        _assertTrue(recipient.attemptedReentry());
        _assertTrue(reentrantVault.swept());
        _assertEq(address(reentrantVault).balance, 0);
        _assertEq(address(recipient).balance, 10 ether);
    }

    function _panicLog(bytes32 incidentId_) internal view returns (IReactive.LogRecord memory log_) {
        log_ = IReactive.LogRecord({
            chainId: ORIGIN_CHAIN_ID,
            contractAddress: address(vault),
            topic0: reactive.PANIC_TOPIC_0(),
            topic1: uint256(uint160(GUARDIAN)),
            topic2: uint256(incidentId_),
            topic3: 0,
            data: abi.encode(address(vault).balance),
            blockNumber: 100,
            opCode: 3,
            blockHash: uint256(keccak256("block")),
            txHash: uint256(keccak256("tx")),
            logIndex: 0
        });
    }

    function _assertTrue(bool value_) internal pure {
        if (!value_) revert AssertionFailed();
    }

    function _assertFalse(bool value_) internal pure {
        if (value_) revert AssertionFailed();
    }

    function _assertEq(address a_, address b_) internal pure {
        if (a_ != b_) revert AssertionFailed();
    }

    function _assertEq(uint256 a_, uint256 b_) internal pure {
        if (a_ != b_) revert AssertionFailed();
    }

    function _assertEq(bytes32 a_, bytes32 b_) internal pure {
        if (a_ != b_) revert AssertionFailed();
    }
}
