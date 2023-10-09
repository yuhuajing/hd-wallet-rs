 module ClayCoin::clay_coin_v2 {
    use std::signer;
    use std::string;
    use aptos_framework::timestamp;
    use std::event;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin, MintCapability, FreezeCapability, BurnCapability};

    const ENOT_ADMIN:u64=0;
    const E_DONT_HAVE_CAPABILITY:u64=1;
    const E_HAVE_CAPABILITY:u64=2;
    const ENOT_ENOUGH_TOKEN:u64=3;
    const E_MINT_FORBIDDEN:u64=4;
    const E_ADDR_NOT_REGISTED_CLAYCoin:u64=5;
    const ERR_NO_UNLOCKED:u64=6;
    const ENOT_VALID_LOCK_TIME:u64=7;
    const E_NOT_WHIIELIST:u64=8;
    const DEPLOYER: address = @ClayCoin;
    const RESOURCE_ACCOUNT_ADDRESS: address = @staking;
    const TEAM_ADDRESS: address = @team;

    struct CLAYCoin has key {}

    struct LockedCLAY has key {
        coins: Coin<CLAYCoin>,
        vec : vector<LockedItem>,
    }

    struct LockedItem has key, store, drop {
        amount: u64,
        owner: address,
        unlock_timestamp: u64,
    }

    // struct Coinabilities has key{
    //     mint_cap: coin::MintCapability<CLAYCoin>,
    //     burn_cap: coin::BurnCapability<CLAYCoin>,
    //     freeze_cap: coin::FreezeCapability<CLAYCoin>
    // }

    struct Caps has key {
        admin_address: address, // admin address, control direct mint ANI and other setting
        staking_address: address,   // staking address (masterchef resource address), which can also mint ANI
        direct_mint: bool,
        mint: MintCapability<CLAYCoin>,
        freeze: FreezeCapability<CLAYCoin>,
        burn: BurnCapability<CLAYCoin>,
        mint_event: event::EventHandle<MintBurnEvent>,
        burn_event: event::EventHandle<MintBurnEvent>,
    }

    struct MintBurnEvent has drop, store {
        value: u64,
    }

    public fun has_coin_capabilities(addr:address){
        assert!(exists<Caps>(addr),E_DONT_HAVE_CAPABILITY);
    }
    public fun not_has_coin_capabilities(addr:address){
        assert!(!exists<Caps>(addr),E_HAVE_CAPABILITY);
    }

    fun init_module(admin: &signer){
        let account_addr = signer::address_of(admin);
        not_has_coin_capabilities(account_addr);
        let (burn_cap,freeze_cap,mint_cap) = coin::initialize<CLAYCoin>(
            admin,
            string::utf8(b"CLAY Coin"),
            string::utf8(b"THJ"),
            8,
            true,
        );

        move_to(admin,Caps{
                admin_address: DEPLOYER, // admin address, control direct mint ANI and other setting
                staking_address: RESOURCE_ACCOUNT_ADDRESS,   // staking address (masterchef resource address), which can also mint ANI
                direct_mint: true,
                mint: mint_cap,
                freeze: freeze_cap,
                burn: burn_cap,
                mint_event: account::new_event_handle<MintBurnEvent>(admin),
                burn_event: account::new_event_handle<MintBurnEvent>(admin),
            });

        register(admin);

        move_to(admin, LockedCLAY {
            coins: coin::zero<CLAYCoin>(),
            vec: vector::empty(),
        });
       //team_emission(admin);
    }

    fun team_emission(admin: &signer)acquires Caps,LockedCLAY {
        let count = 1;
        while (count <= 1) {
            mint_lock_CLAY(admin, TEAM_ADDRESS, 50000000000000, count * 90);
            count = count + 1;
        };
    }

        /// Mint CLAY with a lock period.
    public fun mint_lock_CLAY(
        admin: &signer,
        to: address,
        amount: u64,
        days_to_unlock: u64,
    ) acquires Caps, LockedCLAY {
        let admin_addr = signer::address_of(admin);
        has_coin_capabilities(admin_addr);
        is_admin(admin_addr);
        assert!(days_to_unlock >= 1, ENOT_VALID_LOCK_TIME);       
        let caps = borrow_global_mut<Caps>(DEPLOYER);
        let locked_CLAY = borrow_global_mut<LockedCLAY>(DEPLOYER);
        let coins = coin::mint<CLAYCoin>(amount, &caps.mint);
        coin::merge(&mut locked_CLAY.coins, coins);
        vector::push_back(&mut locked_CLAY.vec, LockedItem {
            amount: amount,
            owner: to,
            unlock_timestamp: timestamp::now_seconds() + days_to_unlock * 86400,
        });
        event::emit_event(&mut caps.mint_event, MintBurnEvent {
            value: amount,
        });
    }

    public entry fun withdraw_unlocked_CLAY(account:&signer)acquires LockedCLAY{
        let account_addr = signer::address_of(account);
        register(account);
        let locked_clay = borrow_global_mut<LockedCLAY>(DEPLOYER);
        let index=0;
        let is_succ = false;
        let now = timestamp::now_seconds();
        while(index < vector::length(&locked_clay.vec)){
            let item = vector::borrow_mut(&mut locked_clay.vec,index);
            if(item.owner == account_addr && item.unlock_timestamp<=now){
                let coins = coin::extract(&mut locked_clay.coins, item.amount);
                coin::deposit<CLAYCoin>(account_addr, coins);
                let _removed_item = vector::swap_remove(&mut locked_clay.vec, index);
                is_succ = true;
            }else{
                index = index+1;
            }
        };
        assert!(is_succ, ERR_NO_UNLOCKED);
    }

    public entry fun mint_CLAY(admin:&signer,amount:u64,to:address)acquires Caps{
        let admin_addr = signer::address_of(admin);
        is_admin(admin_addr);
        has_coin_capabilities(admin_addr);
       // assert!(coin::is_account_registered<CLAYCoin>(to),E_ADDR_NOT_REGISTED_CLAYCoin);
        let caps = borrow_global_mut<Caps>(DEPLOYER);
        assert!(caps.direct_mint,E_MINT_FORBIDDEN);
        let coins = coin::mint<CLAYCoin>(amount,&caps.mint);
      //  coin::deposit<CLAYCoin>(to, coins);
        coin::deposit(to, coins);
        event::emit_event(&mut caps.mint_event, MintBurnEvent {
            value: amount,
        });
    }

    public fun staking_mint_CLAY(
        staking: &signer,
        amount: u64,
    )acquires Caps {
        let caps = borrow_global<Caps>(DEPLOYER);
        assert!(caps.direct_mint,E_MINT_FORBIDDEN);
        let staking_addr = signer::address_of(staking);
        assert!( staking_addr == caps.staking_address, E_MINT_FORBIDDEN);
        register(staking);
        
        let coins = coin::mint<CLAYCoin>(amount, &caps.mint);
        coin::deposit<CLAYCoin>(staking_addr, coins);
    }

    public entry fun burn_CLAY(
        account: &signer,
        amount: u64
    ) acquires Caps {
        let account_addr = signer::address_of(account);
        assert!(coin::balance<CLAYCoin>(account_addr) >= amount,ENOT_ENOUGH_TOKEN);
        let caps = borrow_global_mut<Caps>(DEPLOYER);
        let coins = coin::withdraw<CLAYCoin>(account, amount);
        coin::burn(coins, &caps.burn);
        event::emit_event(&mut caps.burn_event, MintBurnEvent {
            value: amount,
        });
    }

    public fun burn_CLAY_Coin(
        account:&signer,
        coins: Coin<CLAYCoin>,
    ) acquires Caps {        
        let account_addr = signer::address_of(account);
        is_admin(account_addr);
        has_coin_capabilities(account_addr);
        let amount = coin::value(&coins);
        assert!(coin::balance<CLAYCoin>(account_addr)>=amount,ENOT_ENOUGH_TOKEN);
        let caps = borrow_global_mut<Caps>(DEPLOYER);
        coin::burn(coins, &caps.burn);
        event::emit_event(&mut caps.burn_event, MintBurnEvent {
            value: amount,
        });
    }

    public entry fun register(account: &signer){
        let account_address = signer::address_of(account);
        if (!coin::is_account_registered<CLAYCoin>(account_address)){
            coin::register<CLAYCoin>(account);
        };
    }

    public fun is_admin(admin:address)acquires Caps{
        let caps = borrow_global<Caps>(DEPLOYER);
        assert!(admin==caps.admin_address,ENOT_ADMIN);
    }

    /// Set admin address
    public entry fun set_admin_address(
        admin: &signer,
        new_admin_address: address,
    ) acquires Caps {
        let caps = borrow_global_mut<Caps>(DEPLOYER);
        assert!(signer::address_of(admin) == caps.admin_address, ENOT_ADMIN);
        caps.admin_address = new_admin_address;
    }

    /// Set staking address
    public entry fun set_staking_address(
        admin: &signer,
        new_staking_address: address,
    ) acquires Caps {
        let caps = borrow_global_mut<Caps>(DEPLOYER);
        assert!(signer::address_of(admin) == caps.admin_address, ENOT_ADMIN);
        caps.staking_address = new_staking_address;
    }

    /// After call this, direct mint will be disabled forever
    public entry fun set_disable_direct_mint(
        admin: &signer
    ) acquires Caps {
        let caps = borrow_global_mut<Caps>(DEPLOYER);
        assert!(signer::address_of(admin) == caps.admin_address, ENOT_ADMIN);
        caps.direct_mint = false;
    }

    public entry fun transfer(from:&signer,to:address,amount:u64){
        let from_addr = signer::address_of(from);
        assert!(coin::balance<CLAYCoin>(from_addr)>=amount,ENOT_ENOUGH_TOKEN);
        coin::transfer<CLAYCoin>(from, to, amount);
    }

    public entry fun freeze_user(account: &signer) acquires Caps {
        let account_addr = signer::address_of(account);
      //  is_admin(account_addr);
       // has_coin_capabilities(account_addr);
        let caps = borrow_global<Caps>(DEPLOYER);
        coin::freeze_coin_store<CLAYCoin>(account_addr, &caps.freeze);
    }

    public entry fun unfreeze_user(account: &signer) acquires Caps {
        let account_addr = signer::address_of(account);
       // is_admin(account_addr);
       // has_coin_capabilities(account_addr);
       let caps = borrow_global<Caps>(DEPLOYER);
        coin::unfreeze_coin_store<CLAYCoin>(account_addr, &caps.freeze);
    }

    #[view]
    public fun balance(account:&signer):u64{
        let account_addr = signer::address_of(account);
        coin::balance<CLAYCoin>(account_addr)
    }
 }