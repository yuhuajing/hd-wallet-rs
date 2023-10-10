/// A bucket table implementation based on linear hashing. (https://en.wikipedia.org/wiki/Linear_hashing)
/// Compare to Table, it uses less storage slots but has higher chance of collision, it's a trade-off between space and time.
/// Compare to other implementation, linear hashing splits one bucket a time instead of doubling buckets when expanding to avoid unexpected gas cost.
/// BucketTable uses faster hash function SipHash instead of cryptographically secure hash functions like sha3-256 since it tolerates collisions.
module nfttoken::bucket_table {
    use std::error;
    use std::vector;
    use aptos_std::aptos_hash::sip_hash_from_value;
    use aptos_std::table_with_length::{Self, TableWithLength};

    const TARGET_LOAD_PER_BUCKET: u64 = 10;
    const SPLIT_THRESHOLD: u64 = 75;

    /// Key not found in the bucket table
    const ENOT_FOUND: u64 = 1;
    /// Bucket table capacity must be larger than 0
    const EZERO_CAPACITY: u64 = 2;
    /// Cannot destroy non-empty hashmap
    const ENOT_EMPTY: u64 = 3;
    /// Key already exists
    const EALREADY_EXIST: u64 = 4;

    /// BucketTable entry contains both the key and value.
    struct Entry<K, V> has store {
        hash: u64,
        key: K,
        value: V,
    }

    struct BucketTable<K, V> has store {
        buckets: TableWithLength<u64, vector<Entry<K, V>>>,
        num_buckets: u64,
        // number of bits to represent num_buckets
        level: u8,
        // total number of items
        len: u64,
    }

    /// Create an empty BucketTable with `initial_buckets` buckets.
    public fun new<K: drop + store, V: store>(initial_buckets: u64): BucketTable<K, V> {
        assert!(initial_buckets > 0, error::invalid_argument(EZERO_CAPACITY));
        let buckets = table_with_length::new();
        table_with_length::add(&mut buckets, 0, vector::empty());
        let map = BucketTable {
            buckets,
            num_buckets: 1,
            level: 0,
            len: 0,
        };
        split(&mut map, initial_buckets - 1);
        map
    }

    /// Destroy empty map.
    /// Aborts if it's not empty.
    public fun destroy_empty<K, V>(map: BucketTable<K, V>) {
        assert!(map.len == 0, error::invalid_argument(ENOT_EMPTY));
        let i = 0;
        while (i < map.num_buckets) {
            vector::destroy_empty(table_with_length::remove(&mut map.buckets, i));
            i = i + 1;
        };
        let BucketTable {buckets, num_buckets: _, level: _, len: _} = map;
        table_with_length::destroy_empty(buckets);
    }

    /// Add (key, value) pair in the hash map, it may grow one bucket if current load factor exceeds the threshold.
    /// Note it may not split the actual overflowed bucket.
    /// Abort if `key` already exists.
    public fun add<K, V>(map: &mut BucketTable<K, V>, key: K, value: V) {
        let hash = sip_hash_from_value(&key);
        let index = bucket_index(map.level, map.num_buckets, hash);
        let bucket = table_with_length::borrow_mut(&mut map.buckets, index);
        let i = 0;
        let len = vector::length(bucket);
        while (i < len) {
            let entry = vector::borrow(bucket, i);
            assert!(&entry.key != &key, error::invalid_argument(EALREADY_EXIST));
            i = i + 1;
        };
        vector::push_back(bucket, Entry {hash, key, value});
        map.len = map.len + 1;

        if (load_factor(map) > SPLIT_THRESHOLD) {
            split_one_bucket(map);
        }
    }

    fun xor(a: u64, b: u64): u64 {
        a ^ b
    }
    spec xor { // TODO: temporary mockup until Prover supports the operator `^`.
        pragma opaque;
        pragma verify = false;
    }

    /// Split the next bucket into two and re-insert existing items.
    fun split_one_bucket<K, V>(map: &mut BucketTable<K, V>) {
        let new_bucket_index = map.num_buckets;
        // the next bucket to split is num_bucket without the most significant bit.
        let to_split = xor(new_bucket_index, (1 << map.level));
        let new_bucket = vector::empty();
        map.num_buckets = new_bucket_index + 1;
        // if the whole level is splitted once, bump the level.
        if (to_split + 1 == 1 << map.level) {
            map.level = map.level + 1;
        };
        let old_bucket = table_with_length::borrow_mut(&mut map.buckets, to_split);
        // partition the bucket. after the loop, i == j and [0..i) stays in old bucket, [j..len) goes to new bucket
        let i = 0;
        let j = vector::length(old_bucket);
        let len = j;
        while (i < j) {
            let entry = vector::borrow(old_bucket, i);
            let index = bucket_index(map.level, map.num_buckets, entry.hash);
            if (index == new_bucket_index) {
                j = j - 1;
                vector::swap(old_bucket, i, j);
            } else {
                i = i + 1;
            };
        };
        while (j < len) {
            let entry = vector::pop_back(old_bucket);
            vector::push_back(&mut new_bucket, entry);
            len = len - 1;
        };
        table_with_length::add(&mut map.buckets, new_bucket_index, new_bucket);
    }

    /// Return the expected bucket index to find the hash.
    fun bucket_index(level: u8, num_buckets: u64, hash: u64): u64 {
        let index = hash % (1 << (level + 1));
        if (index < num_buckets) {
            // in existing bucket
            index
        } else {
            // in unsplitted bucket
            index % (1 << level)
        }
    }

    /// Acquire an immutable reference to the value which `key` maps to.
    /// Aborts if there is no entry for `key`.
    /// The requirement of &mut BucketTable is to bypass the borrow checker issue described in https://github.com/move-language/move/issues/95
    /// Once Table supports borrow by K, we can remove the &mut
    public fun borrow<K: copy + drop, V>(map: &mut BucketTable<K, V>, key: K): &V {
        let index = bucket_index(map.level, map.num_buckets, sip_hash_from_value(&key));
        let bucket = table_with_length::borrow_mut(&mut map.buckets, index);
        let i = 0;
        let len = vector::length(bucket);
        while (i < len) {
            let entry = vector::borrow(bucket, i);
            if (&entry.key == &key) {
                return &entry.value
            };
            i = i + 1;
        };
        abort error::invalid_argument(ENOT_FOUND)
    }

    /// Acquire a mutable reference to the value which `key` maps to.
    /// Aborts if there is no entry for `key`.
    public fun borrow_mut<K: copy + drop, V>(map: &mut BucketTable<K, V>, key: K): &mut V {
        let index = bucket_index(map.level, map.num_buckets, sip_hash_from_value(&key));
        let bucket = table_with_length::borrow_mut(&mut map.buckets, index);
        let i = 0;
        let len = vector::length(bucket);
        while (i < len) {
            let entry = vector::borrow_mut(bucket, i);
            if (&entry.key == &key) {
                return &mut entry.value
            };
            i = i + 1;
        };
        abort error::invalid_argument(ENOT_FOUND)
    }

    /// Returns true iff `table` contains an entry for `key`.
    public fun contains<K, V>(map: &BucketTable<K, V>, key: &K): bool {
        let index = bucket_index(map.level, map.num_buckets, sip_hash_from_value(key));
        let bucket = table_with_length::borrow(&map.buckets, index);
        let i = 0;
        let len = vector::length(bucket);
        while (i < len) {
            let entry = vector::borrow(bucket, i);
            if (&entry.key == key) {
                return true
            };
            i = i + 1;
        };
        false
    }

    /// Remove from `table` and return the value which `key` maps to.
    /// Aborts if there is no entry for `key`.
    public fun remove<K: drop, V>(map: &mut BucketTable<K,V>, key: &K): V {
        let index = bucket_index(map.level, map.num_buckets, sip_hash_from_value(key));
        let bucket = table_with_length::borrow_mut(&mut map.buckets, index);
        let i = 0;
        let len = vector::length(bucket);
        while (i < len) {
            let entry = vector::borrow(bucket, i);
            if (&entry.key == key) {
                let Entry {hash:_, key:_, value} = vector::swap_remove(bucket, i);
                map.len = map.len - 1;
                return value
            };
            i = i + 1;
        };
        abort error::invalid_argument(ENOT_FOUND)
    }

    /// Returns the length of the table, i.e. the number of entries.
    public fun length<K, V>(map: &BucketTable<K, V>): u64 {
        map.len
    }

    /// Return the load factor of the hashmap.
    public fun load_factor<K, V>(map: &BucketTable<K, V>): u64 {
        map.len * 100 / (map.num_buckets * TARGET_LOAD_PER_BUCKET)
    }

    /// Reserve `additional_buckets` more buckets.
    public fun split<K, V>(map: &mut BucketTable<K, V>, additional_buckets: u64) {
        while (additional_buckets > 0) {
            additional_buckets = additional_buckets - 1;
            split_one_bucket(map);
        }
    }
}