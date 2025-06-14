import {
  AMOUNT_TO_STAKE,
  EXPECTED_TRANSACTION_FEES,
  MOCK_FOLLOWEE_TO_SET,
} from "../setup/constants.ts";
import { Manager } from "../setup/manager.ts";
import { SetupSns } from "../setup/setupsns.ts";
import { NodeShared } from "../setup/sns_test_pylon/declarations/sns_test_pylon.did.js";
import { SnsNeuron } from "../setup/snsneuron.ts";
import { exampleSnsInitPayload } from "../setup/snsvers/sns_ver1.ts";
import { exampleSnsInitPayload2 } from "../setup/snsvers/sns_ver2.ts";

describe("Multiple", () => {
  let manager: Manager;
  let snsNeuron1: SnsNeuron;
  let snsNeuron2: SnsNeuron;
  let allNodes: Array<{
    version: string;
    stakeSns: SetupSns;
    node: NodeShared;
  }> = [];

  beforeAll(async () => {
    manager = await Manager.beforeAll();

    // Create both SNS versions as usual
    const sns1 = await manager.createSns(exampleSnsInitPayload);
    const sns2 = await manager.createSns(exampleSnsInitPayload2);

    snsNeuron1 = await SnsNeuron.create(
      sns1.getIcrcLedger(),
      sns1.getGovernance(),
      sns1.getSnsCanisters().governance[0],
      manager.getMe()
    );

    snsNeuron2 = await SnsNeuron.create(
      sns2.getIcrcLedger(),
      sns2.getGovernance(),
      sns2.getSnsCanisters().governance[0],
      manager.getMe()
    );

    const snsVersions = [
      {
        version: "v1",
        stakeSns: sns1,
        followee: snsNeuron1,
      },
      {
        version: "v2",
        stakeSns: sns2,
        followee: snsNeuron2,
      },
    ];

    const nodesToCreate = 2;

    for (let i = 0; i < nodesToCreate; i++) {
      for (let snsData of snsVersions) {
        const node = await manager.stakeNeuron({
          stake_amount: AMOUNT_TO_STAKE,
          billing_actor: sns1.getIcrcLedger(), // billing actor is the same for both versions
          // version-specific ledger actor:
          ledger_actor: snsData.stakeSns.getIcrcLedger(),
          neuron_params: {
            neuron_ledger_canister:
              snsData.stakeSns.getSnsCanisters().ledger[0],
            dissolve_delay: { Default: null },
            followee: {
              FolloweeId: MOCK_FOLLOWEE_TO_SET,
            },
            dissolve_status: { Locked: null },
          },
        });

        // Store it along with its "version" label
        allNodes.push({
          version: snsData.version,
          stakeSns: snsData.stakeSns,
          node,
        });
      }
    }
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should stake multiple neurons in different SNS governance canisters", async () => {
    for (let { version, stakeSns, node } of allNodes) {
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].id
      ).toBeDefined();
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
          .cached_neuron_stake_e8s
      ).toBe(AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES);
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].topic_followees[0]
          .topic_id_to_followees
      ).toHaveLength(7);

      for (let followee of node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .topic_followees[0].topic_id_to_followees) {
        expect(followee[1].followees[0].neuron_id[0].id).toStrictEqual(
          MOCK_FOLLOWEE_TO_SET
        );
      }
    }
  });

  it("should update multiple SNS neurons", async () => {
    for (let { version, stakeSns, node } of allNodes) {
      await manager.modifyNode(
        node.id,
        [],
        [
          {
            FolloweeId:
              version === "v1"
                ? snsNeuron1.getNeuron().id[0].id
                : snsNeuron2.getNeuron().id[0].id,
          },
        ],
        []
      );
      await manager.advanceBlocksAndTimeMinutes(3);
    }

    await manager.advanceBlocksAndTimeMinutes(1);

    for (let { version, stakeSns, node } of allNodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].topic_followees[0]
          .topic_id_to_followees
      ).toHaveLength(7);

      for (let followee of node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .topic_followees[0].topic_id_to_followees) {
        expect(followee[1].followees[0].neuron_id[0].id).toStrictEqual(
          version === "v1"
            ? snsNeuron1.getNeuron().id[0].id
            : snsNeuron2.getNeuron().id[0].id
        );
      }
    }
  });

  it("should increase multiple SNS neurons stake", async () => {
    let currentStake = AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES;
    let sends = 3n;

    for (let { version, stakeSns, node } of allNodes) {
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
          .cached_neuron_stake_e8s
      ).toBe(currentStake);

      for (let i = 0n; i < sends; i++) {
        await manager.sendIcrc({
          to: manager.getNodeSourceAccount(node, 0),
          amount: AMOUNT_TO_STAKE,
          icrcActor: stakeSns.getIcrcLedger(),
          sender: manager.getMe(),
        });
        await manager.advanceBlocksAndTimeMinutes(1);
      }
    }

    await manager.advanceBlocksAndTimeMinutes(5);

    for (let { version, stakeSns, node } of allNodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom[0].devefi_jes1_snsneuron.internals.refresh_idx
      ).toHaveLength(0);
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
          .cached_neuron_stake_e8s
      ).toBe(
        currentStake + (AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES) * sends
      );
    }
  });

  it("should spawn maturity in multiple SNS neurons", async () => {
    await snsNeuron1.makeProposal();
    await snsNeuron2.makeProposal();

    await manager.advanceBlocksAndTimeDays(8);
    await manager.advanceBlocksAndTimeHours(3);

    for (let { version, stakeSns, node } of allNodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
          .maturity_e8s_equivalent
      ).toBe(0n);
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
          .disburse_maturity_in_progress.length
      ).toBeGreaterThan(0);
    }
  });

  it("should claim maturity from multiple neurons", async () => {
    let oldBalance1;
    let oldBalance2;
    for (let { version, stakeSns, node } of allNodes) {
      if (version === "v1") {
        oldBalance1 = await manager.getMyBalances(stakeSns.getIcrcLedger());
      } else {
        oldBalance2 = await manager.getMyBalances(stakeSns.getIcrcLedger());
      }
    }

    await manager.advanceBlocksAndTimeDays(8);
    await manager.advanceBlocksAndTimeHours(3);
    
    for (let { version, stakeSns, node } of allNodes) {
      node = await manager.getNode(node.id);
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
          .disburse_maturity_in_progress.length
      ).toBe(0);
    }

    let newBalance1;
    let newBalance2;
    for (let { version, stakeSns, node } of allNodes) {
      if (version === "v1") {
        newBalance1 = await manager.getMyBalances(stakeSns.getIcrcLedger());
      } else {
        newBalance2 = await manager.getMyBalances(stakeSns.getIcrcLedger());
      }
    }
    expect(newBalance1.icrc_tokens).toBeGreaterThan(oldBalance1.icrc_tokens);
    expect(newBalance2.icrc_tokens).toBeGreaterThan(oldBalance2.icrc_tokens);
  });
});
