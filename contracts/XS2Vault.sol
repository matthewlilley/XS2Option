// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface Clone {
    function init(address vault, address asset, address currency, uint256 price, uint256 expiry) external;
}

contract XS2Vault {
    address public implementation;

    uint32 public totalOptions;
    mapping(uint32 => address) optionByIndex;
    mapping(address => bool) isOption;

    event OptionCreated(address newOptionAddress);

    constructor(address implementation_) {
        implementation = implementation_;
    }

    /**
     * @dev Creates a new option series and deploys the cloned contract.
     */
    // solium-disable-next-line security/no-inline-assembly
    function deploy(address asset_, address currency_, uint256 price_, uint256 expiry_) public returns (address) {
        bytes20 targetBytes = bytes20(implementation);
        address clone_address;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            clone_address := create(0, clone, 0x37)
        }

        isOption[clone_address] = true;
        optionByIndex[totalOptions] = clone_address;
        totalOptions++;

        Clone(clone_address).init(address(this), asset_, currency_, price_, expiry_);

        emit OptionCreated(clone_address);

        return clone_address;
    }

    /**
     * @dev Calls 'transfer' on an ERC20 token for any XS2Option. Sends funds from the vault to the user.
     * @param token The contract address of the ERC20 token.
     * @param to The address to transfer the tokens to.
     * @param amount The amount to transfer.
     */
    function transfer(address token, address to, uint256 amount) public returns (bool) {
        require(isOption[msg.sender], "XS2: Only option contracts can transfer");

        // solium-disable-next-line security/no-low-level-calls
        (bool success, bytes memory data) = token.call(
            // 0xa9059cbb = bytes4(keccak256("transferFrom(address,address,uint256)"))
            abi.encodeWithSelector(0xa9059cbb, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "XS2: Transfer failed at ERC20");

        return true;
    }

    /**
     * @dev Calls 'transferFrom' on an ERC20 token for any XS2Option. Pulls funds from the user into vault.
     * @param token The contract address of the ERC20 token.
     * @param from The address to transfer the tokens from.
     * @param amount The amount to transfer.
     */
    function transferFrom(address token, address from, uint256 amount) public returns (bool) {
        require(isOption[msg.sender], "XS2: Only option contracts can transferFrom");

        // solium-disable-next-line security/no-low-level-calls
        (bool success, bytes memory data) = token.call(
            // 0x23b872dd = bytes4(keccak256("transferFrom(address,address,uint256)"))
            abi.encodeWithSelector(0x23b872dd, from, address(this), amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "XS2: TransferFrom failed at ERC20");
    }
}