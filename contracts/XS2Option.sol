// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
// Used or inspired code from:
// - OpenZeppelin Contracts - SafeMath and ERC20
// - UniSwap V2 - _safeTransfer and _safeTransferFrom
// - Peter Murray - CloneFactory - EIP-1167
// - BookyPooBah - numToBytes

// DONE:
// Security: Evaluate any opportunity for reentrancy bugs
// Security: Figure out the safest way to call ERC20 transferFrom functions
// Testing: Setup
// Allow burning before expiry
// Setup github
// Use a single vault to store all assets and currency tokens.

// TODO:
// Gas: Reduce where safe
// Docs: Document every line in the contract
// Check: What if currency rebases
// Check: What if asset rebases
// Check: Get extreme decimal examples, does exercise work ok?

// Features for more complex versions:
// - Wipe balances after expiry?
// - A way to reset and reuse the contract?
// - Also create tokens for the issuer
// - Support rebasing tokens
// - Support tokens that give rewards in other tokens
// - Support staking of pooled assets
// - Support flash loans

// price: this is the price of 10^18 base units of asset (ignoring decimals) as expressed in base units of currency (also ignoring decimals)

// The frontend is responsible for making the simple calculation so the code can stay decimal agnostic and simple
// For example, the price of 1 CVC (has 8 decimals) in the currency DAI (18 decimals):
// 1 CVC = 0.0365 DAI
// 1 * 8^10 base units of CVC = 0.0365 DAI (CVC has 8 decimals)
// 1 * 8^10 base units of CVC = 0.0365 * 10^18 base units of DAI (DAI has 18 decimals)
// 1 * 18^10 base units of CVC = 0.0365 * 10^28 base units of DAI (Multiply by 10^10 in this case to get to 10^18 base units)
// Price = 0.0365 * 10^28 = 365000000000000000000000000

// Design decisions and rationale

// Use of block.timestamp
// While blocknumber is more 'exact', block.timestamp is easier to understand for users and more predictable
// So while it can be slightly manipulated by miners, this is not an issue on the timescales options operate at

// safeTransfer and safeTransferFrom
// These are based on the way this is done in Uniswap V2, which interacts with a wide variety of non-compliant tokens
// Compound uses a diffent way that includes inline assembly, but effectively they do the same thing

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) { uint256 c = a + b; require(c >= a, "XS2: Overflow"); return c; }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) { require(b <= a, "XS2: Underflow"); uint256 c = a - b; return c; }
    function mul(uint256 a, uint256 b) internal pure returns (uint256)
        { if (a == 0) {return 0;} uint256 c = a * b; require(c / a == b, "XS2: Overflow"); return c; }
    function div(uint256 a, uint256 b) internal pure returns (uint256) { require(b > 0, "XS2: Div by 0"); uint256 c = a / b; return c; }
}

interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function transfer(address to, uint256 amount) external;
}

interface Vault {
    function transfer(address token, address to, uint256 amount) external returns (bool);
    function transferFrom(address token, address from, uint256 amount) external returns (bool);
}

contract XS2Option {
    using SafeMath for uint256;

    uint256 public price;
    uint256 public expiry;

    uint8 constant DOT = 46;
    uint8 constant ZERO = 48;
    function numToBytes(uint number, uint8 decimals) internal pure returns (bytes memory b) {
        uint i;
        uint j;
        uint result;
        b = new bytes(40);
        if (number == 0) {
            b[j++] = byte(ZERO);
        } else {
            i = decimals + 18;
            do {
                uint num = number / 10 ** i;
                result = result * 10 + num % 10;
                if (result > 0) {
                    b[j++] = byte(uint8(num % 10 + ZERO));
                    if ((j > 1) && (number == num * 10 ** i) && (i <= decimals)) {
                        break;
                    }
                } else {
                    if (i == decimals) {
                        b[j++] = byte(ZERO);
                        b[j++] = byte(DOT);
                    }
                    if (i < decimals) {
                        b[j++] = byte(ZERO);
                    }
                }
                if (decimals != 0 && decimals == i && result > 0 && i > 0) {
                    b[j++] = byte(DOT);
                }
                i--;
            } while (i >= 0);
        }

        bytes memory out = new bytes(j);
        for (uint l = 0; l < j; l++)
        {
            out[l] = b[l];
        }
        return out;
    }

    function name() public pure returns(string memory) {
        return "XS2 Option";
    }

    function symbol() public view returns(string memory) {
        return string(abi.encodePacked(
            "xo", IERC20(asset).symbol(), ":", IERC20(currency).symbol(), " ",
            numToBytes(price, IERC20(currency).decimals())
            ));
    }

    function decimals() public pure returns(uint8) {
        return 18;
    }

    address vault;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function init(address vault_, address asset_, address currency_, uint256 price_, uint256 expiry_) public {
        require(vault == address(0), "Already initialized");
        vault = vault_;
        asset = asset_;
        currency = currency_;
        price = price_;
        expiry = expiry_;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
        balanceOf[recipient] = balanceOf[recipient].add(amount);
        emit Transfer(msg.sender, recipient, amount);

        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
        balanceOf[recipient] = balanceOf[recipient].add(amount);
        emit Transfer(msg.sender, recipient, amount);

        uint256 approval_amount = allowance[sender][msg.sender].sub(amount);
        allowance[sender][msg.sender] = approval_amount;
        emit Approval(sender, msg.sender, approval_amount);

        return true;
    }

    // Variables specific to options
    address public asset;
    address public currency;

    mapping(address => uint256) public issued;
    uint256 public totalIssued;
    uint256 public totalAsset;
    uint256 public totalCurrency;

    event Mint(address indexed by, uint256 amount);
    event Withdraw(address indexed by, uint256 amount);
    event Exercise(address indexed by, uint256 amount);
    event Swap(address indexed by, uint256 asset_amount);

    /**
     * @dev Mint options.
     * @param amount The amount to mint expressed in units of currency.
     */
    function mint(uint256 amount) public returns (bool) {
        // CHECKS
        // Check: Options are not yet expired (this isn't needed, but a nice to have)
        // solium-disable-next-line security/no-block-members
        require(block.timestamp < expiry, "XS2: Option expired");

        // Once any options have been exercised, no more options can be minted
        require(totalAsset == 0, "XS2: Some options exercised, minting disabled");

        // EFFECTS
        // Step 1. Receive amount base units of currency. This is held in the contract to be paid when the option is exercised.
        totalCurrency = totalCurrency.add(amount);

        // Step 2. Mint option tokens
        totalSupply = totalSupply.add(amount);
        balanceOf[msg.sender] = balanceOf[msg.sender].add(amount);

        // Step 3. Increase the issued balance
        totalIssued = totalIssued.add(amount);
        issued[msg.sender] = issued[msg.sender].add(amount);

        // INTERACTIONS
        // Step 1. Receive amount base units of currency. This is held in the contract to be paid when the option is exercised.
        Vault(vault).transferFrom(currency, msg.sender, amount);

        // EVENTS
        emit Mint(msg.sender, amount);
        emit Transfer(address(0), msg.sender, amount);

        return true;
    }

    /**
     * @dev Withdraw from the pool. Asset and currency are withdrawn to the proportion in which they are exercised.
     * @param amount The amount to withdraw expressed in units of the option.
     */
    function withdraw(uint256 amount) public returns (bool) {
        // CHECKS
        // Check: Options are expired
        // solium-disable-next-line security/no-block-members
        require(block.timestamp >= expiry, "XS2: Option not yet expired");

        // EFFECTS
        // Step 1. Give up your issued balance
        issued[msg.sender] = issued[msg.sender].sub(amount);
        uint256 totalIssuedPre = totalIssued;
        totalIssued = totalIssued.sub(amount);

        // Step 2. Receive your share of the currency pool
        uint256 currency_amount = (totalCurrency.mul(amount)).div(totalIssuedPre);
        if (currency_amount > 0) {
            totalCurrency = totalCurrency.sub(currency_amount);
        }

        // Step 3. Receive your share of the asset pool
        uint256 asset_amount = (totalAsset.mul(amount)).div(totalIssuedPre);
        if (asset_amount > 0) {
            totalAsset = totalAsset.sub(asset_amount);
        }

        // INTERACTIONS
        // Step 2. Receive your share of the currency pool
        if (currency_amount > 0) {
            Vault(vault).transfer(currency, msg.sender, currency_amount);
        }

        // Step 3. Receive your share of the asset pool
        if (asset_amount > 0) {
            Vault(vault).transfer(asset, msg.sender, asset_amount);
        }

        // EVENTS
        emit Withdraw(msg.sender, amount);

        return true;
    }

    /**
     * @dev Withdraw from the pool before expiry by returning the options.
     * In this case Assets are withdrawn first if available. Only currency is returned is assets run to 0.
     * @param amount The amount to withdraw expressed in units of the option.
     */
    function withdrawEarly(uint256 amount) public returns (bool) {
        // CHECKS
        // Check: Options are expired
        // solium-disable-next-line security/no-block-members
        require(block.timestamp < expiry, "XS2: Option not yet expired");

        // EFFECTS
        // Step 1. Burn the options
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
        totalSupply = totalSupply.sub(amount);

        // Step 2. Give up your issued balance
        issued[msg.sender] = issued[msg.sender].sub(amount);
        totalIssued = totalIssued.sub(amount);

        // Step 3. Receive from the asset pool
        uint256 asset_amount;
        uint256 currency_amount;

        if (totalAsset > 0) {
            // The amount fully in Assets
            asset_amount = (amount.mul(1e18)).div(price);

            // If there aren't enough Assets in the contract, use as much as possible and get the rest from currency
            if (asset_amount > totalAsset) {
                currency_amount = asset_amount.sub(amount).mul(price).div(1e18);
                asset_amount = totalAsset;
            }
            totalAsset = totalAsset.sub(asset_amount);
        }
        else {
            currency_amount = amount;
        }

        // Step 4. If not enough returned, receive remainder from the currency pool
        if (currency_amount > 0) {
            totalCurrency = totalCurrency.sub(currency_amount);
        }

        // INTERACTIONS
        // Step 2. Receive your share of the currency pool
        if (currency_amount > 0) {
            Vault(vault).transfer(currency, msg.sender, currency_amount);
        }

        // Step 3. Receive your share of the asset pool
        if (asset_amount > 0) {
            Vault(vault).transfer(asset, msg.sender, asset_amount);
        }

        // EVENTS
        emit Transfer(msg.sender, address(0), amount);
        emit Withdraw(msg.sender, amount);

        return true;
    }

    /**
     * @dev Exercise options.
     * @param amount The amount to exercise expressed in units of currency.
     */
    function exercise(uint256 amount) public returns (bool) {
        // CHECKS
        // Check: Options are not yet expired
        // solium-disable-next-line security/no-block-members
        require(block.timestamp < expiry, "XS2: Option has expired");

        // EFFECTS
        // Step 1. Give up your option tokens
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
        totalSupply = totalSupply.sub(amount);

        // Step 2. Transfer your assets into the contract
        uint256 asset_amount = (amount.mul(1e18)).div(price);
        totalAsset = totalAsset.add(asset_amount);

        // Step 3. Receive currency from the contract
        totalCurrency = totalCurrency.sub(amount);

        // INTERACTIONS
        // Step 2. Transfer your assets into the contract
        Vault(vault).transferFrom(asset, msg.sender, asset_amount);

        // Step 3. Receive currency from the contract
        Vault(vault).transfer(currency, msg.sender, amount);

        // EVENTS
        emit Transfer(msg.sender, address(0), amount);
        emit Exercise(msg.sender, amount);

        return true;
    }

    /**
     * @dev If some of the options are exercised, but the price of the asset goes back up, anyone can
     * swap the assets for the original currency. The main reason for this is that minted gets locked
     * once any option is exercised. When all assets are swapped back for currency, further minting
     * can happen again.
     * @param asset_amount The amount to swap. This is denominated in asset (NOT currency!) so it's always possible to swap ALL
     * assets, and rounding won't leave dust behind.
     */
    function swap(uint256 asset_amount) public returns (bool)
    {
        // EFFECTS
        // Step 1. Transfer your currency into the contract
        // We add 1 so that there is never a rounding benefit for the person calling swap
        uint256 currency_amount = (asset_amount.mul(price)).div(1e18) + 1;
        totalCurrency = totalCurrency.add(currency_amount);

        // Step 2. Receive assets from the contract
        totalAsset = totalAsset.sub(asset_amount);

        // INTERACTIONS
        // Step 1. Transfer your currency into the contract
        Vault(vault).transferFrom(currency, msg.sender, currency_amount);

        // Step 2. Receive assets from the contract
        Vault(vault).transfer(asset, msg.sender, asset_amount);

        // EVENTS
        emit Exercise(msg.sender, currency_amount);

        return true;
    }

    // Admin function to withdraw any random token deposits. Destination is hardcoded.
    // Didn't want to add an owner to the contract. No need for extra complexity.
    // No error checking for this admin function as it's not relevant.
    function slurp(address token, uint256 amount) public
    {
        // solium-disable-next-line security/no-low-level-calls
        IERC20(token).transfer(0x9e6e344f94305d36eA59912b0911fE2c9149Ed3E, amount);
    }
}
