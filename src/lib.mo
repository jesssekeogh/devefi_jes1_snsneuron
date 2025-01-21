import U "mo:devefi/utils";
import MU "mo:mosup";
import Map "mo:map/Map";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Nat32 "mo:base/Nat32";
import Core "mo:devefi/core";
import Ver1 "./memory/v1";
import I "./interface";
import { NNS } "mo:neuro";
import Tools "mo:neuro/tools";

module {
    let T = Core.VectorModule;

    public let Interface = I;

    public module Mem {
        public module Vector {
            public let V1 = Ver1;
        };
    };

    let M = Mem.Vector.V1;

    public let ID = "devefi_jes1_snsneuron";

    public class Mod({
        xmem : MU.MemShell<M.Mem>;
        core : Core.Mod;
    }) : T.Class<I.CreateRequest, I.ModifyRequest, I.Shared> {

        let mem = MU.access(xmem);

        public func meta() : T.Meta {
            {
                id = ID; // This has to be same as the variant in vec.custom
                name = "SNS Neuron";
                author = "jes1";
                description = "Stake SNS neurons and receive maturity directly to your destination";
                supported_ledgers = []; // all pylon ledgers
                version = #beta([0, 1, 0]);
                create_allowed = true;
                ledger_slots = [
                    "Neuron"
                ];
                billing = [
                    {
                        cost_per_day = 31700000; // 0.317 tokens
                        transaction_fee = #none;
                    },
                ];
                sources = sources(0);
                destinations = destinations(0);
                author_account = {
                    owner = Principal.fromText("jv4ws-fbili-a35rv-xd7a5-xwvxw-trink-oluun-g7bcp-oq5f6-35cba-vqe");
                    subaccount = null;
                };
                temporary_allowed = true;
            };
        };

        public func run() : () {
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {};
        };

        public func runAsync() : async* () {
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {

            };
        };

        public func create(vid : T.NodeId, _req : T.CommonCreateRequest, t : I.CreateRequest) : T.Create {
            let nodeMem : M.SnsNodeMem = {
                init = {
                    neuron_nonce = 0; // TODO get_neuron_nonce on this
                };
                variables = {
                    var neuron_type = t.variables.neuron_type;
                    var dissolve_delay = t.variables.dissolve_delay;
                    var dissolve_status = t.variables.dissolve_status;
                    var followee = t.variables.followee;
                };
                internals = {
                    var updating = #Init;
                    var refresh_idx = null;
                };
                cache = {
                    var neuron_id = null;
                    var permissions = [];
                    var maturity_e8s_equivalent = null;
                    var cached_neuron_stake_e8s = null;
                    var created_timestamp_seconds = null;
                    var source_nns_neuron_id = null;
                    var auto_stake_maturity = null;
                    var aging_since_timestamp_seconds = null;
                    var dissolve_state = null;
                    var voting_power_percentage_multiplier = null;
                    var vesting_period_seconds = null;
                    var disburse_maturity_in_progress = [];
                    var followees = [];
                    var neuron_fees_e8s = null;
                };
                var log = [];
            };
            ignore Map.put(mem.main, Map.n32hash, vid, nodeMem);
            #ok(ID);
        };

        public func delete(vid : T.NodeId) : T.Delete {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            let shouldDelete = switch (t.cache.cached_neuron_stake_e8s) {
                case (?cachedStake) { if (cachedStake > 0) false else true };
                case (null) { true };
            };

            if (shouldDelete) {
                ignore Map.remove(mem.main, Map.n32hash, vid);
                return #ok();
            };

            return #err("Neuron is not empty");
        };

        public func modify(vid : T.NodeId, m : I.ModifyRequest) : T.Modify {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            t.variables.dissolve_delay := Option.get(m.dissolve_delay, t.variables.dissolve_delay);
            t.variables.dissolve_status := Option.get(m.dissolve_status, t.variables.dissolve_status);
            t.variables.followee := Option.get(m.followee, t.variables.followee);
            #ok();
        };

        public func get(vid : T.NodeId, _vec : T.NodeCoreMem) : T.Get<I.Shared> {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            #ok {
                init = {
                    neuron_nonce = t.init.neuron_nonce;
                };
                variables = {
                    neuron_type = t.variables.neuron_type;
                    dissolve_delay = t.variables.dissolve_delay;
                    dissolve_status = t.variables.dissolve_status;
                    followee = t.variables.followee;
                };
                internals = {
                    updating = t.internals.updating;
                    refresh_idx = t.internals.refresh_idx;
                };
                cache = {
                    neuron_id = t.cache.neuron_id;
                    permissions = t.cache.permissions;
                    maturity_e8s_equivalent = t.cache.maturity_e8s_equivalent;
                    cached_neuron_stake_e8s = t.cache.cached_neuron_stake_e8s;
                    created_timestamp_seconds = t.cache.created_timestamp_seconds;
                    source_nns_neuron_id = t.cache.source_nns_neuron_id;
                    auto_stake_maturity = t.cache.auto_stake_maturity;
                    aging_since_timestamp_seconds = t.cache.aging_since_timestamp_seconds;
                    dissolve_state = t.cache.dissolve_state;
                    voting_power_percentage_multiplier = t.cache.voting_power_percentage_multiplier;
                    vesting_period_seconds = t.cache.vesting_period_seconds;
                    disburse_maturity_in_progress = t.cache.disburse_maturity_in_progress;
                    followees = t.cache.followees;
                    neuron_fees_e8s = t.cache.neuron_fees_e8s;
                };
                log = t.log;
            };
        };

        public func defaults() : I.CreateRequest {
            {
                variables = {
                    neuron_type = #Default;
                    dissolve_delay = #Default;
                    dissolve_status = #Locked;
                    followee = #Default;
                };
            };
        };

        public func sources(_id : T.NodeId) : T.Endpoints {
            [(0, "Stake"), (0, "_Maturity")];
        };

        public func destinations(_id : T.NodeId) : T.Endpoints {
            [(0, "Maturity"), (0, "Disburse")];
        };


        // if transferred neuron in refresh neuron, can just call claim on it, it already exists
    };

};
