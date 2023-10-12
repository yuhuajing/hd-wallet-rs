module smtable::calResaddress {
    use std::signer;
    use aptos_framework::account;
    use std::string::{Self,String};
    use aptos_std::smart_table::{Self, SmartTable};
  //  use aptos_framework::create_signer;
    struct ModuleData has key {
        res_address:SmartTable<String, address>,
    }

    public entry fun generate_res_address(account_signer: &signer, seed: String) acquires ModuleData {
        let seedbytes = string::bytes(&seed);
        let resource_addr = account::create_resource_address(&signer::address_of(account_signer), *seedbytes);
        let caller_address = signer::address_of(account_signer);
      //  let localsigner = create_signer::create_signer(@smtable);
      //  let resource_addr = account::create_resource_address(@smtable, seedbytes);
        if (!exists<ModuleData>(caller_address)) {
            move_to(account_signer, ModuleData {
                res_address:smart_table::new(),
            });
        };
        let module_data = borrow_global_mut<ModuleData>(caller_address);
        let res_address_table = &mut module_data.res_address;
        if(!smart_table::contains(res_address_table,seed)){
            smart_table::add(res_address_table,seed,resource_addr);
        };
    }
    #[view]
    public fun readResAddress(addr:address, seed:String):(address) acquires ModuleData {
         let module_data = borrow_global<ModuleData>(addr);
         let res_address_table = &module_data.res_address;
        // let length = smart_table::length(res_address_table);
         let res_address = smart_table::borrow(res_address_table, seed);
         *res_address
    }
}