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

export const NNS_STATE_PATH = resolve(__dirname, "..", "nns_state");

export const NNS_SUBNET_ID =
  "ikekp-awh3l-6wik7-dknt2-3hnte-pyg6b-qahf2-yamqx-jsdjs-ahvyd-uqe";

export const EXPECTED_STAKE: bigint = 20_0000_0000n;

export const ICP_TRANSACTION_FEE: bigint = 10_000n;

export const EXPECTED_TRANSACTION_FEES: bigint = ICP_TRANSACTION_FEE * 2n;

export const AMOUNT_TO_STAKE: bigint =
  EXPECTED_STAKE + EXPECTED_TRANSACTION_FEES;

export const MOCK_FOLLOWEE_TO_SET: Uint8Array = Uint8Array.from(
  "824f1a1df2652fb26c0fe1c03ab5ce69f2561570fb4d042cdc32dcb4604a4f03"
    .match(/.{1,2}/g)
    .map((byte) => parseInt(byte, 16))
);

export const MOCK_FOLLOWEE_TO_SET_2: Uint8Array = Uint8Array.from(
  "a8a84b57c3faef493ed5399edbbc46663aa78740477f7c2d8bfacd0f339292ad"
    .match(/.{1,2}/g)
    .map((byte) => parseInt(byte, 16))
);
