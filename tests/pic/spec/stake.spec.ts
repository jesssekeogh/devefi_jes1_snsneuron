import {
  AMOUNT_TO_STAKE,
  EXPECTED_TRANSACTION_FEES,
  MOCK_FOLLOWEE_TO_SET,
  MOCK_FOLLOWEE_TO_SET_2,
} from "../setup/constants.ts";
import { Manager } from "../setup/manager.ts";
import { SetupSns } from "../setup/setupsns.ts";
import { NodeShared } from "../setup/sns_test_pylon/declarations/sns_test_pylon.did.js";
import { exampleSnsInitPayload } from "../setup/snsvers/sns_ver1.ts";

describe("Stake", () => {
  let manager: Manager;
  let node: NodeShared;
  let sns: SetupSns;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
    sns = await manager.createSns(exampleSnsInitPayload);
    node = await manager.stakeNeuron({
      stake_amount: AMOUNT_TO_STAKE,
      billing_actor: sns.getIcrcLedger(),
      ledger_actor: sns.getIcrcLedger(),
      neuron_params: {
        neuron_ledger_canister: sns.getSnsCanisters().ledger[0],
        dissolve_delay: { Default: null },
        followee: { FolloweeId: MOCK_FOLLOWEE_TO_SET },
        dissolve_status: { Locked: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should stake neuron", async () => {
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].id
    ).toBeDefined();
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBe(AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES);
  });

  it("should update dissolve delay", async () => {
    if (
      "DissolveDelaySeconds" in
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ) {
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
          .DissolveDelaySeconds
      ).toBe(
        node.custom[0].devefi_jes1_snsneuron.parameters_cache[0]
          .neuron_minimum_dissolve_delay_to_vote_seconds[0] + 60n // buffer
      );
    } else {
      fail("Expected 'DissolveDelaySeconds' in dissolve_state.");
    }

    const max_dissolve_delay =
      node.custom[0].devefi_jes1_snsneuron.parameters_cache[0]
        .max_dissolve_delay_seconds[0];

    await manager.modifyNode(
      node.id,
      [{ DelayDays: manager.convertSecondsToDays(max_dissolve_delay) + 1n }], // we always need a buffer to reach max, the code cleans it later
      [],
      []
    );

    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);
    if (
      "DissolveDelaySeconds" in
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ) {
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
          .DissolveDelaySeconds
      ).toBe(max_dissolve_delay);
    } else {
      fail("Expected 'DissolveDelaySeconds' in dissolve_state.");
    }
  });

  it("should update followee", async () => {
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

    // modify to a new followee and expect it to change

    await manager.modifyNode(
      node.id,
      [],
      [{ FolloweeId: MOCK_FOLLOWEE_TO_SET_2 }],
      []
    );
    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.variables.followee
    ).toStrictEqual({
      FolloweeId: MOCK_FOLLOWEE_TO_SET_2,
    });
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].topic_followees[0]
        .topic_id_to_followees
    ).toHaveLength(7);

    for (let followee of node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
      .topic_followees[0].topic_id_to_followees) {
      expect(followee[1].followees[0].neuron_id[0].id).toStrictEqual(
        MOCK_FOLLOWEE_TO_SET_2
      );
    }
  });

  it("should update dissolving", async () => {
    expect(
      node.custom[0].devefi_jes1_snsneuron.variables.dissolve_status
    ).toEqual({
      Locked: null,
    });

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ).toHaveProperty("DissolveDelaySeconds");

    await manager.modifyNode(node.id, [], [], [{ Dissolving: null }]);
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.variables.dissolve_status
    ).toEqual({
      Dissolving: null,
    });
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ).toHaveProperty("WhenDissolvedTimestampSeconds");

    const max_dissolve_delay =
      node.custom[0].devefi_jes1_snsneuron.parameters_cache[0]
        .max_dissolve_delay_seconds[0];

    await manager.modifyNode(
      node.id,
      [{ DelayDays: manager.convertSecondsToDays(max_dissolve_delay) + 1n }],
      [],
      [{ Locked: null }]
    );
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.variables.dissolve_status
    ).toEqual({
      Locked: null,
    });
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ).toHaveProperty("DissolveDelaySeconds");
  });

  it("should increase stake", async () => {
    let currentStake = AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES;
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBe(currentStake);

    let sends = 3n;
    for (let i = 0n; i < sends; i++) {
      await manager.sendIcrc({
        to: manager.getNodeSourceAccount(node, 0),
        amount: AMOUNT_TO_STAKE,
        icrcActor: sns.getIcrcLedger(),
        sender: manager.getMe(),
      });
      await manager.advanceBlocksAndTimeMinutes(1);
    }

    await manager.advanceBlocksAndTimeMinutes(5);
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
  });

  it("should disburse dissolved neuron", async () => {
    await manager.modifyNode(node.id, [], [], [{ Dissolving: null }]);
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ).toHaveProperty("WhenDissolvedTimestampSeconds");

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBeGreaterThan(0n);

    const max_dissolve_delay =
      node.custom[0].devefi_jes1_snsneuron.parameters_cache[0]
        .max_dissolve_delay_seconds[0];

    await manager.advanceTime(Number(max_dissolve_delay / 60n));
    await manager.advanceBlocks(100);

    await manager.advanceBlocksAndTimeDays(1);
    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBe(0n);
  });

  it("should re-use empty neuron", async () => {
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBe(0n);

    await manager.sendIcrc({
      to: manager.getNodeSourceAccount(node, 0),
      amount: AMOUNT_TO_STAKE,
      icrcActor: sns.getIcrcLedger(),
      sender: manager.getMe(),
    });

    await manager.advanceBlocksAndTimeMinutes(3);

    const max_dissolve_delay =
      node.custom[0].devefi_jes1_snsneuron.parameters_cache[0]
        .max_dissolve_delay_seconds[0];

    await manager.modifyNode(
      node.id,
      [{ DelayDays: manager.convertSecondsToDays(max_dissolve_delay) + 1n }], // we always need a buffer to reach max, the code cleans it later
      [],
      [{ Locked: null }]
    );

    await manager.advanceBlocksAndTimeMinutes(5);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBe(AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES);

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ).toHaveProperty("DissolveDelaySeconds");

    if (
      "DissolveDelaySeconds" in
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ) {
      expect(
        node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
          .DissolveDelaySeconds
      ).toBe(max_dissolve_delay);
    } else {
      fail("Expected 'DissolveDelaySeconds' in dissolve_state.");
    }
  });

  it("should delete node with an empty neuron", async () => {
    await manager.modifyNode(node.id, [], [], [{ Dissolving: null }]);
    await manager.advanceBlocksAndTimeMinutes(3);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0].dissolve_state[0]
    ).toHaveProperty("WhenDissolvedTimestampSeconds");

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBeGreaterThan(0n);

    const max_dissolve_delay =
      node.custom[0].devefi_jes1_snsneuron.parameters_cache[0]
        .max_dissolve_delay_seconds[0];

    await manager.advanceTime(Number(max_dissolve_delay / 60n));
    await manager.advanceBlocks(100);

    await manager.advanceBlocksAndTimeDays(1);
    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .cached_neuron_stake_e8s
    ).toBe(0n);

    await manager.deleteNode(node.id);
    await expect(manager.getNode(node.id)).rejects.toThrow();
  });
});
