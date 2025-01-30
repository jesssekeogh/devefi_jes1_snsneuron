import Ver1 "./memory/v1";
import Principal "mo:base/Principal";

module {

    public type CreateRequest = {
        init : {
            governance_canister : Principal;
        };
        variables : {
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
            governance_canister : Principal;
        };
        variables : {
            dissolve_delay : Ver1.SnsDissolveDelay;
            dissolve_status : Ver1.SnsDissolveStatus;
            followee : Ver1.SnsFollowee;
        };
        internals : {
            updating : Ver1.SnsNeuronUpdatingStatus;
            refresh_idx : ?Nat64;
            neuron_claimed : Bool;
            neuron_state : ?Int32;
        };
        neuron_cache : ?Ver1.SnsNeuronCache;
        parameters_cache : ?Ver1.SnsParametersCache;
        log : [Ver1.SnsNeuronActivity];
    };

};
