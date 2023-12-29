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

contract Wallet {
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
    error InvalidPayeeTime();
    error AlreadyHasPendingOrder();

    event EthTransPayee(
        address indexed payee,
        address indexed to,
        uint256 indexed amount
    );

    // event ReEthTransPayee(
    //     address indexed payee,
    //     address indexed to,
    //     uint256 indexed amount
    // );

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
    uint256 private initialized;
    uint256 public minDelay = 300 seconds;
    string public useridentifier;
    mapping(string => UserInfo) userinfo;
    mapping(string => PayEthOrder) payEthinfo;
    mapping(string => PayTokenOrder) payTokeninfo;
    mapping(string => PayNFTOrder) payNFTinfo;
    mapping(bytes32 => bool) usedsig;
    PayEthOrder ethpayeeinfo; // = payEthinfo[useridentifier];
    PayTokenOrder tokenpayeeinfo; // = payTokeninfo[useridentifier];
    PayNFTOrder nftpayeeinfo; //= payNFTinfo[useridentifier];
    Pay1155NFTOrder nft1155payeeinfo;
    struct UserInfo {
        address owner;
        address signer;
        address manager;
    }

    struct PayEthOrder {
        uint256 delay;
        address payee;
        address to;
        uint256 amount;
    }
    struct PayTokenOrder {
        address contractaddress;
        uint256 delay;
        address payee;
        uint256 amount;
        address to;
    }
    struct PayNFTOrder {
        address contractaddress;
        uint256 delay;
        address payee;
        uint256 tokenID;
        address to;
    }

    struct Pay1155NFTOrder {
        address contractaddress;
        uint256 delay;
        address payee;
        uint256 tokenID;
        address to;
        uint256 amount;
        bytes data;
    }

    modifier onlyOwner() {
        if (msg.sender != userinfo[useridentifier].owner)
            revert NotOwnerAuthorized();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != userinfo[useridentifier].manager)
            revert NotManagerAuthorized();
        _;
    }

    function initData(
        address _owneraddress,
        address _manager,
        address _signaddress
    ) external {
        if (initialized == 1) revert AlreadyInitialzed();
        useridentifier = identifier();
        userinfo[useridentifier] = UserInfo({
            // identifier: useridentifier,
            // ecodehash: 0,
            owner: _owneraddress,
            signer: _signaddress,
            manager: _manager
        });
        initialized = 1;
    }

    function _isvalidSig(bytes memory sig) internal view returns (bool) {
        return usedsig[keccak256(sig)];
    }

    function updateDelay(
        uint256 delay,
        uint256 timestamp,
        bytes calldata updatedelaysignature
    ) external {
        if (_isvalidSig(updatedelaysignature)) {
            revert SigAlreadyUsed();
        }
        usedsig[keccak256(updatedelaysignature)] = true;
        require((timestamp < block.timestamp), "INVALID_TIMESTAMP");
        string memory _updelay = string(abi.encodePacked(delay, timestamp));
        if (!isValidManagerSignature(_updelay, updatedelaysignature))
            revert InvalidManagerSignature();
        minDelay = delay;
    }

    function setEthTransPayee(
        uint256 amount,
        address payee,
        address to,
        uint256 delay,
        bytes calldata signature
    ) public onlyManager {
        if (ethpayeeinfo.delay != 0 && ethpayeeinfo.delay >= block.timestamp)
            revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        string memory hash = string(abi.encodePacked(amount, payee, to, delay));
        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (address(this).balance < amount) {
            revert ENotEnoughBalance(address(this).balance);
        }

        if (ethpayeeinfo.delay != 0 && ethpayeeinfo.delay < block.timestamp) {
            ethpayeeinfo.delay = delay;
            ethpayeeinfo.payee = payee;
            ethpayeeinfo.to = to;
            ethpayeeinfo.amount = amount;
            // emit ReEthTransPayee(payee, to, amount);
        } else if (ethpayeeinfo.delay == 0) {
            ethpayeeinfo = PayEthOrder({
                payee: payee,
                delay: block.timestamp + delay,
                amount: amount,
                to: to
            });
        }
        emit EthTransPayee(payee, to, amount);
    }

    function setTokenTransPayee(
        address tokencontract,
        uint256 amount,
        address to,
        address payee,
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
            abi.encodePacked(tokencontract, amount, payee, to, delay)
        );
        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (IERC20(tokencontract).balanceOf(address(this)) < amount) {
            revert ENotEnoughTokenBalance(
                IERC20(tokencontract).balanceOf(address(this))
            );
        }
        if (
            tokenpayeeinfo.delay != 0 && tokenpayeeinfo.delay < block.timestamp
        ) {
            tokenpayeeinfo.delay = delay;
            tokenpayeeinfo.payee = payee;
            tokenpayeeinfo.to = to;
            tokenpayeeinfo.amount = amount;
            tokenpayeeinfo.contractaddress = tokencontract;
        } else if (tokenpayeeinfo.delay == 0) {
            tokenpayeeinfo = PayTokenOrder({
                payee: payee,
                contractaddress: tokencontract,
                delay: block.timestamp + delay,
                amount: amount,
                to: to
            });
        }
        emit TokenTransPayee(payee, tokencontract, to, amount);
    }

    function setNFTTransPayee(
        address tokencontract,
        uint256 tokenID,
        address to,
        address payee,
        uint256 delay,
        bytes calldata signature
    ) public onlyManager {
        if (nftpayeeinfo.delay != 0 && nftpayeeinfo.delay >= block.timestamp)
            revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        string memory hash = string(
            abi.encodePacked(tokencontract, tokenID, payee, to, delay)
        );

        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (IERC721(tokencontract).ownerOf(tokenID) != address(this)) {
            revert ENotEnoughTokenBalance(
                IERC721(tokencontract).balanceOf(address(this))
            );
        }
        if (nftpayeeinfo.delay != 0 && nftpayeeinfo.delay < block.timestamp) {
            nftpayeeinfo.delay = delay;
            nftpayeeinfo.payee = payee;
            nftpayeeinfo.to = to;
            nftpayeeinfo.tokenID = tokenID;
            nftpayeeinfo.contractaddress = tokencontract;
        } else if (nftpayeeinfo.delay == 0) {
            nftpayeeinfo = PayNFTOrder({
                payee: payee,
                contractaddress: tokencontract,
                delay: block.timestamp + delay,
                tokenID: tokenID,
                to: to
            });
        }
        emit NFTTransPayee(payee, tokencontract, to, tokenID);
    }

    function set1155NFTTransPayee(
        address tokencontract,
        address to,
        address payee,
        uint256 tokenID,
        uint256 amount,
        uint256 delay,
        bytes memory data,
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
            abi.encodePacked(
                tokencontract,
                tokenID,
                payee,
                to,
                amount,
                data,
                delay
            )
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
        if (
            nft1155payeeinfo.delay != 0 &&
            nft1155payeeinfo.delay < block.timestamp
        ) {
            nft1155payeeinfo.delay = delay;
            nft1155payeeinfo.payee = payee;
            nft1155payeeinfo.to = to;
            nft1155payeeinfo.tokenID = tokenID;
            nft1155payeeinfo.contractaddress = tokencontract;
            nft1155payeeinfo.amount = amount;
            nft1155payeeinfo.data = data;
        } else if (nft1155payeeinfo.delay == 0) {
            nft1155payeeinfo = Pay1155NFTOrder({
                payee: payee,
                contractaddress: tokencontract,
                delay: block.timestamp + delay,
                tokenID: tokenID,
                to: to,
                amount: amount,
                data: data
            });
        }
        emit NFTTransPayee(payee, tokencontract, to, tokenID);
    }

    function resetOrforgetPassword(
        address newowner,
        uint256 ecodehash,
        bytes calldata managersignecodehash,
        bytes calldata usersignrandom
    ) public onlyManager {
        string memory _ecodehash = concatStrings(useridentifier, ecodehash);
        if (!isValidManagerSignature(_ecodehash, managersignecodehash))
            revert InvalidManagerSignature();
        string memory sigmsg = string(abi.encodePacked(newowner, ecodehash));
        if (!isValidUserSignature(sigmsg, usersignrandom))
            revert InvalidUserSignature();
        // userinfo[useridentifier].ecodehash = ecodehash;
        userinfo[useridentifier].owner = newowner;
    }

    function transEth(
        address to,
        uint256 value,
        bytes calldata _calldata
    ) external payable onlyOwner returns (bytes memory) {
        return Address.functionCallWithValue(to, _calldata, value);
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
            "Transfer_Faliled"
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
        //  PayNFTOrder memory payeeinfo = payNFTinfo[useridentifier];
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
        uint256 amount,
        bytes memory data
    ) external payable onlyOwner {
        (bool success, bytes memory result) = contractaddress.call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,uint256,bytes)",
                address(this),
                to,
                tokenID,
                amount,
                data
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
        //  PayNFTOrder memory payeeinfo = payNFTinfo[useridentifier];
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

    function resetManaget(address manager) public onlyManager {
        if (manager == address(0)) revert InvalidInput();
        userinfo[useridentifier].manager = manager;
    }

    function resetSignAddress(address signer) external onlyOwner {
        if (signer == address(0)) revert InvalidInput();
        userinfo[useridentifier].signer = signer;
    }

    function equal(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return
            bytes(a).length == bytes(b).length &&
            keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function identifier() internal view returns (string memory) {
        bytes memory footer = new bytes(0x20);
        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x2d, 0x20)
        }
        return convertByte32ToString(abi.decode(footer, (bytes32)));
    }

    function setMinDelay(uint256 newdelay) public virtual onlyManager {
        minDelay = newdelay;
    }

    function getSigner() public view virtual returns (address) {
        return userinfo[useridentifier].signer;
    }

    function getManager() public view virtual returns (address) {
        return userinfo[useridentifier].manager;
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
        address _owner = userinfo[useridentifier].signer;
        bool _sig = isValidSignature(_owner, _msghash, signature);
        usedsig[keccak256(signature)] = true;
        return _sig;
    }

    function isValidManagerSignature(
        string memory _veridata,
        bytes calldata signature
    ) public returns (bool) {
        bytes32 _msghash = getMessageHash(_veridata);
        address _manager = userinfo[useridentifier].manager;
        bool _sig = isValidSignature(_manager, _msghash, signature);
        usedsig[keccak256(signature)] = true;
        return _sig;
    }

    function getMessageHash(string memory str) internal pure returns (bytes32) {
        bytes32 _msgHash = keccak256(abi.encodePacked(str));
        //return ECDSA.toEthSignedMessageHash(_msgHash);
        return toEthSignedMessageHash(_msgHash);
    }

    function toEthSignedMessageHash(bytes32 hash)
        internal
        pure
        returns (bytes32)
    {
        // 哈希的长度为32
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
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

    function concatStrings(string memory a, uint256 b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
        // bytes4(
        //     keccak256(
        //         "onERC1155Received(address,address,uint256,uint256,bytes)"
        //     )
        // );
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
