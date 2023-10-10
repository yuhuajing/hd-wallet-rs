 发布合约
> aptos move publish 

配置文件中的地址必须在根目录下拥有私钥

1.  合约发布后需要执行 init_candy，输入相应的参数，NFT资源被存储在资源账号中
2. mint操作需要输入资源账号的地址
3. 转账时，需要接收方执行 opt_in_receive_nft()函数，表示同意接收NFT


0x9a5d772d8cde6d444c0a3c9ba1b0ca6b90e5580935b6e021a8cca658c0f0043f