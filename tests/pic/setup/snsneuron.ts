import { _SERVICE as ICRCLEDGER, Account } from "./nns/icrcledger.js";
import {
  _SERVICE as SNSGOVERNANCE,
  Neuron,
  ManageNeuronResponse,
} from "./nns/snsgovernance.js";
import { Principal } from "@dfinity/principal";
import { Actor } from "@hadronous/pic";
import { createHash, randomBytes } from "node:crypto";

// needed for making proposals to get maturity and splitting to test transferring to a vector

export class SnsNeuron {
  private readonly snsGovActor: Actor<SNSGOVERNANCE>;
  private readonly snsNeuron: Neuron;
  private readonly controller: Principal;

  constructor(
    snsGovActor: Actor<SNSGOVERNANCE>,
    snsNeuron: Neuron,
    controller: Principal
  ) {
    this.snsGovActor = snsGovActor;
    this.snsNeuron = snsNeuron;
    this.controller = controller;
  }

  public static async create(
    icrcActor: Actor<ICRCLEDGER>,
    snsGovActor: Actor<SNSGOVERNANCE>,
    snsGovCanisterId: Principal,
    controller: Principal
  ): Promise<SnsNeuron> {
    let nonce = this.generateNonce();

    let neuronSubaccount = this.getNeuronSubaccount(controller, nonce);

    let to: Account = {
      owner: snsGovCanisterId,
      subaccount: [neuronSubaccount],
    };

    await icrcActor.icrc1_transfer({
      from_subaccount: [],
      to: to,
      amount: 10_0000_0000n,
      fee: [],
      memo: [],
      created_at_time: [],
    });

    const { command }: ManageNeuronResponse = await snsGovActor.manage_neuron({
      subaccount: neuronSubaccount,
      command: [
        {
          ClaimOrRefresh: {
            by: [
              {
                MemoAndController: {
                  controller: [controller],
                  memo: nonce,
                },
              },
            ],
          },
        },
      ],
    });

    if (
      !("ClaimOrRefresh" in command[0]) ||
      !("refreshed_neuron_id" in command[0].ClaimOrRefresh)
    ) {
      throw new Error("Failed to create neuron");
    }

    const { id } = command[0].ClaimOrRefresh.refreshed_neuron_id[0];

    snsGovActor.setPrincipal(controller);

    const dissolveDelayResponse = await snsGovActor.manage_neuron({
      subaccount: id,
      command: [
        {
          Configure: {
            operation: [
              {
                IncreaseDissolveDelay: {
                  additional_dissolve_delay_seconds: 60 * 60 * 24 * 7 * 52 * 1, // 1 year
                },
              },
            ],
          },
        },
      ],
    });

    const dissolveDelayResult = dissolveDelayResponse.command[0];
    if (!dissolveDelayResult) {
      throw new Error("Failed to set dissolve delay");
    }
    if ("Error" in dissolveDelayResult) {
      throw new Error(
        `${dissolveDelayResult.Error.error_type}: ${dissolveDelayResult.Error.error_message}`
      );
    }

    let { result } = await snsGovActor.get_neuron({
      neuron_id: [{ id: neuronSubaccount }],
    });

    if ("Error" in result[0]) {
      throw new Error(result[0].Error.error_message);
    }

    return new SnsNeuron(snsGovActor, result[0].Neuron, controller);
  }

  private static generateNonce(): bigint {
    return randomBytes(8).readBigUint64BE();
  }

  private static bigEndianU64(value: bigint): Uint8Array {
    const buffer = Buffer.alloc(8);
    buffer.writeBigUInt64BE(value);
    return buffer;
  }

  private static getNeuronSubaccount(
    controller: Principal,
    nonce: bigint
  ): Uint8Array {
    const hasher = createHash("sha256");
    hasher.update(new Uint8Array([0x0c]));
    hasher.update(Buffer.from("neuron-stake"));
    hasher.update(controller.toUint8Array());
    hasher.update(this.bigEndianU64(nonce));

    return hasher.digest();
  }

  getNeuronController(): Principal {
    return this.controller;
  }

  public getNeuron(): Neuron {
    return this.snsNeuron;
  }

  public async makeProposal(): Promise<bigint> {
    const { command }: ManageNeuronResponse =
      await this.snsGovActor.manage_neuron({
        subaccount: this.snsNeuron.id[0].id,
        command: [
          {
            MakeProposal: {
              url: "",
              title: "Oscar",
              summary: "Golden Labrador Retriever",
              action: [
                {
                  Motion: { motion_text: "Good Boy?" },
                },
              ],
            },
          },
        ],
      });

    if (
      !("MakeProposal" in command[0]) ||
      !("proposal_id" in command[0].MakeProposal)
    ) {
      throw new Error("Failed to make proposal");
    }

    const { id } = command[0].MakeProposal.proposal_id[0];

    return id;
  }
}
