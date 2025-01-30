import {
  _SERVICE as SNSTESTPYLON,
  NodeShared,
  CommonCreateRequest,
  CreateRequest,
  ModifyNodeRequest,
  BatchCommandResponse,
  ModifyRequest,
  LocalNodeId as NodeId,
  GetNodeResponse,
  SnsDissolveDelay,
  SnsDissolveStatus,
  SnsFollowee,
} from "./sns_test_pylon/declarations/sns_test_pylon.did.js";
import {
  _SERVICE as ICRCLEDGER,
  Account,
  TransferResult,
} from "./nns/icrcledger";
import {
  _SERVICE as SNSW,
  idlFactory as snswIdlFactory,
  SnsInitPayload,
} from "./nns/snsw";
import {
  Actor,
  PocketIc,
  createIdentity,
  SubnetStateType,
} from "@hadronous/pic";
import { Principal } from "@dfinity/principal";
import { SNSW_CANISTER_ID, GOVERNANCE_CANISTER_ID } from "./constants.ts";
import { SnsTestPylon } from "./sns_test_pylon/sns_test_pylon.ts";
import { NNS_STATE_PATH, NNS_SUBNET_ID } from "./constants.ts";
import { SetupSns } from "./setupsns.ts";

interface NeuronParams {
  neuron_ledger_canister: Principal;
  neuron_governance_canister: Principal;
  dissolve_delay: SnsDissolveDelay;
  followee: SnsFollowee;
  dissolve_status: SnsDissolveStatus;
}

interface StakeNodeParams {
  stake_amount: bigint;
  billing_actor: Actor<ICRCLEDGER>;
  ledger_actor: Actor<ICRCLEDGER>;
  neuron_params: NeuronParams;
}

export class Manager {
  private readonly me: ReturnType<typeof createIdentity>;
  private readonly pic: PocketIc;
  private readonly snsTestPylon: Actor<SNSTESTPYLON>;
  private readonly snswActor: Actor<SNSW>;
  private readonly snsTestPylonCanisterId: Principal;

  constructor(
    pic: PocketIc,
    me: ReturnType<typeof createIdentity>,
    snsTestPylon: Actor<SNSTESTPYLON>,
    snsTestPylonCanisterId: Principal,
    snswActor: Actor<SNSW>
  ) {
    this.pic = pic;
    this.me = me;
    this.snsTestPylon = snsTestPylon;
    this.snsTestPylonCanisterId = snsTestPylonCanisterId;
    this.snswActor = snswActor;
  }

  public static async beforeAll(): Promise<Manager> {
    let pic = await PocketIc.create(process.env.PIC_URL, {
      nns: {
        state: {
          type: SubnetStateType.FromPath,
          path: NNS_STATE_PATH,
          subnetId: Principal.fromText(NNS_SUBNET_ID),
        },
      },
      application: [{ state: { type: SubnetStateType.New } }],
      sns: { state: { type: SubnetStateType.New } },
    });

    await pic.setTime(new Date().getTime());
    await pic.tick();

    let identity = createIdentity("superSecretAlicePassword");

    // setup pylon
    let pylonFixture = await SnsTestPylon(pic);

    // setup snsW
    let snswActor = pic.createActor<SNSW>(snswIdlFactory, SNSW_CANISTER_ID);
    snswActor.setPrincipal(GOVERNANCE_CANISTER_ID);
    await pic.addCycles(SNSW_CANISTER_ID, 500000000000000);

    // remove nns subnet from possible deployments
    await snswActor.update_sns_subnet_list({
      sns_subnet_ids_to_add: [pic.getSnsSubnet().id],
      sns_subnet_ids_to_remove: [Principal.fromText(NNS_SUBNET_ID)],
    });

    return new Manager(
      pic,
      identity,
      pylonFixture.actor,
      pylonFixture.canisterId,
      snswActor
    );
  }

  public async afterAll(): Promise<void> {
    await this.pic.tearDown();
  }

  public async createSns(snsPayload: SnsInitPayload): Promise<SetupSns> {
    let sns = await SetupSns.create(
      this.pic,
      this.snswActor,
      snsPayload,
      this.snsTestPylon
    );

    // send me some tokens from this SNS to my account
    await this.sendIcrc({
      to: { owner: this.me.getPrincipal(), subaccount: [] },
      amount: 5000_0000_0000n,
      icrcActor: sns.getIcrcLedger(),
      sender: sns.getSnsCanisters().governance[0],
    });

    return sns;
  }

  public getMe(): Principal {
    return this.me.getPrincipal();
  }

  public getSnsTestPylon(): Actor<SNSTESTPYLON> {
    return this.snsTestPylon;
  }

  public getSnsTestPylonCanisterId(): Principal {
    return this.snsTestPylonCanisterId;
  }

  public async getNow(): Promise<bigint> {
    let time = await this.pic.getTime();
    return BigInt(Math.trunc(time));
  }

  public async advanceTime(mins: number): Promise<void> {
    await this.pic.advanceTime(mins * 60 * 1000);
  }

  public async advanceBlocks(blocks: number): Promise<void> {
    await this.pic.tick(blocks);
  }

  // used for when a refresh is pending on a node
  public async advanceBlocksAndTimeMinutes(rounds: number): Promise<void> {
    let mins = 10; // 10 mins
    let blocks = 10;
    for (let i = 0; i < rounds; i++) {
      await this.pic.advanceTime(mins * 60 * 1000);
      await this.pic.tick(blocks);
    }
  }

  public async advanceBlocksAndTimeHours(rounds: number): Promise<void> {
    const sixHoursMins = 6 * 60; // 6 hours
    const shortIntervalMins = 10; // 10 minutes
    const blocksForSixHours = 10; // Blocks for 6 hours
    const blocksForShortInterval = 5; // Blocks for 10 minutes

    for (let i = 0; i < rounds; i++) {
      await this.pic.advanceTime(sixHoursMins * 60 * 1000); // Convert minutes to milliseconds
      await this.pic.tick(blocksForSixHours);

      // Advance 10 minutes (to process things)
      await this.pic.advanceTime(shortIntervalMins * 60 * 1000); // Convert minutes to milliseconds
      await this.pic.tick(blocksForShortInterval);
    }
  }

  // Used for when no refresh is pending, a node is updated once every 12 hours (with 10 minutes to process)
  public async advanceBlocksAndTimeDays(rounds: number): Promise<void> {
    const halfDayMins = 12 * 60; // 12 hours
    const shortIntervalMins = 10; // 10 minutes
    const blocksForHalfDay = 10; // Blocks for 12 hours
    const blocksForShortInterval = 5; // Blocks for 10 minutes

    for (let i = 0; i < rounds; i++) {
      // run this twice (24 hours)
      for (let x = 0; x < 2; x++) {
        // Advance 12 hours
        await this.pic.advanceTime(halfDayMins * 60 * 1000); // Convert minutes to milliseconds
        await this.pic.tick(blocksForHalfDay);

        // Advance 10 minutes
        await this.pic.advanceTime(shortIntervalMins * 60 * 1000); // Convert minutes to milliseconds
        await this.pic.tick(blocksForShortInterval);
      }
    }
  }

  public convertDaysToSeconds(days: bigint): bigint {
    const secondsInADay = 24n * 60n * 60n; // Calculate seconds in a day using bigints
    return days * secondsInADay; // Multiply days by seconds in a day
  }

  public convertSecondsToDays(seconds: bigint): bigint {
    const secondsInADay = 24n * 60n * 60n;
    return seconds / secondsInADay;
  }

  public convertNanosToMillis(nanoTimestamp: bigint): bigint {
    return nanoTimestamp / 1_000_000n;
  }

  public hexStringToUint8Array = (hexString: string): Uint8Array => {
    const matches = hexString.match(/.{1,2}/g);

    return Uint8Array.from(matches.map((byte) => parseInt(byte, 16)));
  };

  public uint8ArrayToHexString = (bytes: Uint8Array | number[]) => {
    if (!(bytes instanceof Uint8Array)) {
      bytes = Uint8Array.from(bytes);
    }
    return bytes.reduce(
      (str, byte) => str + byte.toString(16).padStart(2, "0"),
      ""
    );
  };

  public async createNode(stakeParams: StakeNodeParams): Promise<NodeShared> {
    let [
      {
        endpoint: {
          // @ts-ignore
          ic: { account },
        },
      },
    ] = await this.snsTestPylon.icrc55_accounts({
      owner: this.me.getPrincipal(),
      subaccount: [],
    });

    await this.sendIcrc({
      to: account,
      amount: 100_0001_0000n, // more than enough (10_000 for fees)
      icrcActor: stakeParams.billing_actor,
      sender: this.me.getPrincipal(),
    });

    await this.advanceBlocksAndTimeMinutes(3);

    let req: CommonCreateRequest = {
      controllers: [{ owner: this.me.getPrincipal(), subaccount: [] }],
      destinations: [
        [{ ic: { owner: this.me.getPrincipal(), subaccount: [] } }],
        [{ ic: { owner: this.me.getPrincipal(), subaccount: [] } }],
      ],
      refund: { owner: this.me.getPrincipal(), subaccount: [] },
      ledgers: [{ ic: stakeParams.neuron_params.neuron_ledger_canister }],
      sources: [],
      extractors: [],
      affiliate: [],
      temporary: false,
      billing_option: 0n,
      initial_billing_amount: [100_0000_0000n],
      temp_id: 0,
    };

    let creq: CreateRequest = {
      devefi_jes1_snsneuron: {
        init: {
          governance_canister:
            stakeParams.neuron_params.neuron_governance_canister,
        },
        variables: {
          dissolve_delay: stakeParams.neuron_params.dissolve_delay,
          dissolve_status: stakeParams.neuron_params.dissolve_status,
          followee: stakeParams.neuron_params.followee,
        },
      },
    };

    this.snsTestPylon.setPrincipal(this.me.getPrincipal());
    let resp = await this.snsTestPylon.icrc55_command({
      expire_at: [],
      request_id: [],
      controller: { owner: this.me.getPrincipal(), subaccount: [] },
      signature: [],
      commands: [{ create_node: [req, creq] }],
    });

    //@ts-ignore
    if (resp.ok.commands[0].create_node.err) {
      //@ts-ignore
      throw new Error(resp.ok.commands[0].create_node.err);
    }
    //@ts-ignore
    return resp.ok.commands[0].create_node.ok;
  }

  public async modifyNode(
    nodeId: number,
    updateDelaySeconds: [] | [SnsDissolveDelay],
    updateFollowee: [] | [SnsFollowee],
    updateDissolving: [] | [SnsDissolveStatus]
  ): Promise<BatchCommandResponse> {
    let modCustomReq: ModifyRequest = {
      devefi_jes1_snsneuron: {
        dissolve_delay: updateDelaySeconds,
        dissolve_status: updateDissolving,
        followee: updateFollowee,
      },
    };

    let modReq: ModifyNodeRequest = [
      nodeId,
      [
        {
          destinations: [],
          refund: [],
          sources: [],
          extractors: [],
          controllers: [[{ owner: this.me.getPrincipal(), subaccount: [] }]],
          active: [],
        },
      ],
      [modCustomReq],
    ];

    let resp = await this.snsTestPylon.icrc55_command({
      expire_at: [],
      request_id: [],
      controller: { owner: this.me.getPrincipal(), subaccount: [] },
      signature: [],
      commands: [{ modify_node: modReq }],
    });

    //@ts-ignore
    if (resp.ok.commands[0].modify_node.err) {
      //@ts-ignore
      throw new Error(resp.ok.commands[0].modify_node.err);
    }
    //@ts-ignore
    return resp.ok.commands[0].modify_node.ok;
  }

  public async deleteNode(nodeId: number) {
    let resp = await this.snsTestPylon.icrc55_command({
      expire_at: [],
      request_id: [],
      controller: { owner: this.me.getPrincipal(), subaccount: [] },
      signature: [],
      commands: [{ delete_node: nodeId }],
    });

    //@ts-ignore
    if (resp.ok.commands[0].delete_node.err) {
      //@ts-ignore
      throw new Error(resp.ok.commands[0].delete_node.err);
    }
    //@ts-ignore
    return resp.ok.commands[0].delete_node.ok;
  }

  public async sendIcrc({
    to,
    amount,
    icrcActor,
    sender,
  }: {
    to: Account;
    amount: bigint;
    icrcActor: Actor<ICRCLEDGER>;
    sender: Principal;
  }): Promise<TransferResult> {
    icrcActor.setPrincipal(sender);

    let txresp = await icrcActor.icrc1_transfer({
      from_subaccount: [],
      to: to,
      amount: amount,
      fee: [],
      memo: [],
      created_at_time: [],
    });

    if (!("Ok" in txresp)) {
      throw new Error("Transaction failed");
    }

    return txresp;
  }

  public async stakeNeuron(stakeParams: StakeNodeParams): Promise<NodeShared> {
    let node = await this.createNode(stakeParams);
    await this.advanceBlocksAndTimeMinutes(3);

    await this.sendIcrc({
      to: this.getNodeSourceAccount(node, 0),
      amount: stakeParams.stake_amount,
      icrcActor: stakeParams.ledger_actor,
      sender: this.me.getPrincipal(),
    });

    await this.advanceBlocksAndTimeMinutes(8);

    let refreshedNode = await this.getNode(node.id);
    return refreshedNode;
  }

  public async getNode(nodeId: NodeId): Promise<GetNodeResponse> {
    let resp = await this.snsTestPylon.icrc55_get_nodes([{ id: nodeId }]);
    if (resp[0][0] === undefined) throw new Error("Node not found");
    return resp[0][0];
  }

  public getNodeSourceAccount(node: NodeShared, port: number): Account {
    if (!node || node.sources.length === 0) {
      throw new Error("Invalid node or no sources found");
    }

    let endpoint = node.sources[port].endpoint;

    if ("ic" in endpoint) {
      return endpoint.ic.account;
    }

    throw new Error("Invalid endpoint type: 'ic' endpoint expected");
  }

  public async getSourceBalance(nodeId: NodeId): Promise<bigint> {
    let node = await this.getNode(nodeId);
    if (node === undefined) return 0n;

    return node.sources[0].balance;
  }

  public getNodeDestinationAccount(node: NodeShared): Account {
    if (!node || node.destinations.length === 0) {
      throw new Error("Invalid node or no sources found");
    }

    let endpoint = node.destinations[0].endpoint;

    if ("ic" in endpoint && endpoint.ic.account.length > 0) {
      return endpoint.ic.account[0];
    }

    throw new Error("Invalid endpoint type: 'ic' endpoint expected");
  }

  public async getMyBalances(icrcActor: Actor<ICRCLEDGER>) {
    let icrc = await icrcActor.icrc1_balance_of({
      owner: this.me.getPrincipal(),
      subaccount: [],
    });

    return { icrc_tokens: icrc };
  }

  public async getBillingBalances(icrcActor: Actor<ICRCLEDGER>) {
    let author = Principal.fromText(
      "jv4ws-fbili-a35rv-xd7a5-xwvxw-trink-oluun-g7bcp-oq5f6-35cba-vqe"
    );
    let platform = Principal.fromText("eqsml-lyaaa-aaaaq-aacdq-cai");

    // return other balances to check things out
    let authorBilling = await icrcActor.icrc1_balance_of({
      owner: author,
      subaccount: [],
    });

    let platformBilling = await icrcActor.icrc1_balance_of({
      owner: platform,
      subaccount: [],
    });

    return { author_billing: authorBilling, platform_billing: platformBilling };
  }
}
