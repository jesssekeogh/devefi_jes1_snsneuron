import {
  _SERVICE as ICRCLEDGER,
  idlFactory as icrcIdlFactory,
} from "./nns/icrcledger";
import {
  _SERVICE as SNSGOVERNANCE,
  idlFactory as snsGovIdlFactory,
} from "./nns/snsgovernance";
import { _SERVICE as SNSW, SnsInitPayload, SnsCanisterIds } from "./nns/snsw";
import { _SERVICE as SNSTESTPYLON } from "./sns_test_pylon/declarations/sns_test_pylon.did.js";
import { Actor, PocketIc } from "@hadronous/pic";

export class SetupSns {
  private readonly icrcActor: Actor<ICRCLEDGER>;
  private readonly snsGovActor: Actor<SNSGOVERNANCE>;
  private readonly canisterIds: SnsCanisterIds;

  constructor(
    icrcActor: Actor<ICRCLEDGER>,
    snsGovActor: Actor<SNSGOVERNANCE>,
    canisterIds: SnsCanisterIds
  ) {
    this.icrcActor = icrcActor;
    this.snsGovActor = snsGovActor;
    this.canisterIds = canisterIds;
  }

  public static async create(
    pic: PocketIc,
    snswActor: Actor<SNSW>,
    snsPayload: SnsInitPayload,
    snsTestPylon: Actor<SNSTESTPYLON>
  ): Promise<SetupSns> {
    // spawn an SNS
    let res = await snswActor.deploy_new_sns({
      sns_init_payload: [snsPayload],
    });

    // setup icp ledger
    let icrcActor = pic.createActor<ICRCLEDGER>(
      icrcIdlFactory,
      res.canisters[0].ledger[0]
    );

    // setup gov
    let govActor = pic.createActor<SNSGOVERNANCE>(
      snsGovIdlFactory,
      res.canisters[0].governance[0]
    );

    // intialise SNS mode
    govActor.setPrincipal(res.canisters[0].swap[0]);
    await govActor.set_mode({ mode: 1 });

    // add sns ledger to supported ledgers
    await snsTestPylon.add_supported_ledger(res.canisters[0].ledger[0], {
      icrc: null,
    });

    return new SetupSns(icrcActor, govActor, res.canisters[0]);
  }

  public getSnsCanisters(): SnsCanisterIds {
    // for (const [key, value] of Object.entries(this.canisterIds)) {
    //   console.log(`${key}: ${value}`);
    // }
    return this.canisterIds;
  }

  public getGovernance(): Actor<SNSGOVERNANCE> {
    return this.snsGovActor;
  }

  public getIcrcLedger(): Actor<ICRCLEDGER> {
    return this.icrcActor;
  }
}
