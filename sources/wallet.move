module hdwallet::create_nft_with_resource_account {
    use std::vector;
    use aptos_token::token;
    use std::signer;
    use std::string::{Self,String};
    use aptos_framework::account::SignerCapability;
    use aptos_framework::resource_account;
    use aptos_framework::account;
    use std::error;
    use aptos_framework::aptos_account;
    use aptos_std::ed25519;
    use aptos_std::from_bcs;
    use aptos_framework::timestamp;
    use aptos_std::type_info::{Self, TypeInfo};

    const E_AUTHORIZED: u64 =0;
    const E_USER_SIGNATURE_NOT_SATISFIED: u64 =1;
    const E_MANAGER_SIGNATURE_NOT_SATISFIED: u64 =2;
    const E_NOT_VALID_PUBKEY: u64 =3;
    const E_PUBKEY_ALREADY_INITIALIZED: u64 = 4;
    const E_INVALID_ZERO_AMOUNT:u64=5;
    const E_DELAY_LESS_THAN_300:u64=6;
    const E_HAS_PENDING_ORDER:u64=7;
    const E_OUT_DATE_ORDER:u64=8;

    struct ModuleData has key {
        signer_cap: SignerCapability,
        owner_address:address,
        manager_address:address,
        signer_address:address,
    }

    struct PayAptosOrder has copy, drop, store {
        delay: u64,
        payee: address,
        receiver: address,
        amount: u64,
    }

    struct PayCoinOrder has copy, drop, store {
        account_address: address,
        module_name: String,
        struct_name: String,
        delay: u64,
        payee: address,
        receiver: address,
        amount: u64,
    }

    struct PayNFTTokenOrder has copy, drop, store {
        delay: u64,
        payee: address,
        receiver:address,
        creator: address,
        collection_name:String,
        token_name:String,
        token_property_version:u64,
        amount:u64,
    }

    struct ModulePublicKey has key{
        manager_public_key: ed25519::ValidatedPublicKey,
        signer_public_key: ed25519::ValidatedPublicKey,
    }

    /// `init_module` is automatically called when publishing the module.
    fun init_module(resource_signer: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_signer, @source_addr);
        move_to(resource_signer, ModuleData {
            signer_cap: resource_signer_cap,
            owner_address: @owner_addr,
            manager_address: @manager_addr,
            signer_address: @signer_addr,
        });
    }

    // only manager and key Not initialized
    public entry fun initilized_public_key(
        account_signer: &signer, 
        manager_public_key: vector<u8>,
        signer_public_key: vector<u8>) 
        acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(@hdwallet);
      //  let manager_address = &module_data.manager_address;
        assert!(caller_address == module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        assert!(!exists<ModulePublicKey>(@hdwallet),E_PUBKEY_ALREADY_INITIALIZED);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        move_to(&resource_signer, ModulePublicKey {
            manager_public_key: std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(manager_public_key)),
            signer_public_key: std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(signer_public_key)),
        });
    }

    fun convertStringToVector(str:String):vector<u8> {
        return *string::bytes(&str)
    }

    fun acquire_valid_user_sign_sig(
        signature: vector<u8>,
        sign_message: String
    ):bool acquires ModulePublicKey {
        let module_key_data = borrow_global<ModulePublicKey>(@hdwallet);
        let pk = ed25519::public_key_into_unvalidated(module_key_data.signer_public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        ed25519::signature_verify_strict(&sig, &pk, convertStringToVector(sign_message))
    }

    fun acquire_valid_manager_sig(
        signature: vector<u8>,
        sign_message: String
    ):bool acquires ModulePublicKey {
        let module_key_data = borrow_global<ModulePublicKey>(@hdwallet);
        let pk = ed25519::public_key_into_unvalidated(module_key_data.manager_public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        ed25519::signature_verify_strict(&sig, &pk, convertStringToVector(sign_message))
    }

    //only user_signer_address
    public entry fun resetOwner(
        account_signer: &signer,
        user_signature: vector<u8>, 
        user_sign_message: String, 
        manager_signature: vector<u8>, 
        manager_sign_message: String, 
        newowner_address:address )
        acquires ModuleData,ModulePublicKey{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        assert!(caller_address == module_data.signer_address, error::permission_denied(E_AUTHORIZED));
        assert!(acquire_valid_user_sign_sig(user_signature, user_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        assert!(acquire_valid_manager_sig(manager_signature, manager_sign_message),E_MANAGER_SIGNATURE_NOT_SATISFIED);
        module_data.owner_address = newowner_address;
    }

    //only manager
    public entry fun resetManager(
        manager_signer: &signer, 
        new_manager_pub_key:vector<u8>, 
        signature: vector<u8>, 
        sign_message: vector<u8>)
        acquires ModuleData,ModulePublicKey{
        let caller_address = signer::address_of(manager_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        assert!(caller_address == module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        let new_managerr_public_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(new_manager_pub_key));
        let curr_auth_key = ed25519::validated_public_key_to_authentication_key(&new_managerr_public_key);
        let new_manager_addr = from_bcs::to_address(curr_auth_key);
        let pk = ed25519::public_key_into_unvalidated(new_managerr_public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        assert!(ed25519::signature_verify_strict(&sig, &pk, sign_message),E_NOT_VALID_PUBKEY);
        let module_key_data = borrow_global_mut<ModulePublicKey>(@hdwallet);
        module_data.manager_address = new_manager_addr;
        module_key_data.manager_public_key=new_managerr_public_key;
    }

    //only owner
    public entry fun resetSigner(
        account_signer: &signer, 
        new_user_sign_pub_key:vector<u8>, 
        signature: vector<u8>, 
        sign_message: vector<u8>)
        acquires ModuleData,ModulePublicKey{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(@hdwallet);
        assert!(caller_address == module_data.owner_address, error::permission_denied(E_AUTHORIZED));
        let new_signer_public_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(new_user_sign_pub_key));
        let curr_auth_key = ed25519::validated_public_key_to_authentication_key(&new_signer_public_key);
        let new_signer_addr = from_bcs::to_address(curr_auth_key);
        let pk = ed25519::public_key_into_unvalidated(copy new_signer_public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        assert!(ed25519::signature_verify_strict(&sig, &pk, sign_message),E_NOT_VALID_PUBKEY);
        let module_key_data = borrow_global_mut<ModulePublicKey>(@hdwallet);
        module_data.signer_address = new_signer_addr;
        module_key_data.signer_public_key=new_signer_public_key;
    }

    //only owner
    public entry fun transfer(
        account_signer: &signer,
        to: address, 
        amount: u64)
        acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(@hdwallet);
        assert!(caller_address == module_data.owner_address, error::permission_denied(E_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer(&resource_signer, to, amount);
    }

    //only Aptpayee
    public entry fun payeetransfer(account_signer: &signer)acquires ModuleData,PayAptosOrder{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let aptpayeeorder = borrow_global_mut<PayAptosOrder>(@hdwallet);
        assert!(caller_address == aptpayeeorder.payee, error::permission_denied(E_AUTHORIZED));
        let now = aptos_framework::timestamp::now_seconds();
        assert!(aptpayeeorder.delay >= now,E_OUT_DATE_ORDER);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer(&resource_signer, aptpayeeorder.receiver, aptpayeeorder.amout);
        aptpayeeorder.delay = 0;
    }

    //default delay latency is 5 minutes(300s)
    //only Manager
    public entry fun setAptTransPayee(
        account_signer: &signer, 
        amount: u64, 
        payee:address, 
        receiver: address, 
        delay:u64, 
        user_sign_message:String, 
        user_signature:vector<u8> )
        acquires ModuleData,PayAptosOrder{
        assert!(amount>0,E_INVALID_ZERO_AMOUNT);
        assert!(delay>=300,E_DELAY_LESS_THAN_300);
        assert!(acquire_valid_user_sign_sig(user_signature, user_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let caller_address = signer::address_of(account_signer);
        assert!(caller_address == &module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        let now = aptos_framework::timestamp::now_seconds();
        if(!exists<PayAptosOrder>(@hdwallet)){
            let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
            move_to(&resource_signer, PayAptosOrder {
                delay: delay+now,
                payee:payee,
                receiver:receiver,
                amount:amount
            });
        }else{
            let aptpayeeorder = borrow_global_mut<PayAptosOrder>(@hdwallet);
            assert!(aptpayeeorder.delay < now, E_HAS_PENDING_ORDER);
            aptpayeeorder.delay = delay+now;
            aptpayeeorder.payee=payee;
            aptpayeeorder.receiver=receiver;
            aptpayeeorder.amout=amout;
        }
    }

    //only owner
    public entry fun transfer_coins<CoinType>(account_signer: &signer, to: address, amount: u64)acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(@hdwallet);
        assert!(caller_address == module_data.owner_address, error::permission_denied(E_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer_coins<CoinType>(&resource_signer, to, amount);
    }

    //only coin payee
    public entry fun payee_transfer_coins<CoinType>(account_signer: &signer)acquires ModuleData,PayCoinOrder{
        let caller_address = signer::address_of(account_signer);
        let aptpayeeorder = borrow_global_mut<PayCoinOrder>(@hdwallet);
        assert!(caller_address == aptpayeeorder.payee, error::permission_denied(E_AUTHORIZED));
        let now = aptos_framework::timestamp::now_seconds();
        assert!(aptpayeeorder.delay >= now,E_OUT_DATE_ORDER);
        let coiontype = type_info::type_of<CoinType>();
        let accountaddress =  type_info::account_address(&coiontype);
        let modulename =  string::utf8(type_info::module_name(&coiontype));
        let structname =  string::utf8(type_info::struct_name(&coiontype));
        assert!(accountaddress == aptpayeeorder.account_address, error::permission_denied(E_AUTHORIZED));
        assert!(modulename == aptpayeeorder.module_name, error::permission_denied(E_AUTHORIZED));
        assert!(structname == aptpayeeorder.struct_name, error::permission_denied(E_AUTHORIZED));
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer_coins<CoinType>(&resource_signer, aptpayeeorder.receiver, aptpayeeorder.amout);
        aptpayeeorder.delay=0;
    }

    // only Manager
    public entry fun setCoinTransPayee<CoinType>(
        account_signer: &signer, 
        amount: u64, 
        payee:address, 
        receiver: address, 
        delay:u64, 
        user_sign_message:String, 
        user_signature:vector<u8> )
        acquires ModuleData,PayCoinOrder{
        assert!(amount > 0, E_INVALID_ZERO_AMOUNT);
        assert!(delay >= 300, E_DELAY_LESS_THAN_300);
        assert!(acquire_valid_user_sign_sig(user_signature, user_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(@hdwallet);
        assert!(caller_address == module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        let coiontype = type_info::type_of<CoinType>();
        let accountaddress =  type_info::account_address(&coiontype);
        let modulename =  string::utf8(type_info::module_name(&coiontype));
        let structname =  string::utf8(type_info::struct_name(&coiontype));
        let now = aptos_framework::timestamp::now_seconds();
        if(!exists<PayCoinOrder>(@hdwallet)){
            let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
            move_to(&resource_signer, PayCoinOrder {
                account_address: accountaddress,
                module_name: modulename,
                struct_name: structname,
                delay: delay+now,
                payee:payee,
                receiver:receiver,
                amount:amount
            });
        }else{
            let aptpayeeorder = borrow_global_mut<PayCoinOrder>(@hdwallet);
            assert!(aptpayeeorder.delay < now,E_HAS_PENDING_ORDER);
            aptpayeeorder.account_address=accountaddress,
            aptpayeeorder.module_name=modulename,
            aptpayeeorder.struct_name=structname,
            aptpayeeorder.delay = delay+now,
            aptpayeeorder.payee=payee,
            aptpayeeorder.receiver=receiver,
            aptpayeeorder.amout=amout,
        }
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
        let module_data = borrow_global<ModuleData>(@hdwallet);
        assert!(caller_address == module_data.owner_address, error::permission_denied(E_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, token_property_version);
        token::transfer(&resource_signer, token_id, to, amount);
    }

    // must execute opt_in_receive_nft() before receiving any NFT token asserts.
    public entry fun opt_in_receive_nft()acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        token::opt_in_direct_transfer(&resource_signer,true);
    }

    //only NFT payee
    public entry fun payee_transfer_NFT(account_signer: &signer)acquires ModuleData,PayNFTTokenOrder{
        let caller_address = signer::address_of(account_signer);
        let aptpayeeorder = borrow_global_mut<PayNFTTokenOrder>(@hdwallet);
        assert!(caller_address == aptpayeeorder.payee, error::permission_denied(E_AUTHORIZED));
        let now = aptos_framework::timestamp::now_seconds();
        assert!(aptpayeeorder.delay >= now,E_OUT_DATE_ORDER);
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        let token_id = token::create_token_id_raw(aptpayeeorder.creator, aptpayeeorder.collection_name, aptpayeeorder.token_name, aptpayeeorder.token_property_version);
        token::transfer(&resource_signer, token_id, aptpayeeorder.receiver, aptpayeeorder.amount);
        aptpayeeorder.delay=0;
    }

    //only Manager
    public entry fun setNFTTransPayee(
        account_signer: &signer, 
        amount: u64, 
        payee:address, 
        receiver: address, 
        delay:u64, 
        creator:address,
        collection_name:String,
        token_name:String,
        token_property_version:u64,
        user_sign_message:String, 
        user_signature:vector<u8>)
        acquires ModuleData,PayNFTTokenOrder{
        let caller_address = signer::address_of(account_signer);
        assert!(caller_address == module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        assert!(amount>0,E_INVALID_ZERO_AMOUNT);
        assert!(delay>=300,E_DELAY_LESS_THAN_300);
        assert!(acquire_valid_user_sign_sig(user_signature, user_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        let module_data = borrow_global<ModuleData>(@hdwallet);
        let now = aptos_framework::timestamp::now_seconds();
        if(!exists<PayNFTTokenOrder>(@hdwallet)){
            let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
            move_to(&resource_signer, PayNFTTokenOrder {
                creator: creator,
                collection_name: collection_name,
                token_name: token_name,
                token_property_version:token_property_version,
                delay: delay+now,
                payee:payee,
                receiver:receiver,
                amount:amount
            });
        }else{
            let aptpayeeorder = borrow_global_mut<PayNFTTokenOrder>(@hdwallet);
            assert!(aptpayeeorder.delay < now,E_HAS_PENDING_ORDER);
            aptpayeeorder.creator=creator,
            aptpayeeorder.collection_name=collection_name,
            aptpayeeorder.token_name=token_name,
            aptpayeeorder.token_property_version=token_property_version,
            aptpayeeorder.delay = delay+now;
            aptpayeeorder.payee=payee;
            aptpayeeorder.receiver=receiver;
            aptpayeeorder.amout=amout;
        }
    }

    #[view]
     public fun getManager(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@hdwallet);
        module_data.manager_address;
    }
    #[view]
     public fun getOwner(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@hdwallet);
        module_data.owner_address;
    }
    #[view]
     public fun getSignerAddress(): (address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(@hdwallet);
        module_data.signer_address;
    }
}