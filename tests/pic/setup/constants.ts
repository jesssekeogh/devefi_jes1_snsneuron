import { Principal } from "@dfinity/principal";
import { resolve } from "node:path";

export const SNSW_CANISTER_ID = Principal.fromText(
  "qaa6y-5yaaa-aaaaa-aaafa-cai"
);

export const GOVERNANCE_CANISTER_ID = Principal.fromText(
  "rrkah-fqaaa-aaaaa-aaaaq-cai"
);

export const NNS_ROOT_CANISTER_ID = Principal.fromText(
  "r7inp-6aaaa-aaaaa-aaabq-cai"
);

export const NNS_STATE_PATH = resolve(
  __dirname,
  "..",
  "nns_state",
  "node-100",
  "state"
);

export const NNS_SUBNET_ID =
  "mawzk-pspoy-qnbwv-qsdnd-qg6qx-x6gja-lvszb-bvzh6-oxohh-6g45e-sqe";
