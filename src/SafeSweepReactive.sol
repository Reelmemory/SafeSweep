// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";

/// @title SafeSweepReactive
/// @notice Watches a SafeSweepVault PanicTriggered event and autonomously requests
///         a callback that evacuates the vault.
contract SafeSweepReactive is AbstractReactive {
    error NotOwner();
    error ZeroAddress();
    error ZeroChainId();
    error AlreadyConfigured();

    uint64 internal constant CALLBACK_GAS_LIMIT = 350_000;
    uint256 public constant PANIC_TOPIC_0 = uint256(keccak256("PanicTriggered(address,uint256,bytes32)"));

    address public immutable owner;
    bool public configured;
    uint256 public originChainId;
    address public originVault;
    uint256 public destinationChainId;
    address public callbackRecipient;
    /// @notice True once a unique origin log has requested its emergency callback.
    mapping(bytes32 => bool) public processedEvents;

    event Configured(
        uint256 indexed originChainId,
        address indexed originVault,
        uint256 indexed destinationChainId,
        address callbackRecipient
    );
    event SweepRequested(bytes32 indexed incidentId, uint256 indexed originTxHash, address indexed recipient);

    constructor() payable {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice One-time wiring step after the vault is deployed.
    function configure(
        uint256 originChainId_,
        address originVault_,
        uint256 destinationChainId_,
        address callbackRecipient_
    ) external onlyOwner {
        if (configured) revert AlreadyConfigured();
        if (originChainId_ == 0 || destinationChainId_ == 0) revert ZeroChainId();
        if (originVault_ == address(0) || callbackRecipient_ == address(0)) revert ZeroAddress();

        configured = true;
        originChainId = originChainId_;
        originVault = originVault_;
        destinationChainId = destinationChainId_;
        callbackRecipient = callbackRecipient_;

        // Emit before the external system call. If subscribe() reverts, the entire
        // transaction (including this log and state changes) is rolled back.
        emit Configured(originChainId_, originVault_, destinationChainId_, callbackRecipient_);

        SYSTEM.subscribe(originChainId_, originVault_, PANIC_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // Subscriptions should already filter the stream, but a reactive contract should
        // still fail closed without reverting on unrelated logs. Reverts are billable on
        // Reactive Network, so unexpected records simply fall through.
        if (!configured) return;
        if (log_.chainId != originChainId || log_.contractAddress != originVault) return;
        if (log_.topic0 != PANIC_TOPIC_0 || log_.opCode != 3) return;

        // A source log should produce at most one callback request. The network normally
        // delivers each matching log once, but explicit deduplication makes retries safe
        // and avoids paying for duplicate emergency callbacks.
        bytes32 eventKey = keccak256(abi.encode(log_.chainId, log_.txHash, log_.logIndex));
        if (processedEvents[eventKey]) return;
        processedEvents[eventKey] = true;

        // PanicTriggered(address indexed guardian, uint256 balance, bytes32 indexed incidentId)
        // topic1 = guardian, topic2 = incidentId, data = balance.
        bytes32 incidentId = bytes32(log_.topic2);

        bytes memory payload = abi.encodeWithSignature(
            "sweep(address,bytes32)",
            address(0), // Replaced by Reactive Network with address(this).
            incidentId
        );

        // Emitting first keeps checks-effects-interactions ordering. A failed
        // requestCallback call reverts this log together with the transaction.
        emit SweepRequested(incidentId, log_.txHash, callbackRecipient);

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: callbackRecipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    /// @notice Allows anyone to settle debt using this contract's existing balance.
    function coverDebt() external {
        _coverDebt();
    }
}
