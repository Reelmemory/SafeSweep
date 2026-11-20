// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {SafeSweepVault} from "../../src/SafeSweepVault.sol";

contract MockCallbackProxy is IPayable {
    mapping(address => uint256) public override debt;
    mapping(address => uint256) public reserves;

    receive() external payable {}

    function depositTo(address account_) external payable {
        reserves[account_] += msg.value;
    }

    function setDebt(address account_, uint256 amount_) external {
        debt[account_] = amount_;
    }

    function deliver(SafeSweepVault vault_, address reactive_, bytes32 incidentId_) external {
        vault_.sweep(reactive_, incidentId_);
    }
}
