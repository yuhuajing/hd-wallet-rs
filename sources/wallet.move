module hdwallet::create_nft_with_resource_account {
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
    use aptos_framework::aptos_account;
    use aptos_std::ed25519;
    use aptos_std::from_bcs;

    const ENOT_AUTHORIZED: u64 = 0;
    const E_USER_SIGNATURE_NOT_SATISFIED =1;
    const E_MANAGER_SIGNATURE_NOT_SATISFIED =2;
    const E_NOT_VALID_PUBKEY=3;
    const EINVALID_PROOF_OF_KNOWLEDGE: u64 = 8;

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

    struct ModulePublicKey has key{
        //owner_public_key: ed25519::ValidatedPublicKey,
        manager_public_key: ed25519::ValidatedPublicKey,
        signer_public_key: ed25519::ValidatedPublicKey,
        //signature:SmartTable<u64, SigData>,
    }

    /// `init_module` is automatically called when publishing the module.
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

    fun entry init_public_key(account_signer: &signer, manager_public_key: vector<u8>,signer_public_key: vector<u8>) acquires ModulePublicKey{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address == *manager_address, error::permission_denied(ENOT_AUTHORIZED));
        assert!(!exists<ModulePublicKey>(caller_address),E_PUBKEY_ALREADY_INITIALIZED);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);

        move_to(resource_signer, ModulePublicKey {
            manager_public_key: std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(manager_public_key)),
            signer_public_key: std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(signer_public_key)),
        });
    }

    public fun acquire_valid_user_sign_sig(
        signature: vector<u8>,
        sign_message: vector<u8>
    ):bool acquires ModulePublicKey {
        let module_key_data = borrow_global_mut<ModulePublicKey>(@hdwallet);
        let pk = ed25519::public_key_into_unvalidated(module_key_data.signer_public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        ed25519::signature_verify_strict(&sig, &pk, sign_message)
    }

    public fun acquire_valid_manager_sig(
        signature: vector<u8>,
        sign_message: vector<u8>
    ):bool acquires ModulePublicKey {
        let module_key_data = borrow_global_mut<ModulePublicKey>(@hdwallet);
        let pk = ed25519::public_key_into_unvalidated(module_key_data.manager_public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        ed25519::signature_verify_strict(&sig, &pk, sign_message)
    }

    public entry fun set_owner_public_key(account_signer: &signer, pk_bytes: vector<u8>) acquires ModuleData {
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let owner_address = &module_data.owner_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*owner_address, error::permission_denied(ENOT_AUTHORIZED));
        module_data.owner_public_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(pk_bytes));
    }

    public entry fun set_manager_public_key(account_signer: &signer, pk_bytes: vector<u8>) acquires ModuleData {
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*manager_address, error::permission_denied(ENOT_AUTHORIZED));
        module_data.manager_public_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(pk_bytes));
    }

    //only manager
    public entry fun resetOrforgetPassword(account_signer: &signer,user_signature: vector<u8>, user_sign_message: vector<u8>,manager_signature: vector<u8>, manager_sign_message: vector<u8>, newowner_address:address )acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address == *manager_address, error::permission_denied(ENOT_AUTHORIZED));

        assert!(acquire_valid_user_sign_sig(user_signature, user_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        assert!(acquire_valid_user_sign_sig(manager_signature, manager_sign_message),E_MANAGER_SIGNATURE_NOT_SATISFIED);
        module_data.owner_address = newowner_address;
        // //to-do-list Verify the signer_address and Sig
        // let signer_address = &module_data.signer_address;
        // let signature_table = &mut module_data.signature;
        // let length = smart_table::length(signature_table);
        // smart_table::borrow_mut_with_default(signature_table, length+1, SigData {
        //         signature: sig,
        //         signer_address: *signer_address,
        //     });
    }

    //only manager
    public entry fun resetManager(manager_signer: &signer,new_manager_pub_key:vector<u8>, signature: vector<u8>, sign_message: vector<u8>)acquires ModuleData,ModulePublicKey{
        let caller_address = signer::address_of(manager_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*manager_address, error::permission_denied(ENOT_AUTHORIZED));
        

        let new_managerr_public_key = ed25519::new_validated_public_key_from_bytes(new_user_sign_pub_key);
        let pk = ed25519::public_key_into_unvalidated(copy new_signer_public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        assert!(ed25519::signature_verify_strict(&sig, &pk, sign_message),E_NOT_VALID_PUBKEY);

        let curr_auth_key = ed25519::validated_public_key_to_authentication_key(&new_managerr_public_key);
        let new_manager_addr = from_bcs::to_address(curr_auth_key);
        module_data.manager_address = newmanager_address;

        let module_key_data = borrow_global_mut<ModulePublicKey>(@hdwallet);
        module_key_data.manager_public_key=new_managerr_public_key;
    }

    //only owner
    public entry fun resetSigner(account_signer: &signer, new_user_sign_pub_key:vector<u8>, signature: vector<u8>, sign_message: vector<u8>)acquires ModuleData,ModulePublicKey{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let owner_address = &module_data.owner_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*owner_address, error::permission_denied(ENOT_AUTHORIZED));

        let new_signer_public_key = ed25519::new_validated_public_key_from_bytes(new_user_sign_pub_key);
        let pk = ed25519::public_key_into_unvalidated(copy new_signer_public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        assert!(ed25519::signature_verify_strict(&sig, &pk, sign_message),E_NOT_VALID_PUBKEY);

        let module_key_data = borrow_global_mut<ModulePublicKey>(@hdwallet);
        module_key_data.signer_public_key=new_signer_public_key;
    }

    //only owner
    public entry fun transfer(account_signer: &signer, to: address, amount: u64)acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let owner_address = &module_data.owner_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*owner_address, error::permission_denied(ENOT_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer(&resource_signer, to, amount);
       // module_data.signer_address = newsigner_address;
    }
        //only owner
    public entry fun transfer_coins<CoinType>(account_signer: &signer, to: address, amount: u64)acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let owner_address = &module_data.owner_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*owner_address, error::permission_denied(ENOT_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer_coins<CoinType>(&resource_signer, to, amount);
       // module_data.signer_address = newsigner_address;
    }

        //only owner
    public entry fun transfer_NFT(
        account_signer: &signer, 
        to:address,
        creator: address,
        collection_name:String,
        token_name:String,
        token_property_version:u64,
        amount:u64)
        acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let owner_address = &module_data.owner_address;
        // Abort if the caller is not the manager of this module.
        assert!(caller_address ==*owner_address, error::permission_denied(ENOT_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, token_property_version);
        token::transfer(&resource_signer, token_id, to, amount);
    }

    public entry fun opt_in_receive_nft()acquires ModuleData{
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        token::opt_in_direct_transfer(&resource_signer,true);
    }


        #[view]
     public  fun getManager(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let manager_address = &module_data.manager_address;
        // Abort if the caller is not the manager of this module.
        *manager_address
    }
    #[view]
     public  fun getOwner(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let owner_address = &module_data.owner_address;
        // Abort if the caller is not the manager of this module.
        *owner_address
    }
    #[view]
     public  fun getSignerAddress(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let signer_address = &module_data.signer_address;
        // Abort if the caller is not the manager of this module.
        *signer_address
    }
    const ENOT_VALID_SIGINDEX:u64=0;

    #[view]
    public  fun readSig():(address,String) acquires ModuleData {
   // public  fun readSig(modTurn:u64):(address,String) acquires ModuleData {
         let module_data = borrow_global<ModuleData>(@hdwallet);
         let signature_table = &module_data.signature;
         let length = smart_table::length(signature_table);
        // assert!(modTurn <= length, error::permission_denied(ENOT_VALID_SIGINDEX));
         let _sigturn = smart_table::borrow(signature_table, length);
        (_sigturn.signer_address, _sigturn.signature) 
    }

    const ENOT_INITIALIZED: u64 = 0;
    struct NumberHolder has key {
        u8: u8,
    }
        #[view]
    public fun get_number(): (u8) acquires NumberHolder, ModuleData{
        let module_data = borrow_global<ModuleData>(@hdwallet);
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
        let module_data = borrow_global<ModuleData>(@hdwallet);
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