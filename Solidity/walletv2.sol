// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@gnosis.pm/safe-contracts@1.3.0/contracts/base/OwnerManager.sol";
import "@gnosis.pm/safe-contracts@1.3.0/contracts/common/SecuredTokenTransfer.sol";

contract Wallet is OwnerManager, SecuredTokenTransfer {
    uint256 private initialized;
    uint256 public minDelay;
    address public signer;
    address public manager;
    mapping(bytes32 => bool) usedsig;
    PayEthOrder ethpayeeinfo;
    PayTokenOrder tokenpayeeinfo;
    PayNFTOrder nftpayeeinfo;
    Pay1155NFTOrder nft1155payeeinfo;

    error NotPayeeAuthorized();
    error NotOwnerAuthorized();
    error NotManagerAuthorized();
    error InvalidInput();
    error AlreadyInitialzed();
    error InvalidUserSignature();
    error InvalidManagerSignature();
    error SigAlreadyUsed();
    error NotPayeesetted();
    error TimelockInsufficientDelay(uint256 delay, uint256 minDelay);
    error ENotEnoughBalance(uint256 balance);
    error ENotEnoughTokenBalance(uint256 balance);
    error ENotTokenOwner(address owner);
    error InvalidPayeeTime();
    error AlreadyHasPendingOrder();

    event EthTransPayee(
        address indexed payee,
        address indexed receiver,
        uint256 indexed amount
    );
    event EthTrans(address indexed receiver, uint256 indexed amount);
    event TokenTransPayee(
        address indexed payee,
        address indexed tokencontract,
        address indexed receiver,
        uint256 amount
    );
    event TokenTrans(
        address indexed tokencontract,
        address indexed receiver,
        uint256 amount
    );
    event NFTTransPayee(
        address indexed payee,
        address indexed tokencontract,
        address indexed receiver,
        uint256 tokenID
    );
    event NFTTrans(
        address indexed tokencontract,
        address indexed receiver,
        uint256 tokenID
    );
    event NFT1155TransPayee(
        address indexed payee,
        address indexed tokencontract,
        address indexed receiver,
        uint256 tokenID,
        uint256 amount
    );
    event NFT1155Trans(
        address indexed tokencontract,
        address indexed receiver,
        uint256 tokenID,
        uint256 amount,
        bytes32 data
    );

    struct PayEthOrder {
        address payee;
        address receiver;
        uint256 amount;
        uint256 delay;
    }
    struct PayTokenOrder {
        address contractaddress;
        address payee;
        address receiver;
        uint256 delay;
        uint256 amount;
    }
    struct PayNFTOrder {
        address contractaddress;
        address payee;
        address receiver;
        uint256 delay;
        uint256 tokenID;
    }
    struct Pay1155NFTOrder {
        address contractaddress;
        address payee;
        address receiver;
        uint256 tokenID;
        uint256 amount;
        uint256 delay;
        bytes32 data;
    }

    modifier onlyOwner() {
        if (!isOwner(msg.sender)) revert NotOwnerAuthorized();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManagerAuthorized();
        _;
    }

    function initData(
        address _owneraddress,
        address _manager,
        address _signaddress
    ) external {
        if (initialized != 0) revert AlreadyInitialzed();
        initialized = 1;
        signer = _signaddress;
        manager = _manager;
        minDelay = 300 seconds;
        address[] memory array = new address[](1);
        array[0] = _owneraddress;
        setupOwners(array, 1);
    }

    function updateDelay(
        uint256 delay,
        uint256 timestamp,
        bytes calldata signature
    ) external onlyOwner {
        require((timestamp < block.timestamp), "INVALID_TIMESTAMP");
        string memory hash = string(abi.encodePacked(delay, timestamp));
        if (!isValidManagerSignature(hash, signature))
            revert InvalidManagerSignature();
        minDelay = delay;
    }

    function updateManager(address _manager) public onlyManager {
        if (_manager == address(0)) revert InvalidInput();
        manager = _manager;
    }

    function updateSignAddress(
        address _signer,
        uint256 timestamp,
        bytes calldata signature
    ) external onlyOwner {
        if (_signer == address(0)) revert InvalidInput();
        string memory hash = string(abi.encodePacked(_signer, timestamp));
        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        signer = _signer;
    }

    function setEthTransPayee(
        address payee,
        address receiver,
        uint256 amount,
        uint256 delay,
        uint256 timestamp,
        bytes calldata signature
    ) public onlyManager {
        if (ethpayeeinfo.delay != 0 && ethpayeeinfo.delay >= block.timestamp)
            revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        if (address(this).balance < amount) {
            revert ENotEnoughBalance(address(this).balance);
        }
        string memory hash = string(
            abi.encodePacked(payee, receiver, amount, delay, timestamp)
        );
        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (ethpayeeinfo.delay == 0) {
            ethpayeeinfo = PayEthOrder({
                payee: payee,
                delay: block.timestamp + delay,
                amount: amount,
                receiver: receiver
            });
        } else {
            ethpayeeinfo.receiver = receiver;
            ethpayeeinfo.amount = amount;
            ethpayeeinfo.delay = delay;
            ethpayeeinfo.payee = payee;
        }
        emit EthTransPayee(payee, receiver, amount);
    }

    function setTokenTransPayee(
        address tokencontract,
        address payee,
        address receiver,
        uint256 amount,
        uint256 delay,
        uint256 timestamp,
        bytes calldata signature
    ) public onlyManager {
        if (
            tokenpayeeinfo.delay != 0 && tokenpayeeinfo.delay >= block.timestamp
        ) revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        if (IERC20(tokencontract).balanceOf(address(this)) < amount) {
            revert ENotEnoughTokenBalance(
                IERC20(tokencontract).balanceOf(address(this))
            );
        }
        string memory hash = string(
            abi.encodePacked(
                tokencontract,
                payee,
                receiver,
                amount,
                delay,
                timestamp
            )
        );
        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (tokenpayeeinfo.delay == 0) {
            tokenpayeeinfo = PayTokenOrder({
                contractaddress: tokencontract,
                payee: payee,
                receiver: receiver,
                amount: amount,
                delay: block.timestamp + delay
            });
        } else {
            tokenpayeeinfo.contractaddress = tokencontract;
            tokenpayeeinfo.payee = payee;
            tokenpayeeinfo.receiver = receiver;
            tokenpayeeinfo.amount = amount;
            tokenpayeeinfo.delay = delay;
        }
        emit TokenTransPayee(payee, tokencontract, receiver, amount);
    }

    function setNFTTransPayee(
        address tokencontract,
        address payee,
        address receiver,
        uint256 tokenID,
        uint256 delay,
        uint256 timestamp,
        bytes calldata signature
    ) public onlyManager {
        if (nftpayeeinfo.delay != 0 && nftpayeeinfo.delay >= block.timestamp)
            revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        if (IERC721(tokencontract).ownerOf(tokenID) != address(this)) {
            revert ENotTokenOwner(IERC721(tokencontract).ownerOf(tokenID));
        }
        string memory hash = string(
            abi.encodePacked(
                tokencontract,
                payee,
                receiver,
                tokenID,
                delay,
                timestamp
            )
        );

        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (nftpayeeinfo.delay == 0) {
            nftpayeeinfo = PayNFTOrder({
                contractaddress: tokencontract,
                payee: payee,
                receiver: receiver,
                tokenID: tokenID,
                delay: block.timestamp + delay
            });
        } else {
            nftpayeeinfo.contractaddress = tokencontract;
            nftpayeeinfo.payee = payee;
            nftpayeeinfo.receiver = receiver;
            nftpayeeinfo.tokenID = tokenID;
            nftpayeeinfo.delay = delay;
        }
        emit NFTTransPayee(payee, tokencontract, receiver, tokenID);
    }

    function set1155NFTTransPayee(
        address tokencontract,
        address payee,
        address receiver,
        uint256 tokenID,
        uint256 amount,
        uint256 delay,
        uint256 timestamp,
        bytes calldata signature
    ) public onlyManager {
        if (
            nft1155payeeinfo.delay != 0 &&
            nft1155payeeinfo.delay >= block.timestamp
        ) revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        if (
            IERC1155(tokencontract).balanceOf(address(this), tokenID) < amount
        ) {
            revert ENotEnoughTokenBalance(
                IERC1155(tokencontract).balanceOf(address(this), tokenID)
            );
        }
        string memory hash = string(
            abi.encodePacked(
                tokencontract,
                payee,
                receiver,
                tokenID,
                amount,
                delay,
                timestamp
            )
        );

        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();

        if (nft1155payeeinfo.delay == 0) {
            nft1155payeeinfo = Pay1155NFTOrder({
                contractaddress: tokencontract,
                payee: payee,
                receiver: receiver,
                tokenID: tokenID,
                amount: amount,
                data: "",
                delay: block.timestamp + delay
            });
        } else {
            nft1155payeeinfo.contractaddress = tokencontract;
            nft1155payeeinfo.payee = payee;
            nft1155payeeinfo.receiver = receiver;
            nft1155payeeinfo.tokenID = tokenID;
            nft1155payeeinfo.amount = amount;
            nft1155payeeinfo.data = "";
            nft1155payeeinfo.delay = delay;
        }
        emit NFT1155TransPayee(payee, tokencontract, receiver, tokenID, amount);
    }

    function prevOwner(address owner) internal view returns (address preowner) {
        require(isOwner(owner), "NOT_OWNER");
        address[] memory array = getOwners();
        for (uint256 index; index < array.length; index++) {
            address currentowner = array[index];
            if (owners[currentowner] == owner) {
                preowner == currentowner;
                break;
            }
        }
    }

    function resetOrforgetPassword(
        address oldowner,
        address newowner,
        uint256 ecodehash,
        uint256 timestamp,
        bytes calldata usersig
    ) public onlyManager {
        string memory sigmsg = string(
            abi.encodePacked(oldowner, newowner, ecodehash, timestamp)
        );
        if (!isValidUserSignature(sigmsg, usersig))
            revert InvalidUserSignature();
        address preowner = prevOwner(oldowner);
        swapOwner(preowner, oldowner, newowner);
    }

    function addOwner(
        address newowner,
        uint256 timestamp,
        bytes calldata usersignrandom
    ) public onlyManager {
        string memory sigmsg = string(abi.encodePacked(newowner, timestamp));
        if (!isValidUserSignature(sigmsg, usersignrandom))
            revert InvalidUserSignature();
        addOwnerWithThreshold(newowner, 1);
    }

    function removeOwner(
        address owner,
        uint256 timestamp,
        bytes calldata usersignrandom
    ) public onlyManager {
        string memory sigmsg = string(abi.encodePacked(owner, timestamp));
        if (!isValidUserSignature(sigmsg, usersignrandom))
            revert InvalidUserSignature();
        address preowner = prevOwner(owner);
        removeOwner(preowner, owner, 1);
    }

    function transEth(address receiver, uint256 value)
        external
        payable
        onlyOwner
    {
        Address.sendValue(payable(receiver), value);
        emit EthTrans(receiver, value);
    }

    function payeeEthTrans() external {
        if (ethpayeeinfo.delay == 0) revert NotPayeesetted();
        if (ethpayeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (ethpayeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        Address.sendValue(payable(ethpayeeinfo.receiver), ethpayeeinfo.amount);
        ethpayeeinfo.delay = 1;
        emit EthTrans(ethpayeeinfo.receiver, ethpayeeinfo.amount);
    }

    function transToken(
        address contractaddress,
        address receiver,
        uint256 amount
    ) external payable onlyOwner {
        bool success = transferToken(contractaddress, receiver, amount);
        require(success, "Transfer_Token_Faliled");
        emit TokenTrans(contractaddress, receiver, amount);
    }

    function payeeTokenTrans() external {
        if (tokenpayeeinfo.delay == 0) revert NotPayeesetted();
        if (tokenpayeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (tokenpayeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        bool success = transferToken(
            tokenpayeeinfo.contractaddress,
            tokenpayeeinfo.receiver,
            tokenpayeeinfo.amount
        );
        require(success, "Transfer_Token_Faliled");

        tokenpayeeinfo.delay = 1;
        emit TokenTrans(
            tokenpayeeinfo.contractaddress,
            tokenpayeeinfo.receiver,
            tokenpayeeinfo.amount
        );
    }

    function transNFT(
        address contractaddress,
        address receiver,
        uint256 tokenID
    ) external payable onlyOwner {
        (bool success, bytes memory result) = contractaddress.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(this),
                receiver,
                tokenID
            )
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        emit NFTTrans(contractaddress, receiver, tokenID);
    }

    function payeeNFTTrans() external {
        if (nftpayeeinfo.delay == 0) revert NotPayeesetted();
        if (nftpayeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (nftpayeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        (bool success, bytes memory result) = nftpayeeinfo.contractaddress.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(this),
                nftpayeeinfo.receiver,
                nftpayeeinfo.tokenID
            )
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        nftpayeeinfo.delay = 1;
        emit NFTTrans(
            nftpayeeinfo.contractaddress,
            nftpayeeinfo.receiver,
            nftpayeeinfo.tokenID
        );
    }

    function trans1155NFT(
        address contractaddress,
        address receiver,
        uint256 tokenID,
        uint256 amount
    ) external payable onlyOwner {
        (bool success, bytes memory result) = contractaddress.call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,uint256,bytes)",
                address(this),
                receiver,
                tokenID,
                amount,
                ""
            )
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        emit NFT1155Trans(contractaddress, receiver, tokenID, amount, "");
    }

    function payee1155Trans() external {
        if (nft1155payeeinfo.delay == 0) revert NotPayeesetted();
        if (nft1155payeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (nft1155payeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        (bool success, bytes memory result) = nft1155payeeinfo
            .contractaddress
            .call(
                abi.encodeWithSignature(
                    "safeTransferFrom(address,address,uint256,uint256,bytes)",
                    address(this),
                    nft1155payeeinfo.receiver,
                    nft1155payeeinfo.tokenID,
                    nft1155payeeinfo.amount,
                    nft1155payeeinfo.data
                )
            );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        nft1155payeeinfo.delay = 1;
        emit NFT1155Trans(
            nft1155payeeinfo.contractaddress,
            nft1155payeeinfo.receiver,
            nft1155payeeinfo.tokenID,
            nft1155payeeinfo.amount,
            nft1155payeeinfo.data
        );
    }

    function identifier() external view returns (string memory) {
        bytes memory footer = new bytes(0x20);
        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x2d, 0x20)
        }
        return convertByte32ToString(abi.decode(footer, (bytes32)));
    }

    function convertByte32ToString(bytes32 _bytes32)
        internal
        pure
        returns (string memory)
    {
        bytes memory bytesArray = new bytes(32);
        for (uint256 i; i < 32; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function isValidUserSignature(
        string memory _veridata,
        bytes calldata signature
    ) public returns (bool _isvalidsig) {
        bytes32 _msghash = getMessageHash(_veridata);
        address _owner = signer;
        _isvalidsig = isValidSignature(_owner, _msghash, signature);
        usedsig[keccak256(signature)] = true;
    }

    function isValidManagerSignature(
        string memory _veridata,
        bytes calldata signature
    ) public returns (bool _isvalidsig) {
        bytes32 _msghash = getMessageHash(_veridata);
        address _manager = manager;
        _isvalidsig = isValidSignature(_manager, _msghash, signature);
        usedsig[keccak256(signature)] = true;
    }

    function isValidSignature(
        address _owner,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        return
            SignatureChecker.isValidSignatureNow(_owner, hash, signature) &&
            !usedsig[keccak256(signature)];
    }

    function getMessageHash(string memory str) internal pure returns (bytes32) {
        bytes32 _msgHash = keccak256(abi.encodePacked(str));
        return toEthSignedMessageHash(_msgHash);
    }

    function toEthSignedMessageHash(bytes32 hash)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    fallback() external payable {}

    receive() external payable {}
}
