// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";

/// @title SafeSweepVault
/// @notice Holds native funds and evacuates them to an immutable safe wallet after
///         an authenticated Reactive Network callback.
contract SafeSweepVault is AbstractCallback {
    error NotGuardian();
    error ZeroAddress();
    error SweepFailed();
    error AlreadySwept();

    address public immutable guardian;
    address payable public immutable safeWallet;
    bool public swept;

    event Deposited(address indexed from, uint256 amount);
    event PanicTriggered(address indexed guardian, uint256 balance, bytes32 indexed incidentId);
    event FundsSwept(
        address indexed safeWallet, uint256 amount, bytes32 indexed incidentId, address indexed reactiveContract
    );

    constructor(IPayable callbackProxy_, address reactiveContract_, address guardian_, address payable safeWallet_)
        payable
        AbstractCallback(callbackProxy_, reactiveContract_)
    {
        if (
            address(callbackProxy_) == address(0) || guardian_ == address(0) || safeWallet_ == address(0)
                || reactiveContract_ == address(0)
        ) revert ZeroAddress();

        guardian = guardian_;
        safeWallet = safeWallet_;

        if (msg.value > 0) emit Deposited(msg.sender, msg.value);
    }

    receive() external payable override {
        if (swept) revert AlreadySwept();
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice High-signal emergency trigger. It does not move funds itself.
    /// @dev Reactive Network observes this event and requests the callback.
    function panic(bytes32 incidentId_) external {
        if (msg.sender != guardian) revert NotGuardian();
        if (swept) revert AlreadySwept();

        emit PanicTriggered(msg.sender, address(this).balance, incidentId_);
    }

    /// @notice Called only through the destination chain callback proxy and only
    ///         when the callback originated from the configured reactive contract.
    /// @dev The first argument is overwritten by Reactive Network with the actual
    ///      reactive contract address.
    function sweep(address reactive_, bytes32 incidentId_) external onlyServiceProvider onlyCallbackSender(reactive_) {
        if (swept) revert AlreadySwept();

        swept = true;
        uint256 amount = address(this).balance;

        // Effects and incident evidence are recorded before the external call.
        // A failed transfer reverts both the state update and this event.
        emit FundsSwept(safeWallet, amount, incidentId_, reactive_);

        (bool ok,) = safeWallet.call{value: amount}("");
        if (!ok) revert SweepFailed();
    }
}
