// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;
import "@openzeppelin/contracts/utils/Create2.sol";

contract Factory {
    error AccountCreationFailed();
    error InvalidSignerInput();
    error InvalidOwnerInput();
    error DuplicatedAddress();
    event AccountCreated(address indexed _account);

    address[] public userwallet;
    address public implementation;
    address public manager;
    address public owner;
    mapping(string => uint256) walletlimit;

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
        string memory _identifier
    ) external returns (address _account) {
        if (_owner == address(0)) revert InvalidOwnerInput();
        if (_signer == address(0)) revert InvalidSignerInput();
        require(walletlimit[_identifier] == 0, "ONLY_ALLOW_ONE_WALLET");
        walletlimit[_identifier] = 1;
        bytes memory code = getCreationCode(convertStringToByte32(_identifier));
        bytes memory salt = abi.encode(_identifier, _owner, _signer);
        _account = Create2.computeAddress(bytes32(salt), keccak256(code));
        if (_account.code.length != 0) revert DuplicatedAddress();
        emit AccountCreated(_account);
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
    }

    function account(
        address _owner,
        address _signer,
        string memory _identifier
    ) external view returns (address _account) {
        bytes memory code = getCreationCode(convertStringToByte32(_identifier));
        bytes memory salt = abi.encode(_identifier, _owner, _signer);
        _account = Create2.computeAddress(bytes32(salt), keccak256(code));
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
