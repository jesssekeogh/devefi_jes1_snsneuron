import { AMOUNT_TO_STAKE } from "../setup/constants.ts";
import { Manager } from "../setup/manager.ts";
import { SetupSns } from "../setup/setupsns.ts";
import { NodeShared } from "../setup/sns_test_pylon/declarations/sns_test_pylon.did.js";
import { SnsNeuron } from "../setup/snsneuron.ts";
import { exampleSnsInitPayload } from "../setup/snsvers/sns_ver1.ts";

describe.skip("Maturity", () => {
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

    node = await manager.stakeNeuron({
      stake_amount: AMOUNT_TO_STAKE,
      billing_actor: sns.getIcrcLedger(),
      ledger_actor: sns.getIcrcLedger(),
      neuron_params: {
        neuron_ledger_canister: sns.getSnsCanisters().ledger[0],
        neuron_governance_canister: sns.getSnsCanisters().governance[0],
        neuron_creator: { Unspecified: null },
        dissolve_delay: { Default: null },
        followee: { FolloweeId: snsNeuron.getNeuron().id[0].id },
        dissolve_status: { Locked: null },
      },
    });
  });

  afterAll(async () => {
    await manager.afterAll();
  });

  it("should accrue maturity", async () => {
    await snsNeuron.makeProposal();

    await manager.advanceTime(7200); // 5 days in mins
    await manager.advanceBlocks(10);

    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .maturity_e8s_equivalent
    ).toBeGreaterThan(0n);
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .disburse_maturity_in_progress.length
    ).toBe(0);
  });

  it("should spawn maturity", async () => {
    await manager.advanceBlocksAndTimeDays(3);
    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .maturity_e8s_equivalent
    ).toBe(0n);
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .disburse_maturity_in_progress.length
    ).toBeGreaterThan(0);
  });

  it("should claim maturity", async () => {
    let oldBalance = await manager.getMyBalances(sns.getIcrcLedger());

    await manager.advanceBlocksAndTimeDays(8);

    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .disburse_maturity_in_progress.length
    ).toBe(0);
    let newBalance = await manager.getMyBalances(sns.getIcrcLedger());
    expect(newBalance.icrc_tokens).toBeGreaterThan(oldBalance.icrc_tokens);
  });

  it("should spawn and claim maturity again", async () => {
    await snsNeuron.makeProposal();

    await manager.advanceBlocksAndTimeDays(8);

    node = await manager.getNode(node.id);

    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .disburse_maturity_in_progress.length
    ).toBeGreaterThan(0);

    let oldBalance = await manager.getMyBalances(sns.getIcrcLedger());

    await manager.advanceBlocksAndTimeDays(8);

    node = await manager.getNode(node.id);
    expect(
      node.custom[0].devefi_jes1_snsneuron.neuron_cache[0]
        .disburse_maturity_in_progress.length
    ).toBe(0);

    let newBalance = await manager.getMyBalances(sns.getIcrcLedger());
    expect(newBalance.icrc_tokens).toBeGreaterThan(oldBalance.icrc_tokens);
  });
});
