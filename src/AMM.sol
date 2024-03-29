// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

interface IFactory {
    function getExchange(address _tokenAddress) external returns (address);
}

interface IExchange {
    function ethToTokenSwap(uint256 _minTokens) external payable;

    function ethToTokenTransfer(uint256 _minTokens, address _recipient) external payable;
}

import "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/contracts/utils/math/SafeMath.sol";

contract AMM is ERC20 {
    address public tokenAddress;
    address public factoryAddress;

    error AddressZero();
    error InvalidReserves();
    error InvalidInputAmount();
    error InsufficientOutputAmount();
    error InvalidExchangeAddress();

    constructor(address tokenAddress_) ERC20("LuniSwap-V1", "LUNI-V1") {
        if (tokenAddress_ == address(0)) revert AddressZero();

        tokenAddress = tokenAddress_;
        factoryAddress = msg.sender;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          SETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev this function serves for adding liquidity to the pool either in ether or in tokenAddress
     * @param tokenAmount_ the amount of token to add to the liquidity pool (contract)
     */
    function addLiquidity(uint256 tokenAmount_) external payable returns (uint256) {
        if (getReserve() == 0) {
            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), tokenAmount_);

            uint256 liquidity = address(this).balance;
            _mint(msg.sender, liquidity);
            return liquidity;
        } else {
            uint256 ethReserve = address(this).balance - msg.value;
            uint256 tokenReserve = getReserve();
            uint256 tokenAmount = (msg.value * tokenReserve) / ethReserve;
            if (tokenAmount_ < tokenAmount) revert InvalidInputAmount();

            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), tokenAmount);

            uint256 liquidity = (totalSupply() * msg.value) / ethReserve;
            _mint(msg.sender, liquidity);

            return liquidity;
        }
    }

    function removeLiquidity(uint256 amount_) external returns (uint256, uint256) {
        if (amount_ == 0) revert InvalidInputAmount();

        uint256 ethAmount = (address(this).balance * amount_) / totalSupply();
        uint256 tokenAmount = (getReserve() * amount_) / totalSupply();

        _burn(msg.sender, amount_);

        payable(msg.sender).transfer(ethAmount);
        IERC20(tokenAddress).transfer(msg.sender, amount_);

        return (ethAmount, tokenAmount);
    }

    function ethToTokenSwap(uint256 _minTokens) external payable {
        ethToToken(_minTokens, msg.sender);
    }

    function ethToTokenTransfer(uint256 _minTokens, address _recipient) external payable {
        ethToToken(_minTokens, _recipient);
    }
    // For gas better private || internal

    function tokenToEthSwap(uint256 _tokensSold, uint256 _minEth) public {
        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(_tokensSold, tokenReserve, address(this).balance);

        if (ethBought < _minEth) revert InsufficientOutputAmount();

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), _tokensSold);
        payable(msg.sender).transfer(ethBought);
    }

    function tokenToTokenSwap(uint256 tokensSold_, uint256 minTokensBought_, address tokenAddress_) external {
        address exchangeAddress = IFactory(factoryAddress).getExchange(tokenAddress_);
        if (exchangeAddress == address(this) && exchangeAddress == address(0)) revert InvalidExchangeAddress();

        uint256 tokenReserve = getReserve();
        uint256 ethBought = getAmount(tokensSold_, tokenReserve, address(this).balance);

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), tokensSold_);

        IExchange(exchangeAddress).ethToTokenTransfer{ value: ethBought }(minTokensBought_, msg.sender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getReserve() public view returns (uint256 tokenBalance_) {
        uint256 tokenBalance = IERC20(tokenAddress).balanceOf(address(this));
        return tokenBalance;
    }

    function getPrice(uint256 inputReserve, uint256 outputReserve) public pure returns (uint256) {
        if (inputReserve == 0 && outputReserve == 0) revert InvalidReserves();
        return (inputReserve * 1000) / outputReserve;
    }

    function getTokenAmount(uint256 ethSold_) public view returns (uint256) {
        if (ethSold_ == 0) revert InvalidInputAmount();

        uint256 tokenReserve = getReserve();

        return getAmount(ethSold_, address(this).balance, tokenReserve);
    }

    function getEthAmount(uint256 tokenSold_) public view returns (uint256) {
        if (tokenSold_ == 0) revert InvalidInputAmount();

        return getAmount(tokenSold_, getReserve(), address(this).balance);
    }

    function ethToToken(uint256 _minTokens, address recipient) private {
        uint256 tokenReserve = getReserve();
        uint256 tokensBought = getAmount(msg.value, address(this).balance - msg.value, tokenReserve);

        if (tokensBought < _minTokens) revert InsufficientOutputAmount();

        IERC20(tokenAddress).transfer(recipient, tokensBought);
    }

    function getAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    )
        private
        pure
        returns (uint256)
    {
        if (inputReserve == 0 && outputReserve == 0) revert InvalidReserves();

        uint256 inputAmountWithFee = inputAmount * 99;
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;

        return numerator / denominator;
    }
}
