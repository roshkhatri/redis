start_cluster 2 2 {tags {external:skip cluster}} {

    test "Verify that slot ownership transfer through gossip propagates deletes to replicas" {
        assert {[s -2 role] eq {slave}}
        wait_for_condition 1000 50 {
            [s -2 master_link_status] eq {up}
        } else {
            fail "Instance #2 master link status is not up"
        }

        assert {[s -3 role] eq {slave}}
        wait_for_condition 1000 50 {
            [s -3 master_link_status] eq {up}
        } else {
            fail "Instance #3 master link status is not up"
        }
        set online_count 4
        puts [R 0 CLUSTER SHARDS]
        while {$online_count} {
            set shards_response [R 0 CLUSTER SHARDS]
            foreach shard_response $shards_response {
                set nodes [dict get $shard_response nodes]
                foreach node $nodes {
                    if {[dict get $node health] eq "online"} {
                        incr online_count -1
                        puts $online_count
                        if {$online_count == 0} { break }
                    }
                }
            }
            if {$online_count == 0} { break }
            incr online_count [expr {4 - $online_count}]
            puts $online_count
            puts [R 0 CLUSTER SHARDS]
            after 1000
        }

        # Set a single key that will be used to test deletion
        set key "FOO"
        R 0 SET $key TEST
        set key_slot [R 0 cluster keyslot $key]
        set slot_keys_num [R 0 cluster countkeysinslot $key_slot]
        assert {$slot_keys_num > 0}

        # Wait for replica to have the key
        R 2 readonly
        wait_for_condition 1000 50 {
            [R 2 exists $key] eq "1"
        } else {
            fail "Test key was not replicated"
        }

        assert_equal [R 2 cluster countkeysinslot $key_slot] $slot_keys_num

        # Assert other shards in cluster doesn't have the key
        assert_equal [R 1 cluster countkeysinslot $key_slot] "0"
        assert_equal [R 3 cluster countkeysinslot $key_slot] "0"

        set nodeid [R 1 cluster myid]

        R 1 cluster bumpepoch
        # Move $key_slot to node 1
        assert_equal [R 1 cluster setslot $key_slot node $nodeid] "OK"

        puts [R 0 cluster slots]
        puts [R 1 cluster slots]
        puts [R 2 cluster slots]
        puts [R 3 cluster slots]
        
        wait_for_cluster_propagation


        # src master will delete keys in the slot
        wait_for_condition 50 100 {
            [R 0 cluster countkeysinslot $key_slot] eq 0
        } else {
            fail "master 'countkeysinslot $key_slot' did not eq 0"
        }

        # src replica will delete keys in the slot
        wait_for_condition 50 100 {
            [R 2 cluster countkeysinslot $key_slot] eq 0
        } else {
            fail "replica 'countkeysinslot $key_slot' did not eq 0"
        }
    }
}
