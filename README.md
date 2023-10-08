1. 将资源发布到资源号中，签名放在账户中，每次调用资源号的数据就不用额外签名
> aptos move create-resource-account-and-publish-package --seed owne123 --address-name mint_nft --profile nft-mint --named-addresses source_addr=f32dab3492272b1ef0608fac0344d5f1058589db91f52f573b75a2ed0209c8cf,owner_addr=119aedb5c669cc687a84d29467c507448993ec520ef1b743cf62aee838e59c04,manager_addr=9d70be865987802127264da700201ca2bee329ca276d0660e0eb763db5be191a,signer_addr=9d70be865987802127264da700201ca2bee329ca276d0660e0eb763db5be191a

其中，不同的seed表示不同的资源号

2. 通过 resource——address的资源管控该账号，内部资源写入owner_address 和 manager_address,受限的函数可以通过这两个账号限制
```move
    //only manager
    public entry fun resetOrforgetPassword(manager_signer: &signer, sig:string::String,newowner_address:address)acquires ModuleData{
        let caller_address = signer::address_of(manager_signer);
        let module_data = borrow_global_mut<ModuleData>(@mint_nft);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address == *manager_address, error::permission_denied(ENOT_AUTHORIZED));
        module_data.owner_address = newowner_address;
    }

    //only manager
    public entry fun resetManager(manager_signer: &signer, sig:string::String,newmanager_address:address)acquires ModuleData{
        let caller_address = signer::address_of(manager_signer);
        let module_data = borrow_global_mut<ModuleData>(@mint_nft);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*manager_address, error::permission_denied(ENOT_AUTHORIZED));
        module_data.manager_address = newmanager_address;
    }
```
3. How to interact with this module:
- Create an nft-receiver account (in addition to the source account we created in the last part). We'll use this account to receive an NFT in this tutorial.

>  aptos init --profile nft-receiver

- Publish the module under a resource account.

> aptos move create-resource-account-and-publish-package --seed [seed] --address-name mint_nft --profile default --named-addresses source_addr=[default account's address]

- Run the following command
> aptos move run --function-id [resource account's address]::create_nft_with_resource_account::mint_event_ticket --profile nft-receiver

- Check out the transaction on https://explorer.aptoslabs.com/ by searching for the transaction hash.
