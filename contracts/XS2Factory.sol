// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface Clone {
    function init(string memory name, string memory symbol, address asset,
        address currency, uint256 price, uint256 expiry) external;
}

contract XS2Factory {
    address public implementation;
    string public name;

    uint32 public totalContracts;
    mapping(uint32 => address) contracts;

    event ContractCreated(address newContractAddress);

    constructor(address implementation_) {
        implementation = implementation_;
        name = 'XS2Option';
    }

    function deploy(
        string memory name_, string memory symbol_, address asset_,
        address currency_, uint256 price_, uint256 expiry_
    ) public returns (address) {
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

        contracts[totalContracts] = clone_address;
        totalContracts++;

        Clone(clone_address).init(name_, symbol_, asset_, currency_, price_, expiry_);

        emit ContractCreated(clone_address);

        return clone_address;
    }
}
