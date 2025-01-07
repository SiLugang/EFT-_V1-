// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IETFv1} from "./interfaces/IETFv1.sol";//继承
import {FullMath} from "./libraries/FullMath.sol";//继承
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";//继承
import {ERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/ERC20.sol";//继承
import {SafeERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/utils/SafeERC20.sol";//继承
import {Ownable} from "@openzeppelin/contracts@5.1.0/access/Ownable.sol";//继承

contract ETFv1 is IETFv1, ERC20, Ownable {     //继承IETFv1，ERC20
    using SafeERC20 for IERC20;  //using for？
    using FullMath for uint256;

    uint24 public constant HUNDRED_PERCENT = 1000000; // 100%    //定义公开常量，1000000？

    address public feeTo; //定义公开地址
    uint24 public investFee;//定义公开变量，无符号24位：投资费用
    uint24 public redeemFee;//定义公开变量，无符号24位：redeemFee
    uint256 public minMintAmount;//定义公开变量，无符号256位：最小铸造总量

    address[] private _tokens;//定义地址字符串，私有：代币发行
    // Token amount required per 1 ETF share，used in the first invest
    uint256[] private _initTokenAmountPerShares;//定义私有数字数组，初始化账户代币金额每份

    constructor(     //构造函数
        string memory name_,//临时存储name_
        string memory symbol_,//临时存储symbol_
        address[] memory tokens_,//临时存储代币的地址
        uint256[] memory initTokenAmountPerShares_,//临时存储“初始化账户代币金额每份”
        uint256 minMintAmount_//无符号整数256，最小铸造总数
    ) ERC20(name_, symbol_) Ownable(msg.sender) {    //ERC20的（名字，symbol），ownable的发起地址
        _tokens = tokens_;//token的转换
        _initTokenAmountPerShares = initTokenAmountPerShares_;//开启“初始化账户代币金额每份”
        minMintAmount = minMintAmount_;//转换
    }

    function setFee( //setFee费的函数
        address feeTo_, //定义地址
        uint24 investFee_, //定义投资费
        uint24 redeemFee_ //定义赎回费用
    ) external onlyOwner {  //外部可见（仅Owner）
        feeTo = feeTo_; //feeToo转换
        investFee = investFee_; //转换
        redeemFee = redeemFee_;  //转换
    }

    function updateMinMintAmount(uint256 newMinMintAmount) external onlyOwner {  //更新升级最小
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
