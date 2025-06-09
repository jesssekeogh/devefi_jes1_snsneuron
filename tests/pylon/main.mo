import Principal "mo:base/Principal";
import Rechain "mo:rechain";
import RT "./rechain";
import Timer "mo:base/Timer";
import T "./vector_modules";
import U "mo:devefi/utils";
import MU_sys "mo:devefi/sys";
import Ledgers "mo:devefi/ledgers";
import ICRC55 "mo:devefi/ICRC55";
import VecSnsNeuron "../../src";
import Core "mo:devefi/core";

actor class SNSTESTPYLON() = this {

    let me_can = Principal.fromActor(this);
    stable let chain_mem = Rechain.Mem.Rechain.V1.new();

    var chain = Rechain.Chain<system, RT.DispatchAction, RT.DispatchActionError>({
        settings = ?{
            Rechain.DEFAULT_SETTINGS with supportedBlocks = [{
                block_type = "55vec";
                url = "https://github.com/dfinity/ICRC/issues/55";
            }];
        };
        xmem = chain_mem;
        encodeBlock = RT.encodeBlock;
        reducers = [];
        me_can;
    });

    stable let dvf_mem_1 = Ledgers.Mem.Ledgers.V1.new();

    let dvf = Ledgers.Ledgers<system>({ xmem = dvf_mem_1; me_can });

    stable let mem_core_1 = Core.Mem.Core.V1.new();

    let sns_icrc_1 : Principal = Principal.fromText("75lp5-u7777-77776-qaaba-cai");

    let core = Core.Mod<system>({
        xmem = mem_core_1;
        settings = {
            PYLON_NAME = "Neuron";
            PYLON_GOVERNED_BY = "Neutrinite DAO";
            BILLING = {
                ledger = sns_icrc_1;
                min_create_balance = 50000000;
                operation_cost = 20_000;
                freezing_threshold_days = 10;
                exempt_daily_cost_balance = null;
                split = {
                    platform = 20;
                    pylon = 20;
                    author = 40;
                    affiliate = 20;
                };
                pylon_account = {
                    owner = Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai");
                    subaccount = null;
                };
                platform_account = {
                    owner = Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai");
                    subaccount = null;
                };
            };
            TEMP_NODE_EXPIRATION_SEC = 3600;
            MAX_INSTRUCTIONS_PER_HEARTBEAT = 300_000_000;
            REQUEST_MAX_EXPIRE_SEC = 3600;
            ALLOW_TEMP_NODE_CREATION = true;
        } : Core.SETTINGS;
        dvf;
        chain;
        me_can;
    });

    // Vector modules
    stable let mem_vec_snsneuron_1 = VecSnsNeuron.Mem.Vector.V1.new();
    stable let mem_vec_snsneuron_2 = VecSnsNeuron.Mem.Vector.V2.upgrade(mem_vec_snsneuron_1);

    let devefi_jes1_snsneuron = VecSnsNeuron.Mod({
        xmem = mem_vec_snsneuron_2;
        core;
    });

    let vmod = T.VectorModules({ devefi_jes1_snsneuron });

    let sys = MU_sys.Mod<system, T.CreateRequest, T.Shared, T.ModifyRequest>({
        xmem = mem_core_1;
        dvf;
        core;
        vmod;
        me_can;
    });

    private func proc() { devefi_jes1_snsneuron.run() };

    private func async_proc() : async* () {
        await* devefi_jes1_snsneuron.runAsync();
    };

    ignore Timer.recurringTimer<system>(
        #seconds 30,
        func() : async () { core.heartbeat(proc) },
    );

    ignore Timer.recurringTimer<system>(
        #seconds 30,
        func() : async () { await* async_proc() },
    );

    // ICRC-55

    public query func icrc55_get_pylon_meta() : async ICRC55.PylonMetaResp {
        sys.icrc55_get_pylon_meta();
    };

    public shared ({ caller }) func icrc55_command(req : ICRC55.BatchCommandRequest<T.CreateRequest, T.ModifyRequest>) : async ICRC55.BatchCommandResponse<T.Shared> {
        sys.icrc55_command<RT.DispatchActionError>(
            caller,
            req,
            func(r) {
                chain.dispatch({
                    caller;
                    payload = #vector(r);
                    ts = U.now();
                });
            },
        );
    };

    public query func icrc55_command_validate(req : ICRC55.BatchCommandRequest<T.CreateRequest, T.ModifyRequest>) : async ICRC55.ValidationResult {
        #Ok(debug_show (req));
    };

    public query func icrc55_get_nodes(req : [ICRC55.GetNode]) : async [?MU_sys.NodeShared<T.Shared>] {
        sys.icrc55_get_nodes(req);
    };

    public query ({ caller }) func icrc55_get_controller_nodes(req : ICRC55.GetControllerNodesRequest) : async [MU_sys.NodeShared<T.Shared>] {
        sys.icrc55_get_controller_nodes(caller, req);
    };

    public query func icrc55_get_defaults(id : Text) : async T.CreateRequest {
        sys.icrc55_get_defaults(id);
    };

    public shared ({ caller }) func icrc55_account_register(acc : ICRC55.Account) : async () {
        sys.icrc55_account_register(caller, acc);
    };

    public query ({ caller }) func icrc55_accounts(req : ICRC55.AccountsRequest) : async ICRC55.AccountsResponse {
        sys.icrc55_accounts(caller, req);
    };

    // ICRC-3

    public query func icrc3_get_blocks(args : Rechain.GetBlocksArgs) : async Rechain.GetBlocksResult {
        return chain.icrc3_get_blocks(args);
    };

    public query func icrc3_get_archives(args : Rechain.GetArchivesArgs) : async Rechain.GetArchivesResult {
        return chain.icrc3_get_archives(args);
    };

    public query func icrc3_supported_block_types() : async [Rechain.BlockType] {
        return chain.icrc3_supported_block_types();
    };
    public query func icrc3_get_tip_certificate() : async ?Rechain.DataCertificate {
        return chain.icrc3_get_tip_certificate();
    };

    // ---------- Debug functions -----------

    public shared ({ caller }) func add_supported_ledger(id : Principal, ltype : { #icp; #icrc }) : () {
        assert Principal.isController(caller);
        dvf.add_ledger<system>(id, ltype);
    };

    public query func get_ledger_errors() : async [[Text]] {
        dvf.getErrors();
    };

    public query func get_ledgers_info() : async [Ledgers.LedgerInfo] {
        dvf.getLedgersInfo();
    };

};
