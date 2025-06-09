import Ver2 "./memory/v2";
import Principal "mo:base/Principal";

module {

    public type CreateRequest = {
        variables : {
            dissolve_delay : Ver2.SnsDissolveDelay;
            dissolve_status : Ver2.SnsDissolveStatus;
            followee : Ver2.SnsFollowee;
        };
    };

    public type ModifyRequest = {
        dissolve_delay : ?Ver2.SnsDissolveDelay;
        dissolve_status : ?Ver2.SnsDissolveStatus;
        followee : ?Ver2.SnsFollowee;
    };

    public type Shared = {
        variables : {
            dissolve_delay : Ver2.SnsDissolveDelay;
            dissolve_status : Ver2.SnsDissolveStatus;
            followee : Ver2.SnsFollowee;
        };
        internals : {
            updating : Ver2.SnsNeuronUpdatingStatus;
            refresh_idx : ?Nat64;
            neuron_claimed : Bool;
            neuron_state : ?Int32;
            governance_canister : ?Principal;
        };
        neuron_cache : ?Ver2.SnsNeuronCache;
        parameters_cache : ?Ver2.SnsParametersCache;
        log : [Ver2.SnsNeuronActivity];
    };

};
