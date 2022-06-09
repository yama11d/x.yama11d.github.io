// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IErc20 {
    function decimals() external pure returns(uint8);
    function balanceOf(address) external view returns(uint256);
    function transfer(address, uint256) external returns(bool);
    function approve(address, uint256) external returns(bool);
    function transferFrom(address, address, uint256) external returns(bool);
}

struct UniswapExactInputSingle {
    address _0;
    address _1;
    uint24 _2;
    address _3;
    uint256 _4;
    uint256 _5;
    uint256 _6;
    uint160 _7;
}

interface IUniswapQuoter {
    function quoteExactInputSingle(address, address, uint24, uint256, uint160) external returns(uint256);
}

interface IUniswapRouter {
    function exactInputSingle(UniswapExactInputSingle calldata) external returns(uint256);
}

interface ICurvePool {
    function get_dy(int128, int128, uint256) external view returns(uint256);
    function exchange(int128, int128, uint256, uint256) external returns(uint256);
}

struct JarvisMint {
    address _0;
    uint256 _1;
    uint256 _2;
    uint256 _3;
    uint256 _4;
    address _5;
}

interface IJarvisPool {
    function mint(JarvisMint calldata) external returns(uint256, uint256);
    function redeem(JarvisMint calldata) external returns(uint256, uint256);
    function calculateFee(uint256) external view returns(uint256);
    function getPriceFeedIdentifier() external view returns(bytes32);
}

interface IJarvisAggregator {
    function latestRoundData() external view returns(uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns(uint8);
}

contract ParArbitrage {
    IErc20 internal constant par = IErc20(0xE2Aa7db6dA1dAE97C5f5C6914d285fBfCC32A128);
    IErc20 internal constant jeur = IErc20(0x4e3Decbb3645551B8A19f0eA1678079FCB33fB4c);
    IErc20 internal constant usdc = IErc20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IUniswapQuoter internal constant quoterUniswap = IUniswapQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IUniswapRouter internal constant routerUniswap = IUniswapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    ICurvePool internal constant poolCurve = ICurvePool(0xAd326c253A84e9805559b73A08724e11E49ca651);
    IJarvisPool internal constant poolJarvis = IJarvisPool(0xCbbA8c0645ffb8aA6ec868f6F5858F2b0eAe34DA);
    IJarvisAggregator internal constant aggregatorJarvis = IJarvisAggregator(0x73366Fe0AA0Ded304479862808e02506FE556a98);
    address internal constant derivativeJarvis = 0x0Fa1A6b68bE5dD9132A09286a166d75480BE9165;
    constructor() {
        par.approve(address(routerUniswap), type(uint256).max);
        par.approve(address(poolCurve), type(uint256).max);
        jeur.approve(address(poolCurve), type(uint256).max);
        jeur.approve(address(poolJarvis), type(uint256).max);
        usdc.approve(address(routerUniswap), type(uint256).max);
        usdc.approve(address(poolJarvis), type(uint256).max);
    }
    function checkArbitrage(uint256 amount) public returns(uint256, uint256) {
        if(rateJeurToUsdc(rateParToJeur(rateUsdcToPar(amount))) >= rateParToUsdc(rateJeurToPar(rateUsdcToJeur(amount)))) {
            return (rateJeurToUsdc(rateParToJeur(rateUsdcToPar(amount))), 0);
        }
        return (rateParToUsdc(rateJeurToPar(rateUsdcToJeur(amount))), 1);
    }
    function arbitrage(uint256 amount, uint256 minimum, uint256 route, uint256 loop) public {
        uint256 balance;
        uint256 profitOld;
        uint256 profit;
        balance = usdc.balanceOf(msg.sender);
        usdc.transferFrom(msg.sender, address(this), amount);
        profitOld = 0;
        while(loop > 0) {
            try ParArbitrage(this).exchange(amount, route) {
            }
            catch {
                break;
            }
            profit = usdc.balanceOf(address(this)) - amount;
            amount += profit;
            if(profit <= profitOld / 2) {
                break;
            }
            profitOld = profit;
            loop--;
        }
        require(amount >= minimum);
        usdc.transfer(msg.sender, amount);
        require(usdc.balanceOf(msg.sender) >= balance);
    }
    function exchange(uint256 amount, uint256 route) external {
        if(route == 0) {
            exchangeUsdcToPar();
            exchangeParToJeur();
            exchangeJeurToUsdc();
        }
        else if(route == 1) {
            exchangeUsdcToJeur();
            exchangeJeurToPar();
            exchangeParToUsdc();
        }
        require(usdc.balanceOf(address(this)) >= amount);
    }
    function rateParToUsdc(uint256 amount) public returns(uint256) {
        return quoterUniswap.quoteExactInputSingle(address(par), address(usdc), 500, amount, 0);
    }
    function exchangeParToUsdc() public {
        routerUniswap.exactInputSingle(UniswapExactInputSingle(address(par), address(usdc), 500, address(this), block.timestamp, par.balanceOf(address(this)), 0, 0));
    }
    function rateUsdcToPar(uint256 amount) public returns(uint256) {
        return quoterUniswap.quoteExactInputSingle(address(usdc), address(par), 500, amount, 0);
    }
    function exchangeUsdcToPar() public {
        routerUniswap.exactInputSingle(UniswapExactInputSingle(address(usdc), address(par), 500, address(this), block.timestamp, usdc.balanceOf(address(this)), 0, 0));
    }
    function rateJeurToPar(uint256 amount) public view returns(uint256) {
        return poolCurve.get_dy(0, 1, amount);
    }
    function exchangeJeurToPar() public {
        poolCurve.exchange(0, 1, jeur.balanceOf(address(this)), 0);
    }
    function rateParToJeur(uint256 amount) public view returns(uint256) {
        return poolCurve.get_dy(1, 0, amount);
    }
    function exchangeParToJeur() public {
        poolCurve.exchange(1, 0, par.balanceOf(address(this)), 0);
    }
    function rateUsdcToJeur(uint256 amount) public view returns(uint256) {
        int256 a;
        (, a, , , ) = aggregatorJarvis.latestRoundData();
        return ((amount * amount / (amount + poolJarvis.calculateFee(amount))) * (10 ** jeur.decimals()) / (10 ** usdc.decimals())) * (10 ** aggregatorJarvis.decimals()) / uint256(a);
    }
    function exchangeUsdcToJeur() public {
        poolJarvis.mint(JarvisMint(derivativeJarvis, 0, usdc.balanceOf(address(this)), 2000000000000000, block.timestamp, address(this)));
    }
    function rateJeurToUsdc(uint256 amount) public view returns(uint256) {
        int256 a;
        (, a, , , ) = aggregatorJarvis.latestRoundData();
        return ((amount - poolJarvis.calculateFee(amount)) * (10 ** usdc.decimals()) / (10 ** jeur.decimals())) * uint256(a) / (10 ** aggregatorJarvis.decimals());
    }
    function exchangeJeurToUsdc() public {
        poolJarvis.redeem(JarvisMint(derivativeJarvis, jeur.balanceOf(address(this)), 0, 2000000000000000, block.timestamp, address(this)));
    }
}
