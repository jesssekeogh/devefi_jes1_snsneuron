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
            governance_canister : Principal;
            neuron_creator : NeuronCreator;
        };
        variables : {
            var dissolve_delay : SnsDissolveDelay;
            var dissolve_status : SnsDissolveStatus;
            var followee : SnsFollowee;
        };
        internals : {
            var updating : SnsNeuronUpdatingStatus;
            var refresh_idx : ?Nat64;
        };
        neuron_cache : SnsNeuronCache;
        parameters_cache : SnsParametersCache;
        var log : [SnsNeuronActivity];
    };

    public type NeuronCreator = {
        #Default;
        #External : Principal;
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

    public type SnsParametersCache = {
        var default_followees : ?{
            followees : [(Nat64, { followees : [{ id : Blob }] })];
        };
        var max_dissolve_delay_seconds : ?Nat64;
        var max_dissolve_delay_bonus_percentage : ?Nat64;
        var max_followees_per_function : ?Nat64;
        var neuron_claimer_permissions : ?{ permissions : [Int32] };
        var neuron_minimum_stake_e8s : ?Nat64;
        var max_neuron_age_for_age_bonus : ?Nat64;
        var initial_voting_period_seconds : ?Nat64;
        var neuron_minimum_dissolve_delay_to_vote_seconds : ?Nat64;
        var reject_cost_e8s : ?Nat64;
        var max_proposals_to_keep_per_action : ?Nat32;
        var wait_for_quiet_deadline_increase_seconds : ?Nat64;
        var max_number_of_neurons : ?Nat64;
        var transaction_fee_e8s : ?Nat64;
        var max_number_of_proposals_with_ballots : ?Nat64;
        var max_age_bonus_percentage : ?Nat64;
        var neuron_grantable_permissions : ?{ permissions : [Int32] };
        var voting_rewards_parameters : ?{
            final_reward_rate_basis_points : ?Nat64;
            initial_reward_rate_basis_points : ?Nat64;
            reward_rate_transition_duration_seconds : ?Nat64;
            round_duration_seconds : ?Nat64;
        };
        var maturity_modulation_disabled : ?Bool;
        var max_number_of_principals_per_neuron : ?Nat64;
    };
};
