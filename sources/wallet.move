module mint_nft::create_nft_with_resource_account {
    use std::vector;
    use aptos_token::token;
    use std::signer;
    use std::string::{Self,String};
    use aptos_token::token::TokenDataId;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::resource_account;
    use aptos_framework::account;
    use std::error;
    use aptos_std::smart_table::{Self, SmartTable};

    struct SigData has copy, drop, store {
        signer_address: address,
        signature: String,
    }
    struct ModuleData has key {
        signer_cap: SignerCapability,
        owner_address:address,
        manager_address:address,
        signer_address:address,
        signature:SmartTable<u64, SigData>,
    }

    /// `init_module` is automatically called when publishing the module.
    /// In this function, we create an example NFT collection and an example token.
    fun init_module(resource_signer: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_signer, @source_addr);
        move_to(resource_signer, ModuleData {
            signer_cap: resource_signer_cap,
            owner_address: @owner_addr,
            manager_address: @manager_addr,
            signer_address: @signer_addr,
            signature:smart_table::new(),
        });
    }
    const ENOT_AUTHORIZED: u64 = 0;
    #[view]
     public  fun getManager(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@mint_nft);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        *manager_address
    }
    #[view]
     public  fun getOwner(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@mint_nft);
        let owner_address = &module_data.owner_address;
        // Abort if the caller is not the manager of this module.
        *owner_address
    }
    #[view]
     public  fun getSignerAddress(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@mint_nft);
        let signer_address = &module_data.signer_address;
        // Abort if the caller is not the manager of this module.
        *signer_address
    }


    const ENOT_VALID_SIGINDEX:u64=0;

#[view]
    public  fun readSig():(address,String) acquires ModuleData {
   // public  fun readSig(modTurn:u64):(address,String) acquires ModuleData {
         let module_data = borrow_global<ModuleData>(@mint_nft);
         let signature_table = &module_data.signature;
         let length = smart_table::length(signature_table);
        // assert!(modTurn <= length, error::permission_denied(ENOT_VALID_SIGINDEX));
         let _sigturn = smart_table::borrow(signature_table, length);
        (_sigturn.signer_address, _sigturn.signature) 
    }

    //only manager
    public entry fun resetOrforgetPassword(manager_signer: &signer, sig:String, newowner_address:address)acquires ModuleData{
        let caller_address = signer::address_of(manager_signer);
        let module_data = borrow_global_mut<ModuleData>(@mint_nft);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address == *manager_address, error::permission_denied(ENOT_AUTHORIZED));
        module_data.owner_address = newowner_address;
        
        //to-do-list Verify the signer_address and Sig
        let signer_address = &module_data.signer_address;
        let signature_table = &mut module_data.signature;
        let length = smart_table::length(signature_table);
        smart_table::borrow_mut_with_default(signature_table, length+1, SigData {
                signature: sig,
                signer_address: *signer_address,
            });
    }

    //only manager
    public entry fun resetManager(manager_signer: &signer,newmanager_address:address)acquires ModuleData{
        let caller_address = signer::address_of(manager_signer);
        let module_data = borrow_global_mut<ModuleData>(@mint_nft);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*manager_address, error::permission_denied(ENOT_AUTHORIZED));
        module_data.manager_address = newmanager_address;
    }

    //only owner
    public entry fun resetSigner(account_signer: &signer, newsigner_address:address)acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@mint_nft);
        let owner_address = &module_data.owner_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*owner_address, error::permission_denied(ENOT_AUTHORIZED));
        module_data.signer_address = newsigner_address;
    }

    const ENOT_INITIALIZED: u64 = 0;
    struct NumberHolder has key {
        u8: u8,
    }
        #[view]
    public fun get_number(): (u8) acquires NumberHolder, ModuleData{
        let module_data = borrow_global<ModuleData>(@mint_nft);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        let account_addr = signer::address_of(&resource_signer);
        assert!(exists<NumberHolder>(account_addr), error::not_found(ENOT_INITIALIZED));
        let holder = borrow_global<NumberHolder>(account_addr);
        holder.u8
    }

    public entry fun set_number(
        account: &signer,
        u8: u8,
    )
    acquires NumberHolder, ModuleData {
        let module_data = borrow_global<ModuleData>(@mint_nft);
        let owner_address = &module_data.owner_address;
        let caller_address = signer::address_of(account);
        assert!(caller_address == *owner_address, error::permission_denied(ENOT_AUTHORIZED));

        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        let account_addr = signer::address_of(&resource_signer);
        if (!exists<NumberHolder>(account_addr)) {
            move_to(&resource_signer, NumberHolder {
                u8,
            })
        } else {
            let old_holder = borrow_global_mut<NumberHolder>(account_addr);
            old_holder.u8 = u8;
        }
    }

}
