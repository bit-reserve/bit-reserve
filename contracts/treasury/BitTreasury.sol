// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IBTR.sol";

/// @title   BTRtor Treasury
/// @notice  Treasury for BTRtor
/// @author  BTRtor
contract BitTreasury is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Bool if redemptions are active
    bool public redeemtionActive;

    /// @notice rBTC needed to back each BTR
    uint256 public constant RESERVE_BACKING = 0.000001 ether;

    /// @notice Percent of redeemable amount to receive
    uint256 public percentRedeemable;

    /// @notice Address of BTR
    address public immutable BTR;
    /// @notice Address of BTR/BTC
    address public immutable LP;
    /// @notice Address of rBTC
    address public rBTC;

    /// @notice Array of addresses of redeemable tokens
    address[] public redeemableTokens;

    /// @notice Bool if address is an approved sender
    mapping(address => bool) public approvedSender;
    /// @notice Bool if address is an approved minter
    mapping(address => bool) public approvedMinter;

    /// EVENTS ///

    event SetRedemtionActive();
    event SetRedeemableTokens(address[] _redeemableTokens);
    event ApprovedMinterAdded(address approvedMinter);
    event ApprovedMinterRemoved(address removedMinter);
    event ApprovedSenderAdded(address approvedSender);
    event ApprovedSenderRemoved(address removedSender);
    event rBTCUpdated(address oldrBTC, address newrBTC);

    /// CONSTRUCTOR ///

    constructor(address _BTR, address _rBTC) Ownable() {
        BTR = _BTR;
        rBTC = _rBTC;
        LP = IBTR(_BTR).uniswapV2Pair();
    }

    /// VIEW ///

    /// @notice         Returns excess reserves for BTR
    /// @return value_  Amount of excess reserves
    function excessReserves() public view returns (uint256 value_) {
        uint256 _balance = IERC20(rBTC).balanceOf(address(this));
        uint256 _value = (_balance * 1e18) / RESERVE_BACKING;
        if (IERC20(BTR).totalSupply() > _value) return 0;
        return (_value - IERC20(BTR).totalSupply());
    }

    /// @notice         Returns value of token in BTR deciamls
    /// @param _token   Token to get value for
    /// @param _amount  Amount of token to get value for
    /// @return value_  Value of `_amount` of `_token` in BTR decimals
    function valueOfToken(
        address _token,
        uint _amount
    ) external view returns (uint value_) {
        // convert amount to match BTR token decimals
        value_ =
            (_amount * 10 ** IBTR(BTR).decimals()) /
            10 ** IERC20Metadata(_token).decimals();
    }

    /// OWNABLE ///

    /// @notice  Set redemptions to active
    function setRedemtionActive(uint256 _percentRedeemable) external onlyOwner {
        require(_percentRedeemable < 100, "Invalid percentage");
        redeemtionActive = true;
        percentRedeemable = _percentRedeemable;
        emit SetRedemtionActive();
    }

    /// @notice         Set array of redeemable tokens
    /// @param _tokens  Array of redeemable tokens
    function setRedeemableTokens(
        address[] calldata _tokens
    ) external onlyOwner {
        redeemableTokens = _tokens;
        emit SetRedeemableTokens(_tokens);
    }

    /// @notice         Set address of approved minter
    /// @param _minter  Address of minter
    function addApprovedMinter(address _minter) external onlyOwner {
        approvedMinter[_minter] = true;
        emit ApprovedMinterAdded(_minter);
    }

    /// @notice         Remove address of approved minter
    /// @param _minter  Address of minter to remove
    function removeApprovedMinter(address _minter) external onlyOwner {
        approvedMinter[_minter] = false;
        emit ApprovedMinterRemoved(_minter);
    }

    /// @notice         Add an approved sender
    /// @param _sender  Address of sender to add
    function addApprovedSender(address _sender) external onlyOwner {
        approvedSender[_sender] = true;
        emit ApprovedSenderAdded(_sender);
    }

    /// @notice         Remove address of approved sender
    /// @param _sender  Address of sender to remove
    function removeApprovedSender(address _sender) external onlyOwner {
        approvedSender[_sender] = false;
        emit ApprovedSenderRemoved(_sender);
    }

    /// @notice       Update rBTC if for whatever reason need to update
    /// @param _rBTC  Address of new rBTC
    function updaterBTC(address _rBTC) external onlyOwner() {
        address _oldrBTC = rBTC;
        rBTC = _rBTC;
        emit rBTCUpdated(_oldrBTC, _rBTC);
    }

    /// MINTER ///

    /// @notice         Mint BTR
    /// @param _to      Where to mint BTR
    /// @param _amount  Amount of BTR to mint
    function mint(address _to, uint256 _amount) external {
        require(
            approvedMinter[msg.sender],
            "msg.sender is not approved minter"
        );
        require(excessReserves() >= _amount, "Too low excess reserves");
        IBTR(BTR).mint(_to, _amount);
    }

    /// APPROVED SENDER ///

    /// @notice         Transfer token from treasury
    /// @param _token   Address of token to transfer
    /// @param _to      Where to transfer `_token`
    /// @param _amount  Amount of `_token` to transfer
    function transferFromTreasury(
        address _token,
        address _to,
        uint256 _amount
    ) external {
        require(
            approvedSender[msg.sender],
            "msg.sender is not approved sender"
        );

        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// USER FUNCTIONS ///

    /// @notice         Burn BTR and redeem proportionate amount of treasury
    /// @param _amount  Amount of BTR to burn
    function burnAndRedeem(uint256 _amount) external {
        require(redeemtionActive, "Redeemtion Not Active");
        uint256 percent = (1e18 * _amount) / IERC20(BTR).totalSupply();
        IBTR(BTR).burnFrom(msg.sender, _amount);
        for (uint i; i < redeemableTokens.length; ++i) {
            uint256 tokenSupply = IERC20(redeemableTokens[i]).balanceOf(
                address(this)
            );
            uint256 toSend = (tokenSupply * percent) / 1e18;
            IERC20(redeemableTokens[i]).safeTransfer(
                msg.sender,
                (toSend * percentRedeemable) / 100
            );
        }
    }
}
