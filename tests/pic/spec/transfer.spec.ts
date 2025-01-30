import { Manager } from "../setup/manager.ts";
import { SetupSns } from "../setup/setupsns.ts";
import { NodeShared } from "../setup/sns_test_pylon/declarations/sns_test_pylon.did.js";
import { SnsNeuron } from "../setup/snsneuron.ts";
import { exampleSnsInitPayload } from "../setup/snsvers/sns_ver1.ts";

describe("Transfer", () => {
  let manager: Manager;
  let node: NodeShared;
  let sns: SetupSns;
  let snsNeuron: SnsNeuron;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    sns = await manager.createSns(exampleSnsInitPayload);
    snsNeuron = await SnsNeuron.create(
      sns.getIcrcLedger(),
      sns.getGovernance(),
      sns.getSnsCanisters().governance[0],
      manager.getMe()
    );

    node = await manager.createNode({
      stake_amount: 0n,
      billing_actor: sns.getIcrcLedger(),
      ledger_actor: sns.getIcrcLedger(),
      neuron_params: {
        neuron_ledger_canister: sns.getSnsCanisters().ledger[0],
        neuron_governance_canister: sns.getSnsCanisters().governance[0],
        neuron_creator: { NeuronCreator: manager.getMe() },
        dissolve_delay: { Unspecified: null },
        followee: { Unspecified: null },
        dissolve_status: { Unspecified: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should transfer split neuron to vector", async () => {
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
    ).toBeUndefined();

    await snsNeuron.splitNeuron(
      node.custom[0].devefi_jes1_snsneuron.init.neuron_nonce,
      8_0001_0000n
    );
    await manager.advanceBlocksAndTimeDays(3);

    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBe(8_0000_0000n);
  });

  it("should not change vector configs without permission", async () => {
    await manager.modifyNode(
      node.id,
      [],
      [{ FolloweeId: snsNeuron.getNeuron().id[0].id }],
      []
    );

    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].followees
    ).toHaveLength(0);
  });

  it("should change vector configs with permission", async () => {
    await snsNeuron.addPermission(4, manager.getSnsTestPylonCanisterId());

    await manager.advanceBlocksAndTimeDays(3);
    node = await manager.getNode(node.id);

    console.log(node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].permissions);

    expect(
      node.custom[0].devefi_jes1_snsneuron.variables.followee
    ).toStrictEqual({
      FolloweeId: snsNeuron.getNeuron().id[0].id,
    });
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].followees
    ).toHaveLength(4);

    for (let followee of node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
      .followees) {
      expect(followee[1].followees[0].id).toStrictEqual(
        snsNeuron.getNeuron().id[0].id
      );
    }
  });

});
