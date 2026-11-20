// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {SafeSweepVault} from "../../src/SafeSweepVault.sol";
import {MockCallbackProxy} from "./MockCallbackProxy.sol";

contract ReentrantSafeWallet {
    MockCallbackProxy public callbackProxy;
    SafeSweepVault public vault;
    address public reactive;
    bytes32 public incidentId;
    bool public attemptedReentry;

    function configure(MockCallbackProxy callbackProxy_, SafeSweepVault vault_, address reactive_, bytes32 incidentId_)
        external
    {
        callbackProxy = callbackProxy_;
        vault = vault_;
        reactive = reactive_;
        incidentId = incidentId_;
    }

    receive() external payable {
        attemptedReentry = true;
        try callbackProxy.deliver(vault, reactive, incidentId) {} catch {}
    }
}
