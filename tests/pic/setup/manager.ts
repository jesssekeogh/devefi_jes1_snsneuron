import { _SERVICE as SNSTESTPYLON } from "./sns_test_pylon/declarations/sns_test_pylon.did.js";
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

export class Manager {
  private readonly me: ReturnType<typeof createIdentity>;
  private readonly pic: PocketIc;
  private readonly snsTestPylon: Actor<SNSTESTPYLON>;
  private readonly snswActor: Actor<SNSW>;

  constructor(
    pic: PocketIc,
    me: ReturnType<typeof createIdentity>,
    snsTestPylon: Actor<SNSTESTPYLON>,
    snswActor: Actor<SNSW>
  ) {
    this.pic = pic;
    this.me = me;
    this.snsTestPylon = snsTestPylon;
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

    return new Manager(pic, identity, pylonFixture.actor, snswActor);
  }

  public async afterAll(): Promise<void> {
    await this.pic.tearDown();
  }

  public getMe(): Principal {
    return this.me.getPrincipal();
  }

  public getSnsTestPylon(): Actor<SNSTESTPYLON> {
    return this.snsTestPylon;
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

  public async createSns(snsPayload: SnsInitPayload): Promise<SetupSns> {
    let sns = await SetupSns.create(this.pic, this.snswActor, snsPayload);

    return sns;
  }
}
