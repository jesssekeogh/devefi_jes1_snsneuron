import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface Account {
  'owner' : Principal,
  'subaccount' : [] | [Uint8Array | number[]],
}
export interface AccountEndpoint { 'balance' : bigint, 'endpoint' : Endpoint }
export interface AccountsRequest {
  'owner' : Principal,
  'subaccount' : [] | [Uint8Array | number[]],
}
export type AccountsResponse = Array<AccountEndpoint>;
export interface ArchivedTransactionResponse {
  'args' : Array<TransactionRange>,
  'callback' : GetTransactionsFn,
}
export interface BatchCommandRequest {
  'request_id' : [] | [number],
  'controller' : Controller,
  'signature' : [] | [Uint8Array | number[]],
  'expire_at' : [] | [bigint],
  'commands' : Array<Command>,
}
export type BatchCommandResponse = {
    'ok' : { 'id' : [] | [bigint], 'commands' : Array<CommandResponse> }
  } |
  {
    'err' : { 'caller_not_controller' : null } |
      { 'expired' : null } |
      { 'other' : string } |
      { 'duplicate' : bigint } |
      { 'invalid_signature' : null }
  };
export interface Billing {
  'transaction_fee' : BillingTransactionFee,
  'cost_per_day' : bigint,
}
export interface BillingFeeSplit {
  'platform' : bigint,
  'author' : bigint,
  'affiliate' : bigint,
  'pylon' : bigint,
}
export interface BillingPylon {
  'operation_cost' : bigint,
  'freezing_threshold_days' : bigint,
  'min_create_balance' : bigint,
  'split' : BillingFeeSplit,
  'ledger' : Principal,
  'platform_account' : Account,
  'pylon_account' : Account,
}
export type BillingTransactionFee = { 'none' : null } |
  { 'transaction_percentage_fee_e8s' : bigint } |
  { 'flat_fee_multiplier' : bigint };
export interface BlockType { 'url' : string, 'block_type' : string }
export type Command = { 'modify_node' : ModifyNodeRequest } |
  { 'create_node' : CreateNodeRequest } |
  { 'transfer' : TransferRequest } |
  { 'delete_node' : LocalNodeId };
export type CommandResponse = { 'modify_node' : ModifyNodeResponse } |
  { 'create_node' : CreateNodeResponse } |
  { 'transfer' : TransferResponse } |
  { 'delete_node' : DeleteNodeResp };
export interface CommonCreateRequest {
  'controllers' : Array<Controller>,
  'initial_billing_amount' : [] | [bigint],
  'extractors' : Uint32Array | number[],
  'temp_id' : number,
  'billing_option' : bigint,
  'destinations' : Array<[] | [InputAddress]>,
  'sources' : Array<[] | [InputAddress]>,
  'affiliate' : [] | [Account],
  'ledgers' : Array<SupportedLedger>,
  'temporary' : boolean,
  'refund' : Account,
}
export interface CommonModifyRequest {
  'active' : [] | [boolean],
  'controllers' : [] | [Array<Controller>],
  'extractors' : [] | [Uint32Array | number[]],
  'destinations' : [] | [Array<[] | [InputAddress]>],
  'sources' : [] | [Array<[] | [InputAddress]>],
  'refund' : [] | [Account],
}
export interface Controller {
  'owner' : Principal,
  'subaccount' : [] | [Uint8Array | number[]],
}
export type CreateNodeRequest = [CommonCreateRequest, CreateRequest];
export type CreateNodeResponse = { 'ok' : GetNodeResponse } |
  { 'err' : string };
export type CreateRequest = { 'devefi_jes1_snsneuron' : CreateRequest__1 };
export interface CreateRequest__1 {
  'variables' : {
    'dissolve_delay' : SnsDissolveDelay,
    'dissolve_status' : SnsDissolveStatus,
    'followee' : SnsFollowee,
  },
}
export interface DataCertificate {
  'certificate' : Uint8Array | number[],
  'hash_tree' : Uint8Array | number[],
}
export type DeleteNodeResp = { 'ok' : null } |
  { 'err' : string };
export interface DestinationEndpointResp {
  'endpoint' : EndpointOpt,
  'name' : string,
}
export type Endpoint = { 'ic' : EndpointIC } |
  { 'other' : EndpointOther };
export interface EndpointIC { 'ledger' : Principal, 'account' : Account }
export type EndpointIdx = number;
export type EndpointOpt = { 'ic' : EndpointOptIC } |
  { 'other' : EndpointOptOther };
export interface EndpointOptIC {
  'ledger' : Principal,
  'account' : [] | [Account],
}
export interface EndpointOptOther {
  'platform' : bigint,
  'ledger' : Uint8Array | number[],
  'account' : [] | [Uint8Array | number[]],
}
export interface EndpointOther {
  'platform' : bigint,
  'ledger' : Uint8Array | number[],
  'account' : Uint8Array | number[],
}
export type EndpointsDescription = Array<[LedgerIdx, LedgerLabel]>;
export interface GetArchivesArgs { 'from' : [] | [Principal] }
export type GetArchivesResult = Array<GetArchivesResultItem>;
export interface GetArchivesResultItem {
  'end' : bigint,
  'canister_id' : Principal,
  'start' : bigint,
}
export type GetBlocksArgs = Array<TransactionRange>;
export interface GetBlocksResult {
  'log_length' : bigint,
  'blocks' : Array<{ 'id' : bigint, 'block' : [] | [Value] }>,
  'archived_blocks' : Array<ArchivedTransactionResponse>,
}
export interface GetControllerNodesRequest {
  'id' : Controller,
  'start' : LocalNodeId,
  'length' : number,
}
export type GetNode = { 'id' : LocalNodeId } |
  { 'endpoint' : Endpoint };
export interface GetNodeResponse {
  'id' : LocalNodeId,
  'created' : bigint,
  'active' : boolean,
  'modified' : bigint,
  'controllers' : Array<Controller>,
  'custom' : [] | [Shared],
  'extractors' : Uint32Array | number[],
  'billing' : {
    'transaction_fee' : BillingTransactionFee,
    'expires' : [] | [bigint],
    'current_balance' : bigint,
    'billing_option' : bigint,
    'account' : Account,
    'frozen' : boolean,
    'cost_per_day' : bigint,
  },
  'destinations' : Array<DestinationEndpointResp>,
  'sources' : Array<SourceEndpointResp>,
  'refund' : Account,
}
export type GetTransactionsFn = ActorMethod<
  [Array<TransactionRange>],
  GetTransactionsResult
>;
export interface GetTransactionsResult {
  'log_length' : bigint,
  'blocks' : Array<{ 'id' : bigint, 'block' : [] | [Value] }>,
  'archived_blocks' : Array<ArchivedTransactionResponse>,
}
export interface Info {
  'pending' : bigint,
  'last_indexed_tx' : bigint,
  'errors' : bigint,
  'lastTxTime' : bigint,
  'accounts' : bigint,
  'actor_principal' : [] | [Principal],
  'reader_instructions_cost' : bigint,
  'sender_instructions_cost' : bigint,
}
export interface Info__1 {
  'pending' : bigint,
  'last_indexed_tx' : bigint,
  'errors' : bigint,
  'lastTxTime' : bigint,
  'accounts' : bigint,
  'actor_principal' : Principal,
  'reader_instructions_cost' : bigint,
  'sender_instructions_cost' : bigint,
}
export type InputAddress = { 'ic' : Account } |
  { 'other' : Uint8Array | number[] } |
  { 'temp' : { 'id' : number, 'source_idx' : EndpointIdx } };
export type LedgerIdx = bigint;
export interface LedgerInfo {
  'fee' : bigint,
  'decimals' : number,
  'name' : string,
  'ledger' : SupportedLedger,
  'symbol' : string,
}
export interface LedgerInfo__1 {
  'id' : Principal,
  'info' : { 'icp' : Info } |
    { 'icrc' : Info__1 },
}
export type LedgerLabel = string;
export type LocalNodeId = number;
export type ModifyNodeRequest = [
  LocalNodeId,
  [] | [CommonModifyRequest],
  [] | [ModifyRequest],
];
export type ModifyNodeResponse = { 'ok' : GetNodeResponse } |
  { 'err' : string };
export type ModifyRequest = { 'devefi_jes1_snsneuron' : ModifyRequest__1 };
export interface ModifyRequest__1 {
  'dissolve_delay' : [] | [SnsDissolveDelay],
  'dissolve_status' : [] | [SnsDissolveStatus],
  'followee' : [] | [SnsFollowee],
}
export interface ModuleMeta {
  'id' : string,
  'create_allowed' : boolean,
  'ledger_slots' : Array<string>,
  'name' : string,
  'billing' : Array<Billing>,
  'description' : string,
  'supported_ledgers' : Array<SupportedLedger>,
  'author' : string,
  'version' : Version,
  'destinations' : EndpointsDescription,
  'sources' : EndpointsDescription,
  'temporary_allowed' : boolean,
  'author_account' : Account,
}
export interface NodeShared {
  'id' : LocalNodeId,
  'created' : bigint,
  'active' : boolean,
  'modified' : bigint,
  'controllers' : Array<Controller>,
  'custom' : [] | [Shared],
  'extractors' : Uint32Array | number[],
  'billing' : {
    'transaction_fee' : BillingTransactionFee,
    'expires' : [] | [bigint],
    'current_balance' : bigint,
    'billing_option' : bigint,
    'account' : Account,
    'frozen' : boolean,
    'cost_per_day' : bigint,
  },
  'destinations' : Array<DestinationEndpointResp>,
  'sources' : Array<SourceEndpointResp>,
  'refund' : Account,
}
export interface PylonMetaResp {
  'name' : string,
  'billing' : BillingPylon,
  'supported_ledgers' : Array<LedgerInfo>,
  'request_max_expire_sec' : bigint,
  'governed_by' : string,
  'temporary_nodes' : { 'allowed' : boolean, 'expire_sec' : bigint },
  'modules' : Array<ModuleMeta>,
}
export interface SNSTESTPYLON {
  'add_supported_ledger' : ActorMethod<
    [Principal, { 'icp' : null } | { 'icrc' : null }],
    undefined
  >,
  'get_ledger_errors' : ActorMethod<[], Array<Array<string>>>,
  'get_ledgers_info' : ActorMethod<[], Array<LedgerInfo__1>>,
  'icrc3_get_archives' : ActorMethod<[GetArchivesArgs], GetArchivesResult>,
  'icrc3_get_blocks' : ActorMethod<[GetBlocksArgs], GetBlocksResult>,
  'icrc3_get_tip_certificate' : ActorMethod<[], [] | [DataCertificate]>,
  'icrc3_supported_block_types' : ActorMethod<[], Array<BlockType>>,
  'icrc55_account_register' : ActorMethod<[Account], undefined>,
  'icrc55_accounts' : ActorMethod<[AccountsRequest], AccountsResponse>,
  'icrc55_command' : ActorMethod<[BatchCommandRequest], BatchCommandResponse>,
  'icrc55_command_validate' : ActorMethod<
    [BatchCommandRequest],
    ValidationResult
  >,
  'icrc55_get_controller_nodes' : ActorMethod<
    [GetControllerNodesRequest],
    Array<NodeShared>
  >,
  'icrc55_get_defaults' : ActorMethod<[string], CreateRequest>,
  'icrc55_get_nodes' : ActorMethod<[Array<GetNode>], Array<[] | [NodeShared]>>,
  'icrc55_get_pylon_meta' : ActorMethod<[], PylonMetaResp>,
}
export type Shared = { 'devefi_jes1_snsneuron' : Shared__1 };
export interface Shared__1 {
  'log' : Array<SnsNeuronActivity>,
  'internals' : {
    'neuron_state' : [] | [number],
    'governance_canister' : [] | [Principal],
    'neuron_claimed' : boolean,
    'refresh_idx' : [] | [bigint],
    'updating' : SnsNeuronUpdatingStatus,
  },
  'parameters_cache' : [] | [SnsParametersCache],
  'variables' : {
    'dissolve_delay' : SnsDissolveDelay,
    'dissolve_status' : SnsDissolveStatus,
    'followee' : SnsFollowee,
  },
  'neuron_cache' : [] | [SnsNeuronCache],
}
export type SnsDissolveDelay = { 'Default' : null } |
  { 'DelayDays' : bigint };
export type SnsDissolveStatus = { 'Locked' : null } |
  { 'Dissolving' : null };
export type SnsFollowee = { 'FolloweeId' : Uint8Array | number[] } |
  { 'Unspecified' : null };
export type SnsNeuronActivity = {
    'Ok' : { 'operation' : string, 'timestamp' : bigint }
  } |
  { 'Err' : { 'msg' : string, 'operation' : string, 'timestamp' : bigint } };
export interface SnsNeuronCache {
  'id' : [] | [{ 'id' : Uint8Array | number[] }],
  'permissions' : Array<
    {
      'principal' : [] | [Principal],
      'permission_type' : Int32Array | number[],
    }
  >,
  'maturity_e8s_equivalent' : bigint,
  'cached_neuron_stake_e8s' : bigint,
  'created_timestamp_seconds' : bigint,
  'source_nns_neuron_id' : [] | [bigint],
  'auto_stake_maturity' : [] | [boolean],
  'aging_since_timestamp_seconds' : bigint,
  'dissolve_state' : [] | [
    { 'DissolveDelaySeconds' : bigint } |
      { 'WhenDissolvedTimestampSeconds' : bigint }
  ],
  'voting_power_percentage_multiplier' : bigint,
  'vesting_period_seconds' : [] | [bigint],
  'disburse_maturity_in_progress' : Array<
    {
      'timestamp_of_disbursement_seconds' : bigint,
      'amount_e8s' : bigint,
      'account_to_disburse_to' : [] | [
        {
          'owner' : [] | [Principal],
          'subaccount' : [] | [{ 'subaccount' : Uint8Array | number[] }],
        }
      ],
      'finalize_disbursement_timestamp_seconds' : [] | [bigint],
    }
  >,
  'followees' : Array<
    [bigint, { 'followees' : Array<{ 'id' : Uint8Array | number[] }> }]
  >,
  'neuron_fees_e8s' : bigint,
}
export type SnsNeuronUpdatingStatus = { 'Calling' : bigint } |
  { 'Done' : bigint } |
  { 'Init' : null };
export interface SnsParametersCache {
  'default_followees' : [] | [
    {
      'followees' : Array<
        [bigint, { 'followees' : Array<{ 'id' : Uint8Array | number[] }> }]
      >,
    }
  ],
  'max_dissolve_delay_seconds' : [] | [bigint],
  'max_dissolve_delay_bonus_percentage' : [] | [bigint],
  'max_followees_per_function' : [] | [bigint],
  'neuron_claimer_permissions' : [] | [
    { 'permissions' : Int32Array | number[] }
  ],
  'neuron_minimum_stake_e8s' : [] | [bigint],
  'max_neuron_age_for_age_bonus' : [] | [bigint],
  'initial_voting_period_seconds' : [] | [bigint],
  'neuron_minimum_dissolve_delay_to_vote_seconds' : [] | [bigint],
  'reject_cost_e8s' : [] | [bigint],
  'max_proposals_to_keep_per_action' : [] | [number],
  'wait_for_quiet_deadline_increase_seconds' : [] | [bigint],
  'max_number_of_neurons' : [] | [bigint],
  'transaction_fee_e8s' : [] | [bigint],
  'max_number_of_proposals_with_ballots' : [] | [bigint],
  'max_age_bonus_percentage' : [] | [bigint],
  'neuron_grantable_permissions' : [] | [
    { 'permissions' : Int32Array | number[] }
  ],
  'voting_rewards_parameters' : [] | [
    {
      'final_reward_rate_basis_points' : [] | [bigint],
      'initial_reward_rate_basis_points' : [] | [bigint],
      'reward_rate_transition_duration_seconds' : [] | [bigint],
      'round_duration_seconds' : [] | [bigint],
    }
  ],
  'maturity_modulation_disabled' : [] | [boolean],
  'max_number_of_principals_per_neuron' : [] | [bigint],
}
export interface SourceEndpointResp {
  'balance' : bigint,
  'endpoint' : Endpoint,
  'name' : string,
}
export type SupportedLedger = { 'ic' : Principal } |
  { 'other' : { 'platform' : bigint, 'ledger' : Uint8Array | number[] } };
export interface TransactionRange { 'start' : bigint, 'length' : bigint }
export interface TransferRequest {
  'to' : { 'node_billing' : LocalNodeId } |
    { 'node' : { 'node_id' : LocalNodeId, 'endpoint_idx' : EndpointIdx } } |
    { 'temp' : { 'id' : number, 'source_idx' : EndpointIdx } } |
    {
      'external_account' : { 'ic' : Account } |
        { 'other' : Uint8Array | number[] }
    } |
    { 'account' : Account },
  'from' : {
      'node' : { 'node_id' : LocalNodeId, 'endpoint_idx' : EndpointIdx }
    } |
    { 'account' : Account },
  'ledger' : SupportedLedger,
  'amount' : bigint,
}
export type TransferResponse = { 'ok' : bigint } |
  { 'err' : string };
export type ValidationResult = { 'Ok' : string } |
  { 'Err' : string };
export type Value = { 'Int' : bigint } |
  { 'Map' : Array<ValueMap> } |
  { 'Nat' : bigint } |
  { 'Blob' : Uint8Array | number[] } |
  { 'Text' : string } |
  { 'Array' : Array<Value> };
export type ValueMap = [string, Value];
export type Version = { 'alpha' : Uint16Array | number[] } |
  { 'beta' : Uint16Array | number[] } |
  { 'release' : Uint16Array | number[] };
export interface _SERVICE extends SNSTESTPYLON {}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
