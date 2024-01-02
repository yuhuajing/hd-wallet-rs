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

contract Wallet is OwnerManager {
    uint256 private initialized;
    uint256 public minDelay = 300 seconds;
    //address[] public owners;
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
        address indexed to,
        uint256 indexed amount
    );

    event TokenTransPayee(
        address indexed payee,
        address indexed tokencontract,
        address indexed to,
        uint256 amount
    );
    event NFTTransPayee(
        address indexed payee,
        address indexed tokencontract,
        address indexed to,
        uint256 tokenID
    );

    struct PayEthOrder {
        address payee;
        address to;
        uint256 amount;
        uint256 delay;
    }
    struct PayTokenOrder {
        address contractaddress;
        address payee;
        address to;
        uint256 delay;
        uint256 amount;
    }
    struct PayNFTOrder {
        address contractaddress;
        address payee;
        address to;
        uint256 delay;
        uint256 tokenID;
    }
    struct Pay1155NFTOrder {
        address contractaddress;
        address payee;
        address to;
        uint256 tokenID;
        uint256 amount;
        uint256 delay;
        bytes data;
    }

    modifier onlyOwner() {
        //if (msg.sender != owner) revert NotOwnerAuthorized();
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
        if (initialized == 1) revert AlreadyInitialzed();
        // owner = _owneraddress;
        signer = _signaddress;
        manager = _manager;
        initialized = 1;
        address[] memory array = new address[](1);
        array[0] = _owneraddress;
        setupOwners(array, 0);
    }

    function _isvalidSig(bytes memory sig) internal view returns (bool) {
        return usedsig[keccak256(sig)];
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

    function updateManager(
        address _manager,
        uint256 timestamp,
        bytes calldata signature
    ) public onlyOwner {
        if (_manager == address(0)) revert InvalidInput();
        string memory hash = string(abi.encodePacked(_manager, timestamp));
        if (!isValidManagerSignature(hash, signature))
            revert InvalidManagerSignature();
        manager = _manager;
    }

    // function updateSignAddress(
    //     address _signer,
    //     uint256 timestamp,
    //     bytes calldata signature
    // ) external onlyOwner {
    //     if (_signer == address(0)) revert InvalidInput();
    //     string memory hash = string(abi.encodePacked(_signer, timestamp));
    //     if (!isValidUserSignature(hash, signature))
    //         revert InvalidUserSignature();
    //     signer = _signer;
    // }

    function setEthTransPayee(
        address payee,
        address to,
        uint256 amount,
        uint256 delay,
        bytes calldata signature
    ) public onlyManager {
        if (ethpayeeinfo.delay != 0 && ethpayeeinfo.delay >= block.timestamp)
            revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        string memory hash = string(abi.encodePacked(payee, to, amount, delay));
        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (address(this).balance < amount) {
            revert ENotEnoughBalance(address(this).balance);
        }

        if (ethpayeeinfo.delay == 0) {
            ethpayeeinfo = PayEthOrder({
                payee: payee,
                delay: block.timestamp + delay,
                amount: amount,
                to: to
            });
        } else {
            ethpayeeinfo.delay = delay;
            ethpayeeinfo.payee = payee;
            ethpayeeinfo.to = to;
            ethpayeeinfo.amount = amount;
        }
        emit EthTransPayee(payee, to, amount);
    }

    function setTokenTransPayee(
        address tokencontract,
        address payee,
        address to,
        uint256 amount,
        uint256 delay,
        bytes calldata signature
    ) public onlyManager {
        if (
            tokenpayeeinfo.delay != 0 && tokenpayeeinfo.delay >= block.timestamp
        ) revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        string memory hash = string(
            abi.encodePacked(tokencontract, payee, to, amount, delay)
        );
        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (IERC20(tokencontract).balanceOf(address(this)) < amount) {
            revert ENotEnoughTokenBalance(
                IERC20(tokencontract).balanceOf(address(this))
            );
        }
        if (tokenpayeeinfo.delay == 0) {
            tokenpayeeinfo = PayTokenOrder({
                contractaddress: tokencontract,
                payee: payee,
                to: to,
                amount: amount,
                delay: block.timestamp + delay
            });
        } else {
            tokenpayeeinfo.contractaddress = tokencontract;
            tokenpayeeinfo.payee = payee;
            tokenpayeeinfo.to = to;
            tokenpayeeinfo.amount = amount;
            tokenpayeeinfo.delay = delay;
        }
        emit TokenTransPayee(payee, tokencontract, to, amount);
    }

    function setNFTTransPayee(
        address tokencontract,
        address payee,
        address to,
        uint256 tokenID,
        uint256 delay,
        bytes calldata signature
    ) public onlyManager {
        if (nftpayeeinfo.delay != 0 && nftpayeeinfo.delay >= block.timestamp)
            revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        string memory hash = string(
            abi.encodePacked(tokencontract, payee, to, tokenID, delay)
        );

        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (IERC721(tokencontract).ownerOf(tokenID) != address(this)) {
            revert ENotTokenOwner(IERC721(tokencontract).ownerOf(tokenID));
        }
        if (nftpayeeinfo.delay == 0) {
            nftpayeeinfo = PayNFTOrder({
                contractaddress: tokencontract,
                payee: payee,
                to: to,
                tokenID: tokenID,
                delay: block.timestamp + delay
            });
        } else {
            nftpayeeinfo.contractaddress = tokencontract;
            nftpayeeinfo.payee = payee;
            nftpayeeinfo.to = to;
            nftpayeeinfo.tokenID = tokenID;
            nftpayeeinfo.delay = delay;
        }
        emit NFTTransPayee(payee, tokencontract, to, tokenID);
    }

    function set1155NFTTransPayee(
        address tokencontract,
        address payee,
        address to,
        uint256 tokenID,
        uint256 amount,
        uint256 delay,
        bytes calldata signature
    ) public onlyManager {
        if (
            nft1155payeeinfo.delay != 0 &&
            nft1155payeeinfo.delay >= block.timestamp
        ) revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        string memory hash = string(
            abi.encodePacked(tokencontract, payee, to, tokenID, amount, delay)
        );

        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (
            IERC1155(tokencontract).balanceOf(address(this), tokenID) < amount
        ) {
            revert ENotEnoughTokenBalance(
                IERC1155(tokencontract).balanceOf(address(this), tokenID)
            );
        }
        if (nft1155payeeinfo.delay == 0) {
            nft1155payeeinfo = Pay1155NFTOrder({
                contractaddress: tokencontract,
                payee: payee,
                to: to,
                tokenID: tokenID,
                amount: amount,
                data: "",
                delay: block.timestamp + delay
            });
        } else {
            nft1155payeeinfo.contractaddress = tokencontract;
            nft1155payeeinfo.payee = payee;
            nft1155payeeinfo.to = to;
            nft1155payeeinfo.tokenID = tokenID;
            nft1155payeeinfo.amount = amount;
            nft1155payeeinfo.data = "";
            nft1155payeeinfo.delay = delay;
        }
        emit NFTTransPayee(payee, tokencontract, to, tokenID);
    }

    function prevOwner(address owner) internal view returns (address preowner) {
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
        bytes calldata managersig,
        bytes calldata usersig
    ) public onlyManager {
        string memory _ecodehash = string(abi.encodePacked(ecodehash));
        if (!isValidManagerSignature(_ecodehash, managersig))
            revert InvalidManagerSignature();
        string memory sigmsg = string(
            abi.encodePacked(oldowner, newowner, ecodehash)
        );
        if (!isValidUserSignature(sigmsg, usersig))
            revert InvalidUserSignature();
        address preowner = prevOwner(oldowner);
        swapOwner(preowner, oldowner, newowner);
        // addOwnerWithThreshold(newowner, 0);
        // owner = newowner;
    }

    function addOwner(
        address newowner,
        uint256 timestamp,
        bytes calldata usersignrandom
    ) public onlyManager {
        string memory sigmsg = string(abi.encodePacked(newowner, timestamp));
        if (!isValidUserSignature(sigmsg, usersignrandom))
            revert InvalidUserSignature();
        addOwnerWithThreshold(newowner, 0);
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
        removeOwner(preowner, owner, 0);
    }

    function transEth(address to, uint256 value) external payable onlyOwner {
        Address.sendValue(payable(to), value);
    }

    function payeeEthTrans() external {
        if (ethpayeeinfo.delay == 0) revert NotPayeesetted();
        if (ethpayeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (ethpayeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        Address.sendValue(payable(ethpayeeinfo.to), ethpayeeinfo.amount);
        ethpayeeinfo.delay = 1;
    }

    function transToken(
        address contractaddress,
        address to,
        uint256 amount
    ) external payable onlyOwner {
        IERC20(contractaddress).transfer(to, amount);
    }

    function payeeTokenTrans() external {
        if (tokenpayeeinfo.delay == 0) revert NotPayeesetted();
        if (tokenpayeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (tokenpayeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        require(
            IERC20(tokenpayeeinfo.contractaddress).transfer(
                tokenpayeeinfo.to,
                tokenpayeeinfo.amount
            ),
            "Transfer_Token_Faliled"
        );
        tokenpayeeinfo.delay = 1;
    }

    function transNFT(
        address contractaddress,
        address to,
        uint256 tokenID
    ) external payable onlyOwner {
        (bool success, bytes memory result) = contractaddress.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(this),
                to,
                tokenID
            )
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        // IERC721(contractaddress).transferFrom(address(this), to, tokenID);
    }

    function payeeNFTTrans() external {
        if (nftpayeeinfo.delay == 0) revert NotPayeesetted();
        if (nftpayeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (nftpayeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        (bool success, bytes memory result) = nftpayeeinfo.contractaddress.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                address(this),
                nftpayeeinfo.to,
                nftpayeeinfo.tokenID
            )
        );
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
        // IERC721(nftpayeeinfo.contractaddress).transferFrom(
        //     address(this),
        //     nftpayeeinfo.to,
        //     nftpayeeinfo.tokenID
        // );
        nftpayeeinfo.delay = 1;
    }

    function trans1155NFT(
        address contractaddress,
        address to,
        uint256 tokenID,
        uint256 amount
    ) external payable onlyOwner {
        (bool success, bytes memory result) = contractaddress.call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,uint256,bytes)",
                address(this),
                to,
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
        // IERC1155(contractaddress).safeTransferFrom(
        //     address(this),
        //     to,
        //     tokenID,
        //     amount,
        //     data
        // );
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
                    nft1155payeeinfo.to,
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
        // IERC1155(nft1155payeeinfo.contractaddress).safeTransferFrom(
        //     address(this),
        //     nft1155payeeinfo.to,
        //     nft1155payeeinfo.tokenID,
        //     nft1155payeeinfo.amount,
        //     nft1155payeeinfo.data
        // );
        nft1155payeeinfo.delay = 1;
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
    ) public returns (bool) {
        bytes32 _msghash = getMessageHash(_veridata);
        address _owner = signer;
        bool _isvalidsig = isValidSignature(_owner, _msghash, signature);
        usedsig[keccak256(signature)] = true;
        return _isvalidsig;
    }

    function isValidManagerSignature(
        string memory _veridata,
        bytes calldata signature
    ) public returns (bool) {
        bytes32 _msghash = getMessageHash(_veridata);
        address _manager = manager;
        bool _isvalidsig = isValidSignature(_manager, _msghash, signature);
        usedsig[keccak256(signature)] = true;
        return _isvalidsig;
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
