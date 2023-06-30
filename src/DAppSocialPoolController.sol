// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./Ownable.sol";

interface IDAppSocialPoolModel {
    function depositNative() external payable;
    function depositTokens(address tokenAddress, uint256 amount) external;
    function withdrawNative(uint256 amount) external;
    function withdrawTokens(address tokenAddress, uint256 amount) external;
    function withdrawNativeWithAlt(address from, uint256 amount) external;
    function withdrawTokensWithAlt(address tokenAddress, address from, uint256 amount) external;
    function transferNative(address from, address to, uint256 amount) external;
    function transferTokens(address tokenAddress, address from, address to, uint256 amount, bool isWalletTransfer) external;
    function transferPendingTokens(address tokenAddress, address from, address to, uint256 amount) external;
    function transferETH(address from, address to, uint256 amount, uint256 feeAmount) external;
    function transferPendingETH(address from, address to, uint256 amount, uint256 feeAmount) external;
    function holdNative(address fromAddress, uint256 amount) external;
    function holdNativeWithFee(address from, uint256 amount, uint256 feeAmount) external;
    function releaseNative(address fromAddress, uint256 amount) external;
    function holdTokens(address tokenAddress, address fromAddress, uint256 amount) external;
    function holdTokensWithFee(address tokenAddress, address from, uint256 amount, uint256 feeAmount) external;
    function releaseTokens(address tokenAddress, address fromAddress, uint256 amount) external;
    function getTokenBalances(address tokenAddress, address account) external;
    function getNativeBalances(address account) external;
}

contract DAppSocialPoolController is Ownable {

    mapping (address => bool) _supportedTokens;
    mapping (address => bool) _adminList;

    mapping (address => mapping(uint256 => uint256)) _sourceRecords; // Address => Id => Amount
    mapping (address => mapping(uint256 => uint256)) _targetRecords; // Address => Id => Amount
    mapping (address => mapping(uint256 => bool)) _deliveryMethods;

    bool private _isCrossXRunning;

    event TokenSwapRequested(address indexed tokenAddress, address indexed fromAddress, uint256 amount);
    event TokenSwapAccepted(address indexed tokenAddress, address indexed fromAddress, address toAddress, uint256 amount);
    event TokenSwapCancelled(address indexed tokenAddress, address indexed fromAddress, uint256 amount);
    event TokenSwapCompleted(address indexed tokenAddress, address indexed fromAddress, address toAddress, uint256 amount);
    event AdminAddressAdded(address indexed oldAdderess, bool flag);
    event AdminAddressRemoved(address indexed oldAdderess, bool flag);
    event TokenSupportAdded(address indexed, bool);
    event TokenSupportRemoved(address indexed, bool);

    error InvalidRecord();

    IDAppSocialPoolModel poolModel;

    constructor(address modelAddress) {
        _adminList[msg.sender] = true;
        poolModel = IDAppSocialPoolModel(modelAddress);
    }

    modifier adminOnly() {
        require(_adminList[msg.sender], "only Admin action");
        _;
    }

    modifier crossXRunning() {
        require(_isCrossXRunning == true, "CrossX is not running");
        _;
    }

    modifier validRecord(uint256 value) {
        if (value == 0) revert InvalidRecord();
        _;
    }

    function setCrossXOpen(bool isOpen) external onlyOwner {
        _isCrossXRunning = isOpen;
    }

    function setPoolModel(address newModel) external onlyOwner {
        poolModel = IDAppSocialPoolModel(newModel);
    }

    function addSupportedToken(address tokenAddress) external onlyOwner {
        _supportedTokens[tokenAddress] = true;
        emit TokenSupportAdded(tokenAddress, true);
    }

    function removeSupportedToken(address tokenAddress) external onlyOwner {
        _supportedTokens[tokenAddress] = false;
        emit TokenSupportRemoved(tokenAddress, false);
    }

    function addAdmin(address newAddress) external onlyOwner{
        require(!_adminList[newAddress], "Address is already Admin");
        _adminList[newAddress] = true;
        emit AdminAddressAdded(newAddress, true);
    }

    function removeAdmin(address oldAddress) external onlyOwner {
        require(_adminList[oldAddress], "The Address is not admin");
        _adminList[oldAddress] = false;
        emit AdminAddressRemoved(oldAddress, false);
    }

    function requestTokens(uint256 id, address tokenAddress, uint256 amount, uint256 feeAmount) external crossXRunning {
        require(_supportedTokens[tokenAddress], "Token is not supported");
        require(amount > 0, "Amount should be greater than 0");
        _sourceRecords[msg.sender][id] = amount;
        poolModel.holdTokensWithFee(tokenAddress, msg.sender, amount, feeAmount);
        emit TokenSwapRequested(tokenAddress, msg.sender, amount);
    }

    // Create a record for accept on Target
    function createTgtRecord(uint256 id, address tokenAddress, address toAddress, uint256 amount, bool isWalletTransfer) external adminOnly {
        require(_supportedTokens[tokenAddress], "Token is not supported");
        _targetRecords[toAddress][id] = amount;
        if (isWalletTransfer) {
            _deliveryMethods[toAddress][id] = isWalletTransfer;
        }
        emit TokenSwapRequested(tokenAddress, toAddress, amount);
    }

    function acceptRequest(uint256 id, address tokenAddress, address toAddress) external crossXRunning validRecord(_targetRecords[toAddress][id]) {
        uint256 amount = _targetRecords[toAddress][id];
        poolModel.transferTokens(tokenAddress, msg.sender, toAddress, amount, _deliveryMethods[toAddress][id]);
        _targetRecords[toAddress][id] = 0;
        emit TokenSwapAccepted(tokenAddress, msg.sender, toAddress, amount);
    }

    function updateSrcAmount(uint256 id, address tokenAddress, address fromAddress, address toAddress, uint256 amount) external adminOnly validRecord(_sourceRecords[fromAddress][id]) {
        poolModel.transferPendingTokens(tokenAddress, fromAddress, toAddress, amount);
        _sourceRecords[fromAddress][id] = 0;
        emit TokenSwapCompleted(tokenAddress, fromAddress, toAddress, amount);
    }

    function cancelSrcRequest(uint256 id, address tokenAddress, address fromAddress, uint256 amount) external adminOnly validRecord(_sourceRecords[fromAddress][id]) {
        poolModel.releaseTokens(tokenAddress, fromAddress, amount);
        _sourceRecords[fromAddress][id] = 0;
        emit TokenSwapCancelled(tokenAddress, fromAddress, amount);
    }

    function cancelTgtRequest(uint256 id, address tokenAddress, address fromAddress, uint256 amount) external adminOnly validRecord(_targetRecords[fromAddress][id]) {
        _targetRecords[fromAddress][id] = 0;
        emit TokenSwapCancelled(tokenAddress, fromAddress, amount);
    }

}