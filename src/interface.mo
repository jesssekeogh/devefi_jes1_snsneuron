import Ver1 "./memory/v1";
import Principal "mo:base/Principal";

module {

    public type CreateRequest = {
        init : {
            governance_canister : Principal;
            neuron_creator : ?Principal;
        };
        variables : {
            dissolve_delay : ?Ver1.SnsDissolveDelay;
            dissolve_status : ?Ver1.SnsDissolveStatus;
            followee : ?Ver1.SnsFollowee;
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
            governance_canister : Principal;
            neuron_creator : ?Principal;
        };
        variables : {
            dissolve_delay : ?Ver1.SnsDissolveDelay;
            dissolve_status : ?Ver1.SnsDissolveStatus;
            followee : ?Ver1.SnsFollowee;
        };
        internals : {
            updating : Ver1.SnsNeuronUpdatingStatus;
            refresh_idx : ?Nat64;
        };
        neuron_cache : ?Ver1.SnsNeuronCache;
        parameters_cache : ?Ver1.SnsParametersCache;
        log : [Ver1.SnsNeuronActivity];
    };

};
