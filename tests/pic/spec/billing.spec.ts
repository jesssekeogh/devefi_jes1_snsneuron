import { AMOUNT_TO_STAKE, MOCK_FOLLOWEE_TO_SET } from "../setup/constants.ts";
import { Manager } from "../setup/manager.ts";
import { SetupSns } from "../setup/setupsns.ts";
import { NodeShared } from "../setup/sns_test_pylon/declarations/sns_test_pylon.did.js";
import { exampleSnsInitPayload } from "../setup/snsvers/sns_ver1.ts";

describe("Billing", () => {
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

  it("should add fees to billing accounts", async () => {
    let b = await manager.getBillingBalances(sns.getIcrcLedger());

    expect(b.author_billing).toBe(0n);
    expect(b.platform_billing).toBe(0n);

    await manager.advanceBlocksAndTimeDays(3);
    await manager.advanceBlocksAndTimeMinutes(3);
    
    let b2 = await manager.getBillingBalances(sns.getIcrcLedger());

    expect(b2.author_billing).toBeGreaterThan(0n);
    expect(b2.platform_billing).toBeGreaterThan(0n);
  });
});
