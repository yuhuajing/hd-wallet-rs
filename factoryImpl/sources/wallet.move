module hdwallet::create_wallet_factory {
    use aptos_token::token;
    use std::signer;
    use std::string::{Self,String};
    use std::vector;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::account;
    use aptos_framework::coin;
    use std::error;
    use aptos_framework::aptos_account;
    use aptos_std::ed25519;
    use aptos_std::from_bcs;
    use aptos_framework::timestamp;
    use aptos_std::type_info;
    use aptos_std::smart_table::{Self, SmartTable};

    const E_AUTHORIZED: u64 =0;
    const E_USER_SIGNATURE_NOT_SATISFIED: u64 =1;
    const E_MANAGER_SIGNATURE_NOT_SATISFIED: u64 =2;
    const E_SIGNER_SIGNATURE_NOT_SATISFIED:u64=10;
    const E_NOT_VALID_PUBKEY: u64 =3;
    const E_PUBKEY_ALREADY_INITIALIZED: u64 = 4;
    const E_INVALID_ZERO_AMOUNT:u64=5;
    const E_DELAY_LESS_THAN_300:u64=6;
    const E_HAS_PENDING_ORDER:u64=7;
    const E_OUT_DATE_ORDER:u64=8;
    const E_ALRERADY_HAS_WALLET:u64=9;
    const E_DEPULICATED_MANAGER_SIGN_MESSAGE:u64=11;
    const E_DEPULICATED_SIGNER_SIGN_MESSAGE:u64=12;

    struct ModuleData has key {
        signer_cap: SignerCapability,
        owner_address:address,
        manager_address:address,
        signer_address:address,
        manager_public_key: ed25519::ValidatedPublicKey,
        signer_public_key: ed25519::ValidatedPublicKey,
    }

// email is never be changed
    struct WalletData has key {
        wallet_address: SmartTable<String, address>,
        managerSigMessage: vector<String>,
        signerSigMessage: vector<String>
    }

    struct PayAptosOrder has key {
        delay: u64,
        payee: address,
        receiver: address,
        amount: u64,
    }

    struct PayCoinOrder has key {
        account_address: address,
        module_name: String,
        struct_name: String,
        delay: u64,
        payee: address,
        receiver: address,
        amount: u64,
    }

    struct PayNFTTokenOrder has key {
        delay: u64,
        payee: address,
        receiver:address,
        creator: address,
        collection_name:String,
        token_name:String,
        token_property_version:u64,
        amount:u64,
    }

    /// `init_module` is automatically called when publishing the module.
    fun init_module(resource_signer: &signer) {
        move_to(resource_signer, WalletData {
            wallet_address:smart_table::new(),
            managerSigMessage: vector::empty<String>(),
            signerSigMessage: vector::empty<String>()
        });
    }

    //wallet factory
    public entry fun create_wallet(
        account: &signer,
        email: String, //188@163.com
        seed: String, //helloworld
        owner_address: address, //0x119aedb5c669cc687a84d29467c507448993ec520ef1b743cf62aee838e59c04
        manager_address: address,//0x9d70be865987802127264da700201ca2bee329ca276d0660e0eb763db5be191a
        manager_public_key: vector<u8>,//0x47c99a0ea6ee68b436b54842c74d783bf9fb867cb97c1f9975f598ad59e68c94
        manager_signature: vector<u8>, //0x4e6e7861a8ea2766325a38e7d73d77c882424bde98c7128230807b754a5aa1a32415e23bd2cb7de24d11202434adfa4cc49478526500bd6636647ffcfdfc9609
        manager_signmess: String, // IanManager
        signer_address: address, //0x9e7c6a16c798d8ee548faec4b2c4dff7d7ef3f09f56aadd612b9dbdf23859265
        signer_public_key: vector<u8>,//0x4407557bcc3a6c7cc5da6c5e06267a4afbda606143768d5af95a90972a3b916b
        signer_signature: vector<u8>,//0x8e9f3965f58acffe54c607388d4ff88d025733d20a1502d07713a051bea3dc4b7c0dc37945f17547fa168a888806774e4334532a9a27325b3f01a203ad6daa0f
        signer_signmess: String, //IamSigner
    )acquires WalletData {
        let wallet_data = borrow_global_mut<WalletData>(@hdwallet);
        assert!(!vector::contains(&wallet_data.managerSigMessage, &manager_signmess),E_DEPULICATED_MANAGER_SIGN_MESSAGE);
        assert!(!vector::contains(&wallet_data.signerSigMessage, &signer_signmess),E_DEPULICATED_SIGNER_SIGN_MESSAGE);
        vector::push_back(&mut wallet_data.managerSigMessage, manager_signmess);
        vector::push_back(&mut wallet_data.signerSigMessage, signer_signmess);
        let validated_manager_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(manager_public_key));
        let validated_signer_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(signer_public_key));
        assert!(acquire_valid_sig(validated_manager_key, manager_signature, manager_signmess),E_MANAGER_SIGNATURE_NOT_SATISFIED);
        assert!(acquire_valid_sig(validated_signer_key, signer_signature, signer_signmess),E_SIGNER_SIGNATURE_NOT_SATISFIED);
        assert!(!smart_table::contains(&wallet_data.wallet_address,email),E_ALRERADY_HAS_WALLET);
        let seedbytes = *string::bytes(&seed);
        let (resource, resource_cap) = account::create_resource_account(account, seedbytes);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_cap);
        move_to<ModuleData>(&resource_signer_from_cap, ModuleData{
            signer_cap: resource_cap,
            owner_address: owner_address,
            manager_address: manager_address,
            signer_address: signer_address,
            manager_public_key: validated_manager_key,
            signer_public_key: validated_signer_key,
        });
        smart_table::add(&mut wallet_data.wallet_address, email, signer::address_of(&resource));
    }
    
    fun convertStringToVector(str:String):vector<u8> {
        return *string::bytes(&str)
    }

    fun acquire_valid_sig(
        public_key: ed25519::ValidatedPublicKey,
        signature: vector<u8>,
        sign_message: String,
    ):bool{
        let pk = ed25519::public_key_into_unvalidated(public_key);
        let sig = ed25519::new_signature_from_bytes(signature);
        ed25519::signature_verify_strict(&sig, &pk, convertStringToVector(sign_message))
    }

    //only user_signer_address
    public entry fun resetOwner(
        account_signer: &signer,
        walletaddr: address,//0xcad9bfde30bd3d6fb28a05973158a73bf6d8d9152791095272d3a77a9791e497
        user_signer_signature: vector<u8>, //0x8e9f3965f58acffe54c607388d4ff88d025733d20a1502d07713a051bea3dc4b7c0dc37945f17547fa168a888806774e4334532a9a27325b3f01a203ad6daa0f
        user_signer_sign_message: String,  //IamSigner
        manager_signature: vector<u8>, //0x4e6e7861a8ea2766325a38e7d73d77c882424bde98c7128230807b754a5aa1a32415e23bd2cb7de24d11202434adfa4cc49478526500bd6636647ffcfdfc9609 
        manager_sign_message: String, //IanManager
        newowner_address:address ) //0x8e39760cb560a186b203227508172ed0415be9f25f5644d13ddc583cc8966a46
        acquires ModuleData,WalletData {
        let wallet_data = borrow_global_mut<WalletData>(@hdwallet);
        assert!(!vector::contains(&wallet_data.managerSigMessage, &manager_signmess),E_DEPULICATED_MANAGER_SIGN_MESSAGE);
        assert!(!vector::contains(&wallet_data.signerSigMessage, &signer_signmess),E_DEPULICATED_SIGNER_SIGN_MESSAGE);
        vector::push_back(&mut wallet_data.managerSigMessage, manager_signmess);
        vector::push_back(&mut wallet_data.signerSigMessage, signer_signmess);
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(walletaddr);
        assert!(caller_address == module_data.signer_address, error::permission_denied(E_AUTHORIZED));
        assert!(acquire_valid_sig(module_data.signer_public_key, user_signer_signature, user_signer_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        assert!(acquire_valid_sig(module_data.manager_public_key, manager_signature, manager_sign_message),E_MANAGER_SIGNATURE_NOT_SATISFIED);
        module_data.owner_address = newowner_address;
    }

    //only manager
    public entry fun resetManager(
        account_signer: &signer, 
        walletaddr: address,
        new_manager_pub_key:vector<u8>, 
        signature: vector<u8>, 
        manager_signmess: String
        )acquires ModuleData,WalletData {
        let wallet_data = borrow_global_mut<WalletData>(@hdwallet);
        assert!(!vector::contains(&wallet_data.managerSigMessage, &manager_signmess),E_DEPULICATED_MANAGER_SIGN_MESSAGE);
        vector::push_back(&mut wallet_data.managerSigMessage, manager_signmess);
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(walletaddr);
        assert!(caller_address == module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        let new_managerr_public_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(new_manager_pub_key));
        assert!(acquire_valid_sig(new_managerr_public_key, signature, convertStringToVector(manager_signmess)),E_USER_SIGNATURE_NOT_SATISFIED);
        let curr_auth_key = ed25519::validated_public_key_to_authentication_key(&new_managerr_public_key);
        let new_manager_addr = from_bcs::to_address(curr_auth_key);
        module_data.manager_address = new_manager_addr;
        module_data.manager_public_key=new_managerr_public_key;
    }

    //only owner
    public entry fun resetSigner(
        account_signer: &signer, 
        walletaddr: address,
        new_user_signer_sign_pub_key:vector<u8>, 
        signature: vector<u8>, 
        signer_signmess: String
        )acquires ModuleData,WalletData {
        let wallet_data = borrow_global_mut<WalletData>(@hdwallet);
        assert!(!vector::contains(&wallet_data.managerSigMessage, &signer_signmess),E_DEPULICATED_MANAGER_SIGN_MESSAGE);
        vector::push_back(&mut wallet_data.managerSigMessage, signer_signmess);
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global_mut<ModuleData>(walletaddr);
        assert!(caller_address == module_data.owner_address, error::permission_denied(E_AUTHORIZED));
        let new_signer_public_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(new_user_signer_sign_pub_key));
        assert!(acquire_valid_sig(new_signer_public_key, signature, convertStringToVector(signer_signmess)),E_USER_SIGNATURE_NOT_SATISFIED);
        let curr_auth_key = ed25519::validated_public_key_to_authentication_key(&new_signer_public_key);
        let new_signer_addr = from_bcs::to_address(curr_auth_key);
        module_data.signer_address = new_signer_addr;
        module_data.signer_public_key=new_signer_public_key;
    }

    //only owner
    public entry fun transfer(
        account_signer: &signer,
        walletaddr: address,
        to: address, 
        amount: u64
        )acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(walletaddr);
        assert!(caller_address == module_data.owner_address, error::permission_denied(E_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer(&resource_signer, to, amount);
    }

    //only Aptpayee
    public entry fun payeetransfer(
        account_signer: &signer,
        walletaddr: address
    )acquires ModuleData,PayAptosOrder{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(walletaddr);
        let aptpayeeorder = borrow_global_mut<PayAptosOrder>(walletaddr);
        assert!(caller_address == aptpayeeorder.payee, error::permission_denied(E_AUTHORIZED));
        let now = timestamp::now_seconds();
        assert!(aptpayeeorder.delay >= now,E_OUT_DATE_ORDER);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer(&resource_signer, aptpayeeorder.receiver, aptpayeeorder.amount);
        aptpayeeorder.delay = 0;
    }

    //default delay latency is 5 minutes(300s)
    //only Manager
    public entry fun setAptTransPayee(
        account_signer: &signer, 
        walletaddr: address,
        amount: u64, 
        payee:address, 
        receiver: address, 
        delay:u64, 
        user_signer_sign_message:String, 
        user_signer_signature:vector<u8> )
        acquires ModuleData,PayAptosOrder,WalletData {
        let wallet_data = borrow_global_mut<WalletData>(@hdwallet);
        assert!(!vector::contains(&wallet_data.signerSigMessage, &signer_signmess),E_DEPULICATED_SIGNER_SIGN_MESSAGE);
        vector::push_back(&mut wallet_data.signerSigMessage, signer_signmess);

        assert!(amount>0,E_INVALID_ZERO_AMOUNT);
        assert!(delay>=300,E_DELAY_LESS_THAN_300);
        let module_data = borrow_global<ModuleData>(walletaddr);
        assert!(acquire_valid_sig(module_data.signer_public_key, user_signer_signature, user_signer_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        let caller_address = signer::address_of(account_signer);
        assert!(caller_address == module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        let now = timestamp::now_seconds();
        if(!exists<PayAptosOrder>(walletaddr)){
            let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
            move_to(&resource_signer, PayAptosOrder {
                delay: delay+now,
                payee:payee,
                receiver:receiver,
                amount:amount
            });
        }else{
            let aptpayeeorder = borrow_global_mut<PayAptosOrder>(walletaddr);
            assert!(aptpayeeorder.delay < now, E_HAS_PENDING_ORDER);
            aptpayeeorder.delay = delay+now;
            aptpayeeorder.payee=payee;
            aptpayeeorder.receiver=receiver;
            aptpayeeorder.amount=amount;
        }
    }

    //only owner
    public entry fun transfer_coins<CoinType>(
        account_signer: &signer, 
        walletaddr:address,
        to: address, 
        amount: u64
        )acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(walletaddr);
        assert!(caller_address == module_data.owner_address, error::permission_denied(E_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer_coins<CoinType>(&resource_signer, to, amount);
    }

    //only coin payee
    public entry fun payee_transfer_coins<CoinType>(
        account_signer: &signer,
        walletaddr: address,
        )acquires ModuleData,PayCoinOrder{
        let caller_address = signer::address_of(account_signer);
        let aptpayeeorder = borrow_global_mut<PayCoinOrder>(walletaddr);
        assert!(caller_address == aptpayeeorder.payee, error::permission_denied(E_AUTHORIZED));
        let now = timestamp::now_seconds();
        assert!(aptpayeeorder.delay >= now,E_OUT_DATE_ORDER);
        let coiontype = type_info::type_of<CoinType>();
        let accountaddress =  type_info::account_address(&coiontype);
        let modulename =  string::utf8(type_info::module_name(&coiontype));
        let structname =  string::utf8(type_info::struct_name(&coiontype));
        assert!(accountaddress == aptpayeeorder.account_address, error::permission_denied(E_AUTHORIZED));
        assert!(modulename == aptpayeeorder.module_name, error::permission_denied(E_AUTHORIZED));
        assert!(structname == aptpayeeorder.struct_name, error::permission_denied(E_AUTHORIZED));
        let module_data = borrow_global<ModuleData>(walletaddr);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        aptos_account::transfer_coins<CoinType>(&resource_signer, aptpayeeorder.receiver, aptpayeeorder.amount);
        aptpayeeorder.delay=0;
    }

    // only Manager
    public entry fun setCoinTransPayee<CoinType>(
        account_signer: &signer, 
        walletaddr: address,
        amount: u64, 
        payee: address, 
        receiver: address, 
        delay: u64, 
        user_signer_sign_message: String, 
        user_signer_signature: vector<u8> 
        )acquires ModuleData,PayCoinOrder,WalletData {
        let wallet_data = borrow_global_mut<WalletData>(@hdwallet);
        assert!(!vector::contains(&wallet_data.signerSigMessage, &signer_signmess),E_DEPULICATED_SIGNER_SIGN_MESSAGE);
        vector::push_back(&mut wallet_data.signerSigMessage, signer_signmess);
        assert!(amount > 0, E_INVALID_ZERO_AMOUNT);
        assert!(delay >= 300, E_DELAY_LESS_THAN_300);
        let module_data = borrow_global<ModuleData>(walletaddr);
        assert!(acquire_valid_sig(module_data.signer_public_key, user_signer_signature, user_signer_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        let caller_address = signer::address_of(account_signer);
        assert!(caller_address == module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        let coiontype = type_info::type_of<CoinType>();
        let accountaddress =  type_info::account_address(&coiontype);
        let modulename =  string::utf8(type_info::module_name(&coiontype));
        let structname =  string::utf8(type_info::struct_name(&coiontype));
        let now = timestamp::now_seconds();
        if(!exists<PayCoinOrder>(walletaddr)){
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
            let aptpayeeorder = borrow_global_mut<PayCoinOrder>(walletaddr);
            assert!(aptpayeeorder.delay < now,E_HAS_PENDING_ORDER);
            aptpayeeorder.account_address=accountaddress;
            aptpayeeorder.module_name=modulename;
            aptpayeeorder.struct_name=structname;
            aptpayeeorder.delay = delay+now;
            aptpayeeorder.payee=payee;
            aptpayeeorder.receiver=receiver;
            aptpayeeorder.amount=amount;
        }
    }

    //only owner
    public entry fun transfer_NFT(
        account_signer: &signer, 
        walletaddr: address,
        to:address,
        creator: address,
        collection_name:String,
        token_name:String,
        token_property_version:u64,
        amount:u64
        )acquires ModuleData{
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(walletaddr);
        assert!(caller_address == module_data.owner_address, error::permission_denied(E_AUTHORIZED));
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, token_property_version);
        token::transfer(&resource_signer, token_id, to, amount);
    }

    // must execute opt_in_receive_nft() before receiving any NFT token asserts.
    public entry fun opt_in_receive_nft(walletaddr: address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(walletaddr);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        token::opt_in_direct_transfer(&resource_signer,true);
    }

        // must execute opt_in_receive_coin()
    public entry fun opt_in_receive_coin<CoinType>(walletaddr: address)acquires ModuleData{
        let module_data = borrow_global<ModuleData>(walletaddr);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        if (!coin::is_account_registered<CoinType>(walletaddr)){
            coin::register<CoinType>(&resource_signer);
        };
    }

    //only NFT payee
    public entry fun payee_transfer_NFT(account_signer: &signer,walletaddr:address,)acquires ModuleData,PayNFTTokenOrder{
        let caller_address = signer::address_of(account_signer);
        let aptpayeeorder = borrow_global_mut<PayNFTTokenOrder>(walletaddr);
        assert!(caller_address == aptpayeeorder.payee, error::permission_denied(E_AUTHORIZED));
        let now = timestamp::now_seconds();
        assert!(aptpayeeorder.delay >= now,E_OUT_DATE_ORDER);
        let module_data = borrow_global<ModuleData>(walletaddr);
        let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);
        let token_id = token::create_token_id_raw(aptpayeeorder.creator, aptpayeeorder.collection_name, aptpayeeorder.token_name, aptpayeeorder.token_property_version);
        token::transfer(&resource_signer, token_id, aptpayeeorder.receiver, aptpayeeorder.amount);
        aptpayeeorder.delay=0;
    }

    //only Manager
    public entry fun setNFTTransPayee(
        account_signer: &signer, 
        walletaddr: address,
        amount: u64, 
        payee: address, 
        receiver: address, 
        delay: u64, 
        creator: address,
        collection_name: String,
        token_name: String,
        token_property_version: u64,
        user_signer_sign_message: String, 
        user_signer_signature: vector<u8>
        )acquires ModuleData,PayNFTTokenOrder,WalletData {
        let wallet_data = borrow_global_mut<WalletData>(@hdwallet);
        assert!(!vector::contains(&wallet_data.signerSigMessage, &signer_signmess),E_DEPULICATED_SIGNER_SIGN_MESSAGE);
        vector::push_back(&mut wallet_data.signerSigMessage, signer_signmess);
        let caller_address = signer::address_of(account_signer);
        let module_data = borrow_global<ModuleData>(walletaddr);
        assert!(caller_address == module_data.manager_address, error::permission_denied(E_AUTHORIZED));
        assert!(amount>0,E_INVALID_ZERO_AMOUNT);
        assert!(delay>=300,E_DELAY_LESS_THAN_300);
        assert!(acquire_valid_sig(module_data.signer_public_key, user_signer_signature, user_signer_sign_message),E_USER_SIGNATURE_NOT_SATISFIED);
        let now = timestamp::now_seconds();
        if(!exists<PayNFTTokenOrder>(walletaddr)){
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
            let aptpayeeorder = borrow_global_mut<PayNFTTokenOrder>(walletaddr);
            assert!(aptpayeeorder.delay < now,E_HAS_PENDING_ORDER);
            aptpayeeorder.creator=creator;
            aptpayeeorder.collection_name=collection_name;
            aptpayeeorder.token_name=token_name;
            aptpayeeorder.token_property_version=token_property_version;
            aptpayeeorder.delay = delay+now;
            aptpayeeorder.payee=payee;
            aptpayeeorder.receiver=receiver;
            aptpayeeorder.amount=amount;
        }
    }
        
    #[view]
    public fun getResAddress(email:String):address acquires WalletData {
         let module_data = borrow_global<WalletData>(@hdwallet);
         let res_address = smart_table::borrow(&module_data.wallet_address, email);
         *res_address
    }

    #[view]
     public fun getManager(walletaddr:address): address acquires ModuleData{
        let module_data = borrow_global<ModuleData>(walletaddr);
        module_data.manager_address
    }
    #[view]
     public fun getOwner(walletaddr:address): address acquires ModuleData{
        let module_data = borrow_global<ModuleData>(walletaddr);
        module_data.owner_address
    }
    #[view]
     public fun getSignerAddress(walletaddr:address): address acquires ModuleData{
        let module_data = borrow_global<ModuleData>(walletaddr);
        module_data.signer_address
    }
}