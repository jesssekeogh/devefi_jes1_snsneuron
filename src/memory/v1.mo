import Map "mo:map/Map";
import MU "mo:mosup";

module {

    public type Mem = {
        main : Map.Map<Nat32, SnsNodeMem>;
    };

    public func new() : MU.MemShell<Mem> = MU.new<Mem>({
        main = Map.new<Nat32, SnsNodeMem>();
    });

    public type SnsNodeMem = {
        init : {
            neuron_nonce : Nat64;
        };
        variables : {
            var neuron_type : SnsNeuronType;
            var dissolve_delay : SnsDissolveDelay;
            var dissolve_status : SnsDissolveStatus;
            var followee : SnsFollowee;
        };
        internals : {
            var updating : SnsNeuronUpdatingStatus;
            var refresh_idx : ?Nat64;
        };
        cache : SnsNeuronCache;
        var log : [SnsNeuronActivity];
    };

    public type SnsNeuronType = {
        #Default;
        #Transferred : { neuron_owner : Principal };
    };

    public type SnsDissolveDelay = {
        #Default;
        #DelayDays : Nat64;
    };

    public type SnsFollowee = {
        #Default;
        #FolloweeId : Blob;
    };

    public type SnsDissolveStatus = {
        #Dissolving;
        #Locked;
    };

    public type SnsNeuronUpdatingStatus = {
        #Init;
        #Calling : Nat64;
        #Done : Nat64;
    };

    public type SnsNeuronActivity = {
        #Ok : { operation : Text; timestamp : Nat64 };
        #Err : { operation : Text; msg : Text; timestamp : Nat64 };
    };

    public type SnsNeuronCache = {
        var neuron_id : ?Blob;
        var permissions : [{
            principal : ?Principal;
            permission_type : [Int32];
        }];
        var maturity_e8s_equivalent : ?Nat64;
        var cached_neuron_stake_e8s : ?Nat64;
        var created_timestamp_seconds : ?Nat64;
        var source_nns_neuron_id : ?Nat64;
        var auto_stake_maturity : ?Bool;
        var aging_since_timestamp_seconds : ?Nat64;
        var dissolve_state : ?{
            #DissolveDelaySeconds : Nat64;
            #WhenDissolvedTimestampSeconds : Nat64;
        };
        var voting_power_percentage_multiplier : ?Nat64;
        var vesting_period_seconds : ?Nat64;
        var disburse_maturity_in_progress : [{
            timestamp_of_disbursement_seconds : Nat64;
            amount_e8s : Nat64;
            account_to_disburse_to : ?{
                owner : ?Principal;
                subaccount : ?{ subaccount : Blob };
            };
            finalize_disbursement_timestamp_seconds : ?Nat64;
        }];
        var followees : [(Nat64, { followees : [{ id : Blob }] })];
        var neuron_fees_e8s : ?Nat64;
    };

};
