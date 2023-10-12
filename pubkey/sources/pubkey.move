module pubkey::test_pubkey_addressv3 {
    use std::signer;
    use aptos_std::ed25519;
    use aptos_std::from_bcs;
    use std::string::{Self,String,utf8};

    const ENOT_AUTHORIZED: u64 = 0;
    const EINVALID_PROOF_OF_KNOWLEDGE: u64 = 8;


    struct ModuleData has key {
        owner_address:address,
        owner_public_key: ed25519::ValidatedPublicKey,
        res:bool
    }

    public entry fun set_owner_public_key(account_signer: &signer, pk_bytes: vector<u8>) acquires ModuleData {
        let caller_address = signer::address_of(account_signer);
        if (!exists<ModuleData>(caller_address)) {
            move_to(account_signer, ModuleData {
                owner_address:caller_address,
                owner_public_key:std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(pk_bytes)),
                res:false
            })
        } else {
            let old_message_holder = borrow_global_mut<ModuleData>(caller_address);
            old_message_holder.owner_public_key = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(pk_bytes));
        }
    }

    public entry fun get_owner_address(account_signer: &signer) acquires ModuleData {
        let caller_address = signer::address_of(account_signer);
        let old_message_holder = borrow_global_mut<ModuleData>(caller_address);
        let curr_auth_key = ed25519::validated_public_key_to_authentication_key(&old_message_holder.owner_public_key);
        let addr = from_bcs::to_address(curr_auth_key);
        old_message_holder.owner_address = addr;
        //alice_address
    }

    public entry fun acquire_valid_user_sig(
        account_signer: &signer,
        signature: vector<u8>,
        sign_message: vector<u8>
    ) acquires ModuleData {
        let caller_address = signer::address_of(account_signer);
        let old_message_holder = borrow_global_mut<ModuleData>(caller_address);
        let pk = ed25519::public_key_into_unvalidated(old_message_holder.owner_public_key);

        let sig = ed25519::new_signature_from_bytes(signature);
        if( ed25519::signature_verify_strict(&sig, &pk, sign_message)){
            old_message_holder.res=true
         }
    }


    public entry fun acquire_valid_user_sigv2(
        account_signer: &signer,
        signature: vector<u8>,
    ) acquires ModuleData {
        let caller_address = signer::address_of(account_signer);
        let old_message_holder = borrow_global_mut<ModuleData>(caller_address);
        let pk = ed25519::public_key_into_unvalidated(old_message_holder.owner_public_key);

        let sig = ed25519::new_signature_from_bytes(signature);
        if( ed25519::signature_verify_strict(&sig, &pk, x"01")){
            old_message_holder.res=true
         }
    }


   use std::debug;
    #[test]
    fun test_gen_sign_verify_combo() {
        let (sk, vpk) = ed25519::generate_keys();
      //  sk.bytes=x"a434bb088ae8a69d5884a71fe85699b9a058cf9e2b688f50309bafb2f14ec44ea9b418c914b523b07d0836672a621319d2cc7069a06265e3b52853a2339e3efd";
       // vpk.bytes=x"a9b418c914b523b07d0836672a621319d2cc7069a06265e3b52853a2339e3efd";
        //let vpk = std::option::extract(&mut ed25519::new_validated_public_key_from_bytes(x"a9b418c914b523b07d0836672a621319d2cc7069a06265e3b52853a2339e3efd"));
        debug::print(&sk);
        let pk = ed25519::public_key_into_unvalidated(vpk);
        debug::print(&pk);
        // let greet:String = utf8(b"Welcome to Aptos Move by Examples"); 
        // let msg1: vector<u8> = greeting(greet);
        let msg1: vector<u8> = b"Welcome to Aptos Move by Examples";
        debug::print(&msg1);
        let sig1 = ed25519::sign_arbitrary_bytes(&sk, msg1);
        debug::print(&sig1);
        assert!(ed25519::signature_verify_strict(&sig1, &pk, msg1), std::error::invalid_state(1));

        // let msg2 = TestMessage {
        //     title: b"Some Title",
        //     content: b"That is it.",
        // };
        // let sig2 = sign_struct(&sk, copy msg2);
        // assert!(signature_verify_strict_t(&sig2, &pk, copy msg2), std::error::invalid_state(2));
    }


    fun greeting(str:String):vector<u8> {
        //let greet:String = utf8(b"Welcome to Aptos Move by Example"); 
        return *string::bytes(&str)
    }

}