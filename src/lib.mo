import U "mo:devefi/utils";
import MU "mo:mosup";
import Map "mo:map/Map";
import Nat64 "mo:base/Nat64";
import Principal "mo:base/Principal";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Error "mo:base/Error";
import Buffer "mo:base/Buffer";
import Nat32 "mo:base/Nat32";
import Hex "mo:encoding/Hex";
import Core "mo:devefi/core";
import Ver1 "./memory/v1";
import I "./interface";
import { SNS } "mo:neuro";
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

        public type SnsNodeMem = Ver1.SnsNodeMem;

        // Interval for cache check when no neuron refresh is pending.
        let TIMEOUT_NANOS_NO_REFRESH_PENDING : Nat64 = (12 * 60 * 60 * 1_000_000_000); // every 12 hours

        // Timeout interval for when a neuron refresh is pending.
        let TIMEOUT_NANOS_REFRESH_PENDING : Nat64 = (5 * 60 * 1_000_000_000); // every 5 minutes

        // Maximum number of activities to keep in the main neuron's activity log
        let ACTIVITY_LOG_LIMIT : Nat = 10;

        // Used to calculate days as seconds for delay inputs
        let ONE_DAY_SECONDS : Nat64 = 24 * 60 * 60;

        // Minimum allowable delay increase, defined as a buffer one week (in seconds)
        let DELAY_BUFFER_SECONDS : Nat64 = (7 * ONE_DAY_SECONDS);

        // From here: https://github.com/dfinity/ic/blob/master/rs/sns/governance/src/gen/ic_sns_governance.pb.v1.rs#L3829
        let SNS_PERMISSIONS = {
            Unspecified : Int32 = 0;
            ConfigureDissolveState : Int32 = 1;
            ManagePrincipals : Int32 = 2;
            SubmitProposal : Int32 = 3;
            Vote : Int32 = 4;
            Disburse : Int32 = 5;
            Split : Int32 = 6;
            MergeMaturity : Int32 = 7;
            DisburseMaturity : Int32 = 8;
            StakeMaturity : Int32 = 9;
            ManageVotingPermission : Int32 = 10;
        };

        // From here: https://github.com/dfinity/ic/blob/master/rs/sns/governance/src/types.rs#L85
        // Critical proposals found here: https://github.com/dfinity/ic/blob/master/rs/sns/governance/src/types.rs#L1685
        let SNS_ACTIONS : [Nat64] = [
            0, // Catch all for non-critical proposals
            9, // TRANSFER_SNS_TREASURY_FUNDS critical proposal
            11, // DEREGISTER_DAPP_CANISTERS critical proposal
            12, // MINT_SNS_TOKENS critical proposal
        ];

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
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {
                let ?vec = core.getNodeById(vid) else continue vec_loop;
                if (not vec.active) continue vec_loop;
                if (vec.billing.frozen) continue vec_loop; // don't run if frozen
                if (Option.isSome(vec.billing.expires)) continue vec_loop; // don't allow staking until fee paid
                Run.single(vid, vec, nodeMem);
            };
        };

        public func runAsync() : async* () {
            label vec_loop for ((vid, nodeMem) in Map.entries(mem.main)) {
                let ?vec = core.getNodeById(vid) else continue vec_loop;
                if (not vec.active) continue vec_loop;
                if (vec.billing.frozen) continue vec_loop;
                if (Option.isSome(vec.billing.expires)) continue vec_loop;
                if (NodeUtils.node_ready(nodeMem)) {
                    await* Run.singleAsync(vid, vec, nodeMem);
                    return; // return after finding the first ready node
                };
            };
        };

        module Run {
            public func single(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : () {
                let ?sourceStake = core.getSource(vid, vec, 0) else return;
                let stakeBal = core.Source.balance(sourceStake);
                let tokenFee = core.Source.fee(sourceStake);
                let neuronSubaccount = Tools.computeNeuronStakingSubaccountBytes(core.getThisCan(), nodeMem.init.neuron_nonce);

                // If a neuron exists or it's an external neuron, a smaller amount is required for increasing the existing stake.
                // If no neuron exists, enforce the minimum stake requirement (plus fee) to create a new neuron.
                let requiredStake = if (Option.isSome(nodeMem.neuron_cache.neuron_id) or NodeUtils.get_neuron_creator(nodeMem) != core.getThisCan()) {
                    core.Source.fee(sourceStake);
                } else {
                    let ?MINIMUM_STAKE = nodeMem.parameters_cache.neuron_minimum_stake_e8s else return; // if parameters not cached, return

                    Nat64.toNat(MINIMUM_STAKE) + tokenFee;
                };

                if (stakeBal > requiredStake) {
                    // Proceed to send ICP to the neuron's subaccount
                    let #ok(intent) = core.Source.Send.intent(
                        sourceStake,
                        #external_account({
                            owner = nodeMem.init.governance_canister;
                            subaccount = ?neuronSubaccount;
                        }),
                        stakeBal,
                    ) else return;

                    let txId = core.Source.Send.commit(intent);

                    // Set refresh_idx to refresh or refresh the neuron in the next round
                    NodeUtils.tx_sent(nodeMem, txId);
                };

                // forward all maturity
                let ?sourceMaturity = core.getSource(vid, vec, 1) else return;
                let maturityBal = core.Source.balance(sourceMaturity);

                let #ok(intent) = core.Source.Send.intent(
                    sourceMaturity,
                    #destination({ port = 0 }),
                    maturityBal,
                ) else return;

                ignore core.Source.Send.commit(intent);
            };

            public func singleAsync(vid : T.NodeId, vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : async* () {
                try {
                    await* NeuronActions.refresh_neuron(vec, nodeMem);
                    await* NeuronActions.update_delay(nodeMem);
                    await* NeuronActions.update_followees(nodeMem);
                    await* NeuronActions.update_dissolving(nodeMem);
                    await* NeuronActions.disburse_maturity(vec, vid, nodeMem);
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
                    followee = switch (Hex.decode("824f1a1df2652fb26c0fe1c03ab5ce69f2561570fb4d042cdc32dcb4604a4f03")) {
                        case (#ok(decoded)) { Blob.fromArray(decoded) };
                        case (#err(_)) {
                            U.trap("Failed to decode default followee");
                        };
                    };
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
            public func node_authorized(nodeMem : SnsNodeMem, requestedPermission : Int32) : Bool {
                label permissionLoop for (permissions in nodeMem.neuron_cache.permissions.vals()) {
                    let ?principal = permissions.principal else continue permissionLoop;

                    if (principal == core.getThisCan()) {
                        for (permission in permissions.permission_type.vals()) {
                            if (permission == requestedPermission) return true;
                        };
                    };
                };

                return false;
            };

            public func node_ready(nodeMem : SnsNodeMem) : Bool {
                // Determine the appropriate timeout based on whether the neuron should be refreshed
                let timeout = if (node_needs_refresh(nodeMem)) {
                    TIMEOUT_NANOS_REFRESH_PENDING;
                } else {
                    TIMEOUT_NANOS_NO_REFRESH_PENDING;
                };

                switch (nodeMem.internals.updating) {
                    case (#Init) {
                        nodeMem.internals.updating := #Calling(U.now());
                        return true;
                    };
                    case (#Calling(ts) or #Done(ts)) {
                        if (U.now() >= ts + timeout) {
                            nodeMem.internals.updating := #Calling(U.now());
                            return true;
                        } else {
                            return false;
                        };
                    };
                };
            };

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

            private func node_needs_refresh(nodeMem : SnsNodeMem) : Bool {
                return (
                    Option.isSome(nodeMem.internals.refresh_idx) or
                    Option.isNull(nodeMem.parameters_cache.neuron_minimum_stake_e8s) or
                    CacheManager.followee_changed(nodeMem, SNS_ACTIONS[0]) or
                    CacheManager.dissolving_changed(nodeMem) or
                    CacheManager.delay_changed(nodeMem)
                );
            };

            public func node_done(nodeMem : SnsNodeMem) : () {
                nodeMem.internals.updating := #Done(U.now());
            };

            public func tx_sent(nodeMem : SnsNodeMem, txId : Nat64) : () {
                nodeMem.internals.refresh_idx := ?txId;
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
                if (Option.isSome(nodeMem.parameters_cache.neuron_minimum_stake_e8s)) return; // return if present

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

            public func delay_changed(nodeMem : SnsNodeMem) : Bool {
                switch (nodeMem.variables.dissolve_status) {
                    case (#Dissolving) {
                        return false; // don't update delay if dissolving
                    };
                    case (#Locked) {
                        let ?#DissolveDelaySeconds(cachedDelay) = nodeMem.neuron_cache.dissolve_state else return false; // neuron is dissolving
                        let ?minimumDelay = nodeMem.parameters_cache.neuron_minimum_dissolve_delay_to_vote_seconds else return false;

                        let delayToSet : Nat64 = switch (nodeMem.variables.dissolve_delay) {
                            case (#Default) { minimumDelay };
                            case (#DelayDays(days)) { days * ONE_DAY_SECONDS };
                        };

                        return delayToSet > cachedDelay + DELAY_BUFFER_SECONDS;
                    };
                };
            };

            public func followee_changed(nodeMem : SnsNodeMem, functionId : Nat64) : Bool {
                let currentFollowees = Map.fromIter<Nat64, { followees : [{ id : Blob }] }>(nodeMem.neuron_cache.followees.vals(), Map.n64hash);

                switch (Map.get(currentFollowees, Map.n64hash, functionId)) {
                    case (?{ followees }) {
                        for (followee in followees.vals()) {
                            if (followee.id == nodeMem.variables.followee) return false;
                        };

                        return true // couldn't find the followee in there
                    };
                    case _ { return true };
                };
            };

            public func dissolving_changed(nodeMem : SnsNodeMem) : Bool {
                let ?dissolveState = nodeMem.neuron_cache.dissolve_state else return false;

                let isDissolving = switch (dissolveState) {
                    case (#DissolveDelaySeconds(_)) { false };
                    case (#WhenDissolvedTimestampSeconds(_)) { true };
                };

                switch (nodeMem.variables.dissolve_status) {
                    case (#Dissolving) {
                        return not isDissolving;
                    };
                    case (#Locked) {
                        return isDissolving;
                    };
                };
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

            public func update_delay(nodeMem : SnsNodeMem) : async* () {
                let ?neuron_id = nodeMem.neuron_cache.neuron_id else return;

                if (CacheManager.delay_changed(nodeMem)) {
                    if (not NodeUtils.node_authorized(nodeMem, SNS_PERMISSIONS.ConfigureDissolveState)) {
                        return NodeUtils.log_activity(nodeMem, "update_delay", #Err("Node does not have permission type: " # debug_show SNS_PERMISSIONS.ConfigureDissolveState));
                    };

                    let neuron = SNS.Neuron({
                        sns_canister_id = nodeMem.init.governance_canister;
                        neuron_id = neuron_id;
                    });

                    let nowSecs = U.now() / 1_000_000_000;

                    let ?minimumDelay = nodeMem.parameters_cache.neuron_minimum_dissolve_delay_to_vote_seconds else return;
                    let ?maximumDelay = nodeMem.parameters_cache.max_dissolve_delay_seconds else return;

                    let delayToSet : Nat64 = switch (nodeMem.variables.dissolve_delay) {
                        case (#Default) { minimumDelay };
                        case (#DelayDays(days)) { days * ONE_DAY_SECONDS };
                    };

                    let cleanedDelay = Nat64.min(
                        Nat64.max(delayToSet, minimumDelay),
                        maximumDelay,
                    );

                    // Store the original delay in nodeMem, keeping it at the max if applicable
                    nodeMem.variables.dissolve_delay := #DelayDays(cleanedDelay / ONE_DAY_SECONDS);

                    switch (await* neuron.setDissolveTimestamp({ dissolve_timestamp_seconds = nowSecs + cleanedDelay })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "update_delay", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "update_delay", #Err(debug_show err));
                        };
                    };
                };
            };

            public func update_followees(nodeMem : SnsNodeMem) : async* () {
                let ?neuron_id = nodeMem.neuron_cache.neuron_id else return;

                for (functionId in SNS_ACTIONS.vals()) {
                    if (CacheManager.followee_changed(nodeMem, functionId)) {
                        if (not NodeUtils.node_authorized(nodeMem, SNS_PERMISSIONS.Vote)) {
                            return NodeUtils.log_activity(nodeMem, "update_delay", #Err("Node does not have permission type: " # debug_show SNS_PERMISSIONS.Vote));
                        };

                        let neuron = SNS.Neuron({
                            sns_canister_id = nodeMem.init.governance_canister;
                            neuron_id = neuron_id;
                        });

                        switch (await* neuron.follow({ followee = nodeMem.variables.followee; function_id = functionId })) {
                            case (#ok(_)) {
                                NodeUtils.log_activity(nodeMem, "update_followees", #Ok);
                            };
                            case (#err(err)) {
                                NodeUtils.log_activity(nodeMem, "update_followees", #Err(debug_show err));
                            };
                        };
                    };
                };
            };

            public func update_dissolving(nodeMem : SnsNodeMem) : async* () {
                let ?neuron_id = nodeMem.neuron_cache.neuron_id else return;

                if (CacheManager.dissolving_changed(nodeMem)) {
                    if (not NodeUtils.node_authorized(nodeMem, SNS_PERMISSIONS.ConfigureDissolveState)) {
                        return NodeUtils.log_activity(nodeMem, "update_delay", #Err("Node does not have permission type: " # debug_show SNS_PERMISSIONS.ConfigureDissolveState));
                    };

                    let neuron = SNS.Neuron({
                        sns_canister_id = nodeMem.init.governance_canister;
                        neuron_id = neuron_id;
                    });

                    switch (nodeMem.variables.dissolve_status) {
                        case (#Dissolving) {
                            switch (await* neuron.startDissolving()) {
                                case (#ok(_)) {
                                    NodeUtils.log_activity(nodeMem, "start_dissolving", #Ok);
                                };
                                case (#err(err)) {
                                    NodeUtils.log_activity(nodeMem, "start_dissolving", #Err(debug_show err));
                                };
                            };
                        };
                        case (#Locked) {
                            switch (await* neuron.stopDissolving()) {
                                case (#ok(_)) {
                                    NodeUtils.log_activity(nodeMem, "stop_dissolving", #Ok);
                                };
                                case (#err(err)) {
                                    NodeUtils.log_activity(nodeMem, "stop_dissolving", #Err(debug_show err));
                                };
                            };
                        };
                    };
                };
            };

            public func disburse_maturity(vec : T.NodeCoreMem, vid : T.NodeId, nodeMem : SnsNodeMem) : async* () {
                let ?neuron_id = nodeMem.neuron_cache.neuron_id else return;
                let ?cachedMaturity = nodeMem.neuron_cache.maturity_e8s_equivalent else return;
                let ?sourceMaturity = core.getSource(vid, vec, 1) else return;
                let tokenFee = core.Source.fee(sourceMaturity);

                if (cachedMaturity > Nat64.fromNat(tokenFee)) {
                    if (not NodeUtils.node_authorized(nodeMem, SNS_PERMISSIONS.DisburseMaturity)) {
                        return NodeUtils.log_activity(nodeMem, "update_delay", #Err("Node does not have permission type: " # debug_show SNS_PERMISSIONS.DisburseMaturity));
                    };

                    // send maturity to the maturity source
                    let ?{ owner; subaccount } = core.getSourceAccountIC(vec, 1) else return;

                    // formatting for SNS Account
                    let useSubaccount : ?{ subaccount : Blob } = switch (subaccount) {
                        case (?sub) { ?{ subaccount = sub } };
                        case (_) { null };
                    };

                    let neuron = SNS.Neuron({
                        sns_canister_id = nodeMem.init.governance_canister;
                        neuron_id = neuron_id;
                    });

                    switch (await* neuron.disburseMaturity({ percentage_to_disburse = 100; to_account = ?{ owner = ?owner; subaccount = useSubaccount } })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "disburse_maturity", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "disburse_maturity", #Err(debug_show err));
                        };
                    };
                };
            };
        };
    };

};
