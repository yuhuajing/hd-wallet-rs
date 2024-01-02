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

    address[] public userwallet;
    address public implementation;
    address public manager;
    address public owner;

    function getWalletLength() public view returns (uint256) {
        return userwallet.length;
    }

    constructor(address _manager, address _implement) payable {
        owner = msg.sender;
        manager = _manager;
        implementation = _implement;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    function updateOwner(address newOwner) external onlyOwner {
        require(
            newOwner != address(0) && newOwner != owner,
            "DUP/INVALID_NEWOWNER"
        );
        owner = newOwner;
    }

    function updateManager(address newManager) external onlyOwner {
        require(
            newManager != address(0) && newManager != manager,
            "DUP/INVALID_NEWMANAGER"
        );
        manager = newManager;
    }

    function updateImpl(address newImpl) external onlyOwner {
        require(
            newImpl != address(0) && newImpl != implementation,
            "DUP/INVALID_NEWIMPL"
        );
        implementation = newImpl;
    }

    function getCreationCode(bytes32 _identifier)
        internal
        view
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
                implementation,
                hex"5af43d82803e903d91602b57fd5bf3",
                abi.encode(_identifier)
            );
    }

    function createAccount(
        address _owner,
        address _signer,
        uint256 _salt,
        string memory _identifier
    ) external returns (address) {
        if (_signer == address(0)) revert InvalidSignerInput();
        bytes memory code = getCreationCode(
            convertStringToByte32(_identifier)
        );
        bytes memory salt = abi.encode(
            _salt,
            _identifier,
            _owner,
            _signer,
            manager,
            implementation
        );
        address _account = Create2.computeAddress(
            bytes32(salt),
            keccak256(code)
        );
        if (_account.code.length != 0) return _account;
        emit AccountCreated(_account, implementation, salt);
        assembly {
            _account := create2(0, add(code, 0x20), mload(code), salt)
        }
        if (_account == address(0)) revert AccountCreationFailed();
        (bool success, bytes memory result) = _account.call(
            abi.encodeWithSignature(
                "initData(address,address,address)",
                _owner,
                manager,
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
        address _signer,
        uint256 _salt,
        string memory _identifier
    ) external view returns (address) {
        bytes memory code = getCreationCode(
            convertStringToByte32(_identifier)
        );
        bytes memory salt = abi.encode(
            _salt,
            _identifier,
            _owner,
            _signer,
            manager,
            implementation
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
