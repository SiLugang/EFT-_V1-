// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IETFv1} from "./interfaces/IETFv1.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";

contract ETFv1 is IETFv1, ERC20, Ownable {
    using SafeERC20 for IERC20;
    using FullMath for uint256;

    uint24 public constant HUNDRED_PERCENT = 1000000; // 100%

    address public feeTo;
    uint24 public investFee;
    uint24 public redeemFee;
    uint256 public minMintAmount;

    address[] private _tokens;
    // Token amount required per 1 ETF share，used in the first invest
    uint256[] private _initTokenAmountPerShares;

    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory tokens_,
        uint256[] memory initTokenAmountPerShares_,
        uint256 minMintAmount_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        _tokens = tokens_;
        _initTokenAmountPerShares = initTokenAmountPerShares_;
        minMintAmount = minMintAmount_;
    }

    function setFee(
        address feeTo_,
        uint24 investFee_,
        uint24 redeemFee_
    ) external onlyOwner {
        feeTo = feeTo_;
        investFee = investFee_;
        redeemFee = redeemFee_;
    }

    function updateMinMintAmount(uint256 newMinMintAmount) external onlyOwner {
        emit MinMintAmountUpdated(minMintAmount, newMinMintAmount);
        minMintAmount = newMinMintAmount;
    }

    // invest with all tokens, msg.sender need have approved all tokens to this contract
    function invest(address to, uint256 mintAmount) public {
        uint256[] memory tokenAmounts = _invest(to, mintAmount);
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (tokenAmounts[i] > 0) {
                IERC20(_tokens[i]).safeTransferFrom(
                    msg.sender,
                    address(this),
                    tokenAmounts[i]
                );
            }
        }
    }

    function redeem(address to, uint256 burnAmount) public {
        _redeem(to, burnAmount);
    }

    function getTokens() public view returns (address[] memory) {
        return _tokens;
    }

    function getInitTokenAmountPerShares()
        public
        view
        returns (uint256[] memory)
    {
        return _initTokenAmountPerShares;
    }

    function getInvestTokenAmounts(
        uint256 mintAmount
    ) public view returns (uint256[] memory tokenAmounts) {
        uint256 totalSupply = totalSupply();
        tokenAmounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (totalSupply > 0) {
                uint256 tokenReserve = IERC20(_tokens[i]).balanceOf(
                    address(this)
                );
                // tokenAmount / tokenReserve = mintAmount / totalSupply
                tokenAmounts[i] = tokenReserve.mulDivRoundingUp(
                    mintAmount,
                    totalSupply
                );
            } else {
                tokenAmounts[i] = mintAmount.mulDivRoundingUp(
                    _initTokenAmountPerShares[i],
                    1e18
                );
            }
        }
    }

    function getRedeemTokenAmounts(
        uint256 burnAmount
    ) public view returns (uint256[] memory tokenAmounts) {
        if (redeemFee > 0) {
            uint256 fee = (burnAmount * redeemFee) / HUNDRED_PERCENT;
            burnAmount -= fee;
        }

        uint256 totalSupply = totalSupply();
        tokenAmounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 tokenReserve = IERC20(_tokens[i]).balanceOf(address(this));
            // tokenAmount / tokenReserve = burnAmount / totalSupply
            tokenAmounts[i] = tokenReserve.mulDiv(burnAmount, totalSupply);
        }
    }

    function _invest(
        address to,
        uint256 mintAmount
    ) internal returns (uint256[] memory tokenAmounts) {
        if (mintAmount < minMintAmount) revert LessThanMinMintAmount();
        tokenAmounts = getInvestTokenAmounts(mintAmount);
        uint256 fee;
        if (investFee > 0) {
            fee = (mintAmount * investFee) / HUNDRED_PERCENT;
            _mint(feeTo, fee);
            _mint(to, mintAmount - fee);
        } else {
            _mint(to, mintAmount);
        }

        emit Invested(to, mintAmount, fee, tokenAmounts);
    }

    function _redeem(
        address to,
        uint256 burnAmount
    ) internal returns (uint256[] memory tokenAmounts) {
        uint256 totalSupply = totalSupply();
        tokenAmounts = new uint256[](_tokens.length);
        _burn(msg.sender, burnAmount);

        uint256 fee;
        if (redeemFee > 0) {
            fee = (burnAmount * redeemFee) / HUNDRED_PERCENT;
            _mint(feeTo, fee);
        }

        uint256 actuallyBurnAmount = burnAmount - fee;
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 tokenReserve = IERC20(_tokens[i]).balanceOf(address(this));
            tokenAmounts[i] = tokenReserve.mulDiv(
                actuallyBurnAmount,
                totalSupply
            );
            if (to != address(this) && tokenAmounts[i] > 0)
                IERC20(_tokens[i]).safeTransfer(to, tokenAmounts[i]);
        }

        emit Redeemed(msg.sender, to, burnAmount, fee, tokenAmounts);
    }

    /// use for v3
    function _addToken(address token) internal returns (uint256 index) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == token) revert TokenExists();
        }
        index = _tokens.length;
        _tokens.push(token);
        emit TokenAdded(token, index);
    }

    function _removeToken(address token) internal returns (uint256 index) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == token) {
                index = i;
                _tokens[i] = _tokens[_tokens.length - 1];
                _tokens.pop();
                emit TokenRemoved(token, index);
                return index;
            }
        }
        revert TokenNotFound();
    }
}
