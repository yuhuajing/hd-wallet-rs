module nfttoken::nftToken{
    use std::signer;
    use std::bcs;
    use std::hash;
    use aptos_std::aptos_hash;
    use aptos_std::from_bcs;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_token::token::{Self};
    use nfttoken::bit_vector::{Self,BitVector};
    use nfttoken::bucket_table::{Self, BucketTable};
    use nfttoken::merkle_proof::{Self};


    const INVALID_SIGNER: u64 = 0;
    const INVALID_amount: u64 = 1;
    const CANNOT_ZERO: u64 = 2;
    const EINVALID_ROYALTY_NUMERATOR_DENOMINATOR: u64 = 3;
    const ESALE_NOT_STARTED: u64 = 4;
    const ESOLD_OUT:u64 = 5;
    const EPAUSED:u64 = 6;
    const INVALID_MUTABLE_CONFIG:u64 = 7;
    const EINVALID_MINT_TIME:u64 = 8;
    const EINVALID_PRE_MINT_TIME:u64 = 12;
    const EINVALID_PUBLIC_MINT_TIME:u64 = 13;
    const MINT_LIMIT_EXCEED: u64 = 9;
    const INVALID_PROOF:u64 = 10;
    const WhitelistMintNotEnabled: u64 = 11;
  //  const MokshyaFee: address = @0x305d730682a5311fbfc729a51b8eec73924b40849bff25cf9fdb4348cc0a719a;

     struct MintData has key {
        total_mints: u64,
        total_apt: u64
    }

    struct NFTMachine has key {
        collection_name: String,
        collection_description: String,
        collection_url: String, //collection_url
        royalty_payee_address:address,
        royalty_points_denominator: u64, 
        royalty_points_numerator: u64, 
        presale_mint_time: u64,
        public_sale_mint_time: u64,
        presale_mint_price: u64,
        public_sale_mint_price: u64,
        paused: bool,
        total_supply: u64, //collection_supply
        minted: u64,
        token_mutate_setting:vector<bool>,
        candies:BitVector,
        public_mint_limit: u64,
        merkle_root: vector<u8>,
        update_event: EventHandle<UpdateNFTEvent>,
    }
    struct Whitelist has key {
        minters: BucketTable<address,u64>,
    }
    struct PublicMinters has key {
        minters: BucketTable<address, u64>,
    }
    struct ResourceInfo has key {
            source: address,
            resource_cap: account::SignerCapability
    }
    struct UpdateNFTEvent has drop, store {
        presale_mint_price: u64,
        presale_mint_time: u64,
        public_sale_mint_price: u64,
        public_sale_mint_time: u64,
        royalty_points_denominator: u64,
        royalty_points_numerator: u64,
    }

    fun init_module(account: &signer) {
        move_to(account, MintData {
            total_mints: 0,
            total_apt: 0
        })
    }

    public entry fun init_candy(
        account: &signer,
        collection_name: String, // qweq
        collection_description: String,//asd
        collection_url: String,//http://clay
        royalty_payee_address:address,//0x9a5d772d8cde6d444c0a3c9ba1b0ca6b90e5580935b6e021a8cca658c0f0043f
        royalty_points_denominator: u64,//100
        royalty_points_numerator: u64,//2
        presale_mint_time: u64,//1
        public_sale_mint_time: u64,//2
        presale_mint_price: u64,//1
        public_sale_mint_price: u64,//1
        total_supply:u64,//100
        collection_mutate_setting:vector<bool>,// [false,false,false]
        token_mutate_setting:vector<bool>, //[false,false,false,false,false]
        public_mint_limit: u64,//7
        seeds: vector<u8>//0x4941564d56
    ){
        let (_resource, resource_cap) = account::create_resource_account(account, seeds);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_cap);
        let now = aptos_framework::timestamp::now_seconds();
        move_to<ResourceInfo>(&resource_signer_from_cap, ResourceInfo{resource_cap: resource_cap, source: signer::address_of(account)});
        assert!(vector::length(&collection_mutate_setting) == 3 && vector::length(&token_mutate_setting) == 5, INVALID_MUTABLE_CONFIG);
        assert!(royalty_points_denominator > 0, EINVALID_ROYALTY_NUMERATOR_DENOMINATOR);
        assert!(public_sale_mint_time > presale_mint_time && presale_mint_time >= 0,EINVALID_MINT_TIME);
        assert!(royalty_points_numerator <= royalty_points_denominator, EINVALID_ROYALTY_NUMERATOR_DENOMINATOR);
        move_to<NFTMachine>(&resource_signer_from_cap, NFTMachine{
            collection_name,
            collection_description,
            collection_url,
            royalty_payee_address,
            royalty_points_denominator,
            royalty_points_numerator,
            presale_mint_time:now+presale_mint_time,
            public_sale_mint_time:public_sale_mint_time+now,
            presale_mint_price,
            public_sale_mint_price,
            total_supply,
            minted:0,
            paused:false,
            candies:bit_vector::new(total_supply),
            token_mutate_setting,
            public_mint_limit,
            merkle_root: vector::empty(),
            update_event: account::new_event_handle<UpdateNFTEvent>(&resource_signer_from_cap),
        });
        
        token::create_collection(
            &resource_signer_from_cap, 
            collection_name, 
            collection_description, 
            collection_url, 
            0, // if collection maximun is 0, there is no number limitaion of the number of different of NFT Types 
            collection_mutate_setting
        );
    }


    public entry fun mint_script(
        receiver: &signer,
        resource_addr: address,
    )acquires ResourceInfo, NFTMachine,MintData,PublicMinters{
        coin::register<0x1::aptos_coin::AptosCoin>(receiver);
        let candy_data = borrow_global_mut<NFTMachine>(resource_addr);
        let mint_price = candy_data.public_sale_mint_price;
        let now = aptos_framework::timestamp::now_seconds();
        assert!(now > candy_data.public_sale_mint_time, ESALE_NOT_STARTED);
        mint(receiver,resource_addr,mint_price)
    }

    public entry fun mint_from_merkle(
        receiver: &signer,
        resource_addr: address,
        proof: vector<vector<u8>>,
        mint_limit: u64
    ) acquires ResourceInfo,MintData,PublicMinters,NFTMachine,Whitelist{
        coin::register<0x1::aptos_coin::AptosCoin>(receiver);
        let receiver_addr = signer::address_of(receiver);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_data.resource_cap);
        let candy_data = borrow_global<NFTMachine>(resource_addr);
        let mint_data = borrow_global_mut<MintData>(@nfttoken);
        let now = aptos_framework::timestamp::now_seconds();
        let leafvec = bcs::to_bytes(&receiver_addr);
        vector::append(&mut leafvec,bcs::to_bytes(&mint_limit));
        let is_whitelist_mint = candy_data.presale_mint_time < now && now < candy_data.public_sale_mint_time;
        assert!(is_whitelist_mint, WhitelistMintNotEnabled);
        assert!(merkle_proof::verify(proof,candy_data.merkle_root,aptos_hash::keccak256(leafvec)),INVALID_PROOF);
        if(!exists<Whitelist>(resource_addr)){
            initialize_whitelist(resource_signer_from_cap)
        };
        // No need to check limit if mint limit = 0, this means the minter can mint unlimited amount of tokens
        if(mint_limit != 0){
            let whitelist_data = borrow_global_mut<Whitelist>(resource_addr);
            if (!bucket_table::contains(&whitelist_data.minters, &receiver_addr)) {
                // First time minting mint limit = 0 
                bucket_table::add(&mut whitelist_data.minters, receiver_addr, 0);
            };
            let minted_nft = bucket_table::borrow_mut(&mut whitelist_data.minters, receiver_addr);
            assert!(*minted_nft != mint_limit, MINT_LIMIT_EXCEED);
            *minted_nft = *minted_nft + 1;
            mint_data.total_apt=mint_data.total_apt+candy_data.presale_mint_price;
        };
        mint(receiver,resource_addr,candy_data.presale_mint_price);
    }

    public entry fun opt_in_receive_nft(
        from: &signer,
        opt_in:bool,
    )acquires ResourceInfo, NFTMachine{
        token::opt_in_direct_transfer(from,opt_in);
    }

     public entry fun transfer_nft(
        from: &signer,
        resource_addr: address,
        to:address,
        token_name:String,
        token_property_version:u64,
        amount:u64,
    )acquires ResourceInfo, NFTMachine{
        let candy_data = borrow_global_mut<NFTMachine>(resource_addr);
        let collection_name = candy_data.collection_name;
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_data.resource_cap);
        let creator = signer::address_of(&resource_signer_from_cap);        
        let token_id = token::create_token_id_raw(creator, collection_name, token_name, token_property_version);
        token::transfer(from, token_id, to, amount);
    }       

    fun mint(
        receiver: &signer,
        resource_addr: address, //resource_account
        mint_price: u64
    )acquires ResourceInfo, NFTMachine,PublicMinters,MintData{
        let receiver_addr = signer::address_of(receiver);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_data.resource_cap);
        let candy_data = borrow_global_mut<NFTMachine>(resource_addr);
        let mint_data = borrow_global_mut<MintData>(@nfttoken);
        let now = aptos_framework::timestamp::now_seconds();
        if(now > candy_data.public_sale_mint_time && candy_data.public_mint_limit != 0){
            initialize_and_create_public_minter(&resource_signer_from_cap,candy_data,receiver_addr,resource_addr);
            mint_data.total_apt=mint_data.total_apt+candy_data.public_sale_mint_price;
        };
        assert!(!candy_data.paused, EPAUSED);
        assert!(candy_data.minted != candy_data.total_supply, ESOLD_OUT);
        let remaining = candy_data.total_supply - candy_data.minted;
        let random_index = pseudo_random(receiver_addr,remaining);
        let required_position=0; // the number of unset 
        let pos=0; // the mint number 
        while (required_position < random_index)
        {
        if (!bit_vector::is_index_set(&candy_data.candies, pos))
            {
                required_position=required_position+1;

            };
        if (required_position == random_index)
            {                    
                break
            };
            pos=pos+1;
        };
        bit_vector::set(&mut candy_data.candies,pos);
        let mint_position = pos;
        let collection_url = candy_data.collection_url;
        let properties = vector::empty<String>();
        string::append(&mut collection_url,num_str(mint_position));
        let token_name = candy_data.collection_name;
        string::append(&mut token_name,string::utf8(b"#"));
        string::append(&mut token_name,num_str(mint_position));
        string::append(&mut collection_url,string::utf8(b".json"));
        let token_mut_config = token::create_token_mutability_config(&candy_data.token_mutate_setting);
        token::create_tokendata(
            &resource_signer_from_cap,
            candy_data.collection_name,
            token_name,
            candy_data.collection_description,
            1,
            collection_url,
            candy_data.royalty_payee_address,
            candy_data.royalty_points_denominator,
            candy_data.royalty_points_numerator,
            token_mut_config,
            properties,
            vector<vector<u8>>[],
            properties
        );
        let token_data_id = token::create_token_data_id(resource_addr,candy_data.collection_name,token_name);
        token::opt_in_direct_transfer(receiver,true);
       // let fee = (300*mint_price)/10000;
        //let collection_owner_price = mint_price - fee;
       // coin::transfer<AptosCoin>(receiver, MokshyaFee, fee);
        coin::transfer<AptosCoin>(receiver, resource_data.source, mint_price);// collection_owner_price);
        token::mint_token_to(
            &resource_signer_from_cap,
            receiver_addr,
            token_data_id,
            1
            );
        candy_data.minted=candy_data.minted+1;
        mint_data.total_mints=mint_data.total_mints+1
    }

    public entry fun set_root(account: &signer,resource_addr: address,merkle_root: vector<u8>) acquires NFTMachine,ResourceInfo{
        let account_addr = signer::address_of(account);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        assert!(resource_data.source == account_addr, INVALID_SIGNER);
        let candy_data = borrow_global_mut<NFTMachine>(resource_addr);
        candy_data.merkle_root = merkle_root
    }

    public entry fun pause_resume_mint(
        account: &signer,
        resource_addr: address,
    )acquires ResourceInfo,NFTMachine{
        let account_addr = signer::address_of(account);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        assert!(resource_data.source == account_addr, INVALID_SIGNER);
        let candy_data = borrow_global_mut<NFTMachine>(resource_addr);
        if(candy_data.paused == true){
            candy_data.paused = false
        }
        else {
            candy_data.paused = true
        }
    }

    public entry fun update_candy(
        account: &signer,
        resource_addr: address,
        royalty_points_denominator: u64,
        royalty_points_numerator: u64,
        presale_mint_time: u64,
        public_sale_mint_price: u64,
        presale_mint_price: u64,
        public_sale_mint_time: u64,
    )acquires ResourceInfo,NFTMachine{
        let account_addr = signer::address_of(account);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        let now = aptos_framework::timestamp::now_seconds();
        assert!(resource_data.source == account_addr, INVALID_SIGNER);
        let candy_data = borrow_global_mut<NFTMachine>(resource_addr);
        if (royalty_points_denominator>0){
            candy_data.royalty_points_denominator = royalty_points_denominator
        };
        if (royalty_points_numerator>0){
            candy_data.royalty_points_numerator = royalty_points_numerator
        };
        if (presale_mint_time>0){
            assert!(presale_mint_time >= now,EINVALID_PRE_MINT_TIME);
            candy_data.presale_mint_time = presale_mint_time
        };
        if (public_sale_mint_time>0){
            assert!(public_sale_mint_time > candy_data.presale_mint_time,EINVALID_PUBLIC_MINT_TIME);
            candy_data.public_sale_mint_time = public_sale_mint_time
        };
        if (candy_data.public_sale_mint_price==0 || candy_data.presale_mint_price==0){
            if (public_sale_mint_price>0){
                candy_data.royalty_points_numerator = royalty_points_numerator
            };
            if (presale_mint_price>0){
                candy_data.royalty_points_numerator = royalty_points_numerator
            };
        };
        if (presale_mint_price>0){
            candy_data.presale_mint_price = presale_mint_price
        };
        if (public_sale_mint_price>0){
            candy_data.public_sale_mint_price = public_sale_mint_price
        };
        event::emit_event(&mut candy_data.update_event,UpdateNFTEvent {
                presale_mint_price: candy_data.presale_mint_price,
                presale_mint_time: candy_data.presale_mint_time,
                public_sale_mint_price: candy_data.public_sale_mint_price,
                public_sale_mint_time: candy_data.public_sale_mint_time,
                royalty_points_denominator: candy_data.royalty_points_denominator,
                royalty_points_numerator: candy_data.royalty_points_numerator,
            }
        );
    }
    public fun mutate_one_token(
        account: &signer,
        token_owner: address,
        token_name:String,
        property_version:u64,
        keys: vector<String>,
        values: vector<vector<u8>>,
        types: vector<String>,
        resource_addr: address,
    )acquires ResourceInfo,NFTMachine
    {
        let account_addr = signer::address_of(account);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        assert!(resource_data.source == account_addr, INVALID_SIGNER);
        let candy_data = borrow_global<NFTMachine>(resource_addr);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_data.resource_cap);
        let token_id = token::create_token_id_raw(resource_addr,candy_data.collection_name,token_name,property_version);
        token::mutate_one_token(&resource_signer_from_cap,token_owner,token_id,keys,values,types);
    }
    public fun mutate_tokendata_uri(
        account: &signer,
        token_name: String,
        uri: String,
        resource_addr: address,
    )acquires ResourceInfo,NFTMachine
    {
        let account_addr = signer::address_of(account);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        assert!(resource_data.source == account_addr, INVALID_SIGNER);
        let candy_data = borrow_global<NFTMachine>(resource_addr);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_data.resource_cap);
        let token_data_id = token::create_token_data_id(resource_addr,candy_data.collection_name,token_name);
        token::mutate_tokendata_uri(&resource_signer_from_cap,token_data_id,uri);
    }
    public fun mutate_tokendata_property(
        account: &signer,
        token_name:String,
        keys: vector<String>,
        values: vector<vector<u8>>,
        types: vector<String>,
        resource_addr: address
    )acquires ResourceInfo,NFTMachine
    {
        let account_addr = signer::address_of(account);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        assert!(resource_data.source == account_addr, INVALID_SIGNER);
        let candy_data = borrow_global<NFTMachine>(resource_addr);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_data.resource_cap);
        let token_data_id = token::create_token_data_id(resource_addr,candy_data.collection_name,token_name);
        token::mutate_tokendata_property(&resource_signer_from_cap,token_data_id,keys,values,types);  
    }
    public fun mutate_token_royalty(
        account: &signer,
        token_name:String,
        royalty_points_numerator:u64,
        royalty_points_denominator:u64,
        resource_addr: address
    )acquires ResourceInfo,NFTMachine
    {
        let account_addr = signer::address_of(account);
        let resource_data = borrow_global<ResourceInfo>(resource_addr);
        assert!(resource_data.source == account_addr, INVALID_SIGNER);
        let candy_data = borrow_global<NFTMachine>(resource_addr);
        let resource_signer_from_cap = account::create_signer_with_capability(&resource_data.resource_cap);
        let token_data_id = token::create_token_data_id(resource_addr,candy_data.collection_name,token_name);
        let royalty = token::create_royalty(royalty_points_numerator, royalty_points_denominator, candy_data.royalty_payee_address);
        token::mutate_tokendata_royalty(&resource_signer_from_cap,token_data_id,royalty);
    }

    fun num_str(num: u64): String
    {
        let v1 = vector::empty();
        while (num/10 > 0){
            let rem = num%10;
            vector::push_back(&mut v1, (rem+48 as u8));
            num = num/10;
        };
        vector::push_back(&mut v1, (num+48 as u8));
        vector::reverse(&mut v1);
        string::utf8(v1)
    }

    fun pseudo_random(add:address,remaining:u64):u64
    {
        let x = bcs::to_bytes<address>(&add);
        let y = bcs::to_bytes<u64>(&remaining);
        let z = bcs::to_bytes<u64>(&timestamp::now_seconds());
        vector::append(&mut x,y);
        vector::append(&mut x,z);
        let tmp = hash::sha2_256(x);

        let data = vector<u8>[];
        let i =24;
        while (i < 32)
        {
            let x =vector::borrow(&tmp,i);
            vector::append(&mut data,vector<u8>[*x]);
            i= i+1;
        };
        assert!(remaining>0,999);

        let random = from_bcs::to_u64(data) % remaining + 1;
        random
    }

    fun initialize_whitelist(account: signer){
        move_to(&account, Whitelist {
            minters: bucket_table::new<address, u64>(4),
        })
    }

    fun initialize_and_create_public_minter(resource_signer_from_cap:&signer,candy_data: &mut NFTMachine,receiver_addr: address,resource_addr:address)acquires PublicMinters{
        if (!exists<PublicMinters>(resource_addr)) {
                move_to(resource_signer_from_cap, PublicMinters {
                // Can use a different size of bucket table depending on how big we expect the whitelist to be.
                // Here because a global pubic minting max is optional, we are starting with a smaller size
                // bucket table.
                minters: bucket_table::new<address, u64>(4),
                })
            };
            let public_minters= borrow_global_mut<PublicMinters>(resource_addr);
            if (!bucket_table::contains(&public_minters.minters, &receiver_addr)) {
                    bucket_table::add(&mut public_minters.minters, receiver_addr, candy_data.public_mint_limit);
            };
            // add check for public mint limit
            let public_minters_limit= bucket_table::borrow_mut(&mut public_minters.minters, receiver_addr);
            assert!(*public_minters_limit != 0, MINT_LIMIT_EXCEED);
            *public_minters_limit = *public_minters_limit - 1;
    }
}