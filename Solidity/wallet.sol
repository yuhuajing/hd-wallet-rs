// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.21;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Wallet {
    error NotPayeeAuthorized();
    error NotOwnerAuthorized();
    error NotManagerAuthorized();
    error InvalidInput();
    error AlreadyInitialzed();
    error InvalidUserSignature();
    error InvalidManagerSignature();
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

    event ReEthTransPayee(
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
    uint256 private initialized;
    uint256 public minDelay = 300;
    string public useremail;
    mapping(string => UserInfo) userinfo;
    mapping(string => PayEthOrder) payEthinfo;
    mapping(string => PayTokenOrder) payTokeninfo;
    mapping(string => PayNFTOrder) payNFTinfo;
    PayEthOrder ethpayeeinfo = payEthinfo[useremail];
    PayTokenOrder tokenpayeeinfo = payTokeninfo[useremail];
    PayNFTOrder nftpayeeinfo = payNFTinfo[useremail];

    struct UserInfo {
        string email;
        uint256 email_code;
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

    modifier onlyOwner() {
        if (msg.sender != userinfo[useremail].owner)
            revert NotOwnerAuthorized();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != userinfo[useremail].manager)
            revert NotManagerAuthorized();
        _;
    }

    function initData(
        address _owneraddress,
        address _manager,
        address _signaddress,
        uint256 delay
    ) external {
        if (initialized == 1) revert AlreadyInitialzed();
        useremail = email();
        UserInfo memory _userinfo = UserInfo({
            email: useremail,
            email_code: 0,
            owner: _owneraddress,
            signer: _signaddress,
            manager: _manager
        });
        userinfo[useremail] = _userinfo;
        minDelay = delay;
        initialized = 1;
    }

    function setEthTransPayee(
        uint256 amount,
        address payee,
        address to,
        uint256 delay,
        string calldata hash,
        bytes calldata signature
    ) public onlyManager {
        if (ethpayeeinfo.delay != 0 && ethpayeeinfo.delay >= block.timestamp)
            revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
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
            emit ReEthTransPayee(payee, to, amount);
        } else if (ethpayeeinfo.delay == 0) {
            ethpayeeinfo = PayEthOrder({
                payee: payee,
                delay: block.timestamp + delay,
                amount: amount,
                to: to
            });
            emit EthTransPayee(payee, to, amount);
        }
    }

    function setTokenTransPayee(
        address tokencontract,
        uint256 amount,
        address to,
        address payee,
        uint256 delay,
        string calldata hash,
        bytes calldata signature
    ) public onlyManager {
        if (
            tokenpayeeinfo.delay != 0 && tokenpayeeinfo.delay >= block.timestamp
        ) revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
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
        string calldata hash,
        bytes calldata signature
    ) public onlyManager {
        if (nftpayeeinfo.delay != 0 && nftpayeeinfo.delay >= block.timestamp)
            revert AlreadyHasPendingOrder();
        if (delay < minDelay) {
            revert TimelockInsufficientDelay(delay, minDelay);
        }
        if (!isValidUserSignature(hash, signature))
            revert InvalidUserSignature();
        if (IERC721(tokencontract).ownerOf(tokenID) != address(this)) {
            revert ENotEnoughTokenBalance(
                IERC20(tokencontract).balanceOf(address(this))
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

    function resetOrforgetPassword(
        address newowner,
        uint256 emailcode,
        bytes calldata managersignemailcode,
        string calldata random,
        bytes calldata usersignrandom
    ) public onlyManager {
        string memory _email_code = concatStrings(useremail, emailcode);
        if (!isValidManagerSignature(_email_code, managersignemailcode))
            revert InvalidManagerSignature();
        if (!isValidUserSignature(random, usersignrandom))
            revert InvalidUserSignature();
        userinfo[useremail].email_code = emailcode;
        userinfo[useremail].owner = newowner;
    }

    function executeCall(
        address to,
        uint256 value,
        bytes calldata _calldata
    ) external payable onlyOwner returns (bytes memory) {
        return Address.functionCallWithValue(to, _calldata, value);
    }

    function executeEthTrans() external {
        if (ethpayeeinfo.delay == 0) revert NotPayeesetted();
        if (ethpayeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (ethpayeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        Address.sendValue(payable(ethpayeeinfo.to), ethpayeeinfo.amount);
        ethpayeeinfo.delay = 1;
    }

    function executeTokenTrans() external {
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

    function executeNFTTrans() external {
        //  PayNFTOrder memory payeeinfo = payNFTinfo[useremail];
        if (nftpayeeinfo.delay == 0) revert NotPayeesetted();
        if (nftpayeeinfo.delay < block.timestamp) revert InvalidPayeeTime();
        if (nftpayeeinfo.payee != msg.sender) revert NotPayeeAuthorized();
        IERC721(nftpayeeinfo.contractaddress).transferFrom(
            address(this),
            nftpayeeinfo.to,
            nftpayeeinfo.tokenID
        );
        nftpayeeinfo.delay = 1;
    }

    function resetManaget(address manager) public onlyManager {
        if (manager == address(0)) revert InvalidInput();
        userinfo[useremail].manager = manager;
    }

    function resetSignAddress(address signer) external onlyOwner {
        if (signer == address(0)) revert InvalidInput();
        userinfo[useremail].signer = signer;
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

    function email() internal view returns (string memory) {
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
        return userinfo[useremail].signer;
    }

    function getManager() public view virtual returns (address) {
        return userinfo[useremail].manager;
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
        string calldata _veridata,
        bytes calldata signature
    ) public view returns (bool) {
        bytes32 _msghash = getMessageHash(_veridata);
        address _owner = userinfo[useremail].signer;
        return isValidSignature(_owner, _msghash, signature);
    }

    function isValidManagerSignature(
        string memory _veridata,
        bytes calldata signature
    ) public view returns (bool) {
        bytes32 _msghash = getMessageHash(_veridata);
        address _manager = userinfo[useremail].manager;
        return isValidSignature(_manager, _msghash, signature);
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
        return SignatureChecker.isValidSignatureNow(_owner, hash, signature);
    }

    function concatStrings(string memory a, uint256 b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }

    fallback() external payable {}

    receive() external payable {}
}
