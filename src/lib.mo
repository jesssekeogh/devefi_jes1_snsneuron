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
import { SNS } "mo:neuro";
import Tools "mo:neuro/tools";
import NodeUtil "mo:stableheapbtreemap/NodeUtil";

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

        public type SnsNodeMem = Ver1.SnsNodeMem;

        // Maximum number of activities to keep in the main neuron's activity log
        let ACTIVITY_LOG_LIMIT : Nat = 10;

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
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {};
        };

        module Run {
            // in run single you can send a small amount of tokens (below minimum stake) if it's external neuron too
            // Todo figure how to get the minimum stake
            public func single(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : () {

            };

            public func singleAsync(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : async* () {
                try {
                    await* NeuronActions.refresh_neuron(vec, nodeMem);
                    await* CacheManager.refresh_neuron_cache(vec, nodeMem);
                    await* CacheManager.refresh_parameters_cache(vec, nodeMem);
                } catch (err) {
                    NodeUtils.log_activity(nodeMem, "async_cycle", #Err(Error.message(err)));
                } finally {
                    NodeUtils.node_done(nodeMem);
                };
            };
        };

        public func create(vid : T.NodeId, _req : T.CommonCreateRequest, t : I.CreateRequest) : T.Create {
            let nodeMem : SnsNodeMem = {
                init = {
                    neuron_nonce = NodeUtils.get_neuron_nonce(vid, 0);
                    governance_canister = t.init.governance_canister;
                    neuron_creator = t.init.neuron_creator;
                };
                variables = {
                    var dissolve_delay = t.variables.dissolve_delay;
                    var dissolve_status = t.variables.dissolve_status;
                    var followee = t.variables.followee;
                };
                internals = {
                    var updating = #Init;
                    var refresh_idx = null;
                };
                neuron_cache = {
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
                parameters_cache = {
                    var default_followees = null;
                    var max_dissolve_delay_seconds = null;
                    var max_dissolve_delay_bonus_percentage = null;
                    var max_followees_per_function = null;
                    var neuron_claimer_permissions = null;
                    var neuron_minimum_stake_e8s = null;
                    var max_neuron_age_for_age_bonus = null;
                    var initial_voting_period_seconds = null;
                    var neuron_minimum_dissolve_delay_to_vote_seconds = null;
                    var reject_cost_e8s = null;
                    var max_proposals_to_keep_per_action = null;
                    var wait_for_quiet_deadline_increase_seconds = null;
                    var max_number_of_neurons = null;
                    var transaction_fee_e8s = null;
                    var max_number_of_proposals_with_ballots = null;
                    var max_age_bonus_percentage = null;
                    var neuron_grantable_permissions = null;
                    var voting_rewards_parameters = null;
                    var maturity_modulation_disabled = null;
                    var max_number_of_principals_per_neuron = null;
                };
                var log = [];
            };
            ignore Map.put(mem.main, Map.n32hash, vid, nodeMem);
            #ok(ID);
        };

        public func delete(vid : T.NodeId) : T.Delete {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            let shouldDelete = switch (t.neuron_cache.cached_neuron_stake_e8s) {
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
                    governance_canister = t.init.governance_canister;
                    neuron_creator = t.init.neuron_creator;
                };
                variables = {
                    dissolve_delay = t.variables.dissolve_delay;
                    dissolve_status = t.variables.dissolve_status;
                    followee = t.variables.followee;
                };
                internals = {
                    updating = t.internals.updating;
                    refresh_idx = t.internals.refresh_idx;
                };
                neuron_cache = {
                    neuron_id = t.neuron_cache.neuron_id;
                    permissions = t.neuron_cache.permissions;
                    maturity_e8s_equivalent = t.neuron_cache.maturity_e8s_equivalent;
                    cached_neuron_stake_e8s = t.neuron_cache.cached_neuron_stake_e8s;
                    created_timestamp_seconds = t.neuron_cache.created_timestamp_seconds;
                    source_nns_neuron_id = t.neuron_cache.source_nns_neuron_id;
                    auto_stake_maturity = t.neuron_cache.auto_stake_maturity;
                    aging_since_timestamp_seconds = t.neuron_cache.aging_since_timestamp_seconds;
                    dissolve_state = t.neuron_cache.dissolve_state;
                    voting_power_percentage_multiplier = t.neuron_cache.voting_power_percentage_multiplier;
                    vesting_period_seconds = t.neuron_cache.vesting_period_seconds;
                    disburse_maturity_in_progress = t.neuron_cache.disburse_maturity_in_progress;
                    followees = t.neuron_cache.followees;
                    neuron_fees_e8s = t.neuron_cache.neuron_fees_e8s;
                };
                parameters_cache = {
                    default_followees = t.parameters_cache.default_followees;
                    max_dissolve_delay_seconds = t.parameters_cache.max_dissolve_delay_seconds;
                    max_dissolve_delay_bonus_percentage = t.parameters_cache.max_dissolve_delay_bonus_percentage;
                    max_followees_per_function = t.parameters_cache.max_followees_per_function;
                    neuron_claimer_permissions = t.parameters_cache.neuron_claimer_permissions;
                    neuron_minimum_stake_e8s = t.parameters_cache.neuron_minimum_stake_e8s;
                    max_neuron_age_for_age_bonus = t.parameters_cache.max_neuron_age_for_age_bonus;
                    initial_voting_period_seconds = t.parameters_cache.initial_voting_period_seconds;
                    neuron_minimum_dissolve_delay_to_vote_seconds = t.parameters_cache.neuron_minimum_dissolve_delay_to_vote_seconds;
                    reject_cost_e8s = t.parameters_cache.reject_cost_e8s;
                    max_proposals_to_keep_per_action = t.parameters_cache.max_proposals_to_keep_per_action;
                    wait_for_quiet_deadline_increase_seconds = t.parameters_cache.wait_for_quiet_deadline_increase_seconds;
                    max_number_of_neurons = t.parameters_cache.max_number_of_neurons;
                    transaction_fee_e8s = t.parameters_cache.transaction_fee_e8s;
                    max_number_of_proposals_with_ballots = t.parameters_cache.max_number_of_proposals_with_ballots;
                    max_age_bonus_percentage = t.parameters_cache.max_age_bonus_percentage;
                    neuron_grantable_permissions = t.parameters_cache.neuron_grantable_permissions;
                    voting_rewards_parameters = t.parameters_cache.voting_rewards_parameters;
                    maturity_modulation_disabled = t.parameters_cache.maturity_modulation_disabled;
                    max_number_of_principals_per_neuron = t.parameters_cache.max_number_of_principals_per_neuron;
                };
                log = t.log;
            };
        };

        public func defaults() : I.CreateRequest {
            {
                init = {
                    governance_canister = Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai");
                    neuron_creator = #Default;
                };
                variables = {
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

        module NodeUtils {

            // we need a function that checks for permissions for every call

            public func get_neuron_creator(nodeMem : SnsNodeMem) : Principal {
                switch (nodeMem.init.neuron_creator) {
                    case (#Default) {
                        return core.getThisCan();
                    };
                    case (#External(creator)) {
                        return creator;
                    };
                };
            };

            public func node_done(nodeMem : SnsNodeMem) : () {
                nodeMem.internals.updating := #Done(U.now());
            };

            public func log_activity(nodeMem : SnsNodeMem, operation : Text, result : { #Ok; #Err : Text }) : () {
                let log = Buffer.fromArray<Ver1.SnsNeuronActivity>(nodeMem.log);

                switch (result) {
                    case (#Ok(())) {
                        log.add(#Ok({ operation = operation; timestamp = U.now() }));
                    };
                    case (#Err(msg)) {
                        log.add(#Err({ operation = operation; msg = msg; timestamp = U.now() }));
                    };
                };

                if (log.size() > ACTIVITY_LOG_LIMIT) {
                    ignore log.remove(0); // remove 1 item from the beginning
                };

                nodeMem.log := Buffer.toArray(log);
            };

            public func get_neuron_nonce(vid : T.NodeId, localId : Nat32) : Nat64 {
                return Nat64.fromNat32(vid) << 32 | Nat64.fromNat32(localId);
            };
        };

        module CacheManager {
            public func refresh_neuron_cache(vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : async* () {
                let ?nid = nodeMem.neuron_cache.neuron_id else return;
                let neuronLedger = U.onlyICLedger(vec.ledgers[0]);

                let sns = SNS.Governance({
                    canister_id = core.getThisCan();
                    sns_canister_id = nodeMem.init.governance_canister;
                    sns_ledger_canister_id = neuronLedger;
                });

                let #ok(neuron) = await* sns.getNeuron({ id = nid }) else return;

                nodeMem.neuron_cache.permissions := neuron.permissions;
                nodeMem.neuron_cache.maturity_e8s_equivalent := ?neuron.maturity_e8s_equivalent;
                nodeMem.neuron_cache.cached_neuron_stake_e8s := ?neuron.cached_neuron_stake_e8s;
                nodeMem.neuron_cache.created_timestamp_seconds := ?neuron.created_timestamp_seconds;
                nodeMem.neuron_cache.source_nns_neuron_id := neuron.source_nns_neuron_id;
                nodeMem.neuron_cache.auto_stake_maturity := neuron.auto_stake_maturity;
                nodeMem.neuron_cache.aging_since_timestamp_seconds := ?neuron.aging_since_timestamp_seconds;
                nodeMem.neuron_cache.dissolve_state := neuron.dissolve_state;
                nodeMem.neuron_cache.voting_power_percentage_multiplier := ?neuron.voting_power_percentage_multiplier;
                nodeMem.neuron_cache.vesting_period_seconds := neuron.vesting_period_seconds;
                nodeMem.neuron_cache.disburse_maturity_in_progress := neuron.disburse_maturity_in_progress;
                nodeMem.neuron_cache.followees := neuron.followees;
                nodeMem.neuron_cache.neuron_fees_e8s := ?neuron.neuron_fees_e8s;
            };

            public func refresh_parameters_cache(vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : async* () {
                if (Option.isSome(nodeMem.parameters_cache.neuron_minimum_stake_e8s)) return; // only calls this once

                let neuronLedger = U.onlyICLedger(vec.ledgers[0]);

                let sns = SNS.Governance({
                    canister_id = core.getThisCan();
                    sns_canister_id = nodeMem.init.governance_canister;
                    sns_ledger_canister_id = neuronLedger;
                });

                let parameters = await* sns.getParameters();

                nodeMem.parameters_cache.default_followees := parameters.default_followees;
                nodeMem.parameters_cache.max_dissolve_delay_seconds := parameters.max_dissolve_delay_seconds;
                nodeMem.parameters_cache.max_dissolve_delay_bonus_percentage := parameters.max_dissolve_delay_bonus_percentage;
                nodeMem.parameters_cache.max_followees_per_function := parameters.max_followees_per_function;
                nodeMem.parameters_cache.neuron_claimer_permissions := parameters.neuron_claimer_permissions;
                nodeMem.parameters_cache.neuron_minimum_stake_e8s := parameters.neuron_minimum_stake_e8s;
                nodeMem.parameters_cache.max_neuron_age_for_age_bonus := parameters.max_neuron_age_for_age_bonus;
                nodeMem.parameters_cache.initial_voting_period_seconds := parameters.initial_voting_period_seconds;
                nodeMem.parameters_cache.neuron_minimum_dissolve_delay_to_vote_seconds := parameters.neuron_minimum_dissolve_delay_to_vote_seconds;
                nodeMem.parameters_cache.reject_cost_e8s := parameters.reject_cost_e8s;
                nodeMem.parameters_cache.max_proposals_to_keep_per_action := parameters.max_proposals_to_keep_per_action;
                nodeMem.parameters_cache.wait_for_quiet_deadline_increase_seconds := parameters.wait_for_quiet_deadline_increase_seconds;
                nodeMem.parameters_cache.max_number_of_neurons := parameters.max_number_of_neurons;
                nodeMem.parameters_cache.transaction_fee_e8s := parameters.transaction_fee_e8s;
                nodeMem.parameters_cache.max_number_of_proposals_with_ballots := parameters.max_number_of_proposals_with_ballots;
                nodeMem.parameters_cache.max_age_bonus_percentage := parameters.max_age_bonus_percentage;
                nodeMem.parameters_cache.neuron_grantable_permissions := parameters.neuron_grantable_permissions;
                nodeMem.parameters_cache.voting_rewards_parameters := parameters.voting_rewards_parameters;
                nodeMem.parameters_cache.maturity_modulation_disabled := parameters.maturity_modulation_disabled;
                nodeMem.parameters_cache.max_number_of_principals_per_neuron := parameters.max_number_of_principals_per_neuron;
            };
        };

        // when calling actions we need to check do we have permission to do so from permissions list
        module NeuronActions {
            public func refresh_neuron(vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : async* () {
                let neuronCreator = NodeUtils.get_neuron_creator(nodeMem);
                let neuronLedger = U.onlyICLedger(vec.ledgers[0]);
                let ?{ cls = #icrc(ledger) } = core.get_ledger_cls(neuronLedger) else return;
                let ?refreshIdx = nodeMem.internals.refresh_idx else return;

                if (ledger.isSent(refreshIdx)) {
                    let sns = SNS.Governance({
                        canister_id = core.getThisCan();
                        sns_canister_id = nodeMem.init.governance_canister;
                        sns_ledger_canister_id = neuronLedger;
                    });

                    switch (await* sns.claimNeuron({ nonce = nodeMem.init.neuron_nonce; controller = neuronCreator })) {
                        case (#ok(neuronId)) {
                            // if no neuron, store the neuron's ID
                            if (not Option.isSome(nodeMem.neuron_cache.neuron_id)) {
                                // Store the neuron's ID in the cache
                                nodeMem.neuron_cache.neuron_id := ?neuronId;
                            };

                            // Check if refreshIdx hasn't changed during the async call.
                            // If it hasn't changed, it's safe to reset refresh_idx to null.
                            if (Option.equal(?refreshIdx, nodeMem.internals.refresh_idx, Nat64.equal)) {
                                nodeMem.internals.refresh_idx := null;
                            };

                            NodeUtils.log_activity(nodeMem, "refresh_neuron", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "refresh_neuron", #Err(debug_show err));
                        };
                    };
                };
            };

        };
    };

};
