import Ver1 "./memory/v1";

module {

    public type CreateRequest = {
        variables : {
            neuron_type : Ver1.SnsNeuronType;
            dissolve_delay : Ver1.SnsDissolveDelay;
            dissolve_status : Ver1.SnsDissolveStatus;
            followee : Ver1.SnsFollowee;
        };
    };

    public type ModifyRequest = {
        dissolve_delay : ?Ver1.SnsDissolveDelay;
        dissolve_status : ?Ver1.SnsDissolveStatus;
        followee : ?Ver1.SnsFollowee;
    };

    public type Shared = {
        init : {
            neuron_nonce : Nat64;
        };
        variables : {
            neuron_type : Ver1.SnsNeuronType;
            dissolve_delay : Ver1.SnsDissolveDelay;
            dissolve_status : Ver1.SnsDissolveStatus;
            followee : Ver1.SnsFollowee;
        };
        internals : {
            updating : Ver1.SnsNeuronUpdatingStatus;
            refresh_idx : ?Nat64;
        };
        cache : SharedSnsNeuronCache;
        log : [Ver1.SnsNeuronActivity];
    };

    public type SharedSnsNeuronCache = {
        neuron_id : ?Blob;
        permissions : [{
            principal : ?Principal;
            permission_type : [Int32];
        }];
        maturity_e8s_equivalent : ?Nat64;
        cached_neuron_stake_e8s : ?Nat64;
        created_timestamp_seconds : ?Nat64;
        source_nns_neuron_id : ?Nat64;
        auto_stake_maturity : ?Bool;
        aging_since_timestamp_seconds : ?Nat64;
        dissolve_state : ?{
            #DissolveDelaySeconds : Nat64;
            #WhenDissolvedTimestampSeconds : Nat64;
        };
        voting_power_percentage_multiplier : ?Nat64;
        vesting_period_seconds : ?Nat64;
        disburse_maturity_in_progress : [{
            timestamp_of_disbursement_seconds : Nat64;
            amount_e8s : Nat64;
            account_to_disburse_to : ?{
                owner : ?Principal;
                subaccount : ?{ subaccount : Blob };
            };
            finalize_disbursement_timestamp_seconds : ?Nat64;
        }];
        followees : [(Nat64, { followees : [{ id : Blob }] })];
        neuron_fees_e8s : ?Nat64;
    };

};
