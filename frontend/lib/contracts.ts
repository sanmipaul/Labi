export const IntentRegistryABI = [
  {
    "type": "function",
    "name": "createFlow",
    "inputs": [
      { "name": "triggerType", "type": "uint8", "internalType": "uint8" },
      { "name": "actionType", "type": "uint8", "internalType": "uint8" },
      { "name": "triggerValue", "type": "uint256", "internalType": "uint256" },
      { "name": "triggerData", "type": "bytes", "internalType": "bytes" },
      { "name": "conditionData", "type": "bytes", "internalType": "bytes" },
      { "name": "actionData", "type": "bytes", "internalType": "bytes" },
      { "name": "dstEid", "type": "uint32", "internalType": "uint32" }
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
          { "name": "actionType", "type": "uint8", "internalType": "uint8" },
          { "name": "triggerValue", "type": "uint256", "internalType": "uint256" },
          { "name": "triggerData", "type": "bytes", "internalType": "bytes" },
          { "name": "conditionData", "type": "bytes", "internalType": "bytes" },
          { "name": "actionData", "type": "bytes", "internalType": "bytes" },
          { "name": "dstEid", "type": "uint32", "internalType": "uint32" },
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

export const IntentVaultABI = [
  {
    "type": "function",
    "name": "execute",
    "inputs": [
      { "name": "dest", "type": "address", "internalType": "address" },
      { "name": "value", "type": "uint256", "internalType": "uint256" },
      { "name": "func", "type": "bytes", "internalType": "bytes" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "executeBatch",
    "inputs": [
      { "name": "dest", "type": "address[]", "internalType": "address[]" },
      { "name": "value", "type": "uint256[]", "internalType": "uint256[]" },
      { "name": "func", "type": "bytes[]", "internalType": "bytes[]" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  }
] as const;

export const IntentVaultAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"; // Local Anvil Deployment Address

export const FlowExecutorABI = [
  {
    "type": "function",
    "name": "executeFlow",
    "inputs": [{ "name": "flowId", "type": "uint256", "internalType": "uint256" }],
    "outputs": [{ "name": "", "type": "bool", "internalType": "bool" }],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "canExecuteFlow",
    "inputs": [{ "name": "flowId", "type": "uint256", "internalType": "uint256" }],
    "outputs": [
      { "name": "", "type": "bool", "internalType": "bool" },
      { "name": "", "type": "string", "internalType": "string" }
    ],
    "stateMutability": "view"
  }
] as const;

export const FlowExecutorAddress = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"; // Local Anvil Deployment Address
