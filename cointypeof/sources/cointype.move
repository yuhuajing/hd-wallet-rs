module cointypeof::parse_coin_type {
    use aptos_std::type_info;
    use std::signer;

    struct TypeInfo has key {
        account_address: address,
        module_name: vector<u8>,
        struct_name: vector<u8>,
    }

    public entry fun storeCointype<CoinType>(account_signer: &signer){
        let coinaddress = signer::address_of(account_signer);
        let coiontype = type_info::type_of<CoinType>();
        let accountaddress =  type_info::account_address(&coiontype);
        let modulename =  type_info::module_name(&coiontype);
        let structname =  type_info::struct_name(&coiontype);
        if (!exists<TypeInfo>(coinaddress)){
            move_to(account_signer,TypeInfo{
                account_address:accountaddress,
                module_name:modulename,
                struct_name:structname
            })
        }
    }

    #[view]
    public fun parseCointype<CoinType>():(address,vector<u8>,vector<u8>) {
        let coiontype = type_info::type_of<CoinType>();
        let accountaddress =  type_info::account_address(&coiontype);
        let modulename =  type_info::module_name(&coiontype);
        let structname =  type_info::struct_name(&coiontype);
        (accountaddress,modulename,structname)
    }
}