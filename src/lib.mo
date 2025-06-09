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
import Core "mo:devefi/core";
import Ver1 "./memory/v1";
import Ver2 "./memory/v2";
import I "./interface";
import { SNS; SNSW } "mo:neuro";
import Tools "mo:neuro/tools";

module {
    let T = Core.VectorModule;

    public let Interface = I;

    public module Mem {
        public module Vector {
            public let V1 = Ver1;
            public let V2 = Ver2;
        };
    };

    let M = Mem.Vector.V2;

    public let ID = "devefi_jes1_snsneuron";

    public class Mod({
        xmem : MU.MemShell<M.Mem>;
        core : Core.Mod;
    }) : T.Class<I.CreateRequest, I.ModifyRequest, I.Shared> {

        let mem = MU.access(xmem);

        public type SnsNodeMem = Ver2.SnsNodeMem;

        let SNSW_CANISTER_ID = Principal.fromText("qaa6y-5yaaa-aaaaa-aaafa-cai");

        // Interval for cache check when no neuron refresh is pending.
        let TIMEOUT_NANOS_NO_REFRESH_PENDING : Nat64 = (12 * 60 * 60 * 1_000_000_000); // every 12 hours

        // Timeout interval for when a neuron refresh is pending.
        let TIMEOUT_NANOS_REFRESH_PENDING : Nat64 = (3 * 60 * 1_000_000_000); // every 3 minutes

        // Maximum number of activities to keep in the main neuron's activity log
        let ACTIVITY_LOG_LIMIT : Nat = 10;

        // Used to calculate days as seconds for delay inputs
        let ONE_DAY_SECONDS : Nat64 = 24 * 60 * 60;

        // Minimum allowable delay increase, defined as a buffer one week (in seconds)
        let DELAY_BUFFER_SECONDS : Nat64 = (7 * ONE_DAY_SECONDS);

        // From here: https://github.com/dfinity/ic/blob/master/rs/nns/governance/proto/ic_nns_governance/pb/v1/governance.proto#L149
        let NEURON_STATES = {
            locked : Int32 = 1;
            dissolving : Int32 = 2;
            unlocked : Int32 = 3;
        };

        public func meta() : T.Meta {
            {
                id = ID; // This has to be same as the variant in vec.custom
                name = "SNS Neuron";
                author = "jes1";
                description = "Stake SNS neurons and receive maturity directly to your destination";
                supported_ledgers = []; // all pylon ledgers
                version = #beta([0, 2, 0]);
                create_allowed = true;
                ledger_slots = [
                    "Neuron"
                ];
                billing = [
                    {
                        cost_per_day = 5000000; // 0.05 NTN
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

                let neuronSubaccount = NodeUtils.computeNeuronSubaccount(vid);

                // If a neuron exists, a smaller amount is required for increasing the existing stake.
                // If no neuron exists, enforce the minimum stake requirement (plus fee) to create a new neuron.
                let requiredStake = if (Option.isSome(nodeMem.neuron_cache)) {
                    core.Source.fee(sourceStake);
                } else {
                    let ?parameters = nodeMem.parameters_cache else return; // if parameters not cached, return
                    let ?minimumStake = parameters.neuron_minimum_stake_e8s else return;

                    Nat64.toNat(minimumStake) + tokenFee;
                };

                if (stakeBal > requiredStake) {
                    let ?governanceCanister = nodeMem.internals.governance_canister else return;

                    // Proceed to send ICP to the neuron's subaccount
                    let #ok(intent) = core.Source.Send.intent(
                        sourceStake,
                        #external_account({
                            owner = governanceCanister;
                            subaccount = ?neuronSubaccount;
                        }),
                        stakeBal,
                    ) else return;

                    let txId = core.Source.Send.commit(intent);

                    // Set refresh_idx to refresh the neuron in the next round
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
                    await* NeuronActions.refresh_neuron(vec, vid, nodeMem);
                    await* NeuronActions.update_delay(nodeMem);
                    await* NeuronActions.update_following(nodeMem);
                    await* NeuronActions.update_dissolving(nodeMem);
                    await* NeuronActions.disburse_maturity(vec, vid, nodeMem);
                    await* NeuronActions.disburse_neuron(nodeMem, vec);
                    await* CacheManager.find_governance_canister(vec, nodeMem);
                    await* CacheManager.refresh_neuron_cache(vec, vid, nodeMem);
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
                variables = {
                    var dissolve_delay = t.variables.dissolve_delay;
                    var dissolve_status = t.variables.dissolve_status;
                    var followee = t.variables.followee;
                };
                internals = {
                    var updating = #Init;
                    var refresh_idx = null;
                    var neuron_claimed = false;
                    var neuron_state = null;
                    var governance_canister = null;
                };
                var neuron_cache = null;
                var parameters_cache = null;
                var log = [];
            };
            ignore Map.put(mem.main, Map.n32hash, vid, nodeMem);
            #ok(ID);
        };

        public func delete(vid : T.NodeId) : T.Delete {
            let ?t = Map.get(mem.main, Map.n32hash, vid) else return #err("Node not found for ID: " # debug_show vid);

            let shouldDelete = switch (t.neuron_cache) {
                case (?neuron) {
                    if (neuron.cached_neuron_stake_e8s > 0) false else true;
                };
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
                variables = {
                    dissolve_delay = t.variables.dissolve_delay;
                    dissolve_status = t.variables.dissolve_status;
                    followee = t.variables.followee;
                };
                internals = {
                    updating = t.internals.updating;
                    refresh_idx = t.internals.refresh_idx;
                    neuron_claimed = t.internals.neuron_claimed;
                    neuron_state = t.internals.neuron_state;
                    governance_canister = t.internals.governance_canister;
                };
                neuron_cache = t.neuron_cache;
                parameters_cache = t.parameters_cache;
                log = t.log;
            };
        };

        public func defaults() : I.CreateRequest {
            {
                variables = {
                    dissolve_delay = #Default;
                    dissolve_status = #Locked;
                    followee = #Unspecified;
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

            // check if the node needs a refresh
            private func node_needs_refresh(nodeMem : SnsNodeMem) : Bool {
                return (
                    CacheManager.stake_increased(nodeMem) or
                    CacheManager.following_changed(nodeMem) or
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
                let log = Buffer.fromArray<Ver2.SnsNeuronActivity>(nodeMem.log);

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

            public func computeNeuronSubaccount(vid : T.NodeId) : Blob {
                return Tools.computeNeuronStakingSubaccountBytes(
                    core.getThisCan(),
                    NodeUtils.get_neuron_nonce(vid, 0),
                );
            };

            // Determine the int32 state of the neuron based on the dissolve state, mocks how NNS neurons are handled
            public func getNeuronState(
                neuronState : {
                    #DissolveDelaySeconds : Nat64;
                    #WhenDissolvedTimestampSeconds : Nat64;
                }
            ) : Int32 {
                switch (neuronState) {
                    case (#DissolveDelaySeconds(_)) {
                        return NEURON_STATES.locked;
                    };
                    case (#WhenDissolvedTimestampSeconds(cachedTimestamp)) {
                        let nowSeconds = U.now() / 1_000_000_000;
                        if (nowSeconds < cachedTimestamp) {
                            return NEURON_STATES.dissolving;
                        } else {
                            return NEURON_STATES.unlocked;
                        };
                    };
                };
            };
        };

        module CacheManager {
            public func refresh_neuron_cache(vec : T.NodeCoreMem, vid : T.NodeId, nodeMem : SnsNodeMem) : async* () {
                if (not nodeMem.internals.neuron_claimed) return;
                let ?governanceCanister = nodeMem.internals.governance_canister else return;

                let neuronSubaccount = NodeUtils.computeNeuronSubaccount(vid);
                let neuronLedger = U.onlyICLedger(vec.ledgers[0]);

                let sns = SNS.Governance({
                    canister_id = core.getThisCan();
                    sns_canister_id = governanceCanister;
                    sns_ledger_canister_id = neuronLedger;
                });

                let #ok(neuron) = await* sns.getNeuron({ id = neuronSubaccount }) else return;

                nodeMem.neuron_cache := ?neuron;
            };

            public func refresh_parameters_cache(vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : async* () {
                if (Option.isSome(nodeMem.parameters_cache)) return;
                let ?governanceCanister = nodeMem.internals.governance_canister else return;

                let neuronLedger = U.onlyICLedger(vec.ledgers[0]);

                let sns = SNS.Governance({
                    canister_id = core.getThisCan();
                    sns_canister_id = governanceCanister;
                    sns_ledger_canister_id = neuronLedger;
                });

                let parameters = await* sns.getParameters();

                nodeMem.parameters_cache := ?parameters;
            };

            public func find_governance_canister(vec : T.NodeCoreMem, nodeMem : SnsNodeMem) : async* () {
                if (Option.isSome(nodeMem.internals.governance_canister)) return;

                let neuronLedger = U.onlyICLedger(vec.ledgers[0]);

                let snsw = SNSW.Canister({ snsw_canister_id = SNSW_CANISTER_ID });

                let { instances } = await* snsw.listDeployedSnses();

                label snsLoop for ({ governance_canister_id; ledger_canister_id } in instances.vals()) {
                    let ?deployedLedger = ledger_canister_id else continue snsLoop;

                    if (neuronLedger == deployedLedger) {
                        nodeMem.internals.governance_canister := governance_canister_id;
                        return;
                    };
                };
            };

            public func delay_changed(nodeMem : SnsNodeMem) : Bool {
                let ?neuron = nodeMem.neuron_cache else return false;
                let ?parameters = nodeMem.parameters_cache else return false;

                switch (nodeMem.variables.dissolve_status) {
                    case (#Dissolving) {
                        return false; // don't update delay if dissolving
                    };
                    case (#Locked) {
                        let ?dissolveState = neuron.dissolve_state else return false;

                        switch (dissolveState) {
                            case (#DissolveDelaySeconds(cachedDelay)) {
                                let ?minimumDelay = parameters.neuron_minimum_dissolve_delay_to_vote_seconds else return false;

                                let delay : Nat64 = switch (nodeMem.variables.dissolve_delay) {
                                    case (#Default) { minimumDelay };
                                    case (#DelayDays(days)) {
                                        days * ONE_DAY_SECONDS;
                                    };
                                };

                                return delay > cachedDelay + DELAY_BUFFER_SECONDS;
                            };
                            case (#WhenDissolvedTimestampSeconds(_)) {
                                if (NodeUtils.getNeuronState(dissolveState) == NEURON_STATES.unlocked) {
                                    return true; // if unlocked and user changed to Locked, update delay
                                } else {
                                    return false;
                                }; 
                            };
                        };
                    };
                };
            };

            public func following_changed(nodeMem : SnsNodeMem) : Bool {
                let ?neuron = nodeMem.neuron_cache else return false;

                let followeeToSet = switch (nodeMem.variables.followee) {
                    case (#FolloweeId(followee)) { followee };
                    case (_) { return false };
                };

                let ?{ topic_id_to_followees } = neuron.topic_followees else return true;

                for ((_, { followees }) in topic_id_to_followees.vals()) {
                    label followeeLoop for (followee in followees.vals()) {
                        let ?{ id } = followee.neuron_id else continue followeeLoop;

                        // following assumed set across all topics
                        if (Blob.equal(id, followeeToSet)) return false;
                    };
                };

                // no following found, so it's not there or has changed
                return true;
            };

            public func dissolving_changed(nodeMem : SnsNodeMem) : Bool {
                let ?neuron = nodeMem.neuron_cache else return false;
                let ?dissolveState = neuron.dissolve_state else return false;

                let neuronState = NodeUtils.getNeuronState(dissolveState);

                switch (nodeMem.variables.dissolve_status) {
                    case (#Dissolving) {
                        return neuronState == NEURON_STATES.locked;
                    };
                    case (#Locked) {
                        return neuronState == NEURON_STATES.dissolving;
                    };
                };
            };

            public func stake_increased(nodeMem : SnsNodeMem) : Bool {
                return Option.isSome(nodeMem.internals.refresh_idx);
            };
        };

        module NeuronActions {
            public func refresh_neuron(vec : T.NodeCoreMem, vid : T.NodeId, nodeMem : SnsNodeMem) : async* () {
                let ?governanceCanister = nodeMem.internals.governance_canister else return;
                let neuronLedger = U.onlyICLedger(vec.ledgers[0]);
                let ?{ cls = #icrc(ledger) } = core.get_ledger_cls(neuronLedger) else return;
                let ?refreshIdx = nodeMem.internals.refresh_idx else return;

                if (ledger.isSent(refreshIdx)) {
                    let sns = SNS.Governance({
                        canister_id = core.getThisCan();
                        sns_canister_id = governanceCanister;
                        sns_ledger_canister_id = neuronLedger;
                    });

                    let nonce = NodeUtils.get_neuron_nonce(vid, 0);

                    switch (await* sns.claimNeuron({ nonce = nonce; controller = core.getThisCan() })) {
                        case (#ok(_)) {
                            nodeMem.internals.neuron_claimed := true;
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
                let ?governanceCanister = nodeMem.internals.governance_canister else return;
                let ?neuron = nodeMem.neuron_cache else return;
                let ?parameters = nodeMem.parameters_cache else return;
                let ?{ id } = neuron.id else return;

                if (CacheManager.delay_changed(nodeMem)) {
                    let neuron = SNS.Neuron({
                        sns_canister_id = governanceCanister;
                        neuron_id = id;
                    });

                    let nowSecs = U.now() / 1_000_000_000;
                    let extraBuffer : Nat64 = 60; // add 60 seconds as a buffer

                    let ?minimumDelay = parameters.neuron_minimum_dissolve_delay_to_vote_seconds else return;
                    let ?maximumDelay = parameters.max_dissolve_delay_seconds else return;

                    let delay : Nat64 = switch (nodeMem.variables.dissolve_delay) {
                        case (#Default) { minimumDelay };
                        case (#DelayDays(days)) { days * ONE_DAY_SECONDS };
                    };

                    let cleanedDelay = Nat64.min(
                        Nat64.max(delay, minimumDelay),
                        maximumDelay,
                    );

                    // Store the cleaned delay in nodeMem
                    nodeMem.variables.dissolve_delay := #DelayDays(cleanedDelay / ONE_DAY_SECONDS);

                    switch (await* neuron.setDissolveTimestamp({ dissolve_timestamp_seconds = nowSecs + extraBuffer + cleanedDelay })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "update_delay", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "update_delay", #Err(debug_show err));
                        };
                    };
                };
            };

            public func update_following(nodeMem : SnsNodeMem) : async* () {
                let ?governanceCanister = nodeMem.internals.governance_canister else return;
                let ?{ id = ?{ id } } = nodeMem.neuron_cache else return;

                if (CacheManager.following_changed(nodeMem)) {
                    let followeeToSet : Blob = switch (nodeMem.variables.followee) {
                        case (#FolloweeId(followee)) { followee };
                        case (_) { return };
                    };

                    let neuron = SNS.Neuron({
                        sns_canister_id = governanceCanister;
                        neuron_id = id;
                    });

                    // Prepare the followees for each topic
                    let topicFollowingArgs = [
                        {
                            topic = ?#DappCanisterManagement;
                            followees = [{
                                alias = null;
                                neuron_id = ?{ id = followeeToSet };
                            }];
                        },
                        {
                            topic = ?#DaoCommunitySettings;
                            followees = [{
                                alias = null;
                                neuron_id = ?{ id = followeeToSet };
                            }];
                        },
                        {
                            topic = ?#ApplicationBusinessLogic;
                            followees = [{
                                alias = null;
                                neuron_id = ?{ id = followeeToSet };
                            }];
                        },
                        {
                            topic = ?#CriticalDappOperations;
                            followees = [{
                                alias = null;
                                neuron_id = ?{ id = followeeToSet };
                            }];
                        },
                        {
                            topic = ?#TreasuryAssetManagement;
                            followees = [{
                                alias = null;
                                neuron_id = ?{ id = followeeToSet };
                            }];
                        },
                        {
                            topic = ?#Governance;
                            followees = [{
                                alias = null;
                                neuron_id = ?{ id = followeeToSet };
                            }];
                        },
                        {
                            topic = ?#SnsFrameworkManagement;
                            followees = [{
                                alias = null;
                                neuron_id = ?{ id = followeeToSet };
                            }];
                        },
                    ];

                    switch (await* neuron.setFollowing({ followeesForTopic = topicFollowingArgs })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "update_following", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "update_following", #Err(debug_show err));
                        };
                    };
                };
            };

            public func update_dissolving(nodeMem : SnsNodeMem) : async* () {
                let ?governanceCanister = nodeMem.internals.governance_canister else return;
                let ?neuron = nodeMem.neuron_cache else return;
                let ?{ id } = neuron.id else return;

                if (CacheManager.dissolving_changed(nodeMem)) {
                    let neuron = SNS.Neuron({
                        sns_canister_id = governanceCanister;
                        neuron_id = id;
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
                let ?governanceCanister = nodeMem.internals.governance_canister else return;
                let ?neuron = nodeMem.neuron_cache else return;
                let ?{ id } = neuron.id else return;
                let ?sourceMaturity = core.getSource(vid, vec, 1) else return;
                let tokenFee = core.Source.fee(sourceMaturity);

                if (neuron.maturity_e8s_equivalent > Nat64.fromNat(tokenFee)) {
                    // send maturity to the maturity source
                    let ?{ owner; subaccount } = core.getSourceAccountIC(vec, 1) else return;

                    // formatting for SNS Account
                    let useSubaccount : ?{ subaccount : Blob } = switch (subaccount) {
                        case (?sub) { ?{ subaccount = sub } };
                        case (_) { null };
                    };

                    let neuron = SNS.Neuron({
                        sns_canister_id = governanceCanister;
                        neuron_id = id;
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

            public func disburse_neuron(nodeMem : SnsNodeMem, vec : T.NodeCoreMem) : async* () {
                let ?governanceCanister = nodeMem.internals.governance_canister else return;
                let ?neuron = nodeMem.neuron_cache else return;
                let ?{ id } = neuron.id else return;

                let userWantsToDisburse = switch (nodeMem.variables.dissolve_status) {
                    case (#Dissolving) { true };
                    case (#Locked) { false };
                };

                let ?neuronState = neuron.dissolve_state else return;

                if (userWantsToDisburse and neuron.cached_neuron_stake_e8s > 0 and NodeUtils.getNeuronState(neuronState) == NEURON_STATES.unlocked) {
                    let neuron = SNS.Neuron({
                        sns_canister_id = governanceCanister;
                        neuron_id = id;
                    });

                    let ?{ owner; subaccount } = core.getDestinationAccountIC(vec, 1) else return;

                    let useSubaccount : ?{ subaccount : Blob } = switch (subaccount) {
                        case (?sub) { ?{ subaccount = sub } };
                        case (_) { null };
                    };

                    switch (await* neuron.disburse({ to_account = ?{ owner = ?owner; subaccount = useSubaccount }; amount = null })) {
                        case (#ok(_)) {
                            NodeUtils.log_activity(nodeMem, "disburse_neuron", #Ok);
                        };
                        case (#err(err)) {
                            NodeUtils.log_activity(nodeMem, "disburse_neuron", #Err(debug_show err));
                        };
                    };
                };
            };
        };
    };

};
