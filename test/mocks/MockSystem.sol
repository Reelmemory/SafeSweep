// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

contract MockSystem is ISystemContract {
    event CallbackRequest(
        uint256 indexed chainId,
        address indexed sender,
        address indexed recipient,
        CallbackVersion version,
        bytes configuration
    );

    struct CallbackRecord {
        uint256 blockNumber;
        address reactiveContract;
        uint256 callbackIndex;
        uint256 chainId;
        uint256 destinationTxHash;
        bytes err;
    }

    mapping(address => uint256) public override debt;
    mapping(address => uint256) public reserves;

    address public lastSubscriber;
    uint256 public lastSubscriptionChainId;
    address public lastSubscriptionContract;
    uint256 public lastSubscriptionTopic0;
    uint256 public lastSubscriptionTopic1;
    uint256 public lastSubscriptionTopic2;
    uint256 public lastSubscriptionTopic3;

    uint256 public callbackCount;
    address public lastCallbackRequester;
    uint256 public lastCallbackChainId;
    address public lastCallbackRecipient;
    uint64 public lastCallbackGasLimit;
    bytes public lastCallbackPayload;
    uint256 public deliveredCallbackTxHash;

    receive() external payable {}

    function depositTo(address account_) external payable {
        reserves[account_] += msg.value;
    }

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external override {
        lastSubscriber = msg.sender;
        lastSubscriptionChainId = chainId_;
        lastSubscriptionContract = contract_;
        lastSubscriptionTopic0 = topic0_;
        lastSubscriptionTopic1 = topic1_;
        lastSubscriptionTopic2 = topic2_;
        lastSubscriptionTopic3 = topic3_;
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external pure override {}

    function requestCallback(CallbackVersion version_, bytes memory config_) external override {
        require(version_ == CallbackVersion.V_1_0, "unsupported callback version");
        CallbackConfiguration_V_1_0 memory config = abi.decode(config_, (CallbackConfiguration_V_1_0));
        _record(config);
    }

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external override {
        _record(config_);
    }

    function setDeliveredCallbackTx(uint256 txHash_) external {
        deliveredCallbackTxHash = txHash_;
    }

    function getCallbacks(uint256) external view returns (CallbackRecord[] memory callbacks_) {
        if (deliveredCallbackTxHash == 0) return new CallbackRecord[](0);

        callbacks_ = new CallbackRecord[](1);
        callbacks_[0] = CallbackRecord({
            blockNumber: block.number,
            reactiveContract: lastCallbackRequester,
            callbackIndex: 0,
            chainId: lastCallbackChainId,
            destinationTxHash: deliveredCallbackTxHash,
            err: new bytes(0)
        });
    }

    function _record(CallbackConfiguration_V_1_0 memory config_) internal {
        emit CallbackRequest(config_.chainId, msg.sender, config_.recipient, CallbackVersion.V_1_0, abi.encode(config_));
        callbackCount++;
        lastCallbackRequester = msg.sender;
        lastCallbackChainId = config_.chainId;
        lastCallbackRecipient = config_.recipient;
        lastCallbackGasLimit = config_.gasLimit;
        lastCallbackPayload = config_.payload;
    }
}
