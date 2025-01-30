# DeVeFi SNS Neuron Vector
The DeVeFi SNS Neuron Vector is a module that can be integrated into pylons running the DeVeFi framework. This package operates within the context of a pylon system and the ICRC-55 standard. Modules within the DeVeFi framework follow the naming convention: `devefi` _ `<author>` _ `<module>`.

Note: This README assumes familiarity with ICP, the Service Nervous System (SNS), and neurons. Not all neuron concepts are explained in detail.

This module is an SNS neuron version of the [ICP Neuron Vector](https://github.com/jesssekeogh/devefi_jes1_icpneuron).

## Create SNS Neuron Vectors

This module integrates with pylons—canisters running the DeVeFi framework and governed by SNS DAOs on the ICP network—enabling users to create instances of SNS neuron vectors. To create the vector, a minimum creation fee is required, charged by the pylon. For example, the Neutrinite DAO pylons may charge a creation fee of 0.5 NTN, which is stored in the vector's billing account. By default, each vector includes configurable options such as destinations, sources, billing, and refund settings, among other features. 

Alongside these standard vector configurations, **the SNS neuron vector enables the pylon to stake neurons on behalf of vector owners while granting them control over the neuron.** The pylon achieves this by making calls to the user inputted SNS governance canister. To stake an SNS neuron the pylon must be tracking that SNS's ledger, use the `icrc55_get_pylon_meta` endpoint to see which ledgers are supported.

## Vector Source Accounts

When you create an SNS neuron vector, you receive two non-configurable source accounts (one is hidden):

**"Stake" source** 

This ICRC-1 account accepts SNS tokens. Once you reach the SNS minimum stake threshold, it automatically forwards the tokens to a newly created neuron subaccount owned by your vector. The module then stakes a new neuron on your behalf and stores its data in your vector. You can increase your stake by sending any amount above the SNS transaction fee to the vector's "Stake" source again.

**"_Maturity" source**

This hidden ICRC-1 account is used internally to forward your SNS maturity to your destination account. Any maturity claimed from disbursing maturity is routed here first before being forwarded to your destination.

## Vector Destination Accounts

When you create an SNS neuron vector, you are provided with two configurable destination accounts, which can be updated at any time. Both destinations can be external accounts or other vectors:

**"Maturity" destination**

The ICRC-1 account where your claimed SNS tokens maturity rewards are sent.

**"Disburse" destination**

The ICRC-1 account that will receive the SNS tokens staked in your main neuron when it is dissolved.

**Configure your neuron**

The neuron can be configured by the vector controller, allowing you to maintain voting power and earn rewards. The available configurations are:

```javascript
`init`: {
    'governance_canister': Principal,
},
'variables': {
    'dissolve_delay': { 'Default': null } | { 'DelayDays': bigint },
    'dissolve_status': { 'Locked': null } | { 'Dissolving': null },
    'followee': { 'Unspecified': null } | { 'FolloweeId': bigint },
},
```

- `dissolve_delay`: Setting this to `Default` locks the neuron for the minimum period required to earn maturity for that particular SNS. You can specify a custom duration using `DelayDays`. If you set `DelayDays` below the minimum, it defaults to 6 months; if above the maximum, it defaults to the maximum. You can increase the `dissolve_delay` later (by at least 1 week) if the neuron is in the `Locked` state.

- `dissolve_status`: Switches your neuron's state between `Locked` and `Dissolving`. The neuron can only be disbursed if it's set to `Dissolving` and the dissolve delay has elapsed. The `dissolve_delay` can only be increased when the neuron is in the `Locked` state.

- `followee`: Determines which neuron your main neuron follows for voting on SNS proposals. It follows the specified neuron on all topics and critical topics. An `Unspecified` option is provided for not setting any followee, but it's recommended to select a specific `FolloweeId` (an SNS neuron ID) of your choice.

## Maturity Automation

SNS neurons allow you to spawn maturity once you have enough to cover the SNS transaction fee. The spawned maturity is tracked in the neuron’s metadata (note that this differs from ICP neurons, which spawn maturity into new neurons). After seven days, the spawned maturity is transferred to your designated maturity destination account. This process is entirely automatic—you can create and configure your neuron and watch as SNS tokens are sent to your destination account once enough maturity has accumulated to spawn. The more SNS tokens you stake, the faster you accrue maturity and SNS rewards are sent to the destination.

## Billing

To cover operational costs and reward the pylon, author, platform, and affiliates, the module and pylon charge a fee.

- 0.05 NTN tokens per day

Users must ensure their billing account maintains a sufficient balance to cover the fee well into the future. Insufficient funds may result in the vector freezing and potential deletion.

## Use Cases

The SNS neuron vector offers an easy-to-configure and automated neuron staking experience, simplifying the process for DAOs, organizations, and teams to stake neurons on the SNS without manual configurations, or spawning via a UI. Maturity rewards are automatically sent to your chosen destination account. The neurons stake can also be easily increased by sending additional SNS tokens to the vectors stake source account.

Additional use cases include trading systems that stake SNS and use the maturity rewards to purchase specific tokens. The SNS neuron vector can also interact with the broader ecosystem of vectors and integrate with throttle, splitting and liquidity vectors. The possibilities are extensive and surpass what is achievable with simple canister staking or UI-based staking.

## Running the Tests

This repository includes a compressed copy of the `nns_state`, which is decompressed during the npm install process via the postinstall script. The script uses command `tar -xvf ./state/nns_state.tar.xz -C ./` to extract the file. The tests use multiple canisters along with the module to perform operations such as creating nodes, staking neurons, spawning maturity and simulating the passage of significant time. As a result, the tests may take a while to complete.

The `maxWorkers` option in `jest.config.ts` is set to `1`. If your computer has sufficient resources, you can remove this restriction to run the tests in parallel.

These instructions have been tested on macOS. Ensure that the necessary CLI tools (e.g., git, npm) are installed before proceeding.

```bash
# clone the repo
git clone https://github.com/jesssekeogh/devefi_jes1_snsneuron.git

# change directory
cd devefi_jes1_snsneuron/tests/pic

# install the required packages
npm install

# run the tests
npx jest
```

## License

*To be decided*