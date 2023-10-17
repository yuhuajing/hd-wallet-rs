// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;
import "@openzeppelin/contracts/utils/Create2.sol";

contract Factory {
    error AccountCreationFailed();
    error InvalidManagerInput();
    error InvalidSignerInput();
    event AccountCreated(
        address indexed _account,
        address indexed implementation,
        uint256 salt
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

    function getCreationCode(bytes32 _email, address _implementation)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
                _implementation,
                hex"5af43d82803e903d91602b57fd5bf3",
                abi.encode(_email)
            );
    }

    function createAccount(
        address _owner,
        string memory email,
        address _implementation,
        uint256 _salt,
        address _manager,
        address _signer
    ) external returns (address) {
        if (_manager == address(0)) revert InvalidManagerInput();
        if (_signer == address(0)) revert InvalidSignerInput();
        bytes memory code = getCreationCode(convertStringToByte32(email), _implementation);
        address _account = Create2.computeAddress(
            bytes32(_salt),
            keccak256(code)
        );
        if (_account.code.length != 0) return _account;
        emit AccountCreated(_account, _implementation, _salt);
        assembly {
            _account := create2(0, add(code, 0x20), mload(code), _salt)
        }
        if (_account == address(0)) revert AccountCreationFailed();
        (bool success, bytes memory result) = _account.call(
            abi.encodeWithSignature(
                "initData(address,address,address,uint256)",
                 _owner,
                _manager,
                _signer,
                300
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
        string memory email,
        address _implementation,
        uint256 _salt
    ) external view returns (address) {
        bytes32 bytecodeHash = keccak256(
            getCreationCode(convertStringToByte32(email), _implementation)
        );
        return Create2.computeAddress(bytes32(_salt), bytecodeHash);
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
