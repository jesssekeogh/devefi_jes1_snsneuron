import { resolve } from "node:path";
import { PocketIc } from "@hadronous/pic";
import { IDL } from "@dfinity/candid";
import {
  _SERVICE as SNSTESTPYLON,
  idlFactory,
  init as PylonInit,
} from "./declarations/sns_test_pylon.did.js";

const WASM_PATH = resolve(__dirname, "../sns_test_pylon/sns_test_pylon.wasm.gz");

export async function SnsTestPylon(pic: PocketIc) {
  const subnets = pic.getApplicationSubnets();

  const fixture = await pic.setupCanister<SNSTESTPYLON>({
    idlFactory,
    wasm: WASM_PATH,
    arg: IDL.encode(PylonInit({ IDL }), []),
    targetSubnetId: subnets[0].id,
  });

  return fixture;
}

export default SnsTestPylon;