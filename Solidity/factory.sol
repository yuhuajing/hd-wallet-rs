// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@openzeppelin/contracts/utils/Create2.sol";

contract Factory {
    error AccountCreationFailed();
    error InvalidManagerInput();
    error InvalidSignerInput();
    event AccountCreated(
        address indexed _account,
        address indexed implementation,
        bytes salt
    );

    address[] userwallet;

    function getWalletByIndex(uint256 index) public view returns (address) {
        require(index < userwallet.length, "Invalid index");
        return userwallet[index];
    }

    function getWalletLength() public view returns (uint256) {
        return userwallet.length;
    }

    constructor() payable {}

    function getCreationCode(bytes32 _identifier, address _implementation)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
                _implementation,
                hex"5af43d82803e903d91602b57fd5bf3",
                abi.encode(_identifier)
            );
    }

    function createAccount(
        address _owner,
        address _implementation,
        address _manager,
        address _signer,
        uint256 _salt,
        string memory _identifier
    ) external returns (address) {
        if (_manager == address(0)) revert InvalidManagerInput();
        if (_signer == address(0)) revert InvalidSignerInput();
        bytes memory code = getCreationCode(
            convertStringToByte32(_identifier),
            _implementation
        );
        bytes memory salt = abi.encode(
            _salt,
            _identifier,
            _owner,
            _signer,
            _manager,
            _implementation
        );
        address _account = Create2.computeAddress(
            bytes32(salt),
            keccak256(code)
        );
        if (_account.code.length != 0) return _account;
        emit AccountCreated(_account, _implementation, salt);
        assembly {
            _account := create2(0, add(code, 0x20), mload(code), salt)
        }
        if (_account == address(0)) revert AccountCreationFailed();
        (bool success, bytes memory result) = _account.call(
            abi.encodeWithSignature(
                "initData(address,address,address)",
                _owner,
                _manager,
                _signer 
            )
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        userwallet.push(_account);
        return _account;
    }

    function account(
        address _owner,
        address _implementation,
        address _manager,
        address _signer,
        uint256 _salt,
        string memory _identifier
    ) external view returns (address) {
        bytes memory code = getCreationCode(
            convertStringToByte32(_identifier),
            _implementation
        );
        bytes memory salt = abi.encode(
            _salt,
            _identifier,
            _owner,
            _signer,
            _manager,
            _implementation
        );
        address _account = Create2.computeAddress(
            bytes32(salt),
            keccak256(code)
        );
        return _account;
    }

    function convertStringToByte32(string memory _texte)
        internal
        pure
        returns (bytes32 result)
    {
        assembly {
            result := mload(add(_texte, 32))
        }
    }
}
