// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPayable} from "@reactive/src/interfaces/IPayable.sol";

/// @title SafeSweepVault
/// @notice Holds native funds and evacuates them to an immutable safe wallet after
///         an authenticated Reactive Network callback.
contract SafeSweepVault {
    error NotAuthorized(address sender, address provider);
    error CallbackNotAuthorized(address sender, address expectedSender);
    error FeesRequireReserve();
    IPayable public immutable _SERVICE_PROVIDER;
    address public immutable _CALLBACK_SENDER;
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
        payable {
        if (
            address(callbackProxy_) == address(0) || guardian_ == address(0) || safeWallet_ == address(0)
                || reactiveContract_ == address(0)
        ) revert ZeroAddress();

        _SERVICE_PROVIDER = callbackProxy_;
        _CALLBACK_SENDER = reactiveContract_;
        guardian = guardian_;
        safeWallet = safeWallet_;

        if (msg.value > 0) emit Deposited(msg.sender, msg.value);
    }

    receive() external payable {
        if (swept) revert AlreadySwept();
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Callback fees must be prepaid at the proxy.
    function pay(uint256 amount) external view {
        if (msg.sender != address(_SERVICE_PROVIDER)) revert NotAuthorized(msg.sender, address(_SERVICE_PROVIDER));
        if (amount != 0) revert FeesRequireReserve();
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
    function sweep(address reactive_, bytes32 incidentId_) external {
        if (msg.sender != address(_SERVICE_PROVIDER)) revert NotAuthorized(msg.sender, address(_SERVICE_PROVIDER));
        if (reactive_ != _CALLBACK_SENDER) revert CallbackNotAuthorized(reactive_, _CALLBACK_SENDER);
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
