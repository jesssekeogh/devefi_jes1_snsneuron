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
        var neuron_cache : ?SnsNeuronCache;
        var parameters_cache : ?SnsParametersCache;
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

    public type SnsFollowee = Blob;

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
        id : ?{ id : Blob };
        permissions : [{
            principal : ?Principal;
            permission_type : [Int32];
        }];
        maturity_e8s_equivalent : Nat64;
        cached_neuron_stake_e8s : Nat64;
        created_timestamp_seconds : Nat64;
        source_nns_neuron_id : ?Nat64;
        auto_stake_maturity : ?Bool;
        aging_since_timestamp_seconds : Nat64;
        dissolve_state : ?{
            #DissolveDelaySeconds : Nat64;
            #WhenDissolvedTimestampSeconds : Nat64;
        };
        voting_power_percentage_multiplier : Nat64;
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
        neuron_fees_e8s : Nat64;
    };

    public type SnsParametersCache = {
        default_followees : ?{
            followees : [(Nat64, { followees : [{ id : Blob }] })];
        };
        max_dissolve_delay_seconds : ?Nat64;
        max_dissolve_delay_bonus_percentage : ?Nat64;
        max_followees_per_function : ?Nat64;
        neuron_claimer_permissions : ?{ permissions : [Int32] };
        neuron_minimum_stake_e8s : ?Nat64;
        max_neuron_age_for_age_bonus : ?Nat64;
        initial_voting_period_seconds : ?Nat64;
        neuron_minimum_dissolve_delay_to_vote_seconds : ?Nat64;
        reject_cost_e8s : ?Nat64;
        max_proposals_to_keep_per_action : ?Nat32;
        wait_for_quiet_deadline_increase_seconds : ?Nat64;
        max_number_of_neurons : ?Nat64;
        transaction_fee_e8s : ?Nat64;
        max_number_of_proposals_with_ballots : ?Nat64;
        max_age_bonus_percentage : ?Nat64;
        neuron_grantable_permissions : ?{ permissions : [Int32] };
        voting_rewards_parameters : ?{
            final_reward_rate_basis_points : ?Nat64;
            initial_reward_rate_basis_points : ?Nat64;
            reward_rate_transition_duration_seconds : ?Nat64;
            round_duration_seconds : ?Nat64;
        };
        maturity_modulation_disabled : ?Bool;
        max_number_of_principals_per_neuron : ?Nat64;
    };
};
