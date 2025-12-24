export const IntentRegistryABI = [
  {
    "type": "function",
    "name": "createFlow",
    "inputs": [
      { "name": "triggerType", "type": "uint8", "internalType": "uint8" },
      { "name": "triggerValue", "type": "uint256", "internalType": "uint256" },
      { "name": "triggerData", "type": "bytes", "internalType": "bytes" },
      { "name": "conditionData", "type": "bytes", "internalType": "bytes" },
      { "name": "actionData", "type": "bytes", "internalType": "bytes" }
    ],
    "outputs": [{ "name": "", "type": "uint256", "internalType": "uint256" }],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getFlow",
    "inputs": [{ "name": "flowId", "type": "uint256", "internalType": "uint256" }],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct IIntentRegistry.IntentFlow",
        "components": [
          { "name": "id", "type": "uint256", "internalType": "uint256" },
          { "name": "user", "type": "address", "internalType": "address" },
          { "name": "triggerType", "type": "uint8", "internalType": "uint8" },
          { "name": "triggerValue", "type": "uint256", "internalType": "uint256" },
          { "name": "triggerData", "type": "bytes", "internalType": "bytes" },
          { "name": "conditionData", "type": "bytes", "internalType": "bytes" },
          { "name": "actionData", "type": "bytes", "internalType": "bytes" },
          { "name": "active", "type": "bool", "internalType": "bool" },
          { "name": "lastExecutedAt", "type": "uint256", "internalType": "uint256" },
          { "name": "executionCount", "type": "uint256", "internalType": "uint256" }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getUserFlows",
    "inputs": [{ "name": "user", "type": "address", "internalType": "address" }],
    "outputs": [{ "name": "", "type": "uint256[]", "internalType": "uint256[]" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "updateFlowStatus",
    "inputs": [
      { "name": "flowId", "type": "uint256", "internalType": "uint256" },
      { "name": "active", "type": "bool", "internalType": "bool" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "FlowCreated",
    "inputs": [
      { "name": "flowId", "type": "uint256", "indexed": true, "internalType": "uint256" },
      { "name": "user", "type": "address", "indexed": true, "internalType": "address" },
      { "name": "triggerType", "type": "uint8", "indexed": false, "internalType": "uint8" },
      { "name": "triggerValue", "type": "uint256", "indexed": false, "internalType": "uint256" }
    ],
    "anonymous": false
  }
] as const;

export const IntentRegistryAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Local Anvil Deployment Address
