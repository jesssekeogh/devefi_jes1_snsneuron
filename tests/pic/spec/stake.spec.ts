import { Manager } from "../setup/manager.ts";
import { NodeShared } from "../setup/sns_test_pylon/declarations/sns_test_pylon.did.js";

describe("Stake", () => {
  let manager: Manager;
  let node: NodeShared;

  beforeAll(async () => {
    manager = await Manager.beforeAll();
  });
  
  afterAll(async () => {
    await manager.afterAll();
  });

  it("should stake neuron", async () => {
    // expect(
    //   node.custom[0].devefi_jes1_icpneuron.cache.neuron_id[0]
    // ).toBeDefined();
    // expect(
    //   node.custom[0].devefi_jes1_icpneuron.cache.cached_neuron_stake_e8s[0]
    // ).toBe(AMOUNT_TO_STAKE - EXPECTED_TRANSACTION_FEES);
  });
});
